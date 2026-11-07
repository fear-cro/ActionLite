local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - Themes.lua
-- ----------------------------------------------------------------------------
-- Preset themes, a saved custom theme, an embedded Themes page and the
-- retained legacy editor drawer. Every change is applied immediately through
-- UI.ApplyTheme.
-- ============================================================================

local UI = AL.UI
local L = AL.L
local THEME = UI.Theme

local function Hex(s, a)
	return {
		tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255,
		tonumber(s:sub(5, 6), 16) / 255, a or 1,
	}
end

local function Copy(colors)
	local out = {}
	for token, c in pairs(colors) do out[token] = { c[1], c[2], c[3], c[4] or 1 } end
	return out
end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- The ACTIONLITE id is retained so existing SavedVariables select the new
-- Nova Console palette without migration. Motif colors are decorative only;
-- status colors keep their semantic meaning.
local PRESETS = {
	{ id = "ACTIONLITE", name = function() return "Nova Console" end, colors = {
		shell = { .055, .060, .058, .98 }, sidebar = { .085, .090, .086, .98 },
		surface = { .085, .090, .086, .98 }, surfaceAlt = { .115, .120, .112, 1 },
		raised = { .015, .018, .017, 1 }, line = { .420, .780, .780, 1 },
		lineSoft = { .220, .430, .430, .10 }, bronze = { .420, .780, .780, 1 },
		gold = { .880, .830, .660, 1 }, goldDim = { .470, .440, .350, 1 },
		crimson = { .515, .190, .165, 1 }, text = { .910, .890, .810, 1 },
		textDim = { .580, .610, .570, 1 }, textFaint = { .465, .490, .455, 1 },
		ok = { .300, .660, .490, 1 }, green = { .300, .660, .490, 1 },
		warn = { .880, .830, .660, 1 }, danger = { .780, .290, .250, 1 },
		motifA = { .300, .660, .490, 1 }, motifB = { .780, .290, .250, 1 },
		motifC = { .880, .830, .660, 1 },
	} },
	{ id = "ARCANE", name = function() return L("THEME_ARCANE") end, colors = {
		shell = { .047,.039,.090,.98 }, sidebar = { .086,.074,.165,.98 }, surface = { .086,.074,.165,.98 },
		surfaceAlt = { .125,.106,.227,1 }, raised = { .018,.012,.032,1 }, line = { .714,.612,1,1 },
		lineSoft = { .34,.27,.59,.10 }, bronze = { .714,.612,1,1 }, gold = { .89,.83,1,1 },
		goldDim = { .50,.42,.70,1 }, crimson = { .66,.24,.36,1 }, text = { .91,.89,1,1 },
		textDim = { .62,.59,.78,1 }, textFaint = { .50,.47,.63,1 }, ok = { .37,.91,.83,1 },
		green = { .37,.91,.83,1 }, warn = { .89,.83,1,1 }, danger = { 1,.36,.54,1 },
		motifA = { .37,.91,.83,1 }, motifB = { 1,.36,.54,1 }, motifC = { .89,.83,1,1 },
	} },
	{ id = "FROST", name = function() return L("THEME_FROST") end, colors = {
		shell = { .039,.063,.086,.98 }, sidebar = { .071,.118,.161,.98 }, surface = { .071,.118,.161,.98 },
		surfaceAlt = { .094,.157,.212,1 }, raised = { .012,.024,.036,1 }, line = { .624,.890,1,1 },
		lineSoft = { .25,.49,.65,.10 }, bronze = { .624,.890,1,1 }, gold = { .88,.96,1,1 },
		goldDim = { .45,.64,.73,1 }, crimson = { .66,.28,.28,1 }, text = { .90,.96,1,1 },
		textDim = { .61,.72,.79,1 }, textFaint = { .49,.58,.64,1 }, ok = { .49,.94,.75,1 },
		green = { .49,.94,.75,1 }, warn = { .88,.96,1,1 }, danger = { 1,.42,.42,1 },
		motifA = { .49,.94,.75,1 }, motifB = { 1,.42,.42,1 }, motifC = { .88,.96,1,1 },
	} },
	{ id = "FEL", name = function() return L("THEME_FEL") end, colors = {
		shell = { .027,.043,.024,.98 }, sidebar = { .059,.090,.047,.98 }, surface = { .059,.090,.047,.98 },
		surfaceAlt = { .110,.169,.090,1 }, raised = { .008,.018,.006,1 }, line = { .64,1,.24,1 },
		lineSoft = { .26,.50,.12,.10 }, bronze = { .64,1,.24,1 }, gold = { .91,.97,.86,1 },
		goldDim = { .48,.62,.39,1 }, crimson = { .66,.23,.16,1 }, text = { .91,.97,.86,1 },
		textDim = { .61,.72,.55,1 }, textFaint = { .49,.58,.44,1 }, ok = { .49,1,.35,1 },
		green = { .49,1,.35,1 }, warn = { .91,.97,.86,1 }, danger = { 1,.35,.24,1 },
		motifA = { .49,1,.35,1 }, motifB = { 1,.35,.24,1 }, motifC = { .91,.97,.86,1 },
	} },
	{ id = "BLOOD", name = function() return L("THEME_BLOOD") end, colors = {
		shell = { .051,.027,.031,.98 }, sidebar = { .102,.055,.063,.98 }, surface = { .102,.055,.063,.98 },
		surfaceAlt = { .180,.094,.106,1 }, raised = { .022,.006,.008,1 }, line = { 1,.35,.37,1 },
		lineSoft = { .53,.16,.19,.10 }, bronze = { 1,.35,.37,1 }, gold = { .96,.90,.82,1 },
		goldDim = { .66,.43,.44,1 }, crimson = { .66,.20,.20,1 }, text = { .96,.90,.90,1 },
		textDim = { .72,.57,.58,1 }, textFaint = { .58,.46,.47,1 }, ok = { .47,.89,.58,1 },
		green = { .47,.89,.58,1 }, warn = { .96,.90,.82,1 }, danger = { 1,.30,.30,1 },
		motifA = { .47,.89,.58,1 }, motifB = { 1,.30,.30,1 }, motifC = { .96,.90,.82,1 },
	} },
	{ id = "ROYAL", name = function() return L("THEME_ROYAL") end, colors = {
		shell = { .031,.047,.086,.98 }, sidebar = { .063,.094,.165,.98 }, surface = { .063,.094,.165,.98 },
		surfaceAlt = { .114,.169,.271,1 }, raised = { .008,.016,.035,1 }, line = { 1,.84,.35,1 },
		lineSoft = { .55,.43,.13,.10 }, bronze = { 1,.84,.35,1 }, gold = { .93,.95,1,1 },
		goldDim = { .54,.60,.73,1 }, crimson = { .66,.26,.26,1 }, text = { .93,.95,1,1 },
		textDim = { .64,.69,.80,1 }, textFaint = { .51,.55,.64,1 }, ok = { .43,.91,.63,1 },
		green = { .43,.91,.63,1 }, warn = { .93,.95,1,1 }, danger = { 1,.39,.39,1 },
		motifA = { .43,.91,.63,1 }, motifB = { 1,.39,.39,1 }, motifC = { .93,.95,1,1 },
	} },
	{ id = "SNES", name = function() return "SNES" end, colors = {
		shell = { .042,.041,.044,.98 }, sidebar = { .086,.084,.090,.98 }, surface = { .086,.084,.090,.98 },
		surfaceAlt = { .155,.151,.160,1 }, raised = { .020,.019,.022,1 }, line = { .690,.675,.700,1 },
		lineSoft = { .350,.330,.390,.10 }, bronze = { .405,.355,.600,1 }, gold = { .835,.825,.835,1 },
		goldDim = { .490,.480,.500,1 }, crimson = { .572,.083,.083,1 }, text = { .905,.900,.905,1 },
		textDim = { .585,.575,.590,1 }, textFaint = { .470,.460,.475,1 }, ok = { .420,.700,.525,1 },
		green = { .470,.760,.575,1 }, warn = { .835,.825,.835,1 }, danger = { .867,.125,.125,1 },
		motifA = { .405,.355,.600,1 }, motifB = { .867,.125,.125,1 }, motifC = { .835,.825,.835,1 },
	} },
}
-- Quick accent choices: gold, ember, crimson, rose, violet, frost, emerald, fel.
local ACCENTS = { "f0bd61", "ff8a3d", "ff5a5f", "ff7eb6", "b69cff", "9fe3ff", "5fe39a", "a4ff3c" }

