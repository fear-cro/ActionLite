local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - UI_Core.lua - v0.6.11
-- ----------------------------------------------------------------------------
-- Bibliotheque de composants visuels partages par Menu.lua et les fichiers
-- <Class>_UI.lua. Aucune logique de combat ici.
--
-- Principes :
--   * aucun template autre que ceux deja valides sur WoW Forever ;
--   * aucun backdrop : tout est construit avec des textures simples, ce qui
--     fonctionne sur tous les clients et evite BackdropTemplate ;
--   * mise en page par pile verticale (Stack) : plus aucune coordonnee en dur
--     dans les pages de classe ;
--   * chaque composant expose Paint() et s'enregistre dans le registre de
--     rafraichissement, de sorte qu'aucune interface n'est reconstruite.
--
-- API resumee (voir Menu.lua pour la table "ui" passee aux classes) :
--   UI.Stack(frame, opts)          -> pile verticale
--   UI.Card(host, titre, soustitre)-> carte (elle-meme une pile)
--   UI.Toggle(host, opts)          -> interrupteur moderne
--   UI.Slider(host, opts)          -> curseur avec valeur, unite, min et max
--   UI.Button(parent, opts)        -> bouton (neutre / primaire / destructif)
--   UI.ButtonRow(host, liste)      -> rangee de boutons alignes
--   UI.Dropdown(parent, opts)      -> liste deroulante
--   UI.Badge(parent, opts)         -> pastille d'etat
--   UI.Info(host, texte)           -> ligne de texte discrete
--   UI.Divider(host)               -> separateur
--   UI.ScrollArea(parent, opts)    -> zone defilable + pile
--   UI.Tooltip(frame, titre, lignes)
--   UI.Confirm(opts)               -> fenetre modale de confirmation
-- ============================================================================

local WHITE = AL.WHITE or "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local UI = {}
AL.UI = UI
UI.VERSION = "0.6.11"

-- Optional state recorder. Diagnostics failures must never prevent controls
-- from changing the real profile or interfere with their existing callbacks.
local function RegisterDebugControl(widget, opts, kind)
    local debug = AL.ActionLiteDebug
    if debug and debug.RegisterControl then pcall(debug.RegisterControl, widget, opts, kind) end
end
local function DebugControlChanged(widget)
    local debug = AL.ActionLiteDebug
    if debug and debug.ControlChanged then pcall(debug.ControlChanged, widget) end
end

-- ----------------------------------------------------------------------------
-- Valeurs par defaut ajoutees sans toucher a Core.lua.
-- FillDefaults ne remplit que les cles absentes : les anciens profils restent
-- intacts.
-- ----------------------------------------------------------------------------
if AL.defaults then
	if AL.defaults.bgAlpha == nil then AL.defaults.bgAlpha = 0.75 end
	if AL.defaults.scale == nil then AL.defaults.scale = 1 end
end

AL.dbDefaults = {
	menuScale = 1,
	togglesHidden = false,
	castTrailOn = true,
	castTrailLocked = true,
	castTrailScale = 1,
}

function AL.FillDBDefaults()
	ActionLiteDB = ActionLiteDB or {}
	for k, v in pairs(AL.dbDefaults) do
		if ActionLiteDB[k] == nil then ActionLiteDB[k] = v end
	end
	return ActionLiteDB
end

function AL.Version()
	local v
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		v = C_AddOns.GetAddOnMetadata("ActionLITE", "Version")
	elseif GetAddOnMetadata then
		v = GetAddOnMetadata("ActionLITE", "Version")
	end
	return v or "0.6.11"
end

-- ----------------------------------------------------------------------------
-- Palette : acier sombre, bronze / or, rouge profond.
-- ----------------------------------------------------------------------------
local THEME = {
	shell      = { 0.043, 0.047, 0.055, 0.97 },
	sidebar    = { 0.063, 0.068, 0.078, 1.00 },
	surface    = { 0.086, 0.093, 0.105, 1.00 },
	surfaceAlt = { 0.118, 0.126, 0.141, 1.00 },
	raised     = { 0.157, 0.168, 0.188, 1.00 },
	line       = { 0.192, 0.207, 0.235, 1.00 },
	lineSoft   = { 1.000, 1.000, 1.000, 0.055 },
	bronze     = { 0.760, 0.570, 0.290, 1.00 },
	gold       = { 0.940, 0.740, 0.380, 1.00 },
	crimson    = { 0.560, 0.150, 0.150, 1.00 },
	text       = { 0.890, 0.900, 0.920, 1.00 },
	textDim    = { 0.600, 0.630, 0.690, 1.00 },
	textFaint  = { 0.479, 0.513, 0.581, 1.00 },
	ok         = { 0.360, 0.780, 0.440, 1.00 },
	green      = { 0.420, 0.880, 0.450, 1.00 },
	goldDim    = { 0.700, 0.550, 0.280, 1.00 },
	warn       = { 0.940, 0.700, 0.250, 1.00 },
	danger     = { 0.850, 0.320, 0.300, 1.00 },
}
UI.Theme = THEME

-- Grille commune : toutes les marges sont des multiples de 4.
UI.GRID = {
	pad      = 14,
	gutter   = 10,
	section  = 20,
	rowSmall = 24,
	row      = 26,
	rowDesc  = 38,
	slider   = 40,
	button   = 22,
	tab      = 24,
}

local function unpackColor(c, alphaOverride)
	return c[1], c[2], c[3], alphaOverride or c[4] or 1
end
UI.Color = unpackColor

-- ----------------------------------------------------------------------------
-- Theme engine. THEME and DERIVED tables keep their identity: a theme change
-- rewrites their values in place, then every bound object is recoloured.
-- ----------------------------------------------------------------------------
local DERIVED = {
	checkOn = {}, primaryBg = {}, dangerBg = {}, dangerFg = {}, toggleOn = {},
	closeBg = {}, frameEdge = {}, listBg = {}, highlight = {},
}
UI.Derived = DERIVED

local themeColor = {}
for _, c in pairs(THEME) do themeColor[c] = true end
for _, c in pairs(DERIVED) do themeColor[c] = true end

local function Scale(dst, c, k, a)
	dst[1], dst[2], dst[3], dst[4] = c[1] * k, c[2] * k, c[3] * k, a or 1
end

local function Derive()
	Scale(DERIVED.checkOn, THEME.gold, 0.22)
	Scale(DERIVED.primaryBg, THEME.gold, 0.26)
	Scale(DERIVED.dangerBg, THEME.crimson, 0.40)
	Scale(DERIVED.toggleOn, THEME.ok, 0.55)
	Scale(DERIVED.closeBg, THEME.crimson, 0.62)
	Scale(DERIVED.frameEdge, THEME.bronze, 0.82, 0.85)
	Scale(DERIVED.listBg, THEME.shell, 1, 0.99)
	Scale(DERIVED.highlight, THEME.gold, 1, 0.14)
	local d = THEME.danger
	DERIVED.dangerFg[1], DERIVED.dangerFg[2], DERIVED.dangerFg[3], DERIVED.dangerFg[4] =
		d[1] + (1 - d[1]) * 0.35, d[2] + (1 - d[2]) * 0.35, d[3] + (1 - d[3]) * 0.35, 1
