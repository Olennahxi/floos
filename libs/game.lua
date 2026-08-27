--[[
* Floos - Client login / world state helpers
*
* Ashita GetLoginStatus():
*   2 = in the game world (also true during brief zone loads when
*       GetPlayerEntity() may be nil)
*   anything else = title / char select / not ready
]]--

local M = {};

local LOGIN_STATUS_INGAME = 2;

function M.get_login_status()
    local ok, status = pcall(function()
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        if player == nil then
            return nil;
        end
        return player:GetLoginStatus();
    end);
    if not ok then
        return nil;
    end
    return status;
end

-- True while in world. Stays true across zone loads even if craft APIs blip.
function M.is_logged_in()
    return M.get_login_status() == LOGIN_STATUS_INGAME;
end

return M;
