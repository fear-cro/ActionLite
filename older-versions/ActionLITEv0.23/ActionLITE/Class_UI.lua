local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - Class_UI.lua - v0.9.1
-- ----------------------------------------------------------------------------
-- Constructeur commun des interfaces de classe declaratives.
-- Chaque <Class>_UI.lua ne contient que la structure propre a sa rotation :
-- cartes, options, sorts et listes deroulantes. Les controles ecrivent
-- directement dans le profil selectionne, lu ensuite par la rotation.
-- ============================================================================

local function Text(value)
	if type(value) ~= "table" then return tostring(value or "") end
	local language = AL.GetUILanguage and AL.GetUILanguage() or "en"
	return value[language] or value.en or value.fr or ""
end

local function SpellMap(rotation)
	local map = {}
	for _, entry in ipairs((rotation and rotation.spells) or {}) do
		map[entry[2]] = entry[1]
	end
	return map
end

local function KnownSpells(rotation)
	local known, total = 0, 0
	for _, entry in ipairs((rotation and rotation.spells) or {}) do
		total = total + 1
		if AL.known and AL.known[entry[2]] then known = known + 1 end
	end
	return known, total
end

local function BuildControl(card, control, ui, spellIDs)
	if control.type == "slider" then
		return ui.Slider(card, {
			profileKey = control.key,
			label = Text(control.label),
			min = control.min,
			max = control.max,
			step = control.step or 1,
			suffix = Text(control.suffix),
			half = control.half,
			format = control.format,
			get = function()
				local value = tonumber(ui.Profile()[control.key])
				return value or control.default or control.min
			end,
			set = function(value) ui.Profile()[control.key] = value end,
			tooltip = control.tooltip and {
				Text(control.tooltip[1]), Text(control.tooltip[2]),
			} or nil,
		})
	end

	if control.type == "dropdown" then
		local options = {}
		for i, option in ipairs(control.options or {}) do
			options[i] = { label = Text(option.label), value = option.value }
		end
		return ui.StackDropdown(card, {
			profileKey = control.key,
			caption = Text(control.label),
			options = options,
			get = function()
				local value = ui.Profile()[control.key]
				return value or control.default
			end,
			set = function(value) ui.Profile()[control.key] = value end,
			onSelect = ui.Repaint,
			half = control.half,
		})
	end

	if control.type == "info" then
		return ui.Info(card, Text(control.text))
	end

	if control.type == "dynamic_info" then
		local row = ui.Info(card, "")
		local elapsed = 0

		local function Refresh()
			local value = ""
			if type(control.getText) == "function" then
				local ok, result = pcall(control.getText)
				if ok then
					value = tostring(result or "")
				else
					value = "unavailable"
				end
			else
				value = Text(control.text)
			end
			row:SetText(value)
		end

		row:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed < (control.interval or 0.20) then return end
			elapsed = 0
			Refresh()
		end)

		Refresh()
		return row
	end

	local icon
	if control.spell then
		icon = ui.SpellIcon(control.spell, spellIDs[control.spell])
	end
	return ui.SettingCheck(card, control.key, {
		label = Text(control.label or control.spell or control.key),
		icon = icon,
		half = control.half ~= false,
		onChange = control.onChange,
		tooltip = control.tooltip and {
			Text(control.tooltip[1]), Text(control.tooltip[2]),
		} or nil,
	})
end

function AL.RegisterSimpleClassUI(token, config, version)
	if type(token) ~= "string" or type(config) ~= "table" then return end
	if type(AL.RegisterClassUI) ~= "function" then return end

	AL.RegisterClassUI(token, function(page, ui)
		local rotation = AL.rotations and AL.rotations[token]
		local spellIDs = SpellMap(rotation)
		local stack = ui.Body(page)
		local theme = ui.Theme
		local steel = { 0.72, 0.62, 0.50, 1 }

		local head = ui.Card(stack, Text(config.title), Text(config.subtitle))
		local rowA = ui.BadgeRow(head, 3)
		local rowB = ui.BadgeRow(head, 2)
		local badges = {
			level = rowA.badges[1],
			spells = rowA.badges[2],
			state = rowA.badges[3],
			aoe = rowB.badges[1],
			burst = rowB.badges[2],
		}

		for _, cardDef in ipairs(config.cards or {}) do
			local card = ui.Card(stack, Text(cardDef.title), Text(cardDef.subtitle))
			for _, control in ipairs(cardDef.controls or {}) do
				BuildControl(card, control, ui, spellIDs)
			end
		end

		local linkCard = ui.Card(stack,
			Text({ en = "ROTATION LINK", fr = "LIAISON ROTATION", pt = "VÍNCULO DA ROTAÇÃO", es = "VÍNCULO DE ROTACIÓN", de = "ROTATIONS-LINK", zh = "循环联动" }))
		ui.Info(linkCard, Text({
			en = "Every control on this page writes directly to this class profile. The combat rotation reads the same values.",
			fr = "Chaque controle de cette page ecrit directement dans le profil de cette classe. La rotation de combat lit les memes valeurs.",
			pt = "Cada controle desta página grava diretamente no perfil desta classe. A rotação de combate lê os mesmos valores.",
			es = "Cada control de esta página escribe directamente en el perfil de esta clase. La rotación de combate lee los mismos valores.",
			de = "Jede Einstellung auf dieser Seite schreibt direkt in dieses Klassenprofil. Die Kampfrotation liest dieselben Werte.",
			zh = "本页的每个控件都直接写入该职业配置。战斗循环读取相同的数值。",
		}))

		local last = {}
		local function SetBadge(key, value, color)
			if last[key] == value then return end
			last[key] = value
			badges[key]:SetBadge(value, color)
		end

		local function Paint()
			local profile = ui.Profile()
			local known, total = KnownSpells(rotation)
			local level = UnitLevel and UnitLevel("player") or "?"
			SetBadge("level", AL.L("LEVEL") .. " " .. tostring(level), steel)
			SetBadge("spells", tostring(known) .. "/" .. tostring(total) .. " " .. AL.L("SPELLS"):upper(), steel)
			SetBadge("state", rotation and AL.L("ROTATION_LOADED") or AL.L("NO_ROTATION"),
				rotation and theme.ok or theme.danger)
			if config.aoeKey then
				SetBadge("aoe", profile[config.aoeKey] and AL.L("AOE_ON") or AL.L("AOE_OFF"),
					profile[config.aoeKey] and theme.ok or theme.textFaint)
			else
				SetBadge("aoe", Text({ en = "SINGLE TARGET", fr = "CIBLE UNIQUE", pt = "ALVO ÚNICO", es = "OBJETIVO ÚNICO", de = "EINZELZIEL", zh = "单体目标" }), theme.textFaint)
			end
			SetBadge("burst", AL.burst and AL.L("BURST_ON") or AL.L("BURST_OFF"),
				AL.burst and theme.gold or theme.textFaint)
			rowA:Layout()
			rowB:Layout()
		end

		ui.Paint(Paint)
		Paint()
		local elapsed = 0
		page:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed < 0.20 then return end
			elapsed = 0
			Paint()
		end)
	end, version)
end
