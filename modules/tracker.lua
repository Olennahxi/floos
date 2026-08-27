--[[
* Floos - HELM session tracker (Mine / Logg / Harv / Exca)
* UI style adapted from XIUI; HELM detection logic from HGather.
]]--

require('common');
local imgui = require('imgui');
local chat = require('chat');
local settings_lib = require('settings');
local constants = require('constants');
local format = require('libs.format');
local theme = require('libs.theme');
local ui = require('libs.ui');
local drawing = require('libs.drawing');
local fonts = require('libs.fonts');
local vana = require('libs.vana');
local weather = require('libs.weather');
local vis = require('libs.vis');
local fatigue_lib = require('libs.fatigue');
local journal = require('libs.journal');

local ACTIVITIES = { 'mining', 'logging', 'harvest', 'excavate', 'hunting', 'fishing', 'digging', 'clamming' };
local TAB_LABELS = {
    mining = 'Mine',
    logging = 'Logg',
    harvest = 'Harv',
    excavate = 'Exca',
    hunting = 'Hunt',
    fishing = 'Fish',
    digging = 'Dig',
    clamming = 'Clam',
};
local TAB_ORDER = { 'mining', 'logging', 'harvest', 'excavate', 'hunting', 'fishing', 'digging', 'clamming' };

--- Fishing and digging are not HELM: they are their own actions on the client
--- action packet rather than a trade to a gathering point, so they detect
--- differently and their sessions carry different counters.
local NON_HELM = { fishing = true, digging = true, clamming = true };



-- Point names on 0x36 HELM packet target
local POINT_TO_ACTIVITY = {
    ['Mining Point'] = 'mining',
    ['Logging Point'] = 'logging',
    ['Harvesting Point'] = 'harvest',
    ['Harvesting Poin'] = 'harvest', -- truncated name in some clients
    ['Excavation Point'] = 'excavate',
};

--- Match on the leading word instead of the whole string. Entity names come
--- back truncated on some clients ('Harvesting Poin') and servers are free to
--- rename the rest, but the first word is what identifies the point.
local POINT_PREFIX = {
    ['mining'] = 'mining',
    ['logging'] = 'logging',
    ['harvesting'] = 'harvest',
    ['excavation'] = 'excavate',
};

local function point_activity(name)
    if name == nil then
        return nil;
    end
    local exact = POINT_TO_ACTIVITY[name];
    if exact ~= nil then
        return exact;
    end
    local first = tostring(name):lower():match('^(%a+)');
    if first == nil then
        return nil;
    end
    return POINT_PREFIX[first];
end

local TOOL_IDS = {
    mining = 605,     -- Pickaxe
    excavate = 605,   -- Pickaxe
    logging = 1021,   -- Hatchet
    harvest = 1020,   -- Sickle
    digging = 4545,   -- Bunch of Gysahl Greens (fixed id, so stock is countable)
};

local TOOL_LABEL = {
    mining = 'Pickaxes',
    excavate = 'Pickaxes',
    logging = 'Hatchets',
    harvest = 'Sickles',
    hunting = '-',
    fishing = 'Bait',
    digging = 'Greens',
    clamming = 'Kits',
};

local SWING_LABEL = {
    mining = 'Swings',
    excavate = 'Swings',
    logging = 'Chops',
    harvest = 'Cuts',
    hunting = 'Kills',
    fishing = 'Casts',
    digging = 'Digs',
    clamming = 'Digs',
};


-- Chat rules per activity. Excavation shares mining's messages (both use a
-- pickaxe) but we accept an excavate-specific failure line too, in case the
-- server words it differently.
local ACT_RULES = {
    mining = {
        success = 'dig up an? ([^,!]+)',
        broke   = 'pickaxe breaks',
        unable  = { 'unable to mine anything' },
    },
    excavate = {
        success = 'dig up an? ([^,!]+)',
        broke   = 'pickaxe breaks',
        unable  = { 'unable to mine anything', 'unable to excavate anything' },
    },
    logging = {
        success = 'cut off an? ([^,!]+)',
        broke   = 'hatchet breaks',
        unable  = { 'unable to log anything' },
    },
    harvest = {
        success = 'harvest an? ([^,!]+)',
        broke   = 'sickle breaks',
        unable  = { 'unable to harvest anything' },
    },
};

----------------------------------------------------------------------
-- Fishing and digging chat rules
--
-- Every pattern here is lowercase because handle_text lowercases and strips
-- colours before matching. All of these strings were taken from addons that
-- run on this server rather than guessed, because a wrong pattern fails
-- silently - the tracker simply never counts.
----------------------------------------------------------------------

--- What the hook message tells you is on the line. Order matters: the large
--- fish line ends in "!!!" and contains the small fish line as a prefix, so
--- the three-bang form must be tested first or every large fish is miscounted
--- as a small one.
local FISH_HOOK = {
    { pat = 'something caught the hook!!!',              kind = 'large'   },
    { pat = 'something caught the hook!',                kind = 'small'   },
    { pat = 'you feel something pulling at your line',   kind = 'item'    },
    { pat = 'something clamps onto your line ferociously', kind = 'monster' },
};

local function fish_hook_kind(message)
    for _, h in ipairs(FISH_HOOK) do
        if string.find(message, h.pat, 1, true) ~= nil then
            return h.kind;
        end
    end
    return nil;
end

--- How a hooked fish can end badly. Each maps to a different diagnosis, so
--- they are counted apart rather than lumped into one "lost" number.
local FISH_FAIL = {
    { pat = 'you lost your catch due to your lack of skill', kind = 'lost_skill' },
    { pat = 'you lost your catch',                           kind = 'lost'       },
    { pat = 'your line breaks',                              kind = 'line'       },
    { pat = 'your rod breaks',                               kind = 'rod'        },
    { pat = 'whatever caught the hook was too small',        kind = 'too_small'  },
    { pat = 'whatever caught the hook was too large',        kind = 'too_large'  },
    { pat = 'you give up',                                   kind = 'cancel'     },
};

local function fish_fail_kind(message)
    for _, f in ipairs(FISH_FAIL) do
        if string.find(message, f.pat, 1, true) ~= nil then
            return f.kind;
        end
    end
    return nil;
end

--- The catch line is built from your own character name, not "You" - the game
--- writes "Jasim caught a moat carp!". Without the name we cannot tell your
--- catch from someone else's in a crowded fishing spot.
local function fish_catch_name(message, player)
    if player == nil or player == '' then
        return nil, nil;
    end
    local who = string.lower(player);
    -- Multi-catch first: "<name> caught 3 moat carp!"
    local n, many = string.match(message, '^' .. who .. ' caught (%d+) ([^!]+)!');
    if n ~= nil then
        return many, tonumber(n) or 1;
    end
    local one = string.match(message, '^' .. who .. ' caught an? ([^!]+)!');
    if one ~= nil then
        return one, 1;
    end
    return nil, nil;
end

--- Digging outcomes. The success line is a bare system message with no player
--- name, unlike fishing - "Obtained: bird egg." - so it is matched directly.
------------------------------------------------------------------------
-- Clamming
--
-- Every message below is the real server string, taken from the server's own
-- Bibiki Bay message table and cross-checked against Horizon's wiki. Two
-- notes worth keeping:
--
--  * The over-weight line is ONE message that contains the find as well:
--    "You find <item> and toss it into your bucket... But the weight is too
--    much for the bucket and its bottom breaks!" - so the break has to be
--    tested BEFORE the find, or the item gets banked into a bucket that no
--    longer exists.
--
--  * The incident line is easy to get wrong, and the misspelling
--    "somthing jumps into your bucket" is doing the rounds. The real message,
--    id 7287, is "Something jumps into your bucket and breaks through the
--    bottom!" - so the test suite asserts the typo never matches.
------------------------------------------------------------------------
local CLAM_FIND       = 'you find (.-) and toss it into your bucket';
local CLAM_OVERWEIGHT = 'the weight is too much for the bucket';
local CLAM_INCIDENT   = 'something jumps into your bucket';
local CLAM_CAPACITY   = 'clamming capacity has increased to (%d+) ponze';
local CLAM_KIT        = 'key item: clamming kit';
local CLAM_BROKEN     = 'cannot collect any clams with a broken bucket';
local CLAM_FULL_BAG   = 'room in that spiffy bag';
--- Both of these are REJECTED clicks, not flavour text. The server returns
--- before it rolls anything: its trigger function sends one or the other and
--- exits without opening the dig event. So they cost you a click and give
--- nothing, which makes them worth counting - and they are the signal that
--- you are hammering the point before its cooldown is up.
local CLAM_REJECT = {
    'it looks like someone has been digging here',
    'the area is littered with pieces of broken seashells',
};
-- Toh Zonikki's cash-out line. The first is his confirmed dialogue (id
-- 7263); the second is a widely used alternative, kept as a second chance
-- because it could not be verified against any primary source.
local CLAM_TURNIN     = { 'here\'rrre yer clams', 'you return the clamming kit' };

--- Strip the article the message wraps around the item name, so "a jacknife"
--- and "an elm log" both key the same way the price list does.
local function clam_item_name(raw)
    if raw == nil then return nil; end
    local name = raw:gsub('^an%s+', ''):gsub('^a%s+', ''):gsub('^some%s+', '');
    name = name:gsub('%.+$', ''):match('^%s*(.-)%s*$');
    if name == '' then return nil; end
    return name;
end

local function dig_item_name(message)
    local item = string.match(message, 'obtained:%s*(.+)');
    if item == nil then
        return nil;
    end
    item = item:gsub('%.%s*$', '');
    item = item:match('^%s*(.-)%s*$');
    if item == '' then
        return nil;
    end
    return item;
end

--- Trim a captured drop name. Handles "..., but your pickaxe breaks in the
--- process." and any trailing punctuation, and never mangles apostrophes or
--- hyphens the way a %w-only class does.
local function clean_item_name(name)
    if name == nil then
        return nil;
    end
    name = tostring(name):gsub(',%s*but.*$', '');
    name = name:gsub('[%.%!%s]+$', '');
    name = name:match('^%s*(.-)%s*$') or name;
    if name == '' then
        return nil;
    end
    return name;
end

-- Skill lines. Each activity lists every word the game might use, because the
-- chat wording does not match the activity name: excavation skill-ups read
-- "Your excavating skill has increased by 0.1 raising it to 19.3."
local SKILL_LINES = {
    { act = 'mining',   words = { 'mining' } },
    { act = 'logging',  words = { 'logging' } },
    { act = 'harvest',  words = { 'harvesting', 'harvest' } },
    { act = 'excavate', words = { 'excavating', 'excavation' } },
    { act = 'fishing',  words = { 'fishing' } },
    -- Horizon added visible dig skill-ups; retail has none. The exact noun is
    -- unconfirmed, so accept every plausible form rather than guess one.
    { act = 'digging',  words = { 'digging', 'dig', 'chocobo digging' } },
};

-- Strict forms first. [,%s]+ covers "by 0.1, raising" and "by 0.1 raising".
--
-- The number pattern is %d*%.?%d+, NOT %d+%.?%d*. Horizon writes the gain
-- with no leading zero:
--
--     Your Chocobo Digging skill increases by .1 raising it to 52.2!
--
-- %d+ demands a digit before the point, so ".1" never matched and every dig
-- skill-up was silently dropped - which also left the daily cap stuck at the
-- Amateur 100 because the cap is derived from the skill. The new form takes
-- ".1", "0.1" and "1" alike.
local SKILL_PATTERNS = {
    ' skill has increased by (%d*%.?%d+)[,%s]+raising it to (%d*%.?%d+)',
    ' skill increases by (%d*%.?%d+)[,%s]+raising it to (%d*%.?%d+)',
    ' skill has increased by (%d*%.?%d+)[^%d]+(%d*%.?%d+)',
    ' skill increases by (%d*%.?%d+)[^%d]+(%d*%.?%d+)',
};

local function match_skill_up(message, words)
    if type(words) == 'string' then
        words = { words };
    end
    for _, word in ipairs(words) do
        for _, pat in ipairs(SKILL_PATTERNS) do
            local gain, level = string.match(message, word .. pat);
            if gain ~= nil then
                return tonumber(gain), tonumber(level);
            end
        end
    end
    return nil, nil;
end

-- Tool item ids are resolved by name at runtime, with these as the fallback.
local TOOL_NAMES = {
    mining = 'Pickaxe',
    excavate = 'Pickaxe',
    logging = 'Hatchet',
    harvest = 'Sickle',
};

local tool_ids_resolved = false;

local function resolve_tool_ids()
    if tool_ids_resolved then
        return;
    end
    tool_ids_resolved = true;
    local res = nil;
    pcall(function ()
        res = AshitaCore:GetResourceManager();
    end);
    if res == nil then
        return;
    end
    for act, name in pairs(TOOL_NAMES) do
        for _, lang in ipairs({ 2, 1, 0 }) do
            local id = nil;
            pcall(function ()
                local item = res:GetItemByName(name, lang);
                if item ~= nil then
                    id = item.Id;
                end
            end);
            if id ~= nil and id > 0 then
                TOOL_IDS[act] = id;
                break;
            end
        end
    end
end

local M = {
    last_size = { w = 280, h = 240 },
    layout_w = 280,
    settings_ref = nil,
    session_dirty = false,
    session_last_save_ms = 0,
    idle_limit = constants.IDLE_LIMIT_SEC,
    active_tab = 'mining',
    awaiting = nil, -- activity waiting for chat result
    resize = nil,   -- { start_mouse_x/y, start_w/h }
    layout_h = 0,   -- locked panel height this frame (0 = auto fit)
    -- Per-tab vertical layout budget for the haul list. The haul is the only
    -- section that gives up room when the window is dragged shorter, so its
    -- measurements are what decide how short the window may get.
    -- { chrome = px used by everything else, row = one drop row, rows = n,
    --   used = px handed to the haul this frame }
    haul = {},
    win_pad_y = nil, -- measured slack between the last item and the window bottom
};

M.TAB_ORDER = TAB_ORDER;
M.TAB_LABELS = TAB_LABELS;

--- Eight tabs do not fit a 340px panel. Each one can be switched off in the
--- config, and everything downstream - the tab bar, the auto-switch, the
--- width maths - works off this list rather than the full one. Turning a tab
--- off only hides it: the session behind it keeps tracking, so nothing is
--- lost by tidying the bar down to the two or three you actually use.
function M.visible_tabs(settings)
    local out = {};
    local cfg = settings and settings.tabs or nil;
    for _, act in ipairs(TAB_ORDER) do
        local on = true;
        if cfg ~= nil and cfg[act] ~= nil then
            on = (cfg[act][1] ~= false);
        end
        if on then
            out[#out + 1] = act;
        end
    end
    -- A panel with no tabs at all is a bug, not a preference.
    if #out == 0 then
        out[1] = TAB_ORDER[1];
    end
    return out;
end

--- Is this tab on the bar right now?
function M.tab_visible(settings, act)
    for _, a in ipairs(M.visible_tabs(settings)) do
        if a == act then return true; end
    end
    return false;
end

local MIN_PANEL_W = 320;
local MAX_PANEL_W = 600;
local MIN_PANEL_H = 140;
local MAX_PANEL_H = 900;
local RESIZE_GRIP = 18;

--- How far the haul list is allowed to collapse. Two rows still read as a
--- list - you can see your best drop and that there is more underneath - and
--- they are the floor the whole panel's minimum height is built on.
local HAUL_MIN_ROWS = 2;
local HAUL_SCROLLBAR_W = 8;

local function blank_session()
    return {
        swings = 0,       -- kills for hunting
        breaks = 0,
        items = 0,
        rewards = T{},
        skill_gain = 0,
        skill_w = 0,  -- skill-ups after Win (got item)
        skill_m = 0,  -- skill-ups after Miss (unable)
        skill_b = 0,  -- skill-ups after Break (tool broke, no item)
        last_outcome = nil, -- 'W' | 'M' | 'B'
        last_activity_ms = 0,
        -- Digging only: items banked against the personal DAILY limit, and
        -- the Japanese-midnight day they were banked on.
        daily_items = 0,
        daily_day = 0,
        -- Clamming only: the unbanked bucket. Items in here are worth
        -- nothing until Toh Zonikki takes the kit, so they are kept apart
        -- from rewards and only move across on a turn-in.
        bucket = T{},
        bucket_weight = 0,
        bucket_capacity = 0,
        kits = 0,
        turnins = 0,
        overweight = 0,
        incidents = 0,
        bucket_broken = false,
        assumed_weight = false,
        last_find_s = 0,
        paused = false,
        session_active = 0,
        last_action = 0,
        -- hunting-only
        steals = 0,
        steal_attempts = 0,
        raw_gil = 0,
        exp = 0,
        limit = 0,
        -- mining rare events (still tracked, not shown)
        gold_rush = 0,
        motherlode = 0,
        -- fishing. A cast that never gets a bite costs nothing; bait is spent
        -- per BITE on Horizon, so bites is the number that bills the bait.
        bites = 0,
        lost = 0,          -- hooked then lost (any reason)
        lost_skill = 0,    -- lost specifically to lack of skill
        line_breaks = 0,
        monsters = 0,
        no_catch = 0,      -- cast resolved with no bite at all
        cancels = 0,       -- you put the rod away mid-fight
        hook_small = 0,
        hook_large = 0,
        hook_item = 0,
        -- digging. Greens are spent on every ACCEPTED attempt, including the
        -- ones that find nothing, so digs is the number that bills the greens.
        rejected = 0,      -- "wait longer" - free, does not spend a green
        zone_empty = false,
        -- Fatigue is a server-side allowance that clears on a schedule. It is
        -- NOT the session item count, which is why they are separate now.
        -- presentation state (in-memory only, never persisted)
        history = {},        -- ring of { oc = 'W'|'M'|'B', skill = bool }
        samples = {},        -- { t = secs, worth = gil } for the rate sparkline
        last_sample_s = 0,
        flash_ms = 0,        -- skill-up flash timestamp
        anim_gil = nil,      -- smoothed net gil for the count-up
    };
end

local HISTORY_MAX = 40;
local SAMPLE_MAX = 40;
local SAMPLE_INTERVAL_S = 12;
local FLASH_MS = 1100;
local BIG_DROP_GIL = 3000;   -- a drop worth this much gets the gold flash
local RATE_WARMUP_S = 120; -- gph is noise before this much session time
local AWAIT_TIMEOUT_MS = 20000; -- drop an unresolved swing after this long

-- Diagnostics. A detection failure is otherwise invisible: the addon just does
-- nothing, which from the outside looks exactly like the game doing nothing.
-- This keeps a short trail of what was actually seen so the answer is one
-- command away instead of a guess from a screenshot.
local DEBUG_LOG_MAX = 14;
M.debug_echo = false;
M.debug_log = {};

local function debug_note(kind, detail)
    M.debug_log[#M.debug_log + 1] = {
        t = os.time(), kind = tostring(kind), detail = tostring(detail or ''),
    };
    while #M.debug_log > DEBUG_LOG_MAX do
        table.remove(M.debug_log, 1);
    end
    if M.debug_echo then
        print(chat.header(addon.name):append(chat.color1(6, '[' .. tostring(kind) .. '] '))
            :append(chat.message(tostring(detail or ''))));
    end
end
M.debug_note = debug_note;

M.sessions = {
    mining = blank_session(),
    logging = blank_session(),
    harvest = blank_session(),
    excavate = blank_session(),
    hunting = blank_session(),
};

M.zone_id = 0;
M.zone_name = 'Unknown';
M.lifetime_gil = 0;  -- overall history; never cleared by /floos clear
M.lifetime_skill_w = 0;  -- skill-ups on Win (never cleared)
M.lifetime_skill_m = 0;  -- skill-ups on Miss (never cleared)
M.lifetime_skill_b = 0;  -- skill-ups on Break (never cleared)
M.lifetime_wins = 0;     -- total successful digs (denom for W %)
M.lifetime_misses = 0;   -- total unable (denom for M %)
M.lifetime_break_only = 0; -- break with no item (denom for B %)
M.pending_skill_ups = 0; -- skill-up text arrived before dig/miss/break line

-- Current zone visit. Aggregates live in settings.lifetime.zstats.
M.zone_visit = {
    id = 0,
    act = nil,
    name = 'Unknown',
    secs = 0, gil = 0, skill = 0,
    swings = 0, items = 0, breaks = 0, fails = 0,
    last_action = 0,
    started = 0,
    left_at = 0,
};
M.zone_stats = nil;   -- key 'act:id' -> settings record, built on bind

local function player_name()
    local n = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    if n == nil or n == '' then return ''; end
    return string.lower(n);
end

local function safe_zone_name(zone_id)
    zone_id = tonumber(zone_id) or 0;
    if zone_id <= 0 then return 'Unknown'; end
    local ok, name = pcall(function()
        return AshitaCore:GetResourceManager():GetString('zones.names', zone_id);
    end);
    if not ok or name == nil or name == '' then
        return string.format('Zone %d', zone_id);
    end
    name = tostring(name):gsub('%z', ''):match('^%s*(.-)%s*$') or tostring(name);
    if name == '' then return string.format('Zone %d', zone_id); end
    return name;
end

function M.refresh_zone()
    local zid = 0;
    pcall(function()
        zid = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    end);
    zid = tonumber(zid) or 0;

    -- Fast path: this runs every frame now, so skip the resource lookup when
    -- nothing has changed.
    if zid > 0 and zid == M.zone_id and M.zone_name ~= 'Unknown'
        and M.zone_visit ~= nil and (M.zone_visit.id or 0) == zid then
        return M.zone_id, M.zone_name;
    end

    local zname = safe_zone_name(zid);
    if zid > 0 and (zid ~= (M.zone_visit and M.zone_visit.id or 0)
        or M.zone_visit == nil or (M.zone_visit.id or 0) == 0) then
        M.start_zone_visit(zid, zname, M.active_tab);
    end
    M.zone_id = zid;
    M.zone_name = zname;
    return M.zone_id, M.zone_name;
end






local SESSION_AUTOSAVE_MS = 10000;


--- Wall-clock seconds. os.time() is the only source here that is
--- unambiguously a running total rather than a component of the current
--- time, and every timeout in this file is measured in real seconds, so it
--- is what the session timer, the idle grace and the panel auto-hide use.
local function now_s()
    return os.time();
end

--- Milliseconds, built as whole seconds from os.time() plus a sub-second
--- remainder. Correct whether the framework's ms field is a total or the
--- 0-999 component of the current second - which is what made the display
--- timeout never fire: subtracting two wrapping components gives a garbage
--- (often negative) gap, so the panel always looked like it had just been
--- used and never hid itself.
local function now_ms()
    local frac = 0;
    local ok, c = pcall(function () return ashita.time.clock()['ms']; end);
    if ok and type(c) == 'number' then
        frac = math.floor(c) % 1000;
    end
    return (os.time() * 1000) + frac;
end

local function title_case(name)
    return (tostring(name or ''):lower():gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest;
    end));
end

local function normalize_key(name)
    return string.lower(tostring(name or ''):match('^%s*(.-)%s*$') or '');
end

local function sess(act)
    return M.sessions[act] or M.sessions.mining;
end

function M.bind_settings(settings_ref)
    M.settings_ref = settings_ref;
    -- The zone index caches rows of the old table; force a rebuild from the
    -- new one, otherwise zone credit keeps flowing into the dead table.
    M.zone_stats = nil;
    if settings_ref ~= nil then
        if settings_ref.lifetime == nil then
            settings_ref.lifetime = T{
                gil_gained = T{ 0 },
                skill_w = T{ 0 },
                skill_m = T{ 0 },
                skill_b = T{ 0 },
            };
        end
        if settings_ref.lifetime.gil_gained == nil then settings_ref.lifetime.gil_gained = T{ 0 }; end
        if settings_ref.lifetime.skill_w == nil then settings_ref.lifetime.skill_w = T{ 0 }; end
        if settings_ref.lifetime.skill_m == nil then settings_ref.lifetime.skill_m = T{ 0 }; end
        if settings_ref.lifetime.skill_b == nil then settings_ref.lifetime.skill_b = T{ 0 }; end
        if settings_ref.lifetime.wins == nil then settings_ref.lifetime.wins = T{ 0 }; end
        if settings_ref.lifetime.misses == nil then settings_ref.lifetime.misses = T{ 0 }; end
        if settings_ref.lifetime.break_only == nil then settings_ref.lifetime.break_only = T{ 0 }; end
        M.lifetime_gil = tonumber(settings_ref.lifetime.gil_gained[1]) or 0;
        M.lifetime_skill_w = tonumber(settings_ref.lifetime.skill_w[1]) or 0;
        M.lifetime_skill_m = tonumber(settings_ref.lifetime.skill_m[1]) or 0;
        M.lifetime_skill_b = tonumber(settings_ref.lifetime.skill_b[1]) or 0;
        M.lifetime_wins = tonumber(settings_ref.lifetime.wins[1]) or 0;
        M.lifetime_misses = tonumber(settings_ref.lifetime.misses[1]) or 0;
        M.lifetime_break_only = tonumber(settings_ref.lifetime.break_only[1]) or 0;
        M.index_zone_stats();
        -- Legacy skill-up counts without matching outcome totals → rates >100%.
        -- Reset rate pairs so W/M/B rebuild cleanly from this point.
        local bad = (M.lifetime_skill_w > M.lifetime_wins)
            or (M.lifetime_skill_m > M.lifetime_misses)
            or (M.lifetime_skill_b > M.lifetime_break_only);
        if bad then
            M.lifetime_skill_w = 0;
            M.lifetime_skill_m = 0;
            M.lifetime_skill_b = 0;
            M.lifetime_wins = 0;
            M.lifetime_misses = 0;
            M.lifetime_break_only = 0;
            settings_ref.lifetime.skill_w[1] = 0;
            settings_ref.lifetime.skill_m[1] = 0;
            settings_ref.lifetime.skill_b[1] = 0;
            settings_ref.lifetime.wins[1] = 0;
            settings_ref.lifetime.misses[1] = 0;
            settings_ref.lifetime.break_only[1] = 0;
        end
    end
