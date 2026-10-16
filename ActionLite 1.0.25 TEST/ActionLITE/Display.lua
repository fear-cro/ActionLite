local ADDON, AL = ...
local L = AL.L

-- ============================================================================
-- ActionLITE - Display.lua - v0.14.5
-- ----------------------------------------------------------------------------
-- Icone de recommandation, mini-icone et commandes slash.
-- Coloration de portee identique pour chaque suggestion et les deux icones.
-- ============================================================================

local f = CreateFrame("Frame", "ActionLiteFrame", UIParent, "BackdropTemplate")
AL.frame = f
f:SetSize(56, 56)
f:SetPoint("CENTER", 0, 180)
f:SetClampedToScreen(true)
f:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
f:SetBackdropColor(0, 0, 0, 0.75)
f:SetBackdropBorderColor(AL.BABY_R, AL.BABY_G, AL.BABY_B)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")

function AL.ApplyLock()
	f:EnableMouse(not ActionLiteDB.locked)
	if AL.grip then AL.grip:SetShown(not ActionLiteDB.locked) end
	if AL.ApplyToggles then AL.ApplyToggles() end
end

-- nobg reste prioritaire : c'est l'interrupteur "afficher le fond".
-- bgAlpha regle l'opacite lorsque le fond est affiche.
function AL.ApplyStyle()
	local s = AL.S()
	local alpha = 0
	if not s.nobg then
		alpha = tonumber(s.bgAlpha) or 0.75
		if alpha < 0 then alpha = 0 end
		if alpha > 1 then alpha = 1 end
	end
	f:SetBackdropColor(0, 0, 0, alpha)
	f:SetBackdropBorderColor(AL.BABY_R, AL.BABY_G, AL.BABY_B, s.nobg and 0 or 1)
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

-- la poignee d'angle redimensionne l'icone ; l'echelle vit dans le profil
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
	local scale = math.max(0.5, math.min(2, (cx - leftPx) / 56 / UIParent:GetEffectiveScale()))
	AL.S().scale = scale
	f:SetScale(scale)
	es = f:GetEffectiveScale()
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftPx / es, topPx / es)
end)

local icon = f:CreateTexture(nil, "ARTWORK")
icon:SetSize(44, 44)
icon:SetPoint("CENTER")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)


-- Priest secret-health visual priority. Forever may protect the actual health
-- percentage; the protected value is fed directly into a Blizzard ColorCurve
-- and never inspected by Lua.
local priestHealOverlay = f:CreateTexture(nil, "OVERLAY")
priestHealOverlay:SetSize(44, 44)
priestHealOverlay:SetPoint("CENTER")
priestHealOverlay:SetTexCoord(0.08, 0.92, 0.08, 0.92)
priestHealOverlay:SetVertexColor(1, 1, 1, 0)

local rogueFinisherOverlay = f:CreateTexture(nil, "OVERLAY")
rogueFinisherOverlay:SetSize(44, 44)
rogueFinisherOverlay:SetPoint("CENTER")
rogueFinisherOverlay:SetTexCoord(0.08, 0.92, 0.08, 0.92)
rogueFinisherOverlay:SetVertexColor(1, 1, 1, 0)

