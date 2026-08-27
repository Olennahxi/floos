--[[
* Floos - Settings + config editor
* UI layout adapted from XIUI (GPLv3).
]]--

require('common');
local chat = require('chat');
local imgui = require('imgui');
local settings = require('settings');
local theme = require('libs.theme');
local ui = require('libs.ui');
local fonts = require('libs.fonts');
local attribution = require('libs.attribution');

local M = {};

M.editor_open = T{ false };
M.pricing = T{};

M.default_settings = T{
    font_size = T{ 13 },
    reset_on_load = T{ false },
    panels_hidden = T{ false },
    layout_version = T{ 170 },
    psxi_token = T{ '' },   -- optional psxi.gg API token for /floos prices fetch
    lifetime = T{
        gil_gained = T{ 0 }, -- overall history; never cleared by session reset
        skill_w = T{ 0 },
        skill_m = T{ 0 },
        skill_b = T{ 0 },
        wins = T{ 0 },
        misses = T{ 0 },
        break_only = T{ 0 },
    },
    item_index = T{
        'chunk of iron ore:650',
        'chunk of copper ore:123',
        'chunk of zinc ore:166',
        'chunk of tin ore:123',
        'chunk of silver ore:0',
        'chunk of darksteel ore:6000',
        'chunk of gold ore:3000',
        'chunk of mythril ore:800',
        'chunk of platinum ore:5000',
        'pebble:123',
        'flint stone:123',
        'red rock:123',
        'white rock:123',
        'black rock:123',
        'blue rock:123',
        'green rock:123',
        'yellow rock:123',
        'purple rock:123',
        'translucent rock:123',
        'bundle of lumber:200',
        'arrowwood log:50',
        'maple log:80',
        'ash log:100',
        'walnut log:150',
        'elm log:200',
        'oak log:300',
        'rosewood log:500',
        'mahogany log:800',
        'fresh leaves:50',
        -- Harvesting. Every item on the wiki's Harvesting category, keyed by
        -- the name the chat log uses, which is what the tracker reads. Prices
        -- are 0 until you fill them: /floos prices fetch pulls live ones.
        'ball of saruta cotton:100',
        'flax flower:150',
        'clump of moko grass:80',
        'clump of red moko grass:0',
        'clump of beaugreens:0',
        'clump of imperial tea leaves:0',
        'clump of mohbwa grass:0',
        'clump of windurstian tea leaves:0',
        'clump of wolf fur:0',
        'bag of coffee cherries:0',
        'bag of grain seeds:0',
        'bag of herb seeds:0',
        'bag of simsim:0',
        'bag of vegetable seeds:0',
        "sprig of dyer's woad:0",
        'sprig of fresh marjoram:0',
        'sprig of fresh mugwort:0',
        'sprig of mistletoe:0',
        'sprig of sage:0',
        'piece of crawler cocoon:0',
        'piece of raw wool:0',
        'pod of blue peas:0',
        'pot of honey:0',
        'jar of toad oil:0',
        'spool of malboro fiber:0',
        'beehive chip:0',
        'pephredo hive chip:0',
        'cattleya:0',
        'phalaenopsis:0',
        'wijnruit:0',
        'eastern ginger root:0',
        'eggplant:0',
        'frost turnip:0',
        'popoto:0',
        'wild onion:0',
        'insect wing:0',
        'king locust:0',
        'mushroom locust:0',
        'skull locust:0',
        'spider web:0',
        'coral fungus:0',
        'scream fungus:0',
        'sobbing fungus:0',
        'danceshroom:0',
        'sleepshroom:0',
        'woozyshroom:0',
        'puffball:0',
        'reishi mushroom:0',
        -- Clamming (Bibiki Bay). Rough Horizon values; edit to taste.
        'piece of oxblood:13250',
        'tropical clam:5100',
        'lacquer tree log:3578',
        'high-quality crab shell:3312',
        'petrified log:2193',
        'coral fragment:1735',
        'uragnite shell:1455',
        'turtle shell:1190',
        'bibiki urchin:750',
        'crab shell:392',
        'titanictus shell:357',
        'shall shell:307',
        'handful of high-quality pugil scales:253',
        'sack of white sand:250',
        'vongola clam:192',
        'hobgoblin pie:153',
        'loaf of hobgoblin bread:91',
        'nebimonite:53',
        'jacknife:38',
        'seashell:29',
        'handful of pugil scales:23',
        'handful of fish scales:23',
        'bibiki slug:7',
        'clump of pamtam kelp:7',
        'broken willow fishing rod:0',
        'suit of goblin armor:0',
        'suit of goblin mail:0',
        'goblin mask:0',
    },
    mining = T{
        pickaxe_cost = T{ 120 },
        pickaxe_subtract = T{ false },
        skillup_display = T{ true },
        mine_skill = T{ 0 },
        fatigue_cap = T{ 200 },
        session_active = T{ 0 },
        last_mine = T{ 0 },
    },
    logging = T{
        hatchet_cost = T{ 300 },
        hatchet_subtract = T{ false },
        skillup_display = T{ true },
        log_skill = T{ 0 },
        fatigue_cap = T{ 200 },
    },
    harvest = T{
        sickle_cost = T{ 400 },
        sickle_subtract = T{ false },
        skillup_display = T{ true },
        harvest_skill = T{ 0 },
        fatigue_cap = T{ 200 },
    },
    excavate = T{
        skillup_display = T{ true },
        exca_skill = T{ 0 },
        fatigue_cap = T{ 200 },
    },
    fishing = T{
        idle_grace = T{ 60 },      -- clock freezes this long after each action
        bait_cost = T{ 0 },        -- gil per bait; Horizon spends one per BITE
        bait_subtract = T{ false },
        skillup_display = T{ true },
        fish_skill = T{ 0 },
    },
    digging = T{
        idle_grace = T{ 10 },      -- clock freezes this long after each dig
        green_cost = T{ 0 },       -- gil per bunch of Gysahl Greens
        green_subtract = T{ false },
        skillup_display = T{ true },
        dig_skill = T{ 0 },        -- rank IS skill/10, so there is no rank setting
        ore_watch = T{ true },     -- show the elemental ore condition row
    },
    clamming = T{
        idle_grace = T{ 15 },      -- clamming points come back about every 10s
        kit_cost = T{ 500 },       -- a kit from Toh Zonikki; the first is free
        kit_subtract = T{ true },
        hq_body = T{ false },      -- HQ swimwear halves the 200pz incident rate
        dig_delay = T{ 10 },       -- per-point cooldown, measured from the find
    },
    --- Which activity tabs appear on the panel. Eight will not fit a 340px
    --- window; switching one off only hides the tab, it keeps tracking.
    tabs = T{
        mining = T{ true },
        logging = T{ true },
        harvest = T{ true },
        excavate = T{ true },
        hunting = T{ true },
        fishing = T{ true },
        digging = T{ true },
        clamming = T{ true },
    },
    fatigue = T{
        observations = T{},        -- epochs of resets we actually witnessed
        period_hours = T{ 24 },
        last_seen = T{ 0 },
    },
    journal = T{
        enabled = T{ true },
    },
    hunt = T{
        respawn_sec = T{ 345 }, -- 5 min 45 sec from death
        track_list = T{},       -- only these mob names get respawn timers
    },
    helm = T{},
    session = T{
        swings = T{ 0 },
        breaks = T{ 0 },
        items = T{ 0 },
        skill_gain = T{ 0 },
        rewards = T{},
    },
    tracker = T{
        visible = T{ true },
        x = T{ 120 },
        y = T{ 120 },
        width = T{ 340 },
        height = T{ 0 },
        display_timeout = T{ 600 },
        never_hide = T{ false },
        show_duration = T{ true },
        show_controls = T{ false },
        show_moon = T{ true },
        show_fatigue = T{ true },
        show_zone_verdict = T{ true },
        verdict_metric = T{ 'Gil' },   -- Gil | Skill
        show_best_for = T{ true },
    },
    ui = T{
        background_theme = T{ 'DarkGold' },
        font_family = T{ 'Tahoma Bold (Default)' },
        accent_by_activity = T{ true },
        text_style = T{ 'Shadow' },
        show_bars = T{ true },
        show_strip = T{ true },
        show_sparkline = T{ true },
        animations = T{ true },
        expert = T{ true },     -- labeled rules, 10m trend, meter graduations
        detail = T{ 'Full' },   -- Full | Compact | Mini
        compact = T{ false },   -- legacy mirror of detail == 'Compact'
        tracker = T{
            scale = T{ 1.0 },
            padding = T{ 8 },
            bg_scale = T{ 1.0 },
            border_scale = T{ 1.0 },
            background_opacity = T{ 0.72 },
            border_opacity = T{ 0.9 },
            border_thickness = T{ 0 },
            panel_rounding = T{ 8 },
            show_duration = T{ true },
            show_controls = T{ false },
        },
        background_gradient_start = T{ '#01122b' },
        background_gradient_end = T{ '#061c39' },
    },
};

