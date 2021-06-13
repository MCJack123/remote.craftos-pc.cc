# remote.craftos-pc.cc
WebSocket server to connect VS Code to a ComputerCraft computer.

## Using
Install all dependencies with `npm install`.

Create a file named `config.json` with contents like this:

```json
{
    "ip": "127.0.0.1",
    "port": 4000,
    "isSecure": false
}
```

Then run `npm run start`.