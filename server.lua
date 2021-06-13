local url = "${URL}"
if not fs.exists("rawterm.lua") then
    local handle, err = http.get(url:gsub("^ws", "http") .. "rawterm.lua")
    if not handle then error("Could not download rawterm API: " .. err) end
    local file, err = fs.open("rawterm.lua", "w")
    if not file then handle.close() error("Could not open rawterm.lua for writing: " .. err) end
    file.write(handle.readAll())
    handle.close()
    file.close()
end
local rawterm = dofile "rawterm.lua"

local conn, err = rawterm.wsDelegate(url .. ..., {["X-Rawterm-Is-Server"] = "Yes"})
if not conn then error("Could not connect to server: " .. err) end
local oldClose = conn.close
local isOpen = true
function conn:close() isOpen = false return oldClose(self) end
local w, h = term.getSize()
local win = rawterm.server(conn, w, h, 0, "ComputerCraft Remote Terminal: " .. (os.computerLabel() or ("Computer " .. os.computerID())), term.current())
win.setVisible(false)
local oldterm = term.redirect(win)
local ok, tm
ok, err = pcall(parallel.waitForAny, function()
    local coro = coroutine.create(shell.run)
    local ok, filter = coroutine.resume(coro, "shell")
    while ok and coroutine.status(coro) == "suspended" do
        local ev = table.pack(win.pullEvent(filter))
        if ev[1] ~= "timer" or ev[2] ~= tm then ok, filter = coroutine.resume(coro, table.unpack(ev, 1, ev.n)) end
    end
    if not ok then err = filter end
end, function()
    while isOpen do
        win.setVisible(true)
        win.setVisible(false)
        tm = os.startTimer(0.05)
        repeat local ev, p = os.pullEvent("timer") until p == tm
    end
end)
term.redirect(oldterm)
win.close()
shell.run("clear")
if type(err) == "string" then printError(err) end