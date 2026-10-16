local ADDON, AL = ...
local UI_VERSION = "0.14.6"

-- Interface Shaman dediee. Les textes sont localises ici uniquement ; les
-- noms de sorts et les cles de profil restent identiques dans les deux langues.

local function Text(value)
	if type(value) ~= "table" then return tostring(value or "") end
	local language = AL.GetUILanguage and AL.GetUILanguage() or "en"
	return value[language] or value.en or value.fr or ""
end

local function SafeNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function BuildShamanUI(page, ui)
	local rotation = AL.rotations and AL.rotations.SHAMAN
	local theme = ui.Theme
	local stack = ui.Body(page)
	local spellIDs = {}
	for _, entry in ipairs((rotation and rotation.spells) or {}) do
		spellIDs[entry[2]] = entry[1]
	end

	local function SpellIcon(name)
		local override = AL.IconFor and AL.IconFor(name)
		return override or ui.SpellIcon(name, spellIDs[name])
	end

	local function Check(card, key, label, spell, help, full)
		return ui.SettingCheck(card, key, {
			label = Text(label),
			icon = spell and SpellIcon(spell) or nil,
			half = not full,
			tooltip = help and { Text(label), Text(help) } or nil,
			onChange = ui.Repaint,
		})
	end

	local function Slider(card, key, label, minimum, maximum, default, suffix, help)
		return ui.Slider(card, {
			profileKey = key,
			label = Text(label), half = true,
			min = minimum, max = maximum, step = maximum <= 5 and 1 or 5, suffix = suffix or "",
			get = function()
                local raw = ui.Profile()[key]
                local value = not (issecretvalue and issecretvalue(raw)) and tonumber(raw) or nil
                value = SafeNumber(value) or default
                return math.max(minimum, math.min(maximum, math.floor(value+0.5)))
            end,
			set = function(value) ui.Profile()[key] = value end,
			tooltip = help and { Text(label), Text(help) } or nil,
		})
	end

	local function Dropdown(card, key, label, options, default)
		local translated = {}
		for index, option in ipairs(options) do
			translated[index] = { label = Text(option.label), value = option.value }
		end
		return ui.StackDropdown(card, {
			profileKey = key,
			caption = Text(label),
			options = translated,
			get = function()
                local value = ui.Profile()[key]
                if not (issecretvalue and issecretvalue(value)) then
                    for _, option in ipairs(options) do if value == option.value then return value end end
                end
                return default
            end,
			set = function(value)
				ui.Profile()[key] = value
				if AL.UpdateRoleText then AL.UpdateRoleText() end
			end,
			onSelect = ui.Repaint,
		})
	end

	local roleCard = ui.Card(stack,
		Text({ en = "SHAMAN SPECIALIZATION", fr = "SPECIALISATION DU CHAMAN", pt = "ESPECIALIZAÇÃO DO XAMÃ", es = "ESPECIALIZACIÓN DEL CHAMÁN", de = "SCHAMANEN-SPEZIALISIERUNG", zh = "萨满祭司专精" }),
		Text({
			en = "The selected specialization changes the real priority, weapon enchant, totems and mana policy.",
			fr = "La specialisation choisie change reellement la priorite, l'enchantement, les totems et la gestion du mana.",
			pt = "A especialização escolhida altera de fato a prioridade, o encantamento de arma, os totens e a gestão de mana.",
			es = "La especialización elegida cambia realmente la prioridad, el encantamiento de arma, los tótems y la gestión de maná.",
			de = "Die gewählte Spezialisierung ändert die echte Priorität, Waffenverzauberung, Totems und Mana-Strategie.",
			zh = "所选专精会实际改变优先级、武器附魔、图腾和法力策略。",
		}))
	Dropdown(roleCard, "shamanRole",
		{ en = "Active rotation", fr = "Rotation active", pt = "Rotação ativa", es = "Rotación activa", de = "Aktive Rotation", zh = "当前循环" }, {
			{ label = { en = "Enhancement melee", fr = "Amelioration melee", pt = "Aperfeiçoamento corpo a corpo", es = "Mejora cuerpo a cuerpo", de = "Verstärkung Nahkampf", zh = "增强近战" }, value = "ENHANCEMENT" },
			{ label = { en = "Elemental caster", fr = "Elementaire distance", pt = "Elemental conjurador", es = "Elemental lanzador", de = "Elementar Zauberer", zh = "元素施法" }, value = "ELEMENTAL" },
		}, "ENHANCEMENT")

	local steel = { 0.72, 0.62, 0.50, 1 }
	local head = ui.Card(stack,
		Text({ en = "SHAMAN - LIVE STATUS", fr = "CHAMAN - ETAT EN DIRECT", pt = "XAMÃ - STATUS AO VIVO", es = "CHAMÁN - ESTADO EN VIVO", de = "SCHAMANE - LIVE-STATUS", zh = "萨满祭司 - 实时状态" }),
		Text({ en = "Level 1-30 - interface " .. UI_VERSION, fr = "Niveaux 1-30 - interface " .. UI_VERSION, pt = "Níveis 1-30 - interface " .. UI_VERSION, es = "Niveles 1-30 - interfaz " .. UI_VERSION, de = "Stufe 1-30 - Interface " .. UI_VERSION, zh = "等级 1-30 - 界面 " .. UI_VERSION }))
	local rowA = ui.BadgeRow(head, 3)
	local rowB = ui.BadgeRow(head, 3)
	local rowC = ui.BadgeRow(head, 3)
	local rowD = ui.BadgeRow(head, 3)
	local badges = {
		level = rowA.badges[1], health = rowA.badges[2], mana = rowA.badges[3],
		role = rowB.badges[1], spells = rowB.badges[2], shield = rowB.badges[3],
		weapon = rowC.badges[1], earth = rowC.badges[2], water = rowC.badges[3],
		fire = rowD.badges[1], aoe = rowD.badges[2], burst = rowD.badges[3],
	}
	ui.Info(head, Text({
		en = "Forever may protect health, mana, auras and enemy counts. Unknown values stay unknown and optional AoE is withheld.",
		fr = "Forever peut proteger la vie, le mana, les auras et le nombre d'ennemis. Les valeurs inconnues restent inconnues et l'AoE optionnelle est retenue.",
		pt = "Forever pode proteger vida, mana, auras e contagem de inimigos. Valores desconhecidos continuam desconhecidos e o AoE opcional é retido.",
		es = "Forever puede proteger la vida, el maná, las auras y el número de enemigos. Los valores desconocidos siguen desconocidos y el AoE opcional se retiene.",
		de = "Forever kann Gesundheit, Mana, Auren und Gegnerzahl schützen. Unbekannte Werte bleiben unbekannt und optionales AoE wird zurückgehalten.",
		zh = "Forever 可能保护生命值、法力、光环和敌人数量。未知数值保持未知，可选 AoE 将被暂缓。",
	}), { justify = "CENTER" })

	local maintenance = ui.Card(stack,
		Text({ en = "SHIELDS, WEAPON & TOTEMS", fr = "BOUCLIER, ARME ET TOTEMS", pt = "ESCUDOS, ARMA E TOTENS", es = "ESCUDOS, ARMA Y TÓTEMS", de = "SCHILDE, WAFFE & TOTEMS", zh = "护盾、武器和图腾" }))
	Check(maintenance, "shield",
		{ en = "Maintain Lightning Shield", fr = "Maintenir Lightning Shield", pt = "Manter Lightning Shield", es = "Mantener Lightning Shield", de = "Lightning Shield halten", zh = "维持 Lightning Shield" }, "Lightning Shield")
	Check(maintenance, "weapon",
		{ en = "Maintain weapon enchant", fr = "Maintenir l'enchantement d'arme", pt = "Manter encantamento de arma", es = "Mantener encantamiento de arma", de = "Waffenverzauberung halten", zh = "维持武器附魔" }, "Windfury Weapon")
	Dropdown(maintenance, "weaponMode",
		{ en = "Preferred weapon enchant", fr = "Enchantement d'arme prefere", pt = "Encantamento de arma preferido", es = "Encantamiento de arma preferido", de = "Bevorzugte Waffenverzauberung", zh = "首选武器附魔" }, {
			{ label = { en = "Automatic by specialization", fr = "Automatique selon la specialisation", pt = "Automático pela especialização", es = "Automático según especialización", de = "Automatisch nach Spezialisierung", zh = "按专精自动" }, value = "AUTO" },
			{ label = "Windfury Weapon", value = "WINDFURY" },
			{ label = "Rockbiter Weapon", value = "ROCKBITER" },
			{ label = "Flametongue Weapon", value = "FLAMETONGUE" },
		}, "AUTO")
	Check(maintenance, "totems",
		{ en = "Maintain combat totems", fr = "Maintenir les totems de combat", pt = "Manter totens de combate", es = "Mantener tótems de combate", de = "Kampftotems halten", zh = "维持战斗图腾" }, "Strength of Earth Totem", nil, true)
	Dropdown(maintenance, "earthTotemMode",
		{ en = "Earth totem", fr = "Totem de terre", pt = "Totem de terra", es = "Tótem de tierra", de = "Erdtotem", zh = "大地图腾" }, {
			{ label = { en = "Automatic by specialization", fr = "Automatique selon la specialisation", pt = "Automático pela especialização", es = "Automático según especialización", de = "Automatisch nach Spezialisierung", zh = "按专精自动" }, value = "AUTO" },
			{ label = "Strength of Earth Totem", value = "STRENGTH" },
			{ label = "Stoneskin Totem", value = "STONESKIN" },
			{ label = { en = "Disabled", fr = "Desactive", pt = "Desativado", es = "Desactivado", de = "Deaktiviert", zh = "禁用" }, value = "OFF" },
		}, "AUTO")
	Dropdown(maintenance, "waterTotemMode",
		{ en = "Water totem", fr = "Totem d'eau", pt = "Totem de água", es = "Tótem de agua", de = "Wassertotem", zh = "水之图腾" }, {
			{ label = { en = "Automatic by specialization", fr = "Automatique selon la specialisation", pt = "Automático pela especialização", es = "Automático según especialización", de = "Automatisch nach Spezialisierung", zh = "按专精自动" }, value = "AUTO" },
			{ label = "Healing Stream Totem", value = "HEALING" },
			{ label = "Mana Spring Totem", value = "MANA" },
			{ label = { en = "Disabled", fr = "Desactive", pt = "Desativado", es = "Desactivado", de = "Deaktiviert", zh = "禁用" }, value = "OFF" },
		}, "AUTO")
	Check(maintenance, "searing", "Searing Totem", "Searing Totem")
	Slider(maintenance, "totemMinTargetHP",
		{ en = "Totem minimum target health", fr = "Vie cible minimum pour les totems", pt = "Vida mínima do alvo para totens", es = "Vida mínima del objetivo para tótems", de = "Totem Mindest-Zielgesundheit", zh = "图腾目标最低生命值" }, 0, 100, 45, " %")

	local offense = ui.Card(stack,
		Text({ en = "COMBAT PRIORITY", fr = "PRIORITE DE COMBAT", pt = "PRIORIDADE DE COMBATE", es = "PRIORIDAD DE COMBATE", de = "KAMPFPRIORITÄT", zh = "战斗优先级" }))
	Check(offense, "interrupt",
		{ en = "Earth Shock interrupt", fr = "Interruption avec Earth Shock", pt = "Interromper com Earth Shock", es = "Interrumpir con Earth Shock", de = "Earth Shock unterbricht", zh = "Earth Shock 打断" }, "Earth Shock",
		{ en = "Always checked before healing, maintenance and damage.", fr = "Toujours verifie avant les soins, la maintenance et les degats.", pt = "Sempre verificado antes de cura, manutenção e dano.", es = "Siempre se comprueba antes de sanación, mantenimiento y daño.", de = "Wird immer vor Heilung, Pflege und Schaden geprüft.", zh = "始终在治疗、维持和伤害之前检查。" }, true)
	Check(offense, "flameshock", "Flame Shock", "Flame Shock")
	Check(offense, "stormstrike", "Stormstrike", "Stormstrike")
	Check(offense, "earthshock",
		{ en = "Earth Shock damage", fr = "Earth Shock pour les degats", pt = "Earth Shock para dano", es = "Earth Shock para daño", de = "Earth Shock für Schaden", zh = "Earth Shock 伤害" }, "Earth Shock")
	Check(offense, "frostshock",
		{ en = "Frost Shock on low-health targets", fr = "Frost Shock sur cible faible", pt = "Frost Shock em alvos com pouca vida", es = "Frost Shock en objetivos con poca vida", de = "Frost Shock bei schwachen Zielen", zh = "对低生命目标使用 Frost Shock" }, "Frost Shock")
	Check(offense, "lightningbolt", "Lightning Bolt", "Lightning Bolt")
	ui.Info(offense, Text({
		en = "Lightning Bolt opens at range in both specializations. Enhancement repeats it while stationary at range and uses it after melee priorities. Start Attack is a melee fallback. Red indicates out of range when range coloring is enabled.",
		fr = "Eclair ouvre a distance dans les deux specialisations. Amelioration le repete immobile a distance et l'utilise apres les priorites de melee. Start Attack sert de repli au contact. Le rouge indique hors de portee si la coloration est activee.",
		pt = "Lightning Bolt abre à distância nas duas especializações. Aperfeiçoamento o repete parado à distância e o usa após as prioridades corpo a corpo. Start Attack é o recurso corpo a corpo. Vermelho indica fora de alcance quando a coloração de alcance está ativada.",
		es = "Lightning Bolt abre a distancia en ambas especializaciones. Mejora lo repite quieto a distancia y lo usa tras las prioridades cuerpo a cuerpo. Start Attack es el recurso cuerpo a cuerpo. El rojo indica fuera de alcance si la coloración de alcance está activada.",
		de = "Lightning Bolt eröffnet in beiden Spezialisierungen auf Distanz. Verstärkung wiederholt ihn im Stand auf Distanz und nutzt ihn nach den Nahkampfprioritäten. Start Attack ist der Nahkampf-Ersatz. Rot heißt außer Reichweite, wenn die Reichweitenfärbung aktiv ist.",
		zh = "两种专精都会在远程用 Lightning Bolt 起手。增强在远程静止时会重复施放，并在近战优先级之后使用。Start Attack 是近战后备。启用距离着色时，红色表示超出距离。",
	}))
	Slider(offense, "shockMinMana",
		{ en = "Shocks minimum mana", fr = "Mana minimum pour les Shocks", pt = "Mana mínima para Shocks", es = "Maná mínimo para Shocks", de = "Shocks Mindest-Mana", zh = "Shocks 最低法力" }, 0, 100, 25, " %")
	Slider(offense, "lightningBoltMinMana",
		{ en = "Lightning Bolt minimum mana", fr = "Mana minimum pour Lightning Bolt", pt = "Mana mínima para Lightning Bolt", es = "Maná mínimo para Lightning Bolt", de = "Lightning Bolt Mindest-Mana", zh = "Lightning Bolt 最低法力" }, 0, 100, 15, " %")
	Slider(offense, "flameShockMinTargetHP",
		{ en = "Flame Shock minimum target health", fr = "Vie cible minimum pour Flame Shock", pt = "Vida mínima do alvo para Flame Shock", es = "Vida mínima del objetivo para Flame Shock", de = "Flame Shock Mindest-Zielgesundheit", zh = "Flame Shock 目标最低生命值" }, 0, 100, 35, " %")
	Slider(offense, "frostShockTargetHP",
		{ en = "Frost Shock below target health", fr = "Frost Shock sous cette vie cible", pt = "Frost Shock abaixo desta vida do alvo", es = "Frost Shock bajo esta vida del objetivo", de = "Frost Shock unter Zielgesundheit", zh = "目标生命低于此值时 Frost Shock" }, 0, 100, 25, " %")

	local survival = ui.Card(stack,
		Text({ en = "HEALING & RECOVERY", fr = "SOINS ET RECUPERATION", pt = "CURA E RECUPERAÇÃO", es = "SANACIÓN Y RECUPERACIÓN", de = "HEILUNG & ERHOLUNG", zh = "治疗和恢复" }))
	Check(survival, "heal",
		{ en = "Self-healing suggestions", fr = "Suggestions de soins personnels", pt = "Sugestões de autocura", es = "Sugerencias de autosanación", de = "Selbstheilungsvorschläge", zh = "自我治疗建议" }, "Lesser Healing Wave")
	Slider(survival, "healHP",
		{ en = "Combat healing threshold", fr = "Seuil de soin en combat", pt = "Limite de cura em combate", es = "Umbral de sanación en combate", de = "Heilschwelle im Kampf", zh = "战斗中治疗阈值" }, 5, 95, 35, " % HP")
	Slider(survival, "healOutOfCombatHP",
		{ en = "Out-of-combat healing threshold", fr = "Seuil de soin hors combat", pt = "Limite de cura fora de combate", es = "Umbral de sanación fuera de combate", de = "Heilschwelle außerhalb des Kampfes", zh = "脱战治疗阈值" }, 5, 95, 70, " % HP")
	Slider(survival, "healMinMana",
		{ en = "Healing minimum mana", fr = "Mana minimum pour les soins", pt = "Mana mínima para cura", es = "Maná mínimo para sanar", de = "Heilung Mindest-Mana", zh = "治疗最低法力" }, 0, 100, 10, " %")
	Check(survival, "stoneclaw",
		{ en = "Stoneclaw Totem emergency", fr = "Stoneclaw Totem d'urgence", pt = "Stoneclaw Totem de emergência", es = "Stoneclaw Totem de emergencia", de = "Stoneclaw Totem im Notfall", zh = "紧急 Stoneclaw Totem" }, "Stoneclaw Totem")
	Slider(survival, "stoneclawHP",
		{ en = "Stoneclaw health threshold", fr = "Seuil de vie Stoneclaw", pt = "Limite de vida Stoneclaw", es = "Umbral de vida Stoneclaw", de = "Stoneclaw Gesundheitsschwelle", zh = "Stoneclaw 生命阈值" }, 5, 80, 25, " % HP")
	Check(survival, "drink", { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" })
	Slider(survival, "drinkMana",
		{ en = "Drink below mana", fr = "Boire sous ce niveau de mana", pt = "Beber abaixo desta mana", es = "Beber bajo este maná", de = "Trinken unter Mana", zh = "法力低于此值时喝水" }, 0, 80, 30, " %")

	local aoe = ui.Card(stack,
		Text({ en = "AOE & BURST", fr = "AOE ET BURST", pt = "AOE E BURST", es = "AOE Y BURST", de = "AOE & BURST", zh = "AOE 和爆发" }))
	Check(aoe, "aoe", { en = "Enable AoE mode", fr = "Activer le mode AoE", pt = "Ativar modo AoE", es = "Activar modo AoE", de = "AoE-Modus aktivieren", zh = "启用 AoE 模式" }, nil,
		{ en = "AoE totems require a confirmed nearby enemy count.", fr = "Les totems AoE exigent un nombre confirme d'ennemis proches.", pt = "Totens AoE exigem uma contagem confirmada de inimigos próximos.", es = "Los tótems AoE requieren un número confirmado de enemigos cercanos.", de = "AoE-Totems brauchen eine bestätigte Anzahl naher Gegner.", zh = "AoE 图腾需要已确认的附近敌人数量。" })
	Check(aoe, "firenova", "Fire Nova Totem", "Fire Nova Totem")
	Check(aoe, "magma", "Magma Totem", "Magma Totem")
	Slider(aoe, "aoeMinEnemies",
		{ en = "Minimum enemies", fr = "Ennemis minimum", pt = "Mínimo de inimigos", es = "Mínimo de enemigos", de = "Mindestanzahl Gegner", zh = "最少敌人数" }, 2, 5, 2, "")
	Slider(aoe, "aoeMinMana",
		{ en = "AoE minimum mana", fr = "Mana minimum pour l'AoE", pt = "Mana mínima para AoE", es = "Maná mínimo para AoE", de = "AoE Mindest-Mana", zh = "AoE 最低法力" }, 0, 100, 30, " %")
	Slider(aoe, "burstMinTargetHP",
		{ en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Vida mínima del objetivo para Burst", de = "Burst Mindest-Zielgesundheit", zh = "爆发目标最低生命值" }, 0, 100, 40, " %")
	ui.Info(aoe, Text({
		en = "Enhancement uses Blood Fury or Berserking in melee. Elemental only uses Berserking at spell range.",
		fr = "Amelioration utilise Blood Fury ou Berserking en melee. Elementaire utilise uniquement Berserking a portee des sorts.",
		pt = "Aperfeiçoamento usa Blood Fury ou Berserking corpo a corpo. Elemental usa apenas Berserking ao alcance de feitiços.",
		es = "Mejora usa Blood Fury o Berserking cuerpo a cuerpo. Elemental solo usa Berserking a alcance de hechizos.",
		de = "Verstärkung nutzt Blood Fury oder Berserking im Nahkampf. Elementar nutzt Berserking nur in Zauberreichweite.",
		zh = "增强在近战时使用 Blood Fury 或 Berserking。元素仅在法术距离内使用 Berserking。",
	}))

	local utility = ui.Card(stack,
		Text({ en = "FOREVER SAFETY", fr = "SECURITE FOREVER", pt = "SEGURANÇA FOREVER", es = "SEGURIDAD FOREVER", de = "FOREVER-SICHERHEIT", zh = "FOREVER 安全" }))
	ui.Info(utility, Text({
		en = "The three Shocks use one shared lock when cooldown data is protected. Purge and cleansing totems stay manual because hidden enemy/player auras are never guessed.",
		fr = "Les trois Shocks utilisent un verrou commun lorsque les recharges sont protegees. Purge et les totems de purification restent manuels car les auras masquees ne sont jamais devinees.",
		pt = "Os três Shocks usam um bloqueio compartilhado quando os dados de recarga estão protegidos. Purge e os totens de purificação ficam manuais porque auras ocultas de inimigos/jogador nunca são presumidas.",
		es = "Los tres Shocks usan un bloqueo compartido cuando los datos de reutilización están protegidos. Purge y los tótems de purificación siguen siendo manuales porque las auras ocultas de enemigos/jugador nunca se suponen.",
		de = "Die drei Shocks teilen eine Sperre, wenn Abklingzeitdaten geschützt sind. Purge und Reinigungstotems bleiben manuell, da verborgene Gegner-/Spielerauren nie geraten werden.",
		zh = "冷却数据受保护时，三种 Shock 共用一个锁定。Purge 和净化图腾保持手动，因为从不猜测隐藏的敌人/玩家光环。",
	}))

	local last = {}
	local function SetBadge(key, value, color)
		if last[key] == value then return end
		last[key] = value
		badges[key]:SetBadge(value, color)
	end

	local function ShortTotem(name)
		if not name then return "-" end
		return name:gsub(" Totem", ""):gsub("Strength of Earth", "Strength"):gsub("Healing Stream", "Healing")
	end

	local function ShortWeapon(name)
		if not name then return "-" end
		if name == "Enchanted" then return Text({ en = "ENCHANTED", fr = "ENCHANTEE", pt = "ENCANTADA", es = "ENCANTADA", de = "VERZAUBERT", zh = "已附魔" }) end
		return name:gsub(" Weapon", "")
	end

	local function PercentBadge(label, value)
		value = SafeNumber(value)
        return value and (label .. " " .. math.floor(value + 0.5) .. "%") or (label .. " ?")
	end

	local function Paint()
		local state = rotation and rotation.GetUIState and rotation.GetUIState() or {}
		local profile = ui.Profile()
		SetBadge("level", (AL.L and AL.L("LEVEL") or "LEVEL") .. " " .. tostring(state.level or "?"), steel)
		SetBadge("health", PercentBadge("HP", state.health), type(state.health) == "number" and theme.ok or theme.gold)
		SetBadge("mana", PercentBadge("MANA", state.mana), type(state.mana) == "number" and theme.gold or steel)
		SetBadge("role", state.role == "ELEMENTAL" and "ELEMENTAL" or "ENHANCEMENT",
			state.role == "ELEMENTAL" and (theme.info or theme.gold) or theme.ok)
		SetBadge("spells", tostring(state.knownCount or 0) .. " " .. (AL.L and AL.L("SPELLS"):upper() or "SPELLS"), steel)
		SetBadge("shield", state.lightningShield and "SHIELD" or "NO SHIELD",
			state.lightningShield and theme.ok or theme.textFaint)
		SetBadge("weapon", "WEAPON " .. ShortWeapon(state.weaponEnchant), state.weaponEnchant and theme.gold or steel)
		SetBadge("earth", "EARTH " .. ShortTotem(state.earthTotem), state.earthTotem and theme.ok or steel)
		SetBadge("water", "WATER " .. ShortTotem(state.waterTotem), state.waterTotem and theme.ok or steel)
		SetBadge("fire", "FIRE " .. ShortTotem(state.fireTotem), state.fireTotem and theme.ok or steel)
		SetBadge("aoe", profile.aoe and (AL.L and AL.L("AOE_ON") or "AOE ON")
			or (AL.L and AL.L("AOE_OFF") or "AOE OFF"), profile.aoe and theme.ok or theme.textFaint)
		SetBadge("burst", AL.burst and (AL.L and AL.L("BURST_ON") or "BURST ON")
			or (AL.L and AL.L("BURST_OFF") or "BURST OFF"), AL.burst and theme.gold or theme.textFaint)
		rowA:Layout()
		rowB:Layout()
		rowC:Layout()
		rowD:Layout()
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
end

if AL.RegisterClassUI then
	AL.RegisterClassUI("SHAMAN", BuildShamanUI, UI_VERSION)
end
if AL.rotations and AL.rotations.SHAMAN then
	AL.rotations.SHAMAN.uiVersion = UI_VERSION
end