end

function M.get_lifetime_gil()
    return tonumber(M.lifetime_gil) or 0;
end

function M.get_lifetime_wmb()
    return (tonumber(M.lifetime_skill_w) or 0),
           (tonumber(M.lifetime_skill_m) or 0),
           (tonumber(M.lifetime_skill_b) or 0);
end

-- skill-up rate per outcome: skill_ups_on_X / total_X
function M.get_lifetime_wmb_rates()
    local sw = tonumber(M.lifetime_skill_w) or 0;
    local sm = tonumber(M.lifetime_skill_m) or 0;
    local sb = tonumber(M.lifetime_skill_b) or 0;
    local wins = tonumber(M.lifetime_wins) or 0;
    local misses = tonumber(M.lifetime_misses) or 0;
    local brk = tonumber(M.lifetime_break_only) or 0;
    local function rate(num, den)
        if den <= 0 then return 0; end
        local r = (num / den) * 100;
        if r > 100 then r = 100; end
        if r < 0 then r = 0; end
        return r;
    end
    return rate(sw, wins), rate(sm, misses), rate(sb, brk), wins, misses, brk, sw, sm, sb;
end

----------------------------------------------------------------------
-- Fatigue period
--
-- The cap clears on a server schedule that nothing announces. We learn it from
-- the only unambiguous evidence available: being at the cap and then gathering
-- successfully. That can only happen after a reset.
----------------------------------------------------------------------

local SKILL_BAND = 5;   -- skill/hr is banded, because the rate changes as you level

--- The shared schedule lives in settings so it survives a reload.
local function fatigue_state()
    if M.settings_ref == nil then
        return nil;
    end
    if M.settings_ref.fatigue == nil then
        M.settings_ref.fatigue = T{ observations = T{}, period_hours = T{ 24 }, last_seen = T{ 0 } };
    end
    local f = M.settings_ref.fatigue;
    if f.observations == nil then f.observations = T{}; end
    if f.period_hours == nil then f.period_hours = T{ 24 }; end
    if f.last_seen == nil then f.last_seen = T{ 0 }; end
    -- fatigue_lib wants plain fields, not the T{value} boxes settings uses.
    return {
        observations = f.observations,
        period_hours = tonumber(f.period_hours[1]) or 24,
        _store = f,
    };
end

function M.fatigue_time_left()
    local st = fatigue_state();
    if st == nil then
        return nil;
    end
    return fatigue_lib.time_left(st, os.time());
end

function M.fatigue_confidence()
    local st = fatigue_state();
    if st == nil then
        return 'none';
    end
    return fatigue_lib.confidence(st);
end

--- Fatigue is the session's item count, the way it was before 1.9.0. One
--- number, cleared by /floos clear, never touched by anything automatic.
function M.fatigue_items(act)
    return sess(act).items or 0;
end

--- Record that the cap cleared, so the countdown has something to predict from.
--- Deliberately does not zero anything: the counter is the session, and only
--- you decide when the session ends.
function M.fatigue_reset(witnessed, at)
    at = at or os.time();
    local st = fatigue_state();
    if st ~= nil then
        if witnessed then
            fatigue_lib.record(st, at);
        end
        st._store.last_seen[1] = at;
    end
    M.session_dirty = true;
end

--- Gathering while already at the cap can only mean the server cleared it.
--- That is worth learning from, so it is recorded - but nothing is reset.
local function note_reset_if_capped(act, cap)
    local before = sess(act).items or 0;
    if cap ~= nil and cap > 0 and before >= cap then
        M.fatigue_reset(true, os.time());
        return true;
    end
    return false;
end

----------------------------------------------------------------------
-- Zone intelligence
--
-- Every zone + activity gets a lifetime aggregate: time actually spent
-- swinging, gil earned, skill gained, swings, items, breaks. Aggregates are
-- updated on each swing rather than flushed when you leave, so nothing is lost
-- to a crash, a reload, or a quick zone hop.
--
-- The verdict compares THIS visit against the best OTHER zone you have real
-- data for, and names it. The old code averaged every zone together and
-- compared against that blend, which is why it never said anything useful.
----------------------------------------------------------------------

-- A visit needs this much before it is worth judging.
local VERDICT_MIN_SECS = 240;
local VERDICT_MIN_SWINGS = 15;

-- A zone needs this much before it is allowed to be the thing you compare to.
local BENCH_MIN_SECS = 600;
local BENCH_MIN_SWINGS = 40;

-- Re-entering the same zone within this window continues the same visit.
local VISIT_RESUME_S = 240;

--- Band 0 is the all-time record for a zone. Bands above 0 hold the same
--- stats sliced by the skill you had at the time, because skill/hr falls off as
--- you approach a zone's ceiling - a rate you earned at skill 5 says nothing
--- about the rate you will get at skill 45.
local function zkey(act, id, band)
    return tostring(act) .. ':' .. tostring(tonumber(id) or 0)
        .. ':' .. tostring(math.floor(tonumber(band) or 0));
end

local function band_of(skill)
    skill = tonumber(skill) or 0;
    if skill <= 0 then
        return 0;
    end
    return math.floor(skill / SKILL_BAND) * SKILL_BAND;
end

M.band_of = band_of;

--- The settings-backed array of per-zone records. Stored as an array (not a
--- table keyed by zone id) so Ashita's settings serializer round-trips it.
local function ensure_zstats()
    if M.settings_ref == nil then
        return nil;
    end
    if M.settings_ref.lifetime == nil then
        M.settings_ref.lifetime = T{ gil_gained = T{ 0 } };
    end
    if M.settings_ref.lifetime.zstats == nil then
        M.settings_ref.lifetime.zstats = T{};
    end
    return M.settings_ref.lifetime.zstats;
end

--- Rebuild the in-memory index from settings. Safe to call repeatedly.
function M.index_zone_stats()
    M.zone_stats = {};
    local arr = ensure_zstats();
    if arr == nil then
        return;
    end
    for _, r in ipairs(arr) do
        local id = tonumber(r.id) or 0;
        local act = r.act;
        r.band = tonumber(r.band) or 0;
        if id > 0 and act ~= nil then
            r.secs = tonumber(r.secs) or 0;
            r.gil = tonumber(r.gil) or 0;
            r.skill = tonumber(r.skill) or 0;
            r.swings = tonumber(r.swings) or 0;
            r.items = tonumber(r.items) or 0;
            r.breaks = tonumber(r.breaks) or 0;
            r.visits = tonumber(r.visits) or 0;
            M.zone_stats[zkey(act, id, r.band)] = r;
        end
    end
end

local function zone_record(act, id, name, create, band)
    id = tonumber(id) or 0;
    band = math.floor(tonumber(band) or 0);
    if id <= 0 or act == nil then
        return nil;
    end
    if M.zone_stats == nil then
        M.index_zone_stats();
    end
    local key = zkey(act, id, band);
    local rec = M.zone_stats[key];
    if rec ~= nil then
        if name ~= nil and name ~= 'Unknown' then
            rec.name = name;
        end
        return rec;
    end
    if not create then
        return nil;
    end
    local arr = ensure_zstats();
    if arr == nil then
        return nil;
    end
    rec = T{
        id = id, act = act, band = band, name = name or 'Unknown',
        secs = 0, gil = 0, skill = 0,
        swings = 0, items = 0, breaks = 0, visits = 0, last = 0,
    };
    arr:append(rec);
    M.zone_stats[key] = rec;
    return rec;
end

--- Gil per hour over a record's whole recorded life in that zone.
local function rec_gil_hr(rec)
    if rec == nil or (rec.secs or 0) <= 0 then
        return 0;
    end
    return (rec.gil / rec.secs) * 3600;
end

--- Skill per hour, same basis.
local function rec_skill_hr(rec)
    if rec == nil or (rec.secs or 0) <= 0 then
        return 0;
    end
    return (rec.skill / rec.secs) * 3600;
end

M.rec_gil_hr = rec_gil_hr;
M.rec_skill_hr = rec_skill_hr;

local function metric_is_skill(settings)
    if settings == nil or settings.tracker == nil or settings.tracker.verdict_metric == nil then
        return false;
    end
    return settings.tracker.verdict_metric[1] == 'Skill';
end

local function rec_rate(rec, skill_metric)
    if skill_metric then
        return rec_skill_hr(rec);
    end
    return rec_gil_hr(rec);
end

----------------------------------------------------------------------
-- Current visit
----------------------------------------------------------------------

function M.start_zone_visit(zid, zname, act)
    act = act or M.active_tab;
    zid = tonumber(zid) or 0;
    local now = now_s();
    local cur = M.zone_visit;

    if M.parked_visits == nil then
        M.parked_visits = {};
    end

    -- Already standing here on this activity: nothing to restart.
    if cur ~= nil and (cur.id or 0) == zid and cur.act == act then
        cur.name = zname or cur.name;
        cur.last_action = 0;
        return;
    end

    -- Park the visit we are leaving, keyed by zone + activity, so bouncing
    -- Oldton -> Newton -> Oldton resumes the sample instead of wiping it.
    if cur ~= nil and (cur.id or 0) > 0 and cur.act ~= nil then
        cur.left_at = now;
        M.parked_visits[zkey(cur.act, cur.id)] = cur;
    end

    local key = zkey(act, zid);
    local parked = M.parked_visits[key];
    if parked ~= nil and (now - (parked.left_at or 0)) <= VISIT_RESUME_S and (parked.secs or 0) > 0 then
        parked.name = zname or parked.name;
        parked.last_action = 0;   -- travel time is not gathering time
        M.zone_visit = parked;
        M.parked_visits[key] = nil;
        return;
    end
    M.parked_visits[key] = nil;

    M.zone_visit = {
        id = zid,
        act = act,
        name = zname or 'Unknown',
        secs = 0, gil = 0, skill = 0,
        swings = 0, items = 0, breaks = 0, fails = 0,
        last_action = 0,
        started = now,
        left_at = 0,
    };

    local rec = zone_record(act, zid, zname, true);
    if rec ~= nil then
        rec.visits = (rec.visits or 0) + 1;
        rec.last = now;
        M.session_dirty = true;
    end
end

--- Advance the visit + aggregate clocks by the gap since the last action.
--- Gaps longer than the idle limit are dropped, so AFK time never counts.
local function zone_tick(act, id, name)
    local v = M.zone_visit;
    if v == nil or (v.id or 0) <= 0 then
        return nil, nil;
    end
    local rec = zone_record(v.act or act, v.id, v.name, true);
    local now = now_s();
    local last = v.last_action or 0;

    if last == 0 then
        v.last_action = now;
        return v, rec;
    end

    local gap = now - last;
    if gap > 0 and gap <= (M.idle_limit or 600) then
        v.secs = (v.secs or 0) + gap;
        if rec ~= nil then
            rec.secs = (rec.secs or 0) + gap;
            rec.last = now;
        end
    end
    v.last_action = now;
    return v, rec;
end

--- Record one counted swing against the current zone.
function M.zone_record_swing(act, gil, got_item, broke, failed)
    local v = M.zone_visit;
    if v == nil or (v.id or 0) <= 0 then
        return;
    end
    if v.act ~= act then
        -- Switched activity inside the same zone: start a fresh visit for it.
        M.start_zone_visit(v.id, v.name, act);
        v = M.zone_visit;
    end

    local _, rec = zone_tick(act, v.id, v.name);
    gil = tonumber(gil) or 0;

    local band = band_of(M.settings_ref ~= nil and M.skill_value(M.settings_ref, act) or 0);
    local brec = (band > 0) and zone_record(act, v.id, v.name, true, band) or nil;

    v.swings = (v.swings or 0) + 1;
    v.gil = (v.gil or 0) + gil;
    if got_item then v.items = (v.items or 0) + 1; end
    if broke then v.breaks = (v.breaks or 0) + 1; end
    if failed then v.fails = (v.fails or 0) + 1; end

    for _, r in ipairs({ rec, brec }) do
        if r ~= nil then
            r.swings = (r.swings or 0) + 1;
            r.gil = (r.gil or 0) + gil;
            if got_item then r.items = (r.items or 0) + 1; end
            if broke then r.breaks = (r.breaks or 0) + 1; end
        end
    end
    M.session_dirty = true;
end

--- Record a skill-up against the current zone.
function M.zone_record_skill(act, gain)
    local v = M.zone_visit;
    if v == nil or (v.id or 0) <= 0 then
        return;
    end
    gain = tonumber(gain) or 0;
    if gain <= 0 then
        return;
    end
    local _, rec = zone_tick(act, v.id, v.name);
    v.skill = (v.skill or 0) + gain;
    if rec ~= nil then
        rec.skill = (rec.skill or 0) + gain;
    end
    local band = band_of(M.settings_ref ~= nil and M.skill_value(M.settings_ref, act) or 0);
    if band > 0 then
        local brec = zone_record(act, v.id, v.name, true, band);
        if brec ~= nil then
            brec.skill = (brec.skill or 0) + gain;
        end
    end
    M.session_dirty = true;
end

--- Rate for the visit in progress.
function M.visit_rate(skill_metric)
    local v = M.zone_visit;
    if v == nil or (v.secs or 0) <= 0 then
        return 0;
    end
    local amount = skill_metric and (v.skill or 0) or (v.gil or 0);
    return (amount / v.secs) * 3600;
end

----------------------------------------------------------------------
-- Comparison
----------------------------------------------------------------------

--- Best zone for this activity other than `exclude_id`, among zones with
--- enough recorded time to be trustworthy.
function M.best_other_zone(act, exclude_id, skill_metric)
    if M.zone_stats == nil then
        M.index_zone_stats();
    end
    exclude_id = tonumber(exclude_id) or 0;
    local best, best_rate = nil, 0;
    for _, rec in pairs(M.zone_stats) do
        if rec.act == act and (tonumber(rec.band) or 0) == 0
            and (tonumber(rec.id) or 0) ~= exclude_id then
            if (rec.secs or 0) >= BENCH_MIN_SECS and (rec.swings or 0) >= BENCH_MIN_SWINGS then
                local r = rec_rate(rec, skill_metric);
                if r > best_rate then
                    best_rate = r;
                    best = rec;
                end
            end
        end
    end
    return best, best_rate;
end

--- Best zone for a metric. When `band` is given, prefer records from that
--- skill band and only fall back to all-time if the band is too thin to trust.
function M.best_zone_for(act, skill_metric, band)
    if M.zone_stats == nil then
        M.index_zone_stats();
    end

    local function scan(want_band, min_secs, min_swings)
        local best, best_rate = nil, 0;
        for _, rec in pairs(M.zone_stats) do
            if rec.act == act and (tonumber(rec.band) or 0) == want_band then
                if (rec.secs or 0) >= min_secs and (rec.swings or 0) >= min_swings then
                    local r = rec_rate(rec, skill_metric);
                    if r > best_rate then
                        best_rate = r;
                        best = rec;
                    end
                end
            end
        end
        return best, best_rate;
    end

    if band ~= nil and band > 0 then
        -- A band needs less evidence than the all-time benchmark, otherwise it
        -- would never qualify before you outgrew it.
        local rec, rate = scan(band, 300, 20);
        if rec ~= nil then
            return rec, rate, band;
        end
    end
    local rec, rate = scan(0, BENCH_MIN_SECS, BENCH_MIN_SWINGS);
    return rec, rate, 0;
end

