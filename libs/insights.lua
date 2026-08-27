--[[
* Floos - journal insights
*
* The journal records one line per swing. This reads it back and answers the
* questions the live panel cannot: does moon phase change your accuracy, does
* the Vana'diel day matter, what actually earned the gil. Nothing here touches
* the game - it is offline analysis of your own play, on demand.
]]--

require('common');

local M = {};

-- A bucket below this many swings is noise, not evidence.
M.MIN_SAMPLE = 30;

----------------------------------------------------------------------
-- Reading our own JSONL back
----------------------------------------------------------------------

--- Parse one line written by libs/journal. This is not a general JSON parser -
--- it reads the flat, escaped format our own encoder produces, which is the
--- only thing that ever appears in the file.
function M.parse_line(line)
    if type(line) ~= 'string' or #line < 2 then
        return nil;
    end
    local rec = {};
    local any = false;
    -- String values (unescape the few escapes our encoder emits).
    for k, v in line:gmatch('"([%w_]+)":"(.-[^\\])"') do
        v = v:gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\n', '\n'):gsub('\\t', '\t');
        rec[k] = v;
        any = true;
    end
    -- Empty strings ("item":"") never match above; catch them separately.
    for k in line:gmatch('"([%w_]+)":""') do
        rec[k] = '';
        any = true;
    end
    -- Numbers.
    for k, v in line:gmatch('"([%w_]+)":(-?%d+%.?%d*)') do
        rec[k] = tonumber(v);
        any = true;
    end
    if not any then
        return nil;
    end
    return rec;
end

--- Stream the journal through a callback, so a 30 MB file never has to live
--- in memory as a table.
function M.each_record(path, fn)
    local f = io.open(path, 'r');
    if f == nil then
        return 0;
    end
    local n = 0;
    for line in f:lines() do
        local rec = M.parse_line(line);
        if rec ~= nil then
            n = n + 1;
            fn(rec);
        end
    end
    f:close();
    return n;
end

----------------------------------------------------------------------
-- Aggregation
----------------------------------------------------------------------

local function bucket_new()
    return { swings = 0, wins = 0, gil = 0 };
end

local function bucket_add(b, rec)
    b.swings = b.swings + 1;
    if rec.outcome == 'W' then
        b.wins = b.wins + 1;
    end
    b.gil = b.gil + (tonumber(rec.gil) or 0);
end

--- Moon percent -> a coarse band. Fine-grained buckets would never fill.
function M.moon_band(pct)
    pct = tonumber(pct);
    if pct == nil then
        return nil;
    end
    if pct < 25 then return 'New-ish (0-24%)'; end
    if pct < 50 then return 'Quarter (25-49%)'; end
    if pct < 75 then return 'Gibbous (50-74%)'; end
    return 'Full-ish (75-100%)';
end

M.MOON_ORDER = {
    'New-ish (0-24%)', 'Quarter (25-49%)', 'Gibbous (50-74%)', 'Full-ish (75-100%)',
};

M.DAY_ORDER = {
    'Firesday', 'Earthsday', 'Watersday', 'Windsday',
    'Iceday', 'Lightningday', 'Lightsday', 'Darksday',
};

--- One pass over the journal: totals, moon bands, days, items.
function M.analyze(path, act)
    local out = {
        total = bucket_new(),
        moon = {},
        day = {},
        items = {},
        lines = 0,
    };
    out.lines = M.each_record(path, function (rec)
        if act ~= nil and rec.act ~= act then
            return;
        end
        bucket_add(out.total, rec);

        local band = M.moon_band(rec.moon_pct);
        if band ~= nil then
            out.moon[band] = out.moon[band] or bucket_new();
            bucket_add(out.moon[band], rec);
        end
        if rec.day ~= nil and rec.day ~= '' then
            out.day[rec.day] = out.day[rec.day] or bucket_new();
            bucket_add(out.day[rec.day], rec);
        end
        if rec.outcome == 'W' and rec.item ~= nil and rec.item ~= '' then
            local it = out.items[rec.item] or { count = 0, gil = 0 };
            it.count = it.count + 1;
            it.gil = it.gil + (tonumber(rec.gil) or 0);
            out.items[rec.item] = it;
        end
    end);
    return out;
end

local function acc(b)
    if b == nil or b.swings == 0 then
        return 0;
    end
    return (b.wins / b.swings) * 100;
end

M.accuracy = acc;

--- The report as plain lines, ready for chat. Buckets below MIN_SAMPLE are
--- shown but marked, because a confident answer from 12 swings is a lie.
function M.report_lines(a, act_label)
    local lines = {};
    local function add(fmt, ...)
        lines[#lines + 1] = string.format(fmt, ...);
    end

    if a.total.swings == 0 then
        add('No journal data for %s yet. Keep gathering - every swing is recorded.', act_label);
        return lines;
    end

    add('~~~~~~ Insights: %s (%d swings on record) ~~~~~~', act_label, a.total.swings);
    add('Overall: %.1f%% accuracy, %s gil, %.1f gil/swing',
        acc(a.total), tostring(a.total.gil), a.total.gil / a.total.swings);

    add('By moon:');
    for _, band in ipairs(M.MOON_ORDER) do
        local b = a.moon[band];
        if b ~= nil then
            local tag = (b.swings < M.MIN_SAMPLE) and '  (thin sample)' or '';
            add('  %-20s %5.1f%%  over %d swings%s', band, acc(b), b.swings, tag);
        end
    end

    add('By day:');
    for _, day in ipairs(M.DAY_ORDER) do
        local b = a.day[day];
        if b ~= nil then
            local tag = (b.swings < M.MIN_SAMPLE) and '  (thin sample)' or '';
            add('  %-14s %5.1f%%  over %d swings%s', day, acc(b), b.swings, tag);
        end
    end

    -- Earners, best first.
    local names = {};
    for n, _ in pairs(a.items) do
        names[#names + 1] = n;
    end
    table.sort(names, function (x, y)
        return a.items[x].gil > a.items[y].gil;
    end);
    if #names > 0 then
        add('Top earners:');
        for i = 1, math.min(5, #names) do
            local it = a.items[names[i]];
            add('  %-24s x%-4d %sg', names[i], it.count, tostring(it.gil));
        end
    end

    -- The verdict, only when the data can carry it.
    local best_band, best_acc, worst_acc = nil, -1, 101;
    local solid = 0;
    for _, band in ipairs(M.MOON_ORDER) do
        local b = a.moon[band];
        if b ~= nil and b.swings >= M.MIN_SAMPLE then
            solid = solid + 1;
            local v = acc(b);
            if v > best_acc then best_acc = v; best_band = band; end
            if v < worst_acc then worst_acc = v; end
        end
    end
    if solid >= 2 then
        if (best_acc - worst_acc) >= 5 then
            add('Verdict: moon looks like it matters for you - best at %s (%.1f%% vs %.1f%%).',
                best_band, best_acc, worst_acc);
        else
            add('Verdict: no meaningful moon effect in your data (spread %.1f%%).',
                best_acc - worst_acc);
        end
    else
        add('Verdict: not enough data yet for a moon comparison. It builds itself - just play.');
    end

    return lines;
end

return M;
