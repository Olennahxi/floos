--[[
* Floos - Visualization primitives (bars, strips, sparklines, markers)
*
* Everything here draws straight onto an ImGui draw list. Nothing allocates
* textures, so it is safe to call every frame. All calls that touch optional
* ImGui binding functions are pcall-guarded: on an older/newer Ashita the
* widget degrades instead of throwing inside d3d_present.
]]--

require('common');
local imgui = require('imgui');

local M = {};

local function clamp01(v)
    v = tonumber(v) or 0;
    if v < 0 then return 0; end
    if v > 1 then return 1; end
    return v;
end

M.clamp01 = clamp01;

--- Pack an ImGui vec4 table into IM_COL32 (ABGR in memory).
function M.u32(c)
    if c == nil then
        return 0xFFFFFFFF;
    end
    local ok, packed = pcall(function()
        return imgui.GetColorU32(c);
    end);
    if ok and packed ~= nil then
        return packed;
    end
    local r = math.floor(clamp01(c[1] or 1) * 255 + 0.5);
    local g = math.floor(clamp01(c[2] or 1) * 255 + 0.5);
    local b = math.floor(clamp01(c[3] or 1) * 255 + 0.5);
    local a = math.floor(clamp01(c[4] or 1) * 255 + 0.5);
    return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r);
end

--- Copy a color with a new alpha.
function M.alpha(c, a)
    c = c or { 1, 1, 1, 1 };
    return { c[1] or 1, c[2] or 1, c[3] or 1, clamp01(a) };
end

--- Copy a color scaled toward black (t = 0 keeps, t = 1 black).
function M.shade(c, t)
    c = c or { 1, 1, 1, 1 };
    t = 1 - clamp01(t);
    return { (c[1] or 1) * t, (c[2] or 1) * t, (c[3] or 1) * t, c[4] or 1 };
end

