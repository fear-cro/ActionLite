local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - Menu.lua - v0.6.11
-- ----------------------------------------------------------------------------
-- Fenetre principale, disposition compacte a onglets horizontaux, taille libre
-- (poignee en bas a droite) et echelle independante (curseur General) :
--
--   +--------------------------------------------------------------+
--   | Session 0:12:44        ActionLITE           Guerrier  v0.6.1 X|
--   | [ profil de classe v ]                                       |
--   | | General | Guerrier | Sorts |                                 |
--   +--------------------------------------------------------------+
--   |                          General                              |
--   |                          AFFICHAGE                            |
--   |   Nom du reglage (50 % - 200 %)                    100 %      |
--   |   [=============O--------------------------]                  |
--   |   [x] Option a gauche             [ ] Option a droite         |
--   +--------------------------------------------------------------+
--   | v0.6.1 - composants UI 0.6.1          /action  /al            |
--   +--------------------------------------------------------------+
--
-- Contrat avec les fichiers <Class>_UI.lua :
--   AL.RegisterClassUI(token, builder, version)
--   builder(panel, ui) est appele une seule fois, a la construction du menu.
--   "panel" remplit la page de classe ; "ui" expose les composants partages :
--
--     ui.Body(panel)                 -> pile defilable prete a l'emploi
--     ui.Card(host, titre, soustitre)-> section titree
--     ui.Check(host, opts)           -> case a cocher compacte (opts.half)
--     ui.SettingCheck(host, cle, o)  -> case liee au profil selectionne
--     ui.Toggle(host, opts)          -> interrupteur, pour les bascules fortes
--     ui.Slider / ui.Button / ui.ButtonRow / ui.Dropdown / ui.StackDropdown
--     ui.Badge / ui.BadgeRow / ui.Info / ui.Divider / ui.Tooltip / ui.Tabs
--     ui.Paint(fn)                   -> enregistre un rafraichissement
--     ui.SpellIcon(nom)              -> texture d'un sort
--     ui.Profile()                   -> profil en cours d'edition (AL.ES)
--     ui.Theme / ui.Grid / ui.Version
--
--   Toute option passee avec half = true occupe une demi-largeur et se met
--   automatiquement en paire avec la suivante : c'est ainsi qu'on obtient les
--   grilles a deux colonnes sans la moindre coordonnee en dur.
--
--   L'API historique (Section, Check positionnee, SettingCheck, Card, InfoText,
--   Dropdown) reste disponible pour les modules qui exposent encore
--   mod.BuildOptions ; elle est simplement repeinte au nouveau theme.
-- ============================================================================

local UI = AL.UI
local L = AL.L
local THEME = UI.Theme
local GRID = UI.GRID

local W, H = 660, 670
local MIN_W, MIN_H = 560, 450
local MAX_W, MAX_H = 1200, 1000
local HEADER_H, FOOTER_H = 88, 22

local menu
local menuSerial = 0
local pages, classPanels = {}, {}
local tabStrip
local sessionStart = GetTime()

local function ActiveToken()
	return (ActionLiteDB and ActionLiteDB.activeProfile) or AL.playerClass
end

-- Reglages d'affichage et conditions de pause : le moteur les lit toujours sur
-- le profil de la classe jouee (AL.S). On edite donc ce profil-la, afin que
-- chaque controle de la page General soit reellement connecte.
local function S() return AL.S() end
-- Options de rotation : profil selectionne dans l'en-tete.
local function ES() return AL.ES() end

local function ClassUIVersion(token)
	local v = AL.classUIVersions and AL.classUIVersions[token]
	if v then return "|cff6fcf82UI " .. v .. "|r" end
	local mod = AL.rotations and AL.rotations[token]
	if mod and mod.BuildOptions then return "|cff8a92a1" .. L("CLASSIC") .. "|r" end
	return "|cffbf5c5c" .. L("NO_UI") .. "|r"
end

local function SessionText()
	local t = math.floor(GetTime() - sessionStart)
	if t < 0 then t = 0 end
	return (L("SESSION") .. " %d:%02d:%02d"):format(
		math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
end

-- ----------------------------------------------------------------------------
-- Macros
-- ----------------------------------------------------------------------------
local function OpenMacroWindow()
	if ShowMacroFrame then
		pcall(ShowMacroFrame)
		return
	end
	if UIParentLoadAddOn then pcall(UIParentLoadAddOn, "Blizzard_MacroUI") end
	if MacroFrame and ShowUIPanel then ShowUIPanel(MacroFrame) end
end

-- les noms de macro sont limites a 16 caracteres
local function SpellMacroName(spell)
	return ("AL" .. spell:gsub("[%s:'%-]", "")):sub(1, 16)
end

local function CreateSpellMacro(spell)
	if InCombatLockdown and InCombatLockdown() then
		AL.Say(L("MACRO_COMBAT"))
		return
	end
	local mname = SpellMacroName(spell)
	if GetMacroInfo and GetMacroInfo(mname) then
		AL.Say(L("MACRO_EXISTS", mname))
		return
	end
	local icon = AL.SpellTexture(spell) or "INV_MISC_QUESTIONMARK"
	local body = "#showtooltip " .. spell .. "\n/run ActionLite_Queue(\"" .. spell .. "\")"
	local ok = pcall(CreateMacro, mname, icon, body, false)
	if not ok then
		-- certains clients n'acceptent ici que le jeton point d'interrogation
		ok = pcall(CreateMacro, mname, "INV_MISC_QUESTIONMARK", body, false)
	end
	if ok then
		print("|cff89cff0[ActionLITE]|r " .. L("MACRO_CREATED", mname) .. " = queue(" .. spell .. ")")
		OpenMacroWindow()
	else
		AL.Say(L("MACRO_FAILED"))
	end
end

local function CreateBurstMacro()
	if InCombatLockdown and InCombatLockdown() then
		AL.Say(L("MACRO_COMBAT"))
		return
	end
	if GetMacroInfo and GetMacroInfo("ALBurst") then
		AL.Say(L("MACRO_EXISTS", "ALBurst"))
		return
	end
	local ok = pcall(CreateMacro, "ALBurst", "INV_MISC_QUESTIONMARK", "/run ActionLite_Burst()", false)
	if ok then
		AL.Say(L("BURST_MACRO_CREATED"))
		OpenMacroWindow()
	else
		AL.Say(L("MACRO_FAILED"))
	end
end

-- ----------------------------------------------------------------------------
-- Echelle de la fenetre : le coin haut-gauche reste en place.
-- ----------------------------------------------------------------------------
function AL.MenuScale(scale)
	scale = math.max(0.7, math.min(1.5, tonumber(scale) or 1))
	ActionLiteDB = ActionLiteDB or {}
	ActionLiteDB.menuScale = scale
	if not menu then return end
	if not menu:IsShown() or not menu:GetLeft() then
		menu:SetScale(scale)
		return
	end
	local es = menu:GetEffectiveScale()
	local leftPx, topPx = menu:GetLeft() * es, menu:GetTop() * es
	menu:SetScale(scale)
	es = menu:GetEffectiveScale()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftPx / es, topPx / es)
