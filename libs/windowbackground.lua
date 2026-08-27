--[[
* Window background renderer (adapted from XIUI)
* https://github.com/tirem/XIUI — GNU GPL v3
]]--

require('common');
local imgui = require('imgui');
local colorLib = require('libs.color');
local TextureManager = require('libs.texturemanager');

local M = {};

local DEFAULT_PADDING = 8;
local DEFAULT_BORDER_SIZE = 21;
local DEFAULT_BG_OFFSET = 1;
local SOURCE_CORNER_SIZE = 21;
local SOURCE_FULL_SIZE = 491;
local CORNER_UV = SOURCE_CORNER_SIZE / SOURCE_FULL_SIZE;

local tintCache = {};

local function IsWindowTheme(themeName)
    if themeName == nil then
        return false;
    end
    return themeName:match('^Window%d+$') ~= nil;
end

local function ApplyOpacityToColor(color, opacity)
    local alphaByte = math.floor((opacity or 1.0) * 255);
    local rgb = bit.band(color or 0xFFFFFFFF, 0x00FFFFFF);
    return bit.bor(bit.lshift(alphaByte, 24), rgb);
end

local function ResolveTint(color, opacity)
    if opacity ~= nil then
        return ApplyOpacityToColor(color or 0xFFFFFFFF, opacity);
    end
    return color or 0xFFFFFFFF;
end

local function TintU32(argb)
    local v = tintCache[argb];
    if v ~= nil then
        return v;
    end
    v = imgui.GetColorU32(colorLib.ARGBToImGui(argb));
    tintCache[argb] = v;
    return v;
end

local function LoadPiecePtr(theme, piece)
    local tex = TextureManager.getFileTexture(string.format('backgrounds/%s-%s', theme, piece));
    if tex == nil then
        return nil;
    end
    return TextureManager.getTexturePtr(tex);
end

local function ComputeBgRect(x, y, w, h, padding, paddingY)
    return x - padding, y - paddingY, w + (padding * 2), h + (paddingY * 2);
end

local function DrawScaledBackground(drawList, ptr, bgX, bgY, bgW, bgH, bgScale, tint)
    if bgScale <= 0 then
        return;
    end

    if bgScale >= 1.0 then
        local uvMax = 1.0 / bgScale;
        drawList:AddImage(ptr, { bgX, bgY }, { bgX + bgW, bgY + bgH }, { 0, 0 }, { uvMax, uvMax }, tint);
        return;
    end

    local tileW = bgW * bgScale;
    local tileH = bgH * bgScale;
    local cols = math.ceil(bgW / tileW);
    local rows = math.ceil(bgH / tileH);

    for row = 0, rows - 1 do
        local y = bgY + row * tileH;
        local th = math.min(tileH, bgY + bgH - y);
        local uvMaxY = th / tileH;

        for col = 0, cols - 1 do
            local x = bgX + col * tileW;
            local tw = math.min(tileW, bgX + bgW - x);
            local uvMaxX = tw / tileW;
            drawList:AddImage(ptr, { x, y }, { x + tw, y + th }, { 0, 0 }, { uvMaxX, uvMaxY }, tint);
        end
    end
end

function M.DrawBackground(drawList, x, y, w, h, options)
    if drawList == nil then
        return;
    end

    options = options or {};
    local theme = options.theme or 'Window1';
    if theme == '-None-' then
        return;
    end

    local padding = options.padding or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;
    local bgColor = options.bgColor or 0xFFFFFFFF;
    local bgScale = options.bgScale or 1.0;

    local bgX, bgY, bgW, bgH = ComputeBgRect(x, y, w, h, padding, paddingY);
    local ptr = LoadPiecePtr(theme, 'bg');
    if ptr == nil then
        return;
    end

    local tint = TintU32(ResolveTint(bgColor, options.bgOpacity));
    DrawScaledBackground(drawList, ptr, bgX, bgY, bgW, bgH, bgScale, tint);
end

function M.DrawBorders(drawList, x, y, w, h, options)
    if drawList == nil then
        return;
    end

    options = options or {};
    local theme = options.theme or 'Window1';
    if not IsWindowTheme(theme) then
        return;
    end

    local padding = options.padding or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;
    local borderSize = options.borderSize or DEFAULT_BORDER_SIZE;
    local bgOffset = options.bgOffset or DEFAULT_BG_OFFSET;
    local borderScale = options.borderScale or 1.0;
    local borderColor = options.borderColor or 0xFFFFFFFF;

    local bgX, bgY, bgW, bgH = ComputeBgRect(x, y, w, h, padding, paddingY);
    local tint = TintU32(ResolveTint(borderColor, options.borderOpacity));
    local pieceSize = borderSize * borderScale;
    local offset = bgOffset * borderScale;

    local brX = bgX + bgW - math.floor(pieceSize - offset);
    local brY = bgY + bgH - math.floor(pieceSize - offset);
    local brPtr = LoadPiecePtr(theme, 'br');
    if brPtr ~= nil then
        drawList:AddImage(brPtr, { brX, brY }, { brX + pieceSize, brY + pieceSize }, { 0, 0 }, { 1, 1 }, tint);
    end

    local trX = brX;
    local trY = bgY - offset;
    local trH = brY - trY;
    local trPtr = LoadPiecePtr(theme, 'tr');
    if trPtr ~= nil then
        drawList:AddImage(trPtr, { trX, trY }, { trX + pieceSize, trY + pieceSize }, { 0, 0 }, { 1, CORNER_UV }, tint);
        local armH = trH - pieceSize;
        if armH > 0 then
            drawList:AddImage(trPtr, { trX, trY + pieceSize }, { trX + pieceSize, trY + trH }, { 0, CORNER_UV }, { 1, 1 }, tint);
        end
    end

    local tlX = bgX - offset;
    local tlY = bgY - offset;
    local tlW = trX - tlX;
    local tlPtr = LoadPiecePtr(theme, 'tl');
    if tlPtr ~= nil then
        drawList:AddImage(tlPtr, { tlX, tlY }, { tlX + pieceSize, tlY + pieceSize }, { 0, 0 }, { CORNER_UV, CORNER_UV }, tint);
        local armW = tlW - pieceSize;
        if armW > 0 then
            drawList:AddImage(tlPtr, { tlX + pieceSize, tlY }, { tlX + tlW, tlY + pieceSize }, { CORNER_UV, 0 }, { 1, CORNER_UV }, tint);
        end
        local armH = trH - pieceSize;
        if armH > 0 then
            drawList:AddImage(tlPtr, { tlX, tlY + pieceSize }, { tlX + pieceSize, tlY + trH }, { 0, CORNER_UV }, { CORNER_UV, 1 }, tint);
        end
    end

    local blX = tlX;
    local blY = brY;
    local blPtr = LoadPiecePtr(theme, 'bl');
    if blPtr ~= nil then
        drawList:AddImage(blPtr, { blX, blY }, { blX + pieceSize, blY + pieceSize }, { 0, 0 }, { CORNER_UV, 1 }, tint);
        local armW = tlW - pieceSize;
        if armW > 0 then
            drawList:AddImage(blPtr, { blX + pieceSize, blY }, { blX + tlW, blY + pieceSize }, { CORNER_UV, 0 }, { 1, 1 }, tint);
        end
    end
end

function M.Draw(drawList, x, y, w, h, options)
    M.DrawBackground(drawList, x, y, w, h, options);
    M.DrawBorders(drawList, x, y, w, h, options);
end

return M;