--- Linear blend between two colors.
function M.lerp(a, b, t)
    t = clamp01(t);
    a = a or { 1, 1, 1, 1 };
    b = b or { 1, 1, 1, 1 };
    return {
        (a[1] or 0) + ((b[1] or 0) - (a[1] or 0)) * t,
        (a[2] or 0) + ((b[2] or 0) - (a[2] or 0)) * t,
        (a[3] or 0) + ((b[3] or 0) - (a[3] or 0)) * t,
        (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t,
    };
end

--- Three-stop ramp: t 0..0.5 blends a->b, 0.5..1 blends b->c.
function M.ramp3(a, b, c, t)
    t = clamp01(t);
    if t <= 0.5 then
        return M.lerp(a, b, t / 0.5);
    end
    return M.lerp(b, c, (t - 0.5) / 0.5);
end

local function safe(fn)
    local ok = pcall(fn);
    return ok;
end

function M.rect(dl, x, y, w, h, color, rounding)
    if dl == nil or w == nil or w <= 0 or h == nil or h <= 0 then
        return;
    end
    local col = M.u32(color);
    safe(function()
        dl:AddRectFilled({ x, y }, { x + w, y + h }, col, rounding or 0);
    end);
end

function M.rect_outline(dl, x, y, w, h, color, rounding, thickness)
    if dl == nil or w == nil or w <= 0 or h == nil or h <= 0 then
        return;
    end
    local col = M.u32(color);
    safe(function()
        dl:AddRect({ x, y }, { x + w, y + h }, col, rounding or 0, 0, thickness or 1);
    end);
end

function M.line(dl, x1, y1, x2, y2, color, thickness)
    if dl == nil then return; end
    local col = M.u32(color);
    safe(function()
        dl:AddLine({ x1, y1 }, { x2, y2 }, col, thickness or 1);
    end);
end

--- Horizontal gradient fill (left color -> right color).
function M.grad_rect(dl, x, y, w, h, c_left, c_right)
    if dl == nil or w == nil or w <= 0 or h == nil or h <= 0 then
        return;
    end
    local l = M.u32(c_left);
    local r = M.u32(c_right);
    local ok = safe(function()
        dl:AddRectFilledMultiColor({ x, y }, { x + w, y + h }, l, r, r, l);
    end);
    if not ok then
        M.rect(dl, x, y, w, h, c_right, 0);
    end
end

--- Track + gradient fill meter.
--- opts: { rounding, track, tick (0..1), tick_color, glow }
function M.bar(dl, x, y, w, h, pct, c_from, c_to, opts)
    if dl == nil or w == nil or w <= 0 or h == nil or h <= 0 then
        return;
    end
    opts = opts or {};
    pct = clamp01(pct);
    local rounding = opts.rounding;
    if rounding == nil then
        rounding = math.min(h * 0.5, 3);
    end

    local track = opts.track or { 1, 1, 1, 0.07 };
    M.rect(dl, x, y, w, h, track, rounding);

    local fill_w = w * pct;
    if fill_w > 0 then
        if fill_w < 2 then fill_w = 2; end
        if rounding > 0 and fill_w > rounding * 2 then
            -- Rounded base in the mid tone, then the gradient body on top so the
            -- caps do not read as a hard color break.
            M.rect(dl, x, y, fill_w, h, M.lerp(c_from, c_to or c_from, 0.5), rounding);
            M.grad_rect(dl, x + rounding, y, math.max(0, fill_w - rounding * 2), h, c_from, c_to or c_from);
        else
            M.grad_rect(dl, x, y, fill_w, h, c_from, c_to or c_from);
        end
    end

    if opts.tick ~= nil then
        local tx = x + (w * clamp01(opts.tick));
        M.line(dl, tx, y - 1, tx, y + h + 1, opts.tick_color or { 1, 1, 1, 0.55 }, 1.0);
    end

    -- Quiet graduation marks inside the track (e.g. quarters of a cap), drawn
    -- shorter and dimmer than the reference tick so they read as a ruler, not
    -- as data.
    if opts.ticks ~= nil then
        for _, t in ipairs(opts.ticks) do
            local tx = x + (w * clamp01(t));
            M.line(dl, tx, y + 1, tx, y + h - 1,
                opts.ticks_color or { 1, 1, 1, 0.22 }, 1.0);
        end
    end

    if opts.border then
        M.rect_outline(dl, x, y, w, h, opts.border, rounding, 1);
    end
end

--- Outcome strip: one tick per entry, newest on the right.
--- entries: array of { oc = 'W'|'M'|'B', skill = bool }
--- colors: { W = c, M = c, B = c, skill = c }
function M.strip(dl, x, y, w, h, entries, colors, max_ticks)
    if dl == nil or entries == nil or w <= 0 then
        return 0;
    end
    max_ticks = max_ticks or 30;
    local n = #entries;
    if n <= 0 then
        M.rect(dl, x, y, w, h, { 1, 1, 1, 0.05 }, 2);
        return 0;
    end

    local shown = math.min(n, max_ticks);
    local gap = 2;
    local tick_w = (w - (gap * (shown - 1))) / shown;
    if tick_w < 1.5 then
        gap = 1;
        tick_w = (w - (gap * (shown - 1))) / shown;
    end
    if tick_w < 1 then tick_w = 1; end

    local first = n - shown + 1;
    for i = first, n do
        local e = entries[i] or {};
        local col = colors[e.oc or 'M'] or { 0.6, 0.6, 0.6, 1.0 };
        local idx = i - first;
        local tx = x + (idx * (tick_w + gap));
        -- Oldest entries fade out so the recent tail reads first.
        local age = 1;
        if shown > 1 then
            age = 0.45 + (0.55 * (idx / (shown - 1)));
        end
        M.rect(dl, tx, y, tick_w, h, M.alpha(col, (col[4] or 1) * age), 1);
        if e.skill then
            local dot = colors.skill or { 1, 1, 1, 1 };
            local dw = math.max(2, tick_w);
            M.rect(dl, tx, y - 3, dw, 2, dot, 1);
        end
    end
    return shown;
end

--- Simple filled sparkline. values: array of numbers (oldest first).
function M.spark(dl, x, y, w, h, values, color, fill_alpha)
    if dl == nil or values == nil or #values < 2 or w <= 0 or h <= 0 then
        return false;
    end

    local n = #values;
    local lo, hi = values[1], values[1];
    for i = 2, n do
        local v = values[i] or 0;
        if v < lo then lo = v; end
        if v > hi then hi = v; end
    end
    if hi <= lo then
        hi = lo + 1;
    end

    local step = w / (n - 1);
    local function point(i)
        local v = values[i] or 0;
        local t = (v - lo) / (hi - lo);
        return x + ((i - 1) * step), y + h - (t * h);
    end

    -- Soft area under the curve.
    local area = M.alpha(color, fill_alpha or 0.18);
    for i = 1, n - 1 do
        local x1, y1 = point(i);
        local x2, y2 = point(i + 1);
        local top = math.min(y1, y2);
        M.rect(dl, x1, top, math.max(1, x2 - x1), math.max(0, (y + h) - top), area, 0);
    end

    for i = 1, n - 1 do
        local x1, y1 = point(i);
        local x2, y2 = point(i + 1);
        M.line(dl, x1, y1, x2, y2, color, 1.5);
    end

    local lx, ly = point(n);
    M.rect(dl, lx - 1.5, ly - 1.5, 3, 3, color, 1);
    return true;
end

--- Small diamond marker (font-independent replacement for a star glyph).
function M.diamond(dl, cx, cy, r, color)
    if dl == nil then return; end
    local col = M.u32(color);
    local ok = safe(function()
        dl:AddTriangleFilled({ cx, cy - r }, { cx + r, cy }, { cx, cy + r }, col);
        dl:AddTriangleFilled({ cx, cy - r }, { cx - r, cy }, { cx, cy + r }, col);
    end);
    if not ok then
        M.rect(dl, cx - r * 0.7, cy - r * 0.7, r * 1.4, r * 1.4, color, 1);
    end
end

--- Hollow circle. Falls back to a square outline if AddCircle is unavailable.
function M.circle(dl, cx, cy, r, color, thickness, segments)
    if dl == nil or r == nil or r <= 0 then
        return;
    end
    local col = M.u32(color);
    local ok = safe(function()
        dl:AddCircle({ cx, cy }, r, col, segments or 16, thickness or 1);
    end);
    if not ok then
        M.rect_outline(dl, cx - r, cy - r, r * 2, r * 2, color, r * 0.5, thickness or 1);
    end
end

--- Small filled dot (tab badges).
function M.dot(dl, cx, cy, r, color)
    if dl == nil then return; end
    local col = M.u32(color);
    local ok = safe(function()
        dl:AddCircleFilled({ cx, cy }, r, col, 12);
    end);
    if not ok then
        M.rect(dl, cx - r, cy - r, r * 2, r * 2, color, r);
    end
end

--- Rounded chip with a 1px border; caller draws the text.
function M.chip(dl, x, y, w, h, color, alpha_bg)
    M.rect(dl, x, y, w, h, M.alpha(color, alpha_bg or 0.16), math.min(h * 0.5, 4));
    M.rect_outline(dl, x, y, w, h, M.alpha(color, 0.55), math.min(h * 0.5, 4), 1);
end

return M;
