--[[
* Floos - HELM companion for Ashita 4.3
*
* Mining session tracker with skill, fatigue, and gil stats.
* UI rendering adapted from XIUI (GPLv3). See THIRD_PARTY_NOTICES.md.
* Mining logic adapted from HGather (Hastega).
]]--

addon.name = 'floos';
addon.author = 'Makee';
addon.version = '3.0.1';
addon.desc = 'HorizonXI hobby tracker: Mine, Logg, Harv, Exca, Hunt, Fish, Dig, Clam.';
addon.link = 'https://horizonffxi.wiki';
-- One command. /resetmine used to exist as well, doing exactly what
-- /floos clear does, and squatting on a global slash name that another
-- addon could reasonably want.
addon.commands = { '/floos' };

require('common');
local chat = require('chat');
local settings = require('settings');

local config = require('config');
local ui = require('libs.ui');
local fonts = require('libs.fonts');
local journal = require('libs.journal');
local tracker = require('modules.tracker');

--- The command list, grouped and short.
---
--- This used to print 28 lines for 23 handlers, which is not a help screen,
--- it is a wall. Duplicates were deleted rather than hidden: an invisible
--- alias is how a list grows back. Sub-commands ride on their parent's line.
local COMMANDS = {
    { 'Panel', {
        { '/floos',            'Open the settings window.' },
        { '/floos show|hide',  'Show or hide the tracker.' },
        { '/floos detail',     'full | compact | mini.' },
        { '/floos compact',    'Toggle compact mode (no drop list).' },
        { '/floos mini',       'Toggle the five-line mini panel.' },
        { '/floos auto',       'Release the locked panel height.' },
    }},
    { 'Session', {
        { '/floos report',     'Print session stats to chat.' },
        { '/floos clear',      'Clear every session.' },
        { '/floos zones',      'Rank zones by gil/hr.  (+ clear)' },
        { '/floos insights',   'What your journal shows.  (+ tab name)' },
    }},
    { 'Activity', {
        { '/floos ore',        'Can you dig elemental ore right now?' },
        { '/floos dig',        'Daily count and JST reset.  (+ a number)' },
        { '/floos clam',       'Bucket weight, value, break odds.' },
        { '/floos fatigue',    'Reset countdown.  (+ reset)' },
    }},
    { 'Setup', {
        { '/floos prices fetch',  'Pull live prices from psxi.gg.' },
        { '/floos prices token <t>', 'Save a psxi.gg API token.' },
        { '/floos prices import <file>', 'Merge a name:price file.' },
        { '/floos debug',      'What the addon is actually seeing.  (+ on | off)' },
    }},
};

local function print_help(is_error)
    if is_error then
        print(chat.header(addon.name):append(chat.error(
            'Unknown command. /floos help lists them all.'
        )));
        return;
    end

    for _, group in ipairs(COMMANDS) do
        print(chat.header(addon.name):append(chat.color1(2, group[1])));
        for _, row in ipairs(group[2]) do
            print(chat.header(addon.name)
                :append(chat.message(row[1]))
                :append('  -  ')
                :append(chat.color1(6, row[2])));
        end
    end
end

--- Point every module at the current settings table and reload state from it.
--- Order matters: bind first, restore second, and never persist in between -
--- persisting before the restore would overwrite the character's saved
--- progress with whatever zeros are in memory.
local function bind_all()
    ui.bind(config.settings, config.editor_open);
    tracker.bind_settings(config.settings);
    tracker.restore_session();

    -- Journal path is per character, so it is only right once we are in game.
    local charname = '';
    pcall(function ()
        charname = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or '';
    end);
    journal.flush();
    journal.configure({
        enabled = config.settings.journal.enabled[1],
        path = journal.default_path(charname),
    });
end

-- The settings library swaps to a per-character table at login and back to the
-- global one at logout. Rebinding here is what makes progress survive a relog.
config.on_settings_change = bind_all;

