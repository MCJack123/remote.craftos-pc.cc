import fs from "fs";
import express from "express";
import rateLimit from "express-rate-limit";
import ffmpeg from "fluent-ffmpeg";
import {Readable} from "stream";

var cache: {[key: string]: string} = {}
function getCachedFile(name: string) {
    if (cache[name] !== undefined) return cache[name];
    let data = fs.readFileSync("music/" + name, {encoding: "utf8"});
    cache[name] = data;
    return data;
}

export = function(url: string, isSecure: boolean): express.Router {
    let route = express.Router();

    route.use(rateLimit({windowMs: 15 * 60 * 1000, max: 40, standardHeaders: true, legacyHeaders: true}));

    route.get('/', (req, res) => {res.set("Content-Type", "text/html"); res.send(getCachedFile("index.html"));});
    route.get('/index.js', (req, res) => {res.set("Content-Type", "application/javascript"); res.send(getCachedFile("index.js").replace(/\$URL_PLACEHOLDER/g, (isSecure ? "https://" : "http://") + req.hostname + url));});
    route.get('/site.css', (req, res) => {res.set("Content-Type", "text/css"); res.send(getCachedFile("site.css"));});

    route.use('/upload', express.raw({limit: "25MB", inflate: false, type: "*/*"}));
    route.post("/upload", (req, res) => {
        let binstr = "";
        for (let i = 0; i < 6; i++) binstr += String.fromCharCode(Math.random() * 255);
        let id = Buffer.from(binstr, "binary").toString("base64").replace(/\//g, "_");
        ffmpeg(Readable.from(req.body))
            .audioCodec('dfpwm')
            .audioChannels(1)
            .audioFrequency(48000)
            .noVideo()
            .outputOptions("-fs 25000000")
            .output("content/" + id + ".dfpwm")
            .format("dfpwm")
            .on('error', (err) => {
                res.status(500).json({status: 500, error: err.message});
                res.end();
            })
            .on('end', () => {
                setTimeout(() => fs.rmSync("content/" + id + ".dfpwm"), 10 * 60000);
                res.status(200).send(id);
            })
            .run();
    });

    route.get("/content/[a-zA-Z0-9+_]{8}.dfpwm", (req, res) => {
        res.sendFile(req.url.substr(1), {maxAge: 900000, root: "/var/www/html"});
    });

    if (fs.existsSync("content")) fs.rmSync("content", {recursive: true});
    fs.mkdirSync("content");

    setInterval(() => {
        for (let p of fs.readdirSync("content")) {
            if (p === "." || p === "..") continue;
            fs.stat("content/" + p, (e, stat) => {
                if (stat === null) return;
                if (stat.ctimeMs + 1200000 < Date.now()) fs.rm("content/" + p, () => {});
            });
        }
    }, 1200000);

    return route;
}