end
Derive()

-- object -> { kind, color, alpha }; only theme colors are tracked.
local bound = setmetatable({}, { __mode = "k" })

local function Bind(obj, kind, color, alpha)
	if obj and themeColor[color] then bound[obj] = { kind, color, alpha } end
end

local function Recolor(obj, b)
	local kind, c, a = b[1], b[2], b[3]
	if kind == "tex" then obj:SetColorTexture(unpackColor(c, a))
	elseif kind == "vertex" then obj:SetVertexColor(unpackColor(c, a))
	elseif kind == "text" then obj:SetTextColor(unpackColor(c, a))
	elseif kind == "border" then obj:SetColor(unpackColor(c, a)) end
end

-- Solid texture tinted with a theme color that follows theme changes.
function UI.Tint(tex, color, alpha)
	tex:SetColorTexture(unpackColor(color, alpha))
	Bind(tex, "tex", color, alpha)
	return tex
end

-- Artwork texture (check mark, arrow) recoloured through its vertex color.
function UI.TintVertex(tex, color, alpha)
	tex:SetVertexColor(unpackColor(color, alpha))
	Bind(tex, "vertex", color, alpha)
	return tex
end

-- "ffrrggbb" for inline |c color codes.
function UI.Hex(color)
	return string.format("ff%02x%02x%02x",
		math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
end

-- colors: token -> { r, g, b, a }. Missing tokens keep their current value.
function UI.ApplyTheme(colors)
	for token, c in pairs(colors or {}) do
		local dst = THEME[token]
		if dst and type(c) == "table" then
			dst[1], dst[2], dst[3], dst[4] = c[1] or dst[1], c[2] or dst[2], c[3] or dst[3], c[4] or dst[4] or 1
		end
	end
	Derive()
	for obj, b in pairs(bound) do
		local ok, err = pcall(Recolor, obj, b)
		if not ok and AL.Log then AL.Log("ui", "warn", "theme recolor failed", tostring(err)) end
	end
	UI.Repaint()
end

function UI.ClassColor(token)
	local cc = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[token or ""]
	if not cc then return 0.85, 0.70, 0.40 end
	return cc.r, cc.g, cc.b
end

function UI.ClassHex(token)
	local r, g, b = UI.ClassColor(token)
	return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function UI.ClassName(token)
	if AL.UIClassName then return AL.UIClassName(token) end
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
end

function UI.ClassColored(token)
	return "|c" .. UI.ClassHex(token) .. UI.ClassName(token) .. "|r"
end

-- ----------------------------------------------------------------------------
-- Registre de rafraichissement.
-- Les callbacks sont proteges : un composant en erreur n'empeche jamais les
-- autres de se repeindre.
-- ----------------------------------------------------------------------------
UI.paints = {}

function UI.Register(fn)
	if type(fn) ~= "function" then return end
	UI.paints[#UI.paints + 1] = fn
	return fn
end

function UI.Repaint()
	for i = 1, #UI.paints do
		local ok, err = pcall(UI.paints[i])
		if not ok and AL.Log then AL.Log("ui", "warn", "repaint callback failed", tostring(err)) end
	end
end

-- ----------------------------------------------------------------------------
-- Primitives graphiques
-- ----------------------------------------------------------------------------
function UI.Fill(frame, color, layer, alpha)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints(frame)
	return UI.Tint(t, color, alpha)
end

function UI.Border(frame, color, thickness, layer)
	local th = thickness or 1
	local r, g, b, a = unpackColor(color)
	local function edge(w, h, p1, p2)
		local t = frame:CreateTexture(nil, layer or "BORDER")
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		t:SetPoint(p1)
		t:SetPoint(p2)
		t:SetColorTexture(r, g, b, a)
		return t
	end
	local set = {
		top    = edge(nil, th, "TOPLEFT", "TOPRIGHT"),
		bottom = edge(nil, th, "BOTTOMLEFT", "BOTTOMRIGHT"),
		left   = edge(th, nil, "TOPLEFT", "BOTTOMLEFT"),
		right  = edge(th, nil, "TOPRIGHT", "BOTTOMRIGHT"),
	}
	function set.SetColor(_, nr, ng, nb, na)
		set.top:SetColorTexture(nr, ng, nb, na or 1)
		set.bottom:SetColorTexture(nr, ng, nb, na or 1)
		set.left:SetColorTexture(nr, ng, nb, na or 1)
		set.right:SetColorTexture(nr, ng, nb, na or 1)
	end
	Bind(set, "border", color)
	return set
end

function UI.Text(parent, template, color)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if color then
		fs:SetTextColor(unpackColor(color))
		Bind(fs, "text", color)
	end
	return fs
end

function UI.Tooltip(frame, title, lines)
	if not frame or not title then return end
	frame.alTipTitle = title
	frame.alTipLines = lines
	local function show()
		if not frame.alTipTitle then return end
		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
		GameTooltip:AddLine(frame.alTipTitle, 1, 0.82, 0.35)
		if frame.alTipLines then
			for _, l in ipairs(frame.alTipLines) do
				GameTooltip:AddLine(l, 0.85, 0.86, 0.88, true)
			end
		end
		GameTooltip:Show()
	end
	local function hide() GameTooltip:Hide() end
	if frame:GetScript("OnEnter") then
		frame:HookScript("OnEnter", show)
		frame:HookScript("OnLeave", hide)
	else
		frame:SetScript("OnEnter", show)
		frame:SetScript("OnLeave", hide)
	end
end

-- ----------------------------------------------------------------------------
-- Stack : pile verticale auto-dimensionnee.
-- Les enfants sont ancres a gauche et a droite du conteneur, donc l'interface
-- suit automatiquement la largeur disponible et toute echelle d'interface.
-- ----------------------------------------------------------------------------
local Stack = {}
Stack.__index = Stack

function UI.Stack(frame, opts)
	opts = opts or {}
	return setmetatable({
		frame     = frame,
		items     = {},
		padX      = opts.padX or 0,
		padTop    = opts.padTop or 0,
		padBottom = opts.padBottom or 0,
		spacing   = opts.spacing or UI.GRID.gutter,
		height    = (opts.padTop or 0) + (opts.padBottom or 0),
	}, Stack)
end

function Stack:Add(child, height, opts)
	opts = opts or {}
	child.alHeight = height or UI.GRID.row
	child.alGap = opts.gap
	child.alPadX = opts.padX
	-- half = true : l'element occupe une demi-largeur et se met en paire avec
	-- le prochain element "half". Deux colonnes exactement, par ancrage pur,
	-- donc sans aucun calcul de largeur : la mise en page suit la fenetre.
	child.alHalf = opts.half and true or nil
	self.items[#self.items + 1] = child
	self:Reflow()
	return child
end

function Stack:Resize(child, height)
	if child.alHeight == height then return end
	child.alHeight = height
	self:Reflow()
end

function Stack:SetItemShown(child, shown)
	child.alSkip = not shown
	child:SetShown(shown and not (self.ownerCard and self.ownerCard.collapsed) or false)
	self:Reflow()
end

function Stack:Reflow()
	local items = self.items
	local y, first = self.padTop, true
	local i = 1
	while i <= #items do
		local c = items[i]
		if c.alSkip then
			i = i + 1
		else
			-- cherche un partenaire de colonne parmi les elements suivants
			local partner, pIndex
			if c.alHalf then
				local j = i + 1
				while items[j] and items[j].alSkip do j = j + 1 end
				if items[j] and items[j].alHalf then partner, pIndex = items[j], j end
			end
			if not first then y = y + (c.alGap or self.spacing) end
			first = false
			local px = c.alPadX or self.padX
			local h = c.alHeight or UI.GRID.row
			if partner then
				h = math.max(h, partner.alHeight or UI.GRID.row)
				c:ClearAllPoints()
				c:SetPoint("TOPLEFT", self.frame, "TOPLEFT", px, -y)
				c:SetPoint("TOPRIGHT", self.frame, "TOP", -5, -y)
				c:SetHeight(math.max(1, h))
				partner:ClearAllPoints()
				partner:SetPoint("TOPLEFT", self.frame, "TOP", 5, -y)
				partner:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -px, -y)
				partner:SetHeight(math.max(1, h))
				i = pIndex + 1
			else
				c:ClearAllPoints()
				c:SetPoint("TOPLEFT", self.frame, "TOPLEFT", px, -y)
				c:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -px, -y)
				c:SetHeight(math.max(1, h))
				i = i + 1
			end
			y = y + h
		end
	end
	self.height = y + self.padBottom
	if self.onResize then self.onResize(self.height) end
end

function Stack:Height() return self.height end

-- Un "host" peut etre une Card (qui embarque sa pile) ou une pile directe.
local function HostStack(host)
	if not host then return nil end
	return host.stack or host
end
UI.HostStack = HostStack

-- ----------------------------------------------------------------------------
-- Card : bloc de contenu titre, avec liseret d'accent a gauche.
-- ----------------------------------------------------------------------------
function UI.Card(host, title, subtitle, opts)
	opts = opts or {}
	local st = HostStack(host)
	local card = CreateFrame("Frame", nil, st.frame)
	UI.Fill(card, THEME.surface)
	card.border = UI.Border(card, THEME.line)

	local head = UI.Text(card, "GameFontNormal", THEME.gold)
	head:SetPoint("TOP", 0, -9)
	head:SetText(title or "")
	card.title = head

	local top = 34
	if subtitle then
		local sub = UI.Text(card, "GameFontNormalSmall", THEME.textFaint)
		sub:SetPoint("TOP", 0, -27)
		sub:SetJustifyH("CENTER")
		sub:SetText(subtitle)
		card.subtitle = sub
		top = 50
	end

	local accent = card:CreateTexture(nil, "ARTWORK")
	accent:SetHeight(1)
	accent:SetPoint("TOPLEFT", 12, -(top - 8))
	accent:SetPoint("TOPRIGHT", -12, -(top - 8))
	UI.Tint(accent, opts.accent or THEME.bronze, 0.35)
	card.accent = accent

	st:Add(card, top + 10)
	card.stack = UI.Stack(card, {
		padX = 10, padTop = top, padBottom = 10, spacing = opts.spacing or 3,
	})
	card.stack.onResize = function(h)
		card.alHeight = h
		st:Reflow()
	end
	card.parentStack = st
	card.stack.ownerCard = card
	card.expandedHeight = card.alHeight
	local previousResize = card.stack.onResize
	card.stack.onResize = function(h)
		card.expandedHeight = h
		if card.collapsed then
			card.alHeight = top + 2
			for _, child in ipairs(card.stack.items) do child:Hide() end
			st:Reflow()
		else
			previousResize(h)
		end
	end

	if opts.collapsible then
		local saved = ActionLiteDB and ActionLiteDB.uiCollapsed
		local value = saved and opts.collapseKey and saved[opts.collapseKey]
		card.collapsed = value ~= nil and value or (value == nil and opts.collapsed == true)
		local header = CreateFrame("Button", nil, card)
		header:SetPoint("TOPLEFT", 4, -4)
		header:SetPoint("TOPRIGHT", -28, -4)
		header:SetHeight(24)
		local arrow = UI.Text(header, "GameFontNormalSmall", THEME.goldDim)
		arrow:SetPoint("LEFT", 5, 0)
		function card:SetCollapsed(collapsed)
			self.collapsed = collapsed == true
			arrow:SetText(self.collapsed and "+" or "-")
			for _, child in ipairs(self.stack.items) do child:SetShown(not self.collapsed and not child.alSkip) end
			self.alHeight = self.collapsed and top + 2 or self.expandedHeight
			self.parentStack:Reflow()
			if opts.collapseKey then
				ActionLiteDB.uiCollapsed = ActionLiteDB.uiCollapsed or {}
				ActionLiteDB.uiCollapsed[opts.collapseKey] = self.collapsed
			end
		end
		header:SetScript("OnClick", function() card:SetCollapsed(not card.collapsed) end)
		UI.Tooltip(header, title, { "Click the heading to expand or collapse this section." })
		arrow:SetText(card.collapsed and "+" or "-")
		card.headerButton = header
	end

	function card:SetAccent(r, g, b)
		accent:SetColorTexture(r, g, b, 0.5)
		head:SetTextColor(r, g, b, 1)
	end
	return card
end

-- ----------------------------------------------------------------------------
-- Check : case a cocher compacte. C'est le controle par defaut des grilles a
-- deux colonnes ; le libelle explicatif passe dans l'infobulle pour garder des
-- lignes courtes et denses.
-- opts : label, desc, icon, get, set, onChange, tooltip, half
-- ----------------------------------------------------------------------------
function UI.Check(host, opts)
	local st = HostStack(host)
	local h = opts.desc and UI.GRID.rowDesc or UI.GRID.rowSmall
	local b = CreateFrame("Button", nil, st.frame)

	local hover = UI.Fill(b, THEME.lineSoft)
	hover:Hide()

	local box = CreateFrame("Frame", nil, b)
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 5, opts.desc and 6 or 0)
	local boxBg = UI.Fill(box, THEME.raised)
	local boxEdge = UI.Border(box, THEME.line)
	local mark = box:CreateTexture(nil, "OVERLAY")
	mark:SetSize(16, 16)
	mark:SetPoint("CENTER", 0, 0)
	mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	UI.TintVertex(mark, THEME.gold)

	local x = 25
	if opts.icon then
		local ic = b:CreateTexture(nil, "ARTWORK")
		ic:SetSize(16, 16)
		ic:SetPoint("LEFT", box, "RIGHT", 6, 0)
		ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		ic:SetTexture(opts.icon)
		b.icon = ic
		x = 47
	end

	local label = UI.Text(b, "GameFontHighlightSmall", THEME.text)
	label:SetJustifyH("LEFT")
	label:SetText(opts.label or "")
	b.label = label

	if opts.desc then
		label:SetPoint("TOPLEFT", x, -4)
		label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
		local desc = UI.Text(b, "GameFontNormalSmall", THEME.textFaint)
		desc:SetPoint("TOPLEFT", x, -19)
		desc:SetPoint("RIGHT", b, "RIGHT", -6, 0)
		desc:SetJustifyH("LEFT")
		desc:SetText(opts.desc)
		b.desc = desc
	else
		label:SetPoint("LEFT", x, 0)
		label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
	end

	function b:Paint()
		local on = opts.get and opts.get() and true or false
		mark:SetShown(on)
		if on then
			boxBg:SetColorTexture(UI.Color(DERIVED.checkOn))
			boxEdge:SetColor(UI.Color(THEME.goldDim))
			label:SetTextColor(UI.Color(THEME.text))
		else
			boxBg:SetColorTexture(UI.Color(THEME.raised))
			boxEdge:SetColor(UI.Color(THEME.line))
			label:SetTextColor(UI.Color(THEME.textDim))
		end
	end

	b:SetScript("OnEnter", function()
		hover:Show()
		boxEdge:SetColor(UI.Color(THEME.gold))
	end)
	b:SetScript("OnLeave", function()
		hover:Hide()
		b:Paint()
	end)
	b:SetScript("OnClick", function()
		if not opts.get or not opts.set then return end
		opts.set(not opts.get())
		b:Paint()
		if opts.onChange then opts.onChange() end
		DebugControlChanged(b)
	end)

	if opts.tooltip then
		UI.Tooltip(b, opts.tooltip[1], { unpack(opts.tooltip, 2) })
	end

	st:Add(b, h, { gap = opts.gap, half = opts.half })
	RegisterDebugControl(b, opts, "checkbox")
	UI.Register(function() b:Paint() end)
	b:Paint()
	return b