ashita.events.register('load', 'load_cb', function ()
    config.ensure_ui_settings();
    config.update_pricing();
    bind_all();

    fonts.prewarm();

    if config.settings.reset_on_load[1] then
        tracker.reset_session();
    end
end);

ashita.events.register('unload', 'unload_cb', function ()
    journal.flush();
    tracker.persist_session();
    ui.cleanup();
    settings.save();
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if #args == 0 then
        return;
    end

    if not args[1]:any('/floos') then
        return;
    end

    e.blocked = true;

    if #args == 1 then
        config.editor_open[1] = not config.editor_open[1];
        return;
    end

    if args[2]:any('help', '?') then
        print_help(false);
        return;
    end

    if args[2]:any('report') then
        print(tracker.build_report(config.settings, config.pricing));
        return;
    end

    if args[2]:any('clear') then
        tracker.reset_session('all');
        settings.save();
        print(chat.header(addon.name):append(chat.message('All sessions cleared.')));
        return;
    end

    if args[2]:any('show') then
        if config.settings.panels_hidden == nil then
            config.settings.panels_hidden = T{ false };
        end
        config.settings.panels_hidden[1] = false;
        config.settings.tracker.visible[1] = true;
        tracker.touch_activity();
        return;
    end

    if args[2]:any('hide') then
        if config.settings.panels_hidden == nil then
            config.settings.panels_hidden = T{ false };
        end
        config.settings.panels_hidden[1] = true;
        return;
    end

    -- `/floos detail <level>` sets a level outright; `/floos compact`, `mini`
    -- and `full` are the shorthands, and compact/mini toggle back to Full when
    -- you are already on them, so one word switches the panel both ways.
    if args[2]:any('mini', 'compact', 'detail', 'full') then
        config.ensure_ui_settings();
        local ui_cfg = config.settings.ui;
        local current = ui_cfg.detail[1];
        local target = nil;

        if args[2]:any('detail') then
            local want = (#args >= 3) and args[3]:lower() or '';
            if want == 'full' then target = 'Full';
            elseif want == 'compact' then target = 'Compact';
            elseif want == 'mini' then target = 'Mini';
            else
                print(chat.header(addon.name):append(chat.error(
                    'Usage: /floos detail full | compact | mini'
                )));
                return;
            end
        elseif args[2]:any('full') then
            target = 'Full';
        elseif args[2]:any('mini') then
            target = (current == 'Mini') and 'Full' or 'Mini';
        else
            target = (current == 'Compact') and 'Full' or 'Compact';
        end

        ui_cfg.detail[1] = target;
        ui_cfg.compact[1] = (target == 'Compact');
        -- A locked height would leave a big empty box under a smaller panel.
        config.settings.tracker.height[1] = 0;
        settings.save();
        print(chat.header(addon.name):append(chat.message('Panel detail: ' .. target .. '.')));
        return;
    end

    if args[2]:any('auto', 'autoheight') then
        config.settings.tracker.height[1] = 0;
        settings.save();
        print(chat.header(addon.name):append(chat.message('Panel height set to auto.')));
        return;
    end

    if args[2]:any('clam', 'bucket') then
        local s = tracker.sessions and tracker.sessions.clamming or nil;
        if s == nil then
            print(chat.header(addon.name):append(chat.error('No clamming session.')));
            return;
        end
        local cap = s.bucket_capacity or 0;
        if cap <= 0 then cap = 50; end
        local wt = s.bucket_weight or 0;
        local gil = tracker.get_bucket_value(config.pricing);
        local hq = config.settings.clamming and config.settings.clamming.hq_body
            and config.settings.clamming.hq_body[1];
        local risk = tracker.clam_risk(wt, cap, hq);

        print(chat.header(addon.name):append(chat.message(string.format(
            'Bucket: %d / %d pz, worth %s gil. %d pz of room left.',
            wt, cap, tostring(gil), risk.headroom
        ))));

        if risk.break_pct <= 0.001 then
            print(chat.header(addon.name):append(chat.color1(2,
                'Nothing in the pool can break this bucket. Dig away.')));
        else
            local lose = math.floor((gil * risk.break_pct / 100) + 0.5);
            print(chat.header(addon.name):append(chat.color1(6, string.format(
                'Next dig: %.1f%% chance the bucket bursts (%.1f%% too heavy, %.1f%% jumped in).',
                risk.break_pct, risk.overflow_pct, risk.incident_pct
            ))));
            print(chat.header(addon.name):append(chat.color1(6, string.format(
                'That is %s gil at risk on average. Bucket holds %s gil now.',
                tostring(lose), tostring(gil)
            ))));
        end

        if tracker.clam_upgrade_ready(wt, cap) then
            print(chat.header(addon.name):append(chat.color1(2,
                'Heavy enough for an upgrade - hand in for the next bucket size.')));
        end
        if s.bucket_broken then
            print(chat.header(addon.name):append(chat.error(
                'Your bucket is broken. Buy a new kit from Toh Zonikki.')));
        end
        return;
    end

    if args[2]:any('dig', 'daily') then
        local s = tracker.sessions and tracker.sessions.digging or nil;
        if s == nil then
            print(chat.header(addon.name):append(chat.error('No digging session.')));
            return;
        end
        tracker.roll_dig_day(s);

        if #args >= 3 then
            if args[3]:any('reset', 'clear', 'zero') then
                s.daily_items = 0;
            else
                local n = tonumber(args[3]);
                if n == nil or n < 0 then
                    print(chat.header(addon.name):append(chat.error(
                        'Usage: /floos dig <number of items dug today> | reset'
                    )));
                    return;
                end
                s.daily_items = math.floor(n);
            end
            tracker.persist_session();
            settings.save();
        end

        local vana = require('libs.vana');
        local cap = tracker.dig_daily_cap(config.settings);
        local left = math.max(0, cap - (s.daily_items or 0));
        local secs = vana.seconds_until_jst_midnight();
        print(chat.header(addon.name):append(chat.message(string.format(
            'Dug today: %d / %d  (%d left).', s.daily_items or 0, cap, left
        ))));
        print(chat.header(addon.name):append(chat.color1(6, string.format(
            'Resets in %dh %02dm, at midnight Japan time - 6PM in Kuwait.',
            math.floor(secs / 3600), math.floor((secs % 3600) / 60)
        ))));
        return;
    end

    if args[2]:any('ore', 'orewatch') then
        local ore = tracker.ore_conditions(config.settings);

        local head;
        if ore.verdict == 'yes' then
            head = 'Ore window is OPEN'
                .. (ore.element and (' - digging can turn up ' .. ore.element .. ' Ore today.') or '.');
        elseif ore.verdict == 'maybe' then
            head = 'Cannot say yet - ' .. table.concat(ore.unknowns, ', ')
                .. ' still unknown. Nothing else is blocking.';
        else
            head = 'No ore right now. Blocked by: ' .. table.concat(ore.blockers, ', ') .. '.';
        end
        print(chat.header(addon.name):append(chat.message(head)));

        for _, c in ipairs(ore.conds) do
            local mark = (c.ok == true) and 'OK  ' or ((c.ok == false) and 'NO  ' or '??  ');
            local line = string.format('%s%-8s %s', mark, c.label, c.detail or '');
            if c.ok ~= true then
                line = line .. '   (need: ' .. (c.want or '?') .. ')';
            end
            if c.key == 'moon' and ore.moon_days ~= nil and ore.moon_days > 0 then
                line = line .. string.format('   opens in %d Vana days', ore.moon_days);
            end
            if c.ok == true then
                print(chat.header(addon.name):append(chat.color1(2, line)));
            else
                print(chat.header(addon.name):append(chat.color1(6, line)));
            end
        end

        if ore.day ~= nil then
            print(chat.header(addon.name):append(chat.color1(6, string.format(
                'Today is %s, so any ore found would be %s Ore. Rate is about 5 in 1120 digs.',
                ore.day, ore.element or '?'))));
        end
        return;
    end

    if args[2]:any('fatigue', 'fat') then
        if #args >= 3 and args[3]:any('reset', 'now') then
            tracker.fatigue_reset(true);
            settings.save();
            print(chat.header(addon.name):append(chat.message(
                'Fatigue reset recorded. Confidence: ' .. tracker.fatigue_confidence() .. '.'
            )));
            return;
        end
        if #args >= 3 and args[3]:any('forget', 'clear') then
            config.settings.fatigue.observations = T{};
            settings.save();
            print(chat.header(addon.name):append(chat.message('Fatigue schedule forgotten.')));
            return;
        end

        local left = tracker.fatigue_time_left();
        if left == nil then
            print(chat.header(addon.name):append(chat.message(
                'No reset seen yet. Gather past the cap once and it learns, or use /floos fatigue reset.'
            )));
        else
            local fmt = require('libs.format');
            print(chat.header(addon.name):append(chat.message(string.format(
                'Next fatigue reset in %s (confidence: %s).',
                fmt.format_duration(left), tracker.fatigue_confidence()
            ))));
        end
        return;
    end

    if args[2]:any('prices', 'price') then
        if #args >= 3 and args[3]:any('fetch', 'psxi', 'update') then
            print(chat.header(addon.name):append(chat.message(
                'Asking psxi.gg for prices - the game will hitch for a moment.'
            )));
            -- Second return is the snapshot timestamp on success, the reason
            -- on failure.
            local token = config.settings.psxi_token;
            local updated, info = config.fetch_prices(token and token[1] or '');
            if updated == nil then
                print(chat.header(addon.name):append(chat.error(info)));
                return;
            end
            settings.save();
            print(chat.header(addon.name):append(chat.message(string.format(
                '%d prices updated from psxi.gg%s.', updated,
                info ~= nil and (' (snapshot ' .. tostring(info) .. ')') or ''
            ))));
            return;
        end
        if #args >= 3 and args[3]:any('token', 'key') then
            if config.settings.psxi_token == nil then
                config.settings.psxi_token = T{ '' };
            end
            config.settings.psxi_token[1] = (#args >= 4) and args[4] or '';
            settings.save();
            print(chat.header(addon.name):append(chat.message(
                config.settings.psxi_token[1] == ''
                    and 'psxi.gg token cleared.'
                    or 'psxi.gg token saved.'
            )));
            return;
        end
        if #args >= 3 and args[3]:any('import', 'load') then
            local fname = (#args >= 4) and args[4] or 'prices.txt';
            local path = fname;
            if not fname:match('^%a:[/\\]') and not fname:match('^[/\\]') then
                path = config.prices_dir() .. '/' .. fname;
            end
            local f = io.open(path, 'r');
            if f == nil then
                print(chat.header(addon.name):append(chat.error('Cannot open ' .. path)));
                print(chat.header(addon.name):append(chat.message(
                    'Expected one "name:price" per line, e.g. chunk of iron ore:650'
                )));
                return;
            end
            local lines = {};
            for line in f:lines() do
                lines[#lines + 1] = line;
            end
            f:close();
            local updated, added, skipped = config.merge_prices(lines);
            settings.save();
            print(chat.header(addon.name):append(chat.message(string.format(
                'Prices imported: %d updated, %d added, %d skipped.', updated, added, skipped
            ))));
            return;
        end
        local count = 0;
        for _ in pairs(config.pricing) do count = count + 1; end
        print(chat.header(addon.name):append(chat.message(string.format(
            '%d items priced. Refresh them: /floos prices fetch', count
        ))));
        return;
    end

    if args[2]:any('insights', 'insight', 'stats') then
        local insights = require('libs.insights');
        local act = tracker.active_tab or 'mining';
        if #args >= 3 then
            local want = args[3]:lower();
            if want:any('mining', 'mine') then act = 'mining';
            elseif want:any('logging', 'logg', 'log') then act = 'logging';
            elseif want:any('harvest', 'harv') then act = 'harvest';
            elseif want:any('excavate', 'exca') then act = 'excavate';
            elseif want:any('fishing', 'fish') then act = 'fishing';
            elseif want:any('digging', 'dig') then act = 'digging';
            end
        end

        local charname = '';
        pcall(function ()
            charname = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or '';
        end);
        journal.flush();  -- so the analysis includes the last few swings
        local a = insights.analyze(journal.default_path(charname), act);
        for _, line in ipairs(insights.report_lines(a, act)) do
            print(chat.header(addon.name):append(chat.message(line)));
        end
        return;
    end

    if args[2]:any('debug', 'diag') then
        if #args >= 3 and args[3]:any('on', 'off') then
            tracker.debug_echo = args[3]:any('on');
            print(chat.header(addon.name):append(chat.message(
                'Live debug echo ' .. (tracker.debug_echo and 'on.' or 'off.')
            )));
            return;
        end

        local id, name = tracker.refresh_zone();
        print(chat.header(addon.name):append(chat.message(string.format(
            'Zone: %s (%d)   Tab: %s   Awaiting: %s',
            name or 'Unknown', id or 0, tostring(tracker.active_tab),
            tostring(tracker.awaiting or 'nothing')
        ))));

        do
            local wlib = require('libs.weather');
            local wx = wlib.current();
            print(chat.header(addon.name):append(chat.message(string.format(
                'Weather: %s%s',
                wx.known and wx.name or 'unreadable',
                wx.known and string.format('  (%s, via %s)',
                    wx.elemental and wx.element or 'no element', wx.source or '?') or ''
            ))));
            if not wlib.signature_ok() then
                print(chat.header(addon.name):append(chat.error(
                    'Weather signature did not resolve in FFXiMain.dll - falling back'
                )));
                print(chat.header(addon.name):append(chat.error(
                    'to packets, which means it fills in the next time you zone.'
                )));
            end
        end

        local log = tracker.debug_log or {};
        if #log == 0 then
            print(chat.header(addon.name):append(chat.error(
                'Nothing seen yet. If you are gathering and this stays empty, the'
            )));
            print(chat.header(addon.name):append(chat.error(
                'addon is not seeing the trade at all - check the addon is loaded.'
            )));
            return;
        end

        local now = os.time();
        for _, entry in ipairs(log) do
            print(chat.header(addon.name)
                :append(chat.color1(6, string.format('%4ds ago  ', now - (entry.t or now))))
                :append(chat.message(string.format('%-8s %s', entry.kind, entry.detail))));
        end
        return;
    end

    if args[2]:any('zones', 'zonetrack') then
        if #args >= 3 and args[3]:any('clear', 'reset') then
            tracker.clear_zone_stats();
            settings.save();
            print(chat.header(addon.name):append(chat.message('Zone history cleared.')));
            return;
        end
        print(tracker.build_zone_report(config.settings, tracker.active_tab));
        return;
    end

    print_help(true);
end);

ashita.events.register('packet_out', 'packet_out_cb', function (e)
    tracker.handle_packet_out(e);
end);

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    tracker.handle_packet_in(e);
end);

ashita.events.register('text_in', 'text_in_cb', function (e)
    tracker.handle_text(e, config.pricing);
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    if not AshitaCore:GetFontManager():GetVisible() then
        return;
    end

    ui.present_frame_start();
    tracker.tick_autosave();

    -- Config uses default ImGui font
    config.render_editor();

    fonts.push(config.settings);

    if config.panels_are_shown() then
        tracker.render(config.settings, config.pricing, config.editor_open[1] and config.settings.tracker.visible[1]);
    end

    fonts.pop();
end);
