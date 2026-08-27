--[[
* Floos - HELM fatigue period tracking
*
* The server clears your gathering cap on a schedule. Nothing in the client
* announces it, so this learns the schedule by watching for the one thing that
* proves a reset happened: you were at the cap, and then you successfully
* gathered again. That transition can only occur after a reset, so each one is
* a free, unambiguous observation.
*
* One observation is enough to predict the next reset. More observations let us
* check that the period is actually what we think it is, and say so when it is
* not.
]]--

require('common');

local M = {};

M.DEFAULT_PERIOD_H = 24;
M.MAX_OBSERVATIONS = 12;

-- How far an observation may drift from the predicted slot and still be
-- considered "on schedule", in seconds.
local TOLERANCE = 20 * 60;

local function period_secs(state)
    local hours = tonumber(state and state.period_hours) or M.DEFAULT_PERIOD_H;
    if hours <= 0 then
        hours = M.DEFAULT_PERIOD_H;
    end
    return hours * 3600;
end

M.period_secs = period_secs;

local function sorted_observations(state)
    local out = {};
    if state ~= nil and type(state.observations) == 'table' then
        for _, v in ipairs(state.observations) do
            local n = tonumber(v);
            if n ~= nil and n > 0 then
                out[#out + 1] = n;
            end
        end
    end
    table.sort(out);
    return out;
end

M.observations = sorted_observations;

--- Record a reset that we just witnessed.
function M.record(state, epoch)
    epoch = tonumber(epoch);
    if state == nil or epoch == nil or epoch <= 0 then
        return false;
    end
    if type(state.observations) ~= 'table' then
        state.observations = {};
    end

    -- Ignore a duplicate sighting of the same reset.
    for _, v in ipairs(state.observations) do
        if math.abs((tonumber(v) or 0) - epoch) < 60 then
            return false;
        end
    end

    state.observations[#state.observations + 1] = epoch;
    while #state.observations > M.MAX_OBSERVATIONS do
        table.remove(state.observations, 1);
    end
    return true;
end

--- When the next reset lands, or nil if we have never seen one.
function M.predict_next(state, now)
    now = tonumber(now) or 0;
    local obs = sorted_observations(state);
    if #obs == 0 then
        return nil;
    end
    local period = period_secs(state);
    local t = obs[#obs];
    if t > now then
        return t;
    end
    -- Jump forward in whole periods rather than looping one at a time, so a
    -- month-old observation still resolves instantly.
    local elapsed = now - t;
    t = t + (math.floor(elapsed / period) + 1) * period;
    return t;
end

--- Seconds until the next reset, or nil when unknown.
function M.time_left(state, now)
    local nxt = M.predict_next(state, now);
    if nxt == nil then
        return nil;
    end
    return math.max(0, nxt - (tonumber(now) or 0));
end

--- How much to trust the prediction.
--- 'none'     - never seen a reset
--- 'learning' - one observation, so the period is assumed rather than measured
--- 'good'     - observations line up with the configured period
--- 'unclear'  - observations do not fit the period; the setting is probably wrong
function M.confidence(state)
    local obs = sorted_observations(state);
    if #obs == 0 then
        return 'none';
    end
    if #obs == 1 then
        return 'learning';
    end

    local period = period_secs(state);
    local fits = 0;
    for i = 2, #obs do
        local gap = obs[i] - obs[i - 1];
        -- A gap should be close to a whole number of periods.
        local periods = gap / period;
        local nearest = math.floor(periods + 0.5);
        if nearest >= 1 and math.abs(gap - (nearest * period)) <= TOLERANCE then
            fits = fits + 1;
        end
    end
    if fits >= (#obs - 1) * 0.6 then
        return 'good';
    end
    return 'unclear';
end

--- Best guess at the period actually being observed, in hours. Useful for
--- telling the user their configured period looks wrong.
function M.measured_period_hours(state)
    local obs = sorted_observations(state);
    if #obs < 2 then
        return nil;
    end
    local gaps = {};
    for i = 2, #obs do
        local gap = obs[i] - obs[i - 1];
        if gap > 600 then
            gaps[#gaps + 1] = gap;
        end
    end
    if #gaps == 0 then
        return nil;
    end
    table.sort(gaps);
    local mid = gaps[math.floor((#gaps + 1) / 2)];
    return mid / 3600;
end

--- Has the period rolled over since `since`? Used to auto-clear the counter
--- even when the player was not logged in at the moment it happened.
function M.rolled_over(state, since, now)
    since = tonumber(since) or 0;
    now = tonumber(now) or 0;
    if since <= 0 or now <= since then
        return false;
    end
    local obs = sorted_observations(state);
    if #obs == 0 then
        return false;
    end
    local period = period_secs(state);
    local anchor = obs[#obs];

    -- Slot index of each moment relative to the anchor. A change of slot means
    -- a reset boundary was crossed in between.
    local function slot(t)
        return math.floor((t - anchor) / period);
    end
    return slot(now) > slot(since);
end

function M.clear(state)
    if state ~= nil then
        state.observations = {};
    end
end

return M;