end

-- ----------------------------------------------------------------------------
-- Toggle : interrupteur moderne (piste + pastille).
-- opts : label, desc, icon, get, set, onChange, tooltip = { titre, l1, l2 }
-- ----------------------------------------------------------------------------
function UI.Toggle(host, opts)
	local st = HostStack(host)
	local h = opts.desc and UI.GRID.rowDesc or UI.GRID.rowSmall
	local b = CreateFrame("Button", nil, st.frame)

	local hover = UI.Fill(b, THEME.lineSoft)
	hover:Hide()

	local x = 6
	if opts.icon then
		local ic = b:CreateTexture(nil, "ARTWORK")
		ic:SetSize(18, 18)
		ic:SetPoint("LEFT", 4, 0)
		ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		ic:SetTexture(opts.icon)
		b.icon = ic
		x = 28
	end

	local label = UI.Text(b, "GameFontHighlight", THEME.text)
	label:SetJustifyH("LEFT")
	label:SetText(opts.label or "")
	b.label = label

	local desc
	if opts.desc then
		label:SetPoint("TOPLEFT", x, -6)
		desc = UI.Text(b, "GameFontNormalSmall", THEME.textFaint)
		desc:SetPoint("TOPLEFT", x, -23)
		desc:SetPoint("RIGHT", b, "RIGHT", -56, 0)
		desc:SetJustifyH("LEFT")
		desc:SetText(opts.desc)
		b.desc = desc
	else
		label:SetPoint("LEFT", x, 0)
	end
	label:SetPoint("RIGHT", b, "RIGHT", -52, 0)

	local track = CreateFrame("Frame", nil, b)
	track:SetSize(34, 16)
	track:SetPoint("RIGHT", -6, 0)
	local trackTex = UI.Fill(track, THEME.raised)
	local trackEdge = UI.Border(track, THEME.line)
	local knob = track:CreateTexture(nil, "OVERLAY")
	knob:SetSize(12, 12)

	local function paintState(on)
		knob:ClearAllPoints()
		if on then
			trackTex:SetColorTexture(unpackColor(DERIVED.toggleOn))
			trackEdge:SetColor(unpackColor(THEME.ok))
			knob:SetColorTexture(unpackColor(THEME.ok))
			knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
		else
			trackTex:SetColorTexture(unpackColor(THEME.raised))
			trackEdge:SetColor(unpackColor(THEME.line))
			knob:SetColorTexture(unpackColor(THEME.textFaint))
			knob:SetPoint("LEFT", track, "LEFT", 2, 0)
		end
	end

	function b:Paint()
		local on = opts.get and opts.get() and true or false
		paintState(on)
		if opts.available then
			local avail = opts.available()
			label:SetTextColor(unpackColor(avail and THEME.text or THEME.textFaint))
		end
	end

	b:SetScript("OnEnter", function()
		hover:Show()
		trackEdge:SetColor(unpackColor(THEME.gold))
	end)
	b:SetScript("OnLeave", function()
		hover:Hide()
		b:Paint()
	end)
	b:SetScript("OnClick", function()
		if not opts.get or not opts.set then return end
		opts.set(not opts.get())
		b:Paint()
		if opts.onChange then opts.onChange() end
		DebugControlChanged(b)
	end)

	if opts.tooltip then
		UI.Tooltip(b, opts.tooltip[1], { unpack(opts.tooltip, 2) })
	end

	st:Add(b, h, { gap = opts.gap, half = opts.half })
	RegisterDebugControl(b, opts, "toggle")
	UI.Register(function() b:Paint() end)
	b:Paint()
	return b
