--[[
* Progress bar renderer (adapted from XIUI)
* https://github.com/tirem/XIUI — GNU GPL v3
]]--

require('common');
local colorLib = require('libs.color');
local memory = require('libs.memory');
local drawing = require('libs.drawing');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d = require('d3d8');
local bitmap = require('libs.bitmap');

local M = {
    backgroundGradientStartColor = '#01122b',
    backgroundGradientEndColor = '#061c39',
    backgroundRounding = 0,
    foregroundRounding = 0,
    gradientTexturesByKey = {},
    gradientTextures = {},
    colorU32Cache = {},
    MAX_GRADIENT_CACHE_SIZE = 50,
    EVICTION_COUNT = 10,
};

local style_provider = nil;

function M.set_style_provider(fn)
    style_provider = fn;
end

local function get_style()
    if style_provider then
        return style_provider();
    end
    return {
        show_bookends = true,
        bookend_size = 10,
        bar_border_thickness = 2,
        no_bookend_rounding = 4,
        background_gradient_start = M.backgroundGradientStartColor,
        background_gradient_end = M.backgroundGradientEndColor,
        bookend_gradient_start = '#576C92',
        bookend_gradient_mid = '#B7C9FF',
        bookend_gradient_stop = '#576C92',
    };
end

local hex2rgba = colorLib.hex2rgba;
local hex2rgb = colorLib.hex2rgb;

local function GetCachedColorU32(hexColor)
    local cached = M.colorU32Cache[hexColor];
    if cached then
        return cached;
    end
    local r, g, b, a = hex2rgba(hexColor);
    cached = imgui.GetColorU32({ r / 255, g / 255, b / 255, a / 255 });
    M.colorU32Cache[hexColor] = cached;
    return cached;
end

local function EvictOldestEntries()
    local count = #M.gradientTextures;
    if count <= M.MAX_GRADIENT_CACHE_SIZE then
        return;
    end

    table.sort(M.gradientTextures, function (a, b)
        return (a.lastUsed or 0) < (b.lastUsed or 0);
    end);

    local toRemove = math.min(M.EVICTION_COUNT, count - M.MAX_GRADIENT_CACHE_SIZE + M.EVICTION_COUNT);
    for _ = 1, toRemove do
        local entry = M.gradientTextures[1];
        if entry then
            M.gradientTexturesByKey[entry.cacheKey] = nil;
            table.remove(M.gradientTextures, 1);
        end
    end
end

local function MakeGradientBitmap(startColor, endColor)
    local height = 100;
    local image = bitmap:new(1, height);
    local sr, sg, sb, sa = hex2rgba(startColor);
    local er, eg, eb, ea = hex2rgba(endColor);

    for pixel = 1, height do
        image:setPixelColor(1, (height - pixel) + 1, {
            sr + (er - sr) * (pixel / height),
            sg + (eg - sg) * (pixel / height),
            sb + (eb - sb) * (pixel / height),
            sa + (ea - sa) * (pixel / height),
        });
    end

    return image;
end

local function MakeThreeStepGradientBitmap(startColor, midColor, endColor)
    local height = 100;
    local image = bitmap:new(1, height);
    local sr, sg, sb, sa = hex2rgba(startColor);
    local mr, mg, mb, ma = hex2rgba(midColor);
    local er, eg, eb, ea = hex2rgba(endColor);

    for pixel = 1, height do
        local red, green, blue, alpha;
        local progress = pixel / height;

        if progress <= 0.5 then
            local t = progress * 2;
            red = sr + (mr - sr) * t;
            green = sg + (mg - sg) * t;
            blue = sb + (mb - sb) * t;
            alpha = sa + (ma - sa) * t;
        else
            local t = (progress - 0.5) * 2;
            red = mr + (er - mr) * t;
            green = mg + (eg - mg) * t;
            blue = mb + (eb - mb) * t;
            alpha = ma + (ea - ma) * t;
        end

        image:setPixelColor(1, (height - pixel) + 1, { red, green, blue, alpha });
    end

    return image;
end

