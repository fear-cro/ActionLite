local ADDON, AL = ...
local L = AL.L

-- ============================================================================
-- ActionLITE - Display.lua - v0.15.0
-- ----------------------------------------------------------------------------
-- Recommendation icon, A[1]-A[10] icons and slash commands.
-- Consistent range coloring for each suggestion across all three icons.
-- ============================================================================

local MAIN_SIZE = 44
local idleIcon = "Interface\\Icons\\INV_Sword_27"
local f = CreateFrame("Frame", "ActionLiteFrame", UIParent, "BackdropTemplate")
AL.frame = f
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- Keep the borderless recommendation above full-screen warning effects. This
-- matches the protected strata used by A[1]-A[10] without covering protocol
-- pixels, which remain one frame level higher.
f:SetFrameStrata("TOOLTIP")
f:SetFrameLevel(100)
f:SetSize(MAIN_SIZE, MAIN_SIZE)
f:SetPoint("CENTER", 0, 180)
f:SetClampedToScreen(true)
f:SetBackdrop({
	bgFile = AL.WHITE,
	tile = false,
})
f:SetBackdropColor(0.03, 0.04, 0.06, 0.92)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")

function AL.ApplyLock()
	f:EnableMouse(not ActionLiteDB.locked)
	if AL.grip then AL.grip:SetShown(not ActionLiteDB.locked) end
	if AL.ApplyToggles then AL.ApplyToggles() end
end

-- nobg takes priority: it is the "show background" switch.
-- bgAlpha controls opacity when the background is shown.
function AL.ApplyStyle()
	local s = AL.S()
	local alpha = 0
	if not s.nobg then
		alpha = tonumber(s.bgAlpha) or 0.92
		if alpha < 0 then alpha = 0 end
		if alpha > 1 then alpha = 1 end
	end
	f:SetBackdropColor(0.03, 0.04, 0.06, alpha)
	f:SetScale(tonumber(s.scale) or 1)
end

function AL.ResetIconPosition()
	ActionLiteDB = ActionLiteDB or {}
	ActionLiteDB.pos = nil
	f:ClearAllPoints()
	f:SetPoint("CENTER", 0, 180)
end

f:SetScript("OnDragStart", function(self)
	if not ActionLiteDB.locked then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relPoint, x, y = self:GetPoint()
	ActionLiteDB.pos = { point, relPoint, x, y }
end)

-- The corner grip resizes the icon; its scale is stored in the profile.
local grip = CreateFrame("Button", nil, f)
grip:SetSize(12, 12)
grip:SetPoint("BOTTOMRIGHT", -1, 1)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
AL.grip = grip
local sizing = false
grip:SetScript("OnMouseDown", function() sizing = true end)
grip:SetScript("OnMouseUp", function()
	if not sizing then return end
	sizing = false
	local point, _, relPoint, x, y = f:GetPoint()
	ActionLiteDB.pos = { point, relPoint, x, y }
	if AL.UI then AL.UI.Repaint() end
end)
grip:SetScript("OnHide", function() sizing = false end)
grip:SetScript("OnUpdate", function()
	if not sizing then return end
	local cx = GetCursorPosition()
	local es = f:GetEffectiveScale()
	local leftPx, topPx = f:GetLeft() * es, f:GetTop() * es
	local scale = math.max(0.5, math.min(2, (cx - leftPx) / MAIN_SIZE / UIParent:GetEffectiveScale()))
	AL.S().scale = scale
	f:SetScale(scale)
	es = f:GetEffectiveScale()
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftPx / es, topPx / es)
end)

local icon = f:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints(f)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)


-- Priest secret-health visual priority. Forever may protect the actual health
-- percentage; the protected value is fed directly into a Blizzard ColorCurve
-- and never inspected by Lua.
local priestHealOverlay = f:CreateTexture(nil, "OVERLAY")
priestHealOverlay:SetAllPoints(icon)
priestHealOverlay:SetTexCoord(0.08, 0.92, 0.08, 0.92)
priestHealOverlay:SetVertexColor(1, 1, 1, 0)

local rogueFinisherOverlay = f:CreateTexture(nil, "OVERLAY")
rogueFinisherOverlay:SetAllPoints(icon)
rogueFinisherOverlay:SetTexCoord(0.08, 0.92, 0.08, 0.92)
rogueFinisherOverlay:SetVertexColor(1, 1, 1, 0)