--- Zones for this activity, ranked by rate.
function M.zone_ranking(act, skill_metric)
    if M.zone_stats == nil then
        M.index_zone_stats();
    end
    local list = {};
    for _, rec in pairs(M.zone_stats) do
        if rec.act == act and (tonumber(rec.band) or 0) == 0 and (rec.secs or 0) > 0 then
            list[#list + 1] = rec;
        end
    end
    -- Zones with a trustworthy sample rank above thin ones, so three lucky
    -- swings in a new zone never sit at the top of the list.
    local function solid(r)
        return (r.secs or 0) >= BENCH_MIN_SECS and (r.swings or 0) >= BENCH_MIN_SWINGS;
    end
    table.sort(list, function (a, b)
        local sa, sb = solid(a), solid(b);
        if sa ~= sb then
            return sa;
        end
        return rec_rate(a, skill_metric) > rec_rate(b, skill_metric);
    end);
    return list;
end

--- Stay or move? Returns nil when there is no zone yet.
--- label: SAMPLING (with remaining time) | BASELINE | STAY | MOVE | EVEN
function M.get_zone_verdict(settings, act)
    local v = M.zone_visit;
    if v == nil or (v.id or 0) <= 0 then
        return nil;
    end
    act = act or v.act or M.active_tab;
    if v.act ~= act then
        return nil;
    end

    local skill_metric = metric_is_skill(settings);
    local secs = tonumber(v.secs) or 0;
    local swings = tonumber(v.swings) or 0;
    local here = M.visit_rate(skill_metric);
    local rec = zone_record(act, v.id, v.name, false);
    local here_life = rec ~= nil and rec_rate(rec, skill_metric) or 0;

    local out = {
        here = here,
        here_life = here_life,
        secs = secs,
        swings = swings,
        skill_metric = skill_metric,
    };

    if secs < VERDICT_MIN_SECS or swings < VERDICT_MIN_SWINGS then
        local left = math.max(0, VERDICT_MIN_SECS - secs);
        local need = math.max(0, VERDICT_MIN_SWINGS - swings);
        out.label = 'SAMPLING';
        out.state = 'info';
        if left > 0 then
            out.label = 'SAMPLING ' .. format.format_duration(left);
        elseif need > 0 then
            out.label = string.format('SAMPLING %d', need);
        end
        return out;
    end

    local best, best_rate = M.best_other_zone(act, v.id, skill_metric);
    out.best = best;
    out.best_rate = best_rate;

    if best == nil or best_rate <= 0 then
        out.label = 'BASELINE';
        out.state = 'info';
        return out;
    end

    if here >= best_rate * 1.05 then
        out.label = 'STAY';
        out.state = 'good';
    elseif here <= best_rate * 0.85 then
        out.label = 'MOVE';
        out.state = 'bad';
    else
        out.label = 'EVEN';
        out.state = 'warn';
    end
    return out;
end

--- One-line summary for the panel.
--- The verdict detail split into its two halves: the rate here, and whatever we
--- are comparing it against. The panel needs them apart so a narrow window can
--- drop the comparison whole instead of truncating through a number.
function M.zone_verdict_parts(verdict)
    if verdict == nil then
        return nil, nil;
    end
    local function fmt(v)
        if verdict.skill_metric then
            return string.format('%.1f/hr', v or 0);
        end
        return format.format_int(math.floor((v or 0) + 0.5)) .. '/hr';
    end

    local here = fmt(verdict.here);
    local compare = nil;
    if verdict.best ~= nil and verdict.best_rate and verdict.best_rate > 0 then
        compare = 'vs ' .. (verdict.best.name or '?') .. ' ' .. fmt(verdict.best_rate);
    elseif (verdict.here_life or 0) > 0 then
        compare = 'avg ' .. fmt(verdict.here_life);
    end
    return here, compare;
end

function M.zone_verdict_line(verdict)
    local here, compare = M.zone_verdict_parts(verdict);
    if here == nil then
        return nil;
    end
    if compare ~= nil then
        return here .. '  ' .. compare;
    end
    return here;
end

--- /floos zones
function M.build_zone_report(settings, act)
    act = act or M.active_tab;
    local skill_metric = metric_is_skill(settings);
    local unit = skill_metric and 'skill/hr' or 'gil/hr';
    local lines = T{};
    lines:append('~~~~~~ Floos Zones (' .. (TAB_LABELS[act] or act) .. ', ' .. unit .. ') ~~~~~~');

    local v = M.zone_visit;
    if v ~= nil and (v.id or 0) > 0 and v.act == act then
        local rate = M.visit_rate(skill_metric);
        lines:append(string.format('Now: %s  -  %s',
            v.name or '?',
            skill_metric and string.format('%.2f/hr', rate)
                or (format.format_int(math.floor(rate + 0.5)) .. '/hr')));
        lines:append(string.format('  %s active, %d swings, %d items, %d breaks, %sg, %.1f skill',
            format.format_duration(v.secs or 0),
            v.swings or 0, v.items or 0, v.breaks or 0,
            format.format_int(v.gil or 0), v.skill or 0));

        local verdict = M.get_zone_verdict(settings, act);
        if verdict ~= nil then
            local msg = 'Verdict: ' .. verdict.label;
            if verdict.best ~= nil then
                msg = msg .. '  (best elsewhere: ' .. (verdict.best.name or '?') .. ')';
            end
            lines:append('  ' .. msg);
        end
    end

    local ranking = M.zone_ranking(act, skill_metric);
    if #ranking == 0 then
        lines:append('No zone data yet. Swing for a few minutes and it fills in.');
        return table.concat(lines, '\n');
    end

    lines:append('--- Lifetime, ranked (survives /floos clear) ---');
    for i, rec in ipairs(ranking) do
        if i > 10 then break; end
        local rate = rec_rate(rec, skill_metric);
        local thin = ((rec.secs or 0) < BENCH_MIN_SECS or (rec.swings or 0) < BENCH_MIN_SWINGS)
            and '  (thin sample)' or '';
        lines:append(string.format('%d. %s  %s  |  %s  %d swings%s',
            i,
            rec.name or '?',
            skill_metric and string.format('%.2f/hr', rate)
                or (format.format_int(math.floor(rate + 0.5)) .. '/hr'),
            format.format_duration(rec.secs or 0),
            rec.swings or 0,
            thin));
    end
    return table.concat(lines, '\n');
end

function M.clear_zone_stats()
    M.zone_stats = {};
    if M.settings_ref ~= nil and M.settings_ref.lifetime ~= nil then
        M.settings_ref.lifetime.zstats = T{};
    end
    local v = M.zone_visit;
    if v ~= nil then
        v.secs = 0; v.gil = 0; v.skill = 0;
        v.swings = 0; v.items = 0; v.breaks = 0; v.fails = 0;
    end
    M.session_dirty = true;
end

--- Lifetime dig accuracy (wins / all outcomes), or nil with no data.
function M.get_lifetime_accuracy()
    local w = tonumber(M.lifetime_wins) or 0;
    local m = tonumber(M.lifetime_misses) or 0;
    local b = tonumber(M.lifetime_break_only) or 0;
    local total = w + m + b;
    if total <= 0 then
        return nil;
    end
    return (w / total) * 100;
end

local function save_lifetime_skill()
    if M.settings_ref == nil then return; end
    if M.settings_ref.lifetime == nil then
        M.settings_ref.lifetime = T{
            gil_gained = T{ 0 },
            skill_w = T{ 0 },
            skill_m = T{ 0 },
            skill_b = T{ 0 },
            wins = T{ 0 },
            misses = T{ 0 },
            break_only = T{ 0 },
        };
    end
    if M.settings_ref.lifetime.skill_w == nil then M.settings_ref.lifetime.skill_w = T{ 0 }; end
    if M.settings_ref.lifetime.skill_m == nil then M.settings_ref.lifetime.skill_m = T{ 0 }; end
    if M.settings_ref.lifetime.skill_b == nil then M.settings_ref.lifetime.skill_b = T{ 0 }; end
    if M.settings_ref.lifetime.wins == nil then M.settings_ref.lifetime.wins = T{ 0 }; end
    if M.settings_ref.lifetime.misses == nil then M.settings_ref.lifetime.misses = T{ 0 }; end
    if M.settings_ref.lifetime.break_only == nil then M.settings_ref.lifetime.break_only = T{ 0 }; end
    M.settings_ref.lifetime.skill_w[1] = M.lifetime_skill_w or 0;
    M.settings_ref.lifetime.skill_m[1] = M.lifetime_skill_m or 0;
    M.settings_ref.lifetime.skill_b[1] = M.lifetime_skill_b or 0;
    M.settings_ref.lifetime.wins[1] = M.lifetime_wins or 0;
    M.settings_ref.lifetime.misses[1] = M.lifetime_misses or 0;
    M.settings_ref.lifetime.break_only[1] = M.lifetime_break_only or 0;
end

local function add_lifetime_outcome(oc)
    if oc == 'W' then
        M.lifetime_wins = (tonumber(M.lifetime_wins) or 0) + 1;
    elseif oc == 'M' then
        M.lifetime_misses = (tonumber(M.lifetime_misses) or 0) + 1;
    elseif oc == 'B' then
        M.lifetime_break_only = (tonumber(M.lifetime_break_only) or 0) + 1;
    else
        return;
    end
    save_lifetime_skill();
    M.session_dirty = true;
end

function M.add_lifetime_skill(oc)
    if oc == 'W' then
        M.lifetime_skill_w = (tonumber(M.lifetime_skill_w) or 0) + 1;
    elseif oc == 'M' then
        M.lifetime_skill_m = (tonumber(M.lifetime_skill_m) or 0) + 1;
    elseif oc == 'B' then
        M.lifetime_skill_b = (tonumber(M.lifetime_skill_b) or 0) + 1;
    else
        return;
    end
    save_lifetime_skill();
    M.session_dirty = true;
end


local OUTCOME_WINDOW_MS = 2500; -- skill-up must land within 2.5s of dig/miss/break

-- Rolling outcome history drives the swing strip. Pushed only from the counted
-- path so it always lines up with the Swings number.
local function push_history(s, oc)
    if s == nil or oc == nil then return; end
    if s.history == nil then s.history = {}; end
    s.history[#s.history + 1] = { oc = oc, skill = false };
    while #s.history > HISTORY_MAX do
        table.remove(s.history, 1);
    end
end

local function mark_history_skill(s)
    if s == nil then return; end
    s.flash_ms = now_ms();
    if s.history == nil then return; end
    local last = s.history[#s.history];
    if last ~= nil then
        last.skill = true;
    end
end

local function attribute_skill(s, oc)
    if oc == nil then return; end
    mark_history_skill(s);
    if oc == 'W' then
        s.skill_w = (s.skill_w or 0) + 1;
    elseif oc == 'M' then
        s.skill_m = (s.skill_m or 0) + 1;
    elseif oc == 'B' then
        s.skill_b = (s.skill_b or 0) + 1;
    else
        return;
    end
    M.add_lifetime_skill(oc);
end

local function flush_pending_to(s)
    local n = M.pending_skill_ups or 0;
    if n <= 0 or s == nil or s.last_outcome == nil then return; end
    local oc = s.last_outcome;
    for _ = 1, n do
        attribute_skill(s, oc);
    end
    M.pending_skill_ups = 0;
    M.pending_skill_act = nil;
end

local function set_outcome(s, oc)
    if s == nil or oc == nil then return; end
    s.last_outcome = oc;
    s.last_outcome_ms = now_ms();
    -- any skill-ups waiting for this swing
    flush_pending_to(s);
end

local function on_skill_up_for(s)
    if s == nil then
        M.pending_skill_ups = (M.pending_skill_ups or 0) + 1;
        return;
    end
    local oc = s.last_outcome;
    local ms = s.last_outcome_ms or 0;
    local age = now_ms() - ms;
    -- only trust outcome if it happened very recently (same swing)
    if oc ~= nil and ms > 0 and age >= 0 and age <= OUTCOME_WINDOW_MS then
        attribute_skill(s, oc);
    else
        -- skill text before dig/miss/break, or outcome too old
        M.pending_skill_ups = (M.pending_skill_ups or 0) + 1;
    end
end

function M.add_lifetime_gil(amount)
    amount = tonumber(amount) or 0;
    if amount <= 0 then
        return;
    end
    M.lifetime_gil = (tonumber(M.lifetime_gil) or 0) + amount;
    if M.settings_ref ~= nil then
        if M.settings_ref.lifetime == nil then
            M.settings_ref.lifetime = T{ gil_gained = T{ 0 } };
        end
        if M.settings_ref.lifetime.gil_gained == nil then
            M.settings_ref.lifetime.gil_gained = T{ 0 };
        end
        M.settings_ref.lifetime.gil_gained[1] = M.lifetime_gil;
    end
    M.session_dirty = true;
end

----------------------------------------------------------------------
-- Idle handling
--
-- HELM walks between points, so a gap either looks like ordinary play (count
-- all of it) or like you went away (count none of it). That is the ten minute
-- rule this addon has always used, and it stays.
--
-- Digging and fishing are paced by the game, not by you: a dig is one keypress
-- roughly every 16 seconds and you simply wait in between. Discarding those
-- gaps would leave the clock at zero and send gil/hr to infinity, so instead
-- the gap is CAPPED - the clock runs for a few seconds after each action and
-- then freezes until the next one. That is what makes gil/hr mean "gil per
-- second actually spent digging" rather than "gil per second stood around".
----------------------------------------------------------------------
local IDLE_RULE = {
    digging = { grace = 10, key = 'idle_grace' },
    -- Clamming points come back about every 10s, so the same capping rule
    -- as digging with a little slack for walking between points.
    clamming = { grace = 15, key = 'idle_grace' },
    fishing = { grace = 60, key = 'idle_grace' },
};

--- Seconds of grace after an action, and whether to cap or discard past it.
local function idle_rule(act)
    local r = IDLE_RULE[act];
    if r == nil then
        return M.idle_limit, 'discard';
    end
    local grace = r.grace;
    local st = M.settings_ref;
    if st ~= nil and st[act] ~= nil and st[act][r.key] ~= nil then
        local v = tonumber(st[act][r.key][1]);
        if v ~= nil and v > 0 then
            grace = v;
        end
    end
    return grace, 'cap';
end

M.idle_rule = idle_rule;

--- How much of a gap between two actions the session clock should count.
local function countable_gap(act, gap)
    gap = tonumber(gap) or 0;
    if gap <= 0 then
        return 0;
    end
    local limit, mode = idle_rule(act);
    if mode == 'cap' then
        if gap < limit then
            return gap;
        end
        return limit;
    end
    if gap < limit then
        return gap;
    end
    return 0;   -- clearly away; none of it was play
end

M.countable_gap = countable_gap;

function M.touch_activity(act)
    act = act or M.active_tab;
    local s = sess(act);
    s.last_activity_ms = now_ms();
end

function M.update_session_timer(act)
    act = act or M.active_tab;
    local s = sess(act);
    local now = now_s();
    local last = s.last_action or 0;
    if last == 0 then
        s.last_action = now;
        return;
    end
    local gap = now - last;
    if not s.paused then
        s.session_active = (s.session_active or 0) + countable_gap(act, gap);
    end
    s.last_action = now;
    M.session_dirty = true;
end

function M.get_session_seconds(act)
    act = act or M.active_tab;
    local s = sess(act);
    local active = s.session_active or 0;
    local last = s.last_action or 0;
    if last ~= 0 and not s.paused then
        active = active + countable_gap(act, now_s() - last);
    end
    return active;
end

function M.is_session_paused_idle(act)
    act = act or M.active_tab;
    local s = sess(act);
    if s.paused then
        return true;
    end
    local last = s.last_action or 0;
    if last == 0 then
        return false;
    end
    local limit = idle_rule(act);
    return (now_s() - last) >= limit;
end

--- Counters added for fishing and digging. Listed once so persist and restore
--- can never drift apart - the classic way a new stat silently stops saving.
local EXTRA_COUNTERS = {
    'bites', 'lost', 'lost_skill', 'line_breaks', 'monsters',
    'no_catch', 'cancels', 'hook_small', 'hook_large', 'hook_item',
    'rejected',
    -- digging daily limit, which lives on a real-life clock rather than the
    -- session, so it has to survive a relog like everything else here
    'daily_items', 'daily_day',
    -- clamming: the bucket has to survive a relog too, or a crash costs you
    -- a bucket you were still carrying
    'bucket_weight', 'bucket_capacity', 'kits', 'turnins',
    'overweight', 'incidents', 'last_find_s',
};

function M.persist_session()
    if M.settings_ref == nil then
        return;
    end
    if M.settings_ref.helm == nil then
        M.settings_ref.helm = T{};
    end
    for _, act in ipairs(ACTIVITIES) do
        local s = sess(act);
        local snap = M.settings_ref.helm[act];
        if snap == nil then
            M.settings_ref.helm[act] = T{
                swings = T{ 0 }, breaks = T{ 0 }, items = T{ 0 },
                skill_gain = T{ 0 }, session_active = T{ 0 }, last_action = T{ 0 },
                rewards = T{},
            };
            snap = M.settings_ref.helm[act];
        end
        snap.swings[1] = s.swings;
        snap.breaks[1] = s.breaks;
        snap.items[1] = s.items;
        snap.skill_gain[1] = s.skill_gain;
        if snap.skill_w == nil then snap.skill_w = T{ 0 }; end
        if snap.skill_m == nil then snap.skill_m = T{ 0 }; end
        if snap.skill_b == nil then snap.skill_b = T{ 0 }; end
        snap.skill_w[1] = s.skill_w or 0;
        snap.skill_m[1] = s.skill_m or 0;
        snap.skill_b[1] = s.skill_b or 0;
        snap.session_active[1] = s.session_active or 0;
        snap.last_action[1] = s.last_action or 0;
        if snap.steals == nil then snap.steals = T{ 0 }; end
        if snap.steal_attempts == nil then snap.steal_attempts = T{ 0 }; end
        if snap.raw_gil == nil then snap.raw_gil = T{ 0 }; end
        if snap.gold_rush == nil then snap.gold_rush = T{ 0 }; end
        if snap.motherlode == nil then snap.motherlode = T{ 0 }; end
        -- fishing / digging counters
        for _, k in ipairs(EXTRA_COUNTERS) do
            if snap[k] == nil then snap[k] = T{ 0 }; end
            snap[k][1] = s[k] or 0;
        end
        snap.steals[1] = s.steals or 0;
        snap.steal_attempts[1] = s.steal_attempts or 0;
        snap.raw_gil[1] = s.raw_gil or 0;
        if snap.exp == nil then snap.exp = T{ 0 }; end
        if snap.limit == nil then snap.limit = T{ 0 }; end
        snap.exp[1] = s.exp or 0;
        snap.limit[1] = s.limit or 0;
        snap.gold_rush[1] = s.gold_rush or 0;
        snap.motherlode[1] = s.motherlode or 0;
        snap.rewards = T{};
        for k, v in pairs(s.rewards) do
            snap.rewards[k] = v;
        end
        -- The clamming bucket is unbanked value you are still carrying.
        -- Losing it to a crash or a relog would be the addon costing you
        -- real gil, so it saves exactly like the reward list does.
        snap.bucket = T{};
        if s.bucket ~= nil then
            for k, v in pairs(s.bucket) do
                snap.bucket[k] = v;
            end
        end
        if snap.bucket_broken == nil then snap.bucket_broken = T{ false }; end
        snap.bucket_broken[1] = (s.bucket_broken == true);
    end
    -- legacy mining fields for compatibility
    if M.settings_ref.mining ~= nil then
        M.settings_ref.mining.session_active[1] = M.sessions.mining.session_active or 0;
        M.settings_ref.mining.last_mine[1] = M.sessions.mining.last_action or 0;
    end
end

function M.restore_session()
    if M.settings_ref == nil then
        return;
    end
    -- Start from blank and load only what the table actually has. Restoring
    -- on top of live sessions would let the previous character's numbers leak
    -- through wherever this character has nothing saved - and the next
    -- autosave would then write them into the wrong character's file.
    for _, act in ipairs(ACTIVITIES) do
        M.sessions[act] = blank_session();
    end
    if M.settings_ref.helm ~= nil then
        for _, act in ipairs(ACTIVITIES) do
            local snap = M.settings_ref.helm[act];
            if snap ~= nil then
                local s = sess(act);
                s.swings = (snap.swings and snap.swings[1]) or 0;
                s.breaks = (snap.breaks and snap.breaks[1]) or 0;
                s.items = (snap.items and snap.items[1]) or 0;
                s.skill_gain = (snap.skill_gain and snap.skill_gain[1]) or 0;
                s.skill_w = (snap.skill_w and snap.skill_w[1]) or 0;
                s.skill_m = (snap.skill_m and snap.skill_m[1]) or 0;
                s.skill_b = (snap.skill_b and snap.skill_b[1]) or 0;
                s.session_active = (snap.session_active and snap.session_active[1]) or 0;
                s.last_action = (snap.last_action and snap.last_action[1]) or 0;
                s.steals = (snap.steals and snap.steals[1]) or 0;
                s.steal_attempts = (snap.steal_attempts and snap.steal_attempts[1]) or 0;
                s.raw_gil = (snap.raw_gil and snap.raw_gil[1]) or 0;
                s.exp = (snap.exp and snap.exp[1]) or 0;
                s.limit = (snap.limit and snap.limit[1]) or 0;
                s.gold_rush = (snap.gold_rush and snap.gold_rush[1]) or 0;
                s.motherlode = (snap.motherlode and snap.motherlode[1]) or 0;
                for _, k in ipairs(EXTRA_COUNTERS) do
                    s[k] = (snap[k] and snap[k][1]) or 0;
                end
                s.rewards = T{};
                if snap.rewards ~= nil then
                    for k, v in pairs(snap.rewards) do
                        s.rewards[k] = v;
                    end
                end
                s.bucket = T{};
                if snap.bucket ~= nil then
                    for k, v in pairs(snap.bucket) do
                        s.bucket[k] = v;
                    end
                end
                s.bucket_broken = (snap.bucket_broken and snap.bucket_broken[1]) == true;
            end
        end
    elseif M.settings_ref.session ~= nil then
        -- migrate old single-mining session
        local s = M.sessions.mining;
        local old = M.settings_ref.session;
        s.swings = (old.swings and old.swings[1]) or 0;
        s.breaks = (old.breaks and old.breaks[1]) or 0;
        s.items = (old.items and old.items[1]) or 0;
        s.skill_gain = (old.skill_gain and old.skill_gain[1]) or 0;
        s.rewards = T{};
        if old.rewards ~= nil then
            for k, v in pairs(old.rewards) do s.rewards[k] = v; end
        end
        if M.settings_ref.mining ~= nil then
            s.session_active = M.settings_ref.mining.session_active[1] or 0;
            s.last_action = M.settings_ref.mining.last_mine[1] or 0;
        end
    end
end

--- Clearing a session must not clear the digging DAILY count. That number
--- belongs to the server's clock, not to yours: the items are spent whether
--- or not you press clear, and zeroing it here would quietly tell you that
--- 160 more are available when the server thinks otherwise.
local function carry_daily(a, fresh)
    local old = M.sessions[a];
    if old ~= nil then
        fresh.daily_items = old.daily_items or 0;
        fresh.daily_day = old.daily_day or 0;
    end
    return fresh;
end

function M.reset_session(act)
    if act == nil or act == 'all' then
        for _, a in ipairs(ACTIVITIES) do
            M.sessions[a] = carry_daily(a, blank_session());
        end
    else
        M.sessions[act] = carry_daily(act, blank_session());
    end

    M.persist_session();
    M.session_dirty = true;
end


function M.pause_session(act)
    act = act or M.active_tab;
    local s = sess(act);
    if not s.paused then
        s.paused = true;
        s.session_active = M.get_session_seconds(act);
        s.last_action = now_s();
    end
end

function M.resume_session(act)
    act = act or M.active_tab;
    local s = sess(act);
    if s.paused then
        s.paused = false;
        s.last_action = now_s();
        M.touch_activity(act);
    end
end

function M.tick_autosave()
    journal.tick();
    if not M.session_dirty then
        return;
    end
    if (now_ms() - M.session_last_save_ms) < SESSION_AUTOSAVE_MS then
        return;
    end
    M.persist_session();
    settings_lib.save();
    M.session_dirty = false;
    M.session_last_save_ms = now_ms();
end

function M.get_accuracy(act)
    local s = sess(act or M.active_tab);
    if s.swings <= 0 then return 0; end
    return (s.items / s.swings) * 100;
end

--- What the clamming bucket is worth if you cash it in right now. Kept
--- apart from the session total on purpose: items in the bucket are worth
--- nothing at all until Toh Zonikki takes the kit, and a burst bucket must
--- not leave phantom gil in the session numbers.
function M.get_bucket_value(pricing, act)
    act = act or 'clamming';
    local s = sess(act);
    if s == nil or s.bucket == nil or pricing == nil then
        return 0;
    end
    local total = 0;
    for name, count in pairs(s.bucket) do
        local unit = tonumber(pricing[normalize_key(name)]) or 0;
        total = total + (unit * count);
    end
    return total;
end

function M.get_total_worth(act, pricing)
    local s = sess(act);
    local total = 0;
    for name, count in pairs(s.rewards) do
        local price = tonumber(pricing[normalize_key(name)]) or 0;
        total = total + price * count;
    end
    if act == 'hunting' then
        total = total + (s.raw_gil or 0);
    end
    return total;
end

local function tool_cost(settings, act)
    if act == 'mining' or act == 'excavate' then
        return settings.mining.pickaxe_cost[1] or 120;
    elseif act == 'logging' then
        return (settings.logging and settings.logging.hatchet_cost and settings.logging.hatchet_cost[1]) or 300;
    elseif act == 'harvest' then
        return (settings.harvest and settings.harvest.sickle_cost and settings.harvest.sickle_cost[1]) or 400;
    elseif act == 'fishing' then
        return (settings.fishing and settings.fishing.bait_cost and settings.fishing.bait_cost[1]) or 0;
    elseif act == 'digging' then
        return (settings.digging and settings.digging.green_cost and settings.digging.green_cost[1]) or 0;
    elseif act == 'clamming' then
        return (settings.clamming and settings.clamming.kit_cost and settings.clamming.kit_cost[1])
            or (constants.CLAM_KIT_COST or 500);
    end
    return 0;
end

--- How many consumables this session actually burned. Mining and friends spend
--- a tool only when it breaks, but fishing spends bait on every BITE and
--- digging spends a green on every accepted DIG - so the thing being counted
--- is different per activity, and billing them all off `breaks` would be
--- wrong by an order of magnitude.
local function tool_used(act, s)
    if s == nil then
        return 0;
    end
    if act == 'fishing' then
        return s.bites or 0;
    elseif act == 'digging' then
        return s.swings or 0;
    elseif act == 'clamming' then
        -- One kit, one 500 gil charge - not one per dig.
        return s.kits or 0;
    end
    return s.breaks or 0;
end

M.tool_used = tool_used;

local function tool_subtract(settings, act)
    if act == 'mining' or act == 'excavate' then
        return settings.mining.pickaxe_subtract[1];
    elseif act == 'logging' then
        return settings.logging and settings.logging.hatchet_subtract and settings.logging.hatchet_subtract[1];
    elseif act == 'harvest' then
        return settings.harvest and settings.harvest.sickle_subtract and settings.harvest.sickle_subtract[1];
    elseif act == 'fishing' then
        return settings.fishing and settings.fishing.bait_subtract and settings.fishing.bait_subtract[1];
    elseif act == 'digging' then
        return settings.digging and settings.digging.green_subtract and settings.digging.green_subtract[1];
    elseif act == 'clamming' then
        return settings.clamming and settings.clamming.kit_subtract
            and settings.clamming.kit_subtract[1];
    end
    return false;
end

function M.get_net_gil(act, settings, pricing)
    local total = M.get_total_worth(act, pricing);
    local s = sess(act);
    if tool_subtract(settings, act) then
        total = total - (tool_used(act, s) * tool_cost(settings, act));
    end
    return total;
end

function M.get_gph(act, settings, pricing)
    local elapsed = M.get_session_seconds(act);
    if elapsed <= 0 then return 0; end
    return math.floor((M.get_net_gil(act, settings, pricing) / elapsed) * 3600);
end

local function count_tool(act)
    resolve_tool_ids();
    local id = TOOL_IDS[act];
    if id == nil then return 0; end
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local total = 0;
    for y = 0, 80 do
        local item = inv:GetContainerItem(0, y);
        if item ~= nil and item.Id == id then
            total = total + item.Count;
        end
    end
    return total;
end

-- settings group + key that holds each activity's skill level.
local SKILL_FIELD = {
    mining   = { 'mining',   'mine_skill' },
    logging  = { 'logging',  'log_skill' },
    harvest  = { 'harvest',  'harvest_skill' },
    excavate = { 'excavate', 'exca_skill' },
    fishing  = { 'fishing',  'fish_skill' },
    digging  = { 'digging',  'dig_skill' },
};

local function skill_value(settings, act)
    local f = SKILL_FIELD[act];
    if f == nil or settings == nil then
        return nil;
    end
    local group = settings[f[1]];
    if group == nil or group[f[2]] == nil then
        return nil;
    end
    return tonumber(group[f[2]][1]) or 0;
end

--- Write a parsed skill level back into settings, creating the slot if needed.
local function set_skill_value(settings, act, level)
    local f = SKILL_FIELD[act];
    if f == nil or settings == nil then
        return;
    end
    local group = settings[f[1]];
    if group == nil then
        return;
    end
    if group[f[2]] == nil then
        group[f[2]] = T{ 0 };
    end
    group[f[2]][1] = level;
end

M.skill_value = skill_value;

local function skill_display_enabled(settings, act)
    local f = SKILL_FIELD[act];
    if f == nil or settings == nil then
        return false;
    end
    local group = settings[f[1]];
    if group == nil or group.skillup_display == nil then
        return false;
    end
    return group.skillup_display[1] == true;
end

--- Chocobo digging has no rank stat of its own: the rank IS the skill.
--- Digging is an ordinary craft-style skill (id 59) and the server ranks it
--- up every 10.0 displayed skill, exactly like a craft - the dig script's
--- own comment says "increment rank once player hits 10.0, 20.0, .. 100.0"
--- and the rank-up test is (skillRank * 100) + 100 internal points.
--- So asking the player for a rank was asking them to do arithmetic the
--- addon can do itself from the skill it already tracks.
local function dig_rank_from_skill(skill)
    local rank = math.floor((tonumber(skill) or 0) / 10);
    if rank < 0 then rank = 0; end
    if rank > 10 then rank = 10; end
    return rank;
end

M.dig_rank_from_skill = dig_rank_from_skill;

--- The digging daily limit: 100 items at Amateur, +10 per rank, 200 at
--- Expert. Horizon documents this exactly.
local function dig_daily_cap(settings)
    local skill = 0;
    if settings ~= nil and settings.digging ~= nil and settings.digging.dig_skill ~= nil then
        skill = tonumber(settings.digging.dig_skill[1]) or 0;
    end
    return 100 + (dig_rank_from_skill(skill) * 10);
end

M.dig_daily_cap = dig_daily_cap;

--- Roll the digging daily counter over at Japanese midnight, which is what
--- the server itself uses: the dig script stores the count with an expiry of
--- NextJstDay(). 00:00 JST is 15:00 UTC - 6PM in Kuwait. Cheap enough to
--- call on every render and on every dig.
local function roll_dig_day(s)
    if s == nil then
        return;
    end
    local today = vana.jst_day();
    if (s.daily_day or 0) ~= today then
        s.daily_day = today;
        s.daily_items = 0;
    end
end

M.roll_dig_day = roll_dig_day;

--- Horizon's HELM fatigue is NOT a flat 200, and it is not tied to your
--- character level either. Their wiki documents it growing with your
--- GATHERING rank and being set per zone - West Sarutabaruta goes to 250 at
--- Initiate and 300 at Novice - and the base number is published nowhere.
--- So rather than invent a formula, the addon believes what it sees: gather
--- past the configured cap and the cap moves up to match. It only ever goes
--- up, and only from something that actually happened.
local function learn_fatigue_cap(settings, act, observed)
    if settings == nil or NON_HELM[act] then
        return;
    end
    local group = settings[act];
    if group == nil or group.fatigue_cap == nil then
        return;
    end
    local cap = tonumber(group.fatigue_cap[1]) or 0;
    if cap > 0 and observed > cap then
        group.fatigue_cap[1] = observed;
        debug_note('fatigue', string.format('%s cap raised to %d (saw it)', act, observed));
    end
end

M.learn_fatigue_cap = learn_fatigue_cap;

local function fatigue_cap(settings, act)
    if act == 'mining' then
        return settings.mining.fatigue_cap[1] or 200;
    elseif act == 'logging' then
        return (settings.logging and settings.logging.fatigue_cap and settings.logging.fatigue_cap[1]) or 200;
    elseif act == 'harvest' then
        return (settings.harvest and settings.harvest.fatigue_cap and settings.harvest.fatigue_cap[1]) or 200;
    elseif act == 'excavate' then
        return (settings.excavate and settings.excavate.fatigue_cap and settings.excavate.fatigue_cap[1]) or 200;
    elseif act == 'digging' then
        -- Digging's limit is a real-life daily ITEM cap that grows with rank,
        -- and rank is just the skill divided by ten.
        return dig_daily_cap(settings);
    elseif act == 'clamming' then
        -- Clamming has no fatigue and no daily limit. The bucket IS the
        -- limit, and it is shown as its own meter.
        return nil;
    elseif act == 'fishing' then
        -- Horizon has no fishing fatigue at all. Each body of water holds a
        -- stock of each fish instead, shared by everyone, restocking on the
        -- Vana'diel clock. So there is no personal cap to show.
        return nil;
    end
    return 200;
end

------------------------------------------------------------------------
-- Clamming: how dangerous is one more dig?
--
-- This is the whole point of the Clam tab. A bucket is all-or-nothing: go
-- one ponze over and everything in it is washed back into the sea. So the
-- question is never "how heavy am I", it is "what are the odds the next dig
-- costs me everything, and how much is everything worth right now".
--
-- Both halves of that are knowable. Horizon publishes the item weights, and
-- publishes how often each item turns up (n = 5,424). Add the abundance of
-- every item heavier than your remaining headroom and you have the real
-- chance of a break, not a vibe. On a 200 pz bucket the mandragora incident
-- is added on top, since that one does not care how full you are.
------------------------------------------------------------------------

local function clam_weight_of(name)
    if name == nil then return constants.CLAM_DEFAULT_WEIGHT or 6, false; end
    local w = constants.CLAM_WEIGHTS and constants.CLAM_WEIGHTS[string.lower(name)];
    if w == nil then
        return constants.CLAM_DEFAULT_WEIGHT or 6, false;
    end
    return w, true;
end

M.clam_weight_of = clam_weight_of;

--- Pure, so it can be tested without a game. Returns:
---   headroom     ponzes left before the bucket bursts
---   break_pct    chance the next dig ends the bucket, 0-100
---   overflow_pct just the too-heavy part of that
---   incident_pct just the mandragora part
---   worst        heaviest item that still fits (nil if nothing fits)
---   tier         'safe' | 'watch' | 'risky' | 'stop'
function M.clam_risk(weight, capacity, hq_body)
    weight = tonumber(weight) or 0;
    capacity = tonumber(capacity) or (constants.CLAM_START_CAPACITY or 50);
    local headroom = capacity - weight;
    if headroom < 0 then headroom = 0; end

    -- Anything heavier than the headroom bursts the bucket.
    local overflow = 0;
    local abundance = constants.CLAM_ABUNDANCE or {};
    for name, pct in pairs(abundance) do
        local w = clam_weight_of(name);
        if w > headroom then
            overflow = overflow + pct;
        end
    end
    if overflow > 100 then overflow = 100; end

    -- The 200 pz bucket has its own hazard, independent of how full it is.
    local incident = 0;
    if capacity >= (constants.CLAM_INCIDENT_CAPACITY or 200) then
        incident = hq_body and (constants.CLAM_INCIDENT_PCT_HQ or 5)
            or (constants.CLAM_INCIDENT_PCT or 10);
    end

    -- Independent hazards, so combine rather than add: 1 - (1-a)(1-b).
    local total = 100 * (1 - ((1 - overflow / 100) * (1 - incident / 100)));

    local tier;
    if total <= 0.001 then
        tier = 'safe';
    elseif total < 5 then
        tier = 'watch';
    elseif total < 20 then
        tier = 'risky';
    else
        tier = 'stop';
    end

    return {
        headroom = headroom,
        break_pct = total,
        overflow_pct = overflow,
        incident_pct = incident,
        tier = tier,
        capacity = capacity,
        weight = weight,
    };
end

--- Seconds until this clamming point is ready again, and whether it is.
--- The cooldown is per point and per player, and it starts when the dig
--- resolves rather than when you click - so it is measured from the find.
--- Horizon runs 10s; the stock server is 16s cut to 10s by the swimsuit legs,
--- which is why this is a setting rather than a constant.
function M.clam_cooldown(last_find_s, now, delay)
    delay = tonumber(delay) or (constants.CLAM_POINT_RESPAWN or 10);
    last_find_s = tonumber(last_find_s) or 0;
    now = tonumber(now) or 0;
    if last_find_s <= 0 then
        return 0, true;      -- nothing dug yet, so nothing to wait for
    end
    local left = delay - (now - last_find_s);
    if left <= 0 then
        return 0, true;
    end
    if left > delay then
        left = delay;        -- clock went backwards; do not invent a longer wait
    end
    return left, false;
end

--- Would Toh Zonikki offer the next bucket size for this haul? He does at
--- (capacity - 5) pz, and the upgrade is per kit, so you start at 50 again
--- every time regardless.
function M.clam_upgrade_ready(weight, capacity)
    weight = tonumber(weight) or 0;
    capacity = tonumber(capacity) or (constants.CLAM_START_CAPACITY or 50);
    local caps = constants.CLAM_CAPACITIES or { 50, 100, 150, 200 };
    local top = caps[#caps] or 200;
    if capacity >= top then
        return false;
    end
    return weight >= (capacity - (constants.CLAM_UPGRADE_MARGIN or 5));
end

------------------------------------------------------------------------
-- Elemental ore watch
--
-- Elemental ores are a CHOCOBO DIGGING mechanic, not a mining one. The
-- Horizon Mining page documents no weather, moon, day or rank gated items
-- at all; the Chocobo Digging page documents four gates that must all hold
-- at once, which is exactly the kind of thing a tracker should watch for
-- you instead of making you count moons in your head.
--
--   1. digging rank at least Craftsman (6)
--   2. moon waxing crescent, roughly 7% - 24%
--   3. an active weather in the area - Fog counts
--   4. the zone is not a Rise of the Zilart area
--
-- The ore's element follows the Vana'diel day of the week.
--
-- Reported rate is about 5 ores in 1120 digs, so this is a "dig here rather
-- than there while the window is open" tool, not a payday predictor.
------------------------------------------------------------------------

local function dig_rank_name(rank)
    local name = constants.DIG_RANKS and constants.DIG_RANKS[rank];
    if name == nil then
        return string.format('rank %d', rank or 0);
    end
    return name;
end

--- Pure: takes everything it needs as arguments so it can be tested without
--- a game attached. ok is true / false / nil, and nil means "cannot tell".
--- A single false is a hard no; nil only downgrades a yes to a maybe.
function M.ore_check(input)
    input = input or {};

    local rank = tonumber(input.rank) or 0;
    if rank < 0 then rank = 0; end
    if rank > 10 then rank = 10; end

    local moon = input.moon;
    local wx = input.weather or {};
    local zone_id = tonumber(input.zone_id) or 0;
    local weekday = input.weekday;

    local min_rank = constants.ORE_MIN_RANK or 6;
    local moon_min = constants.ORE_MOON_MIN or 7;
    local moon_max = constants.ORE_MOON_MAX or 24;

    local conds = {};

    -- 1. Rank. Always knowable - it is a setting - so this is never nil.
    conds[#conds + 1] = {
        key = 'rank',
        label = 'Rank',
        ok = (rank >= min_rank),
        detail = string.format('%s (%d)', dig_rank_name(rank), rank),
        want = string.format('%s (%d)+', dig_rank_name(min_rank), min_rank),
    };

    -- 2. Moon.
    local moon_ok, moon_detail;
    if moon == nil then
        moon_ok = nil;
        moon_detail = 'unknown';
    else
        moon_ok = vana.moon_in_waxing_window(moon, moon_min, moon_max);
        moon_detail = string.format('%s %d%%', moon.name or '?', moon.percent or 0);
    end
    conds[#conds + 1] = {
        key = 'moon',
        label = 'Moon',
        ok = moon_ok,
        detail = moon_detail,
        want = string.format('Waxing Crescent %d-%d%%', moon_min, moon_max),
    };

    -- 3. Weather. Unknown until a zone-in or weather-change packet lands,
    -- and unknown is honestly reported rather than guessed as clear.
    local wx_ok, wx_detail;
    if not wx.known then
        wx_ok = nil;
        wx_detail = 'unknown';
    else
        wx_ok = (wx.counts_for_ore == true);
        wx_detail = wx.name or 'unknown';
        if wx.double then
            wx_detail = wx_detail .. ' x2';
        end
    end
    conds[#conds + 1] = {
        key = 'weather',
        label = 'Weather',
        ok = wx_ok,
        detail = wx_detail,
        want = 'any active weather (Fog counts)',
    };

    -- 4. Zone.
    local zone_ok, zone_detail, not_dig_zone;
    if zone_id <= 0 then
        zone_ok = nil;
        zone_detail = 'unknown';
    elseif constants.ROZ_ZONES and constants.ROZ_ZONES[zone_id] then
        zone_ok = false;
        zone_detail = 'Zilart area';
    elseif constants.DIG_ZONES and not constants.DIG_ZONES[zone_id] then
        -- Not a digging zone at all. Nothing on this tab applies here, so the
        -- caller is told to say nothing rather than spend a line on it.
        zone_ok = false;
        zone_detail = 'not a dig zone';
        not_dig_zone = true;
    else
        zone_ok = true;
        zone_detail = 'eligible';
    end
    conds[#conds + 1] = {
        key = 'zone',
        label = 'Zone',
        ok = zone_ok,
        detail = zone_detail,
        want = 'non-Zilart dig zone',
    };

    local blockers, unknowns = {}, {};
    for _, c in ipairs(conds) do
        if c.ok == false then
            blockers[#blockers + 1] = c.label;
        elseif c.ok == nil then
            unknowns[#unknowns + 1] = c.label;
        end
    end

    local verdict = 'yes';
    if #blockers > 0 then
        verdict = 'no';
    elseif #unknowns > 0 then
        verdict = 'maybe';
    end

    return {
        verdict = verdict,
        conds = conds,
        blockers = blockers,
        unknowns = unknowns,
        element = weekday and weekday.element or nil,
        day = weekday and weekday.name or nil,
        rank = rank,
        not_dig_zone = (not_dig_zone == true),
    };
end

--- Live wrapper: gathers rank, moon, weather and zone off the running game
--- and hands them to the pure check above.
function M.ore_conditions(settings)
    settings = settings or M.settings_ref or {};

    local rank = 0;
    if settings.digging and settings.digging.dig_skill then
        rank = dig_rank_from_skill(tonumber(settings.digging.dig_skill[1]) or 0);
    end

    local ts, moon, weekday;
    local ok_ts, got = pcall(vana.get_timestamp);
    if ok_ts and got ~= nil then
        ts = got;
        pcall(function ()
            moon = vana.get_moon(ts);
            weekday = vana.get_weekday(ts);
        end);
    end

    local wx = { known = false };
    pcall(function () wx = weather.current(); end);

    local result = M.ore_check({
        rank = rank,
        moon = moon,
        weather = wx,
        zone_id = M.zone_id or 0,
        weekday = weekday,
    });

    -- How long until the moon gate opens again. Only worth showing when the
    -- moon is the thing standing in the way.
    result.moon_days = nil;
    if moon ~= nil and ts ~= nil
        and not vana.moon_in_waxing_window(moon, constants.ORE_MOON_MIN, constants.ORE_MOON_MAX) then
        pcall(function ()
            result.moon_days = vana.days_until_waxing_window(ts,
                constants.ORE_MOON_MIN, constants.ORE_MOON_MAX);
        end);
    end

    return result;
end

--- Where the trade packet keeps the index of the thing being traded to.
--- Layout of outgoing 0x036 (GP_CLI_ITEM_TRANSFER), offsets from the start of
--- the packet including the 4-byte header:
---   0x04  UniqueNo              server id of the target
---   0x08  ItemNumTbl[10]        quantities
---   0x30  PropertyItemIndexTbl  inventory slots
---   0x3A  ActIndex              target index   <- this one
---   0x3C  ItemNum
--- Total size 0x40.
local TRADE_ACTINDEX_OFFSET = 0x3A;
local TRADE_UNIQUENO_OFFSET = 0x04;
local MAX_ENTITY_INDEX = 0x900;

local function read_u16(data, offset)
    -- string.byte is 1-based, packet offsets are 0-based.
    local lo = data:byte(offset + 1);
    local hi = data:byte(offset + 2);
    if lo == nil or hi == nil then
        return nil;
    end
    return lo + (hi * 256);
end

--- The target index straight out of the packet. This is what the server itself
--- reads, so it is right regardless of what the client happens to be targeting
--- - which is the whole point: a <stnpc> or <lastst> macro trades to a point
--- that is not your main target, and reading the UI would miss it entirely.
local function packet_target_index(e)
    if e == nil or e.data == nil then
        return nil;
    end
    local data = e.data;
    if #data < (TRADE_ACTINDEX_OFFSET + 2) then
        return nil;
    end
    local idx = read_u16(data, TRADE_ACTINDEX_OFFSET);
    if idx == nil or idx <= 0 or idx >= MAX_ENTITY_INDEX then
        return nil;
    end
    return idx;
end

local function entity_name(idx)
    if idx == nil or idx <= 0 then
        return nil;
    end
    local ok, name = pcall(function ()
        local ent = GetEntity(idx);
        if ent == nil or ent.Name == nil or ent.Name == '' then
            return nil;
        end
        return tostring(ent.Name);
    end);
    if ok then
        return name;
    end
    return nil;
end

local function ui_target_index(slot)
    local ok, idx = pcall(function ()
        return AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(slot);
    end);
    if ok and type(idx) == 'number' and idx > 0 then
        return idx;
    end
    return nil;
end

--- Outgoing client action packet (0x01A / GP_CLI_ACTION). ActionID sits at
--- offset 0x0A and says which action it is:
---   0x0E  cast a fishing rod
---   0x11  chocobo dig
--- Unlike HELM this needs no target-name check - the id alone is unambiguous.
local ACTION_ID_OFFSET = 0x0A;
local ACTION_FISH = 0x0E;
local ACTION_DIG  = 0x11;

local function action_id(e)
    if e == nil or e.data == nil then
        return nil;
    end
    local data = e.data;
    if #data < (ACTION_ID_OFFSET + 2) then
        return nil;
    end
    return read_u16(data, ACTION_ID_OFFSET);
end

--- Fishing and digging both begin with the player pressing the button, so the
--- outgoing packet is the honest "an attempt started" signal.
function M.handle_action_packet(e)
    local id = action_id(e);
    if id == nil then
        return;
    end

    local act = nil;
    if id == ACTION_FISH then
        act = 'fishing';
    elseif id == ACTION_DIG then
        act = 'digging';
    else
        return;
    end

    debug_note('action', act .. ' attempt sent');

    local s = sess(act);
    M.active_tab = act;
    M.update_session_timer(act);
    M.touch_activity(act);

    if act == 'fishing' then
        -- A cast is only counted here; whether it bites is decided by chat.
        s.swings = (s.swings or 0) + 1;
        M.awaiting = 'fishing';
        M.awaiting_ms = now_ms();
    else
        -- A dig may still be refused ("wait longer"), which costs no green.
        -- Count it provisionally and take it back if the refusal arrives.
        s.swings = (s.swings or 0) + 1;
        M.dig_pending_ms = now_ms();
    end

    M.session_dirty = true;
    if M.settings_ref ~= nil then
        if M.settings_ref.tracker.visible[1] == false then
            M.settings_ref.tracker.visible[1] = true;
        end
        if M.settings_ref.panels_hidden ~= nil then
            M.settings_ref.panels_hidden[1] = false;
        end
    end
end

--- Incoming packets. Only weather so far, and only two ids, so this stays
--- cheap: anything else falls straight through.
function M.handle_packet_in(e)
    if e == nil or e.id == nil then
        return;
    end
    if e.id == constants.PACKET_WEATHER or e.id == constants.PACKET_ZONE_IN then
        local before = weather.current();
        weather.handle_packet_in(e);
        local after = weather.current();
        if after.known and (not before.known or before.id ~= after.id) then
            debug_note('weather', string.format('%s (%s)', after.name, after.source or '?'));
        end
    end
end

function M.handle_packet_out(e)
    if e.id == constants.PACKET_ACTION then
        M.handle_action_packet(e);
        return;
    end
    if e.id ~= constants.PACKET_HELM then
        return;
    end

    -- Packet first, because it is authoritative. The UI target and subtarget
    -- are only fallbacks for a client that hands us a packet we cannot read.
    local sources = {
        { how = 'packet',    idx = packet_target_index(e) },
        { how = 'target',    idx = ui_target_index(0) },
        { how = 'subtarget', idx = ui_target_index(1) },
    };

    local act, how, point = nil, nil, nil;
    local seen = {};
    for _, src in ipairs(sources) do
        local name = entity_name(src.idx);
        if name ~= nil then
            seen[#seen + 1] = src.how .. '=' .. name;
            if act == nil then
                local found = point_activity(name);
                if found ~= nil then
                    act, how, point = found, src.how, name;
                end
            end
        end
    end

    if act == nil then
        debug_note('trade', (#seen > 0)
            and ('no gathering point in: ' .. table.concat(seen, ', '))
            or 'traded, but no target was readable at all');
        return;
    end

    debug_note('swing', string.format('%s at %s (via %s)', act, point, how));

    M.awaiting = act;
    M.awaiting_ms = now_ms();
    M.active_tab = act; -- auto-switch tab to the activity you're doing
    M.update_session_timer(act);
    M.touch_activity(act);
    if M.settings_ref ~= nil and M.settings_ref.tracker.visible[1] == false then
        M.settings_ref.tracker.visible[1] = true;
    end
    if M.settings_ref ~= nil and M.settings_ref.panels_hidden ~= nil then
        M.settings_ref.panels_hidden[1] = false;
    end
end

function M.handle_text(e, pricing)
    local message = string.lower(string.strip_colors(e.message or ''));

    -- Skill-ups (independent of awaiting). Handled generically so every HELM
    -- skill is treated the same, and tolerant of the comma the game puts
    -- between the amount and "raising" ("... by 0.1, raising it to 23.6.").
    for _, sk in ipairs(SKILL_LINES) do
        local gain, level = match_skill_up(message, sk.words);
        if gain ~= nil and M.settings_ref ~= nil then
            local sess_ref = M.sessions[sk.act];
            if sess_ref ~= nil then
                sess_ref.skill_gain = (sess_ref.skill_gain or 0) + gain;
                on_skill_up_for(sess_ref);
            end
            M.zone_record_skill(sk.act, gain);
            if level ~= nil and level > 0 then
                set_skill_value(M.settings_ref, sk.act, level);
            end
            M.session_dirty = true;
            M.touch_activity(sk.act);
        end
    end

    -- Rare mining events — match SYSTEM text only (not player chat)
    -- Gold Rush! The vein glitters with precious ore!
    -- You hit the motherload! The vein bursts with extraordinary riches!
    do
        local gr = string.match(message, 'vein glitters with precious ore');
        local ml = string.match(message, 'vein bursts with extraordinary riches')
            or string.match(message, 'you hit the motherl[oa]de');
        if gr or ml then
            local target_act = 'mining';
            -- if currently excavating, count on excavate
            if M.awaiting == 'excavate' or M.active_tab == 'excavate' then
                target_act = 'excavate';
            elseif M.awaiting == 'mining' or M.active_tab == 'mining' then
                target_act = 'mining';
            end
            local hs = sess(target_act);
            if gr then
                hs.gold_rush = (hs.gold_rush or 0) + 1;
            end
            if ml then
                hs.motherlode = (hs.motherlode or 0) + 1;
            end
            M.update_session_timer(target_act);
            M.touch_activity(target_act);
            M.session_dirty = true;
            M.active_tab = target_act;
            if M.settings_ref ~= nil then
                if M.settings_ref.tracker.visible[1] == false then
                    M.settings_ref.tracker.visible[1] = true;
                end
                if M.settings_ref.panels_hidden ~= nil then
                    M.settings_ref.panels_hidden[1] = false;
                end
            end
        end
    end

    ----------------------------------------------------------------------
    -- Fishing
    --
    -- The cast is counted from the outgoing packet. Everything after it is
    -- chat: what bit, and how it ended. Bait is spent per BITE on this server,
    -- not per cast, so a cast that never gets a bite is free and bites is the
    -- number that bills the bait.
    ----------------------------------------------------------------------
    do
        local fs = M.sessions.fishing;

        local hook = fish_hook_kind(message);
        if hook ~= nil then
            fs.bites = (fs.bites or 0) + 1;
            if hook == 'large' then
                fs.hook_large = (fs.hook_large or 0) + 1;
            elseif hook == 'small' then
                fs.hook_small = (fs.hook_small or 0) + 1;
            elseif hook == 'item' then
                fs.hook_item = (fs.hook_item or 0) + 1;
            elseif hook == 'monster' then
                fs.monsters = (fs.monsters or 0) + 1;
            end
            M.active_tab = 'fishing';
            M.update_session_timer('fishing');
            M.touch_activity('fishing');
            M.session_dirty = true;
            debug_note('fish', 'hooked ' .. hook);
        end

        -- A cast that resolved with nothing on the line at all.
        if string.find(message, "you didn't catch anything", 1, true) ~= nil then
            fs.no_catch = (fs.no_catch or 0) + 1;
            push_history(fs, 'M');
            set_outcome(fs, 'M');
            M.touch_activity('fishing');
            M.session_dirty = true;
        end

        local fail = fish_fail_kind(message);
        if fail ~= nil then
            if fail == 'rod' then
                fs.breaks = (fs.breaks or 0) + 1;
                push_history(fs, 'B');
                set_outcome(fs, 'B');
            elseif fail == 'line' then
                fs.line_breaks = (fs.line_breaks or 0) + 1;
                push_history(fs, 'B');
                set_outcome(fs, 'B');
            elseif fail == 'cancel' then
                fs.cancels = (fs.cancels or 0) + 1;
            else
                fs.lost = (fs.lost or 0) + 1;
                if fail == 'lost_skill' then
                    fs.lost_skill = (fs.lost_skill or 0) + 1;
                end
                push_history(fs, 'M');
                set_outcome(fs, 'M');
            end
            M.active_tab = 'fishing';
            M.touch_activity('fishing');
            M.session_dirty = true;
            debug_note('fish', 'lost: ' .. fail);
        end

        local caught, qty = fish_catch_name(message, player_name());
        if caught ~= nil then
            if caught == 'monster' then
                -- Already counted at hook time; do not bank it as a catch.
                debug_note('fish', 'landed a monster');
            else
                qty = tonumber(qty) or 1;
                fs.items = (fs.items or 0) + qty;
                local name = clean_item_name(caught) or caught;
                fs.rewards[name] = (fs.rewards[name] or 0) + qty;
                local unit = 0;
                if pricing ~= nil then
                    unit = tonumber(pricing[normalize_key(name)]) or 0;
                end
                M.add_lifetime_gil(unit * qty);
                if (unit * qty) >= BIG_DROP_GIL then
                    fs.big_flash_ms = now_ms();
                end
                push_history(fs, 'W');
                set_outcome(fs, 'W');
                M.zone_record_swing('fishing', unit * qty, true, false, false);
                journal.write({
                    t = os.time(), act = 'fishing', outcome = 'W',
                    item = name, qty = qty, gil = unit * qty,
                    zone = M.zone_name, zone_id = M.zone_id,
                    skill = M.skill_value(M.settings_ref or {}, 'fishing'),
                    swing = fs.swings,
                });
                debug_note('fish', 'caught ' .. name .. ' x' .. qty);
            end
            M.active_tab = 'fishing';
            M.update_session_timer('fishing');
            M.touch_activity('fishing');
            M.session_dirty = true;
            M.persist_session();
        end
    end

    ----------------------------------------------------------------------
    -- Clamming
    --
    -- Order matters here. The over-weight message CONTAINS the find, so the
    -- break has to be handled first or the item gets banked into a bucket
    -- that has already burst.
    ----------------------------------------------------------------------
    do
        local cs = M.sessions.clamming;

        local function clam_touch()
            M.active_tab = 'clamming';
            M.update_session_timer('clamming');
            M.touch_activity('clamming');
            M.session_dirty = true;
            if M.settings_ref ~= nil and M.settings_ref.tracker.visible[1] == false then
                M.settings_ref.tracker.visible[1] = true;
            end
        end

        --- Everything in the bucket is gone. Which of the two ways it went
        --- matters: over-weight is your own call, the mandragora is not.
        local function clam_lose(kind)
            local lost = M.get_bucket_value(pricing);
            cs.bucket = T{};
            cs.bucket_weight = 0;
            cs.bucket_broken = true;
            cs.breaks = (cs.breaks or 0) + 1;
            if kind == 'incident' then
                cs.incidents = (cs.incidents or 0) + 1;
            else
                cs.overweight = (cs.overweight or 0) + 1;
            end
            debug_note('clam', string.format('bucket lost (%s), %d gil in it', kind, lost));
            clam_touch();
        end

        if string.find(message, CLAM_OVERWEIGHT, 1, true) ~= nil then
            cs.swings = (cs.swings or 0) + 1;
            clam_lose('overweight');
        elseif string.find(message, CLAM_INCIDENT, 1, true) ~= nil then
            clam_lose('incident');
        else
            local raw = string.match(message, CLAM_FIND);
            local found = clam_item_name(raw);
            if found ~= nil then
                local name = clean_item_name(found) or found;
                local w, known = clam_weight_of(name);
                cs.swings = (cs.swings or 0) + 1;
                cs.items = (cs.items or 0) + 1;
                if cs.bucket == nil then cs.bucket = T{}; end
                cs.bucket[name] = (cs.bucket[name] or 0) + 1;
                cs.bucket_weight = (cs.bucket_weight or 0) + w;
                if not known then
                    cs.assumed_weight = true;
                    debug_note('clam', 'unknown weight for ' .. name .. ', assumed '
                        .. tostring(w) .. 'pz');
                end
                if (cs.bucket_capacity or 0) <= 0 then
                    cs.bucket_capacity = constants.CLAM_START_CAPACITY or 50;
                end
                cs.last_find_s = now_s();
                push_history(cs, 'W');
                set_outcome(cs, 'W');
                clam_touch();
            end
        end

        -- A click that landed before the point was ready. Not a dig, so it
        -- does not touch the dig count - but it is worth showing, because a
        -- pile of these means you are clicking through the cooldown.
        for _, pat in ipairs(CLAM_REJECT) do
            if string.find(message, pat, 1, true) ~= nil then
                cs.rejected = (cs.rejected or 0) + 1;
                clam_touch();
                break;
            end
        end

        -- A fresh kit. Capacity always starts at 50 again - the upgrade is
        -- per kit, never a character stat.
        if string.find(message, CLAM_KIT, 1, true) ~= nil then
            cs.bucket = T{};
            cs.bucket_weight = 0;
            cs.bucket_capacity = constants.CLAM_START_CAPACITY or 50;
            cs.bucket_broken = false;
            cs.kits = (cs.kits or 0) + 1;
            debug_note('clam', 'new kit, 50pz');
            clam_touch();
        end

        local cap = string.match(message, CLAM_CAPACITY);
        if cap ~= nil then
            cs.bucket_capacity = tonumber(cap) or cs.bucket_capacity;
            debug_note('clam', 'capacity now ' .. tostring(cs.bucket_capacity) .. 'pz');
            clam_touch();
        end

        -- Cash out: the bucket finally becomes real gil, so its contents move
        -- into the session reward list and the bucket empties.
        local turned_in = false;
        for _, pat in ipairs(CLAM_TURNIN) do
            if string.find(message, pat, 1, true) ~= nil then
                turned_in = true;
            end
        end
        if turned_in and cs.bucket ~= nil then
            local banked = 0;
            for k, v in pairs(cs.bucket) do
                cs.rewards[k] = (cs.rewards[k] or 0) + v;
                banked = banked + v;
                if pricing ~= nil then
                    local unit = tonumber(pricing[normalize_key(k)]) or 0;
                    M.add_lifetime_gil(unit * v);
                end
            end
            if banked > 0 then
                cs.turnins = (cs.turnins or 0) + 1;
                debug_note('clam', string.format('turned in %d items', banked));
            end
            cs.bucket = T{};
            cs.bucket_weight = 0;
            cs.bucket_broken = false;
            clam_touch();
        end

        if string.find(message, CLAM_BROKEN, 1, true) ~= nil then
            cs.bucket_broken = true;
            clam_touch();
        end
        if string.find(message, CLAM_FULL_BAG, 1, true) ~= nil then
            cs.bag_full = true;
            debug_note('clam', 'Toh Zonikki says your bag is full');
            clam_touch();
        end
    end

    ----------------------------------------------------------------------
    -- Chocobo digging
    --
    -- A green is spent on every ACCEPTED attempt, including the ones that turn
    -- up nothing. Only a refusal ("wait longer") is free, so that one is taken
    -- back off the dig count rather than billed.
    ----------------------------------------------------------------------
    do
        local ds = M.sessions.digging;

        -- Refusal: too soon, not moved 2 yalms, or the daily cap is spent.
        if string.find(message, 'you must wait longer to perform that action', 1, true) ~= nil
            and (now_ms() - (M.dig_pending_ms or 0)) < 4000 then
            ds.rejected = (ds.rejected or 0) + 1;
            ds.swings = math.max(0, (ds.swings or 0) - 1);   -- no green spent
            M.dig_pending_ms = 0;
            M.session_dirty = true;
            debug_note('dig', 'refused (no green spent)');
        end

        -- Horizon says so out loud when the zone pool is dry; retail just
        -- keeps returning nothing, which is indistinguishable from bad luck.
        if string.find(message, 'the zone has nothing left to dig up', 1, true) ~= nil then
            ds.zone_empty = true;
            M.session_dirty = true;
            debug_note('dig', 'zone pool empty');
        end

        if string.find(message, 'you dig and you dig', 1, true) ~= nil then
            push_history(ds, 'M');
            set_outcome(ds, 'M');
            M.active_tab = 'digging';
            M.update_session_timer('digging');
            M.touch_activity('digging');
            M.session_dirty = true;
        end

        local dug = dig_item_name(message);
        if dug ~= nil and (now_ms() - (M.dig_pending_ms or 0)) < 8000 then
            local name = clean_item_name(dug) or dug;
            ds.items = (ds.items or 0) + 1;
            roll_dig_day(ds);
            ds.daily_items = (ds.daily_items or 0) + 1;
            ds.rewards[name] = (ds.rewards[name] or 0) + 1;
            ds.zone_empty = false;   -- something came up, so the pool is not dry
            local unit = 0;
            if pricing ~= nil then
                unit = tonumber(pricing[normalize_key(name)]) or 0;
            end
            M.add_lifetime_gil(unit);
            if unit >= BIG_DROP_GIL then
                ds.big_flash_ms = now_ms();
            end
            push_history(ds, 'W');
            set_outcome(ds, 'W');
            M.active_tab = 'digging';
            M.update_session_timer('digging');
            M.touch_activity('digging');
            M.zone_record_swing('digging', unit, true, false, false);
            journal.write({
                t = os.time(), act = 'digging', outcome = 'W',
                item = name, qty = 1, gil = unit,
                zone = M.zone_name, zone_id = M.zone_id,
                skill = M.skill_value(M.settings_ref or {}, 'digging'),
                swing = ds.swings,
            });
            M.session_dirty = true;
            M.persist_session();
            debug_note('dig', 'obtained ' .. name);
        end
    end

    -- Hunting (active only while the Hunt tab is selected)
    if M.active_tab == 'hunting' then
        local me = player_name();
        if me ~= '' then
            local hs = M.sessions.hunting;
            local hstealt = string.match(message, me .. ' uses steal%.');
            local hsteals = string.match(message, me .. ' steals an? ([^,!]+) from ');
            local hmug = string.match(message, me .. ' mugs ([0-9,]+) gil from ');
            local hstealtsmp = string.match(message, '%[' .. me .. '%] steal ');
            local hstealssmp = string.match(message, '%[' .. me .. '%] steal .* %(([^,!]+)%)');
            local hmugsmp = string.match(message, '%[' .. me .. '%] ([0-9,]+) gil mug');
            local hitem = string.match(message, me .. ' obtains an? ([^,!]+)%.');
            local hkill = string.match(message, me .. ' defeats the ');
            local hgil = string.match(message, me .. ' obtains ([0-9,]+) gil%.');

            -- Experience / Limit points (own character only)
            -- "Makee gains 200 experience points." / "You gain 200 experience points."
            local hexp = string.match(message, me .. ' gains ([0-9,]+) experience points');
            if not hexp then
                hexp = string.match(message, '^you gain ([0-9,]+) experience points');
            end
            local hlp = string.match(message, me .. ' gains ([0-9,]+) limit points');
            if not hlp then
                hlp = string.match(message, '^you gain ([0-9,]+) limit points');
            end

            local touched = false;
            if hexp then
                local n = tonumber((tostring(hexp):gsub(',', ''))) or 0;
                hs.exp = (hs.exp or 0) + n;
                touched = true;
            end
            if hlp then
                local n = tonumber((tostring(hlp):gsub(',', ''))) or 0;
                hs.limit = (hs.limit or 0) + n;
                touched = true;
            end
            if hkill then
                hs.swings = hs.swings + 1; -- kills
                touched = true;
            elseif hstealt or hstealtsmp then
                hs.steal_attempts = (hs.steal_attempts or 0) + 1;
                touched = true;
            end

            local function add_item(item_name)
                if item_name == nil or item_name == '' then return; end
                item_name = item_name:match('^%s*(.-)%s*$') or item_name;
                hs.items = hs.items + 1;
                if hs.rewards[item_name] == nil then
                    hs.rewards[item_name] = 1;
                else
                    hs.rewards[item_name] = hs.rewards[item_name] + 1;
                end
                if pricing ~= nil then
                    local unit = tonumber(pricing[normalize_key(item_name)]) or 0;
                    M.add_lifetime_gil(unit);
                end
            end

            if hitem then
                add_item(hitem);
                touched = true;
            elseif hsteals then
                hs.steals = (hs.steals or 0) + 1;
                add_item(hsteals);
                touched = true;
            elseif hstealssmp then
                hs.steals = (hs.steals or 0) + 1;
                add_item(hstealssmp);
                touched = true;
            elseif hgil then
                local g = tonumber((tostring(hgil):gsub(',', ''))) or 0;
                hs.raw_gil = (hs.raw_gil or 0) + g;
                M.add_lifetime_gil(g);
                touched = true;
            elseif hmugsmp then
                local g = tonumber((tostring(hmugsmp):gsub(',', ''))) or 0;
                hs.raw_gil = (hs.raw_gil or 0) + g;
                M.add_lifetime_gil(g);
                touched = true;
            elseif hmug then
                local g = tonumber((tostring(hmug):gsub(',', ''))) or 0;
                hs.raw_gil = (hs.raw_gil or 0) + g;
                M.add_lifetime_gil(g);
                touched = true;
            end

            if touched then
                M.update_session_timer('hunting');
                M.touch_activity('hunting');
                M.session_dirty = true;
                if M.settings_ref ~= nil then
                    if M.settings_ref.tracker.visible[1] == false then
                        M.settings_ref.tracker.visible[1] = true;
                    end
                    if M.settings_ref.panels_hidden ~= nil then
                        M.settings_ref.panels_hidden[1] = false;
                    end
                end
            end
        end
        return; -- hunt tab owns text handling while selected
    end

    -- Tag last_outcome from HELM lines (even if await packet was missed)
    -- Priority when multiple match in one line: Win > Miss > Break
    do
        local has_success = string.match(message, 'dig up an? ')
            or string.match(message, 'cut off an? ')
            or string.match(message, 'harvest an? ');
        local has_broke = string.match(message, 'pickaxe breaks')
            or string.match(message, 'hatchet breaks')
            or string.match(message, 'sickle breaks');
        local has_unable = string.match(message, 'unable to mine anything')
            or string.match(message, 'unable to excavate anything')
            or string.match(message, 'unable to log anything')
            or string.match(message, 'unable to harvest anything');
        if has_success or has_broke or has_unable then
            local tag_act = M.awaiting or M.active_tab or 'mining';
            if tag_act == 'hunting' then tag_act = 'mining'; end
            local s = sess(tag_act);
            if has_success then
                set_outcome(s, 'W');
            elseif has_unable then
                set_outcome(s, 'M');
            elseif has_broke then
                set_outcome(s, 'B');
            end
        end
    end

    local act = M.awaiting;
    if act ~= nil and (now_ms() - (M.awaiting_ms or 0)) > AWAIT_TIMEOUT_MS then
        -- The swing we were waiting on never resolved; do not let it capture
        -- an unrelated line later.
        debug_note('timeout', act .. ' swing saw no result line in 20s');
        M.awaiting = nil;
        act = nil;
    end
    if act == nil then
        return;
    end

    local success, broke, unable = nil, nil, nil;
    local rule = ACT_RULES[act];
    if rule ~= nil then
        -- "You dig up a chunk of tin ore" / "...ore, but your pickaxe breaks in the process."
        success = clean_item_name(string.match(message, rule.success));
        broke = string.match(message, rule.broke);
        for _, pat in ipairs(rule.unable) do
            unable = unable or string.match(message, pat);
        end
    end

    if not (success or broke or unable) then
        return;
    end

    M.awaiting = nil;
    debug_note('result', act .. ' -> '
        .. ((success and success ~= '') and ('got ' .. success)
            or (unable and 'nothing' or 'broke')));
    local s = sess(act);
    M.update_session_timer(act);
    M.touch_activity(act);
    s.swings = s.swings + 1;
    if broke then
        s.breaks = (s.breaks or 0) + 1;
    end
    local swing_gil = 0;
    local reset_seen = false;
    if success and success ~= '' then
        -- Check before the increment: the cap is about the items already banked.
        reset_seen = note_reset_if_capped(act, fatigue_cap(M.settings_ref or {}, act));
        s.items = (s.items or 0) + 1;
        learn_fatigue_cap(M.settings_ref, act, s.items);
        if s.rewards[success] == nil then
            s.rewards[success] = 1;
        else
            s.rewards[success] = s.rewards[success] + 1;
        end
        if pricing ~= nil then
            swing_gil = tonumber(pricing[normalize_key(success)]) or 0;
            M.add_lifetime_gil(swing_gil);
            if swing_gil >= BIG_DROP_GIL then
                s.big_flash_ms = now_ms();
            end
        end
    end

    if reset_seen then
        print(chat.header(addon.name):append(chat.message(string.format(
            'Fatigue reset detected. Schedule confidence: %s.', M.fatigue_confidence()
        ))));
    end

    -- Zone aggregate: gil earned here, minus the tool if it broke on this swing.
    if act == 'mining' or act == 'excavate' or act == 'logging' or act == 'harvest' then
        local net_swing = swing_gil;
        if broke and M.settings_ref ~= nil and tool_subtract(M.settings_ref, act) then
            net_swing = net_swing - tool_cost(M.settings_ref, act);
        end
        M.zone_record_swing(act, net_swing,
            (success ~= nil and success ~= ''), broke ~= nil, unable ~= nil);
    end

    -- History entry first so a flushed pending skill-up marks this swing,
    -- then denominator, then the outcome tag.
    if success and success ~= '' then
        push_history(s, 'W');
        add_lifetime_outcome('W');
        set_outcome(s, 'W');
    elseif unable then
        push_history(s, 'M');
        add_lifetime_outcome('M');
        set_outcome(s, 'M');
    elseif broke then
        push_history(s, 'B');
        add_lifetime_outcome('B');
        set_outcome(s, 'B');
    end

    -- One line per swing. Everything the panel cannot answer later - moon
    -- effects, weekday effects, real drop rates with a confidence interval -
    -- comes out of this file.
    do
        local outcome = (success and success ~= '') and 'W' or (unable and 'M' or 'B');
        local ts = vana.get_timestamp();
        local moon = vana.get_moon(ts);
        local weekday = vana.get_weekday(ts);
        journal.write({
            t = os.time(),
            act = act,
            outcome = outcome,
            item = (success ~= '' and success) or nil,
            gil = swing_gil,
            zone = M.zone_name,
            zone_id = M.zone_id,
            skill = M.skill_value(M.settings_ref or {}, act),
            swing = s.swings,
            fatigue = s.items or 0,
            cap = fatigue_cap(M.settings_ref or {}, act),
            moon = moon and moon.name or nil,
            moon_pct = moon and moon.percent or nil,
            day = weekday and weekday.name or nil,
            vana_hour = ts and ts.hour or nil,
            -- Only once we have actually seen a packet. Writing 'Clear'
            -- because we have not heard yet would poison the journal.
            weather = (function ()
                local w = weather.current();
                return w.known and w.name or nil;
            end)(),
        });
    end

    M.session_dirty = true;
    M.persist_session();
end

function M.build_report(settings, pricing)
    local act = M.active_tab;
    local s = sess(act);
    local lines = T{};
    lines:append('~~~~~~ Floos ' .. (TAB_LABELS[act] or act) .. ' ~~~~~~');
    lines:append('Session: ' .. format.format_duration(M.get_session_seconds(act))
        .. (M.is_session_paused_idle(act) and ' (paused)' or ''));
    lines:append(SWING_LABEL[act] .. ': ' .. format.format_int(s.swings));
    lines:append('Items: ' .. format.format_int(s.items));
    lines:append('Breaks: ' .. format.format_int(s.breaks));
    lines:append('Accuracy: ' .. format.format_percent(M.get_accuracy(act)));
    local sk = skill_value(settings, act);
    if sk ~= nil then
        local secs = M.get_session_seconds(act);
        local shr = 0;
        if s.skill_gain and s.skill_gain > 0 and secs > 0 then
            shr = (s.skill_gain / secs) * 3600;
        end
        lines:append('Skill: ' .. string.format('%.1f', sk) .. ' (' .. s.skill_gain .. '+, ' .. string.format('+%.1f/hr', shr) .. ')');
    end
    lines:append('~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    local names = T{};
    for n, _ in pairs(s.rewards) do names:append(n); end
    table.sort(names);
    for _, name in ipairs(names) do
        local count = s.rewards[name];
        local price = tonumber(pricing[normalize_key(name)]) or 0;
        lines:append(title_case(name) .. ': x' .. format.format_int(count)
            .. ' (' .. format.format_int(price * count) .. 'g)');
    end
    lines:append('~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    local net = M.get_net_gil(act, settings, pricing);
    local gph = M.get_gph(act, settings, pricing);
    lines:append('Net Gil: ' .. format.format_int(net) .. 'g (' .. format.format_int(gph) .. ' gph)');
    return table.concat(lines, '\n');
end

local function num_or(v, fallback)
    if type(v) == 'table' then
        return tonumber(v.x or v[1]) or fallback;
    end
    return tonumber(v) or fallback;
end

local function region_avail_w()
    local a = imgui.GetContentRegionAvail();
    return num_or(a, 0);
end

local function text_w(s)
    local w = ui.measure_text(tostring(s or ''));
    if type(w) ~= 'number' then return 0; end
    return w;
end

local function draw_separator(transparent)
    local gap = math.max(1, math.floor(imgui.GetTextLineHeight() * 0.18 + 0.5));
    imgui.Dummy({ 0, gap });
    if not transparent then
        local dl = imgui.GetWindowDrawList();
        if dl ~= nil then
            local x1, y1 = imgui.GetCursorScreenPos();
            x1 = num_or(x1, 0);
            y1 = num_or(({ imgui.GetCursorScreenPos() })[2], y1);
            -- Use separator widget for reliability
        end
        imgui.PushStyleColor(ImGuiCol_Separator, theme.colors.border_gold or theme.colors.border);
        imgui.Separator();
        imgui.PopStyleColor(1);
    end
    imgui.Dummy({ 0, gap });
end

-- Label on the left (muted), value on the right (gold)
-- content_left = window X where content starts (padding)
local function truncate_to_width(str, max_w)
    str = tostring(str or '');
    if max_w <= 0 then return ''; end
    if text_w(str) <= max_w then return str; end
    local ell = '...';
    local ew = text_w(ell);
    if max_w <= ew then return ell; end
    -- binary-ish shrink
    local out = str;
    while #out > 0 and text_w(out) + ew > max_w do
        out = out:sub(1, #out - 1);
    end
    return out .. ell;
end

--- First candidate that fits, or nil. Callers list what they want to say from
--- richest to plainest, and the panel says as much as the window allows rather
--- than printing a sentence that runs off the edge.
local function first_that_fits(max_w, candidates)
    -- Deliberately not ipairs: callers leave nil holes for clauses that do not
    -- apply, and ipairs would stop dead at the first one and skip every
    -- simpler fallback behind it.
    local n = (table.maxn ~= nil) and table.maxn(candidates) or #candidates;
    for i = 1, n do
        local s = candidates[i];
        if s ~= nil and s ~= '' and text_w(s) <= max_w then
            return s;
        end
    end
    return nil;
end

--- Fit "<name><sep><tail>" by shrinking only the name. The tail holds the
--- numbers, and half a number ("avg 81,9...") is worse than no number, so it is
--- never cut - the name gives way first.
local function fit_name_tail(name, tail, max_w, sep)
    sep = sep or '   ';
    name = tostring(name or '');
    tail = tostring(tail or '');
    if tail == '' then
        return truncate_to_width(name, max_w);
    end
    local room = max_w - text_w(sep .. tail);
    if room < text_w('...') + 8 then
        -- Not enough room for both. The numbers are the answer; keep those.
        return truncate_to_width(tail, max_w);
    end
    return truncate_to_width(name, room) .. sep .. tail;
end

--- The fatigue readout, trimmed to the width available. The count and the reset
--- clock are the two things worth keeping; the percentage and the fill-up ETA
--- are the first to go when the panel is narrow.
local function fatigue_value(fill, items, cap, eta_str, reset_left, max_w)
    local pct = string.format('%.0f%%', (fill or 0) * 100);
    local count = format.format_int(items) .. ' / ' .. format.format_int(cap);
    local reset = (reset_left ~= nil)
        and ('reset ' .. format.format_duration(reset_left)) or nil;

    local function join(...)
        local out = T{};
        for _, v in ipairs({ ... }) do
            if v ~= nil and v ~= '' then
                out:append(v);
            end
        end
        return table.concat(out, '   ');
    end

    return first_that_fits(max_w, {
        join(pct, count, eta_str, reset),
        join(pct, count, reset),
        join(count, reset),
        join(count, eta_str),
        count,
    }) or count;
end

--- The "Best" row, sized to the width available. Returns label, value - or
--- nil when there is nothing worth saying yet.
function M.best_for_row(gil_rec, gil_rate, skl_rec, skl_rate, used_band, max_w)
    local has_gil = (gil_rec ~= nil and (gil_rate or 0) > 0);
    local has_skl = (skl_rec ~= nil and (skl_rate or 0) > 0);
    if not has_gil and not has_skl then
        return nil, nil;
    end
    max_w = math.max(tonumber(max_w) or 0, 24);

    local gil_name = has_gil and (gil_rec.name or '?') or nil;
    local skl_name = has_skl and (skl_rec.name or '?') or nil;
    local gil_str = has_gil
        and (format.format_int(math.floor(gil_rate + 0.5)) .. '/hr') or nil;
    -- "skill Oldton 0.6 skill/hr" says it twice, so the unit only carries the
    -- word when the "skill" prefix is not already in front of it.
    local skl_str = has_skl and string.format('%.1f/hr', skl_rate) or nil;
    local skl_solo = has_skl and string.format('%.1f skill/hr', skl_rate) or nil;
    local tag = (has_skl and used_band ~= nil and used_band > 0)
        and string.format('  (%d+)', used_band) or '';

    -- One zone winning both was being printed as its own name twice.
    if has_gil and has_skl and gil_rec.id == skl_rec.id then
        return 'Best', first_that_fits(max_w, {
            gil_name .. '   ' .. gil_str .. ' - ' .. skl_solo .. tag,
            gil_name .. '   ' .. gil_str .. ' - ' .. skl_solo,
            gil_name .. '   ' .. gil_str,
        }) or fit_name_tail(gil_name, gil_str, max_w);
    end

    local both_full = (has_gil and has_skl)
        and ('gil ' .. gil_name .. ' ' .. gil_str
             .. '    skill ' .. skl_name .. ' ' .. skl_str .. tag) or nil;
    local both_plain = (has_gil and has_skl)
        and ('gil ' .. gil_name .. ' ' .. gil_str
             .. '    skill ' .. skl_name .. ' ' .. skl_str) or nil;
    local both_names = (has_gil and has_skl)
        and ('gil ' .. gil_name .. '    skill ' .. skl_name) or nil;
    local one = has_gil and (gil_name .. '   ' .. gil_str)
        or (skl_name .. '   ' .. skl_solo);

    return 'Best', first_that_fits(max_w, { both_full, both_plain, both_names, one })
        or fit_name_tail(has_gil and gil_name or skl_name,
            has_gil and gil_str or skl_solo, max_w);
end

--- The whole ore verdict on ONE line, sized to the width available.
---
--- It used to spend up to five rows on this: a verdict plus a breakdown line
--- per failing gate. On a real panel that is most of the tab given over to a
--- 0.45% drop, so the breakdown is gone. When exactly one gate is shut it is
--- named with its reading inline - the only case where the detail was ever
--- worth reading - and otherwise the shut gates are simply listed.
---
--- Returns value, tier where tier is 'good' / 'warn' / 'muted', or nil when
--- there is nothing worth a row at all.
function M.ore_row(ore, max_w)
    if ore == nil then
        return nil, nil;
    end
    -- Standing somewhere you cannot dig at all: the row would only ever say
    -- "no", which the tab already implies. Say nothing.
    if ore.not_dig_zone then
        return nil, nil;
    end
    max_w = math.max(tonumber(max_w) or 0, 24);

    if ore.verdict == 'yes' then
        local elem = ore.element;
        return first_that_fits(max_w, {
            elem and ('ORE POSSIBLE  -  ' .. elem .. ' Ore') or nil,
            elem and ('ORE  -  ' .. elem) or nil,
            'ORE POSSIBLE',
            'ORE',
        }) or 'ORE', 'good';
    end

    local maybe = (ore.verdict == 'maybe');
    local tier = maybe and 'warn' or 'muted';
    local word = maybe and 'maybe' or 'no';
    local list = (maybe and ore.unknowns or ore.blockers) or {};

    if #list == 0 then
        return word, tier;
    end

    -- One gate shut: name it and say what it currently reads, because that is
    -- the thing you would otherwise go and look up.
    if #list == 1 then
        local label = list[1];
        local cond;
        for _, c in ipairs(ore.conds or {}) do
            if c.label == label then cond = c; end
        end
        local detail = cond and cond.detail or nil;
        local opens = (cond ~= nil and cond.key == 'moon'
            and ore.moon_days ~= nil and ore.moon_days > 0) and ore.moon_days or nil;

        return first_that_fits(max_w, {
            (opens and detail) and string.format('%s - %s: %s, opens %dd',
                word, label, detail, opens) or nil,
            detail and (word .. ' - ' .. label .. ': ' .. detail) or nil,
            opens and string.format('%s - %s, opens %dd', word, label, opens) or nil,
            word .. ' - ' .. label,
            word,
        }) or word, tier;
    end

    -- Several shut: the individual readings stop being useful, so just list
    -- which gates they are.
    return first_that_fits(max_w, {
        word .. ' - ' .. table.concat(list, ', '),
        string.format('%s - %s +%d', word, list[1], #list - 1),
        word .. ' - ' .. list[1],
        word,
    }) or word, tier;
end

local function draw_row(label, value, value_color, content_left, content_w)
    local label_c = theme.colors.text_dim or theme.colors.text_light;
    local value_c = value_color or theme.colors.text_gold;
    local row_y = num_or(imgui.GetCursorPosY(), 0);
    content_left = content_left or 0;
    content_w = math.max(content_w or region_avail_w(), 80);
    value = tostring(value or '');

    -- A value wider than the row used to run off the panel edge. Give the label
    -- a small fixed share and cut the value to what is left.
    local lab_w = text_w(tostring(label or ''));
    if lab_w + text_w(value) + 8 > content_w then
        value = truncate_to_width(value, math.max(24, content_w - math.min(lab_w, content_w * 0.4) - 8));
    end

    local vw = text_w(value);
    local max_lab = content_w - vw - 8;
    if max_lab < 20 then max_lab = 20; end
    label = truncate_to_width(tostring(label or ''), max_lab);

    imgui.SetCursorPosX(content_left);
    imgui.SetCursorPosY(row_y);
    ui.text_outlined_colored(label, label_c);

    local target = content_left + content_w - vw;
    if target < content_left then target = content_left; end
    imgui.SameLine(0, 0);
    imgui.SetCursorPosY(row_y);
    imgui.SetCursorPosX(target);
    ui.text_outlined_colored(value, value_c);
end

-- Fixed-width right columns so every row lines up while resizing:
-- [ name .................. ][  xN ][   Ng ]
-- Count and gil are right-aligned inside fixed column slots.
----------------------------------------------------------------------
-- Presentation helpers
----------------------------------------------------------------------

local function screen_xy()
    local x, y = imgui.GetCursorScreenPos();
    if type(x) == 'table' then
        y = tonumber(x.y or x[2]) or 0;
        x = tonumber(x.x or x[1]) or 0;
    end
    return tonumber(x) or 0, tonumber(y) or 0;
end

local function line_h()
    local h = imgui.GetTextLineHeight();
    if type(h) ~= 'number' or h <= 0 then
        return 14;
    end
    return h;
end

local function draw_list()
    local dl = nil;
    pcall(function()
        dl = imgui.GetWindowDrawList();
    end);
    return dl;
end

--- Height of one stacked text row, spacing included. Only a first guess: the
--- haul measures its own rows once it has drawn one and uses that instead.
local function text_row_pitch()
    local h = nil;
    pcall(function()
        h = imgui.GetTextLineHeightWithSpacing();
    end);
    if type(h) ~= 'number' or h <= 0 then
        h = line_h() + 4;
    end
    return h;
end

--- Style for the haul's scroll region: no window padding, so the rows sit
--- exactly where they did before the list became scrollable, and a thin
--- scrollbar in the tab's accent instead of ImGui's default grey slab.
--- Returns the number of vars and colors pushed, for pop_haul_style.
local function push_haul_style(accent)
    local vars, cols = 0, 0;

    local function var(id, value)
        if id == nil then return; end
        local ok = pcall(function() imgui.PushStyleVar(id, value); end);
        if ok then vars = vars + 1; end
    end
    local function col(id, value)
        if id == nil then return; end
        local ok = pcall(function() imgui.PushStyleColor(id, value); end);
        if ok then cols = cols + 1; end
    end

    var(ImGuiStyleVar_WindowPadding, { 0, 0 });
    var(ImGuiStyleVar_ChildBorderSize, 0);
    var(ImGuiStyleVar_ScrollbarSize, HAUL_SCROLLBAR_W);
    var(ImGuiStyleVar_ScrollbarRounding, HAUL_SCROLLBAR_W * 0.5);

    col(ImGuiCol_ChildBg, { 0, 0, 0, 0 });
    col(ImGuiCol_Border, { 0, 0, 0, 0 });
    col(ImGuiCol_ScrollbarBg, { 0, 0, 0, 0 });
    col(ImGuiCol_ScrollbarGrab, vis.alpha(accent, 0.30));
    col(ImGuiCol_ScrollbarGrabHovered, vis.alpha(accent, 0.55));
    col(ImGuiCol_ScrollbarGrabActive, vis.alpha(accent, 0.80));

    return vars, cols;
end

local function pop_haul_style(vars, cols)
    if (vars or 0) > 0 then
        pcall(function() imgui.PopStyleVar(vars); end);
    end
    if (cols or 0) > 0 then
        pcall(function() imgui.PopStyleColor(cols); end);
    end
end

--- Layout numbers for one tab's haul list, created on first sight.
local function haul_metrics(act)
    local m = M.haul[act];
    if m == nil then
        m = { chrome = 0, row = 0, rows = 0, used = 0 };
        M.haul[act] = m;
    end
    return m;
end

--- The shortest this panel may be drawn: every other section at its natural
--- height, plus the two haul rows that never go away. Falls back to the flat
--- minimum until a tab has been drawn once and measured.
function M.min_panel_height(act)
    local m = M.haul[act or M.active_tab];
    local h = MIN_PANEL_H;
    if m ~= nil and (m.chrome or 0) > 0 then
        local rows = math.min(m.rows or 0, HAUL_MIN_ROWS);
        h = m.chrome + (rows * (m.row or 0));
    end
    h = math.floor(h + 0.5);
    if h < MIN_PANEL_H then h = MIN_PANEL_H; end
    if h > MAX_PANEL_H then h = MAX_PANEL_H; end
    return h;
end

--- Read an optional settings.ui flag without exploding on old configs.
local function ui_flag(settings, key, fallback)
    local u = settings ~= nil and settings.ui or nil;
    if u == nil or u[key] == nil then
        return fallback;
    end
    local v = u[key][1];
    if v == nil then
        return fallback;
    end
    return v;
end

local function accent_of(act, settings)
    return theme.accent_for(act, ui_flag(settings, 'accent_by_activity', true));
end

--- 'Full' | 'Compact' | 'Mini'. Falls back to the old boolean compact flag.
local function detail_level(settings)
    local d = ui_flag(settings, 'detail', nil);
    if d == 'Full' or d == 'Compact' or d == 'Mini' then
        return d;
    end
    if ui_flag(settings, 'compact', false) then
        return 'Compact';
    end
    return 'Full';
end

M.detail_level = detail_level;

--- Content-width rule, tinted with the active accent.
--- Gil/hr over the trailing window only, from the same samples the sparkline
--- uses. The hero number is the whole-session average; this is what the last
--- few minutes actually paid, which is the number that says whether the vein
--- you are on right now is hot or cold.
function M.recent_rate(s, window_secs, now)
    local samples = (s and s.samples) or {};
    if #samples < 2 then
        return nil;
    end
    now = tonumber(now) or (samples[#samples].t or 0);
    window_secs = tonumber(window_secs) or 600;
    local cutoff = now - window_secs;

    -- Oldest sample still inside the window.
    local first = nil;
    for i = 1, #samples do
        if (samples[i].t or 0) >= cutoff then
            first = samples[i];
            break;
        end
    end
    local last = samples[#samples];
    if first == nil or first == last then
        return nil;
    end
    local dt = (last.t or 0) - (first.t or 0);
    -- Half a window of evidence minimum, or the number is mostly noise.
    if dt < (window_secs * 0.5) then
        return nil;
    end
    return (((last.worth or 0) - (first.worth or 0)) / dt) * 3600;
end

--- 'now vs average' as a signed percentage, nil when either side is missing.
function M.rate_trend(recent, average)
    recent = tonumber(recent);
    average = tonumber(average);
    if recent == nil or average == nil or average <= 0 then
        return nil;
    end
    return ((recent - average) / average) * 100;
end

local function expert_on(settings)
    return ui_flag(settings, 'expert', true);
end

local function draw_rule(content_left, content_w, accent, transparent)
    local gap = math.max(2, math.floor(line_h() * 0.22 + 0.5));
    imgui.Dummy({ 0, gap });
    if not transparent then
        imgui.SetCursorPosX(content_left);
        local sx, sy = screen_xy();
        vis.rect(draw_list(), sx, sy, content_w, 1, vis.alpha(accent, 0.28), 0);
        imgui.Dummy({ content_w, 1 });
    end
    imgui.Dummy({ 0, gap });
end

--- A rule with a small label sitting in it: ── HAUL · x137 · 118,469g ─────
--- Turns an anonymous divider into a section header that carries its own
--- summary, which is what gives the panel hierarchy instead of stripes.
local function draw_rule_labeled(label, content_left, content_w, accent, transparent)
    if label == nil or label == '' then
        draw_rule(content_left, content_w, accent, transparent);
        return;
    end
    local gap = math.max(2, math.floor(line_h() * 0.22 + 0.5));
    imgui.Dummy({ 0, gap });

    local muted = theme.colors.text_dim or theme.colors.text_light;
    local row_y = num_or(imgui.GetCursorPosY(), 0);
    local lw = text_w(label);
    local lead = 10;   -- short rule segment before the label

    if not transparent then
        imgui.SetCursorPosX(content_left);
        imgui.SetCursorPosY(row_y);
        local sx, sy = screen_xy();
        local mid = sy + math.floor(line_h() * 0.5 + 0.5);
        vis.rect(draw_list(), sx, mid, lead, 1, vis.alpha(accent, 0.28), 0);
        local after_x = sx + lead + 6 + lw + 6;
        local after_w = content_w - (lead + 6 + lw + 6);
        if after_w > 0 then
            vis.rect(draw_list(), after_x, mid, after_w, 1, vis.alpha(accent, 0.28), 0);
        end
    end

    imgui.SetCursorPosX(content_left + lead + 6);
    imgui.SetCursorPosY(row_y);
    ui.text_outlined_colored(label, vis.alpha(muted, 0.9));

    imgui.Dummy({ 0, gap });
end

--- Label row with a meter underneath.
--- opts: { value_color, from, to, tick, tick_color, height, right_label }
local function draw_meter(label, value, pct, content_left, content_w, opts)
    opts = opts or {};
    draw_row(label, value, opts.value_color, content_left, content_w);

    local h = opts.height or math.max(4, math.floor(line_h() * 0.30 + 0.5));
    imgui.SetCursorPosX(content_left);
    local sx, sy = screen_xy();
    vis.bar(draw_list(), sx, sy + 1, content_w, h, pct, opts.from, opts.to or opts.from, {
        tick = opts.tick,
        tick_color = opts.tick_color,
        ticks = opts.ticks,
        ticks_color = opts.ticks_color,
        track = opts.track,
    });
    imgui.Dummy({ content_w, h + 3 });
end

--- Left label + right-aligned chip (used by the zone verdict).
local function draw_row_chip(label, label_color, chip_text, chip_color, content_left, content_w)
    local row_y = num_or(imgui.GetCursorPosY(), 0);
    local pad_x = 6;
    local cw = text_w(chip_text) + (pad_x * 2);
    local ch = line_h() + 2;

    imgui.SetCursorPosX(content_left);
    imgui.SetCursorPosY(row_y);
    local label_max = content_w - cw - 8;
    if label_max < 20 then label_max = 20; end
    ui.text_outlined_colored(truncate_to_width(label, label_max), label_color);

    imgui.SameLine(0, 0);
    imgui.SetCursorPosY(row_y);
    imgui.SetCursorPosX(content_left + content_w - cw);
    local sx, sy = screen_xy();
    vis.chip(draw_list(), sx, sy - 1, cw, ch, chip_color, 0.18);

    imgui.SameLine(0, 0);
    imgui.SetCursorPosY(row_y);
    imgui.SetCursorPosX(content_left + content_w - cw + pad_x);
    ui.text_outlined_colored(chip_text, chip_color);
end

--- Outcome strip: header counts + the tick row.
local function draw_outcome_strip(s, content_left, content_w, accent)
    local hist = s.history or {};
    if #hist == 0 then
        return;
    end

    local good = theme.state_color('good');
    local warn = theme.state_color('neutral');
    local bad = theme.state_color('bad');
    local muted = theme.colors.text_dim or theme.colors.text_light;

    local w, m, b = 0, 0, 0;
    local ups = 0;
    for i = 1, #hist do
        local oc = hist[i].oc;
        if oc == 'W' then w = w + 1;
        elseif oc == 'M' then m = m + 1;
        elseif oc == 'B' then b = b + 1; end
        if hist[i].skill then ups = ups + 1; end
    end

    local row_y = num_or(imgui.GetCursorPosY(), 0);
    imgui.SetCursorPosX(content_left);
    imgui.SetCursorPosY(row_y);
    ui.text_outlined_colored(string.format('Last %d', #hist), muted);

    -- Right-aligned W / M / B tally, each in its own color.
    local parts = {
        { string.format('%d', b), bad },
        { string.format('%d', m), warn },
        { string.format('%d', w), good },
    };
    local x = content_left + content_w;
    for _, part in ipairs(parts) do
        local pw = text_w(part[1]);
        x = x - pw;
        imgui.SameLine(0, 0);
        imgui.SetCursorPosY(row_y);
        imgui.SetCursorPosX(x);
        ui.text_outlined_colored(part[1], part[2]);
        x = x - 10;
    end

    local h = math.max(5, math.floor(line_h() * 0.42 + 0.5));
    imgui.SetCursorPosX(content_left);
    local sx, sy = screen_xy();
    vis.strip(draw_list(), sx, sy + 3, content_w, h, hist, {
        W = good,
        M = vis.alpha(warn, 0.45),
        B = bad,
        skill = accent,
    }, 30);
    imgui.Dummy({ content_w, h + 6 });
end

--- Rolling gil/hr sparkline built from the session samples.
local function draw_rate_spark(s, content_left, content_w, accent)
    local samples = s.samples or {};
    if #samples < 3 then
        return false;
    end

    local series = {};
    for i = 2, #samples do
        local dt = (samples[i].t or 0) - (samples[i - 1].t or 0);
        local dg = (samples[i].worth or 0) - (samples[i - 1].worth or 0);
        if dt > 0 then
            series[#series + 1] = (dg / dt) * 3600;
        end
    end
    if #series < 2 then
        return false;
    end

    local h = math.max(10, math.floor(line_h() * 0.9 + 0.5));
    imgui.SetCursorPosX(content_left);
    local sx, sy = screen_xy();
    vis.spark(draw_list(), sx, sy + 1, content_w, h, series, accent, 0.16);
    imgui.Dummy({ content_w, h + 3 });
    return true;
end

-- Fixed-width right columns so every row lines up while resizing:
-- [ name .................. ][ xN ][ pct ][ gil ]
-- A share bar sits behind the row so the list doubles as a chart.
local function draw_reward_row(name, count, worth, content_left, content_w, is_best, total_items, accent, max_worth)
    local muted = theme.colors.text_dim or theme.colors.text_light;
    local light = theme.colors.text_light;
    local row_y = num_or(imgui.GetCursorPosY(), 0);
    content_left = content_left or 0;
    content_w = math.max(content_w or 0, 200);
    total_items = tonumber(total_items) or 0;
    count = tonumber(count) or 0;
    worth = tonumber(worth) or 0;
    max_worth = tonumber(max_worth) or 0;

    local pct = 0;
    if total_items > 0 then
        pct = (count / total_items) * 100;
    end

    -- Share of session value; falls back to share of count when nothing is priced.
    local share = 0;
    if max_worth > 0 then
        share = worth / max_worth;
    elseif total_items > 0 then
        share = count / total_items;
    end

    local count_str = string.format('x%d', count);
    local pct_str = string.format('%.1f%%', pct);
    local gil_str = format.format_int(worth) .. 'g';

    -- Row background bar (drawn first so text lands on top).
    imgui.SetCursorPosX(content_left);
    imgui.SetCursorPosY(row_y);
    local sx, sy = screen_xy();
    local bar_h = line_h();
    vis.rect(draw_list(), sx - 3, sy - 1, (content_w + 6) * vis.clamp01(share), bar_h + 2,
        vis.alpha(accent, is_best and 0.20 or 0.09), 2);

    local marker_w = 0;
    if is_best then
        marker_w = math.max(8, math.floor(bar_h * 0.55 + 0.5));
        vis.diamond(draw_list(), sx + (marker_w * 0.4), sy + (bar_h * 0.5), marker_w * 0.36, accent);
    end

    local gap = 8;
    local gil_col_w = math.max(text_w('000,000g'), text_w(gil_str));
    local pct_col_w = math.max(text_w('100.0%'), text_w(pct_str));
    local count_col_w = math.max(text_w('x999'), text_w(count_str));

    local right = content_left + content_w;
    local gil_right = right;
    local pct_right = gil_right - gil_col_w - gap;
    local count_right = pct_right - pct_col_w - gap;
    local name_left = content_left + marker_w;
    local name_max = (count_right - count_col_w - gap) - name_left;
    if name_max < 20 then name_max = 20; end
    local display_name = truncate_to_width(title_case(name), name_max);

    -- Worthless drops stay visible but recede.
    local dim = (worth <= 0) and 0.62 or 1.0;
    local name_c = is_best and accent or vis.alpha(muted, (muted[4] or 1) * dim);
    local mid_c = is_best and accent or vis.alpha(light, (light[4] or 1) * dim);
    local gil_c = (worth > 0) and accent or vis.alpha(muted, 0.55);

    imgui.SetCursorPosX(name_left);
    imgui.SetCursorPosY(row_y);
    ui.text_outlined_colored(display_name, name_c);

    local cw = text_w(count_str);
    imgui.SameLine(0, 0);
    imgui.SetCursorPosY(row_y);
    imgui.SetCursorPosX(math.max(content_left, count_right - cw));
    ui.text_outlined_colored(count_str, mid_c);

    local pw = text_w(pct_str);
    imgui.SameLine(0, 0);
    imgui.SetCursorPosY(row_y);
    imgui.SetCursorPosX(math.max(content_left, pct_right - pw));
    ui.text_outlined_colored(pct_str, mid_c);

    local gw = text_w(gil_str);
    imgui.SameLine(0, 0);
    imgui.SetCursorPosY(row_y);
    imgui.SetCursorPosX(math.max(content_left, gil_right - gw));
    ui.text_outlined_colored(gil_str, gil_c);
end

--- Two label/value columns. opts: { c1, c2 } value colors.
local function draw_stat_pair(l1, v1, l2, v2, content_left, content_w, opts)
    opts = opts or {};
    local label_c = theme.colors.text_dim or theme.colors.text_light;
    content_left = content_left or 0;
    content_w = math.max(content_w or 0, 200);
    local gap = 12;
    local col_w = math.floor((content_w - gap) / 2);
    if col_w < 80 then col_w = 80; end
    local row_y = num_or(imgui.GetCursorPosY(), 0);

    local function half(label, value, x0, width, value_c)
        local lab = tostring(label or '');
        local val = tostring(value or '');
        local vw = text_w(val);
        local max_lab = width - vw - 6;
        if max_lab < 10 then max_lab = 10; end
        lab = truncate_to_width(lab, max_lab);

        imgui.SetCursorPosY(row_y);
        imgui.SetCursorPosX(x0);
        ui.text_outlined_colored(lab, label_c);

        imgui.SameLine(0, 0);
        imgui.SetCursorPosY(row_y);
        imgui.SetCursorPosX(x0 + width - vw);
        ui.text_outlined_colored(val, value_c or theme.colors.text_gold);
    end

    half(l1, v1, content_left, col_w, opts.c1);
    half(l2, v2, content_left + col_w + gap, col_w, opts.c2);
end

-- Horizontal pill tabs across the top, each in its own accent when selected.
local function draw_top_tabs(scale, content_w, settings, mini)
    local tab_h = math.max(mini and 16 or 20, math.floor((mini and 17 or 22) * scale + 0.5));
    local gap = math.max(4, math.floor(6 * scale + 0.5));
    -- Only the tabs you kept. Eight will not fit a 340px panel; two or three
    -- fit comfortably, which is the point of letting you choose.
    local tabs = M.visible_tabs(settings);
    local n = #tabs;
    local tab_w = math.floor((content_w - gap * (n - 1)) / n);
    if tab_w < 42 then tab_w = 42; end

    local muted = theme.colors.text_dim or { 0.70, 0.78, 0.92, 1.0 };

    for i, act in ipairs(tabs) do
        local selected = (M.active_tab == act);
        local label = TAB_LABELS[act];
        local accent = accent_of(act, settings);

        if selected then
            imgui.PushStyleColor(ImGuiCol_Button, { accent[1], accent[2], accent[3], 0.22 });
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, { accent[1], accent[2], accent[3], 0.32 });
            imgui.PushStyleColor(ImGuiCol_ButtonActive, { accent[1], accent[2], accent[3], 0.40 });
            imgui.PushStyleColor(ImGuiCol_Text, accent);
        else
            imgui.PushStyleColor(ImGuiCol_Button, { 1, 1, 1, 0.04 });
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 1, 1, 1, 0.10 });
            imgui.PushStyleColor(ImGuiCol_ButtonActive, { 1, 1, 1, 0.14 });
            imgui.PushStyleColor(ImGuiCol_Text, muted);
        end

        imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4);
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 6, 3 });
        if imgui.Button(label .. '##htab_' .. act, { tab_w, tab_h }) then
            M.active_tab = act;
        end
        imgui.PopStyleVar(2);
        imgui.PopStyleColor(4);

        local min_x, min_y = imgui.GetItemRectMin();
        local max_x, max_y = imgui.GetItemRectMax();
        min_x = num_or(min_x, 0);
        min_y = num_or(min_y, 0);
        max_x = num_or(max_x, min_x + tab_w);
        max_y = num_or(max_y, min_y + tab_h);
        local dl = draw_list();

        if selected then
            vis.rect(dl, min_x + 4, max_y - 2, (max_x - min_x) - 8, 2, vis.alpha(accent, 0.95), 1);
        else
            -- Badge dot: this tab has a session running behind your back.
            local other = sess(act);
            if (other.swings or 0) > 0 then
                vis.dot(dl, max_x - 5, min_y + 5, 2.5, vis.alpha(accent, 0.85));
            end
        end

        if i < n then
            imgui.SameLine(0, gap);
        end
    end
end

--- Hero row: identity + skill on the left, the number you actually watch on
--- the right, at 1.5x. Flashes on a skill-up.
local function draw_hero(act, settings, s, session_secs, hero_value, hero_suffix, accent, content_left, content_w, hero_scale)
    local muted = theme.colors.text_dim or theme.colors.text_light;
    local light = theme.colors.text_light;
    local dl = draw_list();

    hero_scale = tonumber(hero_scale) or 1.5;
    local tag = fonts.push_scale(hero_scale);
    local hero_w, hero_h = ui.measure_text(hero_value);
    fonts.pop_scale(tag);
    hero_h = hero_h or line_h();

    local small_h = line_h();
    local row_y = num_or(imgui.GetCursorPosY(), 0);
    local pad_top = math.max(0, math.floor((hero_h - (small_h * 2)) * 0.5 + 0.5));

    -- Skill-up flash behind the whole hero block.
    if ui_flag(settings, 'animations', true) and (s.flash_ms or 0) > 0 then
        local age = now_ms() - s.flash_ms;
        if age >= 0 and age < FLASH_MS then
            local t = 1 - (age / FLASH_MS);
            imgui.SetCursorPosX(content_left);
            imgui.SetCursorPosY(row_y);
            local fx, fy = screen_xy();
            vis.rect(dl, fx - 4, fy - 3, content_w + 8, hero_h + 6, vis.alpha(accent, 0.22 * t), 4);
        end
    end

    -- A big drop gets a gold flash of its own. You heard the pickaxe; this is
    -- the panel agreeing with you.
    if ui_flag(settings, 'animations', true) and (s.big_flash_ms or 0) > 0 then
        local age = now_ms() - s.big_flash_ms;
        if age >= 0 and age < FLASH_MS then
            local t = 1 - (age / FLASH_MS);
            local gold = theme.colors.text_gold or accent;
            imgui.SetCursorPosX(content_left);
            imgui.SetCursorPosY(row_y);
            local fx, fy = screen_xy();
            vis.rect(dl, fx - 4, fy - 3, content_w + 8, hero_h + 6, vis.alpha(gold, 0.25 * t), 4);
        end
    end

    -- Right: hero number + unit suffix.
    local suffix_w = 0;
    if hero_suffix ~= nil and hero_suffix ~= '' then
        suffix_w = text_w(' ' .. hero_suffix);
    end
    local hero_x = content_left + content_w - hero_w - suffix_w;
    if hero_x < content_left then hero_x = content_left; end

    imgui.SetCursorPosX(hero_x);
    imgui.SetCursorPosY(row_y);
    tag = fonts.push_scale(hero_scale);
    ui.text_outlined_colored(hero_value, accent);
    fonts.pop_scale(tag);

    if suffix_w > 0 then
        imgui.SameLine(0, 0);
        imgui.SetCursorPosX(hero_x + hero_w);
        imgui.SetCursorPosY(row_y + math.max(0, hero_h - small_h - 2));
        ui.text_outlined_colored(' ' .. hero_suffix, muted);
    end

    -- Left: activity + skill, vertically centered against the hero number.
    imgui.SameLine(0, 0);
    imgui.SetCursorPosX(content_left);
    imgui.SetCursorPosY(row_y + pad_top);
    ui.text_outlined_colored(string.upper(TAB_LABELS[act] or act), vis.alpha(muted, 0.85));

    local sk = skill_value(settings, act);
    imgui.SetCursorPosX(content_left);
    imgui.SetCursorPosY(row_y + pad_top + small_h);
    if sk ~= nil and skill_display_enabled(settings, act) then
        local txt = string.format('Skill %.1f', sk);
        if (s.skill_gain or 0) > 0 then
            txt = txt .. string.format('  +%.1f', s.skill_gain);
        end
        ui.text_outlined_colored(txt, light);
    elseif act == 'hunting' then
        ui.text_outlined_colored(string.format('%d kills', s.swings or 0), light);
    else
        ui.text_outlined_colored(format.format_duration(session_secs), light);
    end

    -- Advance past whichever column is taller (hero number vs the two small lines).
    local block_h = math.max(hero_h, pad_top + (small_h * 2));
    imgui.SetCursorPosY(row_y + block_h + 2);
    imgui.Dummy({ 0, 0 });

    -- Skill progress toward the next whole level.
    if sk ~= nil and skill_display_enabled(settings, act) and ui_flag(settings, 'show_bars', true) then
        local frac = sk - math.floor(sk);
        imgui.SetCursorPosX(content_left);
        local bx, by = screen_xy();
        vis.bar(dl, bx, by, content_w, 3, frac, vis.alpha(accent, 0.45), accent, { rounding = 1.5 });
        imgui.Dummy({ content_w, 5 });
    end
end

--- Mini mode: the four things you actually act on while gathering.
--- Rate, when to stop, whether you have tools, and what you have made.
local function draw_mini_body(act, settings, pricing, pad, content_w, accent)
    local s = sess(act);
    local session_secs = M.get_session_seconds(act);
    local paused = M.is_session_paused_idle(act);
    local net = M.get_net_gil(act, settings, pricing);
    local gph = M.get_gph(act, settings, pricing);
    local cap = fatigue_cap(settings, act);
    local tools = count_tool(act);

    local muted = theme.colors.text_dim or theme.colors.text_light;
    local light = theme.colors.text_light;
    local good = theme.state_color('good');
    local warn = theme.state_color('warn');
    local bad = theme.state_color('bad');

    if ui_flag(settings, 'animations', true) then
        if s.anim_gil == nil or math.abs(net - s.anim_gil) < 1 then
            s.anim_gil = net;
        else
            s.anim_gil = s.anim_gil + ((net - s.anim_gil) * 0.18);
        end
    else
        s.anim_gil = net;
    end
    local shown_gil = math.floor((s.anim_gil or net) + 0.5);

    local rate_ready = session_secs >= RATE_WARMUP_S;
    local hero_value = rate_ready and format.format_int(gph) or '--';

    draw_hero(act, settings, s, session_secs, hero_value, 'gil/hr', accent, pad, content_w, 1.3);

    -- Fatigue: the stop signal.
    local show_fatigue = settings.tracker.show_fatigue == nil or settings.tracker.show_fatigue[1];
    if cap ~= nil and cap > 0 and show_fatigue and act ~= 'hunting' then
        -- Fatigue is the server's allowance and clears on its own schedule, so
        -- it is counted separately from the session item total.
        local items = s.items or 0;
        local left = math.max(0, cap - items);
        local fill = vis.clamp01(items / cap);
        local eta_str = nil;
        if session_secs > 0 and (s.items or 0) > 0 then
            if left <= 0 then
                eta_str = 'CAP';
            else
                -- Project from how fast you are gathering this session.
                local rate = (s.items or 0) / session_secs;
                if rate > 0 then
                    eta_str = format.format_duration(math.floor(left / rate + 0.5));
                end
            end
        end

        -- Being capped is not the end of the night if the reset is minutes away.
        local reset_left = M.fatigue_time_left();
        local value = fatigue_value(fill, items, cap, eta_str, reset_left,
            content_w - text_w('Fatigue') - 12);

        local value_c = accent;
        if fill >= 0.9 then
            value_c = bad;
        elseif fill >= 0.75 then
            value_c = warn;
        end
        if left <= 0 and reset_left ~= nil and reset_left <= 1800 then
            value_c = good;   -- capped, but it comes back soon
        end

        draw_meter('Fatigue', value, fill, pad, content_w, {
            value_color = value_c,
            from = vis.alpha(good, 0.9),
            to = vis.ramp3(good, warn, bad, fill),
            ticks = expert_on(settings) and { 0.25, 0.5, 0.75 } or nil,
        });
    end

    local tool_c = light;
    if tools <= 10 then
        tool_c = bad;
    elseif tools <= 25 then
        tool_c = warn;
    end

    if act == 'hunting' then
        draw_stat_pair('Kills', format.format_int(s.swings), 'Items', format.format_int(s.items),
            pad, content_w, { c1 = light, c2 = light });
        draw_row('Net Gil', format.format_int(shown_gil) .. 'g', accent, pad, content_w);
    elseif act == 'clamming' then
        -- Tools mean nothing here; the bucket is the only number that
        -- decides whether to keep going.
        local cap = s.bucket_capacity or 0;
        if cap <= 0 then cap = constants.CLAM_START_CAPACITY or 50; end
        local wt = s.bucket_weight or 0;
        local risk = M.clam_risk(wt, cap,
            settings.clamming and settings.clamming.hq_body and settings.clamming.hq_body[1]);
        local bucket_c = light;
        if risk.tier == 'stop' then
            bucket_c = bad;
        elseif risk.tier == 'risky' then
            bucket_c = warn;
        end
        local delay = (settings.clamming and settings.clamming.dig_delay
            and settings.clamming.dig_delay[1]) or constants.CLAM_POINT_RESPAWN or 10;
        local cd_left, cd_ready = M.clam_cooldown(s.last_find_s, now_s(), delay);
        draw_stat_pair(cd_ready and 'READY' or string.format('%.0fs', math.ceil(cd_left)),
            format.format_int(s.swings) .. ' digs', 'Bucket',
            string.format('%d/%d pz', wt, cap),
            pad, content_w, { c1 = cd_ready and good or light, c2 = bucket_c });
        draw_stat_pair('In bucket',
            format.format_int(math.floor(M.get_bucket_value(pricing, act) + 0.5)) .. 'g',
            'Net Gil', format.format_int(shown_gil) .. 'g',
            pad, content_w, { c1 = bucket_c, c2 = accent });
    else
        draw_stat_pair(SWING_LABEL[act], format.format_int(s.swings), 'Breaks',
            format.format_int(s.breaks),
            pad, content_w, { c1 = light, c2 = (s.breaks or 0) > 0 and warn or light });
        draw_stat_pair(TOOL_LABEL[act], format.format_int(tools), 'Net Gil',
            format.format_int(shown_gil) .. 'g',
            pad, content_w, { c1 = tool_c, c2 = accent });
    end

    local session_str = format.format_duration(session_secs);
    if paused then
        session_str = session_str .. '  (idle)';
    end
    draw_row('Session', session_str, muted, pad, content_w);
end

local function draw_activity_body(act, settings, pricing, pad, content_w, scale, transparent)
    local s = sess(act);
    local session_secs = M.get_session_seconds(act);
    local session_str = format.format_duration(session_secs);
    local paused = M.is_session_paused_idle(act);
    local accuracy = M.get_accuracy(act);
    local net = M.get_net_gil(act, settings, pricing);
    local gph = M.get_gph(act, settings, pricing);
    local tools = count_tool(act);
    local cost = tool_cost(settings, act);
    local cap = fatigue_cap(settings, act);
    local sk = skill_value(settings, act);

    local accent = accent_of(act, settings);
    local muted = theme.colors.text_dim or theme.colors.text_light;
    local light = theme.colors.text_light;
    local good = theme.state_color('good');
    local warn = theme.state_color('warn');
    local bad = theme.state_color('bad');
    local detail = detail_level(settings);
    local compact = (detail == 'Compact');
    local show_bars = ui_flag(settings, 'show_bars', true);

    -- Reset the haul budget for this tab. Layouts that never reach the haul
    -- (Mini, Compact, an empty session) leave it at zero, which makes the
    -- panel's minimum height simply its natural height: nothing to shrink.
    local hm = haul_metrics(act);
    hm.rows = 0;
    hm.used = 0;

    if detail == 'Mini' then
        draw_mini_body(act, settings, pricing, pad, content_w, accent);
        return;
    end

    -- Gil counts up instead of snapping (purely cosmetic).
    if ui_flag(settings, 'animations', true) then
        if s.anim_gil == nil then
            s.anim_gil = net;
        elseif math.abs(net - s.anim_gil) < 1 then
            s.anim_gil = net;
        else
            s.anim_gil = s.anim_gil + ((net - s.anim_gil) * 0.18);
        end
    else
        s.anim_gil = net;
    end
    local shown_gil = math.floor((s.anim_gil or net) + 0.5);

    -- The rate is meaningless in the first minutes; do not pretend otherwise.
    local rate_ready = session_secs >= RATE_WARMUP_S;
    local hero_value = rate_ready and format.format_int(gph) or '--';

    draw_hero(act, settings, s, session_secs, hero_value, 'gil/hr', accent, pad, content_w);

    -- Meta line: session clock, moon, Vana'diel day + time.
    local clock = session_str .. (paused and ' (idle)' or '');
    local meta = clock;
    if settings.tracker.show_moon == nil or settings.tracker.show_moon[1] then
        local ts = vana.get_timestamp();
        local moon = vana.get_moon(ts);
        local weekday = vana.get_weekday(ts);
        local day_name = (weekday and weekday.name) or '';
        local moon_full = vana.format_moon(moon);
        local moon_pct = (moon and moon.percent ~= nil)
            and (tostring(moon.percent) .. '%') or moon_full;
        local vtime = vana.format_time(ts);

        local function join(...)
            local out = T{};
            for _, v in ipairs({ ... }) do
                if v ~= nil and v ~= '' then
                    out:append(v);
                end
            end
            return table.concat(out, '  |  ');
        end

        -- Live zone weather, read off the game's own packets. It rides the
        -- meta line rather than taking a row of its own: it is a fact about
        -- where you are standing, like the clock and the moon, and it is the
        -- one ore gate you cannot work out in your head. The ore row only
        -- appears in a dig zone, so without this there was nowhere to see it.
        local wx_name = nil;
        do
            local w = weather.current();
            if w.known then
                wx_name = w.name;
                if w.double then
                    wx_name = wx_name .. ' x2';
                end
            elseif act == 'digging' then
                -- Only the Dig tab admits to not knowing: weather is an ore
                -- gate there, so its absence is information. Everywhere else
                -- an unreadable sky is not worth a word.
                wx_name = 'sky ?';
            end
        end

        -- Shed detail a piece at a time instead of chopping the last field in half.
        meta = first_that_fits(content_w, {
            join(clock, moon_full, day_name, vtime, wx_name),
            join(clock, moon_pct, day_name, vtime, wx_name),
            join(clock, moon_pct, vtime, wx_name),
            join(clock, moon_full, day_name, vtime),
            join(clock, moon_pct, day_name, vtime),
            join(clock, moon_pct, vtime),
            join(clock, vtime),
        }) or clock;
    end
    imgui.SetCursorPosX(pad);
    ui.text_outlined_colored(truncate_to_width(meta, content_w), muted);

    -- Zone line with a stay/move verdict for the gathering tabs.
    if act ~= 'hunting' then
        M.refresh_zone();
        local zone_line = M.zone_name or 'Unknown';
        local verdict = nil;
        if settings.tracker.show_zone_verdict == nil or settings.tracker.show_zone_verdict[1] then
            verdict = M.get_zone_verdict(settings, act);
        end
        if verdict ~= nil then
            -- Say as much as the window allows, dropping whole clauses rather
            -- than cutting through a figure.
            local here_s, cmp_s = M.zone_verdict_parts(verdict);
            local room = content_w - (text_w(verdict.label) + 20);
            if here_s ~= nil then
                local zone = zone_line;
                zone_line = first_that_fits(room, {
                    (cmp_s ~= nil) and (zone .. '   ' .. here_s .. '   ' .. cmp_s) or nil,
                    zone .. '   ' .. here_s,
                }) or fit_name_tail(zone, here_s, room);
            end
            draw_row_chip(zone_line, muted, verdict.label, theme.state_color(verdict.state), pad, content_w);

            -- The best zone for gil is rarely the best zone for skill, and the
            -- skill answer moves as you level, so both are shown.
            if not compact and (settings.tracker.show_best_for == nil
                or settings.tracker.show_best_for[1]) then
                local band = M.band_of(sk or 0);
                local gil_rec, gil_rate = M.best_zone_for(act, false, nil);
                local skl_rec, skl_rate, used_band = M.best_zone_for(act, true, band);

                local label, value = M.best_for_row(
                    gil_rec, gil_rate, skl_rec, skl_rate, used_band,
                    content_w - text_w('Best') - 12);
                if value ~= nil then
                    draw_row(label, value, light, pad, content_w);
                end
            end
        else
            zone_line = 'Area: ' .. zone_line;
            imgui.SetCursorPosX(pad);
            ui.text_outlined_colored(truncate_to_width(zone_line, content_w), muted);
        end
    end

    draw_rule(pad, content_w, accent, transparent);

    if act == 'fishing' then
        ------------------------------------------------------------------
        -- The fishing funnel. Casts is what you did; bites is what the water
        -- gave you; catches is what you kept. The gaps between those three
        -- are the two different problems - a low bite rate is the spot, a low
        -- land rate is your rod and skill.
        ------------------------------------------------------------------
        local casts  = s.swings or 0;
        local bites  = s.bites or 0;
        local caught = s.items or 0;

        local bite_rate = (casts > 0) and ((bites / casts) * 100) or 0;
        local land_rate = (bites > 0) and ((caught / bites) * 100) or 0;
        local cph = (session_secs > 0) and math.floor((caught / session_secs) * 3600) or 0;

        draw_stat_pair('Casts', format.format_int(casts),
            'Bites', format.format_int(bites) .. string.format('  %.0f%%', bite_rate),
            pad, content_w, { c1 = light, c2 = accent });
        draw_stat_pair('Caught', format.format_int(caught) .. string.format('  %.0f%%', land_rate),
            'Catch/hr', format.format_int(cph),
            pad, content_w, { c1 = accent, c2 = accent });

        -- Losses, split by diagnosis. Lumping these together hides which of
        -- the four different problems you actually have.
        local losses = (s.lost or 0) + (s.line_breaks or 0) + (s.breaks or 0);
        if losses > 0 or (s.monsters or 0) > 0 then
            local parts = T{};
            if (s.lost or 0) > 0 then
                local tag = format.format_int(s.lost);
                if (s.lost_skill or 0) > 0 then
                    tag = tag .. string.format(' (%d skill)', s.lost_skill);
                end
                parts:append('lost ' .. tag);
            end
            if (s.line_breaks or 0) > 0 then
                parts:append('line ' .. format.format_int(s.line_breaks));
            end
            if (s.breaks or 0) > 0 then
                parts:append('rod ' .. format.format_int(s.breaks));
            end
            if (s.monsters or 0) > 0 then
                parts:append('mob ' .. format.format_int(s.monsters));
            end
            draw_row('Lost', table.concat(parts, '   '),
                (losses > 0) and warn or light, pad, content_w);
        end

        -- Bait is spent per bite here, not per cast, so bites is the bill.
        local bait_cost = tool_cost(settings, act);
        if bait_cost > 0 and bites > 0 then
            local spent = bites * bait_cost;
            local spend_str = format.format_int(spent) .. 'g';
            if session_secs >= RATE_WARMUP_S then
                spend_str = spend_str .. '  '
                    .. format.format_int(math.floor((spent / session_secs) * 3600 + 0.5)) .. '/hr';
            end
            draw_stat_pair('Bait used', format.format_int(bites), 'Bait cost', spend_str,
                pad, content_w, { c1 = light, c2 = light });
        end

        -- No fatigue on this server - the limit is the water's stock, which
        -- refills on the Vana'diel clock. Tell them when that happens.
        do
            local ok_ts, ts = pcall(vana.get_timestamp);
            if ok_ts and ts ~= nil then
                local ok_cd, cd = pcall(vana.format_restock_countdown, ts);
                if ok_cd and cd ~= nil then
                    draw_row('Next restock', tostring(cd), muted, pad, content_w);
                end
            end
        end

    elseif act == 'digging' then
        ------------------------------------------------------------------
        -- Digging economics are brutal: a green is spent on nearly every
        -- attempt, including the ones that find nothing. So the only number
        -- that matters is gil per green.
        ------------------------------------------------------------------
        local digs  = s.swings or 0;
        local found = s.items or 0;
        local hit_rate = (digs > 0) and ((found / digs) * 100) or 0;
        local dph = (session_secs > 0) and math.floor((digs / session_secs) * 3600) or 0;

        local early = s.rejected or 0;
        local digs_str = format.format_int(digs);
        if early > 0 then
            local with_early = digs_str .. string.format('   %d early', early);
            if text_w(with_early) <= (content_w * 0.32) then
                digs_str = with_early;
            end
        end
        draw_stat_pair('Digs', digs_str, 'Digs/hr', format.format_int(dph),
            pad, content_w, { c1 = light, c2 = accent });
        draw_stat_pair('Found', format.format_int(found) .. string.format('  %.0f%%', hit_rate),
            'Rejected', format.format_int(s.rejected or 0),
            pad, content_w, { c1 = accent, c2 = ((s.rejected or 0) > 0) and warn or light });

        -- Greens in the bag, which is the number that decides whether you
        -- can keep going. The old row here printed greens USED, which is the
        -- same number as Digs one row up - a wasted line.
        local green_cost = tool_cost(settings, act);
        local greens_left = tools;
        local left_str = format.format_int(greens_left);
        if dph > 0 then
            -- A green goes on nearly every dig, so stock over digs-per-hour
            -- is honestly how long you can keep digging.
            local hrs = greens_left / dph;
            local mins = math.floor(hrs * 60 + 0.5);
            local with_eta;
            if mins >= 60 then
                with_eta = string.format('%s   ~%dh %02dm', left_str,
                    math.floor(mins / 60), mins % 60);
            else
                with_eta = string.format('%s   ~%dm', left_str, mins);
            end
            local room = content_w * 0.5;
            if text_w(with_eta) <= room then
                left_str = with_eta;
            end
        end
        local left_c = light;
        if greens_left <= 10 then
            left_c = bad;
        elseif greens_left <= 25 then
            left_c = warn;
        end

        if green_cost > 0 and digs > 0 then
            local spent = digs * green_cost;
            local gross = M.get_total_worth(act, pricing);
            local per_green = (gross - spent) / digs;
            draw_stat_pair('Greens left', left_str,
                'Net/green', format.format_int(math.floor(per_green + 0.5)) .. 'g',
                pad, content_w, { c1 = left_c, c2 = (per_green >= 0) and good or bad });
        else
            draw_row('Greens left', left_str, left_c, pad, content_w);
        end

        -- The personal daily item cap. Unlike HELM fatigue this one runs on a
        -- real-life clock: the server banks it against Japanese midnight, so
        -- the counter here rolls over at 00:00 JST too, and the cap itself is
        -- 100 + 10 per digging rank, with rank derived from your dig skill.
        local show_fatigue = settings.tracker.show_fatigue == nil or settings.tracker.show_fatigue[1];
        if cap ~= nil and cap > 0 and show_fatigue then
            roll_dig_day(s);
            local today = s.daily_items or 0;
            local fill = vis.clamp01(today / cap);
            local base = string.format('%.0f%%   %s / %s', fill * 100,
                format.format_int(today), format.format_int(cap));
            local value = base;
            do
                local secs = vana.seconds_until_jst_midnight();
                local hh = math.floor(secs / 3600);
                local mm = math.floor((secs % 3600) / 60);
                local short = (hh > 0) and string.format('%dh %02dm', hh, mm)
                    or string.format('%dm', mm);
                local reset = string.format('%s   resets %s', base, short);
                if text_w(reset) <= (content_w - text_w('Daily cap') - 12) then
                    value = reset;
                end
            end
            local value_c = accent;
            if fill >= 0.9 then
                value_c = bad;
            elseif fill >= 0.75 then
                value_c = warn;
            end
            if show_bars then
                draw_meter('Daily cap', value, fill, pad, content_w, {
                    value_color = value_c,
                    from = vis.alpha(good, 0.9),
                    to = vis.ramp3(good, warn, bad, fill),
                    ticks = expert_on(settings) and { 0.25, 0.5, 0.75 } or nil,
                });
            else
                draw_row('Daily cap', value, value_c, pad, content_w);
            end
        end

        ------------------------------------------------------------------
        -- Elemental ore window. Four gates have to line up at once - rank,
        -- moon, weather and zone - and three of them change under you while
        -- you dig. One line: open or shut, and what is shutting it. The full
        -- per-gate breakdown lives in /floos ore, where it costs no space.
        ------------------------------------------------------------------
        local show_ore = settings.digging == nil or settings.digging.ore_watch == nil
            or settings.digging.ore_watch[1];
        if show_ore then
            local label = 'Ore watch';
            local value, tier = M.ore_row(M.ore_conditions(settings),
                content_w - text_w(label) - 8);
            if value ~= nil then
                local colr = muted;
                if tier == 'good' then
                    colr = good;
                elseif tier == 'warn' then
                    colr = warn;
                end
                draw_row(label, value, colr, pad, content_w);
            end
        end

        -- Horizon says so out loud when a zone is dug out. That is the single
        -- most actionable thing on this tab: every further green is wasted.
        if s.zone_empty then
            draw_row('Zone', 'DUG OUT - move or wait for Vana midnight', bad, pad, content_w);
        end

    elseif act == 'clamming' then
        ------------------------------------------------------------------
        -- Clamming is the only activity here where the numbers on screen
        -- are not a record of what happened - they are a decision. The
        -- bucket is all-or-nothing, so the panel's job is to say what the
        -- next dig actually risks, in gil.
        ------------------------------------------------------------------
        local digs = s.swings or 0;
        local dph = (session_secs > 0) and math.floor((digs / session_secs) * 3600) or 0;
        local capacity = s.bucket_capacity or 0;
        if capacity <= 0 then capacity = constants.CLAM_START_CAPACITY or 50; end
        local wt = s.bucket_weight or 0;
        local bucket_gil = M.get_bucket_value(pricing, act);

        draw_stat_pair('Digs', format.format_int(digs), 'Digs/hr', format.format_int(dph),
            pad, content_w, { c1 = light, c2 = accent });

        -- The bucket meter. Filling it is the goal and also the danger, so
        -- unlike every other meter here the colour ramps the wrong way on
        -- purpose: full is bad.
        local fill = vis.clamp01((capacity > 0) and (wt / capacity) or 0);
        local wt_value = string.format('%d / %d pz', wt, capacity);
        if s.assumed_weight then
            wt_value = wt_value .. ' ~';
        end
        local wt_c = accent;
        if fill >= 0.95 then
            wt_c = bad;
        elseif fill >= 0.8 then
            wt_c = warn;
        end
        if show_bars then
            draw_meter('Bucket', wt_value, fill, pad, content_w, {
                value_color = wt_c,
                from = vis.alpha(good, 0.9),
                to = vis.ramp3(good, warn, bad, fill),
                ticks = expert_on(settings) and { 0.25, 0.5, 0.75 } or nil,
            });
        else
            draw_row('Bucket', wt_value, wt_c, pad, content_w);
        end

        -- The one number that decides whether to dig again: what is in the
        -- bucket, and the real odds of losing it on the next scoop.
        local risk = M.clam_risk(wt, capacity,
            settings.clamming and settings.clamming.hq_body and settings.clamming.hq_body[1]);
        local risk_c = good;
        if risk.tier == 'stop' then
            risk_c = bad;
        elseif risk.tier == 'risky' then
            risk_c = warn;
        elseif risk.tier == 'watch' then
            risk_c = light;
        end
        -- The point's cooldown. This is the number you actually watch while
        -- clamming: click early and the server just says no and eats the
        -- click, which is what those "someone has been digging here" lines
        -- in the log are.
        local delay = (settings.clamming and settings.clamming.dig_delay
            and settings.clamming.dig_delay[1]) or constants.CLAM_POINT_RESPAWN or 10;
        local left, ready = M.clam_cooldown(s.last_find_s, now_s(), delay);
        local cd_str, cd_c;
        if ready then
            cd_str = 'READY';
            cd_c = good;
        else
            cd_str = string.format('%.0fs', math.ceil(left));
            cd_c = muted;
        end

        draw_stat_pair('In bucket',
            format.format_int(math.floor(bucket_gil + 0.5)) .. 'g',
            'Next dig', cd_str,
            pad, content_w, { c1 = accent, c2 = cd_c });

        -- Risk gets its own line, and only when there is any. "Safe" is the
        -- absence of information, so it does not need a row of its own.
        if risk.break_pct > 0.001 then
            local risk_str = first_that_fits(content_w * 0.6, {
                string.format('%.0f%% break   -%s', risk.break_pct,
                    format.format_int(math.floor(bucket_gil + 0.5)) .. 'g'),
                string.format('%.0f%% break', risk.break_pct),
                string.format('%.0f%%', risk.break_pct),
            }) or string.format('%.0f%%', risk.break_pct);
            draw_row('Risk', risk_str, risk_c, pad, content_w);
        end

        -- Toh Zonikki offers the next bucket size at capacity minus five, so
        -- there is a narrow band where one more dig is worth the risk for the
        -- upgrade rather than the gil.
        if M.clam_upgrade_ready(wt, capacity) then
            draw_row('Upgrade', 'ready - hand in for the next bucket up', good, pad, content_w);
        end

        if s.bucket_broken then
            draw_row('Bucket', 'BROKEN - buy a new kit from Toh Zonikki', bad, pad, content_w);
        end

        -- Kits and losses. Only worth a row once something has happened.
        if (s.kits or 0) > 0 or (s.breaks or 0) > 0 then
            local lost = T{};
            if (s.overweight or 0) > 0 then
                lost:append(format.format_int(s.overweight) .. ' over');
            end
            if (s.incidents or 0) > 0 then
                lost:append(format.format_int(s.incidents) .. ' jumped');
            end
            local lost_str = (#lost > 0) and table.concat(lost, '  ') or 'none';
            draw_stat_pair('Kits', format.format_int(s.kits or 0)
                .. '   ' .. format.format_int(s.turnins or 0) .. ' in',
                'Lost', lost_str,
                pad, content_w, { c1 = light, c2 = ((s.breaks or 0) > 0) and bad or light });
        end

    elseif act == 'hunting' then
        local steal_acc = 0;
        if (s.steal_attempts or 0) > 0 then
            steal_acc = ((s.steals or 0) / s.steal_attempts) * 100;
        end
        local drop_rate = 0;
        if s.swings > 0 then
            drop_rate = (s.items / s.swings) * 100;
        end
        local kph = 0;
        if session_secs > 0 then
            kph = math.floor((s.swings / session_secs) * 3600);
        end

        draw_stat_pair('Kills', format.format_int(s.swings), 'Kills/hr', format.format_int(kph),
            pad, content_w, { c1 = accent, c2 = accent });
        draw_stat_pair('Items', format.format_int(s.items), 'Drop Rate', format.format_percent(drop_rate),
            pad, content_w, { c1 = accent, c2 = light });

        if (s.steal_attempts or 0) > 0 then
            local steal_line = format.format_int(s.steals or 0) .. ' / ' .. format.format_int(s.steal_attempts or 0);
            draw_stat_pair('Steals', steal_line, 'Steal Rate', format.format_percent(steal_acc),
                pad, content_w, { c1 = accent, c2 = light });
        end
        if (s.raw_gil or 0) > 0 then
            draw_row('Raw Gil', format.format_int(s.raw_gil or 0) .. 'g', accent, pad, content_w);
        end
    else
        -- Fatigue: the number that decides when you go home.
        local show_fatigue = settings.tracker.show_fatigue == nil or settings.tracker.show_fatigue[1];
        if cap ~= nil and cap > 0 and show_fatigue then
            -- Fatigue is the server's allowance and clears on its own schedule, so
            -- it is counted separately from the session item total.
            local items = s.items or 0;
            local left = math.max(0, cap - items);
            local fill = vis.clamp01(items / cap);
            local eta_str = nil;
            if session_secs > 0 and (s.items or 0) > 0 then
                if left <= 0 then
                    eta_str = 'CAP';
                else
                    -- Project from how fast you are gathering this session.
                    local rate = (s.items or 0) / session_secs;
                    if rate > 0 then
                        eta_str = format.format_duration(math.floor(left / rate + 0.5));
                    end
                end
            end

            -- Being capped is not the end of the night if the reset is minutes away.
            local reset_left = M.fatigue_time_left();
            local value = fatigue_value(fill, items, cap, eta_str, reset_left,
                content_w - text_w('Fatigue') - 12);

            local value_c = accent;
            if fill >= 0.9 then
                value_c = bad;
            elseif fill >= 0.75 then
                value_c = warn;
            end
            if left <= 0 and reset_left ~= nil and reset_left <= 1800 then
                value_c = good;   -- capped, but it comes back soon
            end

            if show_bars then
                draw_meter('Fatigue', value, fill, pad, content_w, {
                    value_color = value_c,
                    from = vis.alpha(good, 0.9),
                    to = vis.ramp3(good, warn, bad, fill),
                    ticks = expert_on(settings) and { 0.25, 0.5, 0.75 } or nil,
                });
            else
                draw_row('Fatigue', value, value_c, pad, content_w);
            end
        end

        -- Accuracy against your own lifetime average.
        if show_bars and (s.swings or 0) > 0 then
            local life = M.get_lifetime_accuracy();
            local value = format.format_percent(accuracy);
            local value_c = light;
            if life ~= nil then
                value = value .. string.format('   avg %.1f%%', life);
                if accuracy >= life + 2 then
                    value_c = good;
                elseif accuracy <= life - 2 then
                    value_c = bad;
                end
            end
            draw_meter('Accuracy', value, accuracy / 100, pad, content_w, {
                value_color = value_c,
                from = vis.alpha(accent, 0.55),
                to = accent,
                tick = (life ~= nil) and (life / 100) or nil,
                tick_color = vis.alpha(light, 0.6),
            });
        elseif not show_bars then
            draw_row('Accuracy', format.format_percent(accuracy), light, pad, content_w);
        end

        if not compact then
            -- Tool stock turns amber then red before you get stranded.
            local tool_c = light;
            if tools <= 10 then
                tool_c = bad;
            elseif tools <= 25 then
                tool_c = warn;
            end

            -- Break rate next to the count: 51 breaks means little on its own,
            -- 19% of swings tells you whether this pickaxe budget is normal.
            local breaks_str = format.format_int(s.breaks);
            if (s.swings or 0) > 0 and (s.breaks or 0) > 0 then
                breaks_str = breaks_str
                    .. string.format('  %.0f%%', (s.breaks / s.swings) * 100);
            end
            -- Break cost as a rate, because that is what eats the gil/hr.
            local bcost = (s.breaks or 0) * cost;
            local bcost_str = format.format_int(bcost) .. 'g';
            if bcost > 0 and session_secs >= RATE_WARMUP_S then
                bcost_str = bcost_str .. '  '
                    .. format.format_int(math.floor((bcost / session_secs) * 3600 + 0.5))
                    .. '/hr';
            end

            draw_stat_pair(SWING_LABEL[act], format.format_int(s.swings), 'Breaks', breaks_str,
                pad, content_w, { c1 = light, c2 = (s.breaks or 0) > 0 and warn or light });
            draw_stat_pair(TOOL_LABEL[act], format.format_int(tools), 'Break Cost', bcost_str,
                pad, content_w, { c1 = tool_c, c2 = light });
        end

        -- Swing history strip.
        if ui_flag(settings, 'show_strip', true) then
            draw_outcome_strip(s, pad, content_w, accent);
        end
    end

    -- Rewards, best value first, worthless drops dimmed at the bottom.
    local names = T{};
    for n, _ in pairs(s.rewards) do names:append(n); end

    local total_items = 0;
    local max_worth = 0;
    local worth_of = {};
    for _, name in ipairs(names) do
        local count = s.rewards[name] or 0;
        local unit = tonumber(pricing[normalize_key(name)]) or 0;
        local total = unit * count;
        worth_of[name] = total;
        total_items = total_items + count;
        if total > max_worth then
            max_worth = total;
        end
    end

    table.sort(names, function (a, b)
        local wa = worth_of[a] or 0;
        local wb = worth_of[b] or 0;
        if wa ~= wb then
            return wa > wb;
        end
        local ca = s.rewards[a] or 0;
        local cb = s.rewards[b] or 0;
        if ca ~= cb then
            return ca > cb;
        end
        return tostring(a) < tostring(b);
    end);

    local best_name = names[1];
    if best_name ~= nil and (worth_of[best_name] or 0) <= 0 then
        -- Nothing priced: highlight the most numerous drop instead.
        local best_count = -1;
        for _, name in ipairs(names) do
            local count = s.rewards[name] or 0;
            if count > best_count then
                best_count = count;
                best_name = name;
            end
        end
    end

    if #names > 0 and not compact then
        if expert_on(settings) then
            local total_worth = 0;
            for _, name in ipairs(names) do
                total_worth = total_worth + (worth_of[name] or 0);
            end
            draw_rule_labeled(string.format('Haul  x%d  %sg',
                total_items, format.format_int(total_worth)),
                pad, content_w, accent, transparent);
        else
            draw_rule(pad, content_w, accent, transparent);
        end

        ------------------------------------------------------------------
        -- The haul is the panel's shock absorber. Everything above and
        -- below it keeps its natural height; when the window is dragged
        -- shorter the drop list is what gives, scrolling inside whatever
        -- height is left over. It stops giving at HAUL_MIN_ROWS rows, and
        -- that floor is what M.min_panel_height hands the resize grip, so
        -- the window simply refuses to go shorter rather than clipping the
        -- footer off the bottom.
        ------------------------------------------------------------------
        local row_h = (hm.row or 0);
        if row_h <= 0 then row_h = text_row_pitch(); end

        hm.rows = #names;
        -- A pixel of slack: at exactly rows*pitch a rounding wobble in the
        -- font metrics would put a scrollbar on a list that fits.
        local full_h = (row_h * #names) + 2;
        local floor_h = row_h * math.min(#names, HAUL_MIN_ROWS);

        local haul_h = full_h;
        if (M.layout_h or 0) > 0 and (hm.chrome or 0) > 0 then
            haul_h = M.layout_h - hm.chrome;
            if haul_h > full_h then haul_h = full_h; end
            if haul_h < floor_h then haul_h = floor_h; end
        end
        haul_h = math.floor(haul_h + 0.5);
        if haul_h < 1 then haul_h = 1; end

        local scrolls = haul_h < full_h - 0.5;

        -- Give the scrollbar its own lane so it never sits on the gil column.
        local list_w = content_w;
        if scrolls then
            local bite = HAUL_SCROLLBAR_W - pad + 2;
            if bite > 0 then
                list_w = content_w - bite;
                if list_w < 200 then list_w = 200; end
            end
        end

        -- Always a child, scrolling or not, so the list measures the same on
        -- every frame and the budget above does not wobble as it crosses the
        -- threshold. Zero window padding keeps the rows exactly where they
        -- sat before, and the scrollbar borrows the tab's accent.
        local vars, cols = push_haul_style(accent);

        local function draw_rows(width)
            local y0 = num_or(imgui.GetCursorPosY(), 0);
            local measured = nil;
            for i, name in ipairs(names) do
                draw_reward_row(name, s.rewards[name], worth_of[name] or 0, pad, width,
                    (best_name ~= nil and name == best_name), total_items, accent, max_worth);
                if i == 1 then
                    measured = num_or(imgui.GetCursorPosY(), 0) - y0;
                end
            end
            if measured ~= nil and measured > 0 then
                hm.row = measured;
            end
        end

        imgui.SetCursorPosX(0);
        local opened, began = ui.begin_child('FloosHaul##' .. tostring(act),
            { content_w + (pad * 2), haul_h }, false);
        if opened then
            draw_rows(list_w);
        end
        ui.end_child();

        pop_haul_style(vars, cols);

        if began then
            hm.used = haul_h;
        else
            -- No child window on this ImGui build: draw the list plainly and
            -- report no give, so the panel's floor becomes its natural height
            -- and nothing ends up clipped.
            imgui.SetCursorPosX(pad);
            draw_rows(content_w);
            hm.rows = 0;
            hm.used = 0;
        end
    end

    draw_rule(pad, content_w, accent, transparent);

    -- Footer: money, rate, lifetime.
    draw_row('Net Gil', format.format_int(shown_gil) .. 'g', accent, pad, content_w);

    if not compact then
        local rate_str = rate_ready and (format.format_int(gph) .. ' gph') or 'warming up';
        draw_row('Rate', rate_str, rate_ready and accent or muted, pad, content_w);

        -- The hero is the whole-session average; this is what the last ten
        -- minutes actually paid. The spread between them is the difference
        -- between "good session" and "good session that just went cold".
        if expert_on(settings) and rate_ready then
            local recent = M.recent_rate(s, 600);
            local trend = M.rate_trend(recent, gph);
            if recent ~= nil then
                local val = format.format_int(math.floor(recent + 0.5)) .. ' gph';
                local col = light;
                if trend ~= nil then
                    val = val .. string.format('  %+.0f%%', trend);
                    if trend >= 10 then
                        col = good;
                    elseif trend <= -25 then
                        col = bad;
                    elseif trend <= -10 then
                        col = warn;
                    end
                end
                draw_row('Last 10m', val, col, pad, content_w);
            end
        end

        if ui_flag(settings, 'show_sparkline', true) then
            draw_rate_spark(s, pad, content_w, accent);
        end

        draw_row('Lifetime Gil', format.format_int(M.get_lifetime_gil()) .. 'g', vis.alpha(accent, 0.85), pad, content_w);

        if sk ~= nil and skill_display_enabled(settings, act) and (s.skill_gain or 0) > 0 and session_secs > 0 then
            local skill_hr = (s.skill_gain / session_secs) * 3600;
            draw_row('Skill/hr', string.format('+%.1f', skill_hr), accent, pad, content_w);
        end

        if act ~= 'hunting' then
            local wr, mr, br = M.get_lifetime_wmb_rates();
            local row_y = num_or(imgui.GetCursorPosY(), 0);
            imgui.SetCursorPosX(pad);
            imgui.SetCursorPosY(row_y);
            ui.text_outlined_colored('Skillup Rate', muted);

            local parts = {
                { string.format('B %.0f%%', br or 0), bad },
                { string.format('M %.0f%%', mr or 0), light },
                { string.format('W %.0f%%', wr or 0), good },
            };
            local x = pad + content_w;
            for _, part in ipairs(parts) do
                local pw = text_w(part[1]);
                x = x - pw;
                imgui.SameLine(0, 0);
                imgui.SetCursorPosY(row_y);
                imgui.SetCursorPosX(x);
                ui.text_outlined_colored(part[1], part[2]);
                x = x - 10;
            end
        end

        if act == 'hunting' then
            local exp_total = s.exp or 0;
            local lp_total = s.limit or 0;
            local exp_hr = 0;
            local lp_hr = 0;
            if session_secs > 0 then
                exp_hr = math.floor((exp_total / session_secs) * 3600);
                lp_hr = math.floor((lp_total / session_secs) * 3600);
            end
            if exp_total > 0 or lp_total > 0 then
                draw_stat_pair('XP', format.format_int(exp_total) .. '  (' .. format.format_int(exp_hr) .. '/hr)',
                    'Limit', format.format_int(lp_total) .. '  (' .. format.format_int(lp_hr) .. '/hr)',
                    pad, content_w, { c1 = accent, c2 = accent });
            end
        end
    end
end

function M.render(settings, pricing, preview)
    if not settings.tracker.visible[1] and not preview then
        return;
    end

    -- An activity can grab focus for a tab you have switched off - it still
    -- tracks, it just has nowhere to show. Snap to a tab that exists rather
    -- than rendering a body with no tab above it.
    do
        local tabs = M.visible_tabs(settings);
        local ok_tab = false;
        for _, a in ipairs(tabs) do
            if a == M.active_tab then ok_tab = true; break; end
        end
        if not ok_tab then
            M.active_tab = tabs[1];
        end
    end

    if not preview then
        local never_hide = settings.tracker.never_hide ~= nil and settings.tracker.never_hide[1];
        if not never_hide then
            local any_recent = false;
            for _, act in ipairs(ACTIVITIES) do
                local s = sess(act);
                if s.last_activity_ms > 0 then
                    local idle_secs = (now_ms() - s.last_activity_ms) / 1000;
                    if idle_secs <= settings.tracker.display_timeout[1] then
                        any_recent = true;
                        break;
                    end
                end
            end
            local any_activity = false;
            for _, act in ipairs(ACTIVITIES) do
                if sess(act).last_activity_ms > 0 then
                    any_activity = true;
                    break;
                end
            end
            if any_activity and not any_recent then
                return;
            end
        end
    end

    -- Sample cumulative value for the rate sparkline.
    do
        local s = sess(M.active_tab);
        local now = now_s();
        if (now - (s.last_sample_s or 0)) >= SAMPLE_INTERVAL_S then
            s.last_sample_s = now;
            if s.samples == nil then s.samples = {}; end
            s.samples[#s.samples + 1] = { t = now, worth = M.get_total_worth(M.active_tab, pricing) };
            while #s.samples > SAMPLE_MAX do
                table.remove(s.samples, 1);
            end
        end
    end

    local x = settings.tracker.x[1];
    local y = settings.tracker.y[1];
    local pad = ui.get_padding(settings, 'tracker');
    local bg_draw_list = drawing.GetUIDrawList();
    local scale = ui.get_module_scale(settings, 'tracker');
    local transparent = ui.is_transparent_theme(settings);
    local accent = accent_of(M.active_tab, settings);

    -- Stored width + height (0 height = auto fit to content)
    if settings.tracker.width == nil then
        settings.tracker.width = T{ 320 };
    end
    if settings.tracker.height == nil then
        settings.tracker.height = T{ 0 };
    end
    local layout_w = settings.tracker.width[1] or 320;
    if layout_w < MIN_PANEL_W then layout_w = MIN_PANEL_W; end
    if layout_w > MAX_PANEL_W then layout_w = MAX_PANEL_W; end
    local layout_h = settings.tracker.height[1] or 0;
    if layout_h < 0 then layout_h = 0; end
    if layout_h > MAX_PANEL_H then layout_h = MAX_PANEL_H; end
    -- A height saved on one tab can be shorter than another tab's floor, and
    -- toggling rows on in the config moves the floor under a saved height too.
    -- Draw at the floor rather than clipping; the saved value is left alone so
    -- it comes back the moment there is room for it again.
    if layout_h > 0 then
        local min_h = M.min_panel_height(M.active_tab);
        if layout_h < min_h then layout_h = min_h; end
    end
    M.layout_w = layout_w;
    M.layout_h = layout_h;

    local draw_h = layout_h;
    if draw_h <= 0 then
        draw_h = M.last_size.h or 240;
    end
    ui.draw_panel_background(bg_draw_list, x, y, layout_w, draw_h, settings, 'tracker');

    -- Accent hairline along the top edge of the panel.
    if not transparent and bg_draw_list ~= nil then
        vis.rect(bg_draw_list, x - pad + 2, y - pad, layout_w + (pad * 2) - 4, 2, vis.alpha(accent, 0.75), 1);
    end

    imgui.SetNextWindowBgAlpha(0);
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    if layout_h > 0 then
        imgui.SetNextWindowSize({ layout_w, layout_h }, ImGuiCond_Always);
    else
        imgui.SetNextWindowSize({ layout_w, 0 }, ImGuiCond_Always);
    end

    if imgui.Begin('FloosTracker##Display', ui.get_panel_open('tracker'), ui.get_panel_flags()) then
        local scale_tag = fonts.begin_scale(scale);
        local content_w = layout_w - (pad * 2);
        if content_w < 120 then content_w = 120; end
        imgui.SetCursorPos({ pad, pad });

        draw_top_tabs(scale, content_w, settings, detail_level(settings) == 'Mini');
        imgui.Dummy({ 0, 4 });
        draw_rule(pad, content_w, accent, transparent);

        draw_activity_body(M.active_tab, settings, pricing, pad, content_w, scale, transparent);

        -- Spacer so the grip never overlaps the last line.
        imgui.Dummy({ 0, RESIZE_GRIP });

        local content_bottom = num_or(imgui.GetCursorPosY(), 0);

        fonts.end_scale(scale_tag);

        local sw, sh = imgui.GetWindowSize();
        if type(sw) == 'table' then
            sh = tonumber(sw.y or sw[2]) or M.last_size.h;
            sw = tonumber(sw.x or sw[1]) or layout_w;
        else
            sw = tonumber(sw) or layout_w;
            sh = tonumber(sh) or M.last_size.h;
        end

        ----------------------------------------------------------------
        -- Book-keeping for the next frame's haul budget. On an auto-height
        -- frame the window tells us exactly how much slack sits below the
        -- last item; that calibration then holds while the height is
        -- locked. Chrome is whatever the body needed minus what the haul
        -- was handed, so it does not move when the haul does.
        ----------------------------------------------------------------
        if layout_h <= 0 then
            local extra = (tonumber(sh) or 0) - content_bottom;
            if extra >= 0 and extra < 64 then
                M.win_pad_y = extra;
            end
        end
        do
            local hm = haul_metrics(M.active_tab);
            local needed = content_bottom + (M.win_pad_y or 8);
            local chrome = needed - (hm.used or 0);
            if chrome < 0 then chrome = 0; end
            hm.chrome = chrome;
        end

        if layout_h > 0 then
            sh = layout_h;
        end
        M.last_size.h = sh;
        M.last_size.w = layout_w;

        ----------------------------------------------------------------
        -- Bottom-right resize grip (width AND height).
        -- Double-click it to go back to auto height.
        ----------------------------------------------------------------
        local win_x, win_y = imgui.GetWindowPos();
        if type(win_x) == 'table' then
            win_y = win_x.y or win_x[2] or y;
            win_x = win_x.x or win_x[1] or x;
        end
        win_x = tonumber(win_x) or x;
        win_y = tonumber(win_y) or y;

        local mouse_x, mouse_y = imgui.GetMousePos();
        if type(mouse_x) == 'table' then
            mouse_y = mouse_x.y or mouse_x[2] or 0;
            mouse_x = mouse_x.x or mouse_x[1] or 0;
        end
        mouse_x = tonumber(mouse_x) or 0;
        mouse_y = tonumber(mouse_y) or 0;

        local grip_x1 = win_x + layout_w - RESIZE_GRIP;
        local grip_y1 = win_y + sh - RESIZE_GRIP;
        local grip_x2 = win_x + layout_w;
        local grip_y2 = win_y + sh;

        local over_grip = mouse_x >= grip_x1 and mouse_x <= grip_x2
            and mouse_y >= grip_y1 and mouse_y <= grip_y2;

        local dl = draw_list();
        if dl ~= nil then
            local alpha = (over_grip or M.resize ~= nil) and 0.95 or 0.45;
            local col = vis.alpha(accent, alpha);
            vis.line(dl, grip_x2 - 3, grip_y2 - 12, grip_x2 - 12, grip_y2 - 3, col, 1.5);
            vis.line(dl, grip_x2 - 3, grip_y2 - 9, grip_x2 - 9, grip_y2 - 3, col, 1.5);
            vis.line(dl, grip_x2 - 3, grip_y2 - 6, grip_x2 - 6, grip_y2 - 3, col, 1.5);
        end

        -- Double-click the grip: release the locked height.
        if over_grip and imgui.IsMouseDoubleClicked ~= nil then
            local dbl = false;
            pcall(function()
                dbl = imgui.IsMouseDoubleClicked(0);
            end);
            if dbl then
                settings.tracker.height[1] = 0;
                M.resize = nil;
                -- Do not let the second click of the double-click re-lock height.
                M.block_resize = true;
                settings_lib.save();
            end
        end

        if M.block_resize and not imgui.IsMouseDown(0) then
            M.block_resize = false;
        end

        if over_grip and imgui.IsMouseClicked(0) and M.resize == nil and not M.block_resize then
            local busy = false;
            if imgui.IsAnyItemActive ~= nil then busy = imgui.IsAnyItemActive(); end
            if not busy then
                M.resize = {
                    start_mouse_x = mouse_x,
                    start_mouse_y = mouse_y,
                    start_w = layout_w,
                    start_h = sh,
                };
            end
        end

        if M.resize ~= nil then
            if imgui.IsMouseDown(0) then
                local new_w = M.resize.start_w + (mouse_x - M.resize.start_mouse_x);
                local new_h = M.resize.start_h + (mouse_y - M.resize.start_mouse_y);
                if new_w < MIN_PANEL_W then new_w = MIN_PANEL_W; end
                if new_w > MAX_PANEL_W then new_w = MAX_PANEL_W; end
                -- Hard stop: the haul is down to its last two rows and there
                -- is nothing else left to give.
                local min_h = M.min_panel_height(M.active_tab);
                if new_h < min_h then new_h = min_h; end
                if new_h > MAX_PANEL_H then new_h = MAX_PANEL_H; end
                new_w = math.floor(new_w + 0.5);
                new_h = math.floor(new_h + 0.5);
                settings.tracker.width[1] = new_w;
                settings.tracker.height[1] = new_h;
                M.layout_w = new_w;
                M.last_size.h = new_h;
            else
                M.resize = nil;
                settings_lib.save();
            end
        end

        if M.resize == nil then
            ui.draw_panel_drag('tracker', settings.tracker.x, settings.tracker.y, layout_w, sh);
        end
    end
    imgui.End();
end

return M;
