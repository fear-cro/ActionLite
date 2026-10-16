local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - Glow.lua
-- ----------------------------------------------------------------------------
-- Surligne sur les barres d'action chaque bouton qui porte le sort suggere.
-- Notre propre texture : la lueur de proc de Blizzard n'est jamais touchee.
-- ============================================================================

-- prefixe, nombre, commande de raccourci (nil = pas de raccourci Blizzard)
local BAR_BUTTONS = {
	{ "ActionButton", 12, "ACTIONBUTTON" }, { "BonusActionButton", 12, "ACTIONBUTTON" },
	{ "MultiBarBottomLeftButton", 12, "MULTIACTIONBAR1BUTTON" },
	{ "MultiBarBottomRightButton", 12, "MULTIACTIONBAR2BUTTON" },
	{ "MultiBarRightButton", 12, "MULTIACTIONBAR3BUTTON" }, { "MultiBarLeftButton", 12, "MULTIACTIONBAR4BUTTON" },
	{ "MultiBar5Button", 12, "MULTIACTIONBAR5BUTTON" }, { "MultiBar6Button", 12, "MULTIACTIONBAR6BUTTON" },
	{ "MultiBar7Button", 12, "MULTIACTIONBAR7BUTTON" },
	{ "BT4Button", 180 }, { "DominosActionButton", 180 }, { "EABButton", 180 },
}
for bar = 1, 10 do BAR_BUTTONS[#BAR_BUTTONS + 1] = { "ElvUI_Bar" .. bar .. "Button", 12 } end
local STANCE_BUTTONS = 10

-- emplacements Classic : 1-12 et 13-24 pages principales, puis barres multiples
local SLOT_COMMANDS = {
	{ 1, 24, "ACTIONBUTTON" }, { 25, 36, "MULTIACTIONBAR3BUTTON" }, { 37, 48, "MULTIACTIONBAR4BUTTON" },
	{ 49, 60, "MULTIACTIONBAR2BUTTON" }, { 61, 72, "MULTIACTIONBAR1BUTTON" }, { 73, 120, "ACTIONBUTTON" },
}

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function SpellNameOf(id)
	if type(id) ~= "number" or Secret(id) then return nil end
	local ok, name = pcall(AL.SpellName, id)
	if ok and type(name) == "string" and not Secret(name) and name ~= "" then return name end
end

-- ---------------------------------------------------------------- couleur
local function ValidColor(c)
	if type(c) ~= "table" then return false end
	for i = 1, 3 do
		local v = c[i]
		if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return false end
	end
	return true
end

local function UIStore()
	local db = ActionLiteDB
	local profiles = type(db) == "table" and db.profiles
	return type(profiles) == "table" and profiles.__ACTIONLITE_UI or nil
end

--- Highlight colour: own key first, then the profiles mirror, then the default blue.
function AL.GlowColor()
	local c = ActionLiteDB and ActionLiteDB.glowColor
	if not ValidColor(c) then
		local ui = UIStore()
		c = type(ui) == "table" and ui.glowColor or nil
	end
	if ValidColor(c) then return c[1], c[2], c[3] end
	return AL.BABY_R, AL.BABY_G, AL.BABY_B
end

-- ---------------------------------------------------------------- lecture des boutons
local function ActionSlot(btn)
	local slot = btn.action
	if type(slot) ~= "number" and btn._state_type == "action" then slot = btn._state_action end
	if type(slot) ~= "number" and type(btn.GetAttribute) == "function" then
		local ok, v = pcall(btn.GetAttribute, btn, "action")
		slot = ok and not Secret(v) and tonumber(v) or nil
	end
	if type(slot) == "number" and not Secret(slot) and slot > 0 then return slot end
end

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function AddCastList(out, payload)
	for part in payload:gmatch("[^;]+") do
		part = Trim(part:gsub("%b[]", ""))
		part = Trim(part:gsub("^!", ""):gsub("%(.-%)%s*$", ""))
		if part ~= "" and not part:find("^%d+$") then out[#out + 1] = part end
	end
end

--- Spell names a macro body casts: #showtooltip and /cast lines, conditions and ! removed.
function AL.MacroSpells(body)
	local out = {}
	if type(body) ~= "string" or Secret(body) then return out end
	for line in body:gmatch("[^\r\n]+") do
		local low = line:lower()
		local tip = low:find("^%s*#show") and line:match("^%s*#%a+%s+(.+)$")
		local cast = (low:find("^%s*/cast%s") or low:find("^%s*/use%s")) and line:match("^%s*/%a+%s+(.+)$")
		if tip then AddCastList(out, tip) end
		if cast then AddCastList(out, cast) end
	end
	return out
end

local function MacroSpellNames(id)
	local names = {}
	if type(GetMacroSpell) == "function" then
		local ok, spellID = pcall(GetMacroSpell, id)
		local name = ok and SpellNameOf(spellID)
		if name then names[1] = name end
	end
	if type(GetMacroInfo) == "function" then
		local ok, _, _, body = pcall(GetMacroInfo, id)
		if ok then
			for _, n in ipairs(AL.MacroSpells(body)) do names[#names + 1] = n end
		end
	end
	return names
end

-- second return true = the client hid this slot, so the map can't be trusted
local function ActionSpellNames(slot)
	local ok, kind, id, sub = pcall(GetActionInfo, slot)
	if not ok or Secret(kind) or Secret(id) or Secret(sub) then return nil, true end
	if kind == "spell" then return { SpellNameOf(id) } end
	if kind ~= "macro" then return nil end
	if sub == "spell" then return { SpellNameOf(id) } end
	return MacroSpellNames(id)
end

-- l'ancienne API renvoie (icone, nom, actif, utilisable), la recente (icone, actif, utilisable, id)
local function StanceName(i)
	if type(GetShapeshiftFormInfo) ~= "function" then return nil end
	local ok, _, a, _, d = pcall(GetShapeshiftFormInfo, i)
	if not ok or Secret(a) or Secret(d) then return nil, true end
	if type(a) == "string" and a ~= "" then return a end
	if type(d) == "number" then return SpellNameOf(d) end
end
AL.StanceName = StanceName

local overlays = setmetatable({}, { __mode = "k" })

-- child frames of secure buttons are only created out of combat
local function Overlay(btn)
	local o = overlays[btn]
	if o or (InCombatLockdown and InCombatLockdown()) then return o end
	local ok, frame = pcall(CreateFrame, "Frame", nil, btn)
	if not ok or not frame then return nil end
	frame:SetAllPoints(btn)
	frame:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
	local tex = frame:CreateTexture(nil, "OVERLAY")
	tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	tex:SetBlendMode("ADD")
	tex:SetPoint("CENTER")
	local w = btn:GetWidth()
	local size = (type(w) == "number" and w > 0 and w or 36) * 1.75
	tex:SetSize(size, size)
	tex:SetVertexColor(AL.GlowColor())
	frame.tex = tex
	local pulse = frame:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.6)
	fade:SetSmoothing("IN_OUT")
	frame.pulse = pulse
	frame:Hide()
	overlays[btn] = frame
	return frame
end

local byName = {}
local commandOf = setmetatable({}, { __mode = "k" })
local nameOf = setmetatable({}, { __mode = "k" })
local keyCache = {}
local dirty, retryAt = true, 0
local signature
local HealOverlay

local function Add(fresh, seen, name, btn)
	if not name or seen[name] then return end
	seen[name] = true
	fresh[name] = fresh[name] or {}
	table.insert(fresh[name], btn)
end

local function Rebuild()
	if type(GetActionInfo) ~= "function" then byName = {} return true, "" end
	local fresh, blocked, sig = {}, false, {}
	for _, def in ipairs(BAR_BUTTONS) do
		for i = 1, def[2] do
			local btn = _G[def[1] .. i]
			if type(btn) == "table" then HealOverlay(btn) end
			local slot = type(btn) == "table" and ActionSlot(btn)
			if slot then
				-- made for every button so a stance page swap in combat still has one
				Overlay(btn)
				commandOf[btn] = def[3] and (def[3] .. i) or false
				nameOf[btn] = def[1] .. i
				local names, hidden = ActionSpellNames(slot)
				if hidden then
					blocked = true
				elseif names then
					local seen = {}
					for _, name in ipairs(names) do Add(fresh, seen, name, btn) end
					sig[#sig + 1] = def[1] .. i .. "=" .. table.concat(names, ",")
				end
			end
		end
	end
	for i = 1, STANCE_BUTTONS do
		local btn = _G["StanceButton" .. i]
		local name, hidden = nil, false
		if type(btn) == "table" then name, hidden = StanceName(i) end
		if hidden then blocked = true end
		if name then
			Overlay(btn)
			commandOf[btn] = "SHAPESHIFTBUTTON" .. i
			Add(fresh, {}, name, btn)
			sig[#sig + 1] = "S" .. i .. "=" .. name
		end
	end
	-- a hidden slot would drop its button: keep the last full map and retry
	if blocked and next(byName) then return false end
	byName = fresh
	return true, table.concat(sig, ";")
end

-- English rotation name and the client's localized name, merged without duplicates
local function ButtonsFor(spell)
	if not spell then return nil end
	local a = byName[spell]
	local localName = AL.LocalName and AL.LocalName(spell)
	local b = localName and localName ~= spell and byName[localName] or nil
	if not b then return a end
	if not a then return b end
	local out, seen = {}, {}
	for _, list in ipairs({ a, b }) do
		for _, btn in ipairs(list) do
			if not seen[btn] then seen[btn] = true out[#out + 1] = btn end
		end
	end
	return out
end
AL.GlowButtonsFor = ButtonsFor

local STALE = {}
local shown = STALE
local lit = {}

-- true when the map changed; the shown glow is then marked stale
local function EnsureMap()
	if not dirty or GetTime() < retryAt then return false end
	local ok, sig = Rebuild()
	if not ok then
		retryAt = GetTime() + 1
		return false
	end
	dirty = false
	if sig == signature then return false end
	signature = sig
	wipe(keyCache)
	shown = STALE
	return true
end

-- ---------------------------------------------------------------- raccourcis
local MODIFIERS = { SHIFT = "S", CTRL = "C", ALT = "A", STRG = "C", META = "M" }

--- Short keybind label: SHIFT-1 -> S1, BUTTON4 -> M4, NUMPAD5 -> N5.
function AL.ShortKey(text)
	if type(text) ~= "string" or Secret(text) or text == "" then return nil end
	local mods, key = "", text
	while true do
		local m, rest = key:match("^(%a+)%-(.+)$")
		local short = m and (MODIFIERS[m:upper()] or (#m == 1 and m:upper()))
		if not short then break end
		mods, key = mods .. short, rest
	end
	local up = key:upper()
	if up == "MOUSEWHEELUP" then key = "WU"
	elseif up == "MOUSEWHEELDOWN" then key = "WD"
	elseif up == "MIDDLEMOUSE" then key = "M3"
	elseif up:find("BUTTON%d+$") or up:find("MOUSE.*%d+$") then key = "M" .. up:match("(%d+)$")
	else key = key:gsub("^NUMPAD", "N"):gsub("^[Nn][Uu][Mm] [Pp][Aa][Dd] ?", "N") end
	return mods .. key
end

local function HotKeyText(btn)
	local hk = btn.HotKey
	if type(hk) ~= "table" and type(btn.GetName) == "function" then
		local ok, name = pcall(btn.GetName, btn)
		if ok and type(name) == "string" then hk = _G[name .. "HotKey"] end
	end
	if type(hk) ~= "table" or type(hk.GetText) ~= "function" then return nil end
	local ok, text = pcall(hk.GetText, hk)
	if not ok or type(text) ~= "string" or Secret(text) or text == "" then return nil end
	if text == RANGE_INDICATOR or text == "●" then return nil end
	return text
end

local function SlotCommand(btn)
	local cmd = commandOf[btn]
	if cmd then return cmd end
	if cmd == false then
		local slot = ActionSlot(btn)
		if not slot then return nil end
		for _, r in ipairs(SLOT_COMMANDS) do
			if slot >= r[1] and slot <= r[2] then return r[3] .. ((slot - r[1]) % 12 + 1) end
		end
	end
end

local function BindingKey(cmd)
	if not cmd or type(GetBindingKey) ~= "function" then return nil end
	local ok, key = pcall(GetBindingKey, cmd)
	if ok and type(key) == "string" and not Secret(key) and key ~= "" then return key end
end

-- Bartender, Dominos and other bar addons bind their buttons as CLICK commands
local function BindingFor(btn)
	return BindingKey(SlotCommand(btn))
		or (nameOf[btn] and BindingKey("CLICK " .. nameOf[btn] .. ":LeftButton"))
end

--- Short keybind of the first bar button holding the spell, or nil.
function AL.KeybindFor(spell)
	if not spell then return nil end
	EnsureMap()
	local cached = keyCache[spell]
	if cached ~= nil then return cached or nil end
	local list = ButtonsFor(spell)
	local found
	for _, btn in ipairs(list or {}) do
		found = AL.ShortKey(HotKeyText(btn) or BindingFor(btn))
		if found then break end
	end
	keyCache[spell] = found or false
	return found
end

-- Priest secret-health action-bar priority layer.
local healOverlays = setmetatable({}, { __mode = "k" })
local healVisibilityCurves, normalVisibilityCurves = {}, {}

local function MakeHealthAlphaCurve(threshold, visibleBelow)
	local r, g, b = AL.GlowColor()
	local key = threshold .. ":" .. r .. ":" .. g .. ":" .. b
	local store = visibleBelow and healVisibilityCurves or normalVisibilityCurves
	if store[key] then return store[key] end
	if not C_CurveUtil or type(C_CurveUtil.CreateColorCurve) ~= "function" or type(CreateColor) ~= "function" then return nil end
	local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
	if not ok or not curve then return nil end
	pcall(curve.SetType, curve, Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	local cut = math.max(0, math.min(100, threshold)) / 100
	local low, high = visibleBelow and 1 or 0, visibleBelow and 0 or 1
	if not pcall(curve.AddPoint, curve, 0, CreateColor(r, g, b, low)) then return nil end
	if not pcall(curve.AddPoint, curve, cut, CreateColor(r, g, b, high)) then return nil end
	if not pcall(curve.AddPoint, curve, 1, CreateColor(r, g, b, high)) then return nil end
	store[key] = curve
	return curve
end

local function ApplyHealthCurve(tex, threshold, visibleBelow)
	local curve = MakeHealthAlphaCurve(threshold, visibleBelow)
	if not tex or not curve or type(UnitHealthPercent) ~= "function" then return false end
	local ok, color = pcall(UnitHealthPercent, "player", true, curve)
	if not ok or not color then return false end
	return pcall(function()
		local r,g,b,a = color:GetRGBA()
		tex:SetVertexColor(r,g,b,a)
	end)
end

function HealOverlay(btn)
	local o = healOverlays[btn]
	if o or (InCombatLockdown and InCombatLockdown()) then return o end
	local ok, frame = pcall(CreateFrame, "Frame", nil, btn)
	if not ok or not frame then return nil end
	frame:SetAllPoints(btn)
	frame:SetFrameLevel((btn:GetFrameLevel() or 1) + 7)
	local tex = frame:CreateTexture(nil, "OVERLAY")
	tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	tex:SetBlendMode("ADD")
	tex:SetPoint("CENTER")
	local w = btn:GetWidth()
	local size = (type(w) == "number" and w > 0 and w or 36) * 1.75
	tex:SetSize(size, size)
	local r, g, b = AL.GlowColor()
	tex:SetVertexColor(r, g, b, 0)
	frame.tex = tex
	frame:Show()
	healOverlays[btn] = frame
	return frame
end

local function PriestHealVisualState()
	if AL.playerClass ~= "PRIEST" then return nil end
	local rotation = AL.rotations and AL.rotations.PRIEST
	if not rotation or type(rotation.SecretHealVisualState) ~= "function" then return nil end
	local ok, spell, threshold = pcall(rotation.SecretHealVisualState)
	if not ok or type(spell) ~= "string" or type(threshold) ~= "number" then return nil end
	return spell, threshold
end

local function ClearHealGlows()
	local r, g, b = AL.GlowColor()
	for _, o in pairs(healOverlays) do
		if o and o.tex then o.tex:SetVertexColor(r, g, b, 0) end
	end
end

local function UpdateSecretPriestHealGlow()
	if not ActionLiteDB or ActionLiteDB.glowHidden then
		ClearHealGlows()
		return
	end
	local r, g, b = AL.GlowColor()
	local spell, threshold = PriestHealVisualState()
	if not spell then
		ClearHealGlows()
		for _, o in pairs(lit) do if o and o.tex then o.tex:SetVertexColor(r, g, b, 1) end end
		return
	end
	-- Below the heal threshold, visually suppress the normal suggestion glow.
	for _, o in pairs(lit) do
		if o and o.tex and not ApplyHealthCurve(o.tex, threshold, false) then o.tex:SetVertexColor(r, g, b, 1) end
	end
	ClearHealGlows()
	local list = ButtonsFor(spell)
	if not list then return end
	for _, btn in ipairs(list) do
		local o = HealOverlay(btn)
		if o and o.tex then ApplyHealthCurve(o.tex, threshold, true) end
	end
end

-- Reuse the display's mutually exclusive public interval rows. These mask
-- frames belong to UIParent, so no children are added to secure action buttons
-- in combat. Only our own textures are anchored to the cached action buttons.
local rogueGlowRows = {}
local function ClearRogueGlows()
	for _, row in ipairs(rogueGlowRows) do row.root:Hide() end
end
local function RogueGlowRow(index)
	if rogueGlowRows[index] then return rogueGlowRows[index] end
	local row = { nodes = {}, buttons = {} }
	local parent = UIParent
	for i = 1, 4 do
		local node = CreateFrame("Frame", nil, parent)
		node:SetAllPoints(parent)
		row.nodes[i], parent = node, node
	end
	row.root, row.host = row.nodes[1], parent
	rogueGlowRows[index] = row
	return row
end
local function RogueButtonGlow(row, btn)
	local overlay = row.buttons[btn]
	if overlay then return overlay end
	local frame = CreateFrame("Frame", nil, row.host)
	frame:SetAllPoints(btn)
	frame:SetFrameLevel((btn:GetFrameLevel() or 1) + 7)
	local strata = btn.GetFrameStrata and btn:GetFrameStrata()
	if not Secret(strata) and type(strata) == "string" then frame:SetFrameStrata(strata) end
	local tex = frame:CreateTexture(nil, "OVERLAY")
	tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); tex:SetBlendMode("ADD")
	tex:SetPoint("CENTER", btn, "CENTER")
	local width = btn:GetWidth()
	local size = (type(width) == "number" and width > 0 and width or 36) * 1.75
	tex:SetSize(size, size)
	frame.tex, row.buttons[btn] = tex, frame
	return frame
end
local function UpdateSecretRogueFinisherGlow()
	ClearRogueGlows()
	local visual = AL.rotationSecretVisual or AL.rogueSecretVisual
	local rotation = AL.rotations and AL.rotations[AL.playerClass]
	if not rotation or type(rotation.SecretVisualPlan) ~= "function" then return end
	if not visual or not rotation or ActionLiteDB.glowHidden or GetTime() - visual.at > 0.5 then return end
	local plan = rotation.SecretVisualPlan(AL.lastSuggestion, visual.baseReason)
	if plan ~= visual.plan then return end
	local r, g, b = AL.GlowColor()
	for _, o in pairs(lit) do if o and o.tex then o.tex:SetVertexColor(r, g, b, 0) end end
	for index, decision in ipairs(plan.rows) do
		local row = RogueGlowRow(index)
		for _, overlay in pairs(row.buttons) do overlay:Hide() end
		rotation.ApplyVisualRow(row.nodes, decision, visual.values)
		for _, btn in ipairs(ButtonsFor(decision.spell) or {}) do
			local shownOK, buttonShown = pcall(btn.IsShown, btn)
			if shownOK and not Secret(buttonShown) and buttonShown == true then
				local overlay = RogueButtonGlow(row, btn)
				local scaleOK, buttonScale = pcall(btn.GetEffectiveScale, btn)
				local parentScale = UIParent:GetEffectiveScale()
				if scaleOK and not Secret(buttonScale) and not Secret(parentScale)
					and type(buttonScale) == "number" and type(parentScale) == "number" and parentScale > 0 then
					overlay:SetScale(buttonScale / parentScale)
				end
				local alphaOK, buttonAlpha = false, nil
				if btn.GetEffectiveAlpha then alphaOK, buttonAlpha = pcall(btn.GetEffectiveAlpha, btn) end
				if alphaOK and (Secret(buttonAlpha) or type(buttonAlpha) == "number") then overlay:SetAlpha(buttonAlpha)
				else overlay:SetAlpha(1) end
				overlay.tex:SetVertexColor(r, g, b, 1); overlay:Show()
			end
		end
		row.root:Show()
	end
end

local function Unlight()
	for btn, o in pairs(lit) do
		o.pulse:Stop()
		o:Hide()
		lit[btn] = nil
	end
end

function AL.UpdateGlow(spell)
	if not ActionLiteDB or ActionLiteDB.glowHidden then spell = nil end
	EnsureMap()
	if spell == shown then return end
	shown = spell
	Unlight()
	local list = ButtonsFor(spell)
	if not list then return end
	local pulse = ActionLiteDB.glowPulse
	local r, g, b = AL.GlowColor()
	for _, btn in ipairs(list) do
		local o = Overlay(btn)
		if o then
			o.tex:SetVertexColor(r, g, b, 1)
			o:Show()
			if pulse then o.pulse:Play() end
			lit[btn] = o
		end
	end
end

function AL.RefreshGlow() shown = STALE end

--- Saves the highlight colour twice (own key + profiles mirror) and repaints lit buttons.
function AL.SetGlowColor(c)
	ActionLiteDB = ActionLiteDB or {}
	local saved = ValidColor(c) and { c[1], c[2], c[3] } or nil
	ActionLiteDB.glowColor = saved
	ActionLiteDB.profiles = ActionLiteDB.profiles or {}
	ActionLiteDB.profiles.__ACTIONLITE_UI = ActionLiteDB.profiles.__ACTIONLITE_UI or {}
	ActionLiteDB.profiles.__ACTIONLITE_UI.glowColor = saved and { saved[1], saved[2], saved[3] } or nil
	local r, g, b = AL.GlowColor()
	for _, o in pairs(lit) do if o.tex then o.tex:SetVertexColor(r, g, b, 1) end end
	shown = STALE
end

local secretHealDriver = CreateFrame("Frame")
local secretHealElapsed = 0
secretHealDriver:SetScript("OnUpdate", function(_, dt)
	secretHealElapsed = secretHealElapsed + dt
	if secretHealElapsed < 0.15 then return end
	secretHealElapsed = 0
	UpdateSecretPriestHealGlow()
	local ok = pcall(UpdateSecretRogueFinisherGlow)
	if not ok then
		ClearRogueGlows()
		local r, g, b = AL.GlowColor()
		for _, o in pairs(lit) do if o and o.tex then o.tex:SetVertexColor(r, g, b, 1) end end
	end
end)

-- Blizzard updates button.action in its own handler; rebuilding on the next tick avoids the race
local events = CreateFrame("Frame")
for _, e in ipairs({
	"PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
	"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_MACROS",
	"SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS",
}) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event)
	if event == "UPDATE_BINDINGS" then wipe(keyCache) return end
	dirty, retryAt = true, 0
end)
