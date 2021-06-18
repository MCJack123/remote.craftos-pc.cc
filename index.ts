import express from "express";
import WebSocket from "ws";
import fs from "fs/promises";
import {readFileSync} from "fs";
import ejs from "ejs";
import http from "http";
import https from "https";
import net from "net";
import pmx from "@pm2/io";
import { collectDefaultMetrics, register, Gauge } from "prom-client";
import { ip, port, isSecure } from "./config.json";

var crcTable: [number];

function makeCRCTable() {
    let c;
    let crcTable = [];
    for (let n = 0; n < 256; n++) {
        c = n;
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
        crcTable[n] = c;
    }
    return crcTable;
}

function crc32(str: string) {
    crcTable = crcTable || makeCRCTable();
    let crc = 0 ^ (-1);
    for (let i = 0; i < str.length; i++) {
        crc = (crc >>> 8) ^ crcTable[(crc ^ str.charCodeAt(i)) & 0xFF];
    }
    return (crc ^ (-1)) >>> 0;
};

let connectionPools: {[key: string]: WebSocket[]} = {};
let connectionPoolOpen: {[key: string]: number} = {};

const app = express();
const serverURL = `ws${isSecure ? "s" : ""}://${ip}:${port}/`;

let serverFile: string;
let rawtermFile: string;
let indexFile: string;
fs.readFile("server.lua", {encoding: "utf8"}).then(data => serverFile = data);
fs.readFile("rawterm.lua", {encoding: "utf8"}).then(data => rawtermFile = data);
fs.readFile("index.ejs", {encoding: "utf8"}).then(data => indexFile = data);
let key: Buffer | undefined, cert: Buffer | undefined;
if (isSecure) {
    key = readFileSync(`/etc/letsencrypt/live/remote.craftos-pc.cc/privkey.pem`);
    cert = readFileSync(`/etc/letsencrypt/live/remote.craftos-pc.cc/fullchain.pem`);
}

collectDefaultMetrics();
let connectionCounter = new Gauge({name: "http_active_connections", help: "Active Connections"});
let pipeCounter = new Gauge({name: "http_active_pipes", help: "Active Pipes"});

let awaitingRestart = false;
let pipeCount = 0;

pmx.action("schedule-restart", (reply: (res: any) => void) => {
    if (pipeCount === 0) {
        reply("Exiting NOW!");
        process.exit(0);
    } else {
        awaitingRestart = true;
        reply("Restart scheduled - waiting for all pipes to close.");
    }
});

pmx.action("send-message", (param: string, reply: (res: any) => void) => {
    if (typeof param === "function") {
        (param as (res: any) => void)("Missing parameter");
        return;
    }
    const buf = Buffer.alloc(27 + param.length);
    buf.fill(0);
    buf[0] = 5;
    buf[2] = 0x40;
    buf.write("Message from server", 6);
    buf.write(param, 26);
    const b64 = buf.toString("base64");
    // Send one packet with binary encoding and one packet without to make sure both get the packet
    // (We can't tell what the connections are using from here)
    const packet = "!CPC" + ("000" + b64.length.toString(16)).slice(-4) + b64 + ("0000000" + crc32(b64).toString(16)).slice(-8) + "\n";
    const bpacket = "!CPC" + ("000" + b64.length.toString(16)).slice(-4) + b64 + ("0000000" + crc32(buf.toString("binary")).toString(16)).slice(-8) + "\n";
    for (let x in connectionPools) {
        for (let socket of connectionPools[x]) {
            socket.send(packet);
            socket.send(bpacket);
        }
    }
    reply("Message sent.");
});

pmx.action("reload", (reply: (res: any) => void) => {
    fs.readFile("server.lua", {encoding: "utf8"}).then(data => serverFile = data);
    fs.readFile("rawterm.lua", {encoding: "utf8"}).then(data => rawtermFile = data);
    fs.readFile("index.ejs", {encoding: "utf8"}).then(data => indexFile = data);
    if (isSecure) {
        key = readFileSync(`/etc/letsencrypt/live/remote.craftos-pc.cc/privkey.pem`);
        cert = readFileSync(`/etc/letsencrypt/live/remote.craftos-pc.cc/fullchain.pem`);
    }
    reply("Reloaded all files.");
});