local priestHealthCurves = {}
local function PriestHealthVisibilityCurve(threshold)
	if priestHealthCurves[threshold] then return priestHealthCurves[threshold] end
	if not C_CurveUtil or type(C_CurveUtil.CreateColorCurve) ~= "function" or type(CreateColor) ~= "function" then return nil end
	local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
	if not ok or not curve then return nil end
	pcall(curve.SetType, curve, Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	local cut = math.max(0, math.min(100, threshold)) / 100
	if not pcall(curve.AddPoint, curve, 0.0, CreateColor(1, 1, 1, 1)) then return nil end
	if not pcall(curve.AddPoint, curve, cut, CreateColor(1, 1, 1, 0)) then return nil end
	if not pcall(curve.AddPoint, curve, 1.0, CreateColor(1, 1, 1, 0)) then return nil end
	priestHealthCurves[threshold] = curve
	return curve
end

local function ApplySecretHealthVisibility(texture, threshold)
	local curve = PriestHealthVisibilityCurve(threshold)
	if not texture or not curve or type(UnitHealthPercent) ~= "function" then return false end
	local ok, color = pcall(UnitHealthPercent, "player", true, curve)
	if not ok or not color then return false end
	return pcall(function()
		local r, g, b, a = color:GetRGBA()
		texture:SetVertexColor(r, g, b, a)
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

-- au-dessus du balayage de recharge, sinon le texte passe dessous
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
local COMPACT_TOGGLE_PX, COMPACT_TOGGLE_GAP = 16, 4
local function QuickToggle(index, caption, tipKey, isOn, onClick)
	local b = CreateFrame("Button", nil, f)
	b:SetSize(38, 24)
	b:SetPoint("TOPLEFT", f, "TOPRIGHT", 3, -(index - 1) * 28)
	b:RegisterForClicks("LeftButtonUp")
	local edge = b:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	local bg = b:CreateTexture(nil, "BORDER")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0, 0, 0, 0.8)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetPoint("TOPLEFT", 1, -1)
	hover:SetPoint("BOTTOMRIGHT", -1, 1)
	hover:SetColorTexture(1, 1, 1, 0.12)
	-- coche = repere d'etat qui ne depend pas de la couleur
	local check = b:CreateTexture(nil, "OVERLAY")
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	check:SetSize(14, 14)
	check:SetPoint("LEFT", 3, 0)
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	function b:Paint()
		local on = isOn() and true or false
		local compact = ActionLiteDB and ActionLiteDB.togglesHidden == true or false
		if b.compact ~= compact then
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", f, "TOPRIGHT", 3,
				-(index - 1) * (compact and COMPACT_TOGGLE_PX + COMPACT_TOGGLE_GAP or 28))
			b.compact = compact
		end
		label:SetShown(not compact)
		check:SetShown(not compact and on)
		if compact then
			b:SetSize(COMPACT_TOGGLE_PX, COMPACT_TOGGLE_PX)
			local r, g, bl = on and 0.1 or 1, on and 0.9 or 0.125, on and 0.1 or 0.125
			edge:SetColorTexture(r, g, bl, 1)
			bg:SetColorTexture(r, g, bl, 1)
		else
			label:SetText(caption)
			local pad = on and 14 or 0
			label:SetPoint("CENTER", pad / 2, 0)
			b:SetSize(math.max(38, math.ceil((label:GetStringWidth() or 0) + 12 + pad)), 24)
			bg:SetColorTexture(0, 0, 0, 0.8)
			if on then
				local r, g, bl = AL.GlowColor()
				edge:SetColorTexture(r, g, bl, 1)
				label:SetTextColor(1, 1, 1, 1)
			else
				edge:SetColorTexture(0.35, 0.36, 0.40, 1)
				label:SetTextColor(0.66, 0.68, 0.72, 1)
			end
		end
		b.on = on
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

function PaintToggles()
	for _, b in ipairs(toggles) do b:Paint() end
end

function AL.ApplyToggles()
	for _, b in ipairs(toggles) do
		b:Show()
		b:EnableMouse(true)
		b:Paint()
	end
end

-- Role actif des classes disposant de plusieurs moteurs. La valeur vient du
-- meme profil que celui lu par la rotation afin que l'etiquette ne diverge pas.
local roleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
roleText:SetPoint("BOTTOM", f, "TOP", 0, 3)
roleText:SetShadowColor(0, 0, 0, 1)
roleText:SetShadowOffset(1, -1)
local lastRole
function AL.UpdateRoleText()
	local role
	if AL.playerClass == "WARRIOR" then
		role = AL.S().warriorRole == "TANK" and "TANK" or "DPS"
	elseif AL.playerClass == "PALADIN" then
		role = AL.S().paladinRole == "TANK" and "TANK" or "DPS"
	elseif AL.playerClass == "SHAMAN" then
		role = AL.S().shamanRole == "ELEMENTAL" and "ELEMENTAL" or "ENHANCEMENT"
	else
		roleText:Hide()
		lastRole = nil
		return
	end
	if role ~= lastRole then
		lastRole = role
		if role == "TANK" then
			roleText:SetText("|cff4da6ffTANK|r")
		elseif role == "ELEMENTAL" then
			roleText:SetText("|cff33ccffELEMENTAL|r")
		elseif role == "ENHANCEMENT" then
			roleText:SetText("|cffffcc00ENHANCEMENT|r")
		else
			roleText:SetText("|cffffcc00DPS|r")
		end
	end
	roleText:Show()
end
AL.UpdateRoleText()