-- Advanced editor, grouped so the list reads in short sections.
local SECTIONS = {
	{ label = "THEME_SEC_BG", tokens = { "shell", "sidebar", "surface", "surfaceAlt", "raised", "line", "lineSoft" } },
	{ label = "THEME_SEC_ACCENT", tokens = { "gold", "goldDim", "bronze" } },
	{ label = "THEME_SEC_TEXT", tokens = { "text", "textDim", "textFaint" } },
	{ label = "THEME_SEC_STATUS", tokens = { "ok", "green", "warn", "danger", "crimson" } },
}

local function Clamp(v) return math.max(0, math.min(1, v)) end
local function Lift(c, d) return { Clamp(c[1] + d), Clamp(c[2] + d), Clamp(c[3] + d) } end
local function Mul(c, k) return { Clamp(c[1] * k), Clamp(c[2] * k), Clamp(c[3] * k) } end

-- Main colors: one pick recolours a whole family, using the default theme's steps.
local GROUPS = {
	{ id = "background", base = "shell", apply = function(c, set)
		set("shell", { c[1], c[2], c[3], THEME.shell[4] or 0.97 })
		set("sidebar", Lift(c, 0.020))
		set("surface", Lift(c, 0.043))
		set("surfaceAlt", Lift(c, 0.075))
		set("raised", Lift(c, 0.114))
		set("line", Lift(c, 0.149))
	end },
	{ id = "accent", base = "gold", apply = function(c, set)
		set("gold", c)
		set("goldDim", Mul(c, 0.78))
		set("bronze", Mul(c, 0.8))
		set("motifC", c)
	end },
	{ id = "text", base = "text", apply = function(c, set)
		set("text", c)
		set("textDim", Mul(c, 0.68))
		set("textFaint", Mul(c, 0.55))
	end },
	{ id = "positive", base = "ok", apply = function(c, set)
		set("ok", c)
		set("green", Lift(c, 0.06))
		set("motifA", c)
	end },
	{ id = "warning", base = "warn", apply = function(c, set) set("warn", c) end },
	{ id = "danger", base = "danger", apply = function(c, set)
		set("danger", c)
		set("crimson", Mul(c, 0.66))
		set("motifB", c)
	end },
}

