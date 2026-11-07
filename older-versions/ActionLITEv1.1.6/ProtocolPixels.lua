local ADDON, AL = ...

-- Action-compatible one-pixel signals immediately to the right of A[10].
-- A[10] ends at physical x=163; these frames begin at x=163 and must remain
-- borderless. The Action-main revision defines no active signals at y=-1 or
-- y=-2, so ActionLITE deliberately leaves those coordinates untouched.

local unpack = unpack or table.unpack

-- Exact Action.Data.UC values. These colors are calibrated protocol values;
-- do not round, normalize, tint, or replace them with display colors.
local COLOR_VALUES = {
	[0] = { 0.000000, 0.000000, 0.000000, 1.0 },
	[1] = { 0.192157, 0.878431, 0.015686, 1.0 },
	[2] = { 0.780392, 0.788235, 0.745098, 1.0 },
	[3] = { 0.498039, 0.184314, 0.521569, 1.0 },
	[4] = { 0.627451, 0.905882, 0.882353, 1.0 },
	[5] = { 0.145098, 0.658824, 0.121569, 1.0 },
	[6] = { 0.639216, 0.490196, 0.921569, 1.0 },
	[7] = { 0.172549, 0.368627, 0.427451, 1.0 },
	[8] = { 0.949020, 0.333333, 0.980392, 1.0 },
	[9] = { 0.109804, 0.388235, 0.980392, 1.0 },
	[10] = { 0.615686, 0.694118, 0.435294, 1.0 },
	[11] = { 0.066667, 0.243137, 0.572549, 1.0 },
	[12] = { 0.113725, 0.129412, 1.000000, 1.0 },
	[13] = { 0.592157, 0.023529, 0.235294, 1.0 },
	[14] = { 0.545098, 0.439216, 1.000000, 1.0 },
	[15] = { 0.890196, 0.800000, 0.854902, 1.0 },
	[16] = { 0.513725, 0.854902, 0.639216, 1.0 },
	[17] = { 0.078431, 0.541176, 0.815686, 1.0 },
	[18] = { 0.109804, 0.184314, 0.666667, 1.0 },
	[19] = { 0.650980, 0.572549, 0.098039, 1.0 },
	[20] = { 0.541176, 0.466667, 0.027451, 1.0 },
	[21] = { 0.000000, 0.988235, 0.462745, 1.0 },
	[22] = { 0.211765, 0.443137, 0.858824, 1.0 },
	[23] = { 0.949020, 0.949020, 0.576471, 1.0 },
	[24] = { 0.972549, 0.800000, 0.682353, 1.0 },
	[25] = { 0.031373, 0.619608, 0.596078, 1.0 },
	[26] = { 0.670588, 0.925490, 0.513725, 1.0 },
	[27] = { 0.647059, 0.945098, 0.031373, 1.0 },
	[28] = { 0.058824, 0.490196, 0.054902, 1.0 },
	[29] = { 0.050980, 0.992157, 0.239216, 1.0 },
	[30] = { 0.949020, 0.721569, 0.388235, 1.0 },
	[31] = { 0.254902, 0.749020, 0.627451, 1.0 },
	[32] = { 0.470588, 0.454902, 0.603922, 1.0 },
	[33] = { 0.384314, 0.062745, 0.266667, 1.0 },
	[34] = { 0.639216, 0.168627, 0.447059, 1.0 },
	[35] = { 0.874510, 0.058824, 0.400000, 1.0 },
	[36] = { 0.925490, 0.070588, 0.713725, 1.0 },
	[37] = { 0.098039, 0.803922, 0.905882, 1.0 },
	[38] = { 0.243137, 0.015686, 0.325490, 1.0 },
	[39] = { 0.847059, 0.376471, 0.921569, 1.0 },
	[40] = { 0.341176, 0.533333, 0.231373, 1.0 },
	[41] = { 0.345098, 0.239216, 0.741176, 1.0 },
	[42] = { 0.407843, 0.501961, 0.086275, 1.0 },
	[43] = { 0.160784, 0.470588, 0.164706, 1.0 },
	[44] = { 0.725490, 0.572549, 0.647059, 1.0 },
	[45] = { 0.788235, 0.470588, 0.858824, 1.0 },
	[46] = { 0.615686, 0.227451, 0.988235, 1.0 },
	[47] = { 0.486275, 0.176471, 1.000000, 1.0 },
	[48] = { 0.031373, 0.572549, 0.152941, 1.0 },
	[49] = { 0.874510, 0.239216, 0.239216, 1.0 },
	[50] = { 0.117647, 0.870588, 0.635294, 1.0 },
	[51] = { 0.458824, 0.945098, 0.784314, 1.0 },
	[52] = { 0.239216, 0.654902, 0.278431, 1.0 },
	[53] = { 0.537255, 0.066667, 0.905882, 1.0 },
	[54] = { 0.333333, 0.415686, 0.627451, 1.0 },
	[55] = { 0.576471, 0.811765, 0.011765, 1.0 },
	[56] = { 0.517647, 0.164706, 0.627451, 1.0 },
	[57] = { 0.439216, 0.074510, 0.941176, 1.0 },
	[58] = { 0.984314, 0.854902, 0.376471, 1.0 },
	[59] = { 0.082353, 0.286275, 0.890196, 1.0 },
	[60] = { 0.058824, 0.003922, 0.964706, 1.0 },
	[61] = { 0.956863, 0.509804, 0.949020, 1.0 },
	[62] = { 0.474510, 0.858824, 0.031373, 1.0 },
	[63] = { 0.509804, 0.882353, 0.423529, 1.0 },
	[64] = { 0.337255, 0.647059, 0.427451, 1.0 },
	[65] = { 0.611765, 0.525490, 0.352941, 1.0 },
	[66] = { 0.921569, 0.129412, 0.913725, 1.0 },
	[67] = { 0.117647, 0.933333, 0.862745, 1.0 },
	[68] = { 0.733333, 0.015686, 0.937255, 1.0 },
	[69] = { 0.819608, 0.392157, 0.686275, 1.0 },
	[70] = { 0.823529, 0.976471, 0.541176, 1.0 },
	[71] = { 0.043137, 0.305882, 0.800000, 1.0 },
	[72] = { 0.737255, 0.270588, 0.760784, 1.0 },
	[73] = { 0.807843, 0.368627, 0.058824, 1.0 },
	[74] = { 0.364706, 0.078431, 0.078431, 1.0 },
	[75] = { 0.094118, 0.901961, 1.000000, 1.0 },
	[76] = { 0.772549, 0.690196, 0.047059, 1.0 },
	[77] = { 0.415686, 0.784314, 0.854902, 1.0 },
	[78] = { 0.470588, 0.733333, 0.047059, 1.0 },
	[79] = { 0.619608, 0.086275, 0.572549, 1.0 },
	[80] = { 0.517647, 0.352941, 0.678431, 1.0 },
	[81] = { 0.003922, 0.149020, 0.694118, 1.0 },
	[82] = { 0.454902, 0.619608, 0.831373, 1.0 },
	[83] = { 0.674510, 0.741176, 0.050980, 1.0 },
	[84] = { 0.560784, 0.713725, 0.784314, 1.0 },
	[85] = { 0.400000, 0.721569, 0.737255, 1.0 },
	[86] = { 0.094118, 0.274510, 0.392157, 1.0 },
	[87] = { 0.298039, 0.498039, 0.462745, 1.0 },
	[88] = { 0.125490, 0.196078, 0.027451, 1.0 },
	[89] = { 0.937255, 0.564706, 0.368627, 1.0 },
	[90] = { 0.929412, 0.592157, 0.501961, 1.0 },
	[91] = { 0.411765, 0.760784, 0.176471, 1.0 },
	[92] = { 0.780392, 0.286275, 0.415686, 1.0 },
	[93] = { 0.584314, 0.811765, 0.956863, 1.0 },
	[94] = { 0.513725, 0.658824, 0.650980, 1.0 },
	[95] = { 0.913725, 0.180392, 0.737255, 1.0 },
	[96] = { 0.576471, 0.250980, 0.160784, 1.0 },
	[97] = { 0.803922, 0.741176, 0.874510, 1.0 },
	[98] = { 0.647059, 0.874510, 0.713725, 1.0 },
	[99] = { 0.007843, 0.301961, 0.388235, 1.0 },
	[100] = { 0.572549, 0.705882, 0.984314, 1.0 },
}