end

function AL.ResetMenuSize()
	ActionLiteDB = ActionLiteDB or {}
	ActionLiteDB.menuSize = nil
	if menu then menu:SetSize(W, H) end
end

-- ----------------------------------------------------------------------------
-- Reinitialisation
-- ----------------------------------------------------------------------------
local DISPLAY_KEYS = { "scale", "bgAlpha", "nobg", "norange", "noprint" }

local function ResetSettings()
	local token = ActiveToken()
	local edited = ES()
	wipe(edited)
	AL.FillDefaults(edited, token)

	-- si l'on editait un autre profil, on remet quand meme l'affichage du
	-- profil reellement utilise par le moteur dans son etat par defaut
	local live = S()
	if live ~= edited then
		for _, k in ipairs(DISPLAY_KEYS) do live[k] = AL.defaults[k] end
	end

	ActionLiteDB.locked = false
	ActionLiteDB.hidden = false
	ActionLiteDB.togglesHidden = false
	ActionLiteDB.castTrailOn = true
	ActionLiteDB.castTrailLocked = true
	ActionLiteDB.castTrailScale = 1
	ActionLiteDB.castTrailPosition = nil
	ActionLiteDB.mmHidden = false
	ActionLiteDB.glowHidden = false
	ActionLiteDB.glowPulse = false
	ActionLiteDB.trainHidden = false
	ActionLiteDB.menuScale = 1
	ActionLiteDB.menuSize = nil

	if AL.ResetIconPosition then AL.ResetIconPosition() end
	if AL.frame then AL.frame:Show() end
	AL.ApplyStyle()
	AL.ApplyLock()
	if AL.ApplyMini then AL.ApplyMini() end
	if AL.ResetCastTrail then AL.ResetCastTrail() end
	if AL.ApplyMinimapButton then AL.ApplyMinimapButton() end
	if AL.RefreshGlow then AL.RefreshGlow() end
	AL.MenuScale(1)
	if AL.ResetMenuSize then AL.ResetMenuSize() end
	UI.Repaint()
	AL.Say(L("SETTINGS_RESET"))
end

-- ============================================================================
-- Construction
-- ============================================================================
local function RecordUI(name, detail)
	local debug = AL.ActionLiteDebug
	if debug and debug.RecordUI then pcall(debug.RecordUI, name, detail) end
end

