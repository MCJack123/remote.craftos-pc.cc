import express from "express";
import WebSocket from "ws";
import fs from "fs/promises";
import {readFileSync} from "fs";
import ejs from "ejs";
import http from "http";
import https from "https";
import tls from "tls";
import net from "net";
import luamin from "luamin";
import { collectDefaultMetrics, register, Gauge } from "prom-client";
import { ServerConfig } from "./config";
import music from "./music";

var crcTable: number[];

function makeCRCTable() {
    let c;
    let crcTable: number[] = [];
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

export interface ServerInstance {
  app: express.Application;
  server: http.Server | https.Server;
  stop: () => Promise<void>;
  sendMessage: (message: string) => void;
  reloadFiles: () => Promise<void>;
  getConnectionCount: () => number;
  getPipeCount: () => number;
}

export async function createServer(config: ServerConfig): Promise<ServerInstance> {
  let connectionPools: {[key: string]: WebSocket[]} = {};
  let connectionPoolOpen: {[key: string]: number} = {};
  
  const app = express();
  const serverURL = `ws${config.isSecure ? "s" : ""}://${config.ip}:${config.port}/`;

  let serverFile: string;
  let rawtermFile: string;
  let stringPackFile: string;
  let indexFile: string;
  
  // Load files function
  const loadFiles = async () => {
    serverFile = luamin.minify(await fs.readFile("static/server.lua", {encoding: "utf8"}));
    rawtermFile = luamin.minify(await fs.readFile("static/rawterm.lua", {encoding: "utf8"}));
    stringPackFile = luamin.minify(await fs.readFile("static/string_pack.lua", {encoding: "utf8"}));
    indexFile = await fs.readFile("static/index.ejs", {encoding: "utf8"});
  };
  
  await loadFiles();
  
  let ctx: tls.SecureContext | undefined;
  if (config.isSecure && config.certPath && config.keyPath) {
    ctx = tls.createSecureContext({
      key: readFileSync(config.keyPath),
      cert: readFileSync(config.certPath)
    });
  }

  let connectionCounter: Gauge<string> | undefined;
  let pipeCounter: Gauge<string> | undefined;
  let pipeCount = 0;

  if (config.enableMetrics) {
    collectDefaultMetrics();
    connectionCounter = new Gauge({name: "http_active_connections", help: "Active Connections"});
    pipeCounter = new Gauge({name: "http_active_pipes", help: "Active Pipes"});
  }

  function makeID(): string {
    const buf = Buffer.alloc(30);
    for (let i = 0; i < 30; i++) buf[i] = Math.floor(Math.random() * 255);
    return buf.toString("base64").replace(/\//g, "_").replace(/\+/g, "-");
  }

  function getURL(req: http.IncomingMessage) {
    return req.headers.host ? `ws${config.isSecure ? "s" : ""}://${req.headers.host}/` : serverURL;
  }

  // Routes
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
    res.send(serverFile.replace("${URL}", url).replace("[[${SIZE}]]", `(${rawtermFile.length})`));
  });

  app.get("/rawterm.lua", (req, res) => {
    res.contentType(".lua");
    res.send(rawtermFile);
  });

  app.get("/string_pack.lua", (req, res) => {
    res.contentType(".lua");
    res.send(stringPackFile);
  });

  app.get("/.well-known/acme-challenge/:file", (req, res) => {
    fs.readFile(".well-known/acme-challenge/" + req.params.file)
      .then(data => res.send(data))
      .catch(() => res.status(404).send("404 Not Found"));
  });

  app.use("/music", music("/music", config.isSecure));
  app.get("/music", (req, res) => res.redirect(301, "/music/"));

  // WebSocket server
  const wsServer = new WebSocket.Server({ noServer: true });
  wsServer.on('connection', (socket, request) => {
    const url: string = request.url!;
    const isServer = request.headers["X-Rawterm-Is-Server"] === "Yes";
    if (connectionPools[url] === undefined) {
      connectionPools[url] = [];
      connectionPoolOpen[url] = Date.now();
      if (pipeCounter) pipeCounter.inc();
      pipeCount++;
    }
    connectionPools[url].push(socket);
    if (connectionCounter) connectionCounter.inc();
    
    socket.on('message', message => {
      for (let s of connectionPools[url]) if (s !== socket) s.send(message);
    });
    
    socket.on('close', () => {
      connectionPools[url].splice(connectionPools[url].indexOf(socket), 1);
      if (isServer) for (let s of connectionPools[url]) s.close();
      if (connectionPools[url].length === 0) {
        delete connectionPools[url];
        delete connectionPoolOpen[url];
        if (pipeCounter) pipeCounter.dec();
        pipeCount--;
      }
      if (connectionCounter) connectionCounter.dec();
    });
  });

  // Clean up pipes with single connections
  const cleanupInterval = setInterval(() => {
    const now = Date.now();
    for (let x in connectionPools)
      if (connectionPools[x].length === 1 && now - connectionPoolOpen[x] > 60000)
        connectionPools[x][0].close();
  }, 10 * 60 * 1000);

  // Create server
  const server = config.isSecure && ctx 
    ? https.createServer({SNICallback: (servername, cb) => cb(null, ctx!)}, app)
    : http.createServer(app);

  server.on('upgrade', (request: http.IncomingMessage, socket: net.Socket, head: Buffer) => {
    wsServer.handleUpgrade(request, socket, head, socket => {
      wsServer.emit('connection', socket, request);
    });
  });

  // Start server
  await new Promise<void>((resolve, reject) => {
    server.listen(config.port, config.ip, (err?: Error) => {
      if (err) reject(err);
      else resolve();
    });
  });

  // HTTP redirect server for HTTPS
  let httpServer: http.Server | undefined;
  if (config.isSecure) {
    const httpApp = express();
    httpApp.get('*', function(req, res) { 
      const url = getURL(req); 
      res.redirect(url.replace(/^ws/, "http").replace(/\/$/, "") + req.url);
    });
    httpServer = httpApp.listen(80, config.ip);
    httpServer.on('upgrade', (request: http.IncomingMessage, socket: net.Socket, head: Buffer) => {
      const url = getURL(request);
      socket.write(request.httpVersion + " 301 Moved Permanently\r\nLocation: " + url.replace(/\/$/, "") + request.url + "\r\nContent-Length: 0\r\n\r\n");
      socket.end();
    });
  }

  // Metrics server
  let metricsServer: http.Server | undefined;
  if (config.enableMetrics) {
    const metricsApp = express();
    metricsApp.get("/metrics", async (_req, res) => {
      try {
        res.set('Content-Type', register.contentType);
        res.end(await register.metrics());
      } catch (err) {
        res.status(500).end(err);
      }
    });
    metricsServer = metricsApp.listen(config.metricsPort || 9991, "127.0.0.1");
  }

  // Utility functions
  const sendMessage = (message: string) => {
    const buf = Buffer.alloc(27 + message.length);
    buf.fill(0);
    buf[0] = 5;
    buf[2] = 0x40;
    buf.write("Message from server", 6);
    buf.write(message, 26);
    const b64 = buf.toString("base64");
    const packet = "!CPC" + ("000" + b64.length.toString(16)).slice(-4) + b64 + ("0000000" + crc32(b64).toString(16)).slice(-8) + "\n";
    const bpacket = "!CPC" + ("000" + b64.length.toString(16)).slice(-4) + b64 + ("0000000" + crc32(buf.toString("binary")).toString(16)).slice(-8) + "\n";
    for (let x in connectionPools) {
      for (let socket of connectionPools[x]) {
        socket.send(packet);
        socket.send(bpacket);
      }
    }
  };

  const stop = async (): Promise<void> => {
    clearInterval(cleanupInterval);
    
    // Close all WebSocket connections
    for (let x in connectionPools) {
      for (let socket of connectionPools[x]) {
        socket.close();
      }
    }
    
    // Close servers
    await new Promise<void>((resolve) => {
      server.close(() => resolve());
    });
    
    if (httpServer) {
      await new Promise<void>((resolve) => {
        httpServer!.close(() => resolve());
      });
    }
    
    if (metricsServer) {
      await new Promise<void>((resolve) => {
        metricsServer!.close(() => resolve());
      });
    }
  };

  return {
    app,
    server,
    stop,
    sendMessage,
    reloadFiles: loadFiles,
    getConnectionCount: () => Object.values(connectionPools).reduce((sum, pool) => sum + pool.length, 0),
    getPipeCount: () => pipeCount
  };
}
