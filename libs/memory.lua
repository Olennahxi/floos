--[[
* Memory utilities (adapted from XIUI)
* https://github.com/tirem/XIUI - GNU GPL v3
*
* Thin cache around the D3D8 device pointer used by texture loading.
]]--

local d3d = require('d3d8');

local M = {};

local d3d8dev = nil;

function M.GetD3D8Device()
    if d3d8dev == nil then
        d3d8dev = d3d.get_device();
    end
    return d3d8dev;
end

function M.ResetD3D8Device()
    d3d8dev = nil;
end

return M;
