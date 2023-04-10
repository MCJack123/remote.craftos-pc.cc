local function minver(version)
    local res
    if _CC_VERSION then res = version <= _CC_VERSION
    elseif not _HOST then res = version <= os.version():gsub("CraftOS ", "")
    elseif _HOST:match("ComputerCraft 1%.1%d+") ~= version:match("1%.1%d+") then
      version = version:gsub("(1%.)([02-9])", "%10%2")
      local host = _HOST:gsub("(ComputerCraft 1%.)([02-9])", "%10%2")
      res = version <= host:match("ComputerCraft ([0-9%.]+)")
    else res = version <= _HOST:match("ComputerCraft ([0-9%.]+)") end
    assert(res, "This program requires ComputerCraft " .. version .. " or later.")
end
minver "1.85.0"
local url = "${URL}"
if not string.pack then
    if not fs.exists("string_pack.lua") then
        print("Downloading string.pack polyfill...")
        local handle, err = http.get(url:gsub("^ws", "http") .. "string_pack.lua")
        if not handle then error("Could not download string.pack polyfill: " .. err) end
        local file, err = fs.open("string_pack.lua", "w")
        if not file then handle.close() error("Could not open string_pack.lua for writing: " .. err) end
        file.write(handle.readAll())
        handle.close()
        file.close()
    end
    local sp = dofile "string_pack.lua"
    for k,v in pairs(sp) do string[k] = v end
end
local rawterm
if not fs.exists("rawterm.lua") or fs.getSize("rawterm.lua") ~= [[${SIZE}]] then
    print("Downloading rawterm API...")
    local handle, err = http.get(url:gsub("^ws", "http") .. "rawterm.lua")
    if not handle then error("Could not download rawterm API: " .. err) end
    local data = handle.readAll()
    handle.close()
    if fs.getFreeSpace("/") >= #data + 4096 then
        local file, err = fs.open("rawterm.lua", "w")
        if not file then error("Could not open rawterm.lua for writing: " .. err) end
        file.write(data)
        file.close()
    else rawterm = assert(load(data, "@rawterm.lua", "t"))() end
end
rawterm = rawterm or dofile "rawterm.lua"

local arg, cmd = ...
print("Connecting to " .. url .. "...")
local conn, err = rawterm.wsDelegate(url .. arg, {["X-Rawterm-Is-Server"] = "Yes"})
if not conn then error("Could not connect to server: " .. err) end
local oldClose, oldReceive, oldSend = conn.close, conn.receive, conn.send
local isOpen = true
function conn:close() isOpen = false return oldClose(self) end
function conn:receive(...)
    if not isOpen then return nil end
    local buf, res, size = ""
    repeat
        repeat res = table.pack(pcall(oldReceive, self, ...))
        until not (not res[1] and res[2]:match("Terminated$"))
        if not res[1] then error(res[2])
        elseif not res[2] then return nil end
        if not size then size = tonumber(res[2]:match "!CPC(%x%x%x%x)" or res[2]:match("!CPD(" .. ("%x"):rep(12) .. ")") or "", 16) end
        if size then buf = buf .. res[2]:gsub("\n", "") end
    until size and #buf >= size + 16 + (buf:match "^!CPD" and 8 or 0)
    return buf .. "\n"
end
function conn:send(data) if isOpen then for i = 1, #data, 65530 do oldSend(self, data:sub(i, math.min(i + 65529, #data))) end end end
local w, h = term.getSize()
local win = rawterm.server(conn, w, h, 0, "ComputerCraft Remote Terminal: " .. (os.computerLabel() or ("Computer " .. os.computerID())), term.current())
win.setVisible(false)
local monitors, ids = {}, {[0] = true}
local oldcall = peripheral.call
for i, v in ipairs{peripheral.find "monitor"} do
    local mw, mh = v.getSize()
    local name = peripheral.getName(v)
    local methods = peripheral.getMethods(name)
    local p = {}
    for _, v in ipairs(methods) do p[v] = function(...) return oldcall(name, v, ...) end end
    monitors[name] = {id = i, win = rawterm.server(conn, mw, mh, i, "ComputerCraft Remote Terminal: Monitor " .. name, p, nil, nil, nil, true)}
    monitors[name].win.setVisible(false)
    ids[i] = true
end
function peripheral.call(side, method, ...)
    if monitors[side] then return monitors[side].win[method](...)
    else return oldcall(side, method, ...) end
end
local oldterm = term.redirect(win)
local ok, tm
ok, err = pcall(parallel.waitForAny, function()
    local coro = coroutine.create(shell.run)
    local ok, filter = coroutine.resume(coro, cmd or (settings.get("bios.use_multishell") and "multishell" or "shell"))
    while ok and coroutine.status(coro) == "suspended" do
        local ev = {}
        local pullers = {function() ev = table.pack(win.pullEvent(filter, true, true)) end}
        for k, v in pairs(monitors) do pullers[#pullers+1] = function()
            ev = table.pack(v.win.pullEvent(filter, true, true))
            if ev[1] == "mouse_click" then ev = {"monitor_touch", k, ev[3], ev[4]}
            elseif ev[1] == "mouse_up" or ev[1] == "mouse_drag" or ev[1] == "mouse_scroll" or ev[1] == "mouse_move" then ev = {} end
        end end
        pullers[#pullers+1] = function()
            repeat ev = table.pack(os.pullEventRaw(filter)) until not (ev[1] == "websocket_message" and ev[2] == url .. arg) and not (ev[1] == "timer" and ev[2] == tm)
        end
        parallel.waitForAny(table.unpack(pullers))
        if ev[1] then ok, filter = coroutine.resume(coro, table.unpack(ev, 1, ev.n)) end
    end
    if not ok then err = filter end
end, function()
    while isOpen do
        win.setVisible(true)
        win.setVisible(false)
        for _, v in pairs(monitors) do
            v.win.setVisible(true)
            v.win.setVisible(false)
        end
        tm = os.startTimer(0.05)
        repeat local ev, p = os.pullEventRaw("timer") until p == tm
    end
end, function()
    while true do
        local ev, side = os.pullEventRaw()
        if ev == "peripheral" and peripheral.getType(side) == "monitor" and not monitors[side] then
            local id = #ids + 1
            local mw, mh = oldcall(side, "getSize")
            local methods = peripheral.getMethods(side)
            for _, v in ipairs(methods) do methods[v] = true end
            local p = setmetatable({}, {__index = function(_, idx) if methods[idx] then return function(...) return oldcall(side, idx, ...) end end end})
            monitors[side] = {id = id, win = rawterm.server(conn, mw, mh, id, "ComputerCraft Remote Terminal: Monitor " .. side, p, nil, nil, nil, true)}
            monitors[side].win.setVisible(false)
            ids[id] = true
        elseif ev == "peripheral_detach" and monitors[side] then
            monitors[side].win.close(true)
            ids[monitors[side].id] = nil
            monitors[side] = nil
        elseif ev == "term_resize" then
            win.reposition(nil, nil, term.getSize())
        elseif ev == "monitor_resize" and monitors[side] then
            monitors[side].win.reposition(nil, nil, oldcall(side, "getSize"))
        elseif ev == "websocket_closed" and side == url .. arg then
            isOpen = false
        end
    end
end)
term.redirect(oldterm)
for _, v in pairs(monitors) do v.win.close(true) end
win.close()
peripheral.call = oldcall
shell.run("clear")
if type(err) == "string" and not err:match("attempt to use closed file") then printError(err) end
