local ADDON, AL = ...
local L = AL.L

local btn = CreateFrame("Button", "ActionLiteMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetTexture("Interface\\Icons\\INV_Sword_27")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetPoint("CENTER", -1, 1)

local function Reposition()
	local angle = (ActionLiteDB and ActionLiteDB.minimapPos) or 220
	local rad = math.rad(angle)
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(rad), 80 * math.sin(rad))
end
Reposition()

btn:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		ActionLiteDB = ActionLiteDB or {}
		ActionLiteDB.minimapPos = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
		Reposition()
	end)
end)
btn:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
end)

btn:SetScript("OnClick", function(_, button)
	if button == "RightButton" then
		ActionLite_Burst()
	else
		AL.ToggleMenu()
	end
end)

btn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Action|cff1ae61aLITE|r")
	GameTooltip:AddLine(L("MINIMAP_LEFT"), 1, 1, 1)
	GameTooltip:AddLine(L("MINIMAP_RIGHT"), 1, 1, 1)
	GameTooltip:AddLine("|cffffcc00Drag:|r move around the minimap", 1, 1, 1)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

function AL.ApplyMinimapButton()
	btn:SetShown(not (ActionLiteDB and ActionLiteDB.mmHidden))
	Reposition()
end

btn:RegisterEvent("PLAYER_ENTERING_WORLD")
btn:SetScript("OnEvent", AL.ApplyMinimapButton)
