# remote.craftos-pc.cc

WebSocket server to connect VS Code to a ComputerCraft computer. This project has been refactored to support both standalone operation and embedding in VS Code extensions while preserving all original functionality.

## Architecture

The codebase has been factored into modular components:

- **`src/server.ts`** - Core server functionality with clean API
- **`src/config.ts`** - Configuration interface and defaults  
- **`standalone.ts`** - Standalone server runner with PM2 support
- **`src/extension.ts`** - VS Code extension integration
- **`lib.ts`** - Main export file for easy importing
- **`static/`** - Static files (Lua scripts, EJS templates) served by the server

## Standalone Server

Install dependencies and run the enhanced standalone server:

```bash
npm install
npm start
```

#### Configuration

Create a `config.json` file:

```json
{
  "ip": "127.0.0.1",
  "port": 4000,
  "isSecure": false
}
```

Or use environment variables:
- `SERVER_IP` - Server IP address (default: "127.0.0.1")
- `SERVER_PORT` - Server port (default: 4000) 
- `HTTPS` - Enable HTTPS (default: false)
- `CERT_PATH` - Path to SSL certificate
- `KEY_PATH` - Path to SSL private key
- `METRICS_PORT` - Metrics server port (default: 9991)

## Programmatic API

### Basic Usage

```typescript
import { createServer } from './lib';

// Start server
const server = await createServer({
  ip: "localhost",
  port: 4000,
  isSecure: false,
  enableMetrics: false
});

console.log("Server started!");

// Send message to all connected computers
server.sendMessage("Hello from the server!");

// Check status
console.log(`Connections: ${server.getConnectionCount()}`);
console.log(`Pipes: ${server.getPipeCount()}`);

// Stop server
await server.stop();
```

### VS Code Extension Example

```typescript
import * as vscode from 'vscode';
import { createServer, ServerInstance } from './src/server';
import { defaultConfig } from './src/config';

let serverInstance: ServerInstance | undefined;

export function activate(context: vscode.ExtensionContext) {
  const startCmd = vscode.commands.registerCommand('myext.startServer', async () => {
    if (serverInstance) {
      vscode.window.showWarningMessage('Server already running');
      return;
    }

    try {
      serverInstance = await createServer({
        ...defaultConfig,
        ip: "127.0.0.1",
        port: 4000
      });
      
      vscode.window.showInformationMessage('Server started on localhost:4000');
    } catch (error) {
      vscode.window.showErrorMessage(`Failed to start: ${error}`);
    }
  });

  context.subscriptions.push(startCmd);
}
```

## Configuration Interface

```typescript
interface ServerConfig {
  ip: string;           // Server IP address
  port: number;         // Server port
  isSecure: boolean;    // Enable HTTPS
  certPath?: string;    // SSL certificate path
  keyPath?: string;     // SSL private key path
  enablePM2?: boolean;  // Enable PM2 actions
  enableMetrics?: boolean; // Enable Prometheus metrics
  metricsPort?: number; // Metrics server port
}
```

## Server Instance API

```typescript
interface ServerInstance {
  app: express.Application;     // Express app
  server: http.Server | https.Server; // HTTP(S) server
  stop: () => Promise<void>;    // Stop server
  sendMessage: (message: string) => void; // Broadcast message
  reloadFiles: () => Promise<void>; // Reload Lua files
  getConnectionCount: () => number; // Active connections
  getPipeCount: () => number;   // Active pipes
}
```

## Features

- **WebSocket Communication** - Real-time connection with CraftOS-PC
- **File Serving** - Serves Lua scripts and web interface
- **Music Upload** - Audio file conversion to DFPWM format
- **Connection Management** - Automatic cleanup and pooling
- **Metrics & Monitoring** - Prometheus metrics (standalone mode)
- **PM2 Integration** - Process management (standalone mode)
- **VS Code Extension Support** - Easy embedding in extensions
- **Localhost Optimization** - Perfect for development workflows

## Migration Guide

### From Original Setup
- **No changes needed** - Original functionality preserved
- **Enhanced**: Use `npm start` for better configuration options
- **Optional**: Switch to new configuration format for more features

### For VS Code Extensions
1. Import from `lib.ts`: `import { createServer } from './lib'`
2. Use the `createServer()` function with localhost config
3. Handle server lifecycle in extension activate/deactivate

### For New Deployments
- Use `standalone.ts` for production deployments
- Configure via environment variables or `config.json`
- Enable metrics and PM2 features as needed

## Development

```bash
# Build TypeScript
npm run build

# Watch mode for development
npm run watch
```

### Project Structure

```
src/
├── server.ts        # Core server functionality
├── config.ts        # Configuration interface
├── music.ts         # Music upload router
└── extension.ts     # VS Code extension support

static/
├── music/           # Music upload interface files
│   ├── index.html   # Music upload web interface
│   ├── index.js     # Client-side JavaScript
│   └── site.css     # Styling
├── server.lua       # ComputerCraft server script
├── rawterm.lua      # Raw terminal protocol
├── string_pack.lua  # String packing utilities
└── index.ejs        # Web interface template

standalone.ts        # Standalone server runner
lib.ts              # Main exports
config.json         # Server configuration
```