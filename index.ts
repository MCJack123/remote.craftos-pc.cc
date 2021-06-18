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

let connectionPools: {[key: string]: WebSocket[]} = {}

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
            pipeCounter.dec();
            if (--pipeCount === 0) process.exit(0);
        }
        connectionCounter.dec();
    });
});

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