local function ColorFunction(color)
	return function() return color[1], color[2], color[3], color[4] end
end

local UC = { [""] = ColorFunction(COLOR_VALUES[0]) }
for index, color in pairs(COLOR_VALUES) do UC[index] = ColorFunction(color) end

AL.Data = AL.Data or {}
AL.Data.UC = UC
AL.Data.UniversalColors = COLOR_VALUES

function AL.GetUniversalColor(index)
	local color = COLOR_VALUES[index] or COLOR_VALUES[0]
	return color[1], color[2], color[3], color[4]
end

AL.ProtocolPixelLayout = {
	x = 163,
	healing = 0,
	reserved1 = -1,
	reserved2 = -2,
	character = -3,
	framework = -4,
}

local function CreateProtocolPixel(name)
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetFrameLevel(101)
	frame:SetToplevel(true)
	frame:SetMovable(false)
	frame:EnableMouse(false)
	frame:SetScale(1)
	frame:SetAlpha(1)
	frame.texture = frame:CreateTexture(nil, "OVERLAY")
	frame.texture:SetAllPoints(frame)
	frame.texture:SetColorTexture(AL.GetUniversalColor(0))
	frame:Show()
	return frame
end

local pixels = {
	healing = CreateProtocolPixel("ActionLiteHealingTargetColor"),
	character = CreateProtocolPixel("ActionLiteCharacterColor"),
	framework = CreateProtocolPixel("ActionLiteFrameworkColor"),
}
AL.ProtocolPixels = pixels
AL.HealingTargetPixel = pixels.healing
_G.ActionLiteHealingTargetColor = pixels.healing

