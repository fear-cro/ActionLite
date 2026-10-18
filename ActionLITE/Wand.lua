local ADDON, AL = ...

-- Fear-Cro: wand timing shared by Mage, Priest and Warlock.
-- This only controls recommendations; it never casts or stops a spell.
if AL.playerClass ~= "MAGE" and AL.playerClass ~= "PRIEST" and AL.playerClass ~= "WARLOCK" then return end

local shot = { pendingUntil = 0, untilTime = 0, completed = {} }
local cachedPeriod, repeatActive, stopSuggestion = nil, false, false

local function Public(value)
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        if not ok or not readable then return false end
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    return true
end

local function Number(value)
    if Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge then return value end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end

local function ShootID()
    local ref = AL.rangeSpellRefs and AL.rangeSpellRefs.Shoot
    return Number(ref and ref.id) or 5019
end

local function IsShoot(value)
    if not Public(value) then return false end
    if type(value) == "number" then return value == 5019 or value == ShootID() end
    return type(value) == "string" and (value == "Shoot"
        or AL.englishNames and AL.englishNames[value] == "Shoot") or false
end

local function GUID(value)
    if Public(value) and type(value) == "string" and value:find("^Cast%-") then return value end
end

local function RefreshPeriod()
    local speed = Number(Call(UnitRangedDamage, "player"))
    if speed and speed >= 0.2 and speed <= 10 then cachedPeriod = speed end
end

function AL.WandPeriod()
    RefreshPeriod()
    if cachedPeriod then return cachedPeriod end
    local info = Call(C_Spell and C_Spell.GetSpellInfo, ShootID())
    local ms = Public(info) and type(info) == "table" and Number(info.castTime) or nil
    if not ms then local _, _, _, legacy = Call(GetSpellInfo, ShootID()); ms = Number(legacy) end
    if ms and ms >= 200 and ms <= 10000 then return ms / 1000 end
    return 1.5 -- only when the cast timer and cached weapon speed are unavailable
end

local function CastWindow(confirmed)
    for _, key in ipairs({ "UnitCastingInfo", "UnitChannelInfo" }) do
        local name, _, _, started, ending = Call(_G[key], "player")
        if IsShoot(name) or confirmed and not Public(name) then
            started, ending = Number(started), Number(ending)
            if started and ending and ending > started then return started / 1000, ending / 1000 end
        end
    end
end

local function CooldownRemaining()
    local info = Call(C_Spell and C_Spell.GetSpellCooldown, ShootID())
    local start, duration
    if Public(info) and type(info) == "table" then
        start, duration = Number(info.startTime), Number(info.duration)
    end
    if not start or not duration then
        local a, b = Call(GetSpellCooldown, ShootID())
        start, duration = Number(a), Number(b)
    end
    if start and duration and start > 0 and duration > 0 then
        return math.max(0, start + duration - GetTime())
    end
    return 0
end

function AL.WandAutoRepeatActive()
    for _, fn in pairs({ IsAutoRepeatSpell, C_Spell and C_Spell.IsAutoRepeatSpell }) do
        local active = Call(fn, ShootID())
        if Public(active) and type(active) == "boolean" then repeatActive = active; return active end
    end
    local player = _G.Action and _G.Action.Player
    if Public(player) and type(player) == "table" then
        local active = Call(player.IsShooting, player)
        if Public(active) and type(active) == "boolean" then repeatActive = active; return active end
    end
    return repeatActive
end

function AL.WandCasting()
    local _, ending = CastWindow()
    if ending and ending > GetTime() then return true end
    return shot.pendingUntil > GetTime() or (shot.castingUntil or 0) > GetTime()
end

function AL.WandRecoveryRemaining()
    return math.max(0, shot.untilTime - GetTime(), CooldownRemaining())
end

function AL.WandReady(stopping)
    if shot.pendingUntil > GetTime() then return false, "Wand command pending" end
    if stopping then
        if AL.WandAutoRepeatActive() then return true end
        return false, "Wand stopped"
    end
    if AL.WandCasting() then return false, "Wand shot" end
    if AL.WandAutoRepeatActive() then return false, "Wand active" end
    if AL.WandRecoveryRemaining() > 0 then return false, "Wand recovery" end
    return true
end

