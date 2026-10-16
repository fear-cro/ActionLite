local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - Swing.lua
-- ----------------------------------------------------------------------------
-- Barre de swing dans la marge basse de l'icone : melee et Auto Shot / Shoot.
-- ============================================================================

local W, H = 44, 3
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0.2
-- longest classic weapon speed is under 4 s; a longer gap is a pause, not a swing
local MAX_MEASURED = 4

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function Seconds(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if ok and type(v) == "number" and not Secret(v) and v > 0 then return v end
end

function AL.SwingEnabled()
	local v = AL.S().swingBar
	if v == nil then return AL.playerClass == "WARRIOR" or AL.playerClass == "HUNTER" end
	return v
end

local bar = CreateFrame("Frame", nil, AL.frame)
bar:SetSize(W, H)
bar:SetPoint("BOTTOM", AL.frame, "BOTTOM", 0, 3)
bar:Hide()
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(bar)
bg:SetColorTexture(0, 0, 0, 0.6)
local fill = bar:CreateTexture(nil, "ARTWORK")
fill:SetPoint("TOPLEFT", bar, "TOPLEFT")
fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
bar.fill = fill
AL.swingBar = bar

local swings = { melee = {}, ranged = {} }
local active

local function Start(kind, speed)
	local s = swings[kind]
	local now = GetTime()
	if s.at and now - s.at <= MAX_MEASURED then s.measured = now - s.at end
	s.at = now
	s.dur = speed or s.measured
	active = kind
	if s.dur and AL.SwingEnabled() then bar:Show() end
end

local function SlamWindow()
	local mod = AL.playerClass == "WARRIOR" and AL.rotations.WARRIOR
	return mod and mod.swingWindow
end

local gold
bar:SetScript("OnUpdate", function(self)
	local s = swings[active]
	local elapsed = s and s.at and GetTime() - s.at
	if not elapsed or not s.dur or elapsed > s.dur + 0.5 or not AL.SwingEnabled() then
		self:Hide()
		return
	end
	fill:SetWidth(math.max(0.01, W * math.min(1, elapsed / s.dur)))
	local window = active == "melee" and SlamWindow()
	local nowGold = window and elapsed <= window or false
	if nowGold ~= gold then
		gold = nowGold
		if gold then
			fill:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
		else
			fill:SetColorTexture(AL.BABY_R, AL.BABY_G, AL.BABY_B, 1)
		end
	end
end)
bar:SetScript("OnHide", function() gold = nil end)

local function OnCombatLog()
	local _, sub, _, src, _, _, _, _, _, _, _, _, a13, _, _, _, _, _, _, _, a21 = CombatLogGetCurrentEventInfo()
	local me = UnitGUID("player")
	if Secret(sub) or Secret(src) or Secret(me) or src ~= me then return end
	if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
		local offHand = sub == "SWING_DAMAGE" and a21 or a13
		if not Secret(offHand) and offHand == true then return end
		Start("melee", Seconds(UnitAttackSpeed, "player"))
	elseif sub == "RANGE_DAMAGE" or sub == "RANGE_MISSED" then
		Start("ranged", Seconds(UnitRangedDamage, "player"))
	end
end

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function()
	if CombatLogGetCurrentEventInfo then pcall(OnCombatLog) end
end)
