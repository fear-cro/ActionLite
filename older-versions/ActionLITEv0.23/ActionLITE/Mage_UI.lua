local ADDON, AL = ...

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
				local raw = ui.Profile()[control.key]
                local value = not (issecretvalue and issecretvalue(raw)) and tonumber(raw) or nil
                if not value or value ~= value or value == math.huge or value == -math.huge then value = control.default or control.min end
                return math.max(control.min, math.min(control.max, math.floor(value + 0.5)))
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
				if not (issecretvalue and issecretvalue(value)) then
                    for _, option in ipairs(control.options or {}) do if value == option.value then return value end end
                end
                return control.default
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
		tooltip = control.tooltip and {
			Text(control.tooltip[1]), Text(control.tooltip[2]),
		} or nil,
	})
end

local function RegisterMageUI(token, config, version)
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
			local ok, level = pcall(function() return UnitLevel and UnitLevel("player") end)
            if not ok or (issecretvalue and issecretvalue(level)) or type(level) ~= "number" then level = "?" end
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


RegisterMageUI("MAGE", {
	title = { en = "MAGE - LEVELING", fr = "MAGE - PROGRESSION", pt = "MAGO - EVOLUÇÃO", es = "MAGO - SUBIDA", de = "MAGIER - LEVELN", zh = "法师 - 升级" },
	subtitle = { en = "Frost-first ranged profile - interface 0.15.6", fr = "Profil distance priorite Givre - interface 0.15.6", pt = "Perfil à distância, Gelo primeiro - interface 0.15.6", es = "Perfil a distancia, Escarcha primero - interfaz 0.15.6", de = "Fernkampfprofil, Frost zuerst - Interface 0.15.6", zh = "冰霜优先远程配置 - 界面 0.15.6" },
	aoeKey = "aoe",
	cards = {
		{
			title = { en = "PRIMARY SPELL", fr = "SORT PRINCIPAL", pt = "FEITIÇO PRINCIPAL", es = "HECHIZO PRINCIPAL", de = "HAUPTZAUBER", zh = "主要法术" },
			subtitle = {
				en = "Auto uses Frostbolt first. Every choice falls back to another learned nuke.",
				fr = "Auto choisit Frostbolt en premier. Chaque choix se replie sur un autre sort appris.",
				pt = "Auto usa Frostbolt primeiro. Cada escolha recorre a outro feitiço aprendido.",
				es = "Auto usa Frostbolt primero. Cada opción recurre a otro hechizo aprendido.",
				de = "Auto nutzt zuerst Frostbolt. Jede Wahl weicht auf einen anderen erlernten Schadenszauber aus.",
				zh = "自动优先使用Frostbolt。每个选项都会回退到另一个已学会的主力法术。",
			},
			controls = {
				{ type = "dropdown", key = "nuke", label = { en = "Preferred nuke", fr = "Sort principal prefere", pt = "Feitiço preferido", es = "Hechizo preferido", de = "Bevorzugter Zauber", zh = "首选主力法术" }, default = "AUTO", options = {
					{ label = { en = "Auto - Frost first", fr = "Auto - Givre prioritaire", pt = "Auto - Gelo primeiro", es = "Auto - Escarcha primero", de = "Auto - Frost zuerst", zh = "自动 - 冰霜优先" }, value = "AUTO" },
					{ label = "Frostbolt", value = "FROSTBOLT" },
					{ label = "Fireball", value = "FIREBALL" },
					{ label = "Arcane Missiles", value = "ARCANE_MISSILES" },
					{ label = "Scorch", value = "SCORCH" },
				} },
				{ key = "primaryFire", label = { en = "Primarily use fire spells", fr = "Utiliser principalement les sorts de feu", pt = "Usar principalmente feitiços de fogo", es = "Usar principalmente hechizos de fuego", de = "Hauptsächlich Feuerzauber verwenden", zh = "主要使用火焰法术" }, spell = "Fireball", tooltip = {
					{ en = "Fire-primary rotation", fr = "Rotation principalement Feu", pt = "Rotação principal de Fogo", es = "Rotación principalmente de Fuego", de = "Feuerpriorisierte Rotation", zh = "火焰优先循环" },
					{ en = "Disables Frostbolt priority. Uses Fireball and Fire Blast, and recommends Flamestrike when AoE is enabled and its enemy-count and mana settings are met.", fr = "Désactive la priorité de Frostbolt. Utilise Fireball et Fire Blast, et recommande Flamestrike si l’AoE est activée et que les seuils d’ennemis et de mana sont atteints.", pt = "Desativa a prioridade de Frostbolt. Usa Fireball e Fire Blast e recomenda Flamestrike quando o AoE está ativado e os limites de inimigos e mana são atendidos.", es = "Desactiva la prioridad de Frostbolt. Usa Fireball y Fire Blast y recomienda Flamestrike cuando el AoE está activado y se cumplen los límites de enemigos y maná.", de = "Deaktiviert die Frostbolt-Priorität. Verwendet Fireball und Fire Blast und empfiehlt Flamestrike, wenn AoE aktiviert ist und die Gegner- und Mana-Schwellen erreicht sind.", zh = "禁用 Frostbolt 优先级。使用 Fireball 和 Fire Blast。启用 AoE 且达到敌人数和法力阈值时推荐 Flamestrike。" }
				} },
				{ key = "buffs", label = { en = "Maintain intellect and armor", fr = "Maintenir intelligence et armure", pt = "Manter intelecto e armadura", es = "Mantener intelecto y armadura", de = "Intelligenz und Rüstung halten", zh = "保持智力和护甲" }, spell = "Arcane Intellect" },
				{ key = "conjure", label = { en = "Conjure missing water, food and gem", fr = "Conjurer eau, nourriture et gemme manquantes", pt = "Conjurar água, comida e gema que faltam", es = "Conjurar agua, comida y gema faltantes", de = "Wasser, Essen und Edelstein herbeizaubern", zh = "制造缺少的水、食物和宝石" }, spell = "Conjure Water" },
			},
		},
		{
			title = { en = "MANA & WAND", fr = "MANA ET BAGUETTE", pt = "MANA E VARINHA", es = "MANÁ Y VARITA", de = "MANA & ZAUBERSTAB", zh = "法力值与魔杖" },
			controls = {
				{ key = "drink", label = { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" } },
				{ type = "slider", key = "drinkMana", label = { en = "Drink below mana", fr = "Boire sous ce niveau de mana", pt = "Beber com mana abaixo de", es = "Beber con maná bajo", de = "Trinken unter Mana", zh = "法力值低于时喝水" }, min = 0, max = 80, step = 5, default = 35, suffix = " %" },
				{ key = "evocation", label = "Evocation", spell = "Evocation" },
				{ type = "slider", key = "evocationMana", label = { en = "Evocation below mana", fr = "Evocation sous ce niveau de mana", pt = "Evocation com mana abaixo de", es = "Evocation con maná bajo", de = "Evocation unter Mana", zh = "法力值低于时Evocation" }, min = 0, max = 60, step = 5, default = 15, suffix = " %" },
				{ key = "wand", label = { en = "Use wand to conserve mana", fr = "Utiliser la baguette pour economiser le mana", pt = "Usar varinha para poupar mana", es = "Usar varita para ahorrar maná", de = "Zauberstab nutzen, um Mana zu sparen", zh = "使用魔杖节省法力值" }, spell = "Shoot" },
				{ type = "slider", key = "wandMana", label = { en = "Shoot instead of damage spells at/below mana", fr = "Shoot au lieu des sorts de dégâts à ce mana ou moins", pt = "Shoot em vez de feitiços de dano neste mana ou menos", es = "Shoot en vez de hechizos de daño con este maná o menos", de = "Shoot statt Schadenszaubern ab diesem Mana oder weniger", zh = "法力低于或等于此值时用 Shoot 代替伤害法术" }, min = 0, max = 95, step = 5, default = 25, suffix = " %", tooltip = { { en = "Wand mana hard gate", fr = "Seuil strict de mana pour la baguette", pt = "Limite rígida de mana da varinha", es = "Límite estricto de maná para la varita", de = "Harte Mana-Grenze für den Zauberstab", zh = "魔杖法力硬性阈值" }, { en = "At or below this mana, offensive Mage damage spells are blocked and Shoot is recommended while stationary.", fr = "À ce niveau de mana ou en dessous, les sorts de dégâts offensifs sont bloqués et Shoot est conseillé à l'arrêt.", pt = "Neste valor de mana ou abaixo, feitiços ofensivos são bloqueados e Shoot é recomendado parado.", es = "Con este maná o menos, los hechizos ofensivos se bloquean y se recomienda Shoot al estar quieto.", de = "Bei diesem Mana oder weniger werden offensive Schadenszauber blockiert und im Stand Shoot empfohlen.", zh = "法力值低于或等于此阈值时阻止进攻伤害法术，并在静止时推荐 Shoot。" } } },
				{ type = "slider", key = "wandTargetHP", label = { en = "Wand below target health", fr = "Baguette sous la vie cible", pt = "Varinha com vida do alvo abaixo de", es = "Varita con salud del objetivo baja", de = "Zauberstab unter Zielgesundheit", zh = "目标生命值低于时用魔杖" }, min = 0, max = 80, step = 5, default = 20, suffix = " % HP" },
			},
		},
		{
			title = { en = "RANGED COMBAT & CONTROL", fr = "COMBAT DISTANCE ET CONTROLE", pt = "COMBATE À DISTÂNCIA E CONTROLE", es = "COMBATE A DISTANCIA Y CONTROL", de = "FERNKAMPF & KONTROLLE", zh = "远程战斗与控制" },
			subtitle = {
				en = "Range is checked from the learned spell rank: red out of range, normal color when castable.",
				fr = "La portee est verifiee avec le rang appris : rouge hors portee, couleur normale quand le sort est lancable.",
				pt = "O alcance é verificado pelo grau aprendido do feitiço: vermelho fora de alcance, cor normal quando lançável.",
				es = "El alcance se comprueba con el rango aprendido del hechizo: rojo fuera de alcance, color normal si se puede lanzar.",
				de = "Die Reichweite wird über den erlernten Zauberrang geprüft: rot außer Reichweite, normale Farbe, wenn wirkbar.",
				zh = "射程按已学会的法术等级检查：超出射程显示红色，可施放时显示正常颜色。",
			},
			controls = {
				{ key = "cspell", label = { en = "Counterspell enemy casts", fr = "Counterspell sur les incantations", pt = "Counterspell em lançamentos inimigos", es = "Counterspell a lanzamientos enemigos", de = "Counterspell auf feindliche Zauber", zh = "Counterspell打断敌方施法" }, spell = "Counterspell" },
				{ key = "nova", label = { en = "Frost Nova in melee", fr = "Frost Nova au corps a corps", pt = "Frost Nova em corpo a corpo", es = "Frost Nova en cuerpo a cuerpo", de = "Frost Nova im Nahkampf", zh = "近战时Frost Nova" }, spell = "Frost Nova" },
				{ key = "fireblast", label = { en = "Fire Blast on the move and on cooldown", fr = "Fire Blast en mouvement et des que disponible", pt = "Fire Blast em movimento e quando disponível", es = "Fire Blast en movimiento y al estar disponible", de = "Fire Blast in Bewegung und sobald bereit", zh = "移动中及冷却结束时Fire Blast" }, spell = "Fire Blast" },
				{ type = "slider", key = "fireBlastMinMana", label = { en = "Fire Blast minimum mana", fr = "Mana minimum Fire Blast", pt = "Mana mínima Fire Blast", es = "Maná mínimo Fire Blast", de = "Fire Blast Mindestmana", zh = "Fire Blast最低法力值" }, min = 0, max = 100, step = 5, default = 25, suffix = " %" },
				{ key = "icelance", label = { en = "Ice Lance on frozen targets", fr = "Ice Lance sur les cibles gelees", pt = "Ice Lance em alvos congelados", es = "Ice Lance en objetivos congelados", de = "Ice Lance auf eingefrorene Ziele", zh = "对冰冻目标Ice Lance" }, spell = "Ice Lance" },
				{ type = "slider", key = "burstMinTargetHP", label = { en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Salud mínima del objetivo para Burst", de = "Burst: Mindestgesundheit des Ziels", zh = "Burst目标最低生命值" }, min = 0, max = 100, step = 5, default = 40, suffix = " % HP" },
			},
		},
		{
			title = { en = "SURVIVAL", fr = "SURVIE", pt = "SOBREVIVÊNCIA", es = "SUPERVIVENCIA", de = "ÜBERLEBEN", zh = "生存" },
			controls = {
				{ key = "iceblock", label = { en = "Emergency Ice Block", fr = "Ice Block d'urgence", pt = "Ice Block de emergência", es = "Ice Block de emergencia", de = "Ice Block im Notfall", zh = "紧急Ice Block" }, spell = "Ice Block" },
				{ type = "slider", key = "iceBlockHP", label = { en = "Ice Block health threshold", fr = "Seuil de vie Ice Block", pt = "Limite de vida Ice Block", es = "Umbral de salud Ice Block", de = "Ice Block Gesundheitsschwelle", zh = "Ice Block生命值阈值" }, min = 1, max = 60, step = 1, default = 18, suffix = " % HP" },
				{ key = "manaShield", label = { en = "Mana Shield at low health", fr = "Mana Shield a faible vie", pt = "Mana Shield com pouca vida", es = "Mana Shield con poca salud", de = "Mana Shield bei wenig Gesundheit", zh = "低生命值时Mana Shield" }, spell = "Mana Shield" },
				{ type = "slider", key = "manaShieldHP", label = { en = "Mana Shield health threshold", fr = "Seuil de vie Mana Shield", pt = "Limite de vida Mana Shield", es = "Umbral de salud Mana Shield", de = "Mana Shield Gesundheitsschwelle", zh = "Mana Shield生命值阈值" }, min = 5, max = 90, step = 5, default = 45, suffix = " % HP" },
				{ type = "slider", key = "manaShieldMinMana", label = { en = "Mana Shield minimum mana", fr = "Mana minimum Mana Shield", pt = "Mana mínima Mana Shield", es = "Maná mínimo Mana Shield", de = "Mana Shield Mindestmana", zh = "Mana Shield最低法力值" }, min = 0, max = 100, step = 5, default = 25, suffix = " %" },
			},
		},
		{
			title = { en = "CONFIRMED AOE", fr = "AOE CONFIRMEE", pt = "AOE CONFIRMADO", es = "AOE CONFIRMADO", de = "BESTÄTIGTES AOE", zh = "确认的AOE" },
			subtitle = {
				en = "AoE requires the selected number of confirmed enemies and minimum mana, including in Fire-primary mode.",
				fr = "L’AoE nécessite le nombre choisi d’ennemis confirmés et le mana minimum, y compris en mode Feu.",
				pt = "O AoE exige o número selecionado de inimigos confirmados e a mana mínima, inclusive no modo de Fogo.",
				es = "El AoE requiere el número elegido de enemigos confirmados y el maná mínimo, también en el modo de Fuego.",
				de = "AoE erfordert die gewählte Anzahl bestätigter Gegner und das Mindestmana, auch bei Feuerpriorität.",
				zh = "AoE 需要达到所选的已确认敌人数和最低法力值，包括火焰优先模式。",
			},
			controls = {
				{ key = "aoe", label = { en = "Enable AoE priority", fr = "Activer la priorite AoE", pt = "Ativar prioridade AoE", es = "Activar prioridad AoE", de = "AoE-Priorität aktivieren", zh = "启用AoE优先" }, spell = "Blizzard" },
				{ type = "slider", key = "aoeMinEnemies", label = { en = "Minimum enemies", fr = "Ennemis minimum", pt = "Mínimo de inimigos", es = "Enemigos mínimos", de = "Mindestanzahl Gegner", zh = "最少敌人数" }, min = 2, max = 8, step = 1, default = 3 },
				{ type = "slider", key = "aoeMinMana", label = { en = "AoE minimum mana", fr = "Mana minimum AoE", pt = "Mana mínima AoE", es = "Maná mínimo AoE", de = "AoE Mindestmana", zh = "AoE最低法力值" }, min = 0, max = 100, step = 5, default = 35, suffix = " %" },
			},
		},
	},
}, "0.15.6")