M.settings = settings.load(M.default_settings);

--- Set by floos.lua. The settings library swaps the whole settings table when
--- you log out or in - every module holding a reference to the old table must
--- be rebound to the new one, or their writes land in a dead table and are
--- never saved. That was the "it has no memory" bug: play after a relog wrote
--- all session progress into the orphaned pre-login table.
M.on_settings_change = nil;

settings.register('settings', 'settings_update', function (s)
    if s ~= nil then
        M.settings = s;
    end
    M.ensure_ui_settings();
    if M.on_settings_change ~= nil then
        M.on_settings_change();
    end
    settings.save();
    M.update_pricing();
end);

local function split(inputstr, sep)
    sep = sep or '%s';
    local t = {};
    for str in string.gmatch(inputstr, '([^' .. sep .. ']+)') do
        table.insert(t, str);
    end
    return t;
end

local function fill_height(min_h)
    local avail = imgui.GetContentRegionAvail();
    local h = 0;
    if type(avail) == 'table' then
        h = tonumber(avail.y or avail[2]) or 0;
    else
        local _, ay = imgui.GetContentRegionAvail();
        h = tonumber(ay) or 0;
    end
    if h < min_h then
        return min_h;
    end
    return h;
end

function M.ensure_ui_settings()
    if M.settings.font_size == nil then
        M.settings.font_size = T{ 13 };
    end
    local size = tonumber(M.settings.font_size[1]) or 13;
    if size < 6 then size = 6; end
    if size > 30 then size = 30; end
    M.settings.font_size[1] = math.floor(size + 0.5);

    if M.settings.panels_hidden == nil then
        M.settings.panels_hidden = T{ false };
    end
    if M.settings.ui == nil then
        M.settings.ui = M.default_settings.ui:copy();
    end
    if M.settings.ui.font_family == nil then
        M.settings.ui.font_family = T{ 'Tahoma Bold (Default)' };
    end
    if M.settings.ui.background_theme == nil
        or M.settings.ui.background_theme[1] == 'Transparent'
        or M.settings.ui.background_theme[1] == 'Window1'
        or M.settings.ui.background_theme[1] == '' then
        M.settings.ui.background_theme = T{ 'DarkGold' };
    end
    -- Presentation flags added in 1.7.0.
    local function ensure_flag(tbl, key, value)
        if tbl[key] == nil then
            tbl[key] = T{ value };
        end
    end

    ensure_flag(M.settings.ui, 'accent_by_activity', true);
    ensure_flag(M.settings.ui, 'text_style', 'Shadow');
    ensure_flag(M.settings.ui, 'show_bars', true);
    ensure_flag(M.settings.ui, 'show_strip', true);
    ensure_flag(M.settings.ui, 'show_sparkline', true);
    ensure_flag(M.settings.ui, 'animations', true);
    ensure_flag(M.settings.ui, 'expert', true);
    ensure_flag(M.settings.ui, 'compact', false);

    -- 1.7.3: the compact boolean became a three-level detail setting.
    ensure_flag(M.settings.ui, 'detail', nil);
    local lvl = M.settings.ui.detail[1];
    if lvl ~= 'Full' and lvl ~= 'Compact' and lvl ~= 'Mini' then
        lvl = M.settings.ui.compact[1] and 'Compact' or 'Full';
        M.settings.ui.detail[1] = lvl;
    end
    M.settings.ui.compact[1] = (lvl == 'Compact');

    if M.settings.ui.text_style[1] ~= 'Shadow'
        and M.settings.ui.text_style[1] ~= 'Outline'
        and M.settings.ui.text_style[1] ~= 'None' then
        M.settings.ui.text_style[1] = 'Shadow';
    end

    if M.settings.ui.tracker == nil then
        M.settings.ui.tracker = M.default_settings.ui.tracker:copy();
    end
    local tui = M.settings.ui.tracker;
    if tui.scale == nil then tui.scale = T{ 1.0 }; end
    if tui.padding == nil then tui.padding = T{ 8 }; end
    if tui.background_opacity == nil then tui.background_opacity = T{ 0.72 }; end
    if tui.border_opacity == nil then tui.border_opacity = T{ 0.9 }; end
    if tui.border_thickness == nil then tui.border_thickness = T{ 0 }; end
    if tui.panel_rounding == nil then tui.panel_rounding = T{ 8 }; end
    if tui.show_duration == nil then tui.show_duration = T{ true }; end
    if tui.show_controls == nil then tui.show_controls = T{ false }; end

    if M.settings.tracker == nil then
        M.settings.tracker = M.default_settings.tracker:copy();
    end
    if M.settings.tracker.never_hide == nil then
        M.settings.tracker.never_hide = T{ false };
    end
    if M.settings.tracker.width == nil then
        M.settings.tracker.width = T{ 340 };
    end
    -- Renderer clamps to 320; keep the stored value in the same range.
    if M.settings.tracker.width[1] < 320 then
        M.settings.tracker.width[1] = 320;
    end
    if M.settings.tracker.width[1] > 600 then
        M.settings.tracker.width[1] = 600;
    end
    if M.settings.tracker.height == nil then
        M.settings.tracker.height = T{ 0 };
    end
    if M.settings.tracker.height[1] < 0 then
        M.settings.tracker.height[1] = 0;
    end
    if M.settings.tracker.height[1] > 900 then
        M.settings.tracker.height[1] = 900;
    end
    if M.settings.tracker.show_duration == nil then
        M.settings.tracker.show_duration = T{ tui.show_duration[1] };
    end
    if M.settings.tracker.show_controls == nil then
        M.settings.tracker.show_controls = T{ tui.show_controls[1] };
    end
    if M.settings.tracker.show_fatigue == nil then
        M.settings.tracker.show_fatigue = T{ true };
    end
    if M.settings.tracker.show_zone_verdict == nil then
        M.settings.tracker.show_zone_verdict = T{ true };
    end
    if M.settings.tracker.show_best_for == nil then
        M.settings.tracker.show_best_for = T{ true };
    end
    if M.settings.fatigue == nil then
        M.settings.fatigue = M.default_settings.fatigue:copy();
    end
    if M.settings.fatigue.observations == nil then
        M.settings.fatigue.observations = T{};
    end
    if M.settings.fatigue.period_hours == nil then
        M.settings.fatigue.period_hours = T{ 24 };
    end
    if (tonumber(M.settings.fatigue.period_hours[1]) or 0) <= 0 then
        M.settings.fatigue.period_hours[1] = 24;
    end
    if M.settings.fatigue.last_seen == nil then
        M.settings.fatigue.last_seen = T{ 0 };
    end
    if M.settings.journal == nil then
        M.settings.journal = T{ enabled = T{ true } };
    end
    if M.settings.journal.enabled == nil then
        M.settings.journal.enabled = T{ true };
    end
    if M.settings.tracker.verdict_metric == nil then
        M.settings.tracker.verdict_metric = T{ 'Gil' };
    end
    if M.settings.tracker.verdict_metric[1] ~= 'Gil'
        and M.settings.tracker.verdict_metric[1] ~= 'Skill' then
        M.settings.tracker.verdict_metric[1] = 'Gil';
    end

    -- One-time 1.7.0 layout migration: the panel auto-fits now, so drop any
    -- height locked in by the old resize grip and widen narrow panels.
    if M.settings.layout_version == nil then
        M.settings.layout_version = T{ 0 };
    end
    if (tonumber(M.settings.layout_version[1]) or 0) < 170 then
        M.settings.layout_version[1] = 170;
        M.settings.tracker.height[1] = 0;
        if M.settings.tracker.width[1] < 340 then
            M.settings.tracker.width[1] = 340;
        end
    end
    if M.settings.tracker.show_moon == nil then
        M.settings.tracker.show_moon = T{ true };
    end

    if M.settings.mining == nil then
        M.settings.mining = M.default_settings.mining:copy();
    end
    if M.settings.mining.session_active == nil then
        M.settings.mining.session_active = T{ 0 };
    end
    if M.settings.mining.last_mine == nil then
        M.settings.mining.last_mine = T{ 0 };
    end
    if M.settings.logging == nil then
        M.settings.logging = M.default_settings.logging:copy();
    end
    if M.settings.logging.log_skill == nil then
        M.settings.logging.log_skill = T{ 0 };
    end
    if M.settings.logging.fatigue_cap == nil then
        M.settings.logging.fatigue_cap = T{ 200 };
    end
    if M.settings.harvest == nil then
        M.settings.harvest = M.default_settings.harvest:copy();
    end
    if M.settings.harvest.fatigue_cap == nil then
        M.settings.harvest.fatigue_cap = T{ 200 };
    end
    if M.settings.harvest.harvest_skill == nil then
        M.settings.harvest.harvest_skill = T{ 0 };
    end
    if M.settings.harvest.skillup_display == nil then
        M.settings.harvest.skillup_display = T{ true };
    end
    if M.settings.excavate == nil then
        M.settings.excavate = T{ fatigue_cap = T{ 200 } };
    end
    if M.settings.fishing == nil then
        M.settings.fishing = M.default_settings.fishing:copy();
    end
    if M.settings.digging == nil then
        M.settings.digging = M.default_settings.digging:copy();
    end
    if M.settings.clamming == nil then
        M.settings.clamming = M.default_settings.clamming:copy();
    end
    if M.settings.tabs == nil then
        M.settings.tabs = M.default_settings.tabs:copy();
    end
    for _, pair in ipairs({
        { 'fishing', 'idle_grace', 60 }, { 'digging', 'idle_grace', 10 },
        { 'fishing', 'bait_cost', 0 },   { 'fishing', 'bait_subtract', false },
        { 'fishing', 'skillup_display', true }, { 'fishing', 'fish_skill', 0 },
        { 'digging', 'green_cost', 0 },  { 'digging', 'green_subtract', false },
        { 'digging', 'skillup_display', true }, { 'digging', 'dig_skill', 0 },
        { 'digging', 'ore_watch', true },
        { 'clamming', 'idle_grace', 15 }, { 'clamming', 'kit_cost', 500 },
        { 'clamming', 'kit_subtract', true }, { 'clamming', 'hq_body', false },
        { 'clamming', 'dig_delay', 10 },
        { 'tabs', 'mining', true },   { 'tabs', 'logging', true },
        { 'tabs', 'harvest', true },  { 'tabs', 'excavate', true },
        { 'tabs', 'hunting', true },  { 'tabs', 'fishing', true },
        { 'tabs', 'digging', true },  { 'tabs', 'clamming', true },
    }) do
        local grp = M.settings[pair[1]];
        if grp ~= nil and grp[pair[2]] == nil then
            grp[pair[2]] = T{ pair[3] };
        end
    end
    if M.settings.excavate.fatigue_cap == nil then
        M.settings.excavate.fatigue_cap = T{ 200 };
    end
    if M.settings.excavate.exca_skill == nil then
        M.settings.excavate.exca_skill = T{ 0 };
    end
    if M.settings.excavate.skillup_display == nil then
        M.settings.excavate.skillup_display = T{ true };
    end
    if M.settings.hunt == nil then
        M.settings.hunt = T{ respawn_sec = T{ 345 } };
    end
    if M.settings.hunt.respawn_sec == nil then
        M.settings.hunt.respawn_sec = T{ 345 };
    end
    if M.settings.hunt.track_list == nil then
        M.settings.hunt.track_list = T{};
    end
    if M.settings.helm == nil then
        M.settings.helm = T{};
    end
    if M.settings.session == nil then
        M.settings.session = M.default_settings.session:copy();
    end
    if M.settings.lifetime == nil then
        M.settings.lifetime = T{ gil_gained = T{ 0 } };
    end
    if M.settings.lifetime.gil_gained == nil then
        M.settings.lifetime.gil_gained = T{ 0 };
    end
    if M.settings.item_index == nil then
        M.settings.item_index = M.default_settings.item_index:copy();
    end
    if M.settings.psxi_token == nil then
        M.settings.psxi_token = T{ '' };
    end
