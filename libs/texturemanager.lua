--[[
* Texture manager — asset loading only (adapted from XIUI)
* https://github.com/tirem/XIUI — GNU GPL v3
]]--

require('common');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local memory = require('libs.memory');

local M = {};

local texturesByKey = {};
local pendingReleases = {};

local function deferRelease(entry)
    if entry ~= nil then
        pendingReleases[#pendingReleases + 1] = entry;
    end
end

local function loadTextureFromFile(path)
    local device = memory.GetD3D8Device();
    if device == nil then
        return nil;
    end

    local fullPath;
    if path:sub(1, 1) == '/' or path:sub(1, 1) == '\\' or path:match('^%a:') then
        fullPath = path;
    else
        fullPath = string.format('%s/assets/%s', addon.path, path);
    end

    if not fullPath:match('%.[^/\\]+$') then
        fullPath = fullPath .. '.png';
    end

    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = ffi.C.D3DXCreateTextureFromFileA(device, fullPath, dx_texture_ptr);
    if res ~= ffi.C.S_OK then
        return nil;
    end

    return {
        image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0])),
    };
end

local function getOrCreate(key, loader)
    local entry = texturesByKey[key];
    if entry then
        return entry.texture;
    end

    local success, texture = pcall(loader);
    if not success or texture == nil then
        return nil;
    end

    texturesByKey[key] = {
        key = key,
        texture = texture,
    };

    return texture;
end

function M.getFileTexture(path)
    if path == nil or path == '' then
        return nil;
    end

    local key = 'file_' .. path;
    return getOrCreate(key, function ()
        return loadTextureFromFile(path);
    end);
end

function M.getTexturePtr(texture)
    if texture and texture.image then
        return tonumber(ffi.cast('uint32_t', texture.image));
    end
    return nil;
end

function M.FlushPendingReleases()
    if #pendingReleases > 0 then
        pendingReleases = {};
    end
end

function M.clear()
    for _, entry in pairs(texturesByKey) do
        deferRelease(entry);
    end
    texturesByKey = {};
end

return M;