local priestHealthCurves = {}
local function PriestHealthVisibilityCurve(threshold, inverse)
	local key = tostring(threshold) .. (inverse and ":inverse" or ":heal")
	if priestHealthCurves[key] then return priestHealthCurves[key] end
	if not C_CurveUtil or type(C_CurveUtil.CreateColorCurve) ~= "function" or type(CreateColor) ~= "function" then return nil end
	local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
	if not ok or not curve then return nil end
	pcall(curve.SetType, curve, Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	local cut = math.max(0, math.min(100, threshold)) / 100
	if not pcall(curve.AddPoint, curve, 0.0, CreateColor(1, 1, 1, inverse and 0 or 1)) then return nil end
	if not pcall(curve.AddPoint, curve, cut, CreateColor(1, 1, 1, inverse and 1 or 0)) then return nil end
	if not pcall(curve.AddPoint, curve, 1.0, CreateColor(1, 1, 1, inverse and 1 or 0)) then return nil end
	priestHealthCurves[key] = curve
	return curve
end

local function ApplySecretHealthVisibility(texture, threshold, inverse)
	local curve = PriestHealthVisibilityCurve(threshold, inverse)
	if not texture or not curve or type(UnitHealthPercent) ~= "function" then return false end
	local ok, color = pcall(UnitHealthPercent, "player", true, curve)
	if not ok or not color then return false end
	return pcall(function()
		local r, g, b, a = color:GetRGBA()
		if inverse then texture:SetAlpha(a) else texture:SetVertexColor(r, g, b, a) end
	end)
end

local function PriestSecretHealVisual()
	if AL.playerClass ~= "PRIEST" then return nil end
	local rotation = AL.rotations and AL.rotations.PRIEST
	if not rotation or type(rotation.SecretHealVisualState) ~= "function" then return nil end
	local ok, spell, threshold, reason = pcall(rotation.SecretHealVisualState)
	if not ok or type(spell) ~= "string" or type(threshold) ~= "number" then return nil end
	return spell, threshold, reason
end

-- Above the cooldown swipe; otherwise the text is covered.
local swipe
do
	local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
	if ok and cd then
		swipe = cd
		swipe:SetAllPoints(icon)
		pcall(swipe.SetDrawEdge, swipe, false)
		pcall(swipe.SetHideCountdownNumbers, swipe, true)
		swipe:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
	end
end
local hud = CreateFrame("Frame", nil, f)
hud:SetAllPoints(icon)
hud:SetFrameLevel((f:GetFrameLevel() or 1) + 4)

local function CreateDrinkReminder(parent)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("BOTTOM", f, "TOP", 0, 6)
	text:SetJustifyH("CENTER")
	text:SetTextColor(1, 0.9, 0.5, 1)
	text:SetShadowColor(0, 0, 0, 1)
	text:SetShadowOffset(1, -1)
	text:SetText("LOW MANA - DRINK")
	text:Hide()
	return text
end

local function DrinkReminderAllowed()
	local ok, combat = pcall(UnitAffectingCombat, "player")
	if not ok or issecretvalue and issecretvalue(combat) then return false end
	return combat == false
end

local drinkReminder = CreateDrinkReminder(hud)

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
local spellReadabilityWarning = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
spellReadabilityWarning:SetPoint("BOTTOM", f, "TOP", 0, 24)
spellReadabilityWarning:SetJustifyH("CENTER")
spellReadabilityWarning:SetWidth(360)
pcall(spellReadabilityWarning.SetWordWrap, spellReadabilityWarning, false)
spellReadabilityWarning:SetTextColor(1, 0.32, 0.18, 1)
spellReadabilityWarning:SetShadowColor(0, 0, 0, 1)
spellReadabilityWarning:SetShadowOffset(1, -1)
spellReadabilityWarning:Hide()

local function UpdateSpellReadabilityWarning()
	spellReadabilityWarning:Hide()
	if type(AL.GetSpellReadabilityWarning) ~= "function" then return end
	local ok, text = pcall(AL.GetSpellReadabilityWarning)
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
	-- Secret values must be rejected before Lua examines their type or text.
	if not ok or (issecretvalue and issecretvalue(text))
		or type(text) ~= "string" or text == "" then return end
	spellReadabilityWarning:SetText(text)
	spellReadabilityWarning:Show()
end

-- A reminder is independent of the recommendation. It cannot consume an
-- action, hide a combat opener, or replace either driven A icon (A[3] or A[6]).
local function UpdateDrinkReminder()
	drinkReminder:Hide()
	local s = AL.S()
	if not s.drink or not DrinkReminderAllowed() then return end
	if AL.playerClass == "DRUID" then
		local ok, kind = pcall(UnitPowerType, "player")
		if not ok or issecretvalue and issecretvalue(kind) or kind ~= 0 then return end
	end
	local threshold = tonumber(s.drinkMana) or ((AL.playerClass == "PRIEST" or AL.playerClass == "MAGE") and 35 or 30)
	threshold = math.max(0, math.min(80, threshold))
	local ok, alpha = AL.ResourceIntervalAlpha("power", "player", 0, 0, AL.ResourceThresholdCut(threshold, true))
	if ok and pcall(drinkReminder.SetAlpha, drinkReminder, alpha) then drinkReminder:Show(); return end
	local mana = AL.ManaPercent()
	if type(mana) ~= "number" or issecretvalue and issecretvalue(mana) then
		local rotation = AL.rotations and AL.rotations[AL.playerClass]
		if rotation and type(rotation.ManaPercent) == "function" then
			local read, value = pcall(rotation.ManaPercent)
			if read and not (issecretvalue and issecretvalue(value)) then mana = value end
		end
	end
	if type(mana) == "number" and not (issecretvalue and issecretvalue(mana)) then
		drinkReminder:SetAlpha(1)
		drinkReminder:SetShown(mana <= threshold)
	end
end

local keyText = hud:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
keyText:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -1, -2)
local rogueFinisherKey = hud:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
rogueFinisherKey:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -1, -2)
rogueFinisherKey:Hide()
keyText:SetJustifyH("RIGHT")
keyText:SetWidth(42)
pcall(keyText.SetWordWrap, keyText, false)
keyText:SetTextColor(1, 1, 1, 1)
keyText:Hide()
AL.keyText = keyText

local comboText = hud:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
comboText:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 2, 2)
comboText:SetTextColor(1, 0.82, 0, 1)
comboText:Hide()
AL.comboText = comboText
AL.swipe = swipe

local PaintToggles

function AL.ToggleAoE()
	local s = AL.S()
	s.aoe = not s.aoe
	AL.Say(s.aoe and L("AOE_MODE_ON") or L("AOE_MODE_OFF"))
	if PaintToggles then PaintToggles() end
	if AL.UI then AL.UI.Repaint() end
end

