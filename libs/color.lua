--[[
* Color utilities (adapted from XIUI)
* https://github.com/tirem/XIUI - GNU GPL v3
]]--

local M = {};

local hexToImGuiCache = {};

function M.InvalidateColorCaches()
    hexToImGuiCache = {};
end

function M.hex2rgb(hex)
    local clean = hex:gsub('#', '');
    return tonumber('0x' .. clean:sub(1, 2)), tonumber('0x' .. clean:sub(3, 4)), tonumber('0x' .. clean:sub(5, 6));
end

function M.hex2rgba(hex)
    local clean = hex:gsub('#', '');
    local r = tonumber('0x' .. clean:sub(1, 2));
    local g = tonumber('0x' .. clean:sub(3, 4));
    local b = tonumber('0x' .. clean:sub(5, 6));
    local a = 255;
    if #clean >= 8 then
        a = tonumber('0x' .. clean:sub(7, 8));
    end
    return r, g, b, a;
end

function M.ARGBToImGui(argb)
    local a = bit.rshift(bit.band(argb, 0xFF000000), 24) / 255;
    local r = bit.rshift(bit.band(argb, 0x00FF0000), 16) / 255;
    local g = bit.rshift(bit.band(argb, 0x0000FF00), 8) / 255;
    local b = bit.band(argb, 0x000000FF) / 255;
    return { r, g, b, a };
end

function M.HexToImGui(hex)
    local cached = hexToImGuiCache[hex];
    if cached then
        return cached;
    end

    local cleanHex = hex:gsub('#', '');
    local r = tonumber(cleanHex:sub(1, 2), 16) / 255;
    local g = tonumber(cleanHex:sub(3, 4), 16) / 255;
    local b = tonumber(cleanHex:sub(5, 6), 16) / 255;
    local a = 1.0;
    if #cleanHex == 8 then
        a = tonumber(cleanHex:sub(7, 8), 16) / 255;
    end

    local result = { r, g, b, a };
    hexToImGuiCache[hex] = result;
    return result;
end

function M.HexToARGB(hexString, alpha)
    hexString = hexString:gsub('#', '');
    local r = tonumber(hexString:sub(1, 2), 16);
    local g = tonumber(hexString:sub(3, 4), 16);
    local b = tonumber(hexString:sub(5, 6), 16);
    local a = alpha or 0xFF;
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(r, 16),
        bit.lshift(g, 8),
        b
    );
end

function M.ARGBToU32(argb)
    if imgui and imgui.GetColorU32 then
        return imgui.GetColorU32(M.ARGBToImGui(argb));
    end

    local a = bit.band(bit.rshift(argb, 24), 0xFF);
    local r = bit.band(bit.rshift(argb, 16), 0xFF);
    local g = bit.band(bit.rshift(argb, 8), 0xFF);
    local b = bit.band(argb, 0xFF);
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(b, 16),
        bit.lshift(g, 8),
        r
    );
end

return M;
