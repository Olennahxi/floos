--[[
* Drawing helpers (adapted from XIUI)
* https://github.com/tirem/XIUI - GNU GPL v3
]]--

local imgui = require('imgui');

local M = {};

-- Background draw list so panel fills sit under ImGui text (avoids washed-out labels).
function M.GetUIDrawList()
    return imgui.GetBackgroundDrawList();
end

return M;