-- AoE / Burst stay clickable while the main icon's position is locked.
local toggles = {}
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
-- Side controls share the recommendation's height. Full AoE/Burst controls
-- each occupy one half; role controls and compact indicators occupy thirds.
local COMPACT_TOGGLE_PX = MAIN_SIZE / 3
local FULL_TOGGLE_HEIGHT = MAIN_SIZE / 2
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
-- Keep the compact click areas at one third of the main icon, but render
-- their states as softly vignetted lamps instead of saturated square fills.
local INDICATOR_TEXTURE = "Interface\\AddOns\\ActionLITE\\Media\\ActionLiteIndicator"
local function CompactIndicator(button)
	local halo = button:CreateTexture(nil, "ARTWORK")
	halo:SetTexture(INDICATOR_TEXTURE)
	halo:SetSize(COMPACT_TOGGLE_PX, COMPACT_TOGGLE_PX)
	halo:SetPoint("CENTER")
	local lamp = button:CreateTexture(nil, "OVERLAY")
	lamp:SetTexture(INDICATOR_TEXTURE)
	lamp:SetSize(COMPACT_TOGGLE_PX - 2, COMPACT_TOGGLE_PX - 2)
	lamp:SetPoint("CENTER")
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetTexture(INDICATOR_TEXTURE)
	hover:SetSize(COMPACT_TOGGLE_PX, COMPACT_TOGGLE_PX)
	hover:SetPoint("CENTER")
	hover:SetVertexColor(1, 1, 1, 0.20)
	return function(compact, on)
		halo:SetShown(compact)
		lamp:SetShown(compact)
		hover:SetShown(compact)
		if not compact then return end
		local r, g, blue = on and 0.39 or 0.68, on and 0.61 or 0.39, on and 0.50 or 0.39
		halo:SetVertexColor(r, g, blue, on and 0.27 or 0.15)
		lamp:SetVertexColor(r, g, blue, on and 0.96 or 0.78)
	end