local function PixelScale()
	if type(GetPhysicalScreenSize) ~= "function" then return 1 end
	local _, height = GetPhysicalScreenSize()
	local effective = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
	if type(height) ~= "number" or height <= 0 or type(effective) ~= "number" or effective <= 0 then return 1 end
	return 768 / (height * effective)
end

local function PlacePixel(frame, y, pixelScale)
	frame:SetSize(pixelScale, pixelScale)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", AL.ProtocolPixelLayout.x * pixelScale, y * pixelScale)
end

function AL.LayoutProtocolPixels()
	local pixelScale = PixelScale()
	PlacePixel(pixels.healing, AL.ProtocolPixelLayout.healing, pixelScale)
	PlacePixel(pixels.character, AL.ProtocolPixelLayout.character, pixelScale)
	PlacePixel(pixels.framework, AL.ProtocolPixelLayout.framework, pixelScale)
end

local function SetPixelColor(frame, index)
	index = COLOR_VALUES[index] and index or 0
	if frame.colorIndex == index then return end
	frame.texture:SetColorTexture(AL.GetUniversalColor(index))
	frame.colorIndex = index
end

local HEALING_UNIT_COLORS = { none = 0 }
for index = 1, 40 do HEALING_UNIT_COLORS["raid" .. index] = index end
for index = 1, 4 do HEALING_UNIT_COLORS["party" .. index] = 40 + index end
HEALING_UNIT_COLORS.player = 45
HEALING_UNIT_COLORS.focus = 46
for index = 1, 4 do HEALING_UNIT_COLORS["partypet" .. index] = 46 + index end
for index = 1, 40 do HEALING_UNIT_COLORS["raidpet" .. index] = 50 + index end
AL.HealingTargetColors = HEALING_UNIT_COLORS

function AL.SetHealingTargetPixel(unitID)
	if type(issecretvalue) == "function" then
		local ok, secret = pcall(issecretvalue, unitID)
		if not ok or secret then unitID = nil end
	end
	local index = type(unitID) == "string" and HEALING_UNIT_COLORS[unitID] or nil
	index = index or 0
	SetPixelColor(pixels.healing, index)
	pixels.healing.unitID = index == 0 and "none" or unitID
	return index
end

local FOREVER_CLASS_COLORS = {
	WARRIOR = 40,
	PALADIN = 41,
	HUNTER = 42,
	ROGUE = 43,
	PRIEST = 44,
	SHAMAN = 45,
	MAGE = 46,
	WARLOCK = 47,
	DRUID = 48,
}
AL.ForeverClassColors = FOREVER_CLASS_COLORS

function AL.SetCharacterPixel(classToken)
	local index = FOREVER_CLASS_COLORS[classToken] or 0
	SetPixelColor(pixels.character, index)
	return index
end

local FRAMEWORK_COLORS = { v1 = 1, v2 = 2, MetaEngine = 3 }
function AL.SetFrameworkPixel(framework)
	local index = FRAMEWORK_COLORS[framework] or FRAMEWORK_COLORS.v1
	SetPixelColor(pixels.framework, index)
	return index
end

function AL.ApplyProtocolPixels()
	for _, frame in pairs(pixels) do
		frame:SetMovable(false)
		frame:EnableMouse(false)
		frame:SetScale(1)
		frame:SetAlpha(1)
		frame:Show()
	end
	AL.LayoutProtocolPixels()
	AL.SetHealingTargetPixel(pixels.healing.unitID)
	AL.SetCharacterPixel(AL.playerClass)
	AL.SetFrameworkPixel("v1")
end

AL.ApplyProtocolPixels()

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "DISPLAY_SIZE_CHANGED")
pcall(events.RegisterEvent, events, "UI_SCALE_CHANGED")
events:SetScript("OnEvent", AL.ApplyProtocolPixels)