function makeID(): string {
    const buf = Buffer.alloc(30);
    for (let i = 0; i < 30; i++) buf[i] = Math.floor(Math.random() * 255);
    return buf.toString("base64").replace(/\//g, "_").replace(/\+/g, "-");
}

function getURL(req: http.IncomingMessage) {
    return req.headers.host ? `ws${isSecure ? "s" : ""}://${req.headers.host}/` : serverURL;
}

app.get("/", (req, res) => {
    const id = makeID();
    const url = getURL(req);
    res.send(ejs.render(indexFile, {url: url, id: id}));
});

app.get("/new", (req, res) => {
    res.send(makeID());
});

app.get("/server.lua", (req, res) => {
    const url = getURL(req);
    res.contentType(".lua");
    res.send(serverFile.replace("${URL}", url));
});

app.get("/rawterm.lua", (req, res) => {
    res.contentType(".lua");
    res.send(rawtermFile);
});


const wsServer = new WebSocket.Server({ noServer: true });
wsServer.on('connection', (socket, request) => {
    const url: string = request.url!;
    const isServer = request.headers["X-Rawterm-Is-Server"] === "Yes";
    if (connectionPools[url] === undefined) {
        connectionPools[url] = [];
        connectionPoolOpen[url] = Date.now();
        pipeCounter.inc();
        pipeCount++;
    }
    connectionPools[url].push(socket);
    connectionCounter.inc();
    socket.on('message', message => {
        //console.log(message);
        for (let s of connectionPools[url]) if (s !== socket) s.send(message);
    });
    socket.on('close', () => {
        connectionPools[url].splice(connectionPools[url].indexOf(socket), 1);
        if (isServer) for (let s of connectionPools[url]) s.close();
        if (connectionPools[url].length === 0) {
            delete connectionPools[url];
            delete connectionPoolOpen[url];
            pipeCounter.dec();
            if (--pipeCount === 0 && awaitingRestart) process.exit(0);
        }
        connectionCounter.dec();
    });
});

// Clean up any pipes that only have one connection every few minutes
setInterval(() => {
    const now = Date.now();
    for (let x in connectionPools)
        if (connectionPools[x].length === 1 && now - connectionPoolOpen[x] > 60000)
            connectionPools[x][0].close();
}, 10 * 60 * 1000);

const server = isSecure ? https.createServer({key: key, cert: cert}, app).listen(443, ip) : app.listen(port, ip);
server.on('upgrade', (request: http.IncomingMessage, socket: net.Socket, head: Buffer) => {
    wsServer.handleUpgrade(request, socket, head, socket => {
        wsServer.emit('connection', socket, request);
    });
});

const app2 = express();
app2.get("/metrics", async (_req, res) => {
    try {
        res.set('Content-Type', register.contentType);
        res.end(await register.metrics());
    } catch (err) {
        res.status(500).end(err);
    }
});
app2.listen(9991, "0.0.0.0");

if (isSecure) {
    // https://stackoverflow.com/a/7458587/2032154
    const httpApp = express();
    httpApp.get('*', function(req, res) { 
        const url = getURL(req); 
        res.redirect(url.replace(/^ws/, "http").replace(/\/$/, "") + req.url);
    })
    const httpServer = httpApp.listen(port, ip);
    httpServer.on('upgrade', (request: http.IncomingMessage, socket: net.Socket, head: Buffer) => {
        const url = getURL(request);
        socket.write(request.httpVersion + " 301 Moved Permanently\r\nLocation: " + url.replace(/\/$/, "") + request.url + "\r\nContent-Length: 0\r\n\r\n");
        socket.end();
    });
    server.on("listening", () => console.log("Running! (insecure)"));
}

server.on("listening", () => console.log("Running!"));