end

-- ----------------------------------------------------------------------------
-- Slider : nom, valeur courante avec unite, bornes min/max, pas coherent.
-- opts : label, min, max, step, suffix, get, set, deferred, format
-- Les valeurs manipulees sont celles affichees (ex. 50..200 pour des %).
-- ----------------------------------------------------------------------------
local function RoundStep(value, step, minV, maxV)
	if type(value) ~= "number" then value = minV end
	step = step or 1
	local v = math.floor((value - minV) / step + 0.5) * step + minV
	if v < minV then v = minV end
	if v > maxV then v = maxV end
	return v
end

function UI.Slider(host, opts)
	local st = HostStack(host)
	local minV, maxV = opts.min or 0, opts.max or 100
	local step = opts.step or 5
	local suffix = opts.suffix or ""

	local f = CreateFrame("Frame", nil, st.frame)

	-- Ligne 1 : nom + bornes en gris, valeur courante en vert a droite.
	local label = UI.Text(f, "GameFontNormalSmall", THEME.gold)
	label:SetPoint("TOPLEFT", 6, -3)
	label:SetJustifyH("LEFT")
	local function PaintLabel()
		label:SetText(opts.label or "")
	end
	PaintLabel()

	local value = UI.Text(f, "GameFontNormalSmall", THEME.green)
	value:SetPoint("TOPRIGHT", -6, -3)
	value:SetJustifyH("RIGHT")
	label:SetPoint("RIGHT", value, "LEFT", -12, 0)
	pcall(label.SetWordWrap, label, false)

	local slider = CreateFrame("Slider", nil, f)
	slider:SetPoint("TOPLEFT", 6, -20)
	slider:SetPoint("TOPRIGHT", -6, -20)
	slider:SetHeight(14)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(minV, maxV)
	slider:SetValueStep(step)
	pcall(slider.SetObeyStepOnDrag, slider, true)

	local trackBg = CreateFrame("Frame", nil, f)
	trackBg:SetPoint("LEFT", slider, "LEFT", 0, 0)
	trackBg:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
	trackBg:SetHeight(8)
	UI.Fill(trackBg, THEME.raised)
	UI.Border(trackBg, THEME.line)
	-- Le rail est un frame separe : imposer les niveaux evite qu'il masque
	-- le remplissage ou le pouce sur certains clients anciens.
	trackBg:SetFrameLevel(f:GetFrameLevel() + 1)
	slider:SetFrameLevel(f:GetFrameLevel() + 2)

	local fill = slider:CreateTexture(nil, "ARTWORK")
	fill:SetHeight(6)
	fill:SetPoint("LEFT", 1, 0)
	UI.Tint(fill, THEME.goldDim)

	slider:SetThumbTexture(WHITE)
	local thumb = slider:GetThumbTexture()
	local function PaintThumb()
		if not thumb then return end
		-- couleur d'abord : sur certains clients SetColorTexture reinitialise la taille
		pcall(thumb.SetColorTexture, thumb, UI.Color(THEME.gold))
		pcall(thumb.SetSize, thumb, 8, 14)
	end
	PaintThumb()

	local function Display(v)
		if opts.format then
			value:SetText(opts.format(v))
		else
			value:SetText(tostring(v) .. suffix)
		end
		local w = slider:GetWidth() or 0
		if w > 0 and maxV > minV then
			local ratio = (v - minV) / (maxV - minV)
			fill:SetWidth(math.max(1, (w - 2) * ratio))
		end
	end

	f.applying = false
	f.pending = nil

	slider:SetScript("OnSizeChanged", function()
		Display(RoundStep(slider:GetValue(), step, minV, maxV))
	end)

	slider:SetScript("OnValueChanged", function(self, raw)
		local v = RoundStep(raw, step, minV, maxV)
		Display(v)
		if f.applying then return end
		if opts.deferred then
			f.pending = v
		elseif opts.set then
			opts.set(v)
			DebugControlChanged(f)
		end
	end)

	slider:SetScript("OnMouseUp", function()
		if f.pending ~= nil and opts.set then
			opts.set(f.pending)
			f.pending = nil
			DebugControlChanged(f)
		end
	end)

	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(self, delta)
		local v = RoundStep((self:GetValue() or minV) + delta * step, step, minV, maxV)
		self:SetValue(v)
		if opts.deferred and opts.set then
			opts.set(v)
			f.pending = nil
			DebugControlChanged(f)
		end
	end)

	function f:Paint()
		PaintLabel()
		PaintThumb()
		local v = RoundStep(opts.get and opts.get() or minV, step, minV, maxV)
		f.applying = true
		slider:SetValue(v)
		f.applying = false
		Display(v)
	end

	local help = {}
	if opts.tooltip then for i = 2, #opts.tooltip do help[#help + 1] = opts.tooltip[i] end end
	help[#help + 1] = "Range: " .. minV .. suffix .. " to " .. maxV .. suffix .. "."
	UI.Tooltip(slider, opts.tooltip and opts.tooltip[1] or opts.label, help)

	st:Add(f, UI.GRID.slider, { gap = opts.gap, half = opts.half })
	RegisterDebugControl(f, opts, "slider")
	UI.Register(function() f:Paint() end)
	f:Paint()
	f.slider = slider
	return f
end

-- ----------------------------------------------------------------------------
-- Button : variantes "default", "primary", "danger".
-- ----------------------------------------------------------------------------
local BUTTON_STYLE = {
	default = { bg = THEME.raised,  edge = THEME.line,    fg = THEME.text,  hover = THEME.gold },
	primary = { bg = DERIVED.primaryBg, edge = THEME.bronze, fg = THEME.gold, hover = THEME.gold },
	danger  = { bg = DERIVED.dangerBg, edge = THEME.crimson, fg = DERIVED.dangerFg, hover = THEME.danger },
}

function UI.Button(parent, opts)
	local style = BUTTON_STYLE[opts.variant or "default"] or BUTTON_STYLE.default
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(opts.width or 140, opts.height or UI.GRID.button)
	local bg = UI.Fill(b, style.bg)
	local edge = UI.Border(b, style.edge)
	local text = UI.Text(b, "GameFontHighlightSmall", style.fg)
	text:SetPoint("CENTER")
	text:SetText(opts.label or "")
	b.text = text

	b:SetScript("OnEnter", function()
		edge:SetColor(unpackColor(style.hover))
		bg:SetColorTexture(unpackColor(style.bg, math.min(1, (style.bg[4] or 1))))
		text:SetTextColor(unpackColor(style.hover))
	end)
	b:SetScript("OnLeave", function()
		edge:SetColor(unpackColor(style.edge))
		text:SetTextColor(unpackColor(style.fg))
	end)
	if opts.onClick then
		b:SetScript("OnClick", opts.onClick)
	end
	if opts.tooltip then
		UI.Tooltip(b, opts.tooltip[1], { unpack(opts.tooltip, 2) })
	end
	return b
end

-- Rangee de boutons repartis sur toute la largeur de la pile.
function UI.ButtonRow(host, buttons, opts)
	opts = opts or {}
	local st = HostStack(host)
	local row = CreateFrame("Frame", nil, st.frame)
	local h = opts.height or 26
	local gap = opts.gap or 8
	local created = {}
	for i, def in ipairs(buttons) do
		local b = UI.Button(row, def)
		b:SetHeight(h)
		created[i] = b
	end
	local function Layout()
		local total = row:GetWidth() or 0
		local n = #created
		if n == 0 or total <= 0 then return end
		local w = (total - gap * (n - 1)) / n
		for i, b in ipairs(created) do
			b:ClearAllPoints()
			b:SetWidth(w)
			b:SetPoint("TOPLEFT", row, "TOPLEFT", (w + gap) * (i - 1), 0)
		end
	end
	row:SetScript("OnSizeChanged", Layout)
	st:Add(row, h, { gap = opts.gapBefore })
	Layout()
	row.Layout = Layout
	return row, created
end

-- ----------------------------------------------------------------------------
-- Info / Divider
-- ----------------------------------------------------------------------------
function UI.Info(host, text, opts)
	opts = opts or {}
	local st = HostStack(host)
	local f = CreateFrame("Frame", nil, st.frame)
	local textLeft = 6
	if opts.icon then
		local ic = f:CreateTexture(nil, "ARTWORK")
		ic:SetSize(16, 16)
		ic:SetPoint("TOPLEFT", 6, -1)
		ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		ic:SetTexture(opts.icon)
		f.icon = ic
		textLeft = 28
	end
	local fs = UI.Text(f, opts.template or "GameFontNormalSmall", opts.color or THEME.textDim)
	fs:SetPoint("TOPLEFT", textLeft, -2)
	fs:SetPoint("TOPRIGHT", -6, -2)
	fs:SetJustifyH(opts.justify or "LEFT")
	fs:SetText(text or "")
	local minH = opts.height or 18
	st:Add(f, minH, { gap = opts.gap, half = opts.half })
	f.text = fs

	-- Le texte est ancre a gauche ET a droite : il se replie tout seul quand la
	-- fenetre retrecit. On resuit alors la ligne pour qu'elle ne deborde pas.
	-- Stack:Resize ignore une hauteur identique, donc la boucle se stabilise.
	local function FitHeight()
		local h = fs.GetStringHeight and fs:GetStringHeight() or nil
		if type(h) ~= "number" or h <= 0 then return end
		st:Resize(f, math.max(minH, math.floor(h + 0.5) + 6))
	end
	f:SetScript("OnSizeChanged", FitHeight)
	function f:SetText(v)
		fs:SetText(v)
		FitHeight()
	end
	return f
end

function UI.Divider(host, opts)
	opts = opts or {}
	local st = HostStack(host)
	local f = CreateFrame("Frame", nil, st.frame)
	local t = f:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	t:SetPoint("LEFT", 4, 0)
	t:SetPoint("RIGHT", -4, 0)
	UI.Tint(t, THEME.lineSoft)
	st:Add(f, opts.height or 9, { gap = opts.gap })
	return f
end

-- ----------------------------------------------------------------------------
-- Badge : pastille d'etat a largeur automatique.
-- ----------------------------------------------------------------------------
function UI.Badge(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(opts.height or 18)
	local bg = UI.Fill(f, THEME.surfaceAlt)
	local edge = UI.Border(f, THEME.line)
	local fs = UI.Text(f, "GameFontNormalSmall", THEME.textDim)
	fs:SetPoint("CENTER", 0, 0)
	f.text = fs

	function f:SetBadge(label, color)
		f.badgeLabel, f.badgeColor = label, color
		fs:SetText(label or "")
		color = color or THEME.textDim
		fs:SetTextColor(unpackColor(color))
		edge:SetColor(color[1], color[2], color[3], 0.55)
		bg:SetColorTexture(color[1] * 0.18, color[2] * 0.18, color[3] * 0.18, 1)
		if not opts.fixedWidth then
			f:SetWidth(math.max(opts.minWidth or 40, (fs:GetStringWidth() or 20) + 16))
		end
	end
	f:SetBadge(opts.label, opts.color)
	if opts.fixedWidth then f:SetWidth(opts.fixedWidth) end
	UI.Register(function() f:SetBadge(f.badgeLabel, f.badgeColor) end)
	return f
end

-- Rangee de badges dans une pile (utilisee par la page de classe).
function UI.BadgeRow(host, count, opts)
	opts = opts or {}
	local st = HostStack(host)
	local row = CreateFrame("Frame", nil, st.frame)
	local badges = {}
	local h = opts.height or 20
	local gap = opts.gap or 6
	for i = 1, count do
		local b = UI.Badge(row, { height = h })
		badges[i] = b
	end
	function row:Layout()
		local total = 0
		for i, b in ipairs(badges) do
			total = total + (b:GetWidth() or 40) + (i > 1 and gap or 0)
		end
		local x = math.max(2, ((row:GetWidth() or 0) - total) / 2)
		for _, b in ipairs(badges) do
			b:ClearAllPoints()
			b:SetPoint("LEFT", row, "LEFT", x, 0)
			x = x + (b:GetWidth() or 40) + gap
		end
	end
	row:SetScript("OnSizeChanged", function() row:Layout() end)
	row:Layout()
	st:Add(row, h + 4, { gap = opts.gapBefore })
	row.badges = badges
	return row
end

-- ----------------------------------------------------------------------------
-- Dropdown
-- opts : width, height, align ("LEFT" ou centre), options = { { label, value, icon, right }, ... },
--        get, set, onSelect
-- ----------------------------------------------------------------------------
function UI.Dropdown(parent, opts)
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(opts.width or 170, opts.height or 22)
	UI.Fill(dd, THEME.surfaceAlt)
	local edge = UI.Border(dd, THEME.line)

	-- Libelle centre et fleche doree a droite : meme langage visuel que les
	-- listes deroulantes pleine largeur de l'interface de reference.
	local label = UI.Text(dd, "GameFontHighlightSmall", THEME.text)
	local icon = dd:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	if opts.align == "LEFT" then
		icon:SetPoint("LEFT", 6, 0)
		label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	else
		label:SetPoint("CENTER", 0, 0)
		icon:SetPoint("RIGHT", label, "LEFT", -6, 0)
	end
	local right = UI.Text(dd, "GameFontNormalSmall", THEME.textFaint)
	right:SetPoint("RIGHT", -20, 0)
	local arrow = dd:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(10, 10)
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetRotation(-math.pi / 2)
	UI.TintVertex(arrow, THEME.gold)

	local rowH = 22
	local list = CreateFrame("Frame", nil, dd)
	list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
	list:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -2)
	list:SetHeight(#opts.options * rowH + 4)
	UI.Fill(list, DERIVED.listBg)
	UI.Border(list, THEME.bronze)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetFrameLevel(dd:GetFrameLevel() + 20)
	list:Hide()

	local rows = {}
	for n, def in ipairs(opts.options) do
		-- Lua 5.1 partage la variable de boucle avec les closures. Conserver une
		-- copie par ligne evite que tous les clics choisissent la derniere option.
		local option = def
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(rowH)
		row:SetPoint("TOPLEFT", 2, -(n - 1) * rowH - 2)
		row:SetPoint("TOPRIGHT", -2, -(n - 1) * rowH - 2)
		local hl = UI.Fill(row, DERIVED.highlight)
		hl:Hide()
		local ric = row:CreateTexture(nil, "ARTWORK")
		ric:SetSize(14, 14)
		ric:SetPoint("LEFT", 5, 0)
		if option.icon then option.icon(ric) end
		local rt = UI.Text(row, "GameFontHighlightSmall", THEME.text)
		rt:SetPoint("LEFT", ric, "RIGHT", 6, 0)
		rt:SetText(option.label or "")
		row.label = rt
		local rr = UI.Text(row, "GameFontNormalSmall", THEME.textFaint)
		rr:SetPoint("RIGHT", -6, 0)
		row.right = rr
		row:SetScript("OnEnter", function() hl:Show() end)
		row:SetScript("OnLeave", function() hl:Hide() end)
		row:SetScript("OnClick", function()
			list:Hide()
			if opts.set then opts.set(option.value) end
			if opts.onSelect then opts.onSelect(option.value) end
			UI.Repaint()
			DebugControlChanged(dd)
		end)
		rows[n] = row
	end

	dd:SetScript("OnEnter", function() edge:SetColor(unpackColor(THEME.gold)) end)
	dd:SetScript("OnLeave", function() edge:SetColor(unpackColor(THEME.line)) end)
	dd:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
	dd:SetScript("OnHide", function() list:Hide() end)

	function dd:Paint()
		local current = opts.get and opts.get()
		for n, def in ipairs(opts.options) do
			if def.right and rows[n] then rows[n].right:SetText(def.right()) end
			if def.value == current then
				label:SetText(def.label or "")
				if def.icon then def.icon(icon) end
				right:SetText(def.right and def.right() or "")
			end
		end
	end
	UI.Register(function() dd:Paint() end)
	dd:Paint()
	dd.list = list
	RegisterDebugControl(dd, opts, "dropdown")
	return dd
end

-- ----------------------------------------------------------------------------
-- StackDropdown : liste deroulante pleine largeur posee dans une pile,
-- precedee d'un intitule dore centre.
-- ----------------------------------------------------------------------------
function UI.StackDropdown(host, opts)
	local st = HostStack(host)
	local wrap = CreateFrame("Frame", nil, st.frame)
	local caption = UI.Text(wrap, "GameFontNormalSmall", THEME.gold)
	caption:SetPoint("TOP", 0, -2)
	caption:SetText(opts.caption or "")
	local dd = UI.Dropdown(wrap, opts)
	dd:ClearAllPoints()
	dd:SetPoint("TOPLEFT", 6, -18)
	dd:SetPoint("TOPRIGHT", -6, -18)
	st:Add(wrap, 44, { gap = opts.gap, half = opts.half })
	wrap.dropdown = dd
	return wrap
end

-- ----------------------------------------------------------------------------
-- Tabs : bandeau d'onglets horizontal.
-- defs : { { label = "...", onClick = fn }, ... }
-- Appeler strip:Layout() apres avoir change un libelle (nom de classe).
-- ----------------------------------------------------------------------------
function UI.Tabs(parent, defs, opts)
	opts = opts or {}
	local strip = CreateFrame("Frame", nil, parent)
	strip:SetHeight(opts.height or UI.GRID.tab)
	local buttons = {}

	for i, def in ipairs(defs) do
		local b = CreateFrame("Button", nil, strip)
		b:SetHeight(opts.height or UI.GRID.tab)
		local bg = UI.Fill(b, THEME.surface)
		local edge = UI.Border(b, THEME.line)
		local under = b:CreateTexture(nil, "OVERLAY")
		under:SetHeight(2)
		under:SetPoint("BOTTOMLEFT", 1, 0)
		under:SetPoint("BOTTOMRIGHT", -1, 0)
		UI.Tint(under, THEME.gold)
		under:Hide()
		local text = UI.Text(b, "GameFontNormalSmall", THEME.textDim)
		text:SetPoint("CENTER", 0, 0)
		text:SetText(def.label or "")
		b.label = text

		function b:SetActive(active)
			b.active = active
			under:SetShown(active and true or false)
			if active then
				bg:SetColorTexture(UI.Color(THEME.surfaceAlt))
				edge:SetColor(UI.Color(THEME.goldDim))
				text:SetTextColor(UI.Color(THEME.gold))
			else
				bg:SetColorTexture(UI.Color(THEME.surface))
				edge:SetColor(UI.Color(THEME.line))
				text:SetTextColor(UI.Color(THEME.textDim))
			end
		end
		b:SetScript("OnEnter", function()
			if not b.active then text:SetTextColor(UI.Color(THEME.text)) end
		end)
		b:SetScript("OnLeave", function()
			if not b.active then text:SetTextColor(UI.Color(THEME.textDim)) end
		end)
		b:SetScript("OnClick", function()
			if def.onClick then def.onClick(i) end
		end)
		b:SetActive(false)
		buttons[i] = b
	end

	function strip:Layout()
		local x = 0
		for _, b in ipairs(buttons) do
			local w = math.max(opts.minWidth or 78, (b.label:GetStringWidth() or 40) + 26)
			b:ClearAllPoints()
			b:SetWidth(w)
			b:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
			x = x + w + (opts.gap or 3)
		end
		strip.usedWidth = x
	end

	function strip:SetActive(index)
		for i, b in ipairs(buttons) do b:SetActive(i == index) end
	end

	strip.buttons = buttons
	strip:Layout()
	UI.Register(function()
		for _, b in ipairs(buttons) do b:SetActive(b.active) end
	end)
	return strip
end

-- ----------------------------------------------------------------------------
-- ScrollArea : zone defilable + barre fine maison + molette.
-- Renvoie scroll, content, stack.
-- ----------------------------------------------------------------------------
function UI.ScrollArea(parent, opts)
	opts = opts or {}
	local pad = opts.pad or UI.GRID.pad
	local padTop = opts.padTop or pad
	local barW = 5

	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetPoint("TOPLEFT", pad, -padTop)
	scroll:SetPoint("BOTTOMRIGHT", -(pad + barW + 5), pad)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(10, 10)
	scroll:SetScrollChild(content)

	local track = CreateFrame("Frame", nil, parent)
	track:SetWidth(barW)
	track:SetPoint("TOPRIGHT", -pad, -padTop)
	track:SetPoint("BOTTOMRIGHT", -pad, pad)
	UI.Fill(track, THEME.lineSoft)

	local thumb = CreateFrame("Button", nil, track)
	local thumbTex = UI.Fill(thumb, THEME.bronze, "ARTWORK")
	thumb:SetPoint("LEFT")
	thumb:SetPoint("RIGHT")
	thumb:SetHeight(30)

	local function UpdateThumb()
		local range = scroll:GetVerticalScrollRange() or 0
		local th = track:GetHeight() or 0
		if range <= 1 or th <= 0 then
			track:Hide()
			return
		end
		track:Show()
		local visible = scroll:GetHeight() or 1
		local total = visible + range
		local size = math.max(24, th * visible / total)
		thumb:SetHeight(size)
		local pos = (th - size) * ((scroll:GetVerticalScroll() or 0) / range)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -pos)
		thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -pos)
	end

	local function ScrollBy(delta)
		local range = scroll:GetVerticalScrollRange() or 0
		local v = (scroll:GetVerticalScroll() or 0) - delta * 34
		if v < 0 then v = 0 end
		if v > range then v = range end
		scroll:SetVerticalScroll(v)
	end

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
	scroll:SetScript("OnVerticalScroll", function()
		UpdateThumb()
		if opts.onScroll then opts.onScroll() end
	end)
	scroll:SetScript("OnScrollRangeChanged", UpdateThumb)
	scroll:SetScript("OnSizeChanged", function(self)
		content:SetWidth(math.max(10, self:GetWidth() or 10))
		UpdateThumb()
	end)

	local dragging, startY, startScroll
	thumb:SetScript("OnMouseDown", function()
		dragging = true
		local _, y = GetCursorPosition()
		startY = y
		startScroll = scroll:GetVerticalScroll() or 0
		thumbTex:SetColorTexture(unpackColor(THEME.gold))
	end)
	local function stopDrag()
		dragging = false
		thumbTex:SetColorTexture(unpackColor(THEME.bronze))
	end
	thumb:SetScript("OnMouseUp", stopDrag)
	thumb:SetScript("OnHide", stopDrag)
	thumb:SetScript("OnUpdate", function()
		if not dragging then return end
		local _, y = GetCursorPosition()
		local es = UIParent:GetEffectiveScale()
		if not es or es <= 0 then return end
		local th = track:GetHeight() or 0
		local range = scroll:GetVerticalScrollRange() or 0
		local denom = th - (thumb:GetHeight() or 0)
		if denom <= 0 or range <= 0 then return end
		local v = startScroll + ((startY - y) / es) * range / denom
		if v < 0 then v = 0 end
		if v > range then v = range end
		scroll:SetVerticalScroll(v)
	end)

	local stack = UI.Stack(content, {
		padX = 0, padTop = 0, padBottom = 6, spacing = opts.spacing or UI.GRID.section,
	})
	stack.onResize = function(h)
		content:SetHeight(math.max(1, h))
		local limit = math.max(0, h - (scroll:GetHeight() or 0))
		if (scroll:GetVerticalScroll() or 0) > limit then scroll:SetVerticalScroll(limit) end
		UpdateThumb()
	end
	stack:Reflow()

	scroll.stack = stack
	scroll.content = content
	scroll.UpdateThumb = UpdateThumb
	scroll.ScrollTop = function() scroll:SetVerticalScroll(0) end
	return scroll, content, stack
