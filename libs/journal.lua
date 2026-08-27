--[[
* Floos - session journal
*
* One JSON line per swing, appended to a file. That is the whole feature, and
* it is the foundation for every question the panel cannot answer: does moon
* phase matter, does the day of the week matter, what is your real drop rate
* with a confidence interval, when do you actually play well.
*
* Writes are buffered and flushed on a timer, so a swing never costs a disk
* round trip inside the render loop.
]]--

require('common');

local M = {};

M.FLUSH_LINES = 12;
M.FLUSH_SECS = 20;
M.MAX_BYTES = 32 * 1024 * 1024;   -- refuse to grow past this

M.enabled = false;
M.path = nil;
M.buffer = {};
M.last_flush = 0;
M.written = 0;
M.dropped = 0;
M.bytes = 0;
M.error = nil;

local function now()
    local ok, t = pcall(os.time);
    if ok and type(t) == 'number' then
        return t;
    end
    return 0;
end

----------------------------------------------------------------------
-- Minimal JSON encoding for flat records
----------------------------------------------------------------------

local ESCAPES = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
    ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
};

local function esc(s)
    s = tostring(s);
    s = s:gsub('[%c"\\]', function (c)
        local e = ESCAPES[c];
        if e ~= nil then
            return e;
        end
        return string.format('\\u%04x', string.byte(c));
    end);
    return s;
end

local function encode_value(v)
    local t = type(v);
    if v == nil then
        return 'null';
    elseif t == 'boolean' then
        return v and 'true' or 'false';
    elseif t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then
            return 'null';
        end
        if math.floor(v) == v and math.abs(v) < 1e15 then
            return string.format('%d', v);
        end
        return string.format('%.4f', v);
    end
    return '"' .. esc(v) .. '"';
end

--- Encode a flat table as a JSON object. Key order is fixed by `order` so the
--- file stays diffable and greppable instead of shuffling every line.
function M.encode(record, order)
    local parts = T{};
    local seen = {};
    local function put(k)
        local v = record[k];
        if v == nil or seen[k] then
            return;
        end
        seen[k] = true;
        parts:append('"' .. esc(k) .. '":' .. encode_value(v));
    end
    if order ~= nil then
        for _, k in ipairs(order) do
            put(k);
        end
    end
    local rest = {};
    for k, _ in pairs(record) do
        if not seen[k] then
            rest[#rest + 1] = k;
        end
    end
    table.sort(rest);
    for _, k in ipairs(rest) do
        put(k);
    end
    return '{' .. table.concat(parts, ',') .. '}';
end

M.FIELD_ORDER = {
    't', 'act', 'outcome', 'item', 'qty', 'gil',
    'zone', 'zone_id', 'skill', 'skill_gain', 'skillup',
    'fatigue', 'cap', 'swing', 'tools',
    'moon', 'moon_pct', 'day', 'vana_hour', 'weather', 'char',
};

----------------------------------------------------------------------
-- File handling
----------------------------------------------------------------------

local function install_dir()
    local ok, p = pcall(function ()
        return AshitaCore:GetInstallPath();
    end);
    if ok and p ~= nil and p ~= '' then
        return (tostring(p):gsub('[/\\]+$', '')) .. '/config/addons/floos';
    end
    return nil;
end

local function addon_dir()
    local base = (addon and addon.path) or '.';
    return (tostring(base):gsub('[/\\]+$', ''));
end

--- Journal lives beside the settings, one file per character.
function M.default_path(charname)
    charname = tostring(charname or 'unknown'):gsub('[^%w_%-]', '');
    if charname == '' then
        charname = 'unknown';
    end
    local dir = install_dir() or addon_dir();
    return dir .. '/journal-' .. charname .. '.jsonl';
end

function M.configure(opts)
    opts = opts or {};
    if opts.path ~= nil then
        M.path = opts.path;
    end
    if opts.enabled ~= nil then
        M.enabled = opts.enabled and true or false;
    end
    if M.path ~= nil and M.bytes == 0 then
        local f = io.open(M.path, 'r');
        if f ~= nil then
            local size = f:seek('end');
            f:close();
            M.bytes = tonumber(size) or 0;
        end
    end
end

--- Queue one record. Cheap: no file access here.
function M.write(record)
    if not M.enabled or M.path == nil or record == nil then
        return false;
    end
    if M.bytes >= M.MAX_BYTES then
        M.dropped = M.dropped + 1;
        M.error = 'journal is at the size limit; rename or delete it';
        return false;
    end
    M.buffer[#M.buffer + 1] = M.encode(record, M.FIELD_ORDER);
    if #M.buffer >= M.FLUSH_LINES then
        M.flush();
    end
    return true;
end

function M.flush()
    if #M.buffer == 0 or M.path == nil then
        return false;
    end
    local body = table.concat(M.buffer, '\n') .. '\n';
    local f = io.open(M.path, 'a');
    if f == nil then
        M.error = 'cannot open ' .. tostring(M.path);
        M.buffer = {};
        return false;
    end
    f:write(body);
    f:close();
    M.written = M.written + #M.buffer;
    M.bytes = M.bytes + #body;
    M.buffer = {};
    M.last_flush = now();
    M.error = nil;
    return true;
end

--- Call from the render loop; flushes only when the timer is up.
function M.tick()
    if #M.buffer == 0 then
        return;
    end
    if (now() - (M.last_flush or 0)) >= M.FLUSH_SECS then
        M.flush();
    end
end

function M.stats()
    return {
        enabled = M.enabled,
        path = M.path,
        written = M.written,
        pending = #M.buffer,
        dropped = M.dropped,
        bytes = M.bytes,
        error = M.error,
    };
end

return M;