local function GetGradient(startColor, endColor)
    local cacheKey = startColor .. '|' .. endColor;
    local texture = M.gradientTexturesByKey[cacheKey];

    if texture then
        texture.lastUsed = os.clock();
    else
        local device = memory.GetD3D8Device();
        if device == nil then
            return nil;
        end

        local image = MakeGradientBitmap(startColor, endColor);
        local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        local res = ffi.C.D3DXCreateTextureFromFileInMemory(device, image:binary(), #image:binary(), texture_ptr);
        if res ~= ffi.C.S_OK then
            return nil;
        end

        texture = {
            texture = ffi.new('IDirect3DTexture8*', texture_ptr[0]),
            cacheKey = cacheKey,
            lastUsed = os.clock(),
        };
        d3d.gc_safe_release(texture.texture);
        M.gradientTexturesByKey[cacheKey] = texture;
        table.insert(M.gradientTextures, texture);
        EvictOldestEntries();
    end

    if texture == nil or texture.texture == nil then
        return nil;
    end

    return tonumber(ffi.cast('uint32_t', texture.texture));
end

local function GetThreeStepGradient(startColor, midColor, endColor)
    local cacheKey = startColor .. '|' .. midColor .. '|' .. endColor;
    local texture = M.gradientTexturesByKey[cacheKey];

    if texture then
        texture.lastUsed = os.clock();
    else
        local device = memory.GetD3D8Device();
        if device == nil then
            return nil;
        end

        local image = MakeThreeStepGradientBitmap(startColor, midColor, endColor);
        local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        local res = ffi.C.D3DXCreateTextureFromFileInMemory(device, image:binary(), #image:binary(), texture_ptr);
        if res ~= ffi.C.S_OK then
            return nil;
        end

        texture = {
            texture = ffi.new('IDirect3DTexture8*', texture_ptr[0]),
            cacheKey = cacheKey,
            lastUsed = os.clock(),
        };
        d3d.gc_safe_release(texture.texture);
        M.gradientTexturesByKey[cacheKey] = texture;
        table.insert(M.gradientTextures, texture);
        EvictOldestEntries();
    end

    if texture == nil or texture.texture == nil then
        return nil;
    end

    return tonumber(ffi.cast('uint32_t', texture.texture));
end

function M.DrawBar(startPosition, endPosition, gradientStart, gradientEnd, rounding, cornerFlags, drawList)
    local gradient = GetGradient(gradientStart, gradientEnd);
    if gradient == nil then
        return;
    end

    drawList = drawList or imgui.GetWindowDrawList();
    drawList:AddImageRounded(gradient, startPosition, endPosition, { 0, 0 }, { 1, 1 }, IM_COL32_WHITE, rounding or 0, cornerFlags);
end

function M.DrawBookends(positionStartX, positionStartY, width, height, drawList, style)
    style = style or get_style();
    local baseBookendWidth = style.bookend_size or 10;
    local radius = height / 2;
    local bookendWidth = math.max(baseBookendWidth, radius);
    drawList = drawList or imgui.GetWindowDrawList();

    local gradientTexture = GetThreeStepGradient(
        style.bookend_gradient_start,
        style.bookend_gradient_mid,
        style.bookend_gradient_stop
    );
    if gradientTexture == nil then
        return bookendWidth;
    end

    drawList:AddImageRounded(
        gradientTexture,
        { positionStartX, positionStartY },
        { positionStartX + bookendWidth, positionStartY + height },
        { 0, 0 }, { 1, 1 },
        IM_COL32_WHITE,
        radius,
        ImDrawCornerFlags_Left
    );

    drawList:AddImageRounded(
        gradientTexture,
        { positionStartX + width - bookendWidth, positionStartY },
        { positionStartX + width, positionStartY + height },
        { 0, 0 }, { 1, 1 },
        IM_COL32_WHITE,
        radius,
        ImDrawCornerFlags_Right
    );

    return bookendWidth;
end

function M.ProgressBar(percentList, dimensions, options)
    options = options or {};
    local style = get_style();
    local decorate = options.decorate;
    if decorate == nil then
        decorate = style.show_bookends;
    end

    local drawList = options.drawList or drawing.GetUIDrawList();
    local positionStartX, positionStartY;

    if options.absolutePosition then
        positionStartX = options.absolutePosition[1];
        positionStartY = options.absolutePosition[2];
    else
        positionStartX, positionStartY = imgui.GetCursorScreenPos();
    end

    local width = dimensions[1];
    local height = dimensions[2];
    if width <= 0 then
        width = imgui.GetContentRegionAvail();
    end

    local contentWidth = width;
    local contentPositionStartX = positionStartX;
    local contentPositionStartY = positionStartY;
    local rounding;

    if decorate then
        local bookendWidth = M.DrawBookends(positionStartX, positionStartY, width, height, drawList, style);
        contentWidth = width - (bookendWidth * 2);
        contentPositionStartX = contentPositionStartX + bookendWidth;
    end

    local bgGradientStart = style.background_gradient_start or M.backgroundGradientStartColor;
    local bgGradientEnd = style.background_gradient_end or M.backgroundGradientEndColor;

    if options.backgroundGradientOverride then
        bgGradientStart = options.backgroundGradientOverride[1];
        bgGradientEnd = options.backgroundGradientOverride[2];
    end

    rounding = decorate and M.backgroundRounding or style.no_bookend_rounding;
    M.DrawBar(
        { contentPositionStartX, contentPositionStartY },
        { contentPositionStartX + contentWidth, contentPositionStartY + height },
        bgGradientStart,
        bgGradientEnd,
        rounding,
        nil,
        drawList
    );

    local progressOffset = 0;
    for i, percentData in ipairs(percentList) do
        local percent = math.clamp(percentData[1], 0, 1);
        if percent > 0 then
            local startColor = percentData[2][1];
            local endColor = percentData[2][2];
            local progressWidth = contentWidth * percent;
            local startX = contentPositionStartX + progressOffset;
            local endX = startX + progressWidth;
            local cornerFlags = ImDrawCornerFlags_All;

            rounding = decorate and M.foregroundRounding or style.no_bookend_rounding;
            M.DrawBar({ startX, contentPositionStartY }, { endX, contentPositionStartY + height }, startColor, endColor, rounding, cornerFlags, drawList);
            progressOffset = progressOffset + progressWidth;
        end
    end

    local borderColor = bgGradientStart;
    local bgColorU32 = GetCachedColorU32(borderColor);
    local innerBorderThickness = style.bar_border_thickness or 2;
    local baseRounding = decorate and (height / 2) or (style.no_bookend_rounding or 0);

    if innerBorderThickness > 0 then
        local innerOffset = innerBorderThickness / 2 + 0.5;
        drawList:AddRect(
            { positionStartX - innerOffset, positionStartY - innerOffset },
            { positionStartX + width + innerOffset, positionStartY + height + innerOffset },
            bgColorU32,
            baseRounding + innerOffset,
            15,
            innerBorderThickness
        );
    end

    if not options.absolutePosition then
        local borderExtent = innerBorderThickness > 0 and (innerBorderThickness + 1) or 0;
        imgui.Dummy({ width + borderExtent, height + borderExtent });
    end
end

function M.Cleanup()
    M.gradientTexturesByKey = {};
    M.gradientTextures = {};
    M.colorU32Cache = {};
    collectgarbage('collect');
end

return M;
