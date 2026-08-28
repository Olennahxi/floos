--[[
* Floos - zone weather
*
* Weather comes from a signature scan into FFXiMain.dll, the same way this
* addon already reads the Vana'diel clock. The pattern and pointer walk are
* the ones every Ashita addon that reads weather uses, and they were checked
* against two independent implementations before being trusted here:
*
*   ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0)
*   pointer = read_uint32(match + 0x02)   -- skip the 66 A1 opcode bytes
*   weather = read_uint8(pointer)
*
* The pattern matches `mov ax, [imm32]` followed by `cmp ax, imm16` and a
* `jb`; +0x02 lands on the absolute address operand, so one dereference gets
* the weather variable. The instruction is 16-bit but only the low byte is
* ever used, which is why the final read is a uint8.
*
* This is a read, once per frame, of a value the client already holds. It is
* the same class of access as the clock and the moon.
*
* Packets are kept as a backstop for the case where the signature does not
* resolve on some future client build:
*
*   0x00A  GP_SERV_LOGIN (zone-in)  - weather id, uint16 @ 0x68
*   0x057  GP_SERV_WEATHER          - weather id, uint16 @ 0x08
*
* Memory wins when it answers, because it is right the instant the addon
* loads instead of waiting for you to zone.
]]--

local M = {};

M.PACKET_ZONE_IN = 0x0A;
M.PACKET_WEATHER = 0x57;

local ZONE_IN_WEATHER_OFFSET = 0x68;
local WEATHER_ID_OFFSET      = 0x08;

--- Weather ids 0-19. The client also accepts 0x14-0x27 as a duplicate set,
--- so everything is folded with % 20 before use.
M.NAMES = {
    [0]  = 'Clear',       [1]  = 'Sunshine',       [2]  = 'Clouds',      [3]  = 'Fog',
    [4]  = 'Hot Spells',  [5]  = 'Heat Waves',     [6]  = 'Rain',        [7]  = 'Squalls',
    [8]  = 'Dust Storms', [9]  = 'Sand Storms',    [10] = 'Winds',       [11] = 'Gales',
    [12] = 'Snow',        [13] = 'Blizzards',      [14] = 'Thunder',     [15] = 'Thunderstorms',
    [16] = 'Auroras',     [17] = 'Stellar Glare',  [18] = 'Gloom',       [19] = 'Darkness',
};

--- Ids 4-19 carry an element, in pairs: single strength then double.
M.ELEMENTS = {
    [4]  = 'Fire',  [5]  = 'Fire',
    [6]  = 'Water', [7]  = 'Water',
    [8]  = 'Earth', [9]  = 'Earth',
    [10] = 'Wind',  [11] = 'Wind',
    [12] = 'Ice',   [13] = 'Ice',
    [14] = 'Lightning', [15] = 'Lightning',
    [16] = 'Light', [17] = 'Light',
    [18] = 'Dark',  [19] = 'Dark',
};

--- Lowest weather id that counts as "an active weather effect" for the
--- elemental ore rule. Horizon's wiki calls Fog out by name as counting,
--- and Fog is id 3 - so the bar sits at 3, not at the elemental 4.
M.ORE_ACTIVE_MIN = 3;

local state = {
    id      = nil,   -- nil means "not seen yet", which is not the same as clear
    at      = 0,
    source  = nil,
};

--- Signature for the weather variable. Resolved once and cached: the address
--- cannot move while the client is running, so re-scanning per frame - which
--- is what the reference implementations do, from inside their render paths -
--- is pure waste.
local WEATHER_PATTERN = '66A1????????663D????72';
local scan_done = false;
local p_weather = nil;

local function resolve_pointer()
    if scan_done then
        return p_weather;
    end
    scan_done = true;
    local ok, addr = pcall(function ()
        return ashita.memory.find('FFXiMain.dll', 0, WEATHER_PATTERN, 0, 0);
    end);
    if ok and type(addr) == 'number' and addr ~= 0 then
        p_weather = addr;
    else
        p_weather = nil;
    end
    return p_weather;
end

--- Nil when the signature did not resolve, or the pointer is not live yet
--- (it is null before you are in a zone). Never guesses.
local function read_memory_weather()
    local base = resolve_pointer();
    if base == nil then
        return nil;
    end
    local ok, id = pcall(function ()
        local pointer = ashita.memory.read_uint32(base + 0x02);
        if pointer == nil or pointer == 0 then
            return nil;
        end
        return ashita.memory.read_uint8(pointer);
    end);
    if not ok or id == nil then
        return nil;
    end
    return id;
end

--- Force the signature to be looked up again. Only useful for diagnostics.
function M.rescan()
    scan_done = false;
    p_weather = nil;
    return resolve_pointer() ~= nil;
end

function M.signature_ok()
    return resolve_pointer() ~= nil;
end

local function read_u16(data, offset)
    -- string.byte is 1-based, packet offsets are 0-based.
    local lo = data:byte(offset + 1);
    local hi = data:byte(offset + 2);
    if lo == nil or hi == nil then
        return nil;
    end
    return lo + (hi * 256);
end

function M.normalize(id)
    id = tonumber(id);
    if id == nil or id < 0 then
        return nil;
    end
    id = math.floor(id) % 20;
    return id;
end

--- Fold a raw packet value into state. Split out so tests can drive it
--- without building fake packets.
function M.set(id, source)
    local n = M.normalize(id);
    if n == nil then
        return false;
    end
    state.id = n;
    state.at = os.time();
    state.source = source or 'set';
    return true;
end

function M.forget()
    state.id = nil;
    state.at = 0;
    state.source = nil;
end

function M.handle_packet_in(e)
    if e == nil or e.data == nil or e.id == nil then
        return;
    end

    if e.id == M.PACKET_WEATHER then
        local w = read_u16(e.data, WEATHER_ID_OFFSET);
        if w ~= nil then
            M.set(w, 'change');
        end
        return;
    end

    if e.id == M.PACKET_ZONE_IN then
        local w = read_u16(e.data, ZONE_IN_WEATHER_OFFSET);
        if w ~= nil then
            M.set(w, 'zone');
        end
        return;
    end
end

--- Everything a caller needs about the weather right now.
--- known = false means we have not seen a packet yet; treat that as
--- "unknown", never as "clear".
function M.current()
    -- Memory first: it is correct the moment the addon loads. The packet
    -- state is only consulted when the signature cannot answer.
    local id = M.normalize(read_memory_weather());
    local source = 'memory';
    if id == nil then
        id = state.id;
        source = state.source;
    end

    if id == nil then
        return {
            known = false,
            id = nil,
            name = 'unknown',
            element = nil,
            double = false,
            elemental = false,
            counts_for_ore = nil,
            since = 0,
            source = nil,
        };
    end

    local element = M.ELEMENTS[id];
    return {
        known = true,
        id = id,
        name = M.NAMES[id] or string.format('Weather %d', id),
        element = element,
        -- 4 is single strength, 5 is double, and so on up the pairs.
        double = (element ~= nil) and ((id - 4) % 2 == 1) or false,
        elemental = (element ~= nil),
        counts_for_ore = (id >= M.ORE_ACTIVE_MIN),
        since = state.at,
        source = source,
    };
end

function M.describe()
    local w = M.current();
    if not w.known then
        return 'unknown';
    end
    if w.double then
        return w.name .. ' x2';
    end
    return w.name;
end

return M;
