import pmx from "@pm2/io";
import { createServer } from "./src/server";
import { ServerConfig, defaultConfig } from "./src/config";

// Load configuration (you can create a config.json file or use environment variables)
const config: ServerConfig = {
  ...defaultConfig,
  ip: process.env.SERVER_IP || "127.0.0.1",
  port: parseInt(process.env.SERVER_PORT || "4000"),
  isSecure: process.env.HTTPS === "true",
  certPath: process.env.CERT_PATH || "/etc/letsencrypt/live/remote.craftos-pc.cc/fullchain.pem",
  keyPath: process.env.KEY_PATH || "/etc/letsencrypt/live/remote.craftos-pc.cc/privkey.pem",
  enablePM2: true,
  enableMetrics: true,
  metricsPort: parseInt(process.env.METRICS_PORT || "9991")
};

let serverInstance: any;
let awaitingRestart = false;

async function startServer() {
  try {
    serverInstance = await createServer(config);
    
    // PM2 actions
    pmx.action("schedule-restart", (reply: (res: any) => void) => {
      if (serverInstance.getPipeCount() === 0) {
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
      serverInstance.sendMessage(param);
      reply("Message sent.");
    });

    pmx.action("reload", (reply: (res: any) => void) => {
      serverInstance.reloadFiles().then(() => {
        reply("Reloaded all files.");
      }).catch((err: Error) => {
        reply("Error reloading files: " + err.message);
      });
    });

    console.log(`Server running on ${config.isSecure ? 'https' : 'http'}://${config.ip}:${config.port}`);
    
  } catch (error) {
    console.error("Failed to start server:", error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('Received SIGINT, shutting down gracefully...');
  if (serverInstance) {
    await serverInstance.stop();
  }
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  if (serverInstance) {
    await serverInstance.stop();
  }
  process.exit(0);
});

startServer();
