local ADDON, AL = ...

local D = {}
AL.Debug = D

D.LEVELS = { "error", "warn", "info", "debug", "trace" }
D.LEVEL_RANK = { error = 1, warn = 2, info = 3, debug = 4, trace = 5 }
D.CATEGORIES = { "error", "addon", "cast", "combat", "rotation", "aura", "power", "event", "ui", "probe", "system" }
D.CAPACITY = 3000
D.NOISY = {
	UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_HEALTH = true, UNIT_HEALTH_FREQUENT = true,
	UNIT_MAXHEALTH = true, UNIT_MAXPOWER = true, UNIT_AURA = true, UNIT_COMBAT = true, UNIT_FLAGS = true,
	UNIT_TARGET = true, UNIT_THREAT_LIST_UPDATE = true, UNIT_THREAT_SITUATION_UPDATE = true,
	UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_MODEL_CHANGED = true, UNIT_PORTRAIT_UPDATE = true,
	UNIT_ATTACK_SPEED = true, UNIT_RESISTANCES = true, UNIT_STATS = true, UNIT_DAMAGE = true,
	UPDATE_MOUSEOVER_UNIT = true, CURSOR_UPDATE = true, CURSOR_CHANGED = true, MODIFIER_STATE_CHANGED = true,
	SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_USABLE = true, ACTIONBAR_UPDATE_COOLDOWN = true,
	ACTIONBAR_UPDATE_USABLE = true, ACTIONBAR_UPDATE_STATE = true, BAG_UPDATE_COOLDOWN = true,
	BAG_UPDATE = true, BAG_UPDATE_DELAYED = true, UPDATE_INVENTORY_DURABILITY = true,
	NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true, PLAYER_STARTED_MOVING = true,
	PLAYER_STOPPED_MOVING = true, UPDATE_UI_WIDGET = true, GET_ITEM_INFO_RECEIVED = true,
	COMPANION_UPDATE = true, CHAT_MSG_ADDON = true, CHAT_MSG_CHANNEL = true, UPDATE_SHAPESHIFT_COOLDOWN = true,
	WORLD_CURSOR_TOOLTIP_UPDATE = true, CRITERIA_UPDATE = true, UPDATE_PENDING_MAIL = true,
}
D.traceNoisy = false
D.perf = { calls = 0, totalMs = 0, maxMs = 0, lastMs = 0 }
D.sessionErrors = 0
D.session = 0

local CAP = D.CAPACITY
local LEVEL_RANK = D.LEVEL_RANK
local SECRET = {}

local function IsSecret(v)
	local f = issecretvalue
	if type(f) ~= "function" then return false end
	local ok, r = pcall(f, v)
	return not ok or r == true
end

local function Now()
	local ok, t = pcall(GetTime)
	if ok and type(t) == "number" and not IsSecret(t) then return t end
	return 0
end
local loadTime = Now()

local function Clip(s, max)
	if #s > max then return s:sub(1, max) .. "…" end
	return s
end

local function Num(v)
	if v ~= v then return "nan" end
	if v == math.huge then return "inf" end
	if v == -math.huge then return "-inf" end
	if v == math.floor(v) and v > -1e15 and v < 1e15 then return string.format("%d", v) end
	if v >= 1000 or v <= -1000 then return string.format("%.1f", v) end
	return string.format("%.3g", v)
end

local function FrameKind(v)
	local f = v.GetObjectType
	if type(f) ~= "function" then return nil end
	local kind = f(v)
	if type(kind) ~= "string" or IsSecret(kind) then return nil end
	local name
	if type(v.GetName) == "function" then name = v:GetName() end
	if type(name) == "string" and not IsSecret(name) and name ~= "" then
		return "<" .. kind .. " " .. name .. ">"
	end
	return "<" .. kind .. ">"
end

