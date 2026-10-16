local ADDON, AL = ...
local ns = { version = "1.0.0", Errors = {} }
AL.ActionLiteDebug = ns
local S = { state = "Stopped", ready = true, interval = 5, maxBytes = 2 * 1024 * 1024,
    maxEvents = 3000, maxSnapshots = 240, maxSeconds = 600 }
ns.Scanner = S
local data, pending, intern, logRows = nil, nil, {}, {}
local stateIntern = {}
local bytes, sequence, nextFull, nextState, nextConfig = 0, 0, 0, 0, 0
local combatEvent, enteredCombat, combatEnded, postDeadline, pausedAt
local stopping, hookedLogger = false, nil
local lastConfig, lastState, lastCooldown = nil, nil, -100
local eventThrottle = {}
local P

function ns.ErrorText(value)
    if ns.Probe and ns.Probe.Public(value) and type(value) == "string" then return value:sub(1, 1000) end
    return "Error details are protected or unavailable."
end

function ns.Notice(message)
    ns.message = message
    if ns.UI and ns.UI.Refresh then pcall(ns.UI.Refresh) end
end

function ns.Try(component, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        local message = ns.ErrorText(result)
        ns.Errors[component] = message
        ns.Notice(component .. ": " .. message)
        if S.state == "Recording" then S.AddEvent("Debugger error", { component = component, message = message }) end
        return false
    end
    ns.Errors[component] = nil
    return true, result
end

local function Now()
    local ok, value = pcall(GetTime)
    if ok and ns.Probe and ns.Probe.Public(value) and type(value) == "number" then return value end
    return S.clock or 0
end

local function Combat()
    if combatEvent ~= nil then return combatEvent end
    local value = P.First("UnitAffectingCombat", "player")
    if type(value) ~= "boolean" then value = P.First("InCombatLockdown") end
    if type(value) == "boolean" then return value end
end

local function Phase()
    local combat = Combat()
    if combat == true then return "In combat" end
    if combat == false then return enteredCombat and "After combat" or "Before combat" end
    return "Unknown"
end

function S.Notify()
    if ns.UI and ns.UI.Refresh then pcall(ns.UI.Refresh) end
end

local function Fit(value)
    local text = P.JSON(value)
    if bytes + #text + 1024 > S.maxBytes then
        if not stopping then S.Stop("Report memory limit reached") end
        return false
    end
    bytes = bytes + #text
    return true, text
end

function S.AddEvent(event, detail)
    if S.state ~= "Recording" or not data then return end
    if #data.timeline >= S.maxEvents then if not stopping then S.Stop("Event limit reached") end; return end
    local row = { at = Now() - data.started, phase = Phase(), event = event, detail = P.Copy(detail) }
    if Fit(row) then data.timeline[#data.timeline + 1] = row; return row end
end

function S.CaptureConfiguration(origin, force)
    if S.state ~= "Recording" or not data then return end
    local configuration = ns.State.Configuration()
    local encoded = P.JSON(configuration)
    if not force and encoded == lastConfig then return end
    local row = { at = Now() - data.started, phase = Phase(), origin = origin, configuration = configuration }
    if force or origin == "Finish" then row.controls = ns.State.Controls() end
    if Fit(row) then data.configurations[#data.configurations + 1] = row; lastConfig = encoded end
end

function S.CaptureState(origin, detail)
    if S.state ~= "Recording" or not data then return end
    local state = ns.State.Runtime(detail)
    local encoded = P.JSON(state)
    if encoded == lastState and not detail then return end
    local refs = {}
    for name, value in pairs(state) do
        local text = P.JSON(value)
        local id = stateIntern[text]
        if not id then
            if not Fit(value) then return end
            id = #data.stateValues + 1
            data.stateValues[id], stateIntern[text] = value, id
        end
        refs[name] = id
    end
    local row = { at = Now() - data.started, phase = Phase(), origin = origin, stateRefs = refs }
    if Fit(row) then data.states[#data.states + 1] = row; lastState = encoded end
end

local function NewSnapshot(origin)
    if #data.snapshots >= S.maxSnapshots then S.Stop("API snapshot limit reached"); return end
    sequence = sequence + 1
    local snap = { sequence = sequence, origin = origin, phase = Phase(), started = Now() - data.started,
        observations = {}, complete = false, attempted = 0 }
    data.snapshots[#data.snapshots + 1] = snap
    bytes = bytes + 256
    return snap
end

local failures = {}
local function Observe(path, args, snap)
    if S.state ~= "Recording" then return end
    args = args or {}
    local key = path .. P.JSON(args)
    local phase = Phase()
    if phase ~= snap.phase then return end
    failures[phase] = failures[phase] or {}
    local result = P.Call(path, args, failures[phase], key)
    result.arguments = P.Copy(args)
    result.isOnGCDTrustedContext = path == "C_Spell.GetSpellCooldown" and snap.origin == "SPELL_UPDATE_COOLDOWN" or nil
    local text = P.JSON(result)
    local id = intern[text]
    if not id then
        if not Fit(result) then return end
        id = #data.observations + 1
        data.observations[id], intern[text] = result, id
    end
    snap.observations[#snap.observations + 1] = id
    snap.attempted = snap.attempted + 1
    bytes = bytes + 8
    return result
end

local function ClosePending(reason)
    if not pending then return end
    pending.snap.finished = Now() - data.started
    pending.snap.complete = reason == nil
    pending.snap.interruptedBy = reason
    pending.snap.remaining = #pending.jobs - pending.index + 1
    pending = nil
end

local function AddSpell(id, name)
    if not P.Public(id) or type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then return end
    if data.spellSet[id] or #data.spells >= 128 then return end
    data.spellSet[id] = true
    data.spells[#data.spells + 1] = { id = id, name = P.Copy(name) }
end

local function Discover()
    local module = AL.rotations and AL.rotations[AL.playerClass]
    for _, entry in ipairs(module and module.spells or {}) do
        local reference = AL.rangeSpellRefs and AL.rangeSpellRefs[entry[2]]
        AddSpell(reference and reference.id or entry[1], entry[2])
    end
    -- Inspect existing mappings, never rescan/mutate the live spellbook.
    for name, reference in pairs(AL.rangeSpellRefs or {}) do AddSpell(reference.id, name) end
end

local function Quick(origin)
    local snap = NewSnapshot(origin)
    if not snap then return end
    for _, path in ipairs({"UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitCastingInfo", "UnitChannelInfo"}) do
        Observe(path, {"player"}, snap)
    end
    for _, path in ipairs({"UnitExists", "UnitHealth", "UnitHealthMax", "UnitLevel", "UnitClassification",
        "UnitCreatureType", "UnitIsDeadOrGhost", "UnitAffectingCombat", "UnitGUID"}) do Observe(path, {"target"}, snap) end
    Observe("UnitCanAttack", {"player", "target"}, snap)
    Observe("GetComboPoints", {"player", "target"}, snap)
    Observe("GetWeaponEnchantInfo", {}, snap)
    Observe("GetManaRegen", {}, snap)
    for _, power in ipairs({0,1,2,3,4}) do Observe("UnitPower", {"player", power}, snap); Observe("UnitPowerMax", {"player", power}, snap) end
    local spell = AL.lastSuggestion
    local reference = type(spell) == "string" and AL.rangeSpellRefs and AL.rangeSpellRefs[spell]
    local id = reference and reference.id
    if type(id) == "number" and P.Public(id) then
        Observe("C_Spell.GetSpellCooldown", {id}, snap)
        Observe("C_Spell.IsSpellUsable", {id}, snap)
        Observe("C_Spell.IsSpellInRange", {id,"target"}, snap)
    end
    snap.finished, snap.complete = Now() - data.started, S.state == "Recording"
end

function S.Request(origin)
    if S.state ~= "Recording" or pending or not data then return end
    local snap = NewSnapshot(origin)
    if not snap then return end
    pending = { snap = snap, jobs = {}, index = 1 }
    local function Job(path, ...) pending.jobs[#pending.jobs + 1] = { path, {...} } end
    for _, path in ipairs(ns.Catalog.globals) do
        if path == "GetComboPoints" then Job(path,"player","target") else Job(path) end
    end
    for _, unit in ipairs({"player","target","pet","targettarget"}) do
        for _, path in ipairs(ns.Catalog.unit) do Job(path,unit) end
        if unit ~= "player" then Job("UnitCanAttack","player",unit); Job("UnitIsFriend","player",unit) end
        for _, power in ipairs({0,1,2,3,4}) do
            Job("UnitPower",unit,power);Job("UnitPowerMax",unit,power);Job("UnitPowerPercent",unit,power)
        end
        for _, filter in ipairs({"HELPFUL","HARMFUL"}) do
            for index = 1,4 do
                Job("C_UnitAuras.GetAuraDataByIndex",unit,index,filter)
                Job("UnitAura",unit,index,filter)
            end
        end
    end
    Job("UnitBuff","player",1);Job("UnitDebuff","target",1)
    Job("CheckInteractDistance","target",3)
    Job("UnitIsUnit","targettarget","player")
    Job("UnitThreatSituation","player","target")
    Job("UnitDetailedThreatSituation","player","target")
    for slot=1,4 do Job("GetTotemInfo",slot) end
    if AL.playerClass == "WARLOCK" then Job("GetItemCount",6265);Job("C_Item.GetItemCount",6265) end
    for _, entry in ipairs(data.spells) do
        for _, path in ipairs(ns.Catalog.spell) do Job(path,entry.id) end
        Job("C_Spell.IsSpellInRange",entry.id,"target")
        Job("IsSpellInRange",entry.name or entry.id,"target")
    end
    if Phase() ~= "In combat" then
        for slot=1,120 do
            Job("GetActionInfo",slot);Job("GetActionCooldown",slot)
        end
        for _, prefix in ipairs({"ACTIONBUTTON","MULTIACTIONBAR1BUTTON","MULTIACTIONBAR2BUTTON",
            "MULTIACTIONBAR3BUTTON","MULTIACTIONBAR4BUTTON","MULTIACTIONBAR5BUTTON","MULTIACTIONBAR6BUTTON"}) do
            for index=1,12 do Job("GetBindingKey",prefix..index) end
        end
        for slot=16,18 do Job("GetInventoryItemID","player",slot) end
        Job("GetNumTalentTabs")
        for tab=1,3 do Job("GetTalentTabInfo",tab);Job("GetNumTalents",tab) end
        for index=1,40 do
            local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
            Job("C_SpellBook.GetSpellBookItemName",index,bank)
            Job("C_SpellBook.GetSpellBookItemInfo",index,bank)
        end
    end
    snap.scheduled = #pending.jobs
    nextFull = Now() + S.interval
end

local function AttachLogger()
    local logger = AL.Debug
    if type(logger) ~= "table" or logger == hookedLogger or type(logger.OnLog) ~= "function" then return end
    hookedLogger = logger
    logger.OnLog(function(entry)
        if S.state ~= "Recording" or not data then return end
        local copy = P.Copy(entry)
        if type(copy) ~= "table" then return end
        if logRows[entry.id] then
            local previous = logRows[entry.id]
            local replacement = { at = Now() - data.started, phase = Phase(), event = "ActionLITE " .. (copy.cat or "log"), detail = copy }
            if Fit(replacement) then data.timeline[previous] = replacement end
        else
            local row = S.AddEvent("ActionLITE " .. (copy.cat or "log"), copy)
            if row then logRows[entry.id] = #data.timeline end
        end
    end)
    if type(logger.OnBug) == "function" then logger.OnBug(function(bug)
        if S.state == "Recording" then S.AddEvent("Lua error / taint", bug) end
    end) end
end

function S.Start()
    P = ns.Probe
    if S.state == "Recording" then return true end
    if S.state == "Paused" and data then
        S.state = "Recording"
        if postDeadline and pausedAt then postDeadline = postDeadline + Now() - pausedAt end
        pausedAt = nil
        S.AddEvent("Resume");Quick("Resume");S.Request("Resume");S.Notify();return true
    end
    local build = P.Call("GetBuildInfo")
    local interface = build.values and build.values[4]
    if interface and interface.status == "Visible" and type(interface.value) == "number"
        and (interface.value < 16000 or interface.value >= 20000) then
        ns.Notice("ActionLiteDebug supports WoW Forever.");return false
    end
    if ns.UI then ns.UI.CloseResults(false);ns.UI.ClearResults() end
    intern, logRows, failures = {}, {}, {}
    stateIntern = {}
    eventThrottle, pausedAt, lastCooldown = {}, nil, -100
    bytes, sequence, lastConfig, lastState, pending = 0, 0, nil, nil, nil
    combatEvent, enteredCombat, combatEnded, postDeadline = nil, false, nil, nil
    combatEvent = Combat();enteredCombat = combatEvent == true
    data = { addon = "ActionLiteDebug", version = ns.version, format = "ActionLiteDebug report 1",
        client = "WoW Forever", build = build, addonVersion = P.Call("C_AddOns.GetAddOnMetadata",{ADDON,"Version"}),
        locale = P.Call("GetLocale"), class = P.Call("UnitClass",{"player"}), race = P.Call("UnitRace",{"player"}),
        recordedAt = P.Call("GetServerTime"), started = Now(), startedInCombat = enteredCombat, startPhase = Phase(),
        componentVersions = { ui = AL.UI and AL.UI.VERSION, classUIs = P.Copy(AL.classUIVersions) },
        guards = { issecretvalue = type(issecretvalue)=="function", canaccessvalue = type(canaccessvalue)=="function",
            canaccesstable = type(canaccesstable)=="function" },
        eventSupport = P.Copy(ns.eventSupport),
        inventory = P.Inventory(), configurations = {}, states = {}, stateValues = {}, timeline = {}, observations = {}, snapshots = {},
        spells = {}, spellSet = {}, priorSessionErrors = {}, pauseCount = 0,
        notes = { "Copy/paste capture only; this report is never stored in SavedVariables or written to disk.",
            "Hidden/Inaccessible values are classified without retaining their protected contents. Missing is different from zero or false.",
            "Snapshot observation IDs reference the 1-based observations array. Repeated observations are stored once.",
            "State snapshot stateRefs map each field to a 1-based stateValues entry. Unchanged state components are stored once without dropping timestamps or values.",
            "Configuration snapshots contain stored and effective class settings, all spell toggles and icon choices.",
            "Only current-state getters are queried. Rotation decisions/casts are observed; NextSpell and cast-result handlers are never invoked by this recorder.",
            "Aura indexes 1-4 and spellbook indexes 1-40 are sampled; full learned spell mappings come from ActionLITE. Bounded or interrupted scans are marked.",
            "Start outside combat, reproduce the issue, then wait five seconds after combat and open Results." } }
    bytes = #P.JSON(data)
    if AL.Debug and type(AL.Debug.Bugs) == "function" then
        local ok, bugs = pcall(AL.Debug.Bugs)
        local clean = ok and P.Copy(bugs)
        if type(clean) == "table" then
            for _, bug in ipairs(clean) do
                if type(bug) == "table" and bug.session == AL.Debug.session and #data.priorSessionErrors < 20 then
                    if Fit(bug) then data.priorSessionErrors[#data.priorSessionErrors + 1] = bug end
                end
            end
        end
    end
    if not data.addonVersion.values then data.addonVersion = P.Call("GetAddOnMetadata",{ADDON,"Version"}) end
    S.state, S.stopReason, ns.message = "Recording", nil, nil
    AttachLogger();Discover()
    S.AddEvent("Start",{ startedInCombat = enteredCombat })
    if AL.Debug and type(AL.Debug.RotationState) == "function" then
        local ok, decision = pcall(AL.Debug.RotationState)
        if ok then S.AddEvent("ActionLITE rotation baseline",decision) end
    end
    S.CaptureConfiguration("Start",true);S.CaptureState("Start",true)
    Quick("Start");S.Request("Start")
    nextState, nextConfig = Now()+1,Now()+1
    S.Notify();return true
end

function S.Pause()
    if S.state ~= "Recording" then return end
    S.AddEvent("Pause");ClosePending("Paused");data.pauseCount=data.pauseCount+1
    pausedAt, S.state = Now(), "Paused"
    S.Notify()
end

function S.Stop(reason)
    if stopping or (S.state ~= "Recording" and S.state ~= "Paused") then return end
    stopping = true
    local wasPaused = S.state == "Paused"
    -- A paused capture must not perform fresh API reads just to stop it.
    if not wasPaused then
        pcall(S.CaptureConfiguration,"Finish")
        pcall(S.CaptureState,"Finish",true)
        if reason ~= "Report memory limit reached" then pcall(Quick,"Finish") end
        S.AddEvent("Stop",{ reason = reason or "Stopped" })
    end
    ClosePending(reason or "Stopped")
    data.finished, data.stopReason = Now(),reason or "Stopped"
    local phases = {}
    for _, snap in ipairs(data.snapshots) do if #snap.observations > 0 then phases[snap.phase] = true end end
    data.coverage = { beforeCombat = phases["Before combat"] == true, inCombat = phases["In combat"] == true,
        postCombatSeconds = combatEnded and math.max(0,Now()-combatEnded) or 0,
        requestedPostCombatSeconds = 5, pausedAtStop = wasPaused,
        completeCombatSequence = data.startPhase == "Before combat" and phases["In combat"] == true
            and phases["After combat"] == true and combatEnded ~= nil and Now()-combatEnded >= 5 and data.pauseCount==0 }
    data.debuggerErrors = P.Copy(ns.Errors)
    data.spellSet = nil
    S.state, S.stopReason, stopping = "Stopped", data.stopReason, false
    S.Notify()
end

function S.Results()
    S.Stop("Results opened")
    if not data then return "ActionLiteDebug\nNo capture yet. Click Start outside combat, reproduce the issue, wait five seconds after combat, then click Results." end
    return "ActionLiteDebug\nWoW Forever - ActionLITE bug report\nSelect All, copy, and paste this complete report.\n\n" .. P.JSON(data)
end
function S.Data() return data end
function S.Current() return data end
function S.PostCombatRemaining() return postDeadline and math.max(0,postDeadline-Now()) end

function S.Step(elapsed)
    S.clock = (S.clock or 0) + (type(elapsed)=="number" and elapsed or 0)
    if S.state ~= "Recording" or not data then return end
    local now = Now()
    if now-data.started >= S.maxSeconds then S.Stop("Ten-minute recording limit reached");return end
    if postDeadline and now >= postDeadline then
        Quick("Five seconds after combat");S.Stop("Complete: five seconds after combat");return
    end
    if now >= nextConfig then S.CaptureConfiguration("Settings changed");nextConfig=now+1 end
    if now >= nextState then S.CaptureState("Timer",false);nextState=now+1 end
    if pending and pending.snap.phase ~= Phase() then ClosePending("Combat phase changed") end
    if not pending and now >= nextFull then S.Request("Timer") end
    if pending then
        local t0 = type(debugprofilestop)=="function" and debugprofilestop()
        for index=1,24 do
            local job = pending and pending.jobs[pending.index]
            if not job then ClosePending();break end
            local snap = pending.snap
            pending.index = pending.index+1
            local result = Observe(job[1],job[2],snap)
            if S.state ~= "Recording" then return end
            if job[1] == "GetActionInfo" and result and result.values then
                local kind, id = result.values[1], result.values[2]
                if kind and kind.status=="Visible" and kind.value=="macro"
                    and id and id.status=="Visible" and type(id.value)=="number" then
                    pending.jobs[#pending.jobs+1] = {"GetMacroSpell",{id.value}}
                    snap.scheduled=#pending.jobs
                end
            end
            if t0 and debugprofilestop()-t0 >= 2 then break end
        end
    end
end

function S.Event(event, ...)
    if event == "PLAYER_LOGIN" then AttachLogger();return end
    if event == "PLAYER_LOGOUT" then
        data,pending,intern,logRows,stateIntern = nil,nil,{},{},{}
        S.state="Stopped"
        if ns.UI then ns.UI.ClearResults() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        combatEvent,enteredCombat,combatEnded,postDeadline = true,true,nil,nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatEvent=false
        if enteredCombat then combatEnded=Now();postDeadline=combatEnded+5 end
    end
    if S.state ~= "Recording" or not data then return end
    local args = {...}
    if event:find("^UNIT_") then
        local unit = args[1]
        if not P.Public(unit) then
            S.AddEvent(event,{ arguments = P.Copy(args), note = "Unit token protected; identity not assumed" })
            return
        end
        if unit~="player" and unit~="target" and unit~="pet" and unit~="targettarget" then return end
        if event:find("^UNIT_SPELLCAST") and unit~="player" and unit~="target" then return end
        if not event:find("^UNIT_SPELLCAST") then
            local key=event..":"..unit
            if eventThrottle[key] and Now()-eventThrottle[key]<0.5 then return end
            eventThrottle[key]=Now()
        end
    elseif event=="SPELL_UPDATE_COOLDOWN" or event=="SPELL_UPDATE_USABLE" then
        if eventThrottle[event] and Now()-eventThrottle[event]<0.5 then return end
        eventThrottle[event]=Now()
    end
    S.AddEvent(event, args)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        ClosePending("Combat transition");Quick(event)
        S.CaptureState(event,true);S.Request(event)
    elseif event == "SPELL_UPDATE_COOLDOWN" and Now()-lastCooldown>=0.5 then
        lastCooldown=Now()
        local snap=NewSnapshot(event)
        if snap then
            local suggested=AL.lastSuggestion
            local ref=type(suggested)=="string" and AL.rangeSpellRefs and AL.rangeSpellRefs[suggested]
            if ref and P.Public(ref.id) and type(ref.id)=="number" then Observe("C_Spell.GetSpellCooldown",{ref.id},snap) end
            snap.complete=true;snap.finished=Now()-data.started
        end
    elseif event:find("^UNIT_SPELLCAST") then
        local spellID = event=="UNIT_SPELLCAST_SENT" and args[4] or args[3]
        AddSpell(spellID)
    elseif event=="SPELLS_CHANGED" or event=="LEARNED_SPELL_IN_TAB" then
        Discover();S.CaptureState(event,true)
    end
    S.Notify()
end

local frame = CreateFrame("Frame")
S.frame = frame
ns.eventSupport = {}
frame:SetScript("OnUpdate",function(_,elapsed)
    local ok,problem=pcall(S.Step,elapsed)
    if not ok then
        ns.Errors.Scanner=ns.ErrorText(problem)
        S.Stop("Scanner error; partial report retained")
        ns.Notice("Capture stopped. Open Results to copy the partial report.")
    end
end)
frame:SetScript("OnEvent",function(_,event,...)
    local ok,problem=pcall(S.Event,event,...)
    if not ok then ns.Errors.Events=ns.ErrorText(problem);S.Stop("Event error; partial report retained") end
end)
for _,event in ipairs({ "PLAYER_LOGIN","PLAYER_LOGOUT","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED","PLAYER_DEAD","PLAYER_LEVEL_UP","SPELLS_CHANGED","LEARNED_SPELL_IN_TAB",
    "SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_USABLE","ACTIONBAR_SLOT_CHANGED","UPDATE_BINDINGS","UPDATE_SHAPESHIFT_FORM",
    "PLAYER_EQUIPMENT_CHANGED","UI_ERROR_MESSAGE","LUA_WARNING","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN",
    "UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_DELAYED",
    "UNIT_HEALTH","UNIT_MAXHEALTH","UNIT_POWER_UPDATE","UNIT_MAXPOWER","UNIT_AURA","UNIT_COMBAT",
    "UNIT_THREAT_SITUATION_UPDATE","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED" }) do
    local registered = pcall(frame.RegisterEvent,frame,event)
    ns.eventSupport[event] = registered and "Registered" or "Unavailable on this client"
end
