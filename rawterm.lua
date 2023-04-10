--- rawterm.lua - CraftOS-PC raw mode protocol client/server API
-- By JackMacWindows
--
-- @module rawterm
--
-- This API provides the ability to host terminals accessible from remote
-- systems, as well as to render those terminals on the screen. It uses the raw
-- mode protocol defined by CraftOS-PC to communicate between client and server.
-- This means that this API can be used to host and connect to a CraftOS-PC
-- instance running over a WebSocket connection (using an external server
-- application).
--
-- In addition, this API supports raw mode version 1.1, which includes support
-- for filesystem access. This lets the server send and receive files and query
-- file information over the raw connection.
--
-- To allow the ability to use any type of connection medium to send/receive
-- data, a delegate object is used for communication. This must have a send and
-- receive method, and may also have additional methods as mentioned below.
-- Built-in delegate constructors are provided for WebSockets and Rednet.
--
-- See the adjacent rawtermtest.lua file for an example of how to use this API.

-- MIT License
--
-- Copyright (c) 2021 JackMacWindows
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local expect = dofile "/rom/modules/main/cc/expect.lua"
setmetatable(expect, {__call = function(_, ...) return expect.expect(...) end})

local rawterm = {}

local b64str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local keymap = {
    [1] = 0,
    [2] = keys.one,
    [3] = keys.two,
    [4] = keys.three,
    [5] = keys.four,
    [6] = keys.five,
    [7] = keys.six,
    [8] = keys.seven,
    [9] = keys.eight,
    [10] = keys.nine,
    [11] = keys.zero,
    [12] = keys.minus,
    [13] = keys.equals,
    [14] = keys.backspace,
    [15] = keys.tab,
    [16] = keys.q,
    [17] = keys.w,
    [18] = keys.e,
    [19] = keys.r,
    [20] = keys.t,
    [21] = keys.y,
    [22] = keys.u,
    [23] = keys.i,
    [24] = keys.o,
    [25] = keys.p,
    [26] = keys.leftBracket,
    [27] = keys.rightBracket,
    [28] = keys.enter,
    [29] = keys.leftCtrl,
    [30] = keys.a,
    [31] = keys.s,
    [32] = keys.d,
    [33] = keys.f,
    [34] = keys.g,
    [35] = keys.h,
    [36] = keys.j,
    [37] = keys.k,
    [38] = keys.l,
    [39] = keys.semiColon,
    [40] = keys.apostrophe,
    [41] = keys.grave,
    [42] = keys.leftShift,
    [43] = keys.backslash,
    [44] = keys.z,
    [45] = keys.x,
    [46] = keys.c,
    [47] = keys.v,
    [48] = keys.b,
    [49] = keys.n,
    [50] = keys.m,
    [51] = keys.comma,
    [52] = keys.period,
    [53] = keys.slash,
    [54] = keys.rightShift,
    [55] = keys.multiply,
    [56] = keys.leftAlt,
    [57] = keys.space,
    [58] = keys.capsLock,
    [59] = keys.f1,
    [60] = keys.f2,
    [61] = keys.f3,
    [62] = keys.f4,
    [63] = keys.f5,
    [64] = keys.f6,
    [65] = keys.f7,
    [66] = keys.f8,
    [67] = keys.f9,
    [68] = keys.f10,
    [69] = keys.numLock,
    [70] = keys.scrollLock,
    [71] = keys.numPad7,
    [72] = keys.numPad8,
    [73] = keys.numPad9,
    [74] = keys.numPadSubtract,
    [75] = keys.numPad4,
    [76] = keys.numPad5,
    [77] = keys.numPad6,
    [78] = keys.numPadAdd,
    [79] = keys.numPad1,
    [80] = keys.numPad2,
    [81] = keys.numPad3,
    [82] = keys.numPad0,
    [83] = keys.numPadDecimal,
    [87] = keys.f11,
    [88] = keys.f12,
    [100] = keys.f13,
    [101] = keys.f14,
    [102] = keys.f15,
    [111] = keys.kana,
    [121] = keys.convert,
    [123] = keys.noconvert,
    [125] = keys.yen,
    [141] = keys.numPadEquals,
    [144] = keys.cimcumflex,
    [145] = keys.at,
    [146] = keys.colon,
    [147] = keys.underscore,
    [148] = keys.kanji,
    [149] = keys.stop,
    [150] = keys.ax,
    [156] = keys.numPadEnter,
    [157] = keys.rightCtrl,
    [179] = keys.numPadComma,
    [181] = keys.numPadDivide,
    [184] = keys.rightAlt,
    [197] = keys.pause,
    [199] = keys.home,
    [200] = keys.up,
    [201] = keys.pageUp,
    [203] = keys.left,
    [205] = keys.right,
    [207] = keys["end"],
    [208] = keys.down,
    [209] = keys.pageDown,
    [210] = keys.insert,
    [211] = keys.delete
}
local keymap_rev = {
    [0] = 1,
    [keys.one] = 2,
    [keys.two] = 3,
    [keys.three] = 4,
    [keys.four] = 5,
    [keys.five] = 6,
    [keys.six] = 7,
    [keys.seven] = 8,
    [keys.eight] = 9,
    [keys.nine] = 10,
    [keys.zero] = 11,
    [keys.minus] = 12,
    [keys.equals] = 13,
    [keys.backspace] = 14,
    [keys.tab] = 15,
    [keys.q] = 16,
    [keys.w] = 17,
    [keys.e] = 18,
    [keys.r] = 19,
    [keys.t] = 20,
    [keys.y] = 21,
    [keys.u] = 22,
    [keys.i] = 23,
    [keys.o] = 24,
    [keys.p] = 25,
    [keys.leftBracket] = 26,
    [keys.rightBracket] = 27,
    [keys.enter] = 28,
    [keys.leftCtrl] = 29,
    [keys.a] = 30,
    [keys.s] = 31,
    [keys.d] = 32,
    [keys.f] = 33,
    [keys.g] = 34,
    [keys.h] = 35,
    [keys.j] = 36,
    [keys.k] = 37,
    [keys.l] = 38,
    [keys.semicolon or keys.semiColon] = 39,
    [keys.apostrophe] = 40,
    [keys.grave] = 41,
    [keys.leftShift] = 42,
    [keys.backslash] = 43,
    [keys.z] = 44,
    [keys.x] = 45,
    [keys.c] = 46,
    [keys.v] = 47,
    [keys.b] = 48,
    [keys.n] = 49,
    [keys.m] = 50,
    [keys.comma] = 51,
    [keys.period] = 52,
    [keys.slash] = 53,
    [keys.rightShift] = 54,
    [keys.leftAlt] = 56,
    [keys.space] = 57,
    [keys.capsLock] = 58,
    [keys.f1] = 59,
    [keys.f2] = 60,
    [keys.f3] = 61,
    [keys.f4] = 62,
    [keys.f5] = 63,
    [keys.f6] = 64,
    [keys.f7] = 65,
    [keys.f8] = 66,
    [keys.f9] = 67,
    [keys.f10] = 68,
    [keys.numLock] = 69,
    [keys.scollLock or keys.scrollLock] = 70,
    [keys.numPad7] = 71,
    [keys.numPad8] = 72,
    [keys.numPad9] = 73,
    [keys.numPadSubtract] = 74,
    [keys.numPad4] = 75,
    [keys.numPad5] = 76,
    [keys.numPad6] = 77,
    [keys.numPadAdd] = 78,
    [keys.numPad1] = 79,
    [keys.numPad2] = 80,
    [keys.numPad3] = 81,
    [keys.numPad0] = 82,
    [keys.numPadDecimal] = 83,
    [keys.f11] = 87,
    [keys.f12] = 88,
    [keys.f13] = 100,
    [keys.f14] = 101,
    [keys.f15] = 102,
    [keys.numPadEquals or keys.numPadEqual] = 141,
    [keys.numPadEnter] = 156,
    [keys.rightCtrl] = 157,
    [keys.rightAlt] = 184,
    [keys.pause] = 197,
    [keys.home] = 199,
    [keys.up] = 200,
    [keys.pageUp] = 201,
    [keys.left] = 203,
    [keys.right] = 205,
    [keys["end"]] = 207,
    [keys.down] = 208,
    [keys.pageDown] = 209,
    [keys.insert] = 210,
    [keys.delete] = 211
}

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