end

--- Multi-line text the player can select and copy; opts.editable also allows typing and pasting.
function UI.CopyBox(parent, opts)
	opts = opts or {}
	local box = { text = "" }
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -8, 6)
	scroll:EnableMouse(true)
	scroll:EnableMouseWheel(true)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetWidth(200)
	edit:SetHeight(20)
	if not pcall(edit.SetFontObject, edit, _G.GameFontHighlightSmall or _G.ChatFontNormal) then
		pcall(edit.SetFont, edit, "Fonts\\FRIZQT__.TTF", 11, "")
	end
	edit:SetTextColor(unpackColor(THEME.text))
	UI.Register(function() edit:SetTextColor(unpackColor(THEME.text)) end)
	scroll:SetScrollChild(edit)

	local function ScrollTo(v)
		local range = scroll:GetVerticalScrollRange() or 0
		scroll:SetVerticalScroll(math.max(0, math.min(range, v)))
	end
	scroll:SetScript("OnSizeChanged", function(self, w)
		edit:SetWidth(math.max(10, w or self:GetWidth() or 10))
	end)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		ScrollTo((scroll:GetVerticalScroll() or 0) - delta * 36)
	end)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		if opts.editable then
			box.text = self:GetText() or ""
			if opts.onChange then opts.onChange(box.text) end
		else
			self:SetText(box.text)
		end
	end)
	edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
		if type(y) ~= "number" or type(h) ~= "number" then return end
		local top, view = -y, scroll:GetHeight() or 0
		local at = scroll:GetVerticalScroll() or 0
		if top < at then ScrollTo(top)
		elseif top + h > at + view then ScrollTo(top + h - view) end
	end)

	function box.SetText(text)
		if text == box.text then return end
		box.text = text
		edit:SetText(text)
		scroll:SetVerticalScroll(0)
	end
	function box.GetText() return edit:GetText() or "" end
	function box.SelectAll()
		edit:SetFocus()
		edit:HighlightText()
	end
	function box.SetShown(v) scroll:SetShown(v) end
	function box.ClearFocus() edit:ClearFocus() end
	box.scroll, box.edit = scroll, edit
	return box