local function BuildMenu()
	AL.FillDBDefaults()
	if AL.ActionLiteDebug and AL.ActionLiteDebug.ClearControls then AL.ActionLiteDebug.ClearControls() end
	if AL.LoadTheme then AL.LoadTheme() end

	menuSerial = menuSerial + 1
	local menuName = "ActionLiteMenu" .. menuSerial
	menu = CreateFrame("Frame", menuName, UIParent)
	menu:Hide()
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:SetMovable(true)
	menu:RegisterForDrag("LeftButton")
	menu:SetScale(ActionLiteDB.menuScale or 1)

	-- Taille libre : l'echelle grossit tout, le redimensionnement donne de la
	-- place sans toucher a la taille du texte. Les deux sont independants.
	menu:SetResizable(true)
	local size = ActionLiteDB.menuSize
	menu:SetSize(
		math.max(MIN_W, math.min(MAX_W, (size and size[1]) or W)),
		math.max(MIN_H, math.min(MAX_H, (size and size[2]) or H)))
	-- SetResizeBounds est recent ; SetMinResize/SetMaxResize couvrent 1.60
	if not pcall(menu.SetResizeBounds, menu, MIN_W, MIN_H, MAX_W, MAX_H) then
		pcall(menu.SetMinResize, menu, MIN_W, MIN_H)
		pcall(menu.SetMaxResize, menu, MAX_W, MAX_H)
	end
	UI.Fill(menu, THEME.shell)
	-- double liseret : or a l'exterieur, acier a l'interieur
	UI.Border(menu, UI.Derived.frameEdge)
	local inner = CreateFrame("Frame", nil, menu)
	inner:SetPoint("TOPLEFT", 1, -1)
	inner:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Border(inner, { 0, 0, 0, 0.9 })
	tinsert(UISpecialFrames, menuName)

	-- ------------------------------------------------------------------ header
	local header = CreateFrame("Frame", nil, menu)
	header:SetPoint("TOPLEFT", 2, -2)
	header:SetPoint("TOPRIGHT", -2, -2)
	header:SetHeight(HEADER_H)
	UI.Fill(header, THEME.sidebar)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() menu:StartMoving() end)

	local headerLine = header:CreateTexture(nil, "OVERLAY")
	headerLine:SetHeight(1)
	headerLine:SetPoint("BOTTOMLEFT")
	headerLine:SetPoint("BOTTOMRIGHT")
	UI.Tint(headerLine, THEME.bronze, 0.55)

	-- ligne 1 : session, titre, profil, version, fermeture
	local sessionText = UI.Text(header, "GameFontNormalSmall", THEME.textFaint)
	sessionText:SetPoint("TOPLEFT", 12, -9)

	local title = UI.Text(header, "GameFontNormalLarge", THEME.gold)
	title:SetPoint("TOP", 0, -6)
	local function PaintTitle()
		local g = THEME.gold
		title:SetText("|c" .. UI.Hex({ g[1] * 0.9, g[2] * 0.9, g[3] * 0.9 }) .. "Action|r|c" .. UI.Hex(g) .. "LITE|r")
	end
	PaintTitle()
	UI.Register(PaintTitle)

	local close = CreateFrame("Button", nil, header)
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", -8, -7)
	local closeBg = UI.Fill(close, UI.Derived.closeBg)
	local closeEdge = UI.Border(close, THEME.crimson)
	local closeX = UI.Text(close, "GameFontNormalSmall", THEME.text)
	closeX:SetPoint("CENTER", 0, 0)
	closeX:SetText("X")
	close:SetScript("OnEnter", function()
		closeBg:SetColorTexture(UI.Color(THEME.danger))
		closeEdge:SetColor(1, 0.6, 0.6, 1)
	end)
	close:SetScript("OnLeave", function()
		closeBg:SetColorTexture(UI.Color(UI.Derived.closeBg))
		closeEdge:SetColor(UI.Color(THEME.crimson))
	end)
	close:SetScript("OnClick", function() menu.AnimateClose() end)

	local themeButton = AL.ThemeButton(header)
	themeButton:SetPoint("RIGHT", close, "LEFT", -6, 0)
	local themeDrawer = AL.BuildThemeDrawer(menu, themeButton)
	themeButton:SetScript("OnClick", function() themeDrawer.Toggle() end)

	local headerLeftOf = themeButton
	if AL.DebugButton then
		local debugButton = AL.DebugButton(header)
		debugButton:SetPoint("RIGHT", themeButton, "LEFT", -6, 0)
		headerLeftOf = debugButton
	end

	local profileText = UI.Text(header, "GameFontNormalSmall", THEME.text)
	profileText:SetPoint("TOPRIGHT", headerLeftOf, "TOPLEFT", -8, -1)
	profileText:SetJustifyH("RIGHT")

	local versionText = UI.Text(header, "GameFontNormalSmall", THEME.textFaint)
	versionText:SetPoint("TOPRIGHT", headerLeftOf, "TOPLEFT", -8, -15)
	versionText:SetJustifyH("RIGHT")
	versionText:SetText("v" .. AL.Version())

	-- ligne 2 : selecteur de profil ; les pastilles d'etat suivent les onglets
	local ddOptions = {}
	for i, token in ipairs(AL.CLASS_TOKENS) do
		ddOptions[i] = {
			label = UI.ClassColored(token),
			value = token,
			icon = function(tex) AL.SetClassIcon(tex, token) end,
			right = function() return ClassUIVersion(token) end,
		}
	end
	local classDD = UI.Dropdown(header, {
		width = 176,
		height = 20,
		align = "LEFT",
		options = ddOptions,
		get = ActiveToken,
		set = function(v) ActionLiteDB.activeProfile = v end,
		onSelect = function()
			if menu.RebuildSpells then menu.RebuildSpells() end
		end,
	})
	classDD:SetPoint("TOPLEFT", 10, -40)
	UI.Tooltip(classDD, L("CLASS_PROFILE"), { L("CLASS_PROFILE_1"), L("CLASS_PROFILE_2") })

	local function UpdateStatus()
		sessionText:SetText(SessionText())
	end
	UI.Register(UpdateStatus)

	-- ligne 3 : onglets horizontaux
	local function ShowPage(i)
		if i ~= 1 and i ~= 2 and i ~= 3 and i ~= 4 then i = 1 end
		for n, p in ipairs(pages) do p:SetShown(n == i) end
		if tabStrip then tabStrip:SetActive(i) end
		ActionLiteDB.lastTab = i
		if i == 3 and menu.RebuildSpells then menu.RebuildSpells() end
	end
	menu.ShowPage = ShowPage

	tabStrip = UI.Tabs(header, {
		{ label = L("GENERAL"), onClick = function() ShowPage(1) end },
		{ label = L("CLASS"),   onClick = function() ShowPage(2) end },
		{ label = L("SPELLS"),  onClick = function() ShowPage(3) end },
		{ label = L("BUG_REPORT"), onClick = function() ShowPage(4) end },
	}, { minWidth = 86 })
	tabStrip:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 0)
	tabStrip:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 0)

	local function NewPage(index, caption)
		local page = CreateFrame("Frame", nil, menu)
		page:SetPoint("TOPLEFT", 2, -(HEADER_H + 2))
		page:SetPoint("BOTTOMRIGHT", -2, FOOTER_H + 2)
		page:Hide()
		local cap = UI.Text(page, "GameFontNormal", THEME.gold)
		cap:SetPoint("TOP", 0, -8)
		cap:SetText(caption or "")
		page.caption = cap
		pages[index] = page
		return page
	end

	local generalPage = NewPage(1, L("GENERAL"))
	local classPage = NewPage(2, L("CLASS"))
	local spellsPage = NewPage(3, L("SPELLS"))
	local bugReportPage = NewPage(4, L("BUG_REPORT"))

	-- ------------------------------------------------------------------ footer
	local footer = CreateFrame("Frame", nil, menu)
	footer:SetPoint("BOTTOMLEFT", 2, 2)
	footer:SetPoint("BOTTOMRIGHT", -2, 2)
	footer:SetHeight(FOOTER_H)
	UI.Fill(footer, THEME.sidebar)
	local footerLine = footer:CreateTexture(nil, "OVERLAY")
	footerLine:SetHeight(1)
	footerLine:SetPoint("TOPLEFT")
	footerLine:SetPoint("TOPRIGHT")
	UI.Tint(footerLine, THEME.line)

	local footerLeft = UI.Text(footer, "GameFontNormalSmall", THEME.textFaint)
	footerLeft:SetPoint("LEFT", 12, 0)
	footerLeft:SetText("v" .. AL.Version() .. "  -  " .. L("UI_COMPONENTS") .. " " .. UI.VERSION)

	local footerRight = UI.Text(footer, "GameFontNormalSmall", THEME.textFaint)
	footerRight:SetPoint("RIGHT", -26, 0)
	footerRight:SetText("/action   /al   /actionlite")

	-- ------------------------------------------------------ poignee de taille
	local grip = CreateFrame("Button", nil, menu)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(menu:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	UI.Tooltip(grip, L("WINDOW_SIZE"), { L("WINDOW_SIZE_1"), L("WINDOW_SIZE_2") })

	local sizing = false
	local function StopSizing()
		if not sizing then return end
		sizing = false
		menu:StopMovingOrSizing()
		ActionLiteDB.menuSize = { menu:GetWidth(), menu:GetHeight() }
		local point, _, relPoint, x, y = menu:GetPoint()
		if point then ActionLiteDB.menuPos = { point, relPoint, x, y } end
		-- la liste des sorts se repose sur sa propre hauteur de contenu
		if menu.RebuildSpells then menu.RebuildSpells() end
	end
	grip:SetScript("OnMouseDown", function()
		sizing = true
		menu:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", StopSizing)
	grip:SetScript("OnHide", StopSizing)

	-- --------------------------------------------------------------- animations
	local openAnim = menu:CreateAnimationGroup()
	local openFade = openAnim:CreateAnimation("Alpha")
	openFade:SetFromAlpha(0)
	openFade:SetToAlpha(1)
	openFade:SetDuration(0.14)
	openFade:SetSmoothing("OUT")

	local closeAnim = menu:CreateAnimationGroup()
	local closeFade = closeAnim:CreateAnimation("Alpha")
	closeFade:SetFromAlpha(1)
	closeFade:SetToAlpha(0)
	closeFade:SetDuration(0.10)
	closeFade:SetSmoothing("OUT")
	closeAnim:SetScript("OnFinished", function()
		menu:Hide()
		menu:SetAlpha(1)
	end)

	function menu.AnimateOpen()
		closeAnim:Stop()
		menu:Show()
		openAnim:Play()
	end

	function menu.AnimateClose()
		if closeAnim:IsPlaying() then return end
		openAnim:Stop()
		closeAnim:Play()
	end

	-- ========================================================================
	-- API composants exposee aux pages de classe
	-- ========================================================================
	local function SettingCheck(host, key, opts)
		opts = opts or {}
		return UI.Check(host, {
			profileKey = key,
			label = opts.label or key,
			desc = opts.desc,
			icon = opts.icon,
			tooltip = opts.tooltip,
			half = opts.half,
			get = function() return ES()[key] end,
			set = function(v) ES()[key] = v end,
			onChange = opts.onChange,
		})
	end

	local function LiveCheck(host, key, opts)
		opts = opts or {}
		return UI.Check(host, {
			profileKey = key,
			label = opts.label or key,
			desc = opts.desc,
			tooltip = opts.tooltip,
			half = opts.half ~= false,
			get = function() return S()[key] end,
			set = function(v) S()[key] = v end,
			onChange = opts.onChange,
		})
	end

	local function InvertedDBCheck(host, key, opts)
		return UI.Check(host, {
			label = opts.label,
			desc = opts.desc,
			tooltip = opts.tooltip,
			half = opts.half ~= false,
			get = function() return not ActionLiteDB[key] end,
			set = function(v) ActionLiteDB[key] = not v end,
			onChange = opts.onChange,
		})
	end

	local function InvertedProfileCheck(host, key, opts)
		return UI.Check(host, {
			label = opts.label,
			desc = opts.desc,
			tooltip = opts.tooltip,
			half = opts.half ~= false,
			get = function() return not S()[key] end,
			set = function(v) S()[key] = not v end,
			onChange = opts.onChange,
		})
	end

	local ui = {
		Version       = UI.VERSION,
		Theme         = THEME,
		Grid          = GRID,
		Body          = function(panel, opts)
			opts = opts or {}
			if opts.padTop == nil then opts.padTop = 30 end
			local scroll = UI.ScrollArea(panel, opts)
			return scroll.stack, scroll
		end,
		Card          = UI.Card,
		Check         = UI.Check,
		SettingCheck  = SettingCheck,
		-- noms de la 0.6.0 conserves pour ne casser aucune page deja ecrite
		Toggle        = UI.Check,
		SettingToggle = SettingCheck,
		Switch        = UI.Toggle,
		Slider        = UI.Slider,
		Button        = UI.Button,
		ButtonRow     = UI.ButtonRow,
		Dropdown      = UI.Dropdown,
		StackDropdown = UI.StackDropdown,
		Tabs          = UI.Tabs,
		Badge         = UI.Badge,
		BadgeRow      = UI.BadgeRow,
		Info          = UI.Info,
		Divider       = UI.Divider,
		Tooltip       = UI.Tooltip,
		Paint         = UI.Register,
		Repaint       = UI.Repaint,
		SpellIcon     = UI.SpellIcon,
		Profile       = ES,
		ClassColor    = UI.ClassColor,
		ClassName     = UI.ClassName,
	}

	-- ------------------------------------------------------------------------
	-- API historique pour les modules qui exposent encore mod.BuildOptions.
	-- Memes signatures qu'en 0.5.x, habillage 0.6.1.
	-- ------------------------------------------------------------------------
	local function LegacyCheck(parent, x, y, label, get, set)
		local cb = CreateFrame("Button", nil, parent)
		cb:SetSize(210, 22)
		cb:SetPoint("TOPLEFT", x, y)
		local box = CreateFrame("Frame", nil, cb)
		box:SetSize(14, 14)
		box:SetPoint("LEFT", 0, 0)
		local boxBg = UI.Fill(box, THEME.raised)
		local edge = UI.Border(box, THEME.line)
		local mark = box:CreateTexture(nil, "OVERLAY")
		mark:SetSize(16, 16)
		mark:SetPoint("CENTER")
		mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		UI.TintVertex(mark, THEME.gold)
		local t = UI.Text(cb, "GameFontHighlightSmall", THEME.text)
		t:SetPoint("LEFT", box, "RIGHT", 8, 0)
		t:SetText(label)
		local function Paint()
			local on = get() and true or false
			mark:SetShown(on)
			boxBg:SetColorTexture(UI.Color(on and UI.Derived.checkOn or THEME.raised))
			t:SetTextColor(UI.Color(on and THEME.text or THEME.textDim))
		end
		cb:SetScript("OnClick", function()
			set(not get())
			Paint()
			RecordUI("Class checkbox changed", { class = ActiveToken(), label = label, value = get() })
		end)
		cb:SetScript("OnEnter", function() edge:SetColor(UI.Color(THEME.gold)) end)
		cb:SetScript("OnLeave", function() edge:SetColor(UI.Color(THEME.line)) end)
		UI.Register(Paint)
		Paint()
		return cb
	end

	local legacyUI
	legacyUI = {
		Theme = THEME,
		Paint = UI.Register,
		Check = LegacyCheck,
		SettingCheck = function(parent, x, y, label, key, onChange)
			return LegacyCheck(parent, x, y, label,
				function() return ES()[key] end,
				function(v)
					ES()[key] = v
					if onChange then onChange() end
				end)
		end,
		Section = function(parent, y, text)
			local h = UI.Text(parent, "GameFontNormal", THEME.gold)
			h:SetPoint("TOP", 0, y)
			h:SetText(tostring(text))
			return h
		end,
		InfoText = function(parent, x, y, text, template)
			local l = UI.Text(parent, template or "GameFontHighlightSmall", THEME.textDim)
			l:SetPoint("TOPLEFT", x, y)
			l:SetText(text or "")
			return l
		end,
		Card = function(parent, x, y, width, height, titleText)
			local card = CreateFrame("Frame", nil, parent)
			card:SetSize(width, height)
			card:SetPoint("TOPLEFT", x, y)
			UI.Fill(card, THEME.surface)
			UI.Border(card, THEME.line)
			local head = UI.Text(card, "GameFontNormalSmall", THEME.gold)
			head:SetPoint("TOP", 0, -8)
			head:SetText(tostring(titleText or ""))
			return card
		end,
		Dropdown = function(parent, y, width, options, get, set)
			local converted = {}
			for i, opt in ipairs(options) do
				converted[i] = { label = opt[1], value = opt[2] }
			end
			local dd = UI.Dropdown(parent, {
				width = width, options = converted, get = get, set = set,
			})
			dd:SetPoint("TOP", 0, y)
			return dd
		end,
	}

	-- ========================================================================
	-- Page 1 : General
	-- ========================================================================
	do
		local _, _, stack = UI.ScrollArea(generalPage, { padTop = 30 })
		local currentLanguage = AL.GetUILanguage()
		local languageNames, languageOptions = {}, {}
		for i, def in ipairs(AL.UI_LANGUAGES) do
			languageNames[def.code] = def.name
			languageOptions[i] = { label = def.name, value = def.code }
		end

		local language = UI.Card(stack, L("LANGUAGE"))
		UI.StackDropdown(language, {
			caption = L("INTERFACE_LANGUAGE"),
			options = languageOptions,
			get = AL.GetUILanguage,
			onSelect = function(code)
				if code == currentLanguage then return end
				local saved = AL.SetUILanguage(code)
				AL.Say(L("LANGUAGE_SAVED", languageNames[saved], saved))
				if AL.RebuildMenu then AL.RebuildMenu() end
			end,
		})
		UI.Info(language, L("LANGUAGE_HELP"))

		local actions = UI.Card(stack, L("ACTIONS"))
		UI.ButtonRow(actions, {
			{
				label = L("CENTER_ICON"),
				onClick = function()
					if AL.ResetIconPosition then AL.ResetIconPosition() end
					AL.Say(L("ICON_POSITION_RESET"))
				end,
				tooltip = { L("CENTER_ICON"), L("CENTER_ICON_HELP") },
			},
			{
				label = L("DEFAULT_SIZE"),
				onClick = function()
					AL.ResetMenuSize()
					AL.Say(L("WINDOW_RESTORED", W, H))
				end,
				tooltip = { L("DEFAULT_SIZE"), L("DEFAULT_SIZE_HELP") },
			},
			{
				label = L("CREATE_BURST"),
				variant = "primary",
				onClick = CreateBurstMacro,
				tooltip = { L("CREATE_BURST"), L("CREATE_BURST_HELP") },
			},
		})
		UI.Info(actions, L("BURST_INFO"))
		UI.Divider(actions)
		UI.ButtonRow(actions, {
			{
				label = L("RESET_SETTINGS"),
				variant = "danger",
				onClick = function()
					UI.Confirm({
						parent = menu,
						title = L("RESET_SETTINGS"),
						text = L("RESET_WARNING"),
						accept = L("RESET"),
						onAccept = ResetSettings,
					})
				end,
			},
		})

		local pause = UI.Card(stack, L("PAUSE_CONDITIONS"), L("PAUSE_HELP"))
		LiveCheck(pause, "p_targeting", { label = L("PAUSE_TARGETING") })
		LiveCheck(pause, "p_vehicle", { label = L("PAUSE_VEHICLE") })
		LiveCheck(pause, "p_mounted", { label = L("PAUSE_MOUNTED") })
		LiveCheck(pause, "p_ooc", { label = L("PAUSE_OOC") })
		LiveCheck(pause, "p_loot", { label = L("PAUSE_LOOT") })
		LiveCheck(pause, "p_dead", { label = L("PAUSE_DEAD") })
		LiveCheck(pause, "p_targetdead", { label = L("PAUSE_TARGET_DEAD") })
		LiveCheck(pause, "p_eating", { label = L("PAUSE_EATING") })

		local display = UI.Card(stack, L("DISPLAY"))

		UI.Slider(display, {
			label = L("MAIN_ICON_SCALE"), min = 50, max = 200, step = 5, suffix = " %",
			get = function() return (S().scale or 1) * 100 end,
			set = function(v)
				S().scale = v / 100
				AL.ApplyStyle()
			end,
			tooltip = { L("MAIN_ICON_SCALE"), L("MAIN_ICON_SCALE_HELP") },
		})

		UI.Slider(display, {
			label = L("WINDOW_SCALE"), min = 70, max = 150, step = 5, suffix = " %",
			deferred = true,
			get = function() return (ActionLiteDB.menuScale or 1) * 100 end,
			set = function(v) AL.MenuScale(v / 100) end,
			tooltip = { L("WINDOW_SCALE"), L("WINDOW_SCALE_HELP") },
		})

		UI.Slider(display, {
			label = L("ICON_BG_OPACITY"), min = 0, max = 100, step = 5, suffix = " %",
			get = function() return (S().bgAlpha or 0.75) * 100 end,
			set = function(v)
				S().bgAlpha = v / 100
				AL.ApplyStyle()
			end,
		})



		UI.Divider(display)

		InvertedDBCheck(display, "hidden", {
			label = L("SHOW_MAIN_ICON"),
			onChange = function()
				if AL.frame then AL.frame:SetShown(not ActionLiteDB.hidden) end
			end,
		})
		UI.Check(display, {
			label = L("LOCK_POSITION"),
			half = true,
			tooltip = { L("LOCK_POSITION"), L("LOCK_POSITION_HELP") },
			get = function() return ActionLiteDB.locked end,
			set = function(v) ActionLiteDB.locked = v end,
			onChange = function()
				AL.ApplyLock()
				UI.Repaint()
			end,
		})
		InvertedProfileCheck(display, "nobg", {
			label = L("SHOW_ICON_BG"),
			onChange = AL.ApplyStyle,
		})
		UI.Check(display, {
			label = L("HIDE_TOGGLE_BOXES"),
			half = false,
			tooltip = { L("HIDE_TOGGLE_BOXES"), L("HIDE_TOGGLE_BOXES_HELP") },
			get = function() return ActionLiteDB.togglesHidden == true end,
			set = function(value) ActionLiteDB.togglesHidden = value end,
			onChange = function()
				if AL.ApplyToggles then AL.ApplyToggles() end
				UI.Repaint()
			end,
		})
		UI.Check(display, {
			label = L("CAST_TRAIL_ON"),
			half = true,
			tooltip = { L("CAST_TRAIL_ON"), L("CAST_TRAIL_ON_HELP") },
			get = function() return ActionLiteDB.castTrailOn end,
			set = function(value) ActionLiteDB.castTrailOn = value end,
			onChange = function()
				if AL.ApplyCastTrail then AL.ApplyCastTrail() end
				UI.Repaint()
			end,
		})
		UI.Check(display, {
			label = L("LOCK_CAST_TRAIL"),
			half = true,
			tooltip = { L("LOCK_CAST_TRAIL"), L("LOCK_CAST_TRAIL_HELP") },
			get = function() return ActionLiteDB.castTrailLocked end,
			set = function(value) ActionLiteDB.castTrailLocked = value end,
			onChange = function()
				if AL.ApplyCastTrail then AL.ApplyCastTrail() end
				UI.Repaint()
			end,
		})
		InvertedDBCheck(display, "mmHidden", {
			label = L("SHOW_MINIMAP"),
			onChange = function() if AL.ApplyMinimapButton then AL.ApplyMinimapButton() end end,
		})
		InvertedProfileCheck(display, "norange", {
			label = L("RANGE_TINT"),
			tooltip = { L("RANGE_TINT"), L("RANGE_TINT_HELP") },
		})
		InvertedDBCheck(display, "glowHidden", {
			label = L("SHOW_BAR_GLOW"),
			tooltip = { L("SHOW_BAR_GLOW"), L("BAR_GLOW_HELP") },
			onChange = AL.RefreshGlow,
		})
		UI.Check(display, {
			label = L("BAR_GLOW_PULSE"),
			half = true,
			get = function() return ActionLiteDB.glowPulse end,
			set = function(v) ActionLiteDB.glowPulse = v end,
			onChange = AL.RefreshGlow,
		})
		InvertedProfileCheck(display, "noprint", {
			label = L("CHAT_MESSAGES"),
		})
		InvertedDBCheck(display, "trainHidden", {
			label = L("TRAIN_REMINDER"),
			tooltip = { L("TRAIN_REMINDER"), L("TRAIN_REMINDER_HELP") },
		})
		UI.Check(display, {
			label = L("SHOW_SWING_TIMER"),
			half = true,
			tooltip = { L("SHOW_SWING_TIMER"), L("SWING_TIMER_HELP") },
			get = function() return AL.SwingEnabled() end,
			set = function(v) S().swingBar = v end,
		})
	end

	-- Guided, copy/paste-only issue capture.
	do
		local _, _, stack = UI.ScrollArea(bugReportPage, { padTop = 30 })
		local card = UI.Card(stack, L("BUG_REPORT_GUIDE"), "ActionLiteDebug")
		for _, key in ipairs({ "BUG_REPORT_STEP_1", "BUG_REPORT_STEP_2", "BUG_REPORT_STEP_3", "BUG_REPORT_STEP_4" }) do
			UI.Info(card, L(key), { height = 30 })
		end
		UI.ButtonRow(card, {{
			label = L("OPEN_DEBUGGER"), variant = "primary", width = 170,
			onClick = function()
				if AL.OpenActionLiteDebug then AL.OpenActionLiteDebug() end
			end,
		}})
		UI.Info(card, L("BUG_REPORT_COPY_HELP"), { height = 42 })
	end

	-- ========================================================================
	-- Page 2 : classe selectionnee
	-- ========================================================================
	local classFallback = UI.Text(classPage, "GameFontNormal", THEME.textDim)
	classFallback:SetPoint("TOP", 0, -70)
	classFallback:SetJustifyH("CENTER")

	for _, token in ipairs(AL.CLASS_TOKENS) do
		local mod = AL.rotations[token]
		local modern = AL.classUIs and AL.classUIs[token]
		local legacy = mod and mod.BuildOptions
		if modern or legacy then
			local panel = CreateFrame("Frame", nil, classPage)
			panel:SetAllPoints()
			panel:Hide()
			local ok, err
			if AL.ActionLiteDebug then AL.ActionLiteDebug.controlContext = token end
			if modern then
				ok, err = pcall(modern, panel, ui)
			else
				ok, err = pcall(legacy, panel, legacyUI)
			end
			if AL.ActionLiteDebug then AL.ActionLiteDebug.controlContext = nil end
			if ok then
				classPanels[token] = panel
			else
				panel:Hide()
				if ActionLiteDB and ActionLiteDB.debug then
					pcall(print, "|cff89cff0AL UI|r " .. token .. " : " .. tostring(err))
				end
			end
		end
	end

	UI.Register(function()
		local token = ActiveToken()
		for t, panel in pairs(classPanels) do panel:SetShown(t == token) end
		if classPanels[token] then
			classFallback:Hide()
		else
			classFallback:Show()
			if token == "WARRIOR" then
				classFallback:SetText(L("WARRIOR_UI_MISSING"))
			else
				classFallback:SetText(L("NO_CLASS_UI", UI.ClassName(token)))
			end
		end
		local name = UI.ClassName(token)
		tabStrip.buttons[2].label:SetText(name)
		tabStrip:Layout()
		classPage.caption:SetText(UI.ClassColored(token))
		profileText:SetText(UI.ClassColored(token))
	end)

	-- ========================================================================
	-- Page 3 : Sorts
	-- ========================================================================
	local ROW_H = 28
	do
		local toolbar = CreateFrame("Frame", nil, spellsPage)
		toolbar:SetPoint("TOPLEFT", GRID.pad, -30)
		toolbar:SetPoint("TOPRIGHT", -GRID.pad, -30)
		toolbar:SetHeight(22)

		local searchBox = CreateFrame("Frame", nil, toolbar)
		searchBox:SetPoint("LEFT")
		searchBox:SetSize(240, 22)
		UI.Fill(searchBox, THEME.surfaceAlt)
		local searchEdge = UI.Border(searchBox, THEME.line)

		local magnifier = UI.Text(searchBox, "GameFontNormalSmall", THEME.textFaint)
		magnifier:SetPoint("LEFT", 8, 0)
		magnifier:SetText(L("SEARCH_SPELL"))

		local search = CreateFrame("EditBox", nil, searchBox)
		search:SetPoint("TOPLEFT", 8, 0)
		search:SetPoint("BOTTOMRIGHT", -8, 0)
		search:SetAutoFocus(false)
		search:SetMaxLetters(32)
		local fontOk = pcall(search.SetFontObject, search, _G.ChatFontNormal or _G.GameFontHighlight)
		if not fontOk then
			-- repli explicite : une EditBox sans police provoque une erreur a l'affichage
			pcall(search.SetFont, search, "Fonts\\FRIZQT__.TTF", 12, "")
		end
		search:SetTextColor(UI.Color(THEME.text))
		search:SetScript("OnEscapePressed", function(self)
			self:SetText("")
			self:ClearFocus()
		end)
		search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		search:SetScript("OnEditFocusGained", function() searchEdge:SetColor(UI.Color(THEME.gold)) end)
		search:SetScript("OnEditFocusLost", function() searchEdge:SetColor(UI.Color(THEME.line)) end)
		search:SetScript("OnTextChanged", function(self)
			magnifier:SetShown((self:GetText() or "") == "")
			if menu.RebuildSpells then menu.RebuildSpells() end
		end)

		local onlyKnown = UI.Button(toolbar, { label = L("LEARNED_ONLY"), width = 146, height = 22 })
		onlyKnown:SetPoint("RIGHT", 0, 0)
		local function PaintFilter()
			if ActionLiteDB.spellsOnlyKnown then
				onlyKnown.text:SetText(L("LEARNED_ONLY"))
				onlyKnown.text:SetTextColor(UI.Color(THEME.ok))
			else
				onlyKnown.text:SetText(L("ALL_SPELLS"))
				onlyKnown.text:SetTextColor(UI.Color(THEME.textDim))
			end
		end
		onlyKnown:SetScript("OnClick", function()
			ActionLiteDB.spellsOnlyKnown = not ActionLiteDB.spellsOnlyKnown
			PaintFilter()
			menu.RebuildSpells()
		end)
		UI.Tooltip(onlyKnown, L("FILTER"), { L("FILTER_HELP") })

		local countText = UI.Text(toolbar, "GameFontNormalSmall", THEME.textFaint)
		countText:SetPoint("RIGHT", onlyKnown, "LEFT", -12, 0)

		-- en-tete de colonnes
		local headRow = CreateFrame("Frame", nil, spellsPage)
		headRow:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -6)
		headRow:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -6)
		headRow:SetHeight(16)
		local function Col(text, offset)
			local fs = UI.Text(headRow, "GameFontNormalSmall", THEME.goldDim)
			fs:SetPoint("RIGHT", headRow, "RIGHT", offset, 0)
			fs:SetText(text)
			return fs
		end
		local colName = UI.Text(headRow, "GameFontNormalSmall", THEME.goldDim)
		colName:SetPoint("LEFT", 36, 0)
		colName:SetText(L("SPELL"))
		Col("ID", -252)
		Col(L("STATUS"), -178)
		Col(L("ICON"), -108)
		Col(L("MACRO"), -50)
		Col(L("ENABLED"), -2)
		local headLine = headRow:CreateTexture(nil, "ARTWORK")
		headLine:SetHeight(1)
		headLine:SetPoint("BOTTOMLEFT")
		headLine:SetPoint("BOTTOMRIGHT")
		UI.Tint(headLine, THEME.bronze, 0.35)

		local listHost = CreateFrame("Frame", nil, spellsPage)
		listHost:SetPoint("TOPLEFT", headRow, "BOTTOMLEFT", -GRID.pad, -2)
		listHost:SetPoint("BOTTOMRIGHT", 0, 0)

		local scroll, content = UI.ScrollArea(listHost, { pad = GRID.pad, padTop = 2, spacing = 0 })

		local emptyText = UI.Text(content, "GameFontNormal", THEME.textFaint)
		emptyText:SetPoint("TOP", 0, -24)
		emptyText:Hide()

		-- selecteur d'icone partage, parente au menu pour ne jamais etre rogne
		local iconPicker = CreateFrame("Frame", nil, menu)
		iconPicker:SetSize(160, 11 * 22 + 4)
		UI.Fill(iconPicker, UI.Derived.listBg)
		UI.Border(iconPicker, THEME.bronze)
		iconPicker:SetFrameStrata("FULLSCREEN_DIALOG")
		iconPicker:Hide()
		for n = 0, 10 do
			local opt = CreateFrame("Button", nil, iconPicker)
			opt:SetHeight(22)
			opt:SetPoint("TOPLEFT", 2, -n * 22 - 2)
			opt:SetPoint("TOPRIGHT", -2, -n * 22 - 2)
			local hl = UI.Fill(opt, UI.Derived.highlight)
			hl:Hide()
			local ot = UI.Text(opt, "GameFontHighlightSmall", THEME.text)
			if n == 0 then
				ot:SetPoint("LEFT", 8, 0)
				ot:SetText(L("DEFAULT"))
			else
				local tex = opt:CreateTexture(nil, "ARTWORK")
				tex:SetSize(16, 16)
				tex:SetPoint("LEFT", 6, 0)
				tex:SetTexture(AL.UNIVERSAL_ICONS[n])
				tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				ot:SetPoint("LEFT", tex, "RIGHT", 8, 0)
				ot:SetText(L("UNIVERSAL", n))
			end
			opt:SetScript("OnEnter", function() hl:Show() end)
			opt:SetScript("OnLeave", function() hl:Hide() end)
			opt:SetScript("OnClick", function()
				local spell = iconPicker.spell
				if spell then
					local prof = ES()
					prof.icons = prof.icons or {}
					prof.icons[spell] = n > 0 and AL.UNIVERSAL_ICONS[n] or nil
					RecordUI("Spell icon changed", { class = ActiveToken(), spell = spell, universal = n, icon = prof.icons[spell] })
				end
				iconPicker:Hide()
				menu.RebuildSpells()
			end)
		end
		local function ToggleIconPicker(anchor, spell)
			if iconPicker:IsShown() and iconPicker.spell == spell then
				iconPicker:Hide()
				return
			end
			iconPicker.spell = spell
			iconPicker:ClearAllPoints()
			iconPicker:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
			iconPicker:Show()
			pcall(iconPicker.Raise, iconPicker)
		end
		scroll:HookScript("OnVerticalScroll", function() iconPicker:Hide() end)
		spellsPage:SetScript("OnHide", function() iconPicker:Hide() end)

		-- pool de lignes : aucune frame n'est creee apres le premier affichage
		local rowPool = {}
		local function GetRow(n)
			if rowPool[n] then return rowPool[n] end
			local row = CreateFrame("Frame", nil, content)
			row:SetHeight(ROW_H)
			row:SetPoint("TOPLEFT", 0, -(n - 1) * ROW_H)
			row:SetPoint("TOPRIGHT", 0, -(n - 1) * ROW_H)

			if n % 2 == 0 then UI.Fill(row, { 1, 1, 1, 0.022 }) end
			local sep = row:CreateTexture(nil, "ARTWORK")
			sep:SetHeight(1)
			sep:SetPoint("BOTTOMLEFT", 2, 0)
			sep:SetPoint("BOTTOMRIGHT", -2, 0)
			UI.Tint(sep, THEME.lineSoft)

			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("LEFT", 6, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

			row.nameText = UI.Text(row, "GameFontHighlightSmall", THEME.text)
			row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.nameText:SetPoint("RIGHT", row, "RIGHT", -300, 0)
			row.nameText:SetJustifyH("LEFT")

			row.idText = UI.Text(row, "GameFontNormalSmall", THEME.textFaint)
			row.idText:SetPoint("RIGHT", row, "RIGHT", -252, 0)
			row.idText:SetJustifyH("RIGHT")

			row.stateText = UI.Text(row, "GameFontNormalSmall", THEME.textFaint)
			row.stateText:SetPoint("RIGHT", row, "RIGHT", -178, 0)
			row.stateText:SetJustifyH("RIGHT")

			row.iconBtn = UI.Button(row, { label = "", width = 62, height = 17 })
			row.iconBtn:SetPoint("RIGHT", -108, 0)
			row.iconBtn:SetScript("OnClick", function()
				if row.spellName then ToggleIconPicker(row.iconBtn, row.spellName) end
			end)

			row.queueBtn = UI.Button(row, { label = L("QUEUE"), width = 52, height = 17 })
			row.queueBtn:SetPoint("RIGHT", -50, 0)
			row.queueBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row.queueBtn:SetScript("OnClick", function(_, button)
				if not row.spellName then return end
				if button == "RightButton" then
					ActionLite_Queue(row.spellName)
				else
					CreateSpellMacro(row.spellName)
				end
			end)
			UI.Tooltip(row.queueBtn, L("QUEUE_MACRO"), { L("QUEUE_LEFT"), L("QUEUE_RIGHT") })

			-- case a cocher, meme visuel que le reste de l'interface
			local hit = CreateFrame("Button", nil, row)
			hit:SetSize(16, 16)
			hit:SetPoint("RIGHT", -6, 0)
			local boxBg = UI.Fill(hit, THEME.raised)
			local boxEdge = UI.Border(hit, THEME.line)
			local mark = hit:CreateTexture(nil, "OVERLAY")
			mark:SetSize(18, 18)
			mark:SetPoint("CENTER")
			mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			UI.TintVertex(mark, THEME.gold)

			function row:Paint()
				local on = AL.Allowed(self.spellName, ES())
				mark:SetShown(on)
				if on then
					boxBg:SetColorTexture(UI.Color(UI.Derived.checkOn))
					boxEdge:SetColor(UI.Color(THEME.goldDim))
				else
					boxBg:SetColorTexture(UI.Color(THEME.raised))
					boxEdge:SetColor(UI.Color(THEME.line))
				end
			end
			hit:SetScript("OnClick", function()
				local prof = ES()
				prof.spells = prof.spells or {}
				prof.spells[row.spellName] = not AL.Allowed(row.spellName, prof)
				row:Paint()
				RecordUI("Spell checkbox changed", { class = ActiveToken(), spell = row.spellName, enabled = prof.spells[row.spellName] })
			end)
			hit:SetScript("OnEnter", function() boxEdge:SetColor(UI.Color(THEME.gold)) end)
			hit:SetScript("OnLeave", function() row:Paint() end)
			UI.Register(function()
				if row:IsShown() and row.spellName then row:Paint() end
			end)

			rowPool[n] = row
			return row
		end

		function menu.RebuildSpells()
			local token = ActiveToken()
			local mod = AL.rotations[token]
			local filter = (search:GetText() or ""):lower()
			local onlyLearned = ActionLiteDB.spellsOnlyKnown

			if not mod or not mod.spells then
				for i = 1, #rowPool do rowPool[i]:Hide() end
				emptyText:SetText(L("NO_SPELL_DATA"))
				emptyText:Show()
				countText:SetText("")
				content:SetHeight(80)
				scroll:SetVerticalScroll(0)
				scroll.UpdateThumb()
				return
			end

			local prof = ES()
			local shown, known = 0, 0
			for _, entry in ipairs(mod.spells) do
				local id, name = entry[1], entry[2]
				local isKnown = AL.known[name] and true or false
				if isKnown then known = known + 1 end
				local matches = filter == "" or name:lower():find(filter, 1, true) ~= nil
					or tostring(id):find(filter, 1, true) ~= nil
				if matches and (isKnown or not onlyLearned) then
					shown = shown + 1
					local row = GetRow(shown)
					row.spellName = name
					row.idText:SetText(id and tostring(id) or "?")
					row.nameText:SetText(name)
					row.nameText:SetTextColor(UI.Color(isKnown and THEME.text or THEME.textFaint))
					-- recherche par nom d'abord : les identifiants Forever peuvent
					-- differer des identifiants classiques
					local tex = AL.IconFor(name, prof) or AL.SpellTexture(name)
						or (id and AL.SpellTexture(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
					row.icon:SetTexture(tex)
					pcall(row.icon.SetDesaturated, row.icon, not isKnown)
					if isKnown then
						row.stateText:SetText("|cff5cc46e" .. L("LEARNED") .. "|r")
					else
						row.stateText:SetText("|cff6b7280" .. L("NOT_LEARNED") .. "|r")
					end
					local chosen = prof.icons and prof.icons[name]
					local label = L("DEFAULT")
					if chosen then
						for u, texId in ipairs(AL.UNIVERSAL_ICONS) do
							if texId == chosen then label = L("UNIVERSAL_SHORT", u) break end
						end
					end
					row.iconBtn.text:SetText(label)
					row:Paint()
					row:Show()
				end
			end
			for i = shown + 1, #rowPool do rowPool[i]:Hide() end

			if shown == 0 then
				emptyText:SetText(filter ~= "" and L("NO_SEARCH_MATCH") or L("NO_FILTER_MATCH"))
				emptyText:Show()
			else
				emptyText:Hide()
			end
			countText:SetText(L("SPELL_COUNT", shown, known))
			content:SetHeight(math.max(shown * ROW_H, 80))
			scroll:SetVerticalScroll(0)
			scroll.UpdateThumb()
			PaintFilter()
		end

		PaintFilter()
	end

	-- --------------------------------------------------------------- live loop
	local elapsed = 0
	menu:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.20 then return end
		elapsed = 0
		UpdateStatus()
	end)

	menu:SetScript("OnShow", function()
		UI.Repaint()
		if menu.RebuildSpells then menu.RebuildSpells() end
	end)

	local function SaveMenuPos()
		menu:StopMovingOrSizing()
		local point, _, relPoint, x, y = menu:GetPoint()
		if point then ActionLiteDB.menuPos = { point, relPoint, x, y } end
	end
	menu:SetScript("OnDragStart", function(self) self:StartMoving() end)
	menu:SetScript("OnDragStop", SaveMenuPos)
	header:SetScript("OnDragStop", SaveMenuPos)

	ShowPage(ActionLiteDB.lastTab or 1)
	UI.Repaint()
	tabStrip:Layout()
end

function AL.ToggleMenu()
	if not menu then
		local ok, err = pcall(BuildMenu)
		if not ok then
			menu = nil
			print("|cff89cff0ActionLITE|r: |cffbf5c5c" .. L("INTERFACE_ERROR") .. "|r " .. tostring(err))
			if AL.Log then AL.Log("ui", "error", "settings window failed to build", tostring(err)) end
			return
		end
	end
	if menu:IsShown() then
		menu.AnimateClose()
	else
		local p = ActionLiteDB.menuPos
		menu:ClearAllPoints()
		if p then
			menu:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		else
			menu:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
		end
		menu.AnimateOpen()
	end
end

-- Reconstruit uniquement la fenetre d'options dans la nouvelle langue.
-- L'ancien cadre est masque et ne conserve aucune boucle OnUpdate active.
function AL.RebuildMenu()
	local old = menu
	if old then
		old:Hide()
		old:SetScript("OnUpdate", nil)
		old:SetScript("OnShow", nil)
	end
	menu = nil
	local ok, err = pcall(BuildMenu)
	if not ok then
		menu = old
		if menu then menu:Show() end
		print("|cff89cff0ActionLITE|r: |cffbf5c5c" .. L("INTERFACE_ERROR") .. "|r " .. tostring(err))
		if AL.Log then AL.Log("ui", "error", "settings window failed to rebuild", tostring(err)) end
		return
	end
	local p = ActionLiteDB.menuPos
	menu:ClearAllPoints()
	if p then
		menu:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		menu:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	end
	menu.AnimateOpen()
end

-- Shared with the independent diagnostics window; no toggle/animation race.
function AL.HideMenu()
    if menu then menu:Hide() end
end
function AL.GetMenuFrame() return menu end