local function base64encode(str)
    local retval = ""
    for s in str:gmatch "..." do
        local n = s:byte(1) * 65536 + s:byte(2) * 256 + s:byte(3)
        local a, b, c, d = bit32.extract(n, 18, 6), bit32.extract(n, 12, 6), bit32.extract(n, 6, 6), bit32.extract(n, 0, 6)
        retval = retval .. b64str:sub(a+1, a+1) .. b64str:sub(b+1, b+1) .. b64str:sub(c+1, c+1) .. b64str:sub(d+1, d+1)
    end
    if #str % 3 == 1 then
        local n = str:byte(-1)
        local a, b = bit32.rshift(n, 2), bit32.lshift(bit32.band(n, 3), 4)
        retval = retval .. b64str:sub(a+1, a+1) .. b64str:sub(b+1, b+1) .. "=="
    elseif #str % 3 == 2 then
        local n = str:byte(-2) * 256 + str:byte(-1)
        local a, b, c, d = bit32.extract(n, 10, 6), bit32.extract(n, 4, 6), bit32.lshift(bit32.extract(n, 0, 4), 2)
        retval = retval .. b64str:sub(a+1, a+1) .. b64str:sub(b+1, b+1) .. b64str:sub(c+1, c+1) .. "="
    end
    return retval
end

local function base64decode(str)
    local retval = ""
    for s in str:gmatch "...." do
        if s:sub(3, 4) == '==' then
            retval = retval .. string.char(bit32.bor(bit32.lshift(b64str:find(s:sub(1, 1)) - 1, 2), bit32.rshift(b64str:find(s:sub(2, 2)) - 1, 4)))
        elseif s:sub(4, 4) == '=' then
            local n = (b64str:find(s:sub(1, 1))-1) * 4096 + (b64str:find(s:sub(2, 2))-1) * 64 + (b64str:find(s:sub(3, 3))-1)
            retval = retval .. string.char(bit32.extract(n, 10, 8)) .. string.char(bit32.extract(n, 2, 8))
        else
            local n = (b64str:find(s:sub(1, 1))-1) * 262144 + (b64str:find(s:sub(2, 2))-1) * 4096 + (b64str:find(s:sub(3, 3))-1) * 64 + (b64str:find(s:sub(4, 4))-1)
            retval = retval .. string.char(bit32.extract(n, 16, 8)) .. string.char(bit32.extract(n, 8, 8)) .. string.char(bit32.extract(n, 0, 8))
        end
    end
    return retval
end

local crctable
local function crc32(str)
    -- calculate CRC-table
    if not crctable then
        crctable = {}
        for i = 0, 0xFF do
            local rem = i
            for j = 1, 8 do
                if bit32.band(rem, 1) == 1 then
                    rem = bit32.rshift(rem, 1)
                    rem = bit32.bxor(rem, 0xEDB88320)
                else rem = bit32.rshift(rem, 1) end
            end
            crctable[i] = rem
        end
    end
    local crc = 0xFFFFFFFF
    for x = 1, #str do crc = bit32.bxor(bit32.rshift(crc, 8), crctable[bit32.bxor(bit32.band(crc, 0xFF), str:byte(x))]) end
    return bit32.bxor(crc, 0xFFFFFFFF)
end

local function decodeIBT(data, pos)
    local ptyp = data:byte(pos)
    pos = pos + 1
    local pat
    if ptyp == 0 then pat = "<j"
    elseif ptyp == 1 then pat = "<n"
    elseif ptyp == 2 then pat = "<B"
    elseif ptyp == 3 then pat = "<z"
    elseif ptyp == 4 then
        local t, keys = {}, {}
        local nent = data:byte(pos)
        pos = pos + 1
        for i = 1, nent do keys[i], pos = decodeIBT(data, pos) end
        for i = 1, nent do t[keys[i]], pos = decodeIBT(data, pos) end
        return t, pos
    else return nil, pos end
    local d
    d, pos = string.unpack(pat, data, pos)
    if ptyp == 2 then d = d ~= 0 end
    return d, pos
end

local function encodeIBT(val)
    if type(val) == "number" then
        if val % 1 == 0 and val >= -0x80000000 and val < 0x80000000 then return string.pack("<Bj", 0, val)
        else return string.pack("<Bn", 1, val) end
    elseif type(val) == "boolean" then return string.pack("<BB", 2, val and 1 or 0)
    elseif type(val) == "string" then return string.pack("<Bz", 3, val)
    elseif type(val) == "nil" then return "\5"
    elseif type(val) == "table" then
        local keys, vals = {}, {}
        local i = 1
        for k,v in pairs(val) do keys[i], vals[i], i = k, v, i + 1 end
        local s = string.pack("<BB", 4, i - 1)
        for j = 1, i - 1 do s = s .. encodeIBT(keys[j]) end
        for j = 1, i - 1 do s = s .. encodeIBT(vals[j]) end
        return s
    else error("Cannot encode type " .. type(val)) end
end

local mouse_events = {[0] = "mouse_click", "mouse_up", "mouse_scroll", "mouse_drag"}
local fsFunctions = {[0] = fs.exists, fs.isDir, fs.isReadOnly, fs.getSize, fs.getDrive, fs.getCapacity, fs.getFreeSpace, fs.list, fs.attributes, fs.find, fs.makeDir, fs.delete, fs.copy, fs.move, function() end, function() end}
if not fs.attributes then fsFunctions[8] = function(path)
    expect(1, path, "string")
    if not fs.exists(path) then return nil end
    return {
        size = fs.getSize(path),
        isDir = fs.isDir(path),
        isReadOnly = fs.isReadOnly(path),
        created = 0,
        modified = 0
    }
end end
local openModes = {[0] = "r", "w", "r", "a", "rb", "wb", "rb", "ab"}
local localEvents = {key = true, key_up = true, char = true, mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true, mouse_move = true, term_resize = true, paste = true}

if not string.pack then minver "1.91.0" end

