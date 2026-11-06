local ADDON, AL = ...

local UI = AL.UI
local THEME = UI.Theme
local DERIVED = UI.Derived
local GRID = UI.GRID

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DIGITS = "Fonts\\ARIALN.TTF"
local FRAME_NAME = "ActionLiteDebugFrame"

local W0, H0 = 900, 600
local MIN_W, MIN_H, MAX_W, MAX_H = 640, 400, 1400, 1000
local HEADER_H, FOOTER_H = 64, 22
local PAD = GRID.pad
local ROW_H, BUG_ROW_H, PROBE_ROW_H = 18, 36, 20
local REDRAW = 0.1
local STATE_EVERY = 0.5
local HINT_SECONDS = 5

local TABS = { "live", "errors", "state", "probe" }
local TAB_INDEX = { live = 1, errors = 2, state = 3, probe = 4 }
local TAB_LABEL = { live = "DEBUG_TAB_LIVE", errors = "DEBUG_TAB_ERRORS", state = "DEBUG_TAB_STATE", probe = "DEBUG_TAB_PROBE" }
local LEVEL_COLOR = { error = THEME.danger, warn = THEME.warn, info = THEME.text, debug = THEME.textDim, trace = THEME.textFaint }
local STATE_COLOR = { ok = THEME.ok, warn = THEME.warn, bad = THEME.danger, secret = THEME.gold, unknown = THEME.textFaint }
local PROBE_COLOR = { ok = THEME.ok, secret = THEME.gold, error = THEME.danger, ["nil"] = THEME.textFaint, missing = THEME.textDim }
local SOURCE_COLOR = { lua = THEME.danger, blocked = THEME.warn, forbidden = THEME.warn, warning = THEME.textDim }
local FALLBACK_RANK = { error = 1, warn = 2, info = 3, debug = 4, trace = 5 }
local FALLBACK_CATS = { "error", "addon", "cast", "combat", "rotation", "aura", "power", "event", "ui", "probe", "system" }

local function L(...) return AL.L(...) end

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function Key(v) if type(v) == "string" and Plain(v) then return v end end
local function Num(v) if type(v) == "number" and Plain(v) then return v end return 0 end

local function Call(name, ...)
	local D = AL.Debug
	local f = type(D) == "table" and D[name]
	if type(f) ~= "function" then return nil end
	local ok, a, b = pcall(f, ...)
	if ok then return a, b end
end

local function Escape(s)
	local r = Call("Escape", s)
	if type(r) == "string" then return r end
	return (s:gsub("|", "||"))
end

-- Engine strings are already safe; anything else goes through D.Safe first.
local function Str(v)
	if type(v) ~= "string" or not Plain(v) then
		local r = Call("Safe", v)
		if type(r) ~= "string" then
			if not Plain(v) then
				r = "<secret>"
			else
				local ok, t = pcall(tostring, v)
				r = ok and t or "?"
			end
		end
		v = r
	end
	return Escape(v)
end

local function FirstLine(s) return s:match("^[^\n]*") or s end

local memSettings = {}
local function Settings()
	local s = Call("Settings")
	if type(s) ~= "table" then s = memSettings end
	if type(s.hiddenCats) ~= "table" then s.hiddenCats = {} end
	if type(s.probe) ~= "table" then s.probe = {} end
	if type(s.level) ~= "number" then s.level = 5 end
	return s
end

local function Categories()
	local D = AL.Debug
	return type(D) == "table" and type(D.CATEGORIES) == "table" and D.CATEGORIES or FALLBACK_CATS
end

local function Ranks()
	local D = AL.Debug
	return type(D) == "table" and type(D.LEVEL_RANK) == "table" and D.LEVEL_RANK or FALLBACK_RANK
end

local function SessionErrors()
	local D = AL.Debug
	return Num(type(D) == "table" and D.sessionErrors)
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function Luminance(c)
	local function lin(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end

local win, tabStrip, sheet, footerLeft, footerRight
local current = "live"
local pages = {}
local live, errs, state, probe = {}, {}, {}, {}
local buttons = setmetatable({}, { __mode = "k" })
local dirty = { live = true, errors = true, errTab = true }
local paused, pausedNew = false, 0
local hintUntil = 0
local hookedD, opening = nil, false

local function ShowHint()
	hintUntil = GetTime() + HINT_SECONDS
	if footerRight then footerRight:SetText(L("DEBUG_COPY_HINT")) end
end

local function UpdateFooter()
	if not footerLeft then return end
	local D = AL.Debug
	footerLeft:SetText(L("DEBUG_FOOTER", Num(Call("Count")), SessionErrors(), Num(type(D) == "table" and D.session)))
	if hintUntil > 0 and GetTime() > hintUntil then
		hintUntil = 0
		footerRight:SetText("")
	end
end

local function PaintBadges()
	local n = SessionErrors()
	for b in pairs(buttons) do b:SetCount(n) end
end

local function PaintButtonsOpen(open)
	for b in pairs(buttons) do b:SetOpen(open) end
end

local function NoWrap(fs)
	fs:SetWordWrap(false)
	fs:SetJustifyH("LEFT")
	return fs
end

local function FitButton(b, minW, ...)
	local cur = b.text:GetText()
	local w = minW
	for i = 1, select("#", ...) do
		b.text:SetText(select(i, ...))
		w = math.max(w, (b.text:GetStringWidth() or 0) + 20)
	end
	b.text:SetText(cur)
	b:SetWidth(math.floor(w + 0.5))
end

local function CloseButton(parent, onClick)
	local close = CreateFrame("Button", nil, parent)
	close:SetSize(18, 18)
	local bg = UI.Fill(close, DERIVED.closeBg)
	local edge = UI.Border(close, THEME.crimson)
	local x = UI.Text(close, "GameFontNormalSmall", THEME.text)
	x:SetPoint("CENTER", 0, 0)
	x:SetText("X")
	close:SetScript("OnEnter", function()
		bg:SetColorTexture(UI.Color(THEME.danger))
		edge:SetColor(1, 0.6, 0.6, 1)
	end)
	close:SetScript("OnLeave", function()
		bg:SetColorTexture(UI.Color(DERIVED.closeBg))
		edge:SetColor(UI.Color(THEME.crimson))
	end)
	close:SetScript("OnClick", onClick)
	return close
end

-- UI.Check expects a stack; a one-item stack gives a free-standing check.
local function FreeCheck(parent, opts)
	local box = CreateFrame("Frame", nil, parent)
	box:SetHeight(GRID.rowSmall)
	local check = UI.Check(UI.Stack(box), opts)
	box.check = check
	function box:Fit()
		box:SetWidth(math.floor(25 + (check.label:GetStringWidth() or 0) + 14))
	end
	box:Fit()
	return box
end

local CopyBox = UI.CopyBox

-- Virtualised list: only the rows that fit are created, then reused on scroll.
local function VList(parent, rowH, make, draw, canFollow)
	local v = CreateFrame("Frame", nil, parent)
	v:EnableMouseWheel(true)
	v.rows, v.data, v.offset = {}, {}, 0
	v.follow = canFollow and true or false

	local track = CreateFrame("Frame", nil, v)
	track:SetWidth(5)
	track:SetPoint("TOPRIGHT")
	track:SetPoint("BOTTOMRIGHT")
	UI.Fill(track, THEME.lineSoft)
	local thumb = CreateFrame("Button", nil, track)
	local thumbTex = UI.Fill(thumb, THEME.bronze, "ARTWORK")

	function v:Visible() return math.max(1, math.floor((v:GetHeight() or 0) / rowH)) end
	function v:MaxOffset() return math.max(0, #v.data - v:Visible()) end

	local function UpdateThumb()
		local n, vis, th = #v.data, v:Visible(), v:GetHeight() or 0
		if n <= vis or th <= 0 then
			track:Hide()
			return
		end
		track:Show()
		local size = math.max(20, th * vis / n)
		local pos = (th - size) * v.offset / (n - vis)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -pos)
		thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -pos)
	end

	function v:Draw()
		local vis = v:Visible()
		for i = 1, vis do
			local r = v.rows[i]
			if not r then
				r = make(v)
				r:SetHeight(rowH)
				r:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -(i - 1) * rowH)
				r:SetPoint("TOPRIGHT", v, "TOPRIGHT", -9, -(i - 1) * rowH)
				v.rows[i] = r
			end
			local item = v.data[v.offset + i]
			if item ~= nil then
				draw(r, item, v.offset + i)
				r:Show()
			else
				r.item = nil
				r:Hide()
			end
		end
		for i = vis + 1, #v.rows do v.rows[i]:Hide() end
		UpdateThumb()
	end

	function v:SetOffset(o)
		local maxOff = v:MaxOffset()
		v.offset = Clamp(math.floor(o + 0.5), 0, maxOff)
		if canFollow then v.follow = v.offset >= maxOff end
		v:Draw()
		if v.onScroll then v.onScroll() end
	end

	function v:SetData(data)
		v.data = data
		if v.follow then v.offset = v:MaxOffset() else v.offset = Clamp(v.offset, 0, v:MaxOffset()) end
		v:Draw()
		if v.onScroll then v.onScroll() end
	end

	function v:Reveal(index)
		local vis = v:Visible()
		if index <= v.offset then v:SetOffset(index - 1)
		elseif index > v.offset + vis then v:SetOffset(index - vis) end
	end

	v:SetScript("OnMouseWheel", function(_, delta) v:SetOffset(v.offset - delta * 3) end)

	local dragY, dragOff
	thumb:SetScript("OnMouseDown", function()
		local _, y = GetCursorPosition()
		dragY, dragOff = y, v.offset
		thumbTex:SetColorTexture(UI.Color(THEME.gold))
	end)
	local function StopDrag()
		dragY = nil
		thumbTex:SetColorTexture(UI.Color(THEME.bronze))
	end
	thumb:SetScript("OnMouseUp", StopDrag)
	thumb:SetScript("OnHide", StopDrag)
	thumb:SetScript("OnUpdate", function()
		if not dragY then return end
		local _, y = GetCursorPosition()
		local es = v:GetEffectiveScale()
		local free = (v:GetHeight() or 0) - (thumb:GetHeight() or 0)
		if not es or es <= 0 or free <= 0 then return end
		v:SetOffset(dragOff + (dragY - y) / es / free * v:MaxOffset())
	end)
	return v
