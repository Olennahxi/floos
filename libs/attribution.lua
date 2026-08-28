--[[
* Floos - credits and third-party notices
*
* Two different things live here and they are not interchangeable:
*
*   CREDITS  - people and projects worth thanking. A courtesy.
*   NOTICES  - licence terms the code arrived under. An obligation.
*
* Both are rendered in the About tab, because a player should be able to see
* who built what without going to look for a text file.
]]--

require('common');
local imgui = require('imgui');

local M = {};

M.DESCRIPTION = [[
Floos is a hobby tracker for HorizonXI. It follows all eight of them - mining,
logging, harvesting, excavation, hunting, fishing, chocobo digging and
clamming - and answers one question for each: is this still worth doing?

Swings, breaks, drops, fatigue and daily caps, gil and gil per hour, skill gain
and skill-up rate per outcome, per-zone history so you can tell whether to stay
or move, the elemental ore window, and the odds that your next clam bursts the
bucket.

It reads. It never sends, never acts for you, and never automates anything.
]];

--------------------------------------------------------------------------
-- Credits
--
-- Ordered by how much they gave, not alphabetically. Every entry says what
-- it actually contributed, because "thanks to X" tells a reader nothing.
--------------------------------------------------------------------------
M.CREDITS = {
    {
        name = 'XIUI',
        by = 'tirem',
        url = 'https://github.com/tirem/XIUI',
        license = 'GPLv3',
        what = 'The rendering layer Floos is drawn with - window backgrounds, '
            .. 'progress bars, texture and font handling, D3D helpers, colour '
            .. 'utilities and most of the visual assets. Floos would look like '
            .. 'a debug console without it.',
    },
    {
        name = 'HGather',
        by = 'Hastega, and SlowedHaste who maintains it',
        url = 'https://github.com/SlowedHaste/HGather',
        license = 'see repository',
        what = 'The original HELM tracker, and where the gathering detection '
            .. 'approach came from - the 0x36 trade handshake and reading the '
            .. 'outcome out of chat. Floos started as an attempt to extend it.',
    },
    {
        name = 'HXIClam',
        by = 'jimmy58663',
        url = 'https://github.com/jimmy58663/hxiclam',
        license = 'BSD 3-Clause',
        what = 'The reference clamming tracker for HorizonXI. No code was '
            .. 'taken, but it is what the Clam tab was checked against, and '
            .. 'the bucket-weight idea is its.',
    },
    {
        name = 'LuAshitacast',
        by = 'ThornyFFXI',
        url = 'https://github.com/ThornyFFXI/LuAshitacast',
        license = 'see repository',
        what = 'Independent confirmation of the weather signature, and the '
            .. 'better habit of resolving a scan once instead of per frame.',
    },
    {
        name = 'Lua-Bitmap',
        by = 'RexmecK',
        url = 'https://github.com/RexmecK/Lua-Bitmap',
        license = 'see repository',
        what = 'libs/bitmap.lua, by way of XIUI.',
    },
    {
        name = 'LandSandBoat / AirSkyBoat / DarkStar',
        by = 'their contributors',
        url = 'https://github.com/LandSandBoat/server',
        license = 'GPLv3',
        what = 'Open server implementations. Reading them is how the exact '
            .. 'message strings, the clamming cooldown and the digging rank '
            .. 'formula were verified instead of guessed.',
    },
    {
        name = 'XiPackets',
        by = 'atom0s',
        url = 'https://github.com/atom0s/XiPackets',
        license = 'see repository',
        what = 'Packet documentation. The trade and weather offsets in Floos '
            .. 'are right because this exists.',
    },
    {
        name = 'Windower resources',
        by = 'the Windower project',
        url = 'https://github.com/Windower/Resources',
        license = 'see repository',
        what = 'Cross-checked the weather table and packet field layouts.',
    },
    {
        name = 'Ashita',
        by = 'atom0s and contributors',
        url = 'https://ashitaxi.com',
        license = 'see site',
        what = 'The framework all of this runs on.',
    },
    {
        name = 'The HorizonXI wiki editors',
        by = 'and Sushomi, whose clamming analysis is the source of the '
            .. 'weights and abundances',
        url = 'https://horizonffxi.wiki',
        license = '',
        what = 'Every number Floos treats as fact - dig ranks, ore conditions, '
            .. 'clam weights, drop abundances, restock hours - was published '
            .. 'by someone who measured it and wrote it down.',
    },
};

--------------------------------------------------------------------------
-- Licence notices. These are not thank-yous; they are the terms.
--------------------------------------------------------------------------
M.XIUI_URL = 'https://github.com/tirem/XIUI';
M.XIUI_LICENSE = 'GNU General Public License v3.0';

M.XIUI_NOTICE = [[
UI rendering components and visual assets in Floos are derived from XIUI
(https://github.com/tirem/XIUI), copyright its respective authors, and used
under the terms of the GNU General Public License v3.0.

Ported or adapted components include:
  - libs/color.lua
  - libs/bitmap.lua (originally by RexmecK, used by XIUI)
  - libs/memory.lua (D3D device helpers)
  - libs/texturemanager.lua
  - libs/windowbackground.lua
  - libs/progressbar.lua
  - libs/drawing.lua
  - assets/backgrounds/* (Window1 theme)
  - assets/gil.png, assets/arrow.png
  - assets/session_play.png, session_pause.png, session_clear.png

HELM detection logic is adapted from HGather by Hastega.

Source for XIUI is available at the URL above. Full notices are in
THIRD_PARTY_NOTICES.md.
]];

function M.get_short_credit()
    return string.format('UI rendering adapted from XIUI (%s), GPLv3.', M.XIUI_URL);
end

--- Rendered inside the config About tab.
function M.render()
    imgui.TextWrapped(M.DESCRIPTION);
    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    imgui.Text('Thanks to');
    imgui.TextDisabled('Floos stands on other people\'s work. In order of debt:');
    imgui.Spacing();
    for _, c in ipairs(M.CREDITS) do
        imgui.Text(c.name);
        if c.by ~= nil and c.by ~= '' then
            imgui.SameLine();
            imgui.TextDisabled('by ' .. c.by);
        end
        imgui.TextWrapped(c.what);
        if c.url ~= nil and c.url ~= '' then
            local tail = c.url;
            if c.license ~= nil and c.license ~= '' then
                tail = tail .. '   -   ' .. c.license;
            end
            imgui.TextDisabled(tail);
        end
        imgui.Spacing();
    end

    imgui.Separator();
    imgui.Spacing();
    imgui.TextDisabled('Third-party licence notices');
    imgui.TextWrapped(M.XIUI_NOTICE);
    imgui.Spacing();
    imgui.TextDisabled(M.get_short_credit());
end

return M;