-- Mini-icone : suggestion sans bordure ancree en haut a gauche de l'ecran,
-- dimensionnee en pixels physiques pour rester nette a toute echelle
local MINI_PX, MINI_X, MINI_Y = 18, 19, 7
local mini = CreateFrame("Frame", "ActionLiteMiniFrame", UIParent)
local miniTex = mini:CreateTexture(nil, "OVERLAY")
miniTex:SetAllPoints(mini)
miniTex:Hide()
local miniPriestHealTex = mini:CreateTexture(nil, "OVERLAY")
miniPriestHealTex:SetAllPoints(mini)
miniPriestHealTex:SetVertexColor(1, 1, 1, 0)
local miniRogueFinisherTex = mini:CreateTexture(nil, "OVERLAY")
miniRogueFinisherTex:SetAllPoints(mini)
miniRogueFinisherTex:SetVertexColor(1, 1, 1, 0)

-- EllesmereUI hooks every SetTexture to turn pixel snapping off, which blurs the pixel-sized icon
local snapOn = miniTex.IsSnappingToPixelGrid and miniTex:IsSnappingToPixelGrid()
local snapBias = miniTex.GetTexelSnappingBias and miniTex:GetTexelSnappingBias()
local function SetSharpTexture(tex, path)
	tex:SetTexture(path)
	if snapOn ~= nil and tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(snapOn) end
	if snapBias ~= nil and tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(snapBias) end
end

local miniH, miniE = 0, 0
local function LayoutMini(force)
	if not GetPhysicalScreenSize then
		if force or miniH ~= -1 then
			miniH = -1
			mini:SetSize(MINI_PX, MINI_PX)
			mini:ClearAllPoints()
			mini:SetPoint("TOPLEFT", UIParent, "TOPLEFT", MINI_X, MINI_Y)
		end
		return
	end
	local _, h = GetPhysicalScreenSize()
	local e = UIParent:GetEffectiveScale()
	if type(h) ~= "number" or h <= 0 or type(e) ~= "number" or e <= 0 then return end
	if not force and h == miniH and e == miniE then return end
	miniH, miniE = h, e
	-- 768 est la hauteur d'ecran virtuelle de WoW : conversion pixels -> unites
	local px = 768 / (h * e)
	mini:SetSize(MINI_PX * px, MINI_PX * px)
	mini:ClearAllPoints()
	mini:SetPoint("TOPLEFT", UIParent, "TOPLEFT", MINI_X * px, MINI_Y * px)
end
LayoutMini()

function AL.ApplyMini()
	mini:SetMovable(false)
	mini:EnableMouse(false)
	mini:SetScale(1)
	mini:SetAlpha(1)
	mini:Show()
	LayoutMini(true)
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

-- AL.CooldownRemaining compte en secondes entieres (time()) : 1.5 s de tolerance avant relance
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
	local key = small and "mini" or "main"
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
	if small then row.tex:SetAllPoints(parent)
	else
		row.tex:SetSize(44, 44); row.tex:SetPoint("CENTER", parent, "CENTER")
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
		if pair.mini then pair.mini.root:Hide() end
	end
	rogueFinisherOverlay:SetTexture(nil); miniRogueFinisherTex:SetTexture(nil)
	rogueFinisherOverlay:SetVertexColor(1, 1, 1, 0); miniRogueFinisherTex:SetVertexColor(1, 1, 1, 0)
	icon:SetAlpha(1); miniTex:SetAlpha(1); keyText:SetAlpha(1)
	rogueFinisherKey:Hide()
	AL.rogueSecretVisual, AL.rotationSecretVisual = nil, nil
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
		local main, small = RogueVisualRow(index, f, false), RogueVisualRow(index, mini, true)
		local texture = decision.spell and (AL.IconFor(decision.spell) or AL.SpellTexture(decision.spell))
			or "Interface\\Icons\\Spell_Nature_TimeStop"
		local r, g, b = 1, 1, 1
		if decision.spell and not AL.S().norange and AL.InRange(decision.spell) == false then r, g, b = 1, 0.25, 0.25 end
		SetSharpTexture(main.tex, texture); SetSharpTexture(small.tex, texture)
		main.tex:SetVertexColor(r, g, b, 1); small.tex:SetVertexColor(r, g, b, 1)
		local key = decision.spell and not ActionLiteDB.keybindHidden and AL.KeybindFor and AL.KeybindFor(decision.spell)
		main.key:SetText(key or ""); main.key:SetShown(key ~= nil and key ~= false)
		rotation.ApplyVisualRow(main.nodes, decision, values)
		rotation.ApplyVisualRow(small.nodes, decision, values)
		main.root:Show(); small.root:Show()
	end
	-- Base and conditional rows share the same masks, so icons, keys and action
	-- highlights cannot disagree about a higher-priority defensive cooldown.
	icon:SetAlpha(0); miniTex:SetAlpha(0); keyText:SetAlpha(0)
	AL.rotationSecretVisual = { plan = plan, values = values, spells = plan.spells,
		baseSpell = spell, baseReason = reason, at = GetTime() }
	AL.rogueSecretVisual = AL.playerClass == "ROGUE" and AL.rotationSecretVisual or nil