local PRESET_BY_ID = {}
for _, p in ipairs(PRESETS) do PRESET_BY_ID[p.id] = p end

-- --------------------------------------------------------------------------
-- Persistence uses the same redundant copy as the language (see Localization.lua).
-- --------------------------------------------------------------------------
local function Saved()
	ActionLiteDB = ActionLiteDB or {}
	local st = ActionLiteDB.uiTheme
	if type(st) ~= "table" then
		local ui = ActionLiteDB.profiles and ActionLiteDB.profiles.__ACTIONLITE_UI
		st = ui and type(ui.theme) == "table" and ui.theme or { preset = "ACTIONLITE" }
	end
	ActionLiteDB.uiTheme = st
	ActionLiteDB.profiles = ActionLiteDB.profiles or {}
	ActionLiteDB.profiles.__ACTIONLITE_UI = ActionLiteDB.profiles.__ACTIONLITE_UI or {}
	ActionLiteDB.profiles.__ACTIONLITE_UI.theme = st
	return st
end

local function CurrentColors(st)
	if st.preset == "CUSTOM" and st.custom and type(st.custom.colors) == "table" then
		-- Custom themes saved before the header motif existed inherit the three
		-- decorative colors from their original base preset.
		local base = (PRESET_BY_ID[st.custom.base] or PRESETS[1]).colors
		for _, token in ipairs({ "motifA", "motifB", "motifC" }) do
			if type(st.custom.colors[token]) ~= "table" and base[token] then
				local c = base[token]
				st.custom.colors[token] = { c[1], c[2], c[3], c[4] or 1 }
			end
		end
		return st.custom.colors
	end
	return (PRESET_BY_ID[st.preset] or PRESETS[1]).colors
