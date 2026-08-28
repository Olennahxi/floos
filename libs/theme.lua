--[[
* Floos - Theme palettes and config menu styling
* Colors adapted from XIUI config.lua (https://github.com/tirem/XIUI), GPLv3.
]]--

require('common');
local imgui = require('imgui');

local M = {};

-- OceanBlue gold shared by OceanBlue and GreenGold.
local OCEAN_GOLD = { 1.0, 0.886, 0.278, 1.0 };         -- #FFE247
local OCEAN_GOLD_DARK = { 1.0, 0.843, 0.0, 1.0 };      -- #FFD700
local OCEAN_GOLD_DARKER = { 0.85, 0.65, 0.05, 1.0 };
local OCEAN_BORDER_GOLD = { 1.0, 0.886, 0.278, 0.95 };

M.palettes = {
    OceanBlue = {
        gold = OCEAN_GOLD,
        gold_dark = OCEAN_GOLD_DARK,
        gold_darker = OCEAN_GOLD_DARKER,
        bg_dark = { 0.035, 0.12, 0.38, 0.95 },     -- royal blue config bg
        bg_medium = { 0.06, 0.18, 0.48, 1.0 },
        bg_light = { 0.10, 0.26, 0.58, 1.0 },
        bg_lighter = { 0.15, 0.34, 0.70, 1.0 },
        text_light = { 0.92, 0.95, 1.0, 1.0 },
        text_muted = { 0.70, 0.78, 0.92, 1.0 },
        border_dark = { 0.20, 0.35, 0.70, 1.0 },
        border_gold = OCEAN_BORDER_GOLD,
        panel_bg_hex = '#163A9C',
        panel_border_hex = '#FFE247',
        default_bg_opacity = 0.30,
        bar_fill = { 0.25, 0.55, 0.95, 1.0 },
    },
    Plain = {
        -- Black panels / config; white text and separators.
        gold = { 1.0, 1.0, 1.0, 1.0 },
        gold_dark = { 0.85, 0.85, 0.85, 1.0 },
        gold_darker = { 0.65, 0.65, 0.65, 1.0 },
        bg_dark = { 0.0, 0.0, 0.0, 0.95 },
        bg_medium = { 0.08, 0.08, 0.08, 1.0 },
        bg_light = { 0.14, 0.14, 0.14, 1.0 },
        bg_lighter = { 0.22, 0.22, 0.22, 1.0 },
        text_light = { 1.0, 1.0, 1.0, 1.0 },
        text_muted = { 0.70, 0.70, 0.70, 1.0 },
        border_dark = { 1.0, 1.0, 1.0, 0.85 },
        border_gold = { 1.0, 1.0, 1.0, 0.90 },
        panel_bg_hex = '#000000',
        panel_border_hex = '#FFFFFF',
        default_bg_opacity = 0.50,
        bar_fill = { 0.85, 0.85, 0.85, 1.0 },
    },
    DarkGold = {
        gold = { 0.957, 0.855, 0.592, 1.0 },       -- #F4DA97
        gold_dark = { 0.765, 0.684, 0.474, 1.0 },  -- #C3AE79
        gold_darker = { 0.573, 0.512, 0.355, 1.0 }, -- #92835B
        bg_dark = { 0.051, 0.051, 0.051, 0.95 },   -- #0D0D0D
        bg_medium = { 0.098, 0.090, 0.075, 1.0 },  -- #191713
        bg_light = { 0.137, 0.125, 0.106, 1.0 },   -- #23201B
        bg_lighter = { 0.176, 0.161, 0.137, 1.0 }, -- #2D2923
        text_light = { 0.878, 0.855, 0.812, 1.0 }, -- #E0DACF
        text_muted = { 0.6, 0.58, 0.54, 1.0 },
        border_dark = { 0.3, 0.275, 0.235, 1.0 },  -- #4D463C
        border_gold = { 0.957, 0.855, 0.592, 0.85 },
        panel_bg_hex = '#0D0D0D',
        panel_border_hex = '#F4DA97',
        default_bg_opacity = 0.92,
        bar_fill = { 0.22, 0.60, 0.81, 1.0 },
    },
    GreenGold = {
        gold = OCEAN_GOLD,
        gold_dark = OCEAN_GOLD_DARK,
        gold_darker = OCEAN_GOLD_DARKER,
        bg_dark = { 0.02, 0.10, 0.05, 0.95 },      -- deep forest
        bg_medium = { 0.04, 0.16, 0.08, 1.0 },
        bg_light = { 0.07, 0.24, 0.12, 1.0 },
        bg_lighter = { 0.10, 0.32, 0.16, 1.0 },
        text_light = { 0.90, 0.96, 0.90, 1.0 },
        text_muted = { 0.60, 0.75, 0.62, 1.0 },
        border_dark = { 0.15, 0.40, 0.22, 1.0 },
        border_gold = OCEAN_BORDER_GOLD,
        panel_bg_hex = '#0A2E14',
        panel_border_hex = '#FFE247',
        default_bg_opacity = 0.55,
        bar_fill = { 0.25, 0.70, 0.40, 1.0 },
    },
};

-- Per-activity accent. The whole panel (tab underline, hero number, bars,
-- separators) recolors from this so each HELM tab has its own identity.
M.ACTIVITY_ACCENT = {
    mining   = { 1.00, 0.78, 0.30, 1.0 }, -- amber
    logging  = { 0.55, 0.86, 0.46, 1.0 }, -- green
    harvest  = { 0.38, 0.85, 0.78, 1.0 }, -- teal
    excavate = { 1.00, 0.58, 0.34, 1.0 }, -- orange
    hunting  = { 0.96, 0.46, 0.46, 1.0 }, -- crimson
    fishing  = { 0.42, 0.68, 0.96, 1.0 }, -- deep water blue
    digging  = { 0.88, 0.72, 0.44, 1.0 }, -- sand
    clamming = { 0.52, 0.86, 0.90, 1.0 }, -- shallow sea
};

-- Semantic colors for state, shared by every activity.
M.STATE = {
    good    = { 0.46, 0.86, 0.52, 1.0 },
    warn    = { 1.00, 0.74, 0.30, 1.0 },
    bad     = { 0.96, 0.44, 0.44, 1.0 },
    info    = { 0.56, 0.76, 0.98, 1.0 },
    neutral = { 0.86, 0.88, 0.92, 1.0 },
};

--- Accent for an activity tab. Plain stays monochrome by design, and the
--- Appearance toggle can force the palette gold everywhere.
function M.accent_for(act, enabled)
    if M.active_name == 'Plain' then
        return M.colors.text_gold;
    end
    if enabled == false then
        return M.colors.text_gold;
    end
    return M.ACTIVITY_ACCENT[act] or M.colors.text_gold;
end

--- Semantic color, dimmed to the palette text color on Plain.
function M.state_color(name)
    if M.active_name == 'Plain' then
        if name == 'bad' then
            return { 0.75, 0.75, 0.75, 1.0 };
        end
        return M.colors.text_light;
    end
    return M.STATE[name] or M.colors.text_light;
end

-- Display order / labels for the Appearance radio list.
M.THEME_OPTIONS = T{
    { id = 'DarkGold',  label = 'DarkGold (Default)' },
    { id = 'OceanBlue', label = 'OceanBlue' },
    { id = 'Plain',     label = 'Plain' },
    { id = 'GreenGold', label = 'GreenGold' },
};

local function apply_palette(p)
    M.gold = p.gold;
    M.gold_dark = p.gold_dark;
    M.gold_darker = p.gold_darker;
    M.bg_dark = p.bg_dark;
    M.bg_medium = p.bg_medium;
    M.bg_light = p.bg_light;
    M.bg_lighter = p.bg_lighter;
    M.text_light = p.text_light;
    M.text_muted = p.text_muted;
    M.border_dark = p.border_dark;
    M.border_gold = p.border_gold;
    M.panel_bg_hex = p.panel_bg_hex;
    M.panel_border_hex = p.panel_border_hex;
    M.default_bg_opacity = p.default_bg_opacity;

    M.colors = {
        bg_dark       = p.bg_dark,
        bg_mid        = p.bg_medium,
        bg_light      = p.bg_light,
        border        = p.border_gold,
        border_gold   = p.border_gold,
        text          = p.text_light,
        text_light    = p.text_light,
        text_dim      = p.text_muted,
        text_gold     = p.gold,
        accent        = p.gold,
        bar_fill      = p.bar_fill,
    };
end

apply_palette(M.palettes.DarkGold);
M.active_name = 'DarkGold';

--- Switch active palette used by overlays and the config window.
function M.set_active(theme_name)
    local palette = M.palettes[theme_name];
    if palette == nil then
        palette = M.palettes.DarkGold;
        theme_name = 'DarkGold';
    end
    if M.active_name == theme_name then
        return;
    end
    apply_palette(palette);
    M.active_name = theme_name;
end

function M.get_palette(theme_name)
    return M.palettes[theme_name] or M.palettes.DarkGold;
end

function M.hex_to_imgui(hex)
    local clean = hex:gsub('#', '');
    return {
        tonumber(clean:sub(1, 2), 16) / 255,
        tonumber(clean:sub(3, 4), 16) / 255,
        tonumber(clean:sub(5, 6), 16) / 255,
        1.0,
    };
end

-- Prefer first non-nil enum (Ashita 4.3 / ImGui 1.90.9+ renamed several colors).
local function style_col(...)
    for i = 1, select('#', ...) do
        local v = select(i, ...);
        if v ~= nil then
            return v;
        end
    end
    return nil;
end

local function push_style_color(idx, color)
    if idx == nil or color == nil then
        return 0;
    end
    local ok = pcall(function()
        imgui.PushStyleColor(idx, color);
    end);
    if ok then
        return 1;
    end
    -- Some bindings want ImVec4(r,g,b,a) instead of a table.
    if ImVec4 ~= nil and type(color) == 'table' then
        ok = pcall(function()
            imgui.PushStyleColor(idx, ImVec4(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1));
        end);
        if ok then
            return 1;
        end
    end
    return 0;
end

local function push_style_var(idx, value)
    if idx == nil then
        return 0;
    end
    local ok = pcall(function()
        imgui.PushStyleVar(idx, value);
    end);
    if ok then
        return 1;
    end
    if type(value) == 'table' and ImVec2 ~= nil then
        ok = pcall(function()
            imgui.PushStyleVar(idx, ImVec2(value[1] or 0, value[2] or 0));
        end);
        if ok then
            return 1;
        end
    end
    return 0;
end

--- Push ImGui colors/vars for the config editor; pair with pop_style.
function M.apply_style()
    local style = imgui.GetStyle();
    if style ~= nil then
        pcall(function()
            style.WindowBorderSize = 1;
            style.ChildBorderSize = 1;
            style.FrameBorderSize = 1;
            style.TabBorderSize = 1;
        end);
    end

    local g = M.gold;
    local tab_active = { g[1], g[2], g[3], 0.3 };
    local plain = M.active_name == 'Plain';
    local text_disabled = plain and M.text_muted or M.gold_dark;

    local colors = 0;
    colors = colors + push_style_color(ImGuiCol_WindowBg, M.bg_dark);
    colors = colors + push_style_color(ImGuiCol_ChildBg, { 0, 0, 0, 0 });
    colors = colors + push_style_color(ImGuiCol_TitleBg, M.bg_medium);
    colors = colors + push_style_color(ImGuiCol_TitleBgActive, M.bg_light);
    colors = colors + push_style_color(ImGuiCol_TitleBgCollapsed, M.bg_dark);
    colors = colors + push_style_color(ImGuiCol_FrameBg, M.bg_medium);
    colors = colors + push_style_color(ImGuiCol_FrameBgHovered, M.bg_light);
    colors = colors + push_style_color(ImGuiCol_FrameBgActive, M.bg_lighter);
    colors = colors + push_style_color(ImGuiCol_Header, M.bg_light);
    colors = colors + push_style_color(ImGuiCol_HeaderHovered, M.bg_lighter);
    colors = colors + push_style_color(ImGuiCol_HeaderActive, tab_active);
    colors = colors + push_style_color(ImGuiCol_Border, M.border_gold);
    colors = colors + push_style_color(ImGuiCol_Text, M.text_light);
    colors = colors + push_style_color(ImGuiCol_TextDisabled, text_disabled);
    colors = colors + push_style_color(ImGuiCol_Button, M.bg_medium);
    colors = colors + push_style_color(ImGuiCol_ButtonHovered, M.bg_light);
    colors = colors + push_style_color(ImGuiCol_ButtonActive, M.bg_lighter);
    colors = colors + push_style_color(ImGuiCol_CheckMark, M.gold);
    colors = colors + push_style_color(ImGuiCol_SliderGrab, M.gold_dark);
    colors = colors + push_style_color(ImGuiCol_SliderGrabActive, M.gold);
    colors = colors + push_style_color(ImGuiCol_ScrollbarBg, M.bg_medium);
    colors = colors + push_style_color(ImGuiCol_ScrollbarGrab, M.bg_lighter);
    colors = colors + push_style_color(ImGuiCol_ScrollbarGrabHovered, M.border_dark);
    colors = colors + push_style_color(ImGuiCol_ScrollbarGrabActive, M.gold_dark);
    colors = colors + push_style_color(ImGuiCol_Separator, M.border_dark);
    colors = colors + push_style_color(ImGuiCol_PopupBg, M.bg_medium);
    colors = colors + push_style_color(ImGuiCol_Tab, M.bg_medium);
    colors = colors + push_style_color(ImGuiCol_TabHovered, M.bg_light);
    -- Renamed in ImGui 1.90.9 (Ashita 4.3): TabActive / TabUnfocused*.
    colors = colors + push_style_color(style_col(ImGuiCol_TabSelected, ImGuiCol_TabActive), tab_active);
    colors = colors + push_style_color(style_col(ImGuiCol_TabDimmed, ImGuiCol_TabUnfocused), M.bg_dark);
    colors = colors + push_style_color(style_col(ImGuiCol_TabDimmedSelected, ImGuiCol_TabUnfocusedActive), M.bg_medium);
    colors = colors + push_style_color(ImGuiCol_ResizeGrip, M.gold_darker);
    colors = colors + push_style_color(ImGuiCol_ResizeGripHovered, M.gold_dark);
    colors = colors + push_style_color(ImGuiCol_ResizeGripActive, M.gold);

    local vars = 0;
    vars = vars + push_style_var(ImGuiStyleVar_WindowPadding, { 12, 12 });
    vars = vars + push_style_var(ImGuiStyleVar_FramePadding, { 6, 4 });
    vars = vars + push_style_var(ImGuiStyleVar_ItemSpacing, { 8, 6 });
    vars = vars + push_style_var(ImGuiStyleVar_FrameRounding, 4.0);
    vars = vars + push_style_var(ImGuiStyleVar_WindowRounding, 6.0);
    vars = vars + push_style_var(ImGuiStyleVar_ChildRounding, 4.0);
    vars = vars + push_style_var(ImGuiStyleVar_PopupRounding, 4.0);
    vars = vars + push_style_var(ImGuiStyleVar_ScrollbarRounding, 4.0);
    vars = vars + push_style_var(ImGuiStyleVar_GrabRounding, 4.0);

    return { colors = colors, vars = vars };
end

function M.pop_style(counts)
    counts = counts or { colors = 0, vars = 0 };
    if (counts.vars or 0) > 0 then
        imgui.PopStyleVar(counts.vars);
    end
    if (counts.colors or 0) > 0 then
        imgui.PopStyleColor(counts.colors);
    end
end

return M;