end

local function RowHighlight(r)
	r.sel = UI.Fill(r, DERIVED.checkOn, "BACKGROUND")
	r.sel:Hide()
	r.hl = UI.Fill(r, DERIVED.highlight, "BORDER")
	r.hl:Hide()
	r:SetScript("OnEnter", function() r.hl:Show() end)
	r:SetScript("OnLeave", function() r.hl:Hide() end)
end

local function EmptyText(parent, y)
	local fs = UI.Text(parent, "GameFontHighlight", THEME.textDim)
	fs:SetPoint("TOPLEFT", 20, y or -24)
	fs:SetPoint("TOPRIGHT", -20, y or -24)
	fs:SetJustifyH("CENTER")
	fs:Hide()
	return fs
end

local EnsureHooks

function AL.DebugButton(parent)
	EnsureHooks()
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(18, 18)
	local ring = b:CreateTexture(nil, "BACKGROUND")
	ring:SetAllPoints()
	ring:SetTexture(CIRCLE)
	local core = b:CreateTexture(nil, "ARTWORK")
	core:SetSize(12, 12)
	core:SetPoint("CENTER")
	core:SetTexture(CIRCLE)

	local glyph = {}
	local function Part(tex, w, h, x, y)
		local t = b:CreateTexture(nil, "OVERLAY")
		t:SetTexture(tex)
		t:SetSize(w, h)
		t:SetPoint("CENTER", x, y)
		glyph[#glyph + 1] = t
	end
	Part(CIRCLE, 4, 6, 0, -1)
	Part(CIRCLE, 3, 3, 0, 3)
	for _, y in ipairs({ 1, -1, -3 }) do
		Part(WHITE, 2, 1, -3, y)
		Part(WHITE, 2, 1, 3, y)
	end

	local badge = CreateFrame("Frame", nil, b)
	badge:SetHeight(11)
	badge:SetPoint("CENTER", b, "TOPRIGHT", -2, -2)
	badge:SetFrameLevel(b:GetFrameLevel() + 2)
	UI.Fill(badge, THEME.danger)
	UI.Border(badge, THEME.sidebar)
	local count = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if _G.SystemFont_Tiny then pcall(count.SetFontObject, count, _G.SystemFont_Tiny) end
	count:SetPoint("CENTER", 0, 0)
	badge:Hide()
	b.badge, b.badgeText = badge, count

	local hover, open = false, false
	local function Paint()
		ring:SetVertexColor(UI.Color((hover or open) and THEME.gold or THEME.bronze))
		core:SetVertexColor(UI.Color(THEME.surfaceAlt))
		for _, t in ipairs(glyph) do t:SetVertexColor(UI.Color(THEME.gold)) end
		local l = Luminance(THEME.danger)
		local ink = (l + 0.05) / 0.05 >= 1.05 / (l + 0.05) and 0 or 1
		count:SetTextColor(ink, ink, ink, 1)
	end
	function b:SetOpen(v)
		open = v and true or false
		Paint()
	end
	function b:SetCount(n)
		n = Num(n)
		b.alTipLines = { L("DEBUG_HELP") }
		if n <= 0 then
			badge:Hide()
			return
		end
		b.alTipLines[2] = L("DEBUG_ERRORS_BADGE", n)
		count:SetText(n > 99 and "99+" or tostring(n))
		badge:SetWidth(math.max(11, math.floor((count:GetStringWidth() or 6) + 6)))
		badge:Show()
	end
	b:SetScript("OnEnter", function() hover = true Paint() end)
	b:SetScript("OnLeave", function() hover = false Paint() end)
	b:SetScript("OnMouseDown", function() core:SetSize(11, 11) end)
	b:SetScript("OnMouseUp", function() core:SetSize(12, 12) end)
	b:SetScript("OnClick", function() AL.ToggleDebug() end)
	b:SetScript("OnShow", function() b:SetCount(SessionErrors()) end)
	UI.Tooltip(b, L("DEBUG"), { L("DEBUG_HELP") })
	UI.Register(Paint)
	buttons[b] = true
	Paint()
	b:SetOpen(win ~= nil and win:IsShown())
	b:SetCount(SessionErrors())
	return b
end

local function ShowSheet(text)
	if not sheet then return end
	sheet:Show()
	sheet.box.SetText(text)
	sheet.box.SelectAll()
	ShowHint()
end

local function BuildSheet()
	sheet = CreateFrame("Frame", nil, win)
	sheet:SetPoint("TOPLEFT", 2, -(HEADER_H + 2))
	sheet:SetPoint("BOTTOMRIGHT", -2, FOOTER_H + 2)
	sheet:SetFrameLevel(win:GetFrameLevel() + 40)
	sheet:EnableMouse(true)
	UI.Fill(sheet, DERIVED.listBg)
	local title = UI.Text(sheet, "GameFontNormal", THEME.gold)
	title:SetPoint("TOPLEFT", PAD, -14)
	title:SetText(L("DEBUG_COPY"))
	local close = CloseButton(sheet, function() sheet:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD, -10)
	local frame = CreateFrame("Frame", nil, sheet)
	frame:SetPoint("TOPLEFT", PAD, -38)
	frame:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	UI.Fill(frame, THEME.surface)
	UI.Border(frame, THEME.line)
	sheet.box = CopyBox(frame)
	sheet:SetScript("OnHide", function() sheet.box.ClearFocus() end)
	sheet:Hide()
end

local lowerCache = setmetatable({}, { __mode = "k" })

local function Lower(e)
	local s = lowerCache[e]
	if not s then
		s = Str(e.msg):lower()
		lowerCache[e] = s
	end
	return s
end

local function Matcher()
	local s = Settings()
	local maxRank, hidden, q = s.level, s.hiddenCats, live.query or ""
	local ranks = Ranks()
	return function(e)
		if type(e) ~= "table" then return false end
		local lvl, cat = Key(e.level), Key(e.cat)
		if (lvl and ranks[lvl] or 3) > maxRank then return false end
		if cat and hidden[cat] then return false end
		if q ~= "" and not Lower(e):find(q, 1, true) and not (cat and cat:find(q, 1, true)) then return false end
		return true
	end
end

local function BuildView()
	local out = {}
	local D = AL.Debug
	if type(D) ~= "table" or type(D.Get) ~= "function" then return out end
	local match = Matcher()
	pcall(function()
		for i = 1, Num(D.Count()) do
			local e = D.Get(i)
			if match(e) then out[#out + 1] = e end
		end
	end)
	return out
end

local function EntryText(e)
	local lvl = Key(e.level) or "info"
	local head = Str(e.clock or "") .. "   " .. lvl:upper() .. "   " .. Str(e.cat or "")
	if e.combat ~= nil then head = head .. "   " .. L(e.combat and "DEBUG_IN_COMBAT" or "DEBUG_OUT_COMBAT") end
	if Num(e.count) > 1 then head = head .. "   ×" .. Num(e.count) end
	local text = head .. "\n\n" .. Str(e.msg)
	if e.detail ~= nil then text = text .. "\n\n" .. Str(e.detail) end
	return text
end

local function MakeLiveRow(parent)
	local r = CreateFrame("Button", nil, parent)
	RowHighlight(r)
	r.clock = NoWrap(UI.Text(r, "GameFontNormalSmall", THEME.textFaint))
	pcall(r.clock.SetFont, r.clock, DIGITS, 11, "")
	r.clock:SetPoint("LEFT", 6, 0)
	r.clock:SetWidth(80)
	r.tag = NoWrap(UI.Text(r, "GameFontNormalSmall"))
	r.tag:SetPoint("LEFT", 90, 0)
	r.tag:SetWidth(100)
	r.count = UI.Text(r, "GameFontNormalSmall", THEME.textDim)
	r.count:SetWordWrap(false)
	r.count:SetJustifyH("RIGHT")
	r.count:SetPoint("RIGHT", -6, 0)
	r.count:SetWidth(44)
	r.msg = NoWrap(UI.Text(r, "GameFontHighlightSmall", THEME.text))
	r.msg:SetPoint("LEFT", 196, 0)
	r.msg:SetPoint("RIGHT", -54, 0)
	r:SetScript("OnClick", function(self) if self.item then live.Select(self.item) end end)
	return r
end

local function DrawLiveRow(r, e)
	r.item = e
	local lvl = Key(e.level) or "info"
	r.clock:SetText(Str(e.clock or ""))
	r.tag:SetText(lvl:upper() .. "  " .. Str(e.cat or ""))
	local selected = e == live.selected
	local tagColor = LEVEL_COLOR[lvl] or THEME.text
	if selected and tagColor == THEME.textFaint then tagColor = THEME.textDim end
	r.tag:SetTextColor(UI.Color(tagColor))
	r.clock:SetTextColor(UI.Color(selected and THEME.textDim or THEME.textFaint))
	r.msg:SetText(FirstLine(Str(e.msg)))
	local n = Num(e.count)
	r.count:SetText(n > 1 and ("×" .. n) or "")
	r.sel:SetShown(selected)
end

function live.Select(e)
	live.selected = e
	live.selectText:Hide()
	live.box.SetShown(true)
	live.box.SetText(EntryText(e))
	live.list:Draw()
end

local function PaintChip(c)
	local hidden = Settings().hiddenCats[c.cat]
	if hidden then
		c.bg:SetColorTexture(UI.Color(THEME.surface))
		c.edge:SetColor(UI.Color(c.hover and THEME.gold or THEME.line))
		c.mark:SetColorTexture(UI.Color(THEME.surface))
		c.markEdge:SetColor(UI.Color(THEME.textDim))
		c.label:SetTextColor(UI.Color(THEME.textDim))
	else
		c.bg:SetColorTexture(UI.Color(THEME.surfaceAlt))
		c.edge:SetColor(UI.Color(c.hover and THEME.gold or THEME.goldDim))
		c.mark:SetColorTexture(UI.Color(THEME.gold))
		c.markEdge:SetColor(UI.Color(THEME.gold))
		c.label:SetTextColor(UI.Color(THEME.text))
	end
end

function live.Refresh()
	dirty.live = false
	if not paused then live.view = BuildView() end
	local view = live.view or {}
	live.list:SetData(view)
	local total = Num(Call("Count"))
	if #view == 0 then
		live.empty:SetText(L(total == 0 and "DEBUG_EMPTY_LOG" or "DEBUG_NO_MATCH"))
		live.empty:Show()
	else
		live.empty:Hide()
	end
	live.status:SetText(paused and L("DEBUG_PAUSED", pausedNew) or "")
	live.pause.text:SetText(L(paused and "DEBUG_RESUME" or "DEBUG_PAUSE"))
	for _, c in ipairs(live.chips) do PaintChip(c) end
end

local function BuildLive(page)
	local sb = CreateFrame("Frame", nil, page)
	sb:SetHeight(22)
	UI.Fill(sb, THEME.surfaceAlt)
	local sEdge = UI.Border(sb, THEME.line)
	local placeholder = NoWrap(UI.Text(sb, "GameFontNormalSmall", THEME.textDim))
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetPoint("RIGHT", -8, 0)
	placeholder:SetText(L("DEBUG_SEARCH"))
	local search = CreateFrame("EditBox", nil, sb)
	search:SetPoint("TOPLEFT", 8, 0)
	search:SetPoint("BOTTOMRIGHT", -8, 0)
	search:SetAutoFocus(false)
	search:SetMaxLetters(64)
	if not pcall(search.SetFontObject, search, _G.ChatFontNormal or _G.GameFontHighlight) then
		pcall(search.SetFont, search, "Fonts\\FRIZQT__.TTF", 12, "")
	end
	search:SetTextColor(UI.Color(THEME.text))
	UI.Register(function() search:SetTextColor(UI.Color(THEME.text)) end)
	search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	search:SetScript("OnEditFocusGained", function() sEdge:SetColor(UI.Color(THEME.gold)) end)
	search:SetScript("OnEditFocusLost", function() sEdge:SetColor(UI.Color(THEME.line)) end)
	search:SetScript("OnTextChanged", function(self)
		local t = self:GetText() or ""
		placeholder:SetShown(t == "")
		live.query = t:lower()
		dirty.live = true
	end)
	live.search = search

	local levels = { { label = L("DEBUG_LEVEL_ALL"), value = 5 } }
	for rank = 4, 1, -1 do
		local lvl = ({ "error", "warn", "info", "debug" })[rank]
		levels[#levels + 1] = { label = L("DEBUG_LEVEL_" .. lvl), value = rank }
	end
	local dd = UI.Dropdown(page, {
		width = 150, height = 22, options = levels,
		get = function() return Settings().level end,
		set = function(v) Settings().level = v end,
		onSelect = function() dirty.live = true end,
	})

	live.pause = UI.Button(page, { label = L("DEBUG_PAUSE"), height = 22, onClick = function()
		paused = not paused
		pausedNew = 0
		live.Refresh()
	end })
	live.clear = UI.Button(page, { label = L("DEBUG_CLEAR"), height = 22, onClick = function()
		Call("Clear")
		live.selected, live.view, pausedNew = nil, {}, 0
		live.box.SetText("")
		live.box.SetShown(false)
		live.selectText:Show()
		live.Refresh()
	end })
	live.copy = UI.Button(page, { label = L("DEBUG_COPY"), height = 22, onClick = function()
		local text = Call("ExportLog", Matcher())
		ShowSheet(Str(type(text) == "string" and text or ""))
	end })
	live.copy:SetPoint("TOPRIGHT", -PAD, -10)
	live.clear:SetPoint("RIGHT", live.copy, "LEFT", -6, 0)
	live.pause:SetPoint("RIGHT", live.clear, "LEFT", -6, 0)
	dd:SetPoint("RIGHT", live.pause, "LEFT", -8, 0)
	sb:SetPoint("TOPLEFT", PAD, -10)
	sb:SetPoint("RIGHT", dd, "LEFT", -8, 0)

	live.chips = {}
	for _, cat in ipairs(Categories()) do
		local key = Key(cat)
		if key then
			local c = CreateFrame("Button", nil, page)
			c.cat = key
			c:SetHeight(20)
			c.bg = UI.Fill(c, THEME.surfaceAlt)
			c.edge = UI.Border(c, THEME.line)
			local m = CreateFrame("Frame", nil, c)
			m:SetSize(8, 8)
			m:SetPoint("LEFT", 7, 0)
			c.mark = UI.Fill(m, THEME.gold)
			c.markEdge = UI.Border(m, THEME.gold)
			c.label = NoWrap(UI.Text(c, "GameFontNormalSmall", THEME.text))
			c.label:SetPoint("LEFT", 20, 0)
			c.label:SetText(L("DEBUG_CAT_" .. key))
			c:SetScript("OnEnter", function() c.hover = true PaintChip(c) end)
			c:SetScript("OnLeave", function() c.hover = false PaintChip(c) end)
			c:SetScript("OnClick", function()
				local hidden = Settings().hiddenCats
				hidden[key] = not hidden[key] or nil
				PaintChip(c)
				dirty.live = true
			end)
			live.chips[#live.chips + 1] = c
		end
	end

	live.trace = FreeCheck(page, {
		label = L("DEBUG_TRACE_EVENTS"),
		tooltip = { L("DEBUG_TRACE_EVENTS"), L("DEBUG_TRACE_HELP") },
		get = function()
			local on = Call("IsTracingEvents")
			if on == nil then on = Settings().traceEvents end
			return on and true or false
		end,
		set = function(v) Call("SetTraceEvents", v and true or false) end,
	})
	live.trace:SetPoint("TOPRIGHT", -PAD, -38)

	live.list = VList(page, ROW_H, MakeLiveRow, DrawLiveRow, true)
	live.empty = EmptyText(live.list, -24)

	live.detail = CreateFrame("Frame", nil, page)
	live.detail:SetPoint("BOTTOMLEFT", PAD, PAD)
	live.detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	UI.Fill(live.detail, THEME.surface)
	UI.Border(live.detail, THEME.line)
	live.box = CopyBox(live.detail)
	live.box.SetShown(false)
	live.selectText = EmptyText(live.detail, -20)
	live.selectText:SetText(L("DEBUG_SELECT"))
	live.selectText:Show()

	local strip = CreateFrame("Frame", nil, page)
	strip:SetHeight(20)
	strip:SetPoint("BOTTOMLEFT", live.detail, "TOPLEFT", 0, 6)
	strip:SetPoint("BOTTOMRIGHT", live.detail, "TOPRIGHT", 0, 6)
	live.status = NoWrap(UI.Text(strip, "GameFontNormalSmall", THEME.warn))
	live.status:SetPoint("LEFT", 4, 0)
	live.status:SetPoint("RIGHT", -180, 0)
	live.jump = UI.Button(strip, { label = L("DEBUG_FOLLOW"), height = 20, variant = "primary", onClick = function()
		live.list.follow = true
		live.list:SetOffset(live.list:MaxOffset())
	end })
	live.jump:SetPoint("RIGHT", 0, 0)
	live.jump:Hide()
	live.list.onScroll = function()
		local l = live.list
		live.jump:SetShown(not l.follow and #l.data > l:Visible())
	end
end

function live.Layout(pw, ph)
	FitButton(live.copy, 60, L("DEBUG_COPY"))
	FitButton(live.clear, 70, L("DEBUG_CLEAR"))
	FitButton(live.pause, 70, L("DEBUG_PAUSE"), L("DEBUG_RESUME"))
	FitButton(live.jump, 110, L("DEBUG_FOLLOW"))
	live.trace:Fit()

	local avail = pw - 2 * PAD - (live.trace:GetWidth() or 150) - 12
	local x, y = 0, 0
	for _, c in ipairs(live.chips) do
		local w = math.floor((c.label:GetStringWidth() or 40) + 28)
		c:SetWidth(w)
		if x > 0 and x + w > avail then
			x, y = 0, y + 24
		end
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", PAD + x, -40 - y)
		x = x + w + 4
	end
	local top = 40 + math.max(y + 20, 24) + 8
	local dh = Clamp(math.floor(ph * 0.3), 84, 280)
	live.detail:SetHeight(dh)
	live.list:ClearAllPoints()
	live.list:SetPoint("TOPLEFT", PAD, -top)
	live.list:SetPoint("TOPRIGHT", -PAD, -top)
	live.list:SetHeight(math.max(ROW_H, ph - top - (PAD + dh + 6 + 20 + 6)))
end

local function ShortDate(s)
	s = Str(s or "")
	local today = date and date("%Y-%m-%d")
	if today and s:sub(1, #today) == today then return s:sub(#today + 2) end
	return s
end

local function MakeBugRow(parent)
	local r = CreateFrame("Button", nil, parent)
	RowHighlight(r)
	r.msg = NoWrap(UI.Text(r, "GameFontHighlightSmall", THEME.text))
	r.msg:SetPoint("TOPLEFT", 8, -4)
	r.msg:SetPoint("TOPRIGHT", -8, -4)
	r.info = NoWrap(UI.Text(r, "GameFontNormalSmall", THEME.textDim))
	r.info:SetPoint("TOPLEFT", 8, -19)
	r.info:SetPoint("TOPRIGHT", -8, -19)
	local line = r:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	UI.Tint(line, THEME.lineSoft)
	r:SetScript("OnClick", function(self) if self.index then errs.Select(self.index) end end)
	return r
end

local function DrawBugRow(r, bug, index)
	r.item, r.index = bug, index
	r.msg:SetText(FirstLine(Str(bug.message or "")))
	local src = Key(bug.source) or "lua"
	r.info:SetText("|c" .. UI.Hex(SOURCE_COLOR[src] or THEME.danger) .. L("DEBUG_SOURCE_" .. src) .. "|r   ×"
		.. Num(bug.count) .. "   " .. ShortDate(bug.last))
	r.sel:SetShown(bug == errs.selected)
end

local function BugText(bug)
	local text = Call("ExportBug", bug)
	if type(text) == "string" then return Str(text) end
	return Str(bug.message or "") .. "\n\nStack:\n" .. Str(bug.stack or "") .. "\n\nLocals:\n" .. Str(bug.locals or "")
end

local function ShowBug()
	local bug, n = errs.selected, #errs.bugs
	if not bug then return end
	errs.title:SetText(L("DEBUG_ERROR_OF", errs.index or 1, n))
	local src = Key(bug.source) or "lua"
	errs.source:SetBadge(L("DEBUG_SOURCE_" .. src), SOURCE_COLOR[src] or THEME.danger)
	errs.seen:SetText(L("DEBUG_SEEN", Num(bug.count)))
	local meta = {
		L("DEBUG_FIRST_SEEN") .. " " .. Str(bug.first or "?"),
		L("DEBUG_LAST_SEEN") .. " " .. Str(bug.last or "?"),
		L("DEBUG_SESSION", Num(bug.session)),
		L(bug.combat and "DEBUG_IN_COMBAT" or "DEBUG_OUT_COMBAT"),
		"v" .. Str(bug.version or "?") .. " · " .. Str(bug.build or "?"),
	}
	errs.meta:SetText(table.concat(meta, "   ·   "))
	errs.box.SetText(BugText(bug))
end

function errs.Select(index)
	local bug = errs.bugs[index]
	if not bug then return end
	errs.index, errs.selected = index, bug
	errs.list:Reveal(index)
	errs.list:Draw()
	ShowBug()
end

local function UpdateErrorsTab()
	dirty.errTab = false
	if not tabStrip then return end
	local bugs = Call("Bugs")
	local n = type(bugs) == "table" and #bugs or 0
	local label = tabStrip.buttons[TAB_INDEX.errors].label
	label:SetText(n > 0 and (L("DEBUG_TAB_ERRORS") .. " (" .. n .. ")") or L("DEBUG_TAB_ERRORS"))
	tabStrip:Layout()
end

function errs.Refresh()
	dirty.errors = false
	local bugs = Call("Bugs")
	if type(bugs) ~= "table" then bugs = {} end
	errs.bugs = bugs
	local sel, index = errs.selected, nil
	for i, b in ipairs(bugs) do
		if b == sel or (sel and type(b) == "table" and b.id ~= nil and b.id == sel.id) then
			index = i
			break
		end
	end
	if not index and #bugs > 0 then index = 1 end
	errs.index, errs.selected = index, bugs[index]
	local has = #bugs > 0
	errs.list:SetShown(has)
	errs.detail:SetShown(has)
	for _, b in ipairs(errs.actions) do b:SetShown(has) end
	errs.empty:SetShown(not has)
	errs.list:SetData(bugs)
	if index then errs.list:Reveal(index) end
	ShowBug()
end

local function BuildErrors(page)
	errs.bugs = {}
	errs.prev = UI.Button(page, { label = L("DEBUG_PREV"), height = 22, onClick = function()
		if errs.index and errs.index > 1 then errs.Select(errs.index - 1) end
	end })
	errs.next = UI.Button(page, { label = L("DEBUG_NEXT"), height = 22, onClick = function()
		if errs.index and errs.index < #errs.bugs then errs.Select(errs.index + 1) end
	end })
	errs.copy = UI.Button(page, { label = L("DEBUG_COPY"), height = 22, onClick = function()
		if not errs.selected then return end
		errs.box.SelectAll()
		ShowHint()
	end })
	errs.clear = UI.Button(page, { label = L("DEBUG_CLEAR_ERRORS"), height = 22, variant = "danger", onClick = function()
		UI.Confirm({
			title = L("DEBUG_CLEAR_ERRORS"),
			text = L("DEBUG_CLEAR_ERRORS_CONFIRM"),
			accept = L("DEBUG_CLEAR_ERRORS"),
			parent = win,
			onAccept = function()
				Call("ClearBugs")
				errs.selected = nil
				errs.Refresh()
				UpdateErrorsTab()
				PaintBadges()
			end,
		})
	end })
	errs.actions = { errs.prev, errs.next, errs.copy, errs.clear }
	errs.prev:SetPoint("TOPLEFT", PAD, -10)
	errs.next:SetPoint("LEFT", errs.prev, "RIGHT", 6, 0)
	errs.copy:SetPoint("LEFT", errs.next, "RIGHT", 6, 0)
	errs.clear:SetPoint("TOPRIGHT", -PAD, -10)

	errs.auto = FreeCheck(page, {
		label = L("DEBUG_AUTO_OPEN"),
		tooltip = { L("DEBUG_AUTO_OPEN"), L("DEBUG_AUTO_OPEN_HELP") },
		get = function() return Settings().autoOpen and true or false end,
		set = function(v) Settings().autoOpen = v and true or false end,
	})
	errs.auto:SetPoint("RIGHT", errs.clear, "LEFT", -12, 0)

	errs.list = VList(page, BUG_ROW_H, MakeBugRow, DrawBugRow, false)
	errs.list:SetPoint("TOPLEFT", PAD, -42)

	errs.detail = CreateFrame("Frame", nil, page)
	errs.detail:SetPoint("TOPLEFT", errs.list, "TOPRIGHT", 10, 0)
	errs.detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	UI.Fill(errs.detail, THEME.surface)
	UI.Border(errs.detail, THEME.line)
	errs.title = UI.Text(errs.detail, "GameFontNormal", THEME.gold)
	errs.title:SetPoint("TOPLEFT", 10, -10)
	errs.source = UI.Badge(errs.detail, { height = 18, minWidth = 40 })
	errs.source:SetPoint("LEFT", errs.title, "RIGHT", 10, 0)
	errs.seen = NoWrap(UI.Text(errs.detail, "GameFontNormalSmall", THEME.text))
	errs.seen:SetPoint("LEFT", errs.source, "RIGHT", 10, 0)
	errs.seen:SetPoint("RIGHT", errs.detail, "RIGHT", -10, 0)
	errs.meta = UI.Text(errs.detail, "GameFontNormalSmall", THEME.textDim)
	errs.meta:SetPoint("TOPLEFT", 10, -34)
	errs.meta:SetPoint("TOPRIGHT", -10, -34)
	errs.meta:SetJustifyH("LEFT")
	errs.meta:SetJustifyV("TOP")
	errs.meta:SetHeight(26)
	pcall(errs.meta.SetMaxLines, errs.meta, 2)
	local boxFrame = CreateFrame("Frame", nil, errs.detail)
	boxFrame:SetPoint("TOPLEFT", 6, -66)
	boxFrame:SetPoint("BOTTOMRIGHT", -6, 6)
	UI.Fill(boxFrame, THEME.surfaceAlt)
	errs.box = CopyBox(boxFrame)

	errs.empty = EmptyText(page, -80)
	errs.empty:SetText(L("DEBUG_NO_ERRORS"))
end

function errs.Layout(pw, ph)
	FitButton(errs.prev, 70, L("DEBUG_PREV"))
	FitButton(errs.next, 70, L("DEBUG_NEXT"))
	FitButton(errs.copy, 60, L("DEBUG_COPY"))
	FitButton(errs.clear, 90, L("DEBUG_CLEAR_ERRORS"))
	errs.auto:Fit()
	errs.list:SetWidth(Clamp(math.floor(pw * 0.34), 220, 380))
	errs.list:SetHeight(math.max(BUG_ROW_H, ph - 42 - PAD))
end

local function Field(row, name, index)
	local v = row[name]
	if v == nil then v = row[index] end
	return v
end

function state.Refresh()
	state.acc = 0
	local snap = Call("Snapshot")
	if type(snap) ~= "table" then snap = {} end
	local count = 0
	for i, sec in ipairs(snap) do
		if type(sec) == "table" then
			count = i
			local card = state.cards[i]
			if not card then
				card = UI.Card(state.stack, "")
				card.rows = {}
				state.cards[i] = card
			end
			if not card:IsShown() then state.stack:SetItemShown(card, true) end
			card.title:SetText(L(Key(sec.key) or "DEBUG_TAB_STATE"))
			local cst = UI.HostStack(card)
			local rows = type(sec.rows) == "table" and sec.rows or {}
			local n = 0
			for j, row in ipairs(rows) do
				if type(row) == "table" then
					n = j
					local r = card.rows[j]
					if not r then
						r = CreateFrame("Frame", nil, cst.frame)
						r.label = NoWrap(UI.Text(r, "GameFontNormalSmall", THEME.textDim))
						r.label:SetPoint("LEFT", 6, 0)
						r.label:SetPoint("RIGHT", r, "CENTER", -30, 0)
						r.value = UI.Text(r, "GameFontHighlightSmall")
						r.value:SetWordWrap(false)
						r.value:SetJustifyH("RIGHT")
						r.value:SetPoint("LEFT", r, "CENTER", -20, 0)
						r.value:SetPoint("RIGHT", -6, 0)
						r:EnableMouse(true)
						UI.Tooltip(r, "", {})
						cst:Add(r, 18, { gap = 1 })
						card.rows[j] = r
					end
					if not r:IsShown() then cst:SetItemShown(r, true) end
					local label, value = Str(Field(row, "label", 1)), Str(Field(row, "value", 2))
					r.label:SetText(label)
					r.value:SetText(value)
					r.alTipTitle, r.alTipLines = label, { value }
					local status = Key(Field(row, "status", 3))
					r.value:SetTextColor(UI.Color(status and STATE_COLOR[status] or THEME.text))
				end
			end
			for j = n + 1, #card.rows do
				if card.rows[j]:IsShown() then cst:SetItemShown(card.rows[j], false) end
			end
		end
	end
	for i = count + 1, #state.cards do
		if state.cards[i]:IsShown() then state.stack:SetItemShown(state.cards[i], false) end
	end
end

local function BuildState(page)
	state.cards = {}
	state.acc = 0
	local scroll, _, stack = UI.ScrollArea(page, { pad = PAD, padTop = 12 })
	state.scroll, state.stack = scroll, stack
	page:SetScript("OnUpdate", function(_, dt)
		state.acc = state.acc + dt
		if state.acc >= STATE_EVERY then state.Refresh() end
	end)
end

local function ProbeRuns()
	local p = Settings().probe
	local ooc = type(p.ooc) == "table" and p.ooc or nil
	local combat = type(p.combat) == "table" and p.combat or nil
	return ooc, combat
end

local function ProbeRows()
	local rows, byApi = {}, {}
	local ooc, combat = ProbeRuns()
	for _, pair in ipairs({ { "ooc", ooc }, { "combat", combat } }) do
		local which, run = pair[1], pair[2]
		if run and type(run.results) == "table" then
			for _, r in ipairs(run.results) do
				local api = type(r) == "table" and Key(r.api)
				if api then
					local row = byApi[api]
					if not row then
						row = { api = api }
						byApi[api] = row
						rows[#rows + 1] = row
					end
					row[which] = r
				end
			end
		end
	end
	return rows
end

local function ProbeCell(result)
	if not result then return "-", THEME.textFaint, nil end
	local status = Key(Field(result, "status", 1)) or "nil"
	return L("DEBUG_STATUS_" .. status), PROBE_COLOR[status] or THEME.text, Str(Field(result, "value", 2))
end

local function PlaceProbeRow(r)
	r.api:SetWidth(math.max(40, probe.apiW - 8))
	r.ooc:ClearAllPoints()
	r.ooc:SetPoint("TOPLEFT", probe.apiW, 0)
	r.ooc:SetSize(probe.colW, PROBE_ROW_H)
	r.combat:ClearAllPoints()
	r.combat:SetPoint("TOPLEFT", probe.apiW + probe.colW, 0)
	r.combat:SetSize(probe.colW, PROBE_ROW_H)
end

local function MakeProbeRow(parent)
	local r = CreateFrame("Frame", nil, parent)
	r.api = NoWrap(UI.Text(r, "GameFontHighlightSmall", THEME.text))
	r.api:SetPoint("LEFT", 6, 0)
	local function Cell()
		local c = CreateFrame("Button", nil, r)
		c.hl = UI.Fill(c, DERIVED.highlight)
		c.hl:Hide()
		c.text = NoWrap(UI.Text(c, "GameFontNormalSmall"))
		c.text:SetPoint("LEFT", 6, 0)
		c.text:SetPoint("RIGHT", -6, 0)
		c:SetScript("OnEnter", function() c.hl:Show() end)
		c:SetScript("OnLeave", function() c.hl:Hide() end)
		UI.Tooltip(c, "", {})
		c.alTipTitle = nil
		return c
	end
	r.ooc, r.combat = Cell(), Cell()
	local line = r:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	UI.Tint(line, THEME.lineSoft)
	PlaceProbeRow(r)
	return r
end

local function DrawProbeRow(r, row)
	r.item = row
	r.api:SetText(Str(row.api))
	for _, which in ipairs({ "ooc", "combat" }) do
		local cell = r[which]
		local label, color, value = ProbeCell(row[which])
		cell.text:SetText(label)
		cell.text:SetTextColor(UI.Color(color))
		cell.alTipTitle = value and Str(row.api) or nil
		cell.alTipLines = value and { value } or nil
	end
end

local function RunHeader(key, run)
	local text = L(key)
	if run and run.clock ~= nil then
		text = text .. "  |c" .. UI.Hex(THEME.textDim) .. Str(run.clock) .. "|r"
	end
	return text
end

function probe.Refresh()
	local rows = ProbeRows()
	local ooc, combat = ProbeRuns()
	probe.headOoc:SetText(RunHeader("DEBUG_PROBE_OOC", ooc))
	probe.headCombat:SetText(RunHeader("DEBUG_PROBE_COMBAT", combat))
	local has = #rows > 0
	probe.head:SetShown(has)
	probe.list:SetShown(has)
	probe.empty:SetShown(not has)
	probe.copy:SetShown(has)
	probe.list:SetData(rows)
end

local function ProbeExport()
	local ooc, combat = ProbeRuns()
	local lines = { L("DEBUG_PROBE_API") .. " | " .. L("DEBUG_PROBE_OOC") .. " " .. Str(ooc and ooc.clock or "-")
		.. " | " .. L("DEBUG_PROBE_COMBAT") .. " " .. Str(combat and combat.clock or "-") }
	for _, row in ipairs(ProbeRows()) do
		local parts = { Str(row.api) }
		for _, which in ipairs({ "ooc", "combat" }) do
			local label, _, value = ProbeCell(row[which])
			parts[#parts + 1] = value and (label .. ": " .. value) or label
		end
		lines[#lines + 1] = table.concat(parts, " | ")
	end
	return table.concat(lines, "\n")
end

local function BuildProbe(page)
	probe.apiW, probe.colW = 300, 200
	probe.help = UI.Text(page, "GameFontHighlightSmall", THEME.textDim)
	probe.help:SetPoint("TOPLEFT", PAD, -12)
	probe.help:SetJustifyH("LEFT")
	probe.help:SetText(L("DEBUG_PROBE_HELP"))
	probe.run = UI.Button(page, { label = L("DEBUG_PROBE_RUN"), height = 22, variant = "primary", onClick = function()
		Call("RunProbe")
		dirty.live = true
		probe.Refresh()
	end })
	probe.copy = UI.Button(page, { label = L("DEBUG_COPY"), height = 22, onClick = function()
		ShowSheet(ProbeExport())
	end })
	probe.copy:SetPoint("LEFT", probe.run, "RIGHT", 6, 0)

	probe.head = CreateFrame("Frame", nil, page)
	probe.head:SetHeight(20)
	UI.Fill(probe.head, THEME.surfaceAlt)
	local function Head()
		return NoWrap(UI.Text(probe.head, "GameFontNormalSmall", THEME.gold))
	end
	probe.headApi, probe.headOoc, probe.headCombat = Head(), Head(), Head()
	probe.headApi:SetText(L("DEBUG_PROBE_API"))

	probe.list = VList(page, PROBE_ROW_H, MakeProbeRow, DrawProbeRow, false)
	probe.empty = EmptyText(page)
	probe.empty:SetText(L("DEBUG_PROBE_EMPTY"))
end

function probe.Layout(pw, ph)
	local inner = pw - 2 * PAD
	probe.help:SetWidth(inner)
	FitButton(probe.run, 100, L("DEBUG_PROBE_RUN"))
	FitButton(probe.copy, 60, L("DEBUG_COPY"))
	local helpH = math.max(14, math.floor((probe.help:GetStringHeight() or 14) + 0.5))
	local by = 12 + helpH + 10
	probe.run:ClearAllPoints()
	probe.run:SetPoint("TOPLEFT", PAD, -by)
	local hy = by + 22 + 14
	probe.head:ClearAllPoints()
	probe.head:SetPoint("TOPLEFT", PAD, -hy)
	probe.head:SetPoint("TOPRIGHT", -PAD, -hy)
	probe.empty:ClearAllPoints()
	probe.empty:SetPoint("TOPLEFT", PAD + 20, -(hy + 24))
	probe.empty:SetPoint("TOPRIGHT", -(PAD + 20), -(hy + 24))

	probe.apiW = math.floor((inner - 9) * 0.4)
	probe.colW = math.floor((inner - 9 - probe.apiW) / 2)
	probe.headApi:SetPoint("LEFT", 6, 0)
	probe.headApi:SetWidth(probe.apiW - 8)
	probe.headOoc:SetPoint("LEFT", probe.apiW + 6, 0)
	probe.headOoc:SetWidth(probe.colW - 12)
	probe.headCombat:SetPoint("LEFT", probe.apiW + probe.colW + 6, 0)
	probe.headCombat:SetWidth(probe.colW - 12)

	local ly = hy + 22
	probe.list:ClearAllPoints()
	probe.list:SetPoint("TOPLEFT", PAD, -ly)
	probe.list:SetPoint("TOPRIGHT", -PAD, -ly)
	probe.list:SetHeight(math.max(PROBE_ROW_H, ph - ly - PAD))
	for _, r in ipairs(probe.list.rows) do PlaceProbeRow(r) end
end

local function RefreshTab(key)
	if key == "live" then live.Refresh()
	elseif key == "errors" then errs.Refresh()
	elseif key == "state" then state.Refresh()
	elseif key == "probe" then probe.Refresh() end
end

local function ShowTab(key)
	if not TAB_INDEX[key] then key = "live" end
	current = key
	Settings().tab = key
	for k, page in pairs(pages) do page:SetShown(k == key) end
	tabStrip:SetActive(TAB_INDEX[key])
	sheet:Hide()
	RefreshTab(key)
end

local function Layout()
	if not win then return end
	local pw = (win:GetWidth() or W0) - 4
	local ph = (win:GetHeight() or H0) - HEADER_H - FOOTER_H - 4
	live.Layout(pw, ph)
	errs.Layout(pw, ph)
	probe.Layout(pw, ph)
	for _, l in ipairs({ live.list, errs.list, probe.list }) do l:SetData(l.data) end
end

local function SavePos()
	if not win then return end
	local point, _, relPoint, x, y = win:GetPoint()
	if not point then return end
	Settings().window = { point = point, relPoint = relPoint, x = x, y = y, w = win:GetWidth(), h = win:GetHeight() }
end

local function RestorePos()
	local p = Settings().window
	win:ClearAllPoints()
	if type(p) == "table" and type(p.point) == "string" and type(p.x) == "number" and type(p.y) == "number" then
		win:SetPoint(p.point, UIParent, type(p.relPoint) == "string" and p.relPoint or p.point, p.x, p.y)
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
	local w = type(p) == "table" and tonumber(p.w) or W0
	local h = type(p) == "table" and tonumber(p.h) or H0
	win:SetSize(Clamp(w, MIN_W, MAX_W), Clamp(h, MIN_H, MAX_H))
end

local function Build()
	win = CreateFrame("Frame", FRAME_NAME, UIParent)
	win:Hide()
	win:SetFrameStrata("DIALOG")
	pcall(win.SetToplevel, win, true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:SetResizable(true)
	if not pcall(win.SetResizeBounds, win, MIN_W, MIN_H, MAX_W, MAX_H) then
		pcall(win.SetMinResize, win, MIN_W, MIN_H)
		pcall(win.SetMaxResize, win, MAX_W, MAX_H)
	end
	UI.Fill(win, THEME.shell)
	UI.Border(win, DERIVED.frameEdge)
	local inner = CreateFrame("Frame", nil, win)
	inner:SetPoint("TOPLEFT", 1, -1)
	inner:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Border(inner, { 0, 0, 0, 0.9 })
	tinsert(UISpecialFrames, FRAME_NAME)

	local header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT", 2, -2)
	header:SetPoint("TOPRIGHT", -2, -2)
	header:SetHeight(HEADER_H)
	UI.Fill(header, THEME.sidebar)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() win:StartMoving() end)
	header:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		SavePos()
	end)
	local headerLine = header:CreateTexture(nil, "OVERLAY")
	headerLine:SetHeight(1)
	headerLine:SetPoint("BOTTOMLEFT")
	headerLine:SetPoint("BOTTOMRIGHT")
	UI.Tint(headerLine, THEME.bronze, 0.55)

	local title = UI.Text(header, "GameFontNormalLarge", THEME.gold)
	title:SetPoint("TOP", 0, -8)
	local function PaintTitle()
		local g = THEME.gold
		title:SetText("|c" .. UI.Hex({ g[1] * 0.9, g[2] * 0.9, g[3] * 0.9 }) .. "Action|r|c" .. UI.Hex(g) .. "LITE|r  |c"
			.. UI.Hex(THEME.textDim) .. L("DEBUG_TITLE") .. "|r")
	end
	PaintTitle()
	UI.Register(PaintTitle)

	local close = CloseButton(header, function() win.AnimateClose() end)
	close:SetPoint("TOPRIGHT", -8, -7)

	local defs = {}
	for i, key in ipairs(TABS) do
		defs[i] = { label = L(TAB_LABEL[key]), onClick = function() ShowTab(key) end }
	end
	tabStrip = UI.Tabs(header, defs, { minWidth = 90 })
	tabStrip:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 0)
	tabStrip:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 0)

	for _, key in ipairs(TABS) do
		local page = CreateFrame("Frame", nil, win)
		page:SetPoint("TOPLEFT", 2, -(HEADER_H + 2))
		page:SetPoint("BOTTOMRIGHT", -2, FOOTER_H + 2)
		page:Hide()
		pages[key] = page
	end
	BuildLive(pages.live)
	BuildErrors(pages.errors)
	BuildState(pages.state)
	BuildProbe(pages.probe)

	local footer = CreateFrame("Frame", nil, win)
	footer:SetPoint("BOTTOMLEFT", 2, 2)
	footer:SetPoint("BOTTOMRIGHT", -2, 2)
	footer:SetHeight(FOOTER_H)
	UI.Fill(footer, THEME.sidebar)
	local footerLine = footer:CreateTexture(nil, "OVERLAY")
	footerLine:SetHeight(1)
	footerLine:SetPoint("TOPLEFT")
	footerLine:SetPoint("TOPRIGHT")
	UI.Tint(footerLine, THEME.line)
	footerLeft = NoWrap(UI.Text(footer, "GameFontNormalSmall", THEME.textDim))
	footerLeft:SetPoint("LEFT", 12, 0)
	footerLeft:SetPoint("RIGHT", footer, "CENTER", 60, 0)
	footerRight = UI.Text(footer, "GameFontNormalSmall", THEME.gold)
	footerRight:SetWordWrap(false)
	footerRight:SetJustifyH("RIGHT")
	footerRight:SetPoint("LEFT", footer, "CENTER", 70, 0)
	footerRight:SetPoint("RIGHT", -26, 0)

	BuildSheet()

	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(win:GetFrameLevel() + 50)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	local sizing = false
	local function StopSizing()
		if not sizing then return end
		sizing = false
		win:StopMovingOrSizing()
		SavePos()
	end
	grip:SetScript("OnMouseDown", function()
		sizing = true
		win:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", StopSizing)
	grip:SetScript("OnHide", StopSizing)

	local openAnim = win:CreateAnimationGroup()
	local openFade = openAnim:CreateAnimation("Alpha")
	openFade:SetFromAlpha(0)
	openFade:SetToAlpha(1)
	openFade:SetDuration(0.14)
	openFade:SetSmoothing("OUT")
	local closeAnim = win:CreateAnimationGroup()
	local closeFade = closeAnim:CreateAnimation("Alpha")
	closeFade:SetFromAlpha(1)
	closeFade:SetToAlpha(0)
	closeFade:SetDuration(0.10)
	closeFade:SetSmoothing("OUT")
	closeAnim:SetScript("OnFinished", function()
		win:Hide()
		win:SetAlpha(1)
	end)
	function win.AnimateOpen()
		closeAnim:Stop()
		win:SetAlpha(1)
		win:Show()
		openAnim:Play()
	end
	function win.AnimateClose()
		if closeAnim:IsPlaying() then return end
		openAnim:Stop()
		closeAnim:Play()
	end

	local acc = 0
	win:SetScript("OnUpdate", function(_, dt)
		acc = acc + dt
		if acc < REDRAW then return end
		acc = 0
		if not hookedD then dirty.live, dirty.errors, dirty.errTab = true, true, true end
		if dirty.errTab then UpdateErrorsTab() end
		if current == "live" and dirty.live then live.Refresh() end
		if current == "errors" and dirty.errors then errs.Refresh() end
		UpdateFooter()
	end)
	win:SetScript("OnShow", function()
		PaintButtonsOpen(true)
		UpdateErrorsTab()
		UpdateFooter()
	end)
	win:SetScript("OnHide", function()
		PaintButtonsOpen(false)
		pcall(live.search.ClearFocus, live.search)
		live.box.ClearFocus()
		errs.box.ClearFocus()
	end)
	win:SetScript("OnSizeChanged", Layout)

	UI.Register(function()
		if not win or not win:IsShown() then return end
		RefreshTab(current)
		UpdateFooter()
	end)

	RestorePos()
	Layout()
end

local function OnLog(entry)
	dirty.live = true
	if paused and type(entry) == "table" and entry.count == 1 then pausedNew = pausedNew + 1 end
end

local lastNotice = -math.huge
local function OnBug(bug, isNew)
	dirty.errors, dirty.errTab = true, true
	PaintBadges()
	if not isNew or type(bug) ~= "table" or opening then return end
	if not Settings().autoOpen then
		local now = GetTime()
		if AL.Say and type(bug.message) == "string" and now - lastNotice > 10 then
			lastNotice = now
			local first = bug.message:match("^[^\n]*") or ""
			if #first > 120 then first = first:sub(1, 117) .. "..." end
			pcall(AL.Say, L("DEBUG_NEW_ERROR", "|cffff6060" .. first:gsub("|", "||") .. "|r"))
		end
		return
	end
	opening = true
	errs.selected = bug
	pcall(AL.OpenDebug, "errors")
	opening = false
end

-- A new AL.Debug table (engine reload, tests) gets fresh listeners.
EnsureHooks = function()
	local D = AL.Debug
	if type(D) ~= "table" or D == hookedD then return end
	if type(D.OnLog) ~= "function" or type(D.OnBug) ~= "function" then return end
	hookedD = D
	pcall(D.OnLog, function(entry) if hookedD == D then OnLog(entry) end end)
	pcall(D.OnBug, function(bug, isNew) if hookedD == D then OnBug(bug, isNew) end end)
end

function AL.OpenDebug(tab)
	EnsureHooks()
	if not win then
		local ok, err = pcall(Build)
		if not ok then
			if win then win:Hide() end
			win = nil
			print("|cff89cff0ActionLITE|r: |cffbf5c5c" .. L("INTERFACE_ERROR") .. "|r " .. tostring(err))
			return
		end
	end
	if not win:IsShown() then win.AnimateOpen() end
	local key = TAB_INDEX[tab] and tab or Settings().tab
	ShowTab(TAB_INDEX[key] and key or current)
	pcall(win.Raise, win)
end

function AL.ToggleDebug(tab)
	if win and win:IsShown() and (tab == nil or tab == current) then
		win.AnimateClose()
	else
		AL.OpenDebug(tab)
	end
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function()
	EnsureHooks()
	PaintBadges()
end)
EnsureHooks()