end

local loaded = false
function AL.LoadTheme()
	if loaded then return end
	loaded = true
	UI.ApplyTheme(CurrentColors(Saved()))
end

local function SelectPreset(id)
	local st = Saved()
	st.preset = (id == "CUSTOM" and st.custom) and "CUSTOM" or (PRESET_BY_ID[id] and id or "ACTIONLITE")
	UI.ApplyTheme(CurrentColors(st))
end

-- The first color change turns the current theme into the custom theme.
local function EnsureCustom()
	local st = Saved()
	if st.preset ~= "CUSTOM" or not st.custom then
		st.custom = { base = st.preset ~= "CUSTOM" and st.preset or "ACTIONLITE", colors = Copy(THEME) }
		st.preset = "CUSTOM"
	end
	return st.custom
end

-- --------------------------------------------------------------------------
-- Drawer
-- --------------------------------------------------------------------------
local DRAWER_W = 300
local WHEEL = 128
local CHANNEL_INDEX = { THEME_RED = 1, THEME_GREEN = 2, THEME_BLUE = 3, THEME_OPACITY = 4 }
local SLIDE = 14
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function Swatch(parent, size, color)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetPoint("TOPLEFT", 1, -1)
	f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Border(f, { 0, 0, 0, 0.9 })
	function f:SetSwatch(c) f.tex:SetColorTexture(c[1], c[2], c[3], 1) end
	if color then f:SetSwatch(color) end
	return f
end