local function SafeValue(v, depth)
	if IsSecret(v) then return "<secret>" end
	local t = type(v)
	if t == "nil" then return "nil" end
	if t == "string" then return Clip(v, 500) end
	if t == "number" then return Num(v) end
	if t == "boolean" then return v and "true" or "false" end
	if t == "function" then return "<function>" end
	if t == "table" then
		local okK, kind = pcall(FrameKind, v)
		if okK and kind then return kind end
		if depth > 0 then return "{…}" end
		local parts, n = {}, 0
		pcall(function()
			for k, val in pairs(v) do
				n = n + 1
				if n > 8 then parts[#parts + 1] = "…"; break end
				parts[#parts + 1] = SafeValue(k, 1) .. "=" .. SafeValue(val, 1)
			end
		end)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	local ok, s = pcall(tostring, v)
	if ok and type(s) == "string" and not IsSecret(s) then return Clip(s, 500) end
	return "<" .. t .. ">"
end

function D.Safe(v)
	local ok, s = pcall(SafeValue, v, 0)
	if ok then return s end
	return "<?>"
end
local Safe = D.Safe

function D.Escape(s)
	if type(s) ~= "string" or IsSecret(s) then s = Safe(s) end
	return (s:gsub("|", "||"))
end

-- Reads one value: value (nil unless readable) and state ok|secret|error|nil|missing.
local function Read1(fn, ...)
	if type(fn) ~= "function" then return nil, "missing" end
	local ok, v = pcall(fn, ...)
	if not ok then return nil, "error", v end
	if IsSecret(v) then return nil, "secret" end
	if v == nil then return nil, "nil" end
	return v, "ok"
end

local function Show(fn, ...)
	local v, st = Read1(fn, ...)
	if st == "ok" then return Safe(v) end
	if st == "secret" then return "<secret>" end
	return st
end

local function InCombat()
	local v, st = Read1(UnitAffectingCombat, "player")
	if st == "ok" or st == "nil" then return v and true or false end
	v, st = Read1(InCombatLockdown)
	if st == "ok" or st == "nil" then return v and true or false end
	return nil
end

local function Stamp()
	local ok, s = pcall(date, "%Y-%m-%d %H:%M:%S")
	if ok and type(s) == "string" then return s end
	return "?"
end

local function Clock(now)
	local ok, s = pcall(date, "%H:%M:%S")
	if not ok or type(s) ~= "string" then s = "??:??:??" end
	return s .. string.format(".%03d", math.floor((now % 1) * 1000))
end

local cachedVersion
local function Version()
	if cachedVersion then return cachedVersion end
	local v
	if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
		v = Read1(C_AddOns.GetAddOnMetadata, ADDON, "Version")
	end
	if type(v) ~= "string" then v = Read1(GetAddOnMetadata, ADDON, "Version") end
	if type(v) == "string" then cachedVersion = v; return v end
	return "?"
end

local function Build()
	if type(GetBuildInfo) ~= "function" then return "?" end
	local ok, v, b = pcall(GetBuildInfo)
	if not ok or IsSecret(v) or IsSecret(b) then return "?" end
	if type(v) == "string" and (type(b) == "string" or type(b) == "number") then return v .. "." .. b end
	if type(v) == "string" then return v end
	return "?"
end

local function FirstLine(s)
	if type(s) ~= "string" then return "" end
	return s:match("^[^\n]*") or ""
end

local function StripColors(s)
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Detail(d)
	if d == nil then return nil end
	if IsSecret(d) then return "<secret>" end
	if type(d) == "string" then return Clip(d, 4000) end
	if type(d) ~= "table" then return Safe(d) end
	local okK, kind = pcall(FrameKind, d)
	if okK and kind then return kind end
	local rows = {}
	pcall(function()
		for k, v in pairs(d) do
			rows[#rows + 1] = { SafeValue(k, 1), SafeValue(v, 0) }
		end
	end)
	table.sort(rows, function(a, b) return a[1] < b[1] end)
	for i = 1, #rows do rows[i] = rows[i][1] .. " = " .. rows[i][2] end
	return table.concat(rows, "\n")
end

local ring, head, count, nextId = {}, 1, 0, 0
local logListeners, bugListeners = {}, {}

local function Slot(i) return (head + i - 2) % CAP + 1 end

function D.Count() return count end

function D.Get(i)
	if type(i) ~= "number" or i < 1 or i > count then return nil end
	return ring[Slot(math.floor(i))]
end

function D.Clear()
	ring, head, count = {}, 1, 0
end

function D.OnLog(fn) if type(fn) == "function" then logListeners[#logListeners + 1] = fn end end
function D.OnBug(fn) if type(fn) == "function" then bugListeners[#bugListeners + 1] = fn end end

local notifying = false
local function Notify(e)
	if notifying then return end
	notifying = true
	for i = 1, #logListeners do pcall(logListeners[i], e) end
	notifying = false
end

local function LogImpl(cat, level, msg, detail)
	if IsSecret(cat) or type(cat) ~= "string" then cat = "system" end
	if IsSecret(level) or not LEVEL_RANK[level] then level = "info" end
	msg = Safe(msg)
	local now = Now()
	local newest = count > 0 and ring[Slot(count)]
	if newest and newest.cat == cat and newest.level == level and newest.msg == msg and now - newest.time <= 2 then
		newest.count = newest.count + 1
		newest.time = now
		newest.clock = Clock(now)
		if detail ~= nil then newest.detail = Detail(detail) end
		Notify(newest)
		return newest
	end
	nextId = nextId + 1
	local e = {
		id = nextId, time = now, clock = Clock(now), cat = cat, level = level, msg = msg,
		detail = Detail(detail), combat = InCombat(), count = 1,
	}
	if count < CAP then
		count = count + 1
		ring[Slot(count)] = e
	else
		ring[head] = e
		head = head % CAP + 1
	end
	Notify(e)
	return e
end

function AL.Log(cat, level, msg, detail)
	local ok, e = pcall(LogImpl, cat, level, msg, detail)
	if ok then return e end
end
local Log = AL.Log

local mem = {}
local dbReady = false

local function Fill(s)
	if type(s.bugs) ~= "table" then s.bugs = {} end
	if type(s.session) ~= "number" then s.session = 0 end
	if s.window ~= nil and type(s.window) ~= "table" then s.window = nil end
	if type(s.level) ~= "number" then s.level = 5 end
	if type(s.hiddenCats) ~= "table" then s.hiddenCats = {} end
	if type(s.traceEvents) ~= "boolean" then s.traceEvents = false end
	if type(s.autoOpen) ~= "boolean" then s.autoOpen = false end
	if type(s.probe) ~= "table" then s.probe = {} end
	return s
end

local function SavedTable()
	if type(ActionLiteDB) ~= "table" then ActionLiteDB = {} end
	local db = ActionLiteDB
	if type(db.profiles) ~= "table" then db.profiles = {} end
	local ui = db.profiles.__ACTIONLITE_UI
	if type(ui) ~= "table" then ui = {}; db.profiles.__ACTIONLITE_UI = ui end
	if type(ui.debug) ~= "table" then ui.debug = {} end
	return ui.debug
end

function D.Settings()
	if dbReady then
		local ok, s = pcall(SavedTable)
		if ok and s then return Fill(s) end
	end
	return Fill(mem)
end

function D.Bugs() return D.Settings().bugs end

function D.ErrorSummary()
	local bugs = D.Bugs()
	local summary = { sessionOccurrences = D.sessionErrors, sessionGroups = 0,
		savedGroups = #bugs, savedOccurrences = 0 }
	for _, bug in ipairs(bugs) do
		summary.savedOccurrences = summary.savedOccurrences + (tonumber(bug.count) or 1)
		if bug.session == D.session then summary.sessionGroups = summary.sessionGroups + 1 end
	end
	return summary
end

function D.ClearBugs()
	local s = D.Settings()
	s.bugs = {}
end

local function GuessAddon(...)
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if type(s) == "string" then
			local name = s:match("[Aa]dd[Oo]ns[\\/]([^\\/]+)[\\/]")
			if name then return name end
		end
	end
end

local function FindBug(bugs, message, stack)
	local first = FirstLine(stack)
	for i = 1, #bugs do
		local b = bugs[i]
		if b.message == message and FirstLine(b.stack) == first then return i, b end
	end
end

local function CapBugs(bugs)
	while #bugs > 50 do bugs[#bugs] = nil end
end

local function TextOf(v, max)
	if type(v) == "string" and not IsSecret(v) then return Clip(v, max) end
	if v == nil then return "" end
	return Safe(v)
end

local function Capture(message, stack, locals, source)
	message = TextOf(message, 4000)
	stack = TextOf(stack, 8000)
	locals = TextOf(locals, 8000)
	local bugs = D.Settings().bugs
	local stamp, now, combat = Stamp(), Now(), InCombat() == true
	local i, bug = FindBug(bugs, message, stack)
	local isNew = bug == nil
	if bug then
		bug.count = (tonumber(bug.count) or 1) + 1
		bug.last, bug.time, bug.combat, bug.session = stamp, now, combat, D.session
		table.remove(bugs, i)
	else
		local maxId = 0
		for j = 1, #bugs do
			local id = tonumber(bugs[j].id)
			if id and id > maxId then maxId = id end
		end
		bug = {
			id = maxId + 1, message = message, stack = stack, locals = locals, count = 1,
			first = stamp, last = stamp, session = D.session, combat = combat,
			version = Version(), build = Build(), source = source,
			addon = GuessAddon(stack, message), time = now,
		}
	end
	table.insert(bugs, 1, bug)
	CapBugs(bugs)
	bug.lastVersion, bug.lastBuild = Version(), Build()
	D.sessionErrors = D.sessionErrors + 1
	local full = stack ~= "" and (message .. "\n" .. stack) or message
	if source == "blocked" or source == "forbidden" then
		Log("addon", "error", FirstLine(message), full)
	elseif source == "warning" then
		Log("error", "warn", FirstLine(message), full)
	else
		Log("error", "error", FirstLine(message), full)
	end
	for j = 1, #bugListeners do pcall(bugListeners[j], bug, isNew) end
	return bug
end

local function SafeCapture(...)
	local ok, bug = pcall(Capture, ...)
	if ok then return bug end
end

-- Handled API/display failures belong in the same Results report as Lua errors.
function D.CaptureError(message, source)
	local stack = ""
	if type(debugstack) == "function" then
		local ok, value = pcall(debugstack, 2)
		if ok then stack = value end
	end
	return SafeCapture(message, stack, "", source or "handled")
end

local handling, prevHandler = false, nil
local function Handler(msg, ...)
	if handling then return msg end
	handling = true
	local stack, locals
	if type(debugstack) == "function" then
		local ok, s = pcall(debugstack, 3)
		if ok then stack = s end
	elseif debug and type(debug.traceback) == "function" then
		local ok, s = pcall(debug.traceback, "", 3)
		if ok and type(s) == "string" then stack = s:gsub("^%s*stack traceback:%s*", "") end
	end
	if type(debuglocals) == "function" then
		local ok, s = pcall(debuglocals, 3)
		if ok then locals = s end
	end
	SafeCapture(msg, stack, locals, "lua")
	local ok, r = true, msg
	local p = prevHandler
	if type(p) == "function" and p ~= Handler then ok, r = pcall(p, msg, ...) end
	handling = false
	if ok then return r end
	return msg
end

local BG_SOURCES = {
	ADDON_ACTION_BLOCKED = "blocked", MACRO_ACTION_BLOCKED = "blocked",
	ADDON_ACTION_FORBIDDEN = "forbidden", MACRO_ACTION_FORBIDDEN = "forbidden", LUA_WARNING = "warning",
}

local function OnBugGrabbed(_, err)
	if type(err) ~= "table" then return end
	local msg = err.message
	local tag = type(msg) == "string" and not IsSecret(msg) and msg:match("^%[([%u_]+)%]")
	SafeCapture(msg, err.stack, err.locals, (tag and BG_SOURCES[tag]) or "lua")
end

local bugGrabberHooked = false
local function BugGrabberPresent()
	local bg = _G.BugGrabber
	return type(bg) == "table" and type(bg.RegisterCallback) == "function"
end

local function InstallHandler()
	if BugGrabberPresent() then
		if not bugGrabberHooked then
			bugGrabberHooked = pcall(_G.BugGrabber.RegisterCallback, D, "BugGrabber_BugGrabbed", OnBugGrabbed)
		end
		return
	end
	if type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then return end
	local ok, cur = pcall(geterrorhandler)
	if not ok or cur == Handler then return end
	prevHandler = cur
	pcall(seterrorhandler, Handler)
end

local function SafeCreateFrame()
	local ok, f = pcall(CreateFrame, "Frame")
	if ok then return f end
end
local ev = SafeCreateFrame()
local trace = SafeCreateFrame()
local tracing = false

function D.IsTracingEvents() return tracing end

function D.SetTraceEvents(on)
	on = on and true or false
	tracing = on
	if trace then
		if on then pcall(trace.RegisterAllEvents, trace) else pcall(trace.UnregisterAllEvents, trace) end
	end
	D.Settings().traceEvents = on
	Log("system", "info", on and "event trace on" or "event trace off")
end

if trace then
	trace:SetScript("OnEvent", function(_, event, ...)
		if not tracing or event == "COMBAT_LOG_EVENT_UNFILTERED" then return end
		if IsSecret(event) or type(event) ~= "string" then return end
		if D.NOISY[event] and not D.traceNoisy then return end
		local n = select("#", ...)
		local detail
		if n > 0 then
			local lines = {}
			for i = 1, n do lines[i] = "arg" .. i .. " = " .. Safe((select(i, ...))) end
			detail = table.concat(lines, "\n")
		end
		Log("event", "trace", event, detail)
	end)
end

local function SpellNameOf(id)
	local fn = AL.SpellName or GetSpellInfo
	local v = Read1(fn, id)
	if type(v) == "string" then return v end
end

local CAST_LEVELS = {
	UNIT_SPELLCAST_SENT = "debug", UNIT_SPELLCAST_START = "info", UNIT_SPELLCAST_STOP = "debug",
	UNIT_SPELLCAST_SUCCEEDED = "info", UNIT_SPELLCAST_FAILED = "warn", UNIT_SPELLCAST_FAILED_QUIET = "debug",
	UNIT_SPELLCAST_INTERRUPTED = "warn", UNIT_SPELLCAST_CHANNEL_START = "info", UNIT_SPELLCAST_CHANNEL_STOP = "debug",
}

local playerGUID
local function PlayerGUID()
	if playerGUID then return playerGUID end
	local g = Read1(UnitGUID, "player")
	if type(g) == "string" then playerGUID = g end
	return playerGUID
end

local lastSpellKey, lastReasonKey, hasLast = nil, nil, false
local lastReasonText
local lastCallAt
local origNext, origSay
local profile

-- A read-only view of the real recommendation stream. A fresh report can
-- include an unchanged/pooling decision without calling NextSpell again.
function D.RotationState()
	local spell = "unobserved"
	if hasLast then
		spell = lastSpellKey == nil and "none" or (lastSpellKey == SECRET and "<secret>" or Safe(lastSpellKey))
	end
	return { observed = hasLast, spell = spell, reason = lastReasonText, at = lastCallAt, calls = D.perf.calls }
end

local function PowerType()
	local v = Read1(UnitPowerType, "player")
	if type(v) == "number" then return v end
end

local function Snap()
	local s = {}
	s.combat = InCombat()
	local exists = Read1(UnitExists, "target")
	s.hostile = exists and (Read1(UnitCanAttack, "player", "target") and true or false) or false
	if type(AL.Power) == "function" then
		local ok, v = pcall(AL.Power, PowerType())
		s.power = ok and v ~= nil and Safe(v) or "unknown"
	end
	if type(AL.ComboPoints) == "function" then
		local ok, v = pcall(AL.ComboPoints)
		s.combo = ok and v ~= nil and Safe(v) or "unknown"
	end
	local names = {}
	if type(AL.queue) == "table" then
		for i = 1, #AL.queue do names[#names + 1] = Safe(type(AL.queue[i]) == "table" and AL.queue[i].spell) end
	end
	s.queue = #names > 0 and table.concat(names, ", ") or "empty"
	s.burst = AL.burst and true or false
	if type(AL.S) == "function" then
		local ok, p = pcall(AL.S)
		s.aoe = ok and type(p) == "table" and p.aoe and true or false
	end
	return s
end

local function OnSuggestion(spell, reason)
	lastReasonText = reason ~= nil and Safe(reason) or nil
	local label = spell == nil and "none" or Safe(spell)
	Log("rotation", "info", "→ " .. label .. " (" .. (lastReasonText or "nil") .. ")", Snap())
end

local function KeyOf(v)
	if IsSecret(v) then return SECRET end
	return v
end

local perf = D.perf
local function Finish(t0, ...)
	if t0 then
		local ok, t1 = pcall(profile)
		if ok and type(t1) == "number" then
			local dt = t1 - t0
			perf.lastMs = dt
			perf.totalMs = perf.totalMs + dt
			if dt > perf.maxMs then perf.maxMs = dt end
		end
	end
	perf.calls = perf.calls + 1
	lastCallAt = Now()
	local spell, reason = ...
	local sk, rk = KeyOf(spell), KeyOf(reason)
	if not hasLast or sk ~= lastSpellKey or rk ~= lastReasonKey then
		hasLast, lastSpellKey, lastReasonKey = true, sk, rk
		pcall(OnSuggestion, spell, reason)
	end
	return ...
end

local function WrappedNext(...)
	local t0
	if profile then
		local ok, t = pcall(profile)
		if ok and type(t) == "number" then t0 = t end
	end
	return Finish(t0, origNext(...))
end

local function WrappedSay(text, ...)
	if type(text) == "string" and not IsSecret(text) then
		Log("system", "info", StripColors(text))
	else
		Log("system", "info", text)
	end
	return origSay(text, ...)
end

local function WrapCore()
	if type(debugprofilestop) == "function" then profile = debugprofilestop end
	if type(AL.NextSpell) == "function" and AL.NextSpell ~= WrappedNext then
		origNext = AL.NextSpell
		AL.NextSpell = WrappedNext
	end
	if type(AL.Say) == "function" and AL.Say ~= WrappedSay then
		origSay = AL.Say
		AL.Say = WrappedSay
	end
end

local function MergeMem(saved)
	for k, v in pairs(mem) do
		if k ~= "bugs" and saved[k] == nil then saved[k] = v end
	end
	Fill(saved)
	local src = type(mem.bugs) == "table" and mem.bugs or {}
	for i = #src, 1, -1 do
		local b = src[i]
		b.session = D.session
		local j, old = FindBug(saved.bugs, b.message, b.stack)
		if old then
			old.count = (tonumber(old.count) or 1) + (tonumber(b.count) or 1)
			old.last, old.time, old.session = b.last, b.time, b.session
			table.remove(saved.bugs, j)
			table.insert(saved.bugs, 1, old)
		else
			local maxId = 0
			for n = 1, #saved.bugs do
				local id = tonumber(saved.bugs[n].id)
				if id and id > maxId then maxId = id end
			end
			b.id = maxId + 1
			table.insert(saved.bugs, 1, b)
		end
	end
	CapBugs(saved.bugs)
	mem = {}
end

local H = {}

function H.ADDON_LOADED(name)
	if name ~= ADDON or dbReady then return end
	local ok, saved = pcall(SavedTable)
	if not ok or not saved then return end
	saved.session = (tonumber(saved.session) or 0) + 1
	D.session = saved.session
	pcall(MergeMem, saved)
	dbReady = true
	Log("system", "info", "ADDON_LOADED " .. ADDON, { version = Version(), build = Build(), session = D.session })
	if D.Settings().traceEvents then D.SetTraceEvents(true) end
end

function H.PLAYER_LOGIN()
	WrapCore()
	InstallHandler()
	PlayerGUID()
	Log("system", "info", "PLAYER_LOGIN")
end

function H.PLAYER_ENTERING_WORLD(initial, reload)
	InstallHandler()
	PlayerGUID()
	Log("system", "info", "PLAYER_ENTERING_WORLD", { isInitialLogin = initial, isReloadingUi = reload })
end

function H.SPELLS_CHANGED() Log("system", "debug", "SPELLS_CHANGED") end

function H.LEARNED_SPELL_IN_TAB(...)
	Log("system", "info", "LEARNED_SPELL_IN_TAB", { arg1 = (select(1, ...)), arg2 = (select(2, ...)) })
end

function H.UI_ERROR_MESSAGE(a1, a2)
	local msg = a2
	if type(msg) ~= "string" or IsSecret(msg) then msg = a1 end
	Log("system", "warn", msg)
end

function H.PLAYER_REGEN_DISABLED() Log("combat", "info", "combat: entered") end
function H.PLAYER_REGEN_ENABLED() Log("combat", "info", "combat: left") end
function H.PLAYER_DEAD() Log("combat", "warn", "player died") end
function H.PLAYER_LEVEL_UP(level) Log("combat", "info", "level up: " .. Safe(level)) end

function H.PLAYER_TARGET_CHANGED()
	local exists = Read1(UnitExists, "target")
	if not exists then
		Log("combat", "info", "target cleared")
		return
	end
	local d = {
		name = Show(UnitName, "target"),
		level = Show(UnitLevel, "target"),
		classification = Show(UnitClassification, "target"),
		hostile = Show(UnitCanAttack, "player", "target"),
		dead = Show(UnitIsDeadOrGhost, "target"),
		creatureType = Show(UnitCreatureType, "target"),
	}
	Log("combat", "info", "target: " .. d.name .. " (level " .. d.level .. " " .. d.classification .. ")", d)
end

local function BlockedEvent(source, event, a1, a2)
	local msg
	if event == "MACRO_ACTION_BLOCKED" or event == "MACRO_ACTION_FORBIDDEN" then
		msg = ("[%s] Macro tried to call the protected function '%s'."):format(event, Safe(a1))
	else
		msg = ("[%s] AddOn '%s' tried to call the protected function '%s'."):format(event, Safe(a1), Safe(a2))
	end
	local stack = ""
	if type(debugstack) == "function" then
		local ok, value = pcall(debugstack, 3)
		if ok and type(value) == "string" and not IsSecret(value) then stack = value end
	elseif debug and type(debug.traceback) == "function" then
		local ok, value = pcall(debug.traceback, "", 3)
		if ok and type(value) == "string" and not IsSecret(value) then stack = value end
	end
	local bug = SafeCapture(msg, stack, "", source)
	if bug and type(a1) == "string" and not IsSecret(a1) and event:find("^ADDON") then bug.addon = a1 end
end

local function OwnCapture() return not BugGrabberPresent() end

function H.ADDON_ACTION_BLOCKED(a1, a2) if OwnCapture() then BlockedEvent("blocked", "ADDON_ACTION_BLOCKED", a1, a2) end end
function H.MACRO_ACTION_BLOCKED(a1) if OwnCapture() then BlockedEvent("blocked", "MACRO_ACTION_BLOCKED", a1) end end
function H.ADDON_ACTION_FORBIDDEN(a1, a2) if OwnCapture() then BlockedEvent("forbidden", "ADDON_ACTION_FORBIDDEN", a1, a2) end end

function H.LUA_WARNING(a1, a2)
	if not OwnCapture() then return end
	local text = a2
	if type(text) ~= "string" or IsSecret(text) then text = a1 end
	SafeCapture("[LUA_WARNING] " .. Safe(text), "", "", "warning")
end

local function Cast(event, unit, a2, a3, a4)
	if IsSecret(unit) or unit ~= "player" then return end
	local name
	for _, a in ipairs({ a4, a3 }) do
		if not name and type(a) == "number" and not IsSecret(a) then name = SpellNameOf(a) end
	end
	if not name and event ~= "UNIT_SPELLCAST_SENT" and type(a2) == "string" and not IsSecret(a2) and not a2:find("^Cast%-") then
		name = a2
	end
	Log("cast", CAST_LEVELS[event], event:gsub("^UNIT_SPELLCAST_", "") .. " " .. (name or "?"),
		{ arg2 = a2, arg3 = a3, arg4 = a4 })
end
for event in pairs(CAST_LEVELS) do
	H[event] = function(...) Cast(event, ...) end
end

local AURA_SUBS = { SPELL_AURA_APPLIED = "applied", SPELL_AURA_REMOVED = "removed" }

local function CombatLog()
	if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
	local ok, _, sub, _, src, srcName, _, _, dst, dstName, _, _, p12, p13, _, p15 = pcall(CombatLogGetCurrentEventInfo)
	if not ok or IsSecret(sub) or type(sub) ~= "string" then return end
	local me = PlayerGUID()
	if not me then return end
	local fromMe = not IsSecret(src) and src == me
	local toMe = not IsSecret(dst) and dst == me
	if not fromMe and not toMe then return end
	local swing = sub:find("^SWING") ~= nil
	local spell = swing and "Melee" or Safe(p13)
	local who = Safe(srcName) .. " → " .. Safe(dstName)
	if sub == "SPELL_CAST_START" or sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_CAST_FAILED" then
		Log("combat", sub == "SPELL_CAST_FAILED" and "warn" or "info", sub .. " " .. spell .. ": " .. who,
			{ spellId = p12, failedType = sub == "SPELL_CAST_FAILED" and p15 or nil })
	elseif sub:find("_MISSED$") then
		Log("combat", "info", sub .. " " .. spell .. ": " .. who, { missType = swing and p12 or p15 })
	elseif AURA_SUBS[sub] then
		Log("aura", "info", "aura " .. AURA_SUBS[sub] .. " " .. spell .. ": " .. who, { spellId = p12, auraType = p15 })
	elseif sub:find("_DAMAGE$") then
		Log("combat", "debug", sub .. " " .. spell .. ": " .. who, { amount = swing and p12 or p15 })
	elseif sub == "UNIT_DIED" or sub == "PARTY_KILL" then
		Log("combat", "info", sub .. ": " .. who)
	end
end
H.COMBAT_LOG_EVENT_UNFILTERED = CombatLog

local UNIT_EVENTS = {
	"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local powerTick, powerState = 0, nil
local function PowerWatch(dt)
	powerTick = powerTick + (type(dt) == "number" and dt or 0)
	if powerTick < 0.5 then return end
	powerTick = 0
	if not origNext or type(AL.Power) ~= "function" then return end
	local pt = PowerType()
	local ok, v = pcall(AL.Power, pt)
	local readable = ok and v ~= nil
	if powerState ~= nil and readable ~= powerState then
		if readable then
			Log("power", "info", "power readable again (type " .. Safe(pt) .. ")", { value = v })
		else
			Log("power", "warn", "power unknown (type " .. Safe(pt) .. ")", { error = not ok and v or nil })
		end
	end
	powerState = readable
end

if ev then
	for event in pairs(H) do
		if not CAST_LEVELS[event] and (event ~= "COMBAT_LOG_EVENT_UNFILTERED"
			or type(CombatLogGetCurrentEventInfo) == "function") then pcall(ev.RegisterEvent, ev, event) end
	end
	for _, event in ipairs(UNIT_EVENTS) do
		if not pcall(ev.RegisterUnitEvent, ev, event, "player") then pcall(ev.RegisterEvent, ev, event) end
	end
	ev:SetScript("OnEvent", function(_, event, ...)
		local h = H[event]
		if h then pcall(h, ...) end
	end)
	ev:SetScript("OnUpdate", function(_, dt) pcall(PowerWatch, dt) end)
end

InstallHandler()

local SPELL, BOOK, BANK = {}, {}, {}
local PROBES = {
	{ 'UnitPower("player")', "UnitPower", "player" },
	{ 'UnitPower("player", 0)', "UnitPower", "player", 0 },
	{ 'UnitPower("player", 1)', "UnitPower", "player", 1 },
	{ 'UnitPower("player", 3)', "UnitPower", "player", 3 },
	{ 'UnitPower("player", 4)', "UnitPower", "player", 4 },
	{ 'UnitPowerMax("player")', "UnitPowerMax", "player" },
	{ 'UnitPowerType("player")', "UnitPowerType", "player" },
	{ 'UnitHealth("player")', "UnitHealth", "player" },
	{ 'UnitHealthMax("player")', "UnitHealthMax", "player" },
	{ 'UnitHealth("target")', "UnitHealth", "target" },
	{ 'UnitHealthMax("target")', "UnitHealthMax", "target" },
	{ 'UnitLevel("player")', "UnitLevel", "player" },
	{ 'UnitLevel("target")', "UnitLevel", "target" },
	{ 'GetComboPoints("player", "target")', "GetComboPoints", "player", "target" },
	{ 'UnitBuff("player", 1)', "UnitBuff", "player", 1 },
	{ 'UnitAura("player", 1, "HELPFUL")', "UnitAura", "player", 1, "HELPFUL" },
	{ 'C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")', "C_UnitAuras.GetAuraDataByIndex", "player", 1, "HELPFUL" },
	{ 'UnitDebuff("target", 1)', "UnitDebuff", "target", 1 },
	{ "GetSpellCooldown(spell)", "GetSpellCooldown", SPELL },
	{ "C_Spell.GetSpellCooldown(spell)", "C_Spell.GetSpellCooldown", SPELL },
	{ "IsUsableSpell(spell)", "IsUsableSpell", SPELL },
	{ "C_Spell.IsSpellUsable(spell)", "C_Spell.IsSpellUsable", SPELL },
	{ 'IsSpellInRange(spell, "target")', "IsSpellInRange", SPELL, "target" },
	{ 'C_Spell.IsSpellInRange(spell, "target")', "C_Spell.IsSpellInRange", SPELL, "target" },
	{ 'UnitCastingInfo("target")', "UnitCastingInfo", "target" },
	{ 'UnitCreatureType("target")', "UnitCreatureType", "target" },
	{ 'UnitClassification("target")', "UnitClassification", "target" },
	{ 'UnitAffectingCombat("player")', "UnitAffectingCombat", "player" },
	{ 'UnitCanAttack("player", "target")', "UnitCanAttack", "player", "target" },
	{ 'UnitIsDeadOrGhost("target")', "UnitIsDeadOrGhost", "target" },
	{ 'CheckInteractDistance("target", 3)', "CheckInteractDistance", "target", 3 },
	{ "GetTotemInfo(1)", "GetTotemInfo", 1 },
	{ "GetWeaponEnchantInfo()", "GetWeaponEnchantInfo" },
	{ "GetShapeshiftForm()", "GetShapeshiftForm" },
	{ 'UnitGUID("target")', "UnitGUID", "target" },
	{ 'GetSpellBookItemName(1, "spell")', "GetSpellBookItemName", 1, BOOK },
	{ "C_SpellBook.GetSpellBookItemName(1, Player)", "C_SpellBook.GetSpellBookItemName", 1, BANK },
	{ 'GetSpellAvailableLevel(1, "spell")', "GetSpellAvailableLevel", 1, BOOK },
	{ "C_SpellBook.GetSpellBookItemLevelLearned(1, Player)", "C_SpellBook.GetSpellBookItemLevelLearned", 1, BANK },
	{ "GetActionInfo(1)", "GetActionInfo", 1 },
	{ 'UnitAttackSpeed("player")', "UnitAttackSpeed", "player" },
	{ 'UnitRangedDamage("player")', "UnitRangedDamage", "player" },
	{ "GetItemCount(6948)", "GetItemCount", 6948 },
	{ "IsMounted()", "IsMounted" },
	{ "GetNumGroupMembers()", "GetNumGroupMembers" },
	{ "CombatLogGetCurrentEventInfo()", "CombatLogGetCurrentEventInfo" },
	{ "GetNetStats()", "GetNetStats" },
	{ "GetFramerate()", "GetFramerate" },
}

local function Resolve(path)
	local ns, name = path:match("^([%w_]+)%.([%w_]+)$")
	local f
	if ns then
		local t = _G[ns]
		if type(t) ~= "table" then return nil end
		f = t[name]
	else
		f = _G[path]
	end
	if type(f) == "function" then return f end
end

local function ProbeSpell()
	if type(AL.known) == "table" then
		local ok, k = pcall(next, AL.known)
		if ok and type(k) == "string" and not IsSecret(k) then return k end
	end
	return "Attack"
end

local function TableHasSecret(t)
	if type(t) ~= "table" or IsSecret(t) then return false end
	local found = false
	pcall(function()
		for k, v in pairs(t) do
			if IsSecret(k) or IsSecret(v) then found = true; break end
		end
	end)
	return found
end

local function Pack(...) return select("#", ...), { ... } end

local function ProbeOne(p, spell)
	local fn = Resolve(p[2])
	if not fn then return { api = p[1], status = "missing", value = "missing" } end
	local args, n = {}, #p - 2
	for i = 1, n do
		local a = p[i + 2]
		if a == SPELL then a = spell
		elseif a == BOOK then a = BOOKTYPE_SPELL or "spell"
		elseif a == BANK then
			a = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		end
		args[i] = a
	end
	local cnt, r = Pack(pcall(fn, unpack(args, 1, n)))
	if not r[1] then return { api = p[1], status = "error", value = Safe(r[2]) } end
	local secret, any = false, false
	local parts = {}
	for i = 2, cnt do
		local v = r[i]
		if IsSecret(v) or TableHasSecret(v) then secret = true end
		if v ~= nil then any = true end
		parts[#parts + 1] = Safe(v)
	end
	local status = secret and "secret" or (any and "ok" or "nil")
	return { api = p[1], status = status, value = #parts > 0 and table.concat(parts, ", ") or "nil" }
end

function D.RunProbe()
	local combat = InCombat() == true
	local spell = ProbeSpell()
	local run = { clock = Clock(Now()), date = Stamp(), combat = combat, build = Build(), spell = spell, results = {} }
	local tally = { ok = 0, secret = 0, error = 0, ["nil"] = 0, missing = 0 }
	for i = 1, #PROBES do
		local ok, res = pcall(ProbeOne, PROBES[i], spell)
		if not ok then res = { api = PROBES[i][1], status = "error", value = Safe(res) } end
		run.results[i] = res
		tally[res.status] = tally[res.status] + 1
	end
	pcall(function()
		D.Settings().probe[combat and "combat" or "ooc"] = run
	end)
	Log("probe", "info", ("probe (%s, spell %s): %d readable, %d secret, %d error, %d empty, %d missing"):format(
		combat and "in combat" or "out of combat", spell, tally.ok, tally.secret, tally.error, tally["nil"], tally.missing))
	for i = 1, #run.results do
		local r = run.results[i]
		Log("probe", "debug", r.api .. " → " .. r.status, r.value)
	end
	return run
end

local function Val(v, st)
	if st == "secret" then return "<secret>", "secret" end
	if st == "ok" then return Safe(v), nil end
	if st == "error" then return "error", "bad" end
	return "unknown", "unknown"
end

local function Row(rows, label, fn)
	local ok, v, st = pcall(fn)
	if not ok then
		rows[#rows + 1] = { label = label, value = "error: " .. Safe(v), status = "bad" }
	else
		rows[#rows + 1] = { label = label, value = type(v) == "string" and v or Safe(v), status = st }
	end
end

local function SortedKeys(t)
	local keys = {}
	if type(t) ~= "table" then return keys end
	for k in pairs(t) do
		if type(k) == "string" and not IsSecret(k) then keys[#keys + 1] = k end
	end
	table.sort(keys)
	return keys
end

local function Seconds(left)
	if type(left) ~= "number" or IsSecret(left) then return "?" end
	if left < 0 then left = 0 end
	return string.format("%ds", math.floor(left + 0.5))
end

local function DebugState()
	if type(AL.DebugState) ~= "function" then return nil end
	local ok, st = pcall(AL.DebugState)
	if ok and type(st) == "table" then return st end
end

local SECTIONS = {}

SECTIONS[1] = { "DEBUG_SEC_SESSION", function(rows)
	Row(rows, "version", function() return Version() end)
	Row(rows, "build", function() return Build() end)
	Row(rows, "locale", function() return Val(Read1(GetLocale)) end)
	Row(rows, "class", function()
		local ok, loc, token = pcall(UnitClass, "player")
		if not ok then return "error", "bad" end
		return Safe(loc) .. " (" .. Safe(token) .. ")"
	end)
	Row(rows, "level", function() return Val(Read1(UnitLevel, "player")) end)
	Row(rows, "session", function() return Safe(D.session) end)
	Row(rows, "uptime", function()
		local s = math.floor(Now() - loadTime)
		return string.format("%dm %02ds", math.floor(s / 60), s % 60)
	end)
	Row(rows, "zone", function() return Val(Read1(GetRealZoneText or GetZoneText)) end)
end }

SECTIONS[2] = { "DEBUG_SEC_PERF", function(rows)
	Row(rows, "fps", function()
		local v, st = Read1(GetFramerate)
		if type(v) ~= "number" then return Val(v, st) end
		return string.format("%.0f", v), v < 20 and "warn" or "ok"
	end)
	Row(rows, "latencyHome", function()
		if type(GetNetStats) ~= "function" then return "unknown", "unknown" end
		local ok, _, _, home = pcall(GetNetStats)
		if not ok or IsSecret(home) or type(home) ~= "number" then return "unknown", "unknown" end
		return home .. " ms", home > 300 and "warn" or "ok"
	end)
	Row(rows, "latencyWorld", function()
		if type(GetNetStats) ~= "function" then return "unknown", "unknown" end
		local ok, _, _, _, world = pcall(GetNetStats)
		if not ok or IsSecret(world) or type(world) ~= "number" then return "unknown", "unknown" end
		return world .. " ms", world > 300 and "warn" or "ok"
	end)
	Row(rows, "memoryKB", function()
		local ns = type(C_AddOns) == "table" and C_AddOns or {}
		local upd = UpdateAddOnMemoryUsage or ns.UpdateAddOnMemoryUsage
		local get = GetAddOnMemoryUsage or ns.GetAddOnMemoryUsage
		if type(upd) == "function" then pcall(upd) end
		local v, st = Read1(get, ADDON)
		if type(v) ~= "number" then return Val(v, st) end
		return string.format("%.0f", v)
	end)
	Row(rows, "nextSpellCalls", function() return Safe(perf.calls) end)
	Row(rows, "nextSpellAvgMs", function()
		if perf.calls == 0 then return "unknown", "unknown" end
		local avg = perf.totalMs / perf.calls
		return string.format("%.3f", avg), avg > 1 and "warn" or "ok"
	end)
	Row(rows, "nextSpellMaxMs", function() return string.format("%.3f", perf.maxMs) end)
	Row(rows, "nextSpellLastMs", function() return string.format("%.3f", perf.lastMs) end)
	Row(rows, "logEntries", function() return Safe(count) end)
	Row(rows, "errorsThisSession", function() return Safe(D.sessionErrors), D.sessionErrors > 0 and "bad" or "ok" end)
end }

SECTIONS[3] = { "DEBUG_SEC_COMBAT", function(rows)
	Row(rows, "inCombat", function()
		local c = InCombat()
		if c == nil then return "unknown", "unknown" end
		return Safe(c)
	end)
	local exists = Read1(UnitExists, "target")
	Row(rows, "target", function()
		if not exists then return "none" end
		return Val(Read1(UnitName, "target"))
	end)
	if exists then
		Row(rows, "targetLevel", function() return Val(Read1(UnitLevel, "target")) end)
		Row(rows, "targetClassification", function() return Val(Read1(UnitClassification, "target")) end)
		Row(rows, "targetHostile", function() return Val(Read1(UnitCanAttack, "player", "target")) end)
		Row(rows, "targetDead", function() return Val(Read1(UnitIsDeadOrGhost, "target")) end)
	end
	Row(rows, "AL.TargetInMelee", function() return Val(Read1(AL.TargetInMelee)) end)
	Row(rows, "AL.TargetCasting", function() return Val(Read1(AL.TargetCasting)) end)
end }

SECTIONS[4] = { "DEBUG_SEC_RESOURCES", function(rows)
	for _, t in ipairs({ 0, 1, 3 }) do
		Row(rows, "AL.Power(" .. t .. ")", function()
			local v, st = Read1(AL.Power, t)
			if st == "nil" then return "unknown", "unknown" end
			return Val(v, st)
		end)
	end
	Row(rows, 'UnitPower("player")', function()
		local v, st = Read1(UnitPower, "player")
		if st == "ok" then return Safe(v), "ok" end
		if st == "secret" then return "<secret>", "secret" end
		if st == "error" then return "error", "bad" end
		return st, "unknown"
	end)
	Row(rows, "AL.ManaPercent", function() return Val(Read1(AL.ManaPercent)) end)
	Row(rows, "AL.HealthPercent(player)", function() return Val(Read1(AL.HealthPercent, "player")) end)
	Row(rows, "AL.HealthPercent(target)", function() return Val(Read1(AL.HealthPercent, "target")) end)
	Row(rows, "AL.ComboPoints", function() return Val(Read1(AL.ComboPoints)) end)
end }

SECTIONS[5] = { "DEBUG_SEC_ROTATION", function(rows)
	Row(rows, "module", function()
		local present = type(AL.rotations) == "table" and AL.playerClass and AL.rotations[AL.playerClass] ~= nil
		return Safe(AL.playerClass) .. (present and " loaded" or " missing"), present and "ok" or "warn"
	end)
	Row(rows, "lastSuggestion", function()
		if AL.lastSuggestion == nil then return "none" end
		return Safe(AL.lastSuggestion)
	end)
	Row(rows, "lastReason", function() return lastReasonText or "none" end)
	Row(rows, "paused", function()
		if type(AL.Paused) ~= "function" or type(AL.S) ~= "function" then return "unknown", "unknown" end
		local p = AL.Paused(AL.S())
		return Safe(p), p and "warn" or nil
	end)
	Row(rows, "burst", function() return Safe(AL.burst and true or false) end)
	Row(rows, "aoe", function()
		if type(AL.S) ~= "function" then return "unknown", "unknown" end
		return Safe(AL.S().aoe and true or false)
	end)
	Row(rows, "queue", function()
		local names = {}
		if type(AL.queue) == "table" then
			for i = 1, #AL.queue do names[#names + 1] = Safe(AL.queue[i].spell) end
		end
		return #names > 0 and table.concat(names, ", ") or "empty"
	end)
end }

SECTIONS[6] = { "DEBUG_SEC_AURAS", function(rows)
	local st = DebugState()
	if not st then
		rows[#rows + 1] = { label = "AL.DebugState", value = "unavailable", status = "unknown" }
		return
	end
	Row(rows, "tooltipValid", function() return Safe(st.tooltipValid), st.tooltipValid and "ok" or "warn" end)
	Row(rows, "tooltipBuffs", function()
		local k = SortedKeys(st.tooltipBuffs)
		return #k > 0 and table.concat(k, ", ") or "none"
	end)
	Row(rows, "selfBuffs", function()
		local now, out = time(), {}
		for _, name in ipairs(SortedKeys(st.selfBuffs)) do
			local exp = st.selfBuffs[name]
			out[#out + 1] = name .. " " .. Seconds(type(exp) == "number" and not IsSecret(exp) and exp - now or nil)
		end
		return #out > 0 and table.concat(out, ", ") or "none"
	end)
	Row(rows, "debuffValid", function() return Safe(st.debuffValid), st.debuffValid and "ok" or "warn" end)
	Row(rows, "tooltipDebuffs", function()
		local k = SortedKeys(st.tooltipDebuffs)
		return #k > 0 and table.concat(k, ", ") or "none"
	end)
	Row(rows, "targetDebuffs", function()
		local now, out = Now(), {}
		for _, name in ipairs(SortedKeys(st.targetDebuffs)) do
			local d = st.targetDebuffs[name]
			local exp = type(d) == "table" and d.expires or nil
			out[#out + 1] = name .. " " .. Seconds(type(exp) == "number" and not IsSecret(exp) and exp - now or nil)
		end
		return #out > 0 and table.concat(out, ", ") or "none"
	end)
end }

SECTIONS[7] = { "DEBUG_SEC_COOLDOWNS", function(rows)
	local st = DebugState()
	if not st then
		rows[#rows + 1] = { label = "AL.DebugState", value = "unavailable", status = "unknown" }
		return
	end
	local keys = SortedKeys(st.cdExpires)
	if #keys == 0 then
		rows[#rows + 1] = { label = "cooldowns", value = "none" }
		return
	end
	for _, name in ipairs(keys) do
		Row(rows, name, function()
			local exp = st.cdExpires[name]
			if type(exp) ~= "number" or IsSecret(exp) then return "unknown", "unknown" end
			return Seconds(exp - time())
		end)
	end
end }

SECTIONS[8] = { "DEBUG_SEC_SPELLBOOK", function(rows)
	Row(rows, "known", function()
		local n = 0
		if type(AL.known) == "table" then for _ in pairs(AL.known) do n = n + 1 end end
		return Safe(n), n > 0 and "ok" or "warn"
	end)
	Row(rows, "unlearned", function()
		local k = SortedKeys(AL.unlearned)
		return #k > 0 and table.concat(k, ", ") or "none", #k > 0 and "warn" or nil
	end)
end }

function D.Snapshot()
	local out = {}
	for i = 1, #SECTIONS do
		local rows = {}
		local ok, err = pcall(SECTIONS[i][2], rows)
		if not ok then rows[#rows + 1] = { label = "error", value = "error: " .. Safe(err), status = "bad" } end
		out[i] = { key = SECTIONS[i][1], rows = rows }
	end
	return out
end

function D.ExportBug(bug)
	if type(bug) ~= "table" then return "" end
	local ok, text = pcall(function()
		local lines = {
			"Message: " .. Safe(bug.message),
			"Count: " .. Safe(bug.count),
			"First seen: " .. Safe(bug.first),
			"Last seen: " .. Safe(bug.last),
			"Session: " .. Safe(bug.session),
			"Combat: " .. (bug.combat and "yes" or "no"),
			"Version: " .. Safe(bug.version),
			"Build: " .. Safe(bug.build),
			"Source: " .. Safe(bug.source),
		}
		if bug.addon then lines[#lines + 1] = "AddOn: " .. Safe(bug.addon) end
		lines[#lines + 1] = "Stack:"
		lines[#lines + 1] = TextOf(bug.stack, 8000)
		lines[#lines + 1] = "Locals:"
		lines[#lines + 1] = TextOf(bug.locals, 8000)
		return table.concat(lines, "\n")
	end)
	return ok and text or ""
end

function D.ExportLog(filter)
	local lines = {}
	for i = 1, count do
		local e = ring[Slot(i)]
		local keep = true
		if type(filter) == "function" then
			local ok, r = pcall(filter, e)
			keep = ok and r and true or false
		end
		if keep then
			local line = ("%s [%s] %s: %s"):format(e.clock, e.level:upper(), e.cat, e.msg)
			if e.count > 1 then line = line .. " (x" .. e.count .. ")" end
			lines[#lines + 1] = line
			if e.detail then lines[#lines + 1] = "    " .. e.detail:gsub("\n", "\n    ") end
		end
	end
	return table.concat(lines, "\n")
end
