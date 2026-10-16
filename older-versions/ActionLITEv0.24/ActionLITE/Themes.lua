local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - Themes.lua
-- ----------------------------------------------------------------------------
-- Themes predefinis, theme personnalise enregistre, et tiroir d'edition qui
-- s'ouvre a droite de la fenetre d'options. Toute modification est appliquee
-- en direct via UI.ApplyTheme.
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

local PRESETS = {
	{ id = "ACTIONLITE", name = function() return "ActionLITE" end, colors = Copy(THEME) },
	{ id = "ARCANE", name = function() return L("THEME_ARCANE") end, colors = {
		shell = Hex("0c0a17", 0.97), sidebar = Hex("110e20"), surface = Hex("16132a"), surfaceAlt = Hex("1f1b3a"),
		raised = Hex("29244b"), line = Hex("342e5c"), lineSoft = Hex("ffffff", 0.06),
		bronze = Hex("7b5cff"), gold = Hex("b69cff"), goldDim = Hex("8a6ee0"), crimson = Hex("7a2350"),
		text = Hex("e8e4ff"), textDim = Hex("a59fcc"), textFaint = Hex("817bad"),
		ok = Hex("4fd1c5"), green = Hex("5eead4"), warn = Hex("f0b75a"), danger = Hex("ff5c8a"),
	} },
	{ id = "FROST", name = function() return L("THEME_FROST") end, colors = {
		shell = Hex("0a1016", 0.97), sidebar = Hex("0e1720"), surface = Hex("121e29"), surfaceAlt = Hex("182836"),
		raised = Hex("1f3344"), line = Hex("2a4256"), lineSoft = Hex("ffffff", 0.06),
		bronze = Hex("5fa8d3"), gold = Hex("9fe3ff"), goldDim = Hex("6cbfe6"), crimson = Hex("5a2a3a"),
		text = Hex("e6f4ff"), textDim = Hex("9db7c9"), textFaint = Hex("6f8b9f"),
		ok = Hex("58d6a8"), green = Hex("7ef0c0"), warn = Hex("ffd479"), danger = Hex("ff6b6b"),
	} },
	{ id = "FEL", name = function() return L("THEME_FEL") end, colors = {
		shell = Hex("070b06", 0.97), sidebar = Hex("0b1109"), surface = Hex("0f170c"), surfaceAlt = Hex("152012"),
		raised = Hex("1c2b17"), line = Hex("26391f"), lineSoft = Hex("ffffff", 0.05),
		bronze = Hex("5fae1f"), gold = Hex("a4ff3c"), goldDim = Hex("79d12a"), crimson = Hex("5c1f14"),
		text = Hex("e9f7dc"), textDim = Hex("a2b894"), textFaint = Hex("728866"),
		ok = Hex("7dff5a"), green = Hex("a4ff3c"), warn = Hex("ffc93c"), danger = Hex("ff5a3c"),
	} },
	{ id = "BLOOD", name = function() return L("THEME_BLOOD") end, colors = {
		shell = Hex("0d0708", 0.97), sidebar = Hex("140a0c"), surface = Hex("1a0e10"), surfaceAlt = Hex("241315"),
		raised = Hex("2e181b"), line = Hex("3d2024"), lineSoft = Hex("ffffff", 0.05),
		bronze = Hex("b3303a"), gold = Hex("ff5a5f"), goldDim = Hex("d0434a"), crimson = Hex("8f1d24"),
		text = Hex("f6e6e6"), textDim = Hex("c29a9c"), textFaint = Hex("9b7476"),
		ok = Hex("5fcf80"), green = Hex("7ae495"), warn = Hex("ffb347"), danger = Hex("ff4d4d"),
	} },
	{ id = "ROYAL", name = function() return L("THEME_ROYAL") end, colors = {
		shell = Hex("080c16", 0.97), sidebar = Hex("0c1220"), surface = Hex("10182a"), surfaceAlt = Hex("162136"),
		raised = Hex("1d2b45"), line = Hex("283a5c"), lineSoft = Hex("ffffff", 0.06),
		bronze = Hex("c9a227"), gold = Hex("ffd65a"), goldDim = Hex("d4b04a"), crimson = Hex("6b1f2a"),
		text = Hex("eef2ff"), textDim = Hex("a3b0cc"), textFaint = Hex("7583a0"),
		ok = Hex("4fd18b"), green = Hex("6ee7a0"), warn = Hex("ffc857"), danger = Hex("ff6363"),
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
	end },
	{ id = "text", base = "text", apply = function(c, set)
		set("text", c)
		set("textDim", Mul(c, 0.68))
		set("textFaint", Mul(c, 0.55))
	end },
	{ id = "positive", base = "ok", apply = function(c, set)
		set("ok", c)
		set("green", Lift(c, 0.06))
	end },
	{ id = "warning", base = "warn", apply = function(c, set) set("warn", c) end },
	{ id = "danger", base = "danger", apply = function(c, set)
		set("danger", c)
		set("crimson", Mul(c, 0.66))
	end },
}

local PRESET_BY_ID = {}
for _, p in ipairs(PRESETS) do PRESET_BY_ID[p.id] = p end

-- --------------------------------------------------------------------------
-- Persistance : meme double copie que la langue (voir Localization.lua).
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

-- Premier changement de couleur : le theme courant devient le theme perso.
local function EnsureCustom()
	local st = Saved()
	if st.preset ~= "CUSTOM" or not st.custom then
		st.custom = { base = st.preset ~= "CUSTOM" and st.preset or "ACTIONLITE", colors = Copy(THEME) }
		st.preset = "CUSTOM"
	end
	return st.custom
end

-- --------------------------------------------------------------------------
-- Tiroir
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
			drawer.Refresh()
		end)
		st:Add(row, 24)
		UI.Register(function() row:Paint() end)
		presetRows[#presetRows + 1] = row
		return row
	end

	for _, p in ipairs(PRESETS) do PresetRow(p.id, p.name(), p.colors) end
	PresetRow("CUSTOM", L("THEME_CUSTOM"), nil)
	UI.Info(presetCard, L("THEME_CUSTOM_HELP"), { color = THEME.textFaint })

	-- Une seule mise a jour par image, meme si plusieurs curseurs bougent.
	local dirty = false
	drawer:SetScript("OnUpdate", function()
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
			drawer.Refresh()
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
				drawer.Refresh()
			end,
		},
		{
			label = L("THEME_ADVANCED_SHOW"),
			onClick = function()
				advancedShown = not advancedShown
				stack:SetItemShown(advanced, advancedShown)
				drawer.Refresh()
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
	function drawer.Refresh()
		PaintLabels()
		UI.Repaint()
	end
	UI.Register(PaintLabels)

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

-- Bouton rond de l'en-tete : pastille aux couleurs du theme courant.
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