local function Reset()
    shot = { pendingUntil = 0, untilTime = 0, completed = {} }
    repeatActive, stopSuggestion = false, false
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_REGEN_ENABLED", "UNIT_RANGEDDAMAGE", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then Reset(); RefreshPeriod(); return end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if Number(unit) == 18 or Number(unit) == 16 then Reset(); cachedPeriod = nil; RefreshPeriod() end
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" or event == "UNIT_RANGEDDAMAGE" then RefreshPeriod(); return end
    if event == "START_AUTOREPEAT_SPELL" then repeatActive = true; return end
    if event == "STOP_AUTOREPEAT_SPELL" then
        repeatActive, stopSuggestion = false, false
        if shot.stopping then shot.pendingUntil = 0 end
        return
    end
    if not Public(unit) or unit ~= "player" then return end
    local now = GetTime()
    local sent = event == "UNIT_SPELLCAST_SENT"
    local guid = GUID(sent and arg3 or arg2)
    local hasID = Number(arg3) or Number(arg4)
    local wand
    if hasID then wand = IsShoot(arg4) or IsShoot(arg3)
    else wand = (not sent or not GUID(arg3)) and IsShoot(arg2) end
    if not wand and not hasID then
        wand = guid and guid == shot.guid or sent and AL.lastSuggestion == "Shoot"
            or not sent and not guid and not shot.guid and shot.pendingUntil > now
    end
    if not wand then return end
    if sent then
        -- A second key press cannot replace an accepted shot's timing/GUID.
        if (shot.castingUntil or 0) > now then return end
        if shot.pendingUntil > now and guid == shot.guid then return end
        local _, _, _, world = Call(GetNetStats)
        local ack = math.min(1, math.max(0.35, (Number(world) or 100) / 500 + 0.15))
        shot.guid, shot.pendingUntil, shot.stopping = guid, now + ack, stopSuggestion or AL.WandAutoRepeatActive()
        shot.started, shot.castingUntil = nil, nil
        stopSuggestion = false
        return
    end
    if guid and shot.guid and guid ~= shot.guid
        and event ~= "UNIT_SPELLCAST_SUCCEEDED" and event ~= "UNIT_SPELLCAST_START"
        and event ~= "UNIT_SPELLCAST_CHANNEL_START" then return end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local started, ending = CastWindow(true)
        shot.started = started or shot.started or now
        shot.castingUntil = ending or shot.started + AL.WandPeriod()
        shot.untilTime = shot.castingUntil
        shot.guid, shot.pendingUntil = guid or shot.guid, 0
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        for key, at in pairs(shot.completed) do if now - at > 60 then shot.completed[key] = nil end end
        if guid and shot.completed[guid] then return end
        if guid then shot.completed[guid] = now end
        if not shot.stopping then
            -- START/DELAYED gives the actual shot end. Do not add a second
            -- full weapon period when SUCCEEDED arrives at that end.
            local same = not guid or not shot.guid or guid == shot.guid
            shot.untilTime = same and shot.started and (shot.castingUntil or shot.untilTime)
                or now + AL.WandPeriod()
            shot.recoveryUntil = shot.untilTime
        end
        shot.pendingUntil, shot.stopping = 0, false
        if (shot.castingUntil or 0) <= now then shot.castingUntil, shot.started = nil, nil end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        shot.pendingUntil, shot.castingUntil = 0, nil
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if guid and shot.completed[guid] then return end
        shot.pendingUntil, shot.castingUntil, shot.started, shot.stopping = 0, nil, nil, false
        shot.untilTime = math.max(shot.recoveryUntil or 0, math.min(shot.untilTime, now))
    end
end)

-- Conditional mana rows and normal recommendations use the same timing and
-- stop command. This helper never inspects a protected visibility value.
function AL.WandSuggestion(spell, reason)
    if AL.WandCasting() then return nil, "Wand shot" end
    if spell == "Shoot" then
        local stopping = type(reason) == "string" and reason:find("^Stop wand for ") ~= nil
        local ready, wait = AL.WandReady(stopping)
        if not ready then return nil, wait end
    elseif spell then
        if AL.WandAutoRepeatActive() then
            local ready, wait = AL.WandReady(true)
            if not ready then return nil, wait end
            return "Shoot", "Stop wand for " .. spell
        end
        if AL.WandRecoveryRemaining() > 0 then return nil, "Wand recovery" end
    end
    return spell, reason
end

-- Check the final suggestion as well as the class gates, including queued Shoot.
local NextSpell = AL.NextSpell
function AL.NextSpell()
    stopSuggestion = false
    if AL.WandCasting() then return nil, "Wand shot" end
    local spell, reason = AL.WandSuggestion(NextSpell())
    stopSuggestion = spell == "Shoot" and type(reason) == "string" and reason:find("^Stop wand for ") ~= nil
    return spell, reason
end

RefreshPeriod()