end
local function QuickToggle(index, caption, tipKey, isOn, onClick)
	local b = CreateFrame("Button", nil, f)
	b:SetSize(38, FULL_TOGGLE_HEIGHT)
	b:SetFrameLevel(f:GetFrameLevel() + 10)
	b:RegisterForClicks("LeftButtonUp")
	local edge = b:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	local bg = b:CreateTexture(nil, "BORDER")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.035, 0.045, 0.065, 0.92)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetPoint("TOPLEFT", 1, -1)
	hover:SetPoint("BOTTOMRIGHT", -1, 1)
	hover:SetColorTexture(1, 1, 1, 0.07)
	local paintIndicator = CompactIndicator(b)
	-- The checkmark indicates state without depending on color.
	local check = b:CreateTexture(nil, "OVERLAY")
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	check:SetSize(14, 14)
	check:SetPoint("LEFT", 3, 0)
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	function b:Paint()
		local on = isOn() and true or false
		local compact = ActionLiteDB and ActionLiteDB.togglesHidden == true or false
		b:ClearAllPoints()
		-- Keep AoE flush with the top and Burst flush with the bottom, even
		-- when the compact indicators leave the middle third empty.
		if index == 1 then
			b:SetPoint("TOPLEFT", f, "TOPRIGHT", 3, 0)
		else
			b:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 3, 0)
		end
		label:SetShown(not compact)
		check:SetShown(not compact and on)
		edge:SetShown(not compact)
		bg:SetShown(not compact)
		hover:SetShown(not compact)
		paintIndicator(compact, on)
		if compact then
			b:SetSize(COMPACT_TOGGLE_PX, COMPACT_TOGGLE_PX)
		else
			label:SetText(caption)
			local pad = on and 14 or 0
			label:SetPoint("CENTER", pad / 2, 0)
			b:SetSize(math.max(38, math.ceil((label:GetStringWidth() or 0) + 12 + pad)), FULL_TOGGLE_HEIGHT)
			bg:SetColorTexture(0.035, 0.045, 0.065, 0.92)
			if on then
				local r, g, bl = AL.GlowColor()
				edge:SetColorTexture(r, g, bl, 1)
				label:SetTextColor(1, 1, 1, 1)
			else
				edge:SetColorTexture(0.35, 0.36, 0.40, 1)
				label:SetTextColor(0.66, 0.68, 0.72, 1)
			end
		end
		b.compact, b.on = compact, on
	end
	local function ShowTip(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L(tipKey), 1, 0.82, 0)
		GameTooltip:AddLine(isOn() and L("QT_STATE_ON") or L("QT_STATE_OFF"), 1, 1, 1)
		GameTooltip:AddLine(L("QT_CLICK"), 0.85, 0.86, 0.88, true)
		GameTooltip:Show()
	end
	b:SetScript("OnClick", function(self)
		onClick()
		self:Paint()
		if GameTooltip:IsOwned(self) then ShowTip(self) end
	end)
	b:SetScript("OnMouseDown", function() label:SetPoint("CENTER", b.on and 7 or 0, -1) end)
	b:SetScript("OnMouseUp", function() label:SetPoint("CENTER", b.on and 7 or 0, 0) end)
	b:SetScript("OnEnter", ShowTip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.isOn = isOn
	toggles[#toggles + 1] = b
	return b
end
AL.aoeToggle = QuickToggle(1, "AoE", "QT_AOE_TIP", function() return AL.S().aoe end, AL.ToggleAoE)
AL.burstToggle = QuickToggle(2, "Burst", "QT_BURST_TIP", function() return AL.burst end, ActionLite_Burst)

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- Rotation-role controls use the same visual language as Burst and AoE, but
-- live in one vertically centered column to the left of the recommendation.
-- Unsupported roles are omitted instead of presenting a button which can
-- never become active.
local ROLE_FALLBACKS = {
	DRUID = { DPS = true, HEAL = true, TANK = true },
	PALADIN = { DPS = true, HEAL = true, TANK = true },
	PRIEST = { DPS = true, HEAL = true },
	SHAMAN = { DPS = true, HEAL = true },
	WARRIOR = { DPS = true, TANK = true },
	HUNTER = { DPS = true }, MAGE = { DPS = true },
	ROGUE = { DPS = true }, WARLOCK = { DPS = true },
}
local ROLE_LABELS = { DPS = "DPS", HEAL = "Heals", TANK = "Tank" }
local roleToggles = {}
local LayoutRoleToggles

local function SupportsRotationRole(role)
	if type(AL.RoleModeSupported) == "function" then
		local ok, supported = pcall(AL.RoleModeSupported, AL.playerClass, role)
		if ok and type(supported) == "boolean"
			and not (issecretvalue and issecretvalue(supported)) then return supported end
	end
	if type(AL.SupportsRotationRole) == "function" then
		local ok, supported = pcall(AL.SupportsRotationRole, role, AL.playerClass)
		if ok and type(supported) == "boolean"
			and not (issecretvalue and issecretvalue(supported)) then return supported end
	end
	local supported = ROLE_FALLBACKS[AL.playerClass]
	return supported and supported[role] == true or false
end

local function CurrentRotationRole()
	local profile = AL.S and AL.S() or nil
	if type(AL.GetRotationMode) == "function" then
		local ok, role = pcall(AL.GetRotationMode, profile, AL.playerClass)
		if ok and type(role) == "string" and SupportsRotationRole(role) then return role end
	end
	if type(AL.GetRotationRole) == "function" then
		local ok, role = pcall(AL.GetRotationRole, profile, AL.playerClass)
		if ok and type(role) == "string" and SupportsRotationRole(role) then return role end
	end
	if type(profile) == "table" then
		if profile.roleTank and SupportsRotationRole("TANK") then return "TANK" end
		if profile.roleHeals and SupportsRotationRole("HEAL") then return "HEAL" end
	end
	return "DPS"
end

local function SelectRotationRole(role)
	if not SupportsRotationRole(role) then return end
	local changed
	local profile = AL.S and AL.S() or nil
	if type(AL.SetRotationMode) == "function" then
		local ok, result = pcall(AL.SetRotationMode, role, true, profile, AL.playerClass)
		changed = ok and result ~= nil and result ~= false
	elseif type(AL.SetRotationRole) == "function" then
		local ok, result = pcall(AL.SetRotationRole, role, true)
		changed = ok and result ~= nil and result ~= false
	else
		if type(profile) == "table" then
			profile.roleDPS = role == "DPS"
			profile.roleHeals = role == "HEAL"
			profile.roleTank = role == "TANK"
			profile.rotationRoleManual = true
			changed = true
		end
	end
	if changed then
		if PaintToggles then PaintToggles() end
		if AL.UI then AL.UI.Repaint() end
	end
end

local function RoleToggle(role)
	local caption = ROLE_LABELS[role]
	local b = CreateFrame("Button", nil, f)
	b:SetSize(44, COMPACT_TOGGLE_PX)
	b:SetFrameLevel(f:GetFrameLevel() + 10)
	b:RegisterForClicks("LeftButtonUp")
	local edge = b:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	local bg = b:CreateTexture(nil, "BORDER")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.035, 0.045, 0.065, 0.92)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetPoint("TOPLEFT", 1, -1)
	hover:SetPoint("BOTTOMRIGHT", -1, 1)
	hover:SetColorTexture(1, 1, 1, 0.07)
	local paintIndicator = CompactIndicator(b)
	local check = b:CreateTexture(nil, "OVERLAY")
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	check:SetSize(11, 11)
	check:SetPoint("LEFT", 2, 0)
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")

	function b:Paint()
		if not SupportsRotationRole(role) then
			b.supported, b.on = false, false
			b:Hide()
			return
		end
		b.supported = true
		b:Show()
		local on = CurrentRotationRole() == role
		local compact = ActionLiteDB and ActionLiteDB.togglesHidden == true or false
		label:SetShown(not compact)
		check:SetShown(not compact and on)
		edge:SetShown(not compact)
		bg:SetShown(not compact)
		hover:SetShown(not compact)
		paintIndicator(compact, on)
		if compact then
			b:SetSize(COMPACT_TOGGLE_PX, COMPACT_TOGGLE_PX)
		else
			label:SetText(caption)
			local pad = on and 14 or 0
			label:SetPoint("CENTER", pad / 2, 0)
			b:SetSize(math.max(44, math.ceil((label:GetStringWidth() or 0) + 12 + pad)), COMPACT_TOGGLE_PX)
			bg:SetColorTexture(0.035, 0.045, 0.065, 0.92)
			if on then
				local r, g, bl = AL.GlowColor()
				edge:SetColorTexture(r, g, bl, 1)
				label:SetTextColor(1, 1, 1, 1)
			else
				edge:SetColorTexture(0.35, 0.36, 0.40, 1)
				label:SetTextColor(0.66, 0.68, 0.72, 1)
			end
		end
		b.compact, b.on = compact, on
	end

	local function ShowTip(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(caption .. " Rotation", 1, 0.82, 0)
		GameTooltip:AddLine(self.on and "Selected" or "Click to select this rotation role.", 1, 1, 1, true)
		GameTooltip:Show()
	end
	b:SetScript("OnClick", function(self)
		SelectRotationRole(role)
		self:Paint()
		if LayoutRoleToggles then LayoutRoleToggles() end
		if GameTooltip:IsOwned(self) then ShowTip(self) end
	end)
	b:SetScript("OnMouseDown", function() label:SetPoint("CENTER", b.on and 7 or 0, -1) end)
	b:SetScript("OnMouseUp", function() label:SetPoint("CENTER", b.on and 7 or 0, 0) end)
	b:SetScript("OnEnter", ShowTip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.isOn = function() return CurrentRotationRole() == role end
	roleToggles[#roleToggles + 1] = b
	toggles[#toggles + 1] = b
	return b
end

AL.dpsRoleToggle = RoleToggle("DPS")
AL.healsRoleToggle = RoleToggle("HEAL")
AL.tankRoleToggle = RoleToggle("TANK")

function LayoutRoleToggles()
	local visible = {}
	for _, b in ipairs(roleToggles) do
		if b.supported then visible[#visible + 1] = b end
	end
	local compact = ActionLiteDB and ActionLiteDB.togglesHidden == true or false
	local height = COMPACT_TOGGLE_PX
	local count = #visible
	for index, b in ipairs(visible) do
		b:ClearAllPoints()
		local centerY = (((count + 1) / 2) - index) * height
		b:SetPoint("RIGHT", f, "LEFT", -3, centerY)
	end
	-- Neither column extends beyond the recommendation icon now.
	local noticeY = 26
	drinkReminder:ClearAllPoints()
	drinkReminder:SetPoint("BOTTOM", f, "TOP", 0, noticeY)
	spellReadabilityWarning:ClearAllPoints()
	spellReadabilityWarning:SetPoint("BOTTOM", f, "TOP", 0, noticeY + 18)
end

function PaintToggles()
	for _, b in ipairs(toggles) do b:Paint() end
	LayoutRoleToggles()
end

function AL.ApplyToggles()
	for _, b in ipairs(toggles) do
		b:Show()
		b:EnableMouse(true)
		b:Paint()
	end
	LayoutRoleToggles()
end

-- A[1]-A[10] icons: borderless suggestions anchored at the screen's top left,
-- sized in physical pixels to stay sharp at every UI scale. They mirror the
-- ten-icon "Shown Main" row of the original Action (one row, 60% scale, no
-- padding), so A[n] sits (n - 3) icon widths from A[3].
-- A[3] and A[6] are the two icons ActionLITE currently drives (formerly
-- mini1 and mini2); the remaining slots are created and ready for future use.
-- Each A[n] is a frame named "A<n>" and its texture is A[n].tex.
local A_PX, A3_X, A_Y = 18, 19, 7
local A_COUNT = 10
local A1_X = A3_X - (A_PX * 2)
local A = {}
for n = 1, A_COUNT do
	A[n] = CreateFrame("Frame", "A" .. n, UIParent)
	-- Keep every corner signal above full-screen low-health warning effects.
	A[n]:SetFrameStrata("TOOLTIP")
	A[n]:SetFrameLevel(100)
	A[n].tex = A[n]:CreateTexture(nil, "OVERLAY")
	A[n].tex:SetAllPoints(A[n])
	A[n].tex:Hide()
end
AL.A = A
local A3, A6 = A[3], A[6]
local A3Tex, A6Tex = A3.tex, A6.tex

-- Keep addon-table and global aliases for integrations written against the
-- old mini names. Both aliases point at the new frames; no extra frames exist.
AL.miniFrame, AL.miniTexture = A3, A3Tex
AL.miniFrame2, AL.miniTexture2 = A6, A6Tex
_G.ActionLiteMiniFrame, _G.ActionLiteMiniFrame2 = A3, A6

local A3PriestHealTex = A3:CreateTexture(nil, "OVERLAY")
A3PriestHealTex:SetAllPoints(A3)
A3PriestHealTex:SetVertexColor(1, 1, 1, 0)
local A6PriestHealTex = A6:CreateTexture(nil, "OVERLAY")
A6PriestHealTex:SetAllPoints(A6)
A6PriestHealTex:SetVertexColor(1, 1, 1, 0)
local A3RogueFinisherTex = A3:CreateTexture(nil, "OVERLAY")
A3RogueFinisherTex:SetAllPoints(A3)
A3RogueFinisherTex:SetVertexColor(1, 1, 1, 0)

-- Restore each texture's own pixel settings after addons that hook SetTexture.
local sharpDefaults = setmetatable({}, { __mode = "k" })
local function SetSharpTexture(tex, path)
	local sharp = sharpDefaults[tex]
	if not sharp then
		sharp = { snap = tex.IsSnappingToPixelGrid and tex:IsSnappingToPixelGrid(),
			bias = tex.GetTexelSnappingBias and tex:GetTexelSnappingBias() }
		sharpDefaults[tex] = sharp
	end
	tex:SetTexture(path)
	if sharp.snap ~= nil and tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(sharp.snap) end
	if sharp.bias ~= nil and tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(sharp.bias) end
end

local layoutH, layoutE = 0, 0
local function PlaceSlots(px)
	for n = 1, A_COUNT do
		local frame = A[n]
		frame:SetSize(A_PX * px, A_PX * px)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (A1_X + (n - 1) * A_PX) * px, A_Y * px)
	end
end
local function LayoutSlots(force)
	if not GetPhysicalScreenSize then
		if force or layoutH ~= -1 then
			layoutH = -1
			PlaceSlots(1)
		end
		return
	end
	local _, h = GetPhysicalScreenSize()
	local e = UIParent:GetEffectiveScale()
	if type(h) ~= "number" or h <= 0 or type(e) ~= "number" or e <= 0 then return end
	if not force and h == layoutH and e == layoutE then return end
	layoutH, layoutE = h, e
	-- WoW's virtual screen height is 768 units; convert physical pixels to units.
	PlaceSlots(768 / (h * e))
end
LayoutSlots()

function AL.ApplySlots()
	for _, frame in ipairs(A) do
		frame:SetMovable(false)
		frame:EnableMouse(false)
		frame:SetScale(1)
		frame:SetAlpha(1)
		frame:Show()
	end
	LayoutSlots(true)
end

-- Compatibility entry point for older ActionLITE integrations.
AL.ApplyMini = AL.ApplySlots

-- HealingEngine rows sit above the normal recommendation and drive the
-- Action-compatible target pixel with the same protected-health alpha.
if AL.HealingEngine and AL.HealingEngine.BindDisplay then
	AL.HealingEngine:BindDisplay({ main = f, slots = A, setTexture = SetSharpTexture })
end

local function CatForm()
    local rotation = AL.rotations and AL.rotations.DRUID
    if rotation and type(rotation.CurrentForm) == "function" then
        local ok, form = pcall(rotation.CurrentForm)
        if ok and not (issecretvalue and issecretvalue(form)) then return form == "cat" end
    end
	if type(GetShapeshiftForm) == "function" and AL.StanceName then
		local ok, index = pcall(GetShapeshiftForm)
		if ok and type(index) == "number" and not (issecretvalue and issecretvalue(index)) and index > 0 then
			local name = AL.StanceName(index)
			if name then return name == "Cat Form" or name == AL.LocalName("Cat Form") end
		end
	end
	local ok, has = pcall(AL.HasBuff, "player", "Cat Form")
	return ok and has == true
end

local function UpdateCombo()
	local cls = AL.playerClass
	local cp = (cls == "ROGUE" or (cls == "DRUID" and CatForm())) and AL.ComboPoints() or nil
	if type(cp) == "number" and not (issecretvalue and issecretvalue(cp)) and cp > 0 then
		comboText:SetText(cp)
		comboText:Show()
	else
		comboText:Hide()
	end
end

local function UpdateKeybind(spell)
	local key = spell and not ActionLiteDB.keybindHidden and AL.KeybindFor and AL.KeybindFor(spell)
	if key then
		keyText:SetText(key)
		keyText:Show()
	else
		keyText:Hide()
	end
end

-- AL.CooldownRemaining counts whole seconds (time()): allow 1.5 seconds before restarting.
local swipeSpell, swipeEnd = nil, 0
local function UpdateSwipe(spell)
	if not swipe then return end
	local rem = spell and AL.CooldownRemaining(spell) or 0
	if type(rem) ~= "number" or rem <= 0 then
		if swipeSpell then
			swipeSpell, swipeEnd = nil, 0
			pcall(swipe.SetCooldown, swipe, 0, 0)
			swipe:Hide()
		end
		return
	end
	local now = GetTime()
	if spell == swipeSpell and math.abs(now + rem - swipeEnd) < 1.5 then return end
	swipeSpell, swipeEnd = spell, now + rem
	swipe:Show()
	pcall(swipe.SetCooldown, swipe, now, rem)
end

-- One row is visible for each client-evaluated combination of HP/energy
-- intervals. Parent alpha supplies AND without arithmetic on protected values.
local rogueVisualRows = {}
local function RogueVisualRow(index, parent, small)
	local pair = rogueVisualRows[index]
	if not pair then pair = {}; rogueVisualRows[index] = pair end
	local key = small and (parent == A6 and "A6" or "A3") or "main"
	if pair[key] then return pair[key] end
	local row = { nodes = {} }
	local host = parent
	for i = 1, 4 do
		local node = CreateFrame("Frame", nil, host)
		node:SetAllPoints(host)
		node:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
		row.nodes[i], host = node, node
	end
	row.root = row.nodes[1]
	row.tex = host:CreateTexture(nil, "OVERLAY")
	row.tex:SetAllPoints(parent)
	if not small then
		row.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.key = host:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		row.key:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -1, -2)
		row.key:SetJustifyH("RIGHT"); row.key:SetWidth(42)
		pcall(row.key.SetWordWrap, row.key, false)
		row.key:SetTextColor(1, 1, 1, 1)
	end
	pair[key] = row
	return row
end

local function ResetRogueSecretVisual()
	for _, pair in ipairs(rogueVisualRows) do
		if pair.main then pair.main.root:Hide() end
		if pair.A3 then pair.A3.root:Hide() end
		if pair.A6 then pair.A6.root:Hide() end
	end
	rogueFinisherOverlay:SetTexture(nil); A3RogueFinisherTex:SetTexture(nil)
	rogueFinisherOverlay:SetVertexColor(1, 1, 1, 0); A3RogueFinisherTex:SetVertexColor(1, 1, 1, 0)
	icon:SetAlpha(1); A3Tex:SetAlpha(1); A6Tex:SetAlpha(1); keyText:SetAlpha(1)
	rogueFinisherKey:Hide()
	AL.rogueSecretVisual, AL.rotationSecretVisual = nil, nil
end

-- A target can disappear between display ticks. Clear every actionable output
-- immediately so an input reader cannot press the previous target's spell and
-- let the client or a macro acquire a different enemy before the next redraw.
-- Cast Trail and the role/AoE/Burst controls are intentionally unaffected.
function AL.ClearRecommendationDisplay()
	AL.lastSuggestion = nil
	ResetRogueSecretVisual()
	SetSharpTexture(icon, idleIcon)
	icon:SetVertexColor(1, 1, 1, 1)
	for _, texture in ipairs({ A3Tex, A6Tex }) do
		texture:Hide()
		SetSharpTexture(texture, nil)
		texture:SetVertexColor(1, 1, 1, 1)
		texture:SetAlpha(1)
	end
	for _, texture in ipairs({ priestHealOverlay, A3PriestHealTex, A6PriestHealTex }) do
		SetSharpTexture(texture, nil)
		texture:SetVertexColor(1, 1, 1, 0)
	end
	if AL.HealingEngine and AL.HealingEngine.ClearVisuals then
		pcall(AL.HealingEngine.ClearVisuals, AL.HealingEngine)
	end
	if AL.UpdateGlow then pcall(AL.UpdateGlow, nil) end
	pcall(UpdateKeybind, nil)
	pcall(UpdateSwipe, nil)
	if type(AL.ObserveDisplayedSpell) == "function" then
		AL.ObserveDisplayedSpell(nil)
	end
end

local function UpdateRogueSecretVisual(spell, reason)
	local rotation = AL.rotations and AL.rotations[AL.playerClass]
	local plan = rotation and rotation.SecretVisualPlan and rotation.SecretVisualPlan(spell, reason)
	ResetRogueSecretVisual()
	if not plan then
		return
	end
	local values = rotation.EvaluateVisualMasks(plan)
	if not values then
		return
	end
	for index, decision in ipairs(plan.rows) do
		local output = A[AL.SlotFor(decision.spell)]
		local main, small = RogueVisualRow(index, f, false), RogueVisualRow(index, output, true)
		-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
		-- Protected Priest self-heal plans can include Ready/No target bands.
		-- Keep those bands visually identical to the ordinary Leveling idle state:
		-- idle artwork on the main icon and no false suggestion on A[3].
		local texture = decision.spell and (AL.IconFor(decision.spell) or AL.SpellTexture(decision.spell))
			or decision.idle and idleIcon or "Interface\\Icons\\INV_Stone_WeightStone_07"
		local r, g, b = 1, 1, 1
		if decision.spell and not AL.S().norange and AL.InRange(decision.spell) == false then r, g, b = 1, 0.25, 0.25 end
		SetSharpTexture(main.tex, texture); SetSharpTexture(small.tex, texture)
		main.tex:SetVertexColor(r, g, b, 1); small.tex:SetVertexColor(r, g, b, 1)
		local key = decision.spell and not ActionLiteDB.keybindHidden and AL.KeybindFor and AL.KeybindFor(decision.spell)
		main.key:SetText(key or ""); main.key:SetShown(key ~= nil and key ~= false)
		rotation.ApplyVisualRow(main.nodes, decision, values)
		rotation.ApplyVisualRow(small.nodes, decision, values)
		main.root:Show()
		if decision.idle then small.root:Hide() else small.root:Show() end
	end
	-- Base and conditional rows share the same masks, so icons, keys and action
	-- highlights cannot disagree about a higher-priority defensive cooldown.
	icon:SetAlpha(0); A3Tex:SetAlpha(0); A6Tex:SetAlpha(0); keyText:SetAlpha(0)
	AL.rotationSecretVisual = { plan = plan, values = values, spells = plan.spells,
		baseSpell = spell, baseReason = reason, at = GetTime() }
	AL.rogueSecretVisual = AL.playerClass == "ROGUE" and AL.rotationSecretVisual or nil

end

-- Dedicated wait/pooling visual. It is not a spell suggestion and therefore
-- never produces an action-bar glow.
local poolingIcon = "Interface\\Icons\\INV_Stone_WeightStone_07"
-- Separate driver: suggestions keep updating the A icons even
-- when the main icon is hidden.
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("PLAYER_DEAD")
driver:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_DEAD" then
		AL.ClearRecommendationDisplay()
	else
		drinkReminder:Hide()
	end
end)
local elapsed = 0
local lastVisualError
local lastHealingVisualError
driver:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.15 then return end
	elapsed = 0
	local spell, reason = AL.NextSpell()
	AL.lastSuggestion = spell
	local tex, r, g, b = nil, 1, 1, 1
	if spell then
		tex = AL.IconFor(spell) or AL.SpellTexture(spell) or "Interface\\Icons\\INV_Misc_QuestionMark"
		if not AL.S().norange and AL.InRange(spell) == false then r, g, b = 1, 0.25, 0.25 end
	elseif reason == "Channeling" then
		tex = poolingIcon
	end
	SetSharpTexture(icon, tex or idleIcon)
	icon:SetVertexColor(r, g, b)
	LayoutSlots()
	local slot = AL.SlotFor(spell)
	for _, n in ipairs({ 3, 6 }) do
		local texture = A[n].tex
		local visible = tex ~= nil and slot == n
		texture:SetShown(visible)
		SetSharpTexture(texture, visible and tex or nil)
		texture:SetVertexColor(r, g, b)
	end

	if AL.UpdateGlow then pcall(AL.UpdateGlow, spell) end
	pcall(UpdateKeybind, spell)
	pcall(UpdateCombo)
	pcall(UpdateSwipe, spell)
	local visualOK, visualError = pcall(UpdateRogueSecretVisual, spell, reason)
	if not visualOK then
		ResetRogueSecretVisual()
		local message = type(visualError) == "string" and not (issecretvalue and issecretvalue(visualError))
			and visualError or "Protected rotation display failure"
		if message ~= lastVisualError and AL.Debug and AL.Debug.CaptureError then
			lastVisualError = message
			AL.Debug.CaptureError("Rotation display: " .. message, "rotation display")
		end
	end
	UpdateDrinkReminder()
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	UpdateSpellReadabilityWarning()

	-- Legacy Priest healing still uses protected health masks. Its Unit1
	-- overlay must also mask A[3]'s underlying damage suggestion.
	for _, texture in ipairs({ priestHealOverlay, A3PriestHealTex, A6PriestHealTex }) do
		SetSharpTexture(texture, nil)
		texture:SetVertexColor(1, 1, 1, 0)
	end
	local healSpell, healThreshold = PriestSecretHealVisual()
	if not AL.rotationSecretVisual and healSpell and healThreshold then
		local healTexture = AL.IconFor(healSpell) or AL.SpellTexture(healSpell) or "Interface\\Icons\\INV_Misc_QuestionMark"
		local healSlot = AL.SlotFor(healSpell) == 6 and A6PriestHealTex or A3PriestHealTex
		SetSharpTexture(priestHealOverlay, healTexture)
		SetSharpTexture(healSlot, healTexture)
		if not ApplySecretHealthVisibility(priestHealOverlay, healThreshold) then priestHealOverlay:SetVertexColor(1, 1, 1, 0) end
		if ApplySecretHealthVisibility(healSlot, healThreshold) then
			ApplySecretHealthVisibility(A3Tex, healThreshold, true)
			ApplySecretHealthVisibility(A6Tex, healThreshold, true)
		end
	end
	local healingVisualOK, healingActive = true, false
	if AL.HealingEngine and AL.HealingEngine.Update then
		local healingOK, healingResult = pcall(AL.HealingEngine.Update, AL.HealingEngine, spell, reason)
		healingVisualOK, healingActive = healingOK, healingOK and healingResult == true
		if not healingOK then
			pcall(AL.HealingEngine.ClearVisuals, AL.HealingEngine)
			local message = type(healingResult) == "string" and not (issecretvalue and issecretvalue(healingResult))
				and healingResult or "Protected HealingEngine display failure"
			if message ~= lastHealingVisualError and AL.Debug and AL.Debug.CaptureError then
				lastHealingVisualError = message
				AL.Debug.CaptureError("HealingEngine display: " .. message, "healing engine")
			end
		end
	end
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
	-- Observe the actual A[3]/A[6] output once after conditional overlays.
	-- A protected-health plan may show a different spell without Lua being
	-- allowed to inspect that choice; it must never start a false blacklist.
	if type(AL.ObserveDisplayedSpell) == "function" then
		local observedSpell, observedSource
		if visualOK and healingVisualOK and not healingActive
			and not AL.rotationSecretVisual and not (healSpell and healThreshold)
			and type(spell) == "string" and (slot == 3 or slot == 6)
			and A[slot].tex:IsShown() then
			observedSpell, observedSource = spell, slot == 3 and "A3" or "A6"
		end
		AL.ObserveDisplayedSpell(observedSpell, observedSource)
	end
	local toggleLayoutChanged
	for _, b in ipairs(toggles) do
		local compact = ActionLiteDB and ActionLiteDB.togglesHidden == true or false
		if b:IsShown() and (b.on ~= (b.isOn() and true or false) or b.compact ~= compact) then
			b:Paint()
			toggleLayoutChanged = true
		end
	end
	if toggleLayoutChanged then LayoutRoleToggles() end
end)

f:SetScript("OnMouseUp", function(_, button)
	if button == "RightButton" then AL.ToggleMenu() end
end)

local announced = false
local SCAN_DELAY = 0.5
local scanToken = 0
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")
pcall(f.RegisterEvent, f, "LEARNED_SPELL_IN_TAB")
f:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		ActionLiteDB = ActionLiteDB or {}
		ActionLiteDB.profiles = ActionLiteDB.profiles or {}
		-- Global values added in 0.6.0 without overwriting existing values.
		if AL.FillDBDefaults then AL.FillDBDefaults() end
		-- Always open the menu on the player's class; the dropdown can then
		-- inspect other profiles.
		ActionLiteDB.activeProfile = AL.playerClass
		AL.FillDefaults(AL.Profile(AL.playerClass), AL.playerClass)
		AL.RestoreSelfBuffs()
		if ActionLiteDB.pos then
			local p = ActionLiteDB.pos
			self:ClearAllPoints()
			self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		end
		if ActionLiteDB.hidden then self:Hide() end
		AL.ApplyStyle()
		AL.ApplyLock()
		AL.ApplySlots()
		if not announced then
			announced = true
			AL.Announce()
		end
		scanToken = scanToken + 1
		AL.ScanSpellbook()
		return
	end
	-- Actually learning a spell can remove it from the blacklist.
	if event == "LEARNED_SPELL_IN_TAB" and AL.unlearned then wipe(AL.unlearned) end
	if not (C_Timer and C_Timer.After) then
		AL.ScanSpellbook()
		return
	end
	-- SPELLS_CHANGED arrives in bursts (quest turn-in, level-up): scan once after it settles.
	scanToken = scanToken + 1
	local token = scanToken
	C_Timer.After(SCAN_DELAY, function()
		if token == scanToken then AL.ScanSpellbook() end
	end)
end)

SLASH_ACTIONLITEMENU1 = "/action"
SlashCmdList.ACTIONLITEMENU = function()
	AL.ToggleMenu()
end

SLASH_ACTIONLITE1 = "/al"
SLASH_ACTIONLITE2 = "/actionlite"
SlashCmdList.ACTIONLITE = function(msg)
	msg = msg:lower():gsub("%s+", "")
	if msg == "lock" then
		ActionLiteDB.locked = true
		AL.ApplyLock()
		AL.Say(L("ICON_LOCKED"))
	elseif msg == "unlock" then
		ActionLiteDB.locked = false
		AL.ApplyLock()
		AL.Say(L("ICON_UNLOCKED"))
	elseif msg == "buffs" then
		AL.DumpBuffs()
	elseif msg == "why" then
		local spell, reason = AL.NextSpell()
		AL.Say(L("SUGGESTION", tostring(spell or L("NONE")), tostring(reason)))
	elseif msg == "train" then
		AL.ScanSpellbook()
		AL.ReportTrainable(UnitLevel("player"))
	elseif msg == "debug" then
		ActionLiteDB.debug = not ActionLiteDB.debug
		AL.Say(ActionLiteDB.debug and L("CAST_DEBUG_ON") or L("CAST_DEBUG_OFF"))
	elseif msg == "reset" then
		AL.ResetIconPosition()
		AL.Say(L("ICON_POSITION_RESET"))
	elseif msg == "aoe" then
		AL.ToggleAoE()
	elseif msg == "burst" then
		ActionLite_Burst()
		if AL.UI then AL.UI.Repaint() end
	elseif (msg == "log" or msg == "errors" or msg == "probe") and AL.ToggleDebug then
		if msg == "probe" then
			if AL.Debug and AL.Debug.RunProbe then AL.Debug.RunProbe() end
			AL.OpenDebug("probe")
		elseif msg == "errors" then
			AL.OpenDebug("errors")
		else
			AL.ToggleDebug("live")
		end
	elseif msg == "hide" then
		ActionLiteDB.hidden = true
		f:Hide()
	elseif msg == "show" then
		ActionLiteDB.hidden = false
		f:Show()
	else
		print("|cff89cff0ActionLITE|r: /al lock | unlock | reset | hide | show | aoe | burst | why | train | buffs | debug | log | errors | probe")
	end
end