end

local idleIcon = "Interface\\Icons\\INV_Sword_27"
-- Dedicated wait/pooling visual. It is not a spell suggestion and therefore
-- never produces an action-bar glow.
local poolingIcon = "Interface\\Icons\\Spell_Nature_TimeStop"
-- pilote separe : les suggestions continuent d'alimenter la mini-icone meme
-- lorsque l'icone principale est masquee
local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.15 then return end
	elapsed = 0
	AL.UpdateRoleText()
	local spell, reason = AL.NextSpell()
	AL.lastSuggestion = spell
	local tex, r, g, b = nil, 1, 1, 1
	if spell then
		tex = AL.IconFor(spell) or AL.SpellTexture(spell) or "Interface\\Icons\\INV_Misc_QuestionMark"
		if not AL.S().norange and AL.InRange(spell) == false then r, g, b = 1, 0.25, 0.25 end
	elseif reason == "Channeling" then
		tex = poolingIcon
	elseif reason == "Drink" then
		tex = "Interface\\Icons\\INV_Drink_07"
	end
	SetSharpTexture(icon, tex or idleIcon)
	icon:SetVertexColor(r, g, b)
	LayoutMini()
	miniTex:SetShown(tex ~= nil)
	if tex then
		SetSharpTexture(miniTex, tex)
		miniTex:SetVertexColor(r, g, b)
	end

	local healSpell, healThreshold = PriestSecretHealVisual()
	if healSpell and healThreshold then
		local healTexture = AL.IconFor(healSpell) or AL.SpellTexture(healSpell) or "Interface\\Icons\\INV_Misc_QuestionMark"
		SetSharpTexture(priestHealOverlay, healTexture)
		SetSharpTexture(miniPriestHealTex, healTexture)
		if not ApplySecretHealthVisibility(priestHealOverlay, healThreshold) then priestHealOverlay:SetVertexColor(1,1,1,0) end
		if not ApplySecretHealthVisibility(miniPriestHealTex, healThreshold) then miniPriestHealTex:SetVertexColor(1,1,1,0) end
	else
		priestHealOverlay:SetTexture(nil)
		miniPriestHealTex:SetTexture(nil)
		priestHealOverlay:SetVertexColor(1,1,1,0)
		miniPriestHealTex:SetVertexColor(1,1,1,0)
	end

	if AL.UpdateGlow then pcall(AL.UpdateGlow, spell) end
	pcall(UpdateKeybind, spell)
	pcall(UpdateCombo)
	pcall(UpdateSwipe, spell)
	local visualOK = pcall(UpdateRogueSecretVisual, spell, reason)
	if not visualOK then
		ResetRogueSecretVisual()
	end
	for _, b in ipairs(toggles) do
		local compact = ActionLiteDB and ActionLiteDB.togglesHidden == true or false
		if b:IsShown() and (b.on ~= (b.isOn() and true or false) or b.compact ~= compact) then b:Paint() end
	end
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
		-- valeurs globales ajoutees en 0.6.0, sans ecraser les anciennes
		if AL.FillDBDefaults then AL.FillDBDefaults() end
		-- on ouvre toujours le menu sur la classe jouee ; la liste peut ensuite
		-- consulter les autres profils
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
		AL.ApplyMini()
		if not announced then
			announced = true
			AL.Announce()
		end
		scanToken = scanToken + 1
		AL.ScanSpellbook()
		return
	end
	-- apprendre reellement un sort peut annuler une mise en liste noire
	if event == "LEARNED_SPELL_IN_TAB" and AL.unlearned then wipe(AL.unlearned) end
	if not (C_Timer and C_Timer.After) then
		AL.ScanSpellbook()
		return
	end
	-- SPELLS_CHANGED arrive en rafale (quete rendue, niveau) : un seul scan une fois calme
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