local function BuildThemeControls(host, stack)
	local controller = { host = host, stack = stack }

	-- ------------------------------------------------------------ presets
	local presetCard = UI.Card(stack, L("THEME_PRESETS"))
	local presetRows = {}

	local function PresetRow(id, label, colors)
		local st = UI.HostStack(presetCard)
		local row = CreateFrame("Button", nil, st.frame)
		local bg = UI.Fill(row, THEME.raised)
		local edge = UI.Border(row, THEME.line)
		local swatches = {}
		for i, token in ipairs({ "sidebar", "surface", "bronze", "gold", "text" }) do
			local s = Swatch(row, 12, colors and colors[token])
			s:SetPoint("LEFT", 6 + (i - 1) * 13, 0)
			s.token = token
			swatches[i] = s
		end
		local name = UI.Text(row, "GameFontHighlightSmall", THEME.text)
		name:SetPoint("LEFT", 6 + 5 * 13 + 6, 0)
		name:SetPoint("RIGHT", -6, 0)
		name:SetJustifyH("LEFT")
		name:SetText(label)

		function row:Paint()
			local st2 = Saved()
			local active = st2.preset == id
			local src = id == "CUSTOM" and st2.custom and st2.custom.colors or colors
			if src then
				for _, s in ipairs(swatches) do
					if src[s.token] then s:SetSwatch(src[s.token]) end
				end
			end
			bg:SetColorTexture(UI.Color(active and UI.Derived.checkOn or THEME.raised))
			edge:SetColor(UI.Color(active and THEME.gold or THEME.line))
			name:SetTextColor(UI.Color(active and THEME.gold or THEME.text))
			if id == "CUSTOM" then
				local show = st2.custom ~= nil
				if row:IsShown() ~= show then st:SetItemShown(row, show) end
			end
		end
		row:SetScript("OnEnter", function() edge:SetColor(UI.Color(THEME.gold)) end)
		row:SetScript("OnLeave", function() row:Paint() end)
		row:SetScript("OnClick", function()
			SelectPreset(id)
			controller.Refresh()
		end)
		st:Add(row, 24)
		UI.Register(function() row:Paint() end)
		presetRows[#presetRows + 1] = row
		return row
	end

	for _, p in ipairs(PRESETS) do PresetRow(p.id, p.name(), p.colors) end
	PresetRow("CUSTOM", L("THEME_CUSTOM"), nil)
	UI.Info(presetCard, L("THEME_CUSTOM_HELP"), { color = THEME.textFaint })

	-- Only one update per frame, even when several sliders move.
	local dirty = false
	host:HookScript("OnUpdate", function()
		if not dirty then return end
		dirty = false
		UI.ApplyTheme(Saved().custom.colors)
	end)

	local function SetCustom(token, c)
		EnsureCustom().colors[token] = { c[1], c[2], c[3], c[4] or 1 }
		dirty = true
	end

	-- Native hue/saturation wheel + brightness bar; false if the client lacks ColorSelect.
	local function Wheel(card, get, set)
		local host = CreateFrame("Frame", nil, UI.HostStack(card).frame)
		local ok, cs = pcall(CreateFrame, "ColorSelect", nil, host)
		if not ok or not cs or not cs.SetColorWheelTexture then return false end
		cs:SetPoint("TOPLEFT", 6, -4)
		cs:SetSize(WHEEL + 12 + 16, WHEEL)

		local wheel = cs:CreateTexture(nil, "ARTWORK")
		wheel:SetSize(WHEEL, WHEEL)
		wheel:SetPoint("TOPLEFT")
		cs:SetColorWheelTexture(wheel)
		local wheelThumb = cs:CreateTexture(nil, "OVERLAY")
		wheelThumb:SetTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
		wheelThumb:SetTexCoord(0, 0.15625, 0, 0.625)
		wheelThumb:SetSize(10, 10)
		cs:SetColorWheelThumbTexture(wheelThumb)

		local value = cs:CreateTexture(nil, "ARTWORK")
		value:SetSize(16, WHEEL)
		value:SetPoint("LEFT", wheel, "RIGHT", 12, 0)
		cs:SetColorValueTexture(value)
		local valueThumb = cs:CreateTexture(nil, "OVERLAY")
		valueThumb:SetTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
		valueThumb:SetTexCoord(0.25, 1, 0, 0.875)
		valueThumb:SetSize(48, 14)
		cs:SetColorValueThumbTexture(valueThumb)

		local preview = Swatch(host, 36)
		preview:SetPoint("TOPLEFT", cs, "TOPRIGHT", 10, -2)
		local hex = UI.Text(host, "GameFontHighlightSmall", THEME.text)
		hex:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -6)

		-- SetColorRGB fires OnColorSelect; the guard keeps repaints from writing back.
		local painting = false
		cs:SetScript("OnColorSelect", function(_, r, g, b)
			if painting then return end
			local cur = get()
			set({ r, g, b, cur[4] or 1 })
		end)

		local function Paint()
			local c = get()
			preview:SetSwatch(c)
			hex:SetText("#" .. UI.Hex(c):sub(3):upper())
			local r, g, b = cs:GetColorRGB()
			-- Re-seat the thumbs only when the color changed elsewhere, never mid-drag.
			if not r or math.abs(r - c[1]) + math.abs(g - c[2]) + math.abs(b - c[3]) > 0.01 then
				painting = true
				cs:SetColorRGB(c[1], c[2], c[3])
				painting = false
			end
		end
		UI.HostStack(card):Add(host, WHEEL + 10)
		UI.Register(Paint)
		Paint()
		return true
	end

	-- Color wheel (or sliders as fallback), plus opacity when asked.
	local function Editor(card, get, set, withAlpha)
		local channels = {}
		if not Wheel(card, get, set) then channels = { "THEME_RED", "THEME_GREEN", "THEME_BLUE" } end
		if withAlpha then channels[#channels + 1] = "THEME_OPACITY" end
		for _, key in ipairs(channels) do
			local index = CHANNEL_INDEX[key]
			UI.Slider(card, {
				label = L(key), min = 0, max = index == 4 and 100 or 255, step = 1,
				suffix = index == 4 and " %" or "",
				get = function()
					local c = get()
					return math.floor((index == 4 and (c[4] or 1) * 100 or c[index] * 255) + 0.5)
				end,
				set = function(v)
					local cur = get()
					local scaled = index == 4 and v / 100 or v / 255
					if math.abs((cur[index] or 1) - scaled) < 0.001 then return end
					local c = { cur[1], cur[2], cur[3], cur[4] or 1 }
					c[index] = scaled
					set(c)
				end,
			})
		end
	end

	-- A selectable row: swatch + label, highlighted while selected.
	local function PickRow(card, label, color, isSelected, onPick)
		local st = UI.HostStack(card)
		local row = CreateFrame("Button", nil, st.frame)
		local hl = UI.Fill(row, UI.Derived.highlight)
		local sw = Swatch(row, 14)
		sw:SetPoint("LEFT", 6, 0)
		local text = UI.Text(row, "GameFontHighlightSmall", THEME.text)
		text:SetPoint("LEFT", sw, "RIGHT", 8, 0)
		text:SetPoint("RIGHT", -64, 0)
		text:SetJustifyH("LEFT")
		text:SetText(label)
		local hex = UI.Text(row, "GameFontNormalSmall", THEME.textFaint)
		hex:SetPoint("RIGHT", -6, 0)
		function row:Paint()
			local c = color()
			sw:SetSwatch(c)
			hex:SetText("#" .. UI.Hex(c):sub(3):upper())
			hl:SetShown(isSelected())
			text:SetTextColor(UI.Color(isSelected() and THEME.gold or THEME.text))
		end
		row:SetScript("OnEnter", function() text:SetTextColor(UI.Color(THEME.gold)) end)
		row:SetScript("OnLeave", function() row:Paint() end)
		row:SetScript("OnClick", function()
			onPick()
			controller.Refresh()
		end)
		st:Add(row, 22, { gap = 2 })
		UI.Register(function() row:Paint() end)
		return row
	end

	-- --------------------------------------------------------- main colors
	local main = UI.Card(stack, L("THEME_MAIN"))
	local group = GROUPS[2]
	local mainEditing = UI.Info(main, "", { color = THEME.gold })
	Editor(main,
		function() return THEME[group.base] end,
		function(c) group.apply(c, SetCustom) end)
	for _, g in ipairs(GROUPS) do
		PickRow(main, L("THEME_G_" .. g.id),
			function() return THEME[g.base] end,
			function() return group == g end,
			function() group = g end)
	end

	UI.Info(main, L("THEME_ACCENT"), { color = THEME.textDim, gap = 10 })
	local chipRow = CreateFrame("Frame", nil, UI.HostStack(main).frame)
	for i, hex in ipairs(ACCENTS) do
		local accent = Hex(hex)
		local chip = CreateFrame("Button", nil, chipRow)
		chip:SetSize(22, 22)
		chip:SetPoint("LEFT", 6 + (i - 1) * 28, 0)
		local ring = chip:CreateTexture(nil, "BACKGROUND")
		ring:SetAllPoints()
		ring:SetTexture(CIRCLE)
		local dot = chip:CreateTexture(nil, "ARTWORK")
		dot:SetSize(16, 16)
		dot:SetPoint("CENTER")
		dot:SetTexture(CIRCLE)
		dot:SetVertexColor(accent[1], accent[2], accent[3], 1)
		local hover = false
		function chip:Paint()
			local g = THEME.gold
			local active = math.abs(g[1] - accent[1]) + math.abs(g[2] - accent[2]) + math.abs(g[3] - accent[3]) < 0.02
			ring:SetVertexColor(UI.Color((active or hover) and THEME.text or THEME.line))
		end
		chip:SetScript("OnEnter", function() hover = true chip:Paint() end)
		chip:SetScript("OnLeave", function() hover = false chip:Paint() end)
		chip:SetScript("OnClick", function() GROUPS[2].apply(accent, SetCustom) end)
		UI.Register(function() chip:Paint() end)
	end
	UI.HostStack(main):Add(chipRow, 28)

	UI.Slider(main, {
		label = L("THEME_BG_OPACITY"), min = 40, max = 100, step = 5, suffix = " %",
		get = function() return math.floor((THEME.shell[4] or 1) * 100 + 0.5) end,
		set = function(v)
			local s = THEME.shell
			if math.abs((s[4] or 1) - v / 100) < 0.001 then return end
			SetCustom("shell", { s[1], s[2], s[3], v / 100 })
		end,
	})

	local advancedShown = false
	local advanced
	local _, mainButtons = UI.ButtonRow(main, {
		{
			label = L("THEME_RESET"),
			tooltip = { L("THEME_RESET"), L("THEME_RESET_HELP") },
			onClick = function()
				local st = Saved()
				if not st.custom then return end
				st.custom.colors = Copy((PRESET_BY_ID[st.custom.base] or PRESETS[1]).colors)
				st.preset = "CUSTOM"
				UI.ApplyTheme(st.custom.colors)
				controller.Refresh()
			end,
		},
		{
			label = L("THEME_ADVANCED_SHOW"),
			onClick = function()
				advancedShown = not advancedShown
				stack:SetItemShown(advanced, advancedShown)
				controller.Refresh()
			end,
		},
	}, { gapBefore = 8 })

	-- ------------------------------------------------------ advanced colors
	advanced = UI.Card(stack, L("THEME_COLORS"))
	stack:SetItemShown(advanced, false)
	local token = "gold"
	local advEditing = UI.Info(advanced, "", { color = THEME.gold })
	Editor(advanced,
		function() return THEME[token] end,
		function(c) SetCustom(token, c) end,
		true)
	for _, section in ipairs(SECTIONS) do
		UI.Info(advanced, L(section.label), { color = THEME.textDim, gap = 10 })
		for _, t in ipairs(section.tokens) do
			PickRow(advanced, L("THEME_C_" .. t),
				function() return THEME[t] end,
				function() return token == t end,
				function() token = t end)
		end
	end

	local function PaintLabels()
		mainEditing:SetText(L("THEME_EDITING", L("THEME_G_" .. group.id)))
		advEditing:SetText(L("THEME_EDITING", L("THEME_C_" .. token)))
		mainButtons[2].text:SetText(L(advancedShown and "THEME_ADVANCED_HIDE" or "THEME_ADVANCED_SHOW"))
	end
	function controller.Refresh()
		PaintLabels()
		UI.Repaint()
	end
	UI.Register(PaintLabels)
	return controller
end

-- Full in-window Themes page. Menu.lua supplies a normal page frame; the
-- shared ScrollArea keeps both presets and advanced controls inside it.
function AL.BuildThemesPage(parent)
	local _, _, stack = UI.ScrollArea(parent, { pad = 14, padTop = 30, spacing = 8 })
	local controller = BuildThemeControls(parent, stack)
	parent.themeController = controller
	parent:HookScript("OnShow", function() controller.Refresh() end)
	return controller
end

-- Legacy slide-out entry point retained for compatibility. It uses the exact
-- same controls and state as the embedded Themes page.
function AL.BuildThemeDrawer(menu, toggleButton)
	local drawer = CreateFrame("Frame", nil, menu)
	drawer:SetWidth(DRAWER_W)
	drawer:SetFrameLevel(menu:GetFrameLevel() + 30)
	drawer:EnableMouse(true)
	UI.Fill(drawer, THEME.shell)
	UI.Border(drawer, UI.Derived.frameEdge)
	drawer:Hide()

	local function Place(dx)
		drawer:ClearAllPoints()
		drawer:SetPoint("TOPLEFT", menu, "TOPRIGHT", 4 - dx, 0)
		drawer:SetPoint("BOTTOMLEFT", menu, "BOTTOMRIGHT", 4 - dx, 0)
	end
	Place(0)

	local head = UI.Text(drawer, "GameFontNormal", THEME.gold)
	head:SetPoint("TOP", 0, -12)
	head:SetText(L("THEMES"))

	local _, _, stack = UI.ScrollArea(drawer, { pad = 10, padTop = 34, spacing = 8 })
	local controller = BuildThemeControls(drawer, stack)
	function drawer.Refresh() controller.Refresh() end

	-- ---------------------------------------------------------- animation
	local progress, target, duration = 0, 0, 0.18
	local anim = CreateFrame("Frame", nil, menu)
	anim:Hide()
	anim:SetScript("OnUpdate", function(self, dt)
		local step = dt / (target == 1 and duration or duration * 0.7)
		progress = target == 1 and math.min(1, progress + step) or math.max(0, progress - step)
		local e = 1 - (1 - progress) ^ 3
		Place(SLIDE * (1 - e))
		drawer:SetAlpha(e)
		if progress == target then
			self:Hide()
			if target == 0 then drawer:Hide() end
		end
	end)

	local function SetOpen(open)
		target = open and 1 or 0
		if open then
			drawer:Show()
			drawer.Refresh()
		end
		if toggleButton and toggleButton.SetOpen then toggleButton:SetOpen(open) end
		anim:Show()
	end

	function drawer.Toggle() SetOpen(target ~= 1) end
	function drawer.Close()
		if target == 1 then SetOpen(false) end
	end
	menu:HookScript("OnHide", function()
		target, progress = 0, 0
		anim:Hide()
		drawer:Hide()
		if toggleButton and toggleButton.SetOpen then toggleButton:SetOpen(false) end
	end)
	return drawer
end

-- Round header button: a swatch showing the current theme's colors.
function AL.ThemeButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(18, 18)
	local ring = b:CreateTexture(nil, "BACKGROUND")
	ring:SetAllPoints()
	ring:SetTexture(CIRCLE)
	local core = b:CreateTexture(nil, "ARTWORK")
	core:SetSize(12, 12)
	core:SetPoint("CENTER")
	core:SetTexture(CIRCLE)
	local dot = b:CreateTexture(nil, "OVERLAY")
	dot:SetSize(5, 5)
	dot:SetPoint("CENTER", 2, 2)
	dot:SetTexture(CIRCLE)

	local hover, open = false, false
	local function Paint()
		ring:SetVertexColor(UI.Color((hover or open) and THEME.gold or THEME.bronze))
		core:SetVertexColor(UI.Color(THEME.surfaceAlt))
		dot:SetVertexColor(UI.Color(THEME.gold))
	end
	function b:SetOpen(v)
		open = v and true or false
		Paint()
	end
	b:SetScript("OnEnter", function() hover = true Paint() end)
	b:SetScript("OnLeave", function() hover = false Paint() end)
	b:SetScript("OnMouseDown", function() core:SetSize(11, 11) end)
	b:SetScript("OnMouseUp", function() core:SetSize(12, 12) end)
	UI.Tooltip(b, L("THEME"), { L("THEME_HELP") })
	UI.Register(Paint)
	Paint()
	return b
end