end

-- ----------------------------------------------------------------------------
-- Confirm : fenetre modale unique et reutilisee (aucune creation en boucle).
-- ----------------------------------------------------------------------------
local confirmFrame

function UI.Confirm(opts)
	if not confirmFrame then
		local f = CreateFrame("Frame", "ActionLiteConfirm", UIParent)
		f:SetSize(340, 136)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetPoint("CENTER", 0, 80)
		f:EnableMouse(true)
		UI.Fill(f, DERIVED.listBg)
		UI.Border(f, THEME.crimson)
		f:Hide()

		f.title = UI.Text(f, "GameFontNormal", THEME.gold)
		f.title:SetPoint("TOP", 0, -14)

		f.body = UI.Text(f, "GameFontHighlightSmall", THEME.textDim)
		f.body:SetPoint("TOPLEFT", 18, -40)
		f.body:SetPoint("TOPRIGHT", -18, -40)
		f.body:SetJustifyH("LEFT")

		f.accept = UI.Button(f, { label = AL.L("CONFIRM"), width = 140, height = 24, variant = "danger" })
		f.accept:SetPoint("BOTTOMLEFT", 18, 16)
		f.cancel = UI.Button(f, { label = AL.L("CANCEL"), width = 140, height = 24 })
		f.cancel:SetPoint("BOTTOMRIGHT", -18, 16)
		f.cancel:SetScript("OnClick", function() f:Hide() end)
		confirmFrame = f
	end

	local f = confirmFrame
	f.title:SetText(opts.title or "Confirmation")
	f.body:SetText(opts.text or "")
	f.cancel.text:SetText(AL.L("CANCEL"))
	f.accept.text:SetText(opts.accept or AL.L("CONFIRM"))
	f.accept:SetScript("OnClick", function()
		f:Hide()
		if opts.onAccept then opts.onAccept() end
	end)
	if opts.parent then
		f:SetParent(opts.parent)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:ClearAllPoints()
		f:SetPoint("CENTER", opts.parent, "CENTER", 0, 0)
	end
	f:Show()
	pcall(f.Raise, f)
	return f
end

-- ----------------------------------------------------------------------------
-- Aide : texture d'un sort, avec repli propre.
-- ----------------------------------------------------------------------------
function UI.SpellIcon(spell, fallbackSpell)
	if spell then
		local ok, tex = pcall(AL.SpellTexture, spell)
		if ok and tex then return tex end
	end
	-- Forever ne renvoie pas toujours la texture par nom avant apprentissage.
	-- L'ID de rang 1 fourni par la rotation garde alors la vraie icone visible.
	if fallbackSpell then
		local ok, tex = pcall(AL.SpellTexture, fallbackSpell)
		if ok and tex then return tex end
	end
	return QUESTION
end