end

function M.panels_are_shown()
    if M.settings.panels_hidden ~= nil and M.settings.panels_hidden[1] then
        return false;
    end
    return true;
end

function M.update_pricing()
    M.pricing = T{};
    for _, line in pairs(M.settings.item_index) do
        local parts = split(line, ':');
        if parts[1] ~= nil then
            local name = string.lower((parts[1]:match('^%s*(.-)%s*$')) or '');
            local price = tonumber(parts[2]) or 0;
            if name ~= '' then
                M.pricing[name] = price;
            end
        end
    end
end

--- Merge `name:price` lines into the price list: existing names are updated in
--- place, new names appended, anything unparseable is skipped and counted.
--- This is how a price file generated outside the game (for example by the
--- psxi market tool) gets in without retyping thirty prices by hand.
function M.merge_prices(lines)
    local updated, added, skipped = 0, 0, 0;

    -- Index the current list by normalized name.
    local index = {};
    for i, line in ipairs(M.settings.item_index) do
        local name = split(line, ':')[1];
        if name ~= nil then
            index[string.lower(name:match('^%s*(.-)%s*$') or '')] = i;
        end
    end

    for _, raw in ipairs(lines) do
        local line = tostring(raw or ''):gsub('[\r\n]', '');
        local name, price = line:match('^%s*(.-)%s*:%s*(-?%d+)%s*$');
        if name ~= nil and name ~= '' and tonumber(price) ~= nil
            and tonumber(price) >= 0 then
            local key = string.lower(name);
            local entry = name .. ':' .. price;
            if index[key] ~= nil then
                M.settings.item_index[index[key]] = entry;
                updated = updated + 1;
            else
                M.settings.item_index[#M.settings.item_index + 1] = entry;
                index[key] = #M.settings.item_index;
                added = added + 1;
            end
        elseif line:match('%S') then
            skipped = skipped + 1;
        end
    end

    M.update_pricing();
    return updated, added, skipped;
end

--- Pull live market prices from psxi.gg and merge them into the price list.
---
--- The keyless snapshot endpoint returns every scanned item on the server, so
--- there is nothing to look up by hand: one request, then only the names
--- already in the price list are updated. Nothing new is ever added - a 4000
--- item price list would be unreadable, and the point is to price what you
--- actually gather.
---
--- psxi names items the way the auction house does ("Moko Grass"); the price
--- list is keyed by the name the chat log uses ("clump of moko grass"), so
--- each row is offered under both, resolved through Ashita's item resources.
---
--- This blocks until the request finishes, which is a second or two on a 2MB
--- body. It is a typed command, not a frame hook, so a brief hitch is the
--- honest trade against a threading layer.
--- ponytail: synchronous fetch on the render thread; move to a coroutine only
--- if this ever runs on a timer instead of on demand.
local PSXI_URL = 'https://www.psxi.gg/api/v1/market/horizonxi';

function M.fetch_prices(token)
    local ok_https, https = pcall(require, 'socket.ssl.https');
    local ok_ltn12, ltn12 = pcall(require, 'socket.ltn12');
    local ok_json, json = pcall(require, 'json');
    if not (ok_https and ok_ltn12 and ok_json) then
        return nil, "LuaSocket/LuaSec is missing from Ashita's addons/libs.";
    end

    local headers = { ['accept'] = 'application/json' };
    if token ~= nil and token ~= '' then
        headers['authorization'] = 'Bearer ' .. token;
    end

    local body = {};
    local _, code = https.request({
        url = PSXI_URL,
        headers = headers,
        sink = ltn12.sink.table(body),
    });
    if code ~= 200 then
        return nil, string.format('psxi.gg returned %s.', tostring(code));
    end

    local ok, doc = pcall(json.decode, table.concat(body));
    if not ok or type(doc) ~= 'table' or type(doc.data) ~= 'table' then
        return nil, 'psxi.gg sent something this cannot read.';
    end

    -- Only names already on the list are worth resolving.
    local want = {};
    for _, line in ipairs(M.settings.item_index) do
        local name = split(line, ':')[1];
        if name ~= nil then
            want[string.lower(name:match('^%s*(.-)%s*$') or '')] = true;
        end
    end

    local res = nil;
    pcall(function () res = AshitaCore:GetResourceManager(); end);

    local lines = {};
    for _, row in ipairs(doc.data) do
        local price = nil;
        if type(row.ah) == 'table' and type(row.ah.single) == 'table' then
            -- 7-day mean of single-item sales, which is what a session of
            -- gathering actually clears; lastSale is one data point and the
            -- bazaar is asking prices, so both are only fallbacks.
            price = row.ah.single.avg or row.ah.single.lastSale;
        end
        if price == nil and type(row.bazaar) == 'table' then
            price = row.bazaar.avg;
        end
        if type(price) == 'number' and price > 0 then
            local names = { row.itemName };
            if res ~= nil and row.itemId ~= nil then
                pcall(function ()
                    local item = res:GetItemById(row.itemId);
                    if item ~= nil and item.LogNameSingular ~= nil then
                        for _, lang in ipairs({ 1, 2, 0 }) do
                            local log = item.LogNameSingular[lang];
                            if type(log) == 'string' and log ~= '' then
                                names[#names + 1] = log;
                                break;
                            end
                        end
                    end
                end);
            end
            for _, name in ipairs(names) do
                if type(name) == 'string' and want[string.lower(name)] then
                    lines[#lines + 1] = string.format('%s:%d', name,
                        math.floor(price + 0.5));
                end
            end
        end
    end

    local updated = M.merge_prices(lines);
    return updated, doc.meta and doc.meta.generatedAt or nil;
end

--- Where the import looks when given a bare filename.
function M.prices_dir()
    local ok, p = pcall(function ()
        return AshitaCore:GetInstallPath();
    end);
    if ok and p ~= nil and p ~= '' then
        return (tostring(p):gsub('[/\\]+$', '')) .. '/config/addons/floos';
    end
    return '.';
end


local function render_general()
    imgui.Text('Modules');
    ui.begin_child('floos_modules', { 0, 90 }, true);
    imgui.Checkbox('Session Tracker', M.settings.tracker.visible);
    imgui.Checkbox('Reset Session On Load', M.settings.reset_on_load);
    ui.end_child();

    imgui.Text('Fonts');
    ui.begin_child('floos_fonts', { 0, 100 }, true);
    if imgui.InputInt('Font Size', M.settings.font_size) then
        if M.settings.font_size[1] < 6 then M.settings.font_size[1] = 6; end
        if M.settings.font_size[1] > 30 then M.settings.font_size[1] = 30; end
    end
    if M.settings.ui.font_family == nil then
        M.settings.ui.font_family = T{ 'Tahoma Bold (Default)' };
    end
    fonts.render_combo(M.settings.ui.font_family);
    ui.end_child();
end

local function render_appearance()
    ui.begin_child('floos_appearance', { 0, fill_height(280) }, true);

    imgui.Text('Tabs On The Panel');
    imgui.TextDisabled('Eight tabs do not fit a narrow window. Untick the ones you');
    imgui.TextDisabled('do not use - they keep tracking, they just stop taking space.');
    do
        local TAB_ROWS = {
            { { 'mining', 'Mine' }, { 'logging', 'Logg' }, { 'harvest', 'Harv' }, { 'excavate', 'Exca' } },
            { { 'hunting', 'Hunt' }, { 'fishing', 'Fish' }, { 'digging', 'Dig' }, { 'clamming', 'Clam' } },
        };
        local shown = 0;
        for _, row in ipairs(TAB_ROWS) do
            for i, entry in ipairs(row) do
                local key, label = entry[1], entry[2];
                if M.settings.tabs[key] == nil then
                    M.settings.tabs[key] = T{ true };
                end
                imgui.Checkbox(label .. '##tab_' .. key, M.settings.tabs[key]);
                if M.settings.tabs[key][1] then shown = shown + 1; end
                if i < #row then imgui.SameLine(); end
            end
            imgui.NewLine();
        end
        -- Zero tabs is a broken panel, not a preference. Put one back.
        if shown == 0 then
            M.settings.tabs.mining[1] = true;
            imgui.TextDisabled('At least one tab has to stay on - Mine was put back.');
        end
    end

    imgui.Separator();
    imgui.Text('Window Theme');
    local themes = theme.THEME_OPTIONS;
    local current_theme = M.settings.ui.background_theme[1];
    for _, entry in ipairs(themes) do
        if imgui.RadioButton(entry.label, current_theme == entry.id) then
            M.settings.ui.background_theme[1] = entry.id;
        end
        imgui.SameLine();
    end
    imgui.NewLine();

    imgui.Text('Text Edge');
    local styles = { 'Shadow', 'Outline', 'None' };
    for _, name in ipairs(styles) do
        if imgui.RadioButton(name .. '##textstyle', M.settings.ui.text_style[1] == name) then
            M.settings.ui.text_style[1] = name;
        end
        imgui.SameLine();
    end
    imgui.NewLine();

    imgui.Separator();
    imgui.Text('Display');
    imgui.Checkbox('Accent Color Per Activity', M.settings.ui.accent_by_activity);
    imgui.Checkbox('Progress Bars', M.settings.ui.show_bars);
    imgui.Checkbox('Swing History Strip', M.settings.ui.show_strip);
    imgui.Checkbox('Rate Sparkline', M.settings.ui.show_sparkline);
    imgui.Checkbox('Animations (flash / count-up)', M.settings.ui.animations);
    imgui.Checkbox('Expert visuals', M.settings.ui.expert);
    imgui.TextDisabled('Labeled section rules, last-10m rate trend, meter graduations.');
    imgui.Text('Detail Level');
    for _, level in ipairs({ 'Full', 'Compact', 'Mini' }) do
        if imgui.RadioButton(level .. '##detail', M.settings.ui.detail[1] == level) then
            M.settings.ui.detail[1] = level;
            M.settings.ui.compact[1] = (level == 'Compact');
            M.settings.tracker.height[1] = 0;
        end
        imgui.SameLine();
    end
    imgui.NewLine();
    imgui.TextDisabled('Full: everything. Compact: no drop list or footer.');
    imgui.TextDisabled('Mini: rate, fatigue, tools, gil. Five lines.');
    imgui.Checkbox('Zone Stay/Move Verdict', M.settings.tracker.show_zone_verdict);
    imgui.Text('Judge zones by');
    for _, metric in ipairs({ 'Gil', 'Skill' }) do
        if imgui.RadioButton(metric .. '/hr##verdict', M.settings.tracker.verdict_metric[1] == metric) then
            M.settings.tracker.verdict_metric[1] = metric;
        end
        imgui.SameLine();
    end
    imgui.NewLine();

    imgui.Separator();
    imgui.Text('Session Panel');
    local ms = M.settings.ui.tracker;
    imgui.SliderFloat('Scale', ms.scale, 0.50, 2.50, '%.2f');
    imgui.SliderFloat('Background Opacity', ms.background_opacity, 0.0, 1.0, '%.2f');
    imgui.SliderInt('Border Thickness', ms.border_thickness, 0, 6);
    imgui.SliderInt('Padding', ms.padding, 2, 20);
    imgui.SliderInt('Panel Rounding', ms.panel_rounding, 0, 16);

    imgui.Separator();
    imgui.Checkbox('Show Duration', ms.show_duration);
    M.settings.tracker.show_duration[1] = ms.show_duration[1];
    M.settings.tracker.show_controls[1] = false;
    ms.show_controls[1] = false;

    imgui.Checkbox('Show Fatigue', M.settings.tracker.show_fatigue);
    imgui.Checkbox('Show Moon Phase', M.settings.tracker.show_moon);
    imgui.Checkbox('Show Skill Line', M.settings.mining.skillup_display);
    ui.end_child();
end

local function render_mining()
    ui.begin_child('floos_mining', { 0, 320 }, true);
    imgui.Text('Mining');
    imgui.InputFloat('Mining Skill', M.settings.mining.mine_skill, 0.1, 0.1, '%.1f');
    imgui.InputInt('Mine Fatigue Cap', M.settings.mining.fatigue_cap);
    imgui.InputInt('Pickaxe Cost', M.settings.mining.pickaxe_cost);
    imgui.Checkbox('Subtract Pickaxe Breaks', M.settings.mining.pickaxe_subtract);
    imgui.TextDisabled('HELM fatigue is not a flat 200 and is not tied to your');
    imgui.TextDisabled('character level. Horizon scales it with your GATHERING rank');
    imgui.TextDisabled('and sets it per zone. The base numbers are unpublished, so');
    imgui.TextDisabled('these caps raise themselves whenever you gather past one.');

    imgui.Separator();
    imgui.Text('Logging');
    imgui.InputFloat('Logging Skill', M.settings.logging.log_skill, 0.1, 0.1, '%.1f');
    imgui.InputInt('Log Fatigue Cap', M.settings.logging.fatigue_cap);
    imgui.InputInt('Hatchet Cost', M.settings.logging.hatchet_cost);
    imgui.Checkbox('Subtract Hatchet Breaks', M.settings.logging.hatchet_subtract);
    imgui.Checkbox('Show Logging Skillups', M.settings.logging.skillup_display);

    imgui.Separator();
    imgui.Text('Harvesting');
    imgui.InputFloat('Harvesting Skill', M.settings.harvest.harvest_skill, 0.1, 0.1, '%.1f');
    imgui.InputInt('Harv Fatigue Cap', M.settings.harvest.fatigue_cap);
    imgui.InputInt('Sickle Cost', M.settings.harvest.sickle_cost);
    imgui.Checkbox('Subtract Sickle Breaks', M.settings.harvest.sickle_subtract);
    imgui.Checkbox('Show Harvesting Skillups', M.settings.harvest.skillup_display);

    imgui.Separator();
    imgui.Text('Excavation');
    imgui.InputFloat('Excavation Skill', M.settings.excavate.exca_skill, 0.1, 0.1, '%.1f');
    imgui.InputInt('Exca Fatigue Cap', M.settings.excavate.fatigue_cap);
    imgui.Checkbox('Show Excavation Skillups', M.settings.excavate.skillup_display);
    imgui.TextDisabled('Excavation uses the Pickaxe Cost set under Mining.');

    imgui.Separator();
    imgui.Text('Fishing');
    imgui.InputInt('Bait Cost', M.settings.fishing.bait_cost);
    if M.settings.fishing.bait_cost[1] < 0 then M.settings.fishing.bait_cost[1] = 0; end
    imgui.Checkbox('Subtract Bait Cost', M.settings.fishing.bait_subtract);
    imgui.TextDisabled('Bait is spent per BITE on Horizon, not per cast, so the');
    imgui.TextDisabled('bill follows bites. Casts that get no bite are free.');
    imgui.InputInt('Fishing Idle Grace (s)', M.settings.fishing.idle_grace);
    if M.settings.fishing.idle_grace[1] < 1 then M.settings.fishing.idle_grace[1] = 1; end
    imgui.TextDisabled('gil/hr clock freezes this long after each action.');
    imgui.Checkbox('Show Fishing Skillups', M.settings.fishing.skillup_display);
    imgui.TextDisabled('No fishing fatigue on Horizon - each water has a shared fish');
    imgui.TextDisabled('stock that refills at Vana hours 0, 4, 6, 7, 17, 18 and 20.');

    imgui.Separator();
    imgui.Text('Chocobo Digging');
    imgui.InputInt('Gysahl Greens Cost', M.settings.digging.green_cost);
    if M.settings.digging.green_cost[1] < 0 then M.settings.digging.green_cost[1] = 0; end
    imgui.Checkbox('Subtract Greens Cost', M.settings.digging.green_subtract);
    imgui.TextDisabled('A green is spent on every accepted dig, including the ones');
    imgui.TextDisabled('that find nothing. Only "wait longer" refusals are free.');
    imgui.InputFloat('Digging Skill', M.settings.digging.dig_skill, 0.1, 0.1, '%.1f');
    if M.settings.digging.dig_skill[1] < 0 then M.settings.digging.dig_skill[1] = 0; end
    if M.settings.digging.dig_skill[1] > 100 then M.settings.digging.dig_skill[1] = 100; end
    do
        local tracker = require('modules.tracker');
        local rank = tracker.dig_rank_from_skill(M.settings.digging.dig_skill[1]);
        local names = require('constants').DIG_RANKS or {};
        imgui.TextDisabled(string.format('Rank: %s (%d)   Daily item cap: %d',
            names[rank] or '?', rank, 100 + (rank * 10)));
    end
    imgui.TextDisabled('Rank is just skill divided by ten, same as a craft, so');
    imgui.TextDisabled('the addon works it out. Skill-ups keep this current.');
    imgui.InputInt('Digging Idle Grace (s)', M.settings.digging.idle_grace);
    if M.settings.digging.idle_grace[1] < 1 then M.settings.digging.idle_grace[1] = 1; end
    imgui.TextDisabled('gil/hr clock runs this long after each dig, then freezes');
    imgui.TextDisabled('until the next one. Stops AFK time diluting your rate.');
    imgui.Checkbox('Show Digging Skillups', M.settings.digging.skillup_display);
    imgui.Checkbox('Elemental Ore Watch', M.settings.digging.ore_watch);
    imgui.TextDisabled('Ore needs Craftsman+ rank, a 7-24 waxing crescent, an active');
    imgui.TextDisabled('weather (fog counts) and a non-Zilart zone. Ore element');
    imgui.TextDisabled('follows the Vana\'diel day. Weather is read straight out of');
    imgui.TextDisabled('the client, the same way the Vana\'diel clock already is.');


    imgui.Separator();
    imgui.Text('Clamming');
    imgui.InputInt('Clamming Kit Cost', M.settings.clamming.kit_cost);
    if M.settings.clamming.kit_cost[1] < 0 then M.settings.clamming.kit_cost[1] = 0; end
    imgui.Checkbox('Subtract Kit Cost', M.settings.clamming.kit_subtract);
    imgui.TextDisabled('500g per kit from Toh Zonikki - your first one is free.');
    imgui.Checkbox('HQ Swimwear Body', M.settings.clamming.hq_body);
    imgui.TextDisabled('The HQ body piece halves the chance of something jumping');
    imgui.TextDisabled('into a 200pz bucket, 10 percent down to 5. It changes the');
    imgui.TextDisabled('risk figure on the Clam tab, nothing else.');
    imgui.InputInt('Dig Cooldown (s)', M.settings.clamming.dig_delay);
    if M.settings.clamming.dig_delay[1] < 1 then M.settings.clamming.dig_delay[1] = 1; end
    imgui.TextDisabled('A clamming point is reusable 10s after your last dig on');
    imgui.TextDisabled('Horizon. The cooldown is per point, so hopping between two');
    imgui.TextDisabled('nearby points beats the timer. Clicking early is rejected');
    imgui.TextDisabled('and shows as "early" next to the dig count.');
    imgui.InputInt('Clamming Idle Grace (s)', M.settings.clamming.idle_grace);
    if M.settings.clamming.idle_grace[1] < 1 then M.settings.clamming.idle_grace[1] = 1; end
    imgui.TextDisabled('No skill, no rank, no daily cap on clamming - the bucket is');
    imgui.TextDisabled('the only limit, and it is all-or-nothing if you go over.');

    imgui.Separator();
    imgui.Text('Display');
    imgui.InputInt('Display Timeout (sec)', M.settings.tracker.display_timeout);
    imgui.Checkbox('Never Hide', M.settings.tracker.never_hide);
    ui.end_child();

    imgui.Text('psxi.gg Prices');
    if M.settings.psxi_token == nil then
        M.settings.psxi_token = T{ '' };
    end
    imgui.InputText('API Token', M.settings.psxi_token, 72);
    imgui.TextDisabled('Optional today, required from 2026-11-01. Generate one at');
    imgui.TextDisabled('psxi.gg - Settings - Account - API Access.');
    if imgui.Button('Fetch Prices Now') then
        -- Blocks for a second or two on a 2MB snapshot. Same call the
        -- /floos prices fetch command makes.
        local updated, info = M.fetch_prices(M.settings.psxi_token[1]);
        if updated == nil then
            M.psxi_status = tostring(info);
        else
            M.psxi_status = string.format('%d prices updated (snapshot %s).',
                updated, tostring(info));
        end
        settings.save();
    end
    imgui.SameLine();
    -- The default list grows with every wiki pass; a settings file saved
    -- before that keeps the old, shorter one forever. This is how you take
    -- the new list without deleting the rest of your settings. Prices you
    -- already entered for an item on the default list are carried over -
    -- the names are replaced, the work is not.
    if imgui.Button('Restore Default List') then
        local kept = {};
        for _, line in ipairs(M.settings.item_index) do
            local name, price = line:match('^%s*(.-)%s*:%s*(-?%d+)%s*$');
            if name ~= nil and tonumber(price) ~= nil and tonumber(price) > 0 then
                kept[string.lower(name)] = tonumber(price);
            end
        end
        local rebuilt = T{};
        for _, line in ipairs(M.default_settings.item_index) do
            local name = split(line, ':')[1];
            local price = kept[string.lower(name or '')];
            rebuilt[#rebuilt + 1] = price ~= nil
                and string.format('%s:%d', name, price) or line;
        end
        M.settings.item_index = rebuilt;
        M.update_pricing();
        settings.save();
        M.psxi_status = string.format('%d default items restored.',
            #M.settings.item_index);
    end
    if M.psxi_status ~= nil then
        imgui.TextDisabled(M.psxi_status);
    end

    imgui.Text('Item Prices (name:price, one per line)');
    local temp = T{ table.concat(M.settings.item_index, '\n') };
    if imgui.InputTextMultiline('##floos_prices', temp, 8192, { 0, fill_height(120) }) then
        M.settings.item_index = split(temp[1], '\n');
        M.update_pricing();
    end
end

local function render_data()
    local tracker = require('modules.tracker');
    local journal = require('libs.journal');

    ui.begin_child('floos_data_cfg', { 0, fill_height(320) }, true);

    imgui.Text('Fatigue reset schedule');
    imgui.TextDisabled('Learned by watching for the one thing that proves a reset:');
    imgui.TextDisabled('being at the cap, then gathering successfully anyway.');
    imgui.TextDisabled('This only predicts the next reset - it never clears your');
    imgui.TextDisabled('counters. Use /floos clear for that.');
    imgui.Spacing();

    local conf = tracker.fatigue_confidence();
    local left = tracker.fatigue_time_left();
    if left ~= nil then
        imgui.Text(string.format('Next reset in %s   (confidence: %s)',
            require('libs.format').format_duration(left), conf));
    else
        imgui.Text('No reset seen yet. Keep gathering past the cap and it will learn.');
    end

    local measured = require('libs.fatigue').measured_period_hours({
        observations = M.settings.fatigue.observations,
        period_hours = tonumber(M.settings.fatigue.period_hours[1]) or 24,
    });
    if measured ~= nil then
        imgui.TextDisabled(string.format('Observed gap between resets: %.1f hours', measured));
        if math.abs(measured - (tonumber(M.settings.fatigue.period_hours[1]) or 24)) > 0.5 then
            imgui.TextColored({ 1.0, 0.74, 0.30, 1.0 },
                'That does not match the period below. Consider changing it.');
        end
    end

    imgui.InputInt('Period (hours)', M.settings.fatigue.period_hours);
    if M.settings.fatigue.period_hours[1] < 1 then
        M.settings.fatigue.period_hours[1] = 1;
    end
    imgui.TextDisabled(string.format('%d reset(s) recorded.',
        #M.settings.fatigue.observations));

    if imgui.Button('It just reset') then
        tracker.fatigue_reset(true);
        print(chat.header(addon.name):append(chat.message('Fatigue reset recorded.')));
    end
    imgui.SameLine();
    if imgui.Button('Forget schedule') then
        M.settings.fatigue.observations = T{};
    end

    imgui.Separator();
    imgui.Text('Zone advice');
    imgui.Checkbox('Show "Best for" line', M.settings.tracker.show_best_for);
    imgui.TextDisabled('Best zone for gil, and best for skill at your current level.');

    imgui.Separator();
    imgui.Text('Session journal');
    imgui.Checkbox('Write one line per swing', M.settings.journal.enabled);
    local st = journal.stats();
    imgui.TextDisabled(string.format('%d written, %d pending', st.written or 0, st.pending or 0));
    if st.path ~= nil then
        imgui.TextDisabled(tostring(st.path));
    end
    if st.error ~= nil then
        imgui.TextColored({ 0.96, 0.44, 0.44, 1.0 }, tostring(st.error));
    end
    if imgui.Button('Flush now') then
        journal.flush();
    end

    ui.end_child();
end

local function do_reset_defaults()
    settings.reset();
    M.ensure_ui_settings();
    ui.bind(M.settings, M.editor_open);
    M.update_pricing();
    print(chat.header(addon.name):append(chat.message('Settings reset for this character.')));
end

local function render_layout()
    ui.begin_child('floos_layout', { 0, 220 }, true);
    local tracker_pos = T{ M.settings.tracker.x[1], M.settings.tracker.y[1] };
    if imgui.InputInt2('Tracker Position', tracker_pos) then
        M.settings.tracker.x[1] = tracker_pos[1];
        M.settings.tracker.y[1] = tracker_pos[2];
    end
    imgui.SliderInt('Panel Width', M.settings.tracker.width, 320, 600);
    imgui.SliderInt('Panel Height (0 = auto)', M.settings.tracker.height, 0, 900);
    imgui.SameLine();
    if imgui.Button('Auto') then
        M.settings.tracker.height[1] = 0;
    end
    imgui.TextDisabled('Drag the bottom-right grip to resize. Double-click it for auto height.');
    imgui.Separator();
    imgui.Spacing();
    if imgui.Button('Reset Defaults') then
        imgui.OpenPopup('FloosResetDefaults##Confirm');
    end
    imgui.TextDisabled('Restores all Floos settings to factory defaults.');
    if imgui.BeginPopupModal('FloosResetDefaults##Confirm', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text('Reset all Floos settings to defaults?');
        imgui.TextWrapped('This cannot be undone. Saved positions, prices, fonts, and appearance will be lost.');
        imgui.Spacing();
        if imgui.Button('Confirm Reset', { 140, 0 }) then
            do_reset_defaults();
            imgui.CloseCurrentPopup();
        end
        imgui.SameLine();
        if imgui.Button('Cancel', { 140, 0 }) then
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end
    ui.end_child();
end

local function render_about()
    ui.begin_child('floos_about', { 0, fill_height(200) }, true);
    imgui.Text('Floos - HELM companion for Ashita 4.3');
    imgui.TextDisabled(string.format('Version %s', addon.version));
    imgui.Spacing();
    if attribution ~= nil and attribution.render ~= nil then
        attribution.render();
    else
        imgui.TextDisabled('See THIRD_PARTY_NOTICES.md for license details.');
    end
    ui.end_child();
end

function M.render_editor()
    if not M.editor_open[1] then
        return;
    end
    M.ensure_ui_settings();
    imgui.SetNextWindowSize({ 540, 600 }, ImGuiCond_FirstUseEver);
    local style_counts = theme.apply_style();
    if imgui.Begin('Floos##Config', M.editor_open) then
        if imgui.Button('Save') then
            M.update_pricing();
            settings.save();
            print(chat.header(addon.name):append(chat.message('Settings saved.')));
        end
        imgui.SameLine();
        if imgui.Button('Reload') then
            settings.reload();
            M.ensure_ui_settings();
            ui.bind(M.settings, M.editor_open);
            M.update_pricing();
            print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        end
        imgui.SameLine();
        if imgui.Button('Reset Session') then
            local tracker = require('modules.tracker');
            tracker.reset_session();
            settings.save();
            print(chat.header(addon.name):append(chat.message('Session cleared.')));
        end

        imgui.Separator();
        if imgui.BeginTabBar('##floos_tabs') then
            if imgui.BeginTabItem('General') then
                render_general();
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('Interface') then
                render_appearance();
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('HELM') then
                render_mining();
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('Data') then
                render_data();
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('Layout') then
                render_layout();
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('About') then
                render_about();
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();
    theme.pop_style(style_counts);
end

return M;