--- Creates a new server window object with the specified properties.
-- This object functions like an object from the window API, and can be used as
-- a redirection target. It also has a few additional functions to control the
-- client and connection.
-- @param delegate The delegate object. This must have two methods named
-- `:send(data)` and `:receive()`, and may additionally have a `:close()` method
-- that's called when the server is closed. Every method is called with the `:`
-- operator, meaning its first argument is the delegate object itself.
-- @param width The width of the new window.
-- @param height The height of the new window.
-- @param id The ID of the window. Multiple window IDs can be sent over one
-- connection. This defaults to 0.
-- @param title The title of the window. This defaults to "CraftOS Raw Terminal".
-- @param parent The parent window to draw to. This allows rendering on both the
-- screen and a remote terminal. If unspecified, output will only be sent to the
-- remote terminal.
-- @param x If parent is specified, the X coordinate to start at. This defaults to 1.
-- @param y If parent is specified, the Y coordinate to start at. This defaults to 1.
-- @param blockFSAccess Set this to true to disable filesystem access for clients.
-- @param isMonitor Whether the terminal identifies as a monitor.
-- @return The new window object.
function rawterm.server(delegate, width, height, id, title, parent, x, y, blockFSAccess, isMonitor)
    expect(1, delegate, "table")
    expect(2, width, "number")
    expect(3, height, "number")
    expect(4, id, "number", "nil")
    expect(5, title, "string", "nil")
    expect(6, parent, "table", "nil")
    expect(7, x, "number", "nil")
    expect(8, y, "number", "nil")
    expect.field(delegate, "send", "function")
    expect.field(delegate, "receive", "function")
    expect.field(delegate, "close", "function", "nil")
    title = title or "CraftOS Raw Terminal"
    x = x or 1
    y = y or 1

    local win, mode, cursorX, cursorY, current_colors, visible, canBlink, isClosed, changed = {}, 0, 1, 1, 0xF0, true, false, false, true
    local screen, colors, pixels, palette, fileHandles = {}, {}, {}, {}, {}
    local flags = delegate.flags or {
        isVersion11 = false,
        filesystem = false,
        binaryChecksum = false
    }
    delegate.flags = flags
    for i = 1, height do screen[i], colors[i] = (" "):rep(width), ("\xF0"):rep(width) end
    for i = 1, height*9 do pixels[i] = ("\x0F"):rep(width*6) end
    for i = 0, 15 do palette[i] = {(parent or term).getPaletteColor(2^i)} end
    for i = 16, 255 do palette[i] = {0, 0, 0} end

    local function makePacket(type, id, data)
        local payload = base64encode(string.char(type) .. string.char(id or 0) .. data)
        local d
        if #payload > 65535 and flags.isVersion11 then d = "!CPD" .. string.format("%012X", #payload)
        else d = "!CPC" .. string.format("%04X", #payload) end
        d = d .. payload
        if flags.binaryChecksum and id ~= 6 then d = d .. ("%08X"):format(crc32(string.char(type) .. string.char(id or 0) .. data))
        else d = d .. ("%08X"):format(crc32(payload)) end
        return d .. "\n"
    end

    -- Term functions

    function win.write(text)
        text = tostring(text)
        expect(1, text, "string")
        if cursorY < 1 or cursorY > height then return
        elseif cursorX > width or cursorX + #text < 1 then
            cursorX = cursorX + #text
            return
        elseif cursorX < 1 then
            text = text:sub(-cursorX + 2)
            cursorX = 1
        end
        local ntext = #text
        if cursorX + #text > width then text = text:sub(1, width - cursorX + 1) end
        screen[cursorY] = screen[cursorY]:sub(1, cursorX - 1) .. text .. screen[cursorY]:sub(cursorX + #text)
        colors[cursorY] = colors[cursorY]:sub(1, cursorX - 1) .. string.char(current_colors):rep(#text) .. colors[cursorY]:sub(cursorX + #text)
        cursorX = cursorX + ntext
        changed = true
        win.redraw()
    end

    function win.blit(text, fg, bg)
        text = tostring(text)
        expect(1, text, "string")
        expect(2, fg, "string")
        expect(3, bg, "string")
        if #text ~= #fg or #fg ~= #bg then error("Arguments must be the same length", 2) end
        if cursorY < 1 or cursorY > height then return
        elseif cursorX > width or cursorX < 1 - #text then
            cursorX = cursorX + #text
            win.redraw()
            return
        elseif cursorX < 1 then
            text, fg, bg = text:sub(-cursorX + 2), fg:sub(-cursorX + 2), bg:sub(-cursorX + 2)
            cursorX = 1
            win.redraw()
        end
        local ntext = #text
        if cursorX + #text > width then text, fg, bg = text:sub(1, width - cursorX + 1), fg:sub(1, width - cursorX + 1), bg:sub(1, width - cursorX + 1) end
        local col = ""
        for i = 1, #text do col = col .. string.char((tonumber(bg:sub(i, i), 16) or 0) * 16 + (tonumber(fg:sub(i, i), 16) or 0)) end
        screen[cursorY] = screen[cursorY]:sub(1, cursorX - 1) .. text .. screen[cursorY]:sub(cursorX + #text)
        colors[cursorY] = colors[cursorY]:sub(1, cursorX - 1) .. col .. colors[cursorY]:sub(cursorX + #text)
        cursorX = cursorX + ntext
        changed = true
        win.redraw()
    end

    function win.clear()
        if mode == 0 then
            for i = 1, height do screen[i], colors[i] = (" "):rep(width), string.char(current_colors):rep(width) end
        else
            for i = 1, height*9 do pixels[i] = ("\x0F"):rep(width*6) end
        end
        changed = true
        win.redraw()
    end

    function win.clearLine()
        if cursorY >= 1 and cursorY <= height then
            screen[cursorY], colors[cursorY] = (" "):rep(width), string.char(current_colors):rep(width)
            changed = true
            win.redraw()
        end
    end

    function win.getCursorPos()
        return cursorX, cursorY
    end

    function win.setCursorPos(cx, cy)
        expect(1, cx, "number")
        expect(2, cy, "number")
        cx, cy = math.floor(cx), math.floor(cy)
        if cx == cursorX and cy == cursorY then return end
        cursorX, cursorY = cx, cy
        changed = true
        win.redraw()
    end

    function win.getCursorBlink()
        return canBlink
    end

    function win.setCursorBlink(b)
        expect(1, b, "boolean")
        canBlink = b
        if parent then parent.setCursorBlink(b) end
        win.redraw()
    end

    function win.isColor()
        if parent then return parent.isColor() end
        return true
    end

    function win.getSize(m)
        if (type(m) == "number" and m > 1) or (type(m) == "boolean" and m == true) then return width * 6, height * 9
        else return width, height end
    end

    function win.scroll(lines)
        expect(1, lines, "number")
        if math.abs(lines) >= width then
            for i = 1, height do screen[i], colors[i] = (" "):rep(width), string.char(current_colors):rep(width) end
        elseif lines > 0 then
            for i = lines + 1, height do screen[i - lines], colors[i - lines] = screen[i], colors[i] end
            for i = height - lines + 1, height do screen[i], colors[i] = (" "):rep(width), string.char(current_colors):rep(width) end
        elseif lines < 0 then
            for i = 1, height + lines do screen[i - lines], colors[i - lines] = screen[i], colors[i] end
            for i = 1, -lines do screen[i], colors[i] = (" "):rep(width), string.char(current_colors):rep(width) end
        else return end
        changed = true
        win.redraw()
    end

    function win.getTextColor()
        return 2^bit32.band(current_colors, 0x0F)
    end

    function win.setTextColor(color)
        expect(1, color, "number")
        current_colors = bit32.band(current_colors, 0xF0) + bit32.band(math.floor(math.log(color, 2)), 0x0F)
    end

    function win.getBackgroundColor()
        return 2^bit32.rshift(current_colors, 4)
    end

    function win.setBackgroundColor(color)
        expect(1, color, "number")
        current_colors = bit32.band(current_colors, 0x0F) + bit32.band(math.floor(math.log(color, 2)), 0x0F) * 16
    end

    function win.getPaletteColor(color)
        expect(1, color, "number")
        if mode == 2 then if color < 0 or color > 255 then error("bad argument #1 (value out of range)", 2) end
        else color = bit32.band(math.floor(math.log(color, 2)), 0x0F) end
        return table.unpack(palette[color])
    end

    function win.setPaletteColor(color, r, g, b)
        expect(1, color, "number")
        expect(2, r, "number")
        expect(3, g, "number")
        expect(4, b, "number")
        if r < 0 or r > 1 then error("bad argument #2 (value out of range)", 2) end
        if g < 0 or g > 1 then error("bad argument #3 (value out of range)", 2) end
        if b < 0 or b > 1 then error("bad argument #4 (value out of range)", 2) end
        if mode == 2 then if color < 0 or color > 255 then error("bad argument #1 (value out of range)", 2) end
        else color = bit32.band(math.floor(math.log(color, 2)), 0x0F) end
        palette[color] = {r, g, b}
        changed = true
        win.redraw()
    end

    -- Graphics functions

    function win.getGraphicsMode()
        if mode == 0 then return false
        else return mode end
    end

    function win.setGraphicsMode(m)
        expect(1, m, "boolean", "number")
        local om = mode
        if m == false then mode = 0
        elseif m == true then mode = 1
        elseif m >= 0 and m <= 2 then mode = math.floor(m)
        else error("bad argument #1 (invalid mode)", 2) end
        if mode ~= om then changed = true win.redraw() end
    end

    function win.getPixel(px, py)
        expect(1, px, "number")
        expect(2, py, "number")
        if px < 0 or px >= width * 6 or py < 0 or py >= height * 9 then return nil end
        local c = pixels[py + 1]:byte(px + 1, px + 1)
        return mode == 2 and c or 2^c
    end

    function win.setPixel(px, py, color)
        expect(1, px, "number")
        expect(2, py, "number")
        expect(3, color, "number")
        if px < 0 or px >= width * 6 or py < 0 or py >= height * 9 then return nil end
        if mode == 2 then if color < 0 or color > 255 then error("bad argument #3 (value out of range)", 2) end
        else color = bit32.band(math.floor(math.log(color, 2)), 0x0F) end
        pixels[py + 1] = pixels[py + 1]:sub(1, px) .. string.char(color) .. pixels[py + 1]:sub(px + 2)
        changed = true
        win.redraw()
    end

    function win.drawPixels(px, py, pix, pw, ph)
        expect(1, px, "number")
        expect(2, py, "number")
        expect(3, pix, "table", "number")
        expect(4, pw, "number", type(pix) ~= "number" and "nil" or nil)
        expect(5, ph, "number", type(pix) ~= "number" and "nil" or nil)
        if type(pix) == "number" then
            if mode == 2 then if pix < 0 or pix > 255 then error("bad argument #3 (value out of range)", 2) end
            else pix = bit32.band(math.floor(math.log(pix, 2)), 0x0F) end
            for cy = py + 1, py + ph do pixels[cy] = pixels[cy]:sub(1, px) .. string.char(pix):rep(pw) .. pixels[cy]:sub(px + pw + 1) end
        else
            for cy = py + 1, py + (ph or #pix) do
                local row = pix[cy - py]
                if row and pixels[cy] then
                    if type(row) == "string" then
                        pixels[cy] = pixels[cy]:sub(1, px) .. row:sub(1, pw or -1) .. pixels[cy]:sub(px + (pw or #row) + 1)
                    elseif type(row) == "table" then
                        local str = ""
                        for cx = 1, pw or #row do str = str .. string.char(row[cx] or pixels[cy]:byte(px + cx)) end
                        pixels[cy] = pixels[cy]:sub(1, px) .. str .. pixels[cy]:sub(px + #str + 1)
                    end
                end
            end
        end
        changed = true
        win.redraw()
    end

    function win.getPixels(px, py, pw, ph, str)
        expect(1, px, "number")
        expect(2, py, "number")
        expect(3, pw, "number")
        expect(4, ph, "number")
        expect(5, str, "boolean", "nil")
        local retval = {}
        for cy = py + 1, py + ph do
            if pixels[cy] then if str then retval[cy - py] = pixels[cy]:sub(px + 1, px + pw) else
                retval[cy - py] = {pixels[cy]:byte(px + 1, px + pw)}
                if mode < 2 then for i = 1, pw do retval[cy - py][i] = 2^retval[cy - py][i] end end
            end end
        end
        return retval
    end

    win.isColour = win.isColor
    win.getTextColour = win.getTextColor
    win.setTextColour = win.setTextColor
    win.getBackgroundColour = win.getBackgroundColor
    win.setBackgroundColour = win.setBackgroundColor
    win.getPaletteColour = win.getPaletteColor
    win.setPaletteColour = win.setPaletteColor

    -- Window functions

    function win.getLine(cy)
        if cy < 1 or cy > height then return nil end
        local fg, bg = "", ""
        for c in colors[cy]:gmatch "." do
            fg, bg = fg .. ("%x"):format(bit32.band(c:byte(), 0x0F)), bg .. ("%x"):format(bit32.rshift(c:byte(), 4))
        end
        return screen[cy], fg, bg
    end

    function win.isVisible()
        return visible
    end

    function win.setVisible(v)
        expect(1, v, "boolean")
        visible = v
        win.redraw()
    end

    function win.redraw()
        if visible and changed then
            -- Draw to parent screen
            if parent then
                -- This is NOT efficient, but it's not really supposed to be anyway.
                if parent.getGraphicsMode and (parent.getGraphicsMode() or 0) ~= mode then parent.setGraphicsMode(mode) end
                if mode == 0 then
                    local b = parent.getCursorBlink()
                    parent.setCursorBlink(false)
                    for cy = 1, height do
                        parent.setCursorPos(x, y + cy - 1)
                        parent.blit(win.getLine(cy))
                    end
                    parent.setCursorBlink(b)
                    win.restoreCursor()
                elseif parent.drawPixels then
                    parent.drawPixels((x - 1) * 6, (y - 1) * 9, pixels, width, height)
                end
                for i = 0, (parent.getGraphicsMode and mode == 2 and 255 or 15) do parent.setPaletteColor(2^i, table.unpack(palette[i])) end
            end
            -- Draw to raw target
            if not isClosed then
                local rleText = ""
                if mode == 0 then
                    local c, n = screen[1]:sub(1, 1), 0
                    for cy = 1, height do
                        for ch in screen[cy]:gmatch "." do
                            if ch ~= c or n == 255 then
                                rleText = rleText .. c .. string.char(n)
                                c, n = ch, 0
                            end
                            n=n+1
                        end
                    end
                    if n > 0 then rleText = rleText .. c .. string.char(n) end
                    c, n = colors[1]:sub(1, 1), 0
                    for cy = 1, height do
                        for ch in colors[cy]:gmatch "." do
                            if ch ~= c or n == 255 then
                                rleText = rleText .. c .. string.char(n)
                                c, n = ch, 0
                            end
                            n=n+1
                        end
                    end
                    if n > 0 then rleText = rleText .. c .. string.char(n) end
                else
                    local c, n = pixels[1]:sub(1, 1), 0
                    for cy = 1, height * 9 do
                        for ch in pixels[cy]:gmatch "." do
                            if ch ~= c or n == 255 then
                                rleText = rleText .. c .. string.char(n)
                                c, n = ch, 0
                            end
                            n=n+1
                        end
                    end
                end
                for i = 0, (mode == 2 and 255 or 15) do rleText = rleText .. string.char(palette[i][1] * 255) .. string.char(palette[i][2] * 255) .. string.char(palette[i][3] * 255) end
                delegate:send(makePacket(0, id, string.pack("<BBHHHHBxxx", mode, canBlink and 1 or 0, width, height, math.min(math.max(cursorX - 1, 0), 0xFFFFFFFF), math.min(math.max(cursorY - 1, 0), 0xFFFFFFFF), parent and (parent.isColor() and 0 or 1) or 0) .. rleText))
            end
            changed = false
        end
    end

    function win.restoreCursor()
        if parent then parent.setCursorPos(x + cursorX - 1, y + cursorY - 1) end
    end

    function win.getPosition()
        return x, y
    end

    function win.reposition(nx, ny, nwidth, nheight, nparent)
        expect(1, nx, "number", "nil")
        expect(2, ny, "number", "nil")
        expect(3, nwidth, "number", "nil")
        expect(4, nheight, "number", "nil")
        expect(5, nparent, "table", "nil")
        x, y, parent = nx or x, ny or y, nparent or parent
        local resized = (nwidth and nwidth ~= width) or (nheight and nheight ~= height)
        if nwidth then
            if nwidth < width then
                for cy = 1, height do
                    screen[cy], colors[cy] = screen[cy]:sub(1, nwidth), colors[cy]:sub(1, nwidth)
                    for i = 1, 9 do pixels[(cy - 1)*9 + i] = pixels[(cy - 1)*9 + i]:sub(1, nwidth * 6) end
                end
            elseif nwidth > width then
                for cy = 1, height do
                    screen[cy], colors[cy] = screen[cy] .. (" "):rep(nwidth - width), colors[cy] .. string.char(current_colors):rep(nwidth - width)
                    for i = 1, 9 do pixels[(cy - 1)*9 + i] = pixels[(cy - 1)*9 + i] .. ("\x0F"):rep((nwidth - width) * 6) end
                end
            end
            width = nwidth
        end
        if nheight then
            if nheight < height then
                for cy = nheight + 1, height do
                    screen[cy], colors[cy] = nil
                    for i = 1, 9 do pixels[(cy - 1)*9 + i] = nil end
                end
            elseif nheight > height then
                for cy = height + 1, nheight do
                    screen[cy], colors[cy] = (" "):rep(width), string.char(current_colors):rep(width)
                    for i = 1, 9 do pixels[(cy - 1)*9 + i] = ("\x0F"):rep(width * 6) end
                end
            end
            height = nheight
        end
        if resized and not isClosed then delegate:send(makePacket(4, id, string.pack("<BBHHz", 0, isMonitor and 0 or os.computerID() % 256, width, height, title))) end
        changed = true
        win.redraw()
    end

    -- Monitor functions (if available)
    if parent.setTextScale then
        function win.getTextScale()
            return parent.getTextScale()
        end

        function win.setTextScale(scale)
            expect(1, scale, "number")
            parent.setTextScale(scale)
            width, height = parent.getSize()
            if resized and not isClosed then delegate:send(makePacket(4, id, string.pack("<BBHHz", 0, isMonitor and 0 or os.computerID() % 256, width, height, title))) end
        end
    end

    -- Raw functions

    --- A wrapper for os.pullEvent() that also listens for raw events, and returns
    -- them if found.
    -- @param filter A filter for the event.
    -- @param ignoreLocalEvents Set this to a truthy value to ignore receiving
    -- input events from the local computer, making the terminal otherwise
    -- isolated from the rest of the system.
    -- @param ignoreAllEvents Set this to a truthy value to ignore all local events.
    -- @return The event name and arguments.
    function win.pullEvent(filter, ignoreLocalEvents, ignoreAllEvents)
        expect(1, filter, "string", "nil")
        local ev
        parallel.waitForAny(function()
            if isClosed then while true do coroutine.yield() end end
            while true do
                local msg = delegate:receive()
                if not msg then
                    isClosed = true
                    error("Connection closed")
                end
                if msg:sub(1, 3) == "!CP" then
                    local off = 8
                    if msg:sub(4, 4) == 'D' then off = 16 end
                    local size = tonumber(msg:sub(5, off), 16)
                    local payload = msg:sub(off + 1, off + size)
                    local expected = tonumber(msg:sub(off + size + 1, off + size + 8), 16)
                    local data = base64decode(payload)
                    local typ, wid = data:byte(1, 2)
                    if crc32(flags.binaryChecksum and data or payload) == expected then
                        if wid == id then
                            if typ == 1 then
                                local ch, flags = data:byte(3, 4)
                                if bit32.btest(flags, 8) then ev = {"char", string.char(ch)}
                                elseif not bit32.btest(flags, 1) then ev = {"key", keymap[ch], bit32.btest(flags, 2)}
                                else ev = {"key_up", keymap[ch]} end
                                if not filter or ev[1] == filter then return else ev = nil end
                            elseif typ == 2 then
                                local evt, button, mx, my = string.unpack("<BBII", data, 3)
                                ev = {mouse_events[evt], evt == 2 and button * 2 - 1 or button, mx, my}
                                if not filter or ev[1] == filter then return else ev = nil end
                            elseif typ == 3 then
                                local nparam, name = string.unpack("<Bz", data, 3)
                                ev = {name}
                                local pos = #name + 5
                                for i = 2, nparam + 1 do ev[i], pos = decodeIBT(data, pos) end
                                if not filter or ev[1] == filter then return else ev = nil end
                            elseif typ == 4 then
                                local flags, _, w, h = string.unpack("<BBHH", data, 3)
                                if flags == 0 then
                                    if w ~= 0 and h ~= 0 then
                                        win.reposition(nil, nil, w, h, nil)
                                        ev = {"term_resize"}
                                    end
                                elseif flags == 1 or flags == 2 then
                                    win.close()
                                    ev = {"win_close"}
                                end
                                if not filter or ev[1] == filter then return else ev = nil end
                            elseif typ == 7 and flags.filesystem then
                                local reqtype, reqid, path, path2 = string.unpack("<BBz", data, 3)
                                if reqtype == 12 or reqtype == 13 then path2 = string.unpack("<z", data, path2) else path2 = nil end
                                if bit32.band(reqtype, 0xF0) == 0 then
                                    local ok, val = pcall(fsFunctions[reqtype], path, path2)
                                    if ok then
                                        if type(val) == "boolean" then delegate:send(makePacket(8, id, string.pack("<BBB", reqtype, reqid, val and 1 or 0)))
                                        elseif type(val) == "number" then delegate:send(makePacket(8, id, string.pack("<BBI4", reqtype, reqid, val)))
                                        elseif type(val) == "string" then delegate:send(makePacket(8, id, string.pack("<BBz", reqtype, reqid, val)))
                                        elseif reqtype == 8 then
                                            if val then delegate:send(makePacket(8, id, string.pack("<BBI4I8I8BBBB", reqtype, reqid, val.size, val.created or 0, val.modified or val.modification or 0, val.isDir and 1 or 0, val.isReadOnly and 1 or 0, 0, 0)))
                                            else delegate:send(makePacket(8, id, string.pack("<BBI4I8I8BBBB", reqtype, reqid, 0, 0, 0, 0, 0, 1, 0))) end
                                        elseif type(val) == "table" then
                                            local list = ""
                                            for i = 1, #val do list = list .. val[i] .. "\0" end
                                            delegate:send(makePacket(8, id, string.pack("<BBI4", reqtype, reqid, #val) .. list))
                                        else delegate:send(makePacket(8, id, string.pack("<BBB", reqtype, reqid, 0))) end
                                    else
                                        if reqtype == 0 or reqtype == 1 or reqtype == 2 then delegate:send(makePacket(8, id, string.pack("<BBB", reqtype, reqid, 2)))
                                        elseif reqtype == 3 or reqtype == 5 or reqtype == 6 then delegate:send(makePacket(8, id, string.pack("<BBI4", reqtype, reqid, 0xFFFFFFFF)))
                                        elseif reqtype == 4 or reqtype == 7 or reqtype == 9 then delegate:send(makePacket(8, id, string.pack("<BBz", reqtype, reqid, "")))
                                        elseif reqtype == 8 then delegate:send(makePacket(8, id, string.pack("<BBI4I8I8BBBB", reqtype, reqid, 0, 0, 0, 0, 0, 2, 0)))
                                        else delegate:send(makePacket(8, id, string.pack("<BBz", reqtype, reqid, val))) end
                                    end
                                elseif bit32.band(reqtype, 0xF0) == 0x10 then
                                    local file, err = fs.open(path, openModes[bit32.band(reqtype, 7)])
                                    if file then
                                        if bit32.btest(reqtype, 1) then fileHandles[reqid] = file else
                                            delegate:send(makePacket(9, id, string.pack("<BBs4", 0, reqid, file.readAll() or "")))
                                            file.close()
                                        end
                                    else
                                        if bit32.btest(reqtype, 1) then delegate:send(makePacket(8, id, string.pack("<BBz", reqtype, reqid, err)))
                                        else delegate:send(makePacket(9, id, string.pack("<BBs4", 1, reqid, err))) end
                                    end
                                end
                            elseif typ == 9 and flags.filesystem then
                                local _, reqid, size = string.unpack("<BBI4", data, 3)
                                local str = data:sub(9, size + 8)
                                if fileHandles[reqid] ~= nil then
                                    fileHandles[reqid].write(str)
                                    fileHandles[reqid].close()
                                    fileHandles[reqid] = nil
                                    delegate:send(makePacket(8, id, string.pack("<BBB", 17, reqid, 0)))
                                else delegate:send(makePacket(8, id, string.pack("<BBz", 17, reqid, "Unknown request ID"))) end
                            end
                        end
                    end
                    if typ == 6 then
                        flags.isVersion11 = true
                        local f = string.unpack("<H", data, 3)
                        if wid == id then delegate:send(makePacket(6, wid, string.pack("<H", 1 + (blockFSAccess and 0 or 2)))) end
                        if bit32.btest(f, 0x01) then flags.binaryChecksum = true end
                        if bit32.btest(f, 0x02) and not blockFSAccess then flags.filesystem = true end
                        if bit32.btest(f, 0x04) then delegate:send(makePacket(4, id, string.pack("<BBHHz", 0, isMonitor and 0 or os.computerID() % 256, width, height, title))) changed = true end
                    end
                end
            end
        end, function()
            if ignoreAllEvents then while true do coroutine.yield() end end
            repeat
                ev = nil
                ev = table.pack(os.pullEventRaw(filter))
            until not ignoreLocalEvents or not localEvents[ev[1]]
        end)
        return table.unpack(ev, 1, ev.n or #ev)
    end

    --- Sets the window's title and sends a message to the client.
    -- @param t The new title of the window.
    function win.setTitle(t)
        expect(1, title, "string")
        title = t
        if isClosed then return end
        delegate:send(makePacket(4, id, string.pack("<BBHHz", 0, isMonitor and 0 or os.computerID() % 256, width, height, title)))
    end

    --- Sends a message to the client.
    -- @param type Either "error", "warning", or "info" to specify an icon to show.
    -- @param title The title of the message.
    -- @param message The message to display.
    function win.sendMessage(type, title, message)
        expect(1, title, "string")
        expect(2, message, "string")
        expect(3, type, "string", "nil")
        if isClosed then return end
        local flags = 0
        if type == "error" then type = 0x10
        elseif type == "warning" then type = 0x20
        elseif type == "info" then type = 0x40
        elseif type then error("bad argument #3 (invalid type '" .. type .. "')", 2) end
        delegate:send(makePacket(5, id, string.pack("<Izz", flags, title, message)))
    end

    --- Closes the window connection. Any changes made to the screen will still
    -- show on the parent window if defined.
    function win.close(keepAlive)
        if isClosed then return end
        delegate:send(makePacket(4, id, string.pack("<BBHHz", keepAlive and 1 or 2, 0, 0, 0, "")))
        if delegate.close and not keepAlive then delegate:close() end
        isClosed = true
    end

    if parent then for k, v in pairs(parent) do if win[k] == nil then win[k] = v end end end
    delegate:send(makePacket(4, id, string.pack("<BBHHz", 0, isMonitor and 0 or os.computerID() % 256, width, height, title)))

    return win
end

--- Creates a new client handle that listens for the specified window ID, and
-- renders to a window.
-- @param delegate The delegate object. This must have two methods named
-- `:send(data)` and `:receive()`, and may additionally have a `:close()` method
-- that's called when the server is closed. It may also have `:setTitle(title)`
-- to set the title of the window, `:showMessage(type, title, message)` to show
-- a message on the screen (type may be `error`, `warning`, or `info`), and
-- `:windowNotification(id, width, height, title)` which is called when an
-- unknown window ID gets a window update (this may be used to discover new
-- window alerts from the server). Every method is called with the `:` operator,
-- meaning its first argument is the delegate object itself.
-- @param id The ID of the window to listen for. (If in doubt, use 0.)
-- @param window The window to render to.
-- @return The new client handle.
function rawterm.client(delegate, id, window)
    expect(1, delegate, "table")
    expect(2, id, "number")
    expect(3, window, "table", "nil")
    expect.field(delegate, "send", "function")
    expect.field(delegate, "receive", "function")
    expect.field(delegate, "close", "function", "nil")
    expect.field(delegate, "setTitle", "function", "nil")
    expect.field(delegate, "showMessage", "function", "nil")
    expect.field(delegate, "windowNotification", "function", "nil")

    local handle = {}
    local flags = {
        isVersion11 = false,
        binaryChecksum = false,
        filesystem = false
    }
    local isClosed = false
    local nextFSID = 0

    local function makePacket(type, id, data)
        local payload = base64encode(string.char(type) .. string.char(id or 0) .. data)
        local d
        if #data > 65535 and flags.isVersion11 then d = "!CPD" .. string.format("%012X", #payload)
        else d = "!CPC" .. string.format("%04X", #payload) end
        d = d .. payload
        if flags.binaryChecksum then d = d .. ("%08X"):format(crc32(string.char(type) .. string.char(id or 0) .. data))
        else d = d .. ("%08X"):format(crc32(payload)) end
        return d .. "\n"
    end

    local function makeFSFunction(fid, type, p2)
        local f = function(path, path2)
            expect(1, path, "string")
            if p2 then expect(2, path, "string") end
            local n = nextFSID
            delegate:send(makePacket(7, id, string.pack(p2 and "<BBzz" or "<BBz", fid, n, path, path2)))
            nextFSID = (nextFSID + 1) % 256
            local data
            while not data or data:byte(4) ~= n do data = handle.update(delegate:receive()) end
            if type == "nil" then
                local v = string.unpack("z", data, 5)
                if v ~= "" then error(v, 2)
                else return end
            elseif type == "boolean" then
                local v = data:byte(5)
                if v == 2 then error("Failure", 2)
                else return v ~= 0 end
            elseif type == "number" then
                local v = string.unpack("<I4", data, 5)
                if v == 0xFFFFFFFF then error("Failure", 2)
                else return v end
            elseif type == "string" then
                local v = string.unpack("<I4", data, 5)
                if v == "" then error("Failure", 2)
                else return v end
            elseif type == "table" then
                local size = string.unpack("<I4", data, 5)
                if size == 0xFFFFFFFF then error("Failure", 2) end
                local retval, pos = {}, 9
                for i = 1, size do retval[i], pos = string.unpack("z", data, pos) end
                return retval
            elseif type == "attributes" then
                local attr, err = {}
                attr.size, attr.created, attr.modified, attr.isDir, attr.isReadOnly, err = string.unpack("<I4I8I8BBB", data, 5)
                if err == 1 then return nil
                elseif err == 2 then error("Failure", 2)
                else return attr end
            end
        end
        if p2 then return f else return function(path) return f(path) end end
    end

    local fsHandle = {
        exists = makeFSFunction(0, "boolean"),
        isDir = makeFSFunction(1, "boolean"),
        isReadOnly = makeFSFunction(2, "boolean"),
        getSize = makeFSFunction(3, "number"),
        getDrive = makeFSFunction(4, "string"),
        getCapacity = makeFSFunction(5, "number"),
        getFreeSpace = makeFSFunction(6, "number"),
        list = makeFSFunction(7, "table"),
        attributes = makeFSFunction(8, "attributes"),
        find = makeFSFunction(9, "table"),
        makeDir = makeFSFunction(10, "nil"),
        delete = makeFSFunction(11, "nil"),
        copy = makeFSFunction(12, "nil", true),
        move = makeFSFunction(13, "nil", true),
        open = function(path, mode)
            expect(1, path, "string")
            expect(2, mode, "string")
            local m
            for i = 0, 7 do if openModes[i] == mode then m = i break end end
            if not m then error("Invalid mode", 2) end
            if bit32.btest(m, 1) then
                local buf, closed = "", false
                return {
                    write = function(d)
                        if closed then error("attempt to use closed file", 2) end
                        if bit32.btest(m, 4) and type(d) == "number" then buf = buf .. string.char(d)
                        else buf = buf .. tostring(d) end
                    end,
                    writeLine = function(d)
                        if closed then error("attempt to use closed file", 2) end
                        buf = buf .. tostring(d) .. "\n"
                    end,
                    flush = function()
                        if closed then error("attempt to use closed file", 2) end
                        local n = nextFSID
                        delegate:send(makePacket(7, id, string.pack("<BBz", 16 + m, n, path)))
                        delegate:send(makePacket(9, id, string.pack("<BBs4", 0, n, buf)))
                        nextFSID = (nextFSID + 1) % 256
                        buf, m = "", bit32.bor(m, 2)
                        local d
                        while not d or d:byte(4) ~= n do d = handle.update(delegate:receive()) end
                        local v = string.unpack("z", d, 5)
                        if v ~= "" then error(v, 2) end
                    end,
                    close = function()
                        if closed then error("attempt to use closed file", 2) end
                        closed = true
                        local n = nextFSID
                        delegate:send(makePacket(7, id, string.pack("<BBz", 16 + m, n, path)))
                        delegate:send(makePacket(9, id, string.pack("<BBs4", 0, n, buf)))
                        nextFSID = (nextFSID + 1) % 256
                        buf, m = "", bit32.bor(m, 2)
                        local d
                        while not d or d:byte(4) ~= n do d = handle.update(delegate:receive()) end
                        local v = string.unpack("z", d, 5)
                        if v ~= "" then error(v, 2) end
                    end
                }
            else
                local n = nextFSID
                delegate:send(makePacket(7, id, string.pack("<BBz", 16 + m, n, path)))
                nextFSID = (nextFSID + 1) % 256
                local d
                while not d or d:byte(4) ~= n do d = handle.update(delegate:receive()) end
                local size = string.unpack("<I4", d, 5)
                local data = d:sub(9, 8 + size)
                if d:byte(3) ~= 0 then return nil, data end
                local pos, closed = 1, false
                return {
                    read = function(n)
                        expect(1, n, "number", "nil")
                        if closed then error("attempt to use closed file", 2) end
                        if pos >= #data then return nil end
                        if n == nil then
                            if bit32.btest(m, 4) then
                                pos = pos + 1
                                return data:byte(pos - 1)
                            else n = 1 end
                        end
                        pos = pos + n
                        return data:sub(pos - n, pos - 1)
                    end,
                    readLine = function(strip)
                        if closed then error("attempt to use closed file", 2) end
                        if pos >= #data then return nil end
                        local oldpos, line = pos
                        line, pos = data:match("([^\n]" .. (strip and "+)\n" or "*\n)").."()", pos)
                        if not pos then
                            line = data:sub(pos)
                            pos = #data
                        end
                        return line
                    end,
                    readAll = function()
                        if closed then error("attempt to use closed file", 2) end
                        if pos >= #data then return nil end
                        local d = data:sub(pos)
                        pos = #data
                        return d
                    end,
                    close = function()
                        if closed then error("attempt to use closed file", 2) end
                        closed = true
                    end,
                    seek = bit32.btest(m, 4) and function(whence, offset)
                        expect(1, whence, "string", "nil")
                        expect(2, offset, "number", "nil")
                        whence = whence or "cur"
                        offset = offset or 0
                        if closed then error("attempt to use closed file", 2) end
                        if whence == "set" then pos = offset
                        elseif whence == "cur" then pos = pos + offset
                        elseif whence == "end" then pos = #data - offset
                        else error("Invalid whence", 2) end
                        return pos
                    end or nil
                }
            end
        end
    }

    --- Updates the window with the raw message provided.
    -- @param message A raw message to parse.
    function handle.update(message)
        expect(1, message, "string")
        if message:sub(1, 3) == "!CP" then
            local off = 8
            if message:sub(4, 4) == 'D' then off = 16 end
            local size = tonumber(message:sub(5, off), 16)
            local payload = message:sub(off + 1, off + size)
            local expected = tonumber(message:sub(off + size + 1, off + size + 8), 16)
            local data = base64decode(payload)
            if crc32(flags.binaryChecksum and data or payload) == expected then
                local typ, wid = data:byte(1, 2)
                if wid == id then
                    if typ == 0 and window then
                        local mode, blink, width, height, cursorX, cursorY, grayscale = string.unpack("<BBHHHHB", data, 3)
                        local c, n, pos = string.unpack("c1B", data, 17)
                        window.setCursorBlink(false)
                        if window.setVisible then window.setVisible(false) end
                        if window.getGraphicsMode and window.getGraphicsMode() ~= mode then window.setGraphicsMode(mode) end
                        window.clear()
                        -- These RLE routines could probably be optimized with string.rep.
                        if mode == 0 then
                            local text = {}
                            for y = 1, height do
                                text[y] = ""
                                for x = 1, width do
                                    text[y] = text[y] .. c
                                    n = n - 1
                                    if n == 0 then c, n, pos = string.unpack("c1B", data, pos) end
                                end
                            end
                            c = c:byte()
                            for y = 1, height do
                                local fg, bg = "", ""
                                for x = 1, width do
                                    fg, bg = fg .. ("%x"):format(bit32.band(c, 0x0F)), bg .. ("%x"):format(bit32.rshift(c, 4))
                                    n = n - 1
                                    if n == 0 then c, n, pos = string.unpack("BB", data, pos) end
                                end
                                window.setCursorPos(1, y)
                                window.blit(text[y], fg, bg)
                            end
                        else
                            local pixels = {}
                            for y = 1, height * 9 do
                                pixels[y] = ""
                                for x = 1, width * 6 do
                                    pixels[y] = pixels[y] .. c
                                    n = n - 1
                                    if n == 0 then c, n, pos = string.unpack("c1B", data, pos) end
                                end
                            end
                            if window.drawPixels then window.drawPixels(0, 0, pixels) end
                        end
                        pos = pos - 2
                        local r, g, b
                        if mode ~= 2 then
                            for i = 0, 15 do
                                r, g, b, pos = string.unpack("BBB", data, pos)
                                window.setPaletteColor(2^i, r / 255, g / 255, b / 255)
                            end
                        else
                            for i = 0, 255 do
                                r, g, b, pos = string.unpack("BBB", data, pos)
                                window.setPaletteColor(i, r / 255, g / 255, b / 255)
                            end
                        end
                        window.setCursorBlink(blink ~= 0)
                        window.setCursorPos(cursorX + 1, cursorY + 1)
                        if window.setVisible then window.setVisible(true) end
                    elseif typ == 4 then
                        local flags, _, w, h, title = string.unpack("<BBHHz", data, 3)
                        if flags == 0 then
                            if w ~= 0 and h ~= 0 and window and window.reposition then
                                local x, y = window.getPosition()
                                window.reposition(x, y, w, h)
                            end
                            if delegate.setTitle then delegate:setTitle(title) end
                        elseif flags == 1 or flags == 2 then
                            if not isClosed then
                                delegate:send("\n")
                                if delegate.close then delegate:close() end
                                isClosed = true
                            end
                        end
                    elseif typ == 5 then
                        local flags, title, msg = string.unpack("<Izz", data, 3)
                        local mtyp
                        if bit32.btest(flags, 0x10) then mtyp = "error"
                        elseif bit32.btest(flags, 0x20) then mtyp = "warning"
                        elseif bit32.btest(flags, 0x40) then mtyp = "info" end
                        if delegate.showMessage then delegate:showMessage(mtyp, title, msg) end
                    elseif typ == 8 or typ == 9 then
                        return data
                    end
                elseif typ == 4 then
                    local flags, _, w, h, title = string.unpack("<BBHHz", data, 3)
                    if flags == 0 and delegate.windowNotification then delegate:windowNotification(wid, w, h, title) end
                end
                if typ == 6 then
                    flags.isVersion11 = true
                    local f = string.unpack("<H", data, 3)
                    if bit32.btest(f, 0x01) then flags.binaryChecksum = true end
                    if bit32.btest(f, 0x02) then flags.filesystem = true handle.fs = fsHandle end
                end
            end
        end
    end

    --- Sends an event to the server. This functions like os.queueEvent.
    -- @param ev The name of the event to send.
    -- @param ... The event parameters. This must not contain any functions,
    -- coroutines, or userdata.
    function handle.queueEvent(ev, ...)
        expect(1, ev, "string")
        if isClosed then return end
        local params = table.pack(...)
        if ev == "key" then delegate:send(makePacket(1, id, string.pack("<BB", keymap_rev[params[1]], params[2] and 2 or 0)))
        elseif ev == "key_up" then delegate:send(makePacket(1, id, string.pack("<BB", keymap_rev[params[1]], 1)))
        elseif ev == "char" then delegate:send(makePacket(1, id, string.pack("<BB", params[1]:byte(), 9)))
        elseif ev == "mouse_click" then delegate:send(makePacket(2, id, string.pack("<BBII", 0, params[1], params[2], params[3])))
        elseif ev == "mouse_up" then delegate:send(makePacket(2, id, string.pack("<BBII", 1, params[1], params[2], params[3])))
        elseif ev == "mouse_scroll" then delegate:send(makePacket(2, id, string.pack("<BBII", 2, params[1] < 0 and 0 or 1, params[2], params[3])))
        elseif ev == "mouse_drag" then delegate:send(makePacket(2, id, string.pack("<BBII", 3, params[1], params[2], params[3])))
        elseif ev == "term_resize" then
            if window then
                local w, h = window.getSize()
                delegate:send(makePacket(4, id, string.pack("<BBHHz", 0, 0, w, h, "")))
            end
        else
            local s = ""
            for i = 1, params.n do s = s .. encodeIBT(params[i]) end
            delegate:send(makePacket(3, id, string.pack("<Bz", params.n, ev) .. s))
        end
    end

    --- Sends a resize request to the server and resizes the window.
    -- @param w The width of the window.
    -- @param h The height of the window.
    function handle.resize(w, h)
        expect(1, w, "number")
        expect(2, h, "number")
        if window and window.reposition then
            local x, y = window.getPosition()
            window.reposition(x, y, w, h)
        end
        if isClosed then return end
        delegate:send(makePacket(4, id, string.pack("<BBHHz", 0, 0, w, h, "")))
    end

    --- Closes the window connection.
    function handle.close()
        if isClosed then return end
        delegate:send(makePacket(4, id, string.pack("<BBHHz", 1, 0, 0, 0, "")))
        delegate:send("\n")
        if delegate.close then delegate:close() end
        isClosed = true
    end

    --- A simple function that sends input events to the server, as well as
    -- updating the window with messages from the server.
    function handle.run()
        parallel.waitForAny(function() while not isClosed do
            local msg = delegate:receive()
            if msg == nil then isClosed = true
            else handle.update(msg) end
        end end,
        function() while true do
            local ev = table.pack(os.pullEventRaw())
            if ev[1] == "key" or ev[1] == "key_up" or ev[1] == "char" or
                ev[1] == "mouse_click" or ev[1] == "mouse_up" or ev[1] == "mouse_scroll" or ev[1] == "mouse_drag" or
                ev[1] == "paste" or ev[1] == "terminate" or ev[1] == "term_resize" then
                handle.queueEvent(table.unpack(ev, 1, ev.n))
            end
        end end)
    end

    -- This field is normally left empty, but if the remote server supports
    -- filesystem transfers it becomes a table with various functions for
    -- accessing the remote filesystem. The functions are a subset of the FS API
    -- as implemented by the raw mode protocol.
    handle.fs = nil

    delegate:send(makePacket(6, id, string.pack("<H", 7)))

    return handle
end

local wsDelegate, rednetDelegate = {}, {}
wsDelegate.__index, rednetDelegate.__index = wsDelegate, rednetDelegate
function wsDelegate:send(data) return self._ws.send(data) end
function wsDelegate:receive(timeout) return self._ws.receive(timeout) end
function wsDelegate:close() return self._ws.close() end
function rednetDelegate:send(data) return rednet.send(self._id, data, self._protocol) end
function rednetDelegate:receive(timeout)
    local tm = os.startTimer(timeout)
    repeat
        local ev = {os.pullEvent()}
        if ev[1] == "rednet_message" and ev[2] == self._id and (not self._protocol or ev[4] == self._protocol) then
            os.cancelTimer(tm)
            return ev[3]
        end
    until ev[1] == "timer" and ev[2] == tm
end

--- Creates a basic delegate object that connects to a WebSocket server.
-- @param url The URL of the WebSocket to connect to.
-- @param headers Any headers to set on the request.
-- @return The new delegate, or nil on error.
-- @return If error, the error message.
function rawterm.wsDelegate(url, headers)
    expect(1, url, "string")
    expect(2, headers, "table", "nil")
    local ws, err = http.websocket(url, headers)
    if not ws then return nil, err end
    return setmetatable({_ws = ws}, wsDelegate)
end

--- Creates a basic delegate object that communicates over Rednet.
-- @param id The ID of the computer to connect to.
-- @param protocol The protocol to communicate over. Defaults to "ccpc_raw_terminal".
function rawterm.rednetDelegate(id, protocol)
    expect(1, id, "number")
    expect(2, protocol, "string", "nil")
    return setmetatable({_id = id, _protocol = protocol or "ccpc_raw_terminal"}, rednetDelegate)
end

return rawterm
