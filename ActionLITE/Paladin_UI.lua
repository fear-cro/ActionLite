local ADDON, AL = ...
local UI_VERSION = "0.14.4"

-- Interface Paladin dediee. Les textes sont localises ici uniquement ; les
-- noms internes des sorts et les cles du profil restent inchanges.

local function Text(value)
	if type(value) ~= "table" then return tostring(value or "") end
	local language = AL.GetUILanguage and AL.GetUILanguage() or "en"
	return value[language] or value.en or value.fr or ""
end

local function BuildPaladinUI(page, ui)
	local rotation = AL.rotations and AL.rotations.PALADIN
	if rotation and rotation.NormalizeBuild then rotation.NormalizeBuild(ui.Profile()) end
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

	local function Check(card, key, label, spell, help, full, changed)
		return ui.SettingCheck(card, key, {
			label = Text(label),
			icon = spell and SpellIcon(spell) or nil,
			half = not full,
			tooltip = help and { Text(label), Text(help) } or nil,
			onChange = changed or ui.Repaint,
		})
	end

	local function Slider(card, key, label, minimum, maximum, default, suffix, help)
		return ui.Slider(card, {
			profileKey = key,
			label = Text(label), half = true,
			min = minimum, max = maximum, step = maximum <= 5 and 1 or ((default - minimum) % 5 == 0 and 5 or 1), suffix = suffix or "",
			get = function()
                local raw = ui.Profile()[key]
                if issecretvalue and issecretvalue(raw) then return default end
                local value = tonumber(raw)
                if not value or value ~= value or value == math.huge or value == -math.huge then return default end
                return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
            end,
			set = function(value) ui.Profile()[key] = value end,
			tooltip = help and { Text(label), Text(help) } or nil,
		})
	end

	local function Dropdown(card, key, label, options, default, changed)
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
				if issecretvalue and issecretvalue(value) then return default end
				for _, option in ipairs(translated) do
					if value == option.value then return value end
				end
				return default
			end,
			set = function(value)
				if key ~= "paladinRole" then ui.Profile()[key] = value end
				if changed then changed(value) end
			end,
			onSelect = ui.Repaint,
		})
	end

	local levelingCard = ui.Card(stack, "LEVELING ROTATION", "Original class rotation")
	Check(levelingCard, "leveling", "Leveling Rotation", "Judgement", "Uses the finalized class rotation from before the level-60 sim builds, with its original priorities and existing settings. Select a DPS or Tank build to switch rotations. Turning the active build off automatically selects Leveling Rotation. One rotation always stays selected.", true,
		function() rotation.SetBuild("leveling", ui.Profile().leveling == true, ui.Profile()); ui.Repaint() end)

	local roleCard = ui.Card(stack,
		Text({ en = "PALADIN ROLE", fr = "ROLE DU PALADIN", pt = "FUNÇÃO DO PALADINO", es = "ROL DEL PALADÍN", de = "PALADIN-ROLLE", zh = "圣骑士职责" }),
		Text({
			en = "The selected role changes the actual combat priority, buffs, seal and mana policy.",
			fr = "Le role selectionne change reellement la priorite de combat, les buffs, le sceau et la gestion du mana.",
			pt = "A função escolhida altera de fato a prioridade de combate, os buffs, o selo e a gestão de mana.",
			es = "El rol elegido cambia realmente la prioridad de combate, los beneficios, el sello y la gestión de maná.",
			de = "Die gewählte Rolle ändert die echte Kampfpriorität, Buffs, Siegel und Mana-Strategie.",
			zh = "所选职责会实际改变战斗优先级、增益、圣印和法力策略。",
		}))
	Dropdown(roleCard, "paladinRole",
		{ en = "Active rotation", fr = "Rotation active", pt = "Rotação ativa", es = "Rotación activa", de = "Aktive Rotation", zh = "当前循环" }, {
			{ label = { en = "Retribution DPS", fr = "Vindicte DPS", pt = "Retribuição DPS", es = "Reprensión DPS", de = "Vergeltung DPS", zh = "惩戒 DPS" }, value = "DPS" },
			{ label = { en = "Protection Tank", fr = "Protection Tank", pt = "Proteção Tanque", es = "Protección Tanque", de = "Schutz Tank", zh = "防护坦克" }, value = "TANK" },
		}, "DPS", function(value)
			if value == "DPS" then ui.Profile().levelingPaladinRole, ui.Profile().paladinRole = "DPS", "DPS" end
			if rotation and rotation.SelectBuild then rotation.SelectBuild(ui.Profile(), "protection", value == "TANK") end
		end)
	Check(roleCard, "protection", "Tank — Protection (8/33/10)", "Holy Shield",
		"Uses the Protection priority with learned spells through level 60. Selecting Tank disables both DPS build boxes. Turning Tank off automatically selects Leveling Rotation. Talents, equipment, spell permissions and icon assignments are not changed.", true,
		function() rotation.SelectBuild(ui.Profile(), "protection", ui.Profile().protection == true); ui.Repaint() end)
	local buildCard = ui.Card(stack, "DPS BUILDS", "MythicSim level-60 references: Retribution 10/8/33; Shockadin 23/0/28")
	local function SelectBuild(key, other)
		rotation.SelectBuild(ui.Profile(), key, ui.Profile()[key] == true)
		ui.Repaint()
	end
	Check(buildCard, "retribution", "Use Retribution (10/8/33)", "Seal of Command",
		"Uses learned Retribution damage and execute priorities. Automatic seal mode prepares Command for learned Twist of Light when aura data is readable. Otherwise it keeps the weapon-based single-seal choice. Selecting this disables Shockadin and Tank. Talents and equipment are not changed.", true,
		function() SelectBuild("retribution", "shockadin") end)
	Check(buildCard, "shockadin", "Use Shockadin", "Holy Shock",
		"Uses learned Shockadin damage priorities and automatic Seal of Righteousness. Selecting this disables Retribution and Tank. Select Leveling Rotation to use the earlier DPS priority. Talents and equipment are not changed.", true,
		function() SelectBuild("shockadin", "retribution") end)
	Check(buildCard, "sealTwisting", "Use Twist of Light", "Seal of Command",
		"Retribution only, in melee and with Automatic seal mode. Requires the learned capstone and both seals. Swaps Command and Righteousness only when readable aura data confirms the previous Echo is gone. Protected or incomplete aura data falls back to maintaining one seal according to your weapon or explicit seal choice.", true)
	Slider(buildCard, "sealTwistMinMana", "Seal twisting minimum mana", 0, 100, 15, " %")
	ui.Info(buildCard, "Area damage requires AoE On. Divine Favor requires Burst On and an eligible offensive Holy Shock. Only learned and enabled spells are used.")
	local tankCard = ui.Card(stack, "PROTECTION — 8/33/10", "Tank defenses and Judgement reset")
	Check(tankCard, "holyShield", "Maintain Holy Shield", "Holy Shield",
		"Tank only. Requires the learned spell and an equipped shield. Prepares for a nearby pull and maintains block protection in melee combat. Uses confirmed casts when aura or cooldown data is protected.", true)
	Slider(tankCard, "holyShieldMinMana", "Holy Shield minimum mana", 0, 100, 10, " %")
	Check(tankCard, "swiftJudgement", "Burst: use Swift Judgement", "Swift Judgement",
		"Tank only and Burst On. Resets a cooling-down Judgement when an active seal, the Judgement checkbox, target range, mana slider and target-health limits allow the follow-up. It is never used while Judgement is already ready.", true)
	Check(tankCard, "templarsBulwark", "Use Templar's Bulwark", "Templar's Bulwark",
		"Tank only, with emergency spells enabled. Uses the learned absorb at or below its health slider, unless Forbearance or the absorb is already active. Independent of Burst On. Tank never automatically uses Divine Protection or Divine Shield.", true)
	Slider(tankCard, "templarsBulwarkHP", "Templar's Bulwark at or below health", 5, 80, 35, " %")
	ui.Info(tankCard, "Automatic Tank preparation keeps Seal of Fury, Righteous Fury, Blessing of Wisdom and Devotion Aura. Explicit seal, blessing and aura choices take priority. Area damage still requires AoE On and enough engaged nearby enemies.")

	local steel = { 0.72, 0.62, 0.50, 1 }
	local head = ui.Card(stack,
		Text({ en = "PALADIN - LIVE STATUS", fr = "PALADIN - ETAT EN DIRECT", pt = "PALADINO - STATUS AO VIVO", es = "PALADÍN - ESTADO EN VIVO", de = "PALADIN - LIVE-STATUS", zh = "圣骑士 - 实时状态" }),
		Text({ en = "Level 1-60 - interface " .. UI_VERSION, fr = "Niveaux 1-60 - interface " .. UI_VERSION, pt = "Níveis 1-60 - interface " .. UI_VERSION, es = "Niveles 1-60 - interfaz " .. UI_VERSION, de = "Stufe 1-60 - Interface " .. UI_VERSION, zh = "等级 1-60 - 界面 " .. UI_VERSION }))
	local rowA = ui.BadgeRow(head, 3)
	local rowB = ui.BadgeRow(head, 3)
	local rowC = ui.BadgeRow(head, 3)
	local rowD = ui.BadgeRow(head, 2)
	local badges = {
		level = rowA.badges[1], mana = rowA.badges[2], spells = rowA.badges[3],
		role = rowB.badges[1], seal = rowB.badges[2], aura = rowB.badges[3],
		blessing = rowC.badges[1], enemies = rowC.badges[2], shield = rowC.badges[3],
		aoe = rowD.badges[1], burst = rowD.badges[2],
	}
	ui.Info(head, Text({
		en = "Forever may protect mana, auras and enemy counts in combat. Unknown values remain unknown; they are never converted to zero.",
		fr = "Forever peut proteger le mana, les auras et le nombre d'ennemis en combat. Une valeur inconnue reste inconnue et n'est jamais convertie en zero.",
		pt = "Forever pode proteger mana, auras e contagem de inimigos em combate. Valores desconhecidos continuam desconhecidos; nunca são convertidos em zero.",
		es = "Forever puede proteger el maná, las auras y el número de enemigos en combate. Los valores desconocidos siguen desconocidos; nunca se convierten en cero.",
		de = "Forever kann Mana, Auren und Gegnerzahl im Kampf schützen. Unbekannte Werte bleiben unbekannt; sie werden nie zu null.",
		zh = "Forever 可能在战斗中保护法力、光环和敌人数量。未知数值保持未知，绝不会被转换为零。",
	}), { justify = "CENTER" })

	local preparation = ui.Card(stack,
		Text({ en = "BLESSINGS, AURAS & SEALS", fr = "BENEDICTIONS, AURAS ET SCEAUX", pt = "BÊNÇÃOS, AURAS E SELOS", es = "BENDICIONES, AURAS Y SELLOS", de = "SEGEN, AUREN & SIEGEL", zh = "祝福、光环和圣印" }))
	Check(preparation, "buffs",
		{ en = "Maintain selected preparation", fr = "Maintenir la preparation choisie", pt = "Manter a preparação escolhida", es = "Mantener la preparación elegida", de = "Gewählte Vorbereitung halten", zh = "维持所选准备" },
		"Blessing of Might",
		{ en = "Maintains the selected blessing, aura, tank threat buff and seal.", fr = "Maintient la benediction, l'aura, le buff de menace Tank et le sceau selectionnes.", pt = "Mantém a bênção, a aura, o buff de ameaça de tanque e o selo escolhidos.", es = "Mantiene la bendición, el aura, el beneficio de amenaza de tanque y el sello elegidos.", de = "Hält den gewählten Segen, die Aura, den Tank-Bedrohungsbuff und das Siegel aufrecht.", zh = "维持所选的祝福、光环、坦克仇恨增益和圣印。" }, true)
	Dropdown(preparation, "blessingMode",
		{ en = "Preferred blessing", fr = "Benediction preferee", pt = "Bênção preferida", es = "Bendición preferida", de = "Bevorzugter Segen", zh = "首选祝福" }, {
			{ label = { en = "Automatic by role", fr = "Automatique selon le role", pt = "Automático pela função", es = "Automático según el rol", de = "Automatisch nach Rolle", zh = "按职责自动" }, value = "AUTO" },
			{ label = "Blessing of Might", value = "MIGHT" },
			{ label = "Blessing of Wisdom", value = "WISDOM" },
		}, "AUTO")
	Dropdown(preparation, "auraMode",
		{ en = "Preferred aura", fr = "Aura preferee", pt = "Aura preferida", es = "Aura preferida", de = "Bevorzugte Aura", zh = "首选光环" }, {
			{ label = { en = "Automatic by role", fr = "Automatique selon le role", pt = "Automático pela função", es = "Automático según el rol", de = "Automatisch nach Rolle", zh = "按职责自动" }, value = "AUTO" },
			{ label = "Retribution Aura", value = "RETRIBUTION" },
			{ label = "Devotion Aura", value = "DEVOTION" },
			{ label = "Concentration Aura", value = "CONCENTRATION" },
		}, "AUTO")
	Dropdown(preparation, "seal",
		{ en = "Preferred seal", fr = "Sceau prefere", pt = "Selo preferido", es = "Sello preferido", de = "Bevorzugtes Siegel", zh = "首选圣印" }, {
			{ label = { en = "Automatic by role and weapon", fr = "Automatique selon le role et l'arme", pt = "Automático pela função e arma", es = "Automático según rol y arma", de = "Automatisch nach Rolle und Waffe", zh = "按职责和武器自动" }, value = "AUTO" },
			{ label = "Seal of Command", value = "COMMAND" },
			{ label = "Seal of Righteousness", value = "RIGHTEOUSNESS" },
			{ label = "Seal of Fury", value = "FURY" },
		}, "AUTO")
	ui.Info(preparation, Text({
		en = "Protection Auto prefers learned Seal of Fury. Righteous Fury remains a separate threat buff.",
		fr = "En Protection, Auto prefere Seal of Fury appris. Righteous Fury reste un buff de menace distinct.",
		pt = "Em Proteção, Auto prefere Seal of Fury aprendido. Righteous Fury continua como um buff de ameaça separado.",
		es = "En Protección, Auto prefiere Seal of Fury aprendido. Righteous Fury sigue siendo un beneficio de amenaza separado.",
		de = "Schutz-Auto bevorzugt das erlernte Seal of Fury. Righteous Fury bleibt ein eigener Bedrohungsbuff.",
		zh = "防护自动模式优先使用已学会的 Seal of Fury。Righteous Fury 仍是独立的仇恨增益。",
	}))
	Check(preparation, "tankRighteousFury", "Righteous Fury", "Righteous Fury",
		{ en = "Protection only. Maintains the threat buff whenever it is learned.", fr = "Protection uniquement. Maintient le buff de menace lorsqu'il est appris.", pt = "Somente Proteção. Mantém o buff de ameaça quando aprendido.", es = "Solo Protección. Mantiene el beneficio de amenaza cuando está aprendido.", de = "Nur Schutz. Hält den Bedrohungsbuff aufrecht, sobald er erlernt ist.", zh = "仅限防护。学会后维持仇恨增益。" }, true)

	local offense = ui.Card(stack,
		Text({ en = "OFFENSIVE PRIORITY", fr = "PRIORITE OFFENSIVE", pt = "PRIORIDADE OFENSIVA", es = "PRIORIDAD OFENSIVA", de = "OFFENSIVPRIORITÄT", zh = "进攻优先级" }))
	Check(offense, "holyShock", "Use Holy Shock", "Holy Shock", "Shockadin: casts on cooldown when learned, enabled and above the configured mana minimum.")
	Slider(offense, "holyShockMinMana", "Holy Shock minimum mana", 0, 100, 10, " %")
	Check(offense, "hammerOfWrath", "Use Hammer of Wrath", "Hammer of Wrath", "Protection, Retribution and Shockadin: casts when target health is at or below 20%, the spell is learned and ready, the player is stationary, and mana meets the configured minimum.")
	Slider(offense, "hammerOfWrathMinMana", "Hammer of Wrath minimum mana", 0, 100, 10, " %")
	Check(offense, "holystrike", "Holy Strike", "Holy Strike",
		{ en = "Main melee strike when learned, ready and affordable.", fr = "Attaque de melee principale lorsqu'elle est apprise, disponible et abordable.", pt = "Golpe corpo a corpo principal quando aprendido, pronto e com mana suficiente.", es = "Golpe cuerpo a cuerpo principal cuando está aprendido, listo y es asequible.", de = "Hauptangriff im Nahkampf, wenn erlernt, bereit und bezahlbar.", zh = "已学会、可用且资源足够时的主要近战攻击。" })
	Check(offense, "judgement", "Judgement", "Judgement",
		{ en = "Used as a ranged opener and on cooldown while a seal is active.", fr = "Utilise comme ouverture a distance puis des qu'il est disponible avec un sceau actif.", pt = "Usado como abertura à distância e sempre que disponível com um selo ativo.", es = "Se usa como apertura a distancia y en cuanto está disponible con un sello activo.", de = "Als Fernkampf-Opener und sofort bei Bereitschaft genutzt, solange ein Siegel aktiv ist.", zh = "用作远程起手，并在圣印激活时冷却就绪即使用。" })
	Slider(offense, "holyStrikeMinMana",
		{ en = "Holy Strike minimum mana", fr = "Mana minimum Holy Strike", pt = "Mana mínima Holy Strike", es = "Maná mínimo Holy Strike", de = "Holy Strike Mindest-Mana", zh = "Holy Strike 最低法力" }, 0, 100, 10, " %")
	Slider(offense, "judgementMinMana",
		{ en = "Judgement minimum mana", fr = "Mana minimum Judgement", pt = "Mana mínima Judgement", es = "Maná mínimo Judgement", de = "Judgement Mindest-Mana", zh = "Judgement 最低法力" }, 0, 100, 15, " %")
	Slider(offense, "judgementMinTargetHP",
		{ en = "Judgement minimum target health", fr = "Vie cible minimum pour Judgement", pt = "Vida mínima do alvo para Judgement", es = "Vida mínima del objetivo para Judgement", de = "Judgement Mindest-Zielgesundheit", zh = "Judgement 目标最低生命值" }, 0, 100, 20, " %")
	Check(offense, "exorcism",
		{ en = "Exorcism against undead/demons", fr = "Exorcism sur morts-vivants/demons", pt = "Exorcism contra mortos-vivos/demônios", es = "Exorcism contra no-muertos/demonios", de = "Exorcism gegen Untote/Dämonen", zh = "对亡灵/恶魔使用 Exorcism" }, "Exorcism")
	Slider(offense, "exorcismMinMana",
		{ en = "Exorcism minimum mana", fr = "Mana minimum Exorcism", pt = "Mana mínima Exorcism", es = "Maná mínimo Exorcism", de = "Exorcism Mindest-Mana", zh = "Exorcism 最低法力" }, 0, 100, 25, " %")
	Slider(offense, "exorcismMinTargetHP",
		{ en = "Exorcism minimum target health", fr = "Vie cible minimum pour Exorcism", pt = "Vida mínima do alvo para Exorcism", es = "Vida mínima del objetivo para Exorcism", de = "Exorcism Mindest-Zielgesundheit", zh = "Exorcism 目标最低生命值" }, 0, 100, 25, " %")
	Check(offense, "hsicon",
		{ en = "Alternate Holy Strike icon", fr = "Icone alternative Holy Strike", pt = "Ícone alternativo Holy Strike", es = "Icono alternativo Holy Strike", de = "Alternatives Holy Strike-Symbol", zh = "Holy Strike 备用图标" }, "Holy Strike",
		{ en = "Use the alternate Holy Strike artwork. A selected Universal icon takes priority.", fr = "Utilise l'illustration alternative de Holy Strike. L'icone Universal selectionnee est prioritaire.", pt = "Usa a imagem alternativa de Holy Strike. O ícone Universal selecionado tem prioridade.", es = "Usa la imagen alternativa de Holy Strike. El icono Universal seleccionado tiene prioridad.", de = "Nutzt das alternative Holy Strike-Symbol. Ein gewähltes Universal-Symbol hat Vorrang.", zh = "使用 Holy Strike 备用图标。已选择的通用图标优先。" }, true)

	local aoe = ui.Card(stack,
		Text({ en = "AOE & BURST", fr = "AOE ET BURST", pt = "AOE E BURST", es = "AOE Y BURST", de = "AOE & BURST", zh = "AOE 和爆发" }))
	Check(aoe, "aoe", { en = "Enable AoE mode", fr = "Activer le mode AoE", pt = "Ativar modo AoE", es = "Activar modo AoE", de = "AoE-Modus aktivieren", zh = "启用 AoE 模式" }, nil,
		{ en = "Allows Consecration only after the enemy threshold is confirmed.", fr = "Autorise Consecration uniquement lorsque le seuil d'ennemis est confirme.", pt = "Permite Consecration apenas após confirmar o limite de inimigos.", es = "Permite Consecration solo tras confirmar el umbral de enemigos.", de = "Erlaubt Consecration erst, wenn die Gegnerschwelle bestätigt ist.", zh = "仅在确认敌人数量阈值后才允许 Consecration。" })
	Check(aoe, "consecration", "Consecration", "Consecration")
	Check(aoe, "hammerOfTheRighteous", "Use Hammer of the Righteous", "Hammer of the Righteous",
		"Protection and Retribution, AoE On only. Uses this attack instead of Holy Strike when learned, in melee and the engaged-enemy threshold is met. Their cooldown is shared.")
	Slider(aoe, "hammerOfTheRighteousMinMana", "Hammer of the Righteous minimum mana", 0, 100, 10, " %")
	Check(aoe, "holyWrath", "Use Holy Wrath", "Holy Wrath",
		"Protection and Retribution, AoE On only. Requires a learned rank, an undead or demon target, the engaged-enemy threshold, sufficient mana and a stationary player.")
	Slider(aoe, "holyWrathMinMana", "Holy Wrath minimum mana", 0, 100, 35, " %")
	Slider(aoe, "aoeMinEnemies",
		{ en = "Minimum enemies", fr = "Ennemis minimum", pt = "Mínimo de inimigos", es = "Mínimo de enemigos", de = "Mindestanzahl Gegner", zh = "最少敌人数" }, 2, 5, 2, "")
	Slider(aoe, "consecrationMinMana",
		{ en = "DPS Consecration minimum mana", fr = "Mana minimum Consecration DPS", pt = "Mana mínima Consecration DPS", es = "Maná mínimo Consecration DPS", de = "DPS-Consecration Mindest-Mana", zh = "DPS Consecration 最低法力" }, 0, 100, 35, " %")
	Slider(aoe, "tankConsecrationMinMana",
		{ en = "Tank Consecration minimum mana", fr = "Mana minimum Consecration Tank", pt = "Mana mínima Consecration Tanque", es = "Maná mínimo Consecration Tanque", de = "Tank-Consecration Mindest-Mana", zh = "坦克 Consecration 最低法力" }, 0, 100, 20, " %")
	Slider(aoe, "burstMinTargetHP",
		{ en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Vida mínima del objetivo para Burst", de = "Burst Mindest-Zielgesundheit", zh = "爆发目标最低生命值" }, 0, 100, 40, " %")
	Check(aoe, "divineFavor", "Use Divine Favor", "Divine Favor",
		"Shockadin Burst On only. Prepares a guaranteed critical Holy Shock when learned, enabled, ready, in range and above the Holy Shock mana threshold. The Burst target-health slider controls activation.", true)
	ui.Info(aoe, Text({
		en = "If the enemy count is protected, Consecration is withheld instead of being guessed on a single target.",
		fr = "Si le nombre d'ennemis est protege, Consecration est retenu au lieu d'etre suppose sur une cible unique.",
		pt = "Se a contagem de inimigos estiver protegida, Consecration é retido em vez de ser presumido em um alvo único.",
		es = "Si el número de enemigos está protegido, Consecration se retiene en lugar de suponerse sobre un objetivo único.",
		de = "Ist die Gegnerzahl geschützt, wird Consecration zurückgehalten, statt bei einem Einzelziel geraten zu werden.",
		zh = "如果敌人数量受保护，将暂缓 Consecration，而不是按单体目标猜测。",
	}))

	local survival = ui.Card(stack,
		Text({ en = "HEALING & SURVIVAL", fr = "SOINS ET SURVIE", pt = "CURA E SOBREVIVÊNCIA", es = "SANACIÓN Y SUPERVIVENCIA", de = "HEILUNG & ÜBERLEBEN", zh = "治疗和生存" }))

	Check(survival, "oocHeal",
		{ en = "Holy Light out of combat", fr = "Holy Light hors combat", pt = "Holy Light fora de combate", es = "Holy Light fuera de combate", de = "Holy Light außerhalb des Kampfes", zh = "非战斗时使用 Holy Light" }, "Holy Light",
		{ en = "Heal yourself below the selected health threshold. Enabled by default at 80%. Uses the healing mana minimum and the learned spell cost.", fr = "Soignez-vous sous le seuil choisi. Activé par défaut à 80 %. Respecte le mana minimum des soins et le coût du rang appris.", pt = "Cura você abaixo da vida escolhida. Ativado por padrão em 80%. Respeita a mana mínima de cura e o custo do nível aprendido.", es = "Te sana por debajo de la salud elegida. Activado por defecto al 80%. Respeta el maná mínimo de sanación y el coste aprendido.", de = "Heilt dich unter der gewählten Gesundheit. Standardmäßig bei 80% aktiviert. Beachtet Mindestmana und Kosten des erlernten Rangs.", zh = "生命值低于所选阈值时治疗自己。默认启用，阈值为80%。遵循治疗最低法力值和已学等级的消耗。" }, true)
	Slider(survival, "oocHealHP",
		{ en = "Out-of-combat heal below health", fr = "Soins hors combat sous ce niveau de vie", pt = "Curar fora de combate abaixo desta vida", es = "Sanar fuera de combate por debajo de esta salud", de = "Außerhalb des Kampfes unter Gesundheit heilen", zh = "非战斗治疗生命值低于" }, 5, 100, 80, " % HP")
	Check(survival, "emergency",
		{ en = "Enable survival suggestions", fr = "Activer les suggestions de survie", pt = "Ativar sugestões de sobrevivência", es = "Activar sugerencias de supervivencia", de = "Überlebensvorschläge aktivieren", zh = "启用生存建议" }, nil,
		{ en = "Master switch for combat healing, immunities and Lay on Hands. Out-of-combat healing has its own checkbox.", fr = "Interrupteur des soins en combat, immunités et Lay on Hands. Les soins hors combat ont leur propre case.", pt = "Chave para cura em combate, imunidades e Lay on Hands. A cura fora de combate tem sua própria opção.", es = "Interruptor de sanación en combate, inmunidades y Lay on Hands. La sanación fuera de combate tiene su propia opción.", de = "Schalter für Heilung im Kampf, Immunitäten und Lay on Hands. Heilung außerhalb des Kampfes hat eine eigene Option.", zh = "战斗治疗、无敌和 Lay on Hands 的总开关。非战斗治疗有独立开关。" }, true)
	Check(survival, "flashHeal", "Flash of Light", "Flash of Light")
	Slider(survival, "flashHealHP",
		{ en = "Flash of Light health threshold", fr = "Seuil de vie Flash of Light", pt = "Limite de vida Flash of Light", es = "Umbral de vida Flash of Light", de = "Flash of Light Gesundheitsschwelle", zh = "Flash of Light 生命阈值" }, 5, 95, 55, " % HP")
	Check(survival, "holyHeal", "Holy Light", "Holy Light")
	Slider(survival, "holyHealHP",
		{ en = "Holy Light health threshold", fr = "Seuil de vie Holy Light", pt = "Limite de vida Holy Light", es = "Umbral de vida Holy Light", de = "Holy Light Gesundheitsschwelle", zh = "Holy Light 生命阈值" }, 5, 90, 35, " % HP")
	Slider(survival, "healMinMana",
		{ en = "Healing minimum mana", fr = "Mana minimum pour les soins", pt = "Mana mínima para cura", es = "Maná mínimo para sanar", de = "Heilung Mindest-Mana", zh = "治疗最低法力" }, 0, 100, 10, " %")
	Check(survival, "divineProtection", "Divine Protection", "Divine Protection")
	Slider(survival, "divineProtectionHP",
		{ en = "Divine Protection health threshold", fr = "Seuil de vie Divine Protection", pt = "Limite de vida Divine Protection", es = "Umbral de vida Divine Protection", de = "Divine Protection Gesundheitsschwelle", zh = "Divine Protection 生命阈值" }, 5, 80, 30, " % HP")
	Check(survival, "divineShield", "Divine Shield", "Divine Shield",
		{ en = "Retribution only. It is never suggested while the Tank role is active.", fr = "Vindicte uniquement. Il n'est jamais propose lorsque le role Tank est actif.", pt = "Somente Retribuição. Nunca é sugerido com a função Tanque ativa.", es = "Solo Reprensión. Nunca se sugiere con el rol de Tanque activo.", de = "Nur Vergeltung. Wird bei aktiver Tank-Rolle nie vorgeschlagen.", zh = "仅限惩戒。坦克职责激活时绝不会建议。" })
	Slider(survival, "divineShieldHP",
		{ en = "Divine Shield health threshold", fr = "Seuil de vie Divine Shield", pt = "Limite de vida Divine Shield", es = "Umbral de vida Divine Shield", de = "Divine Shield Gesundheitsschwelle", zh = "Divine Shield 生命阈值" }, 5, 60, 18, " % HP")
	Check(survival, "layOnHands", "Lay on Hands", "Lay on Hands")
	Slider(survival, "layOnHandsHP",
		{ en = "Lay on Hands health threshold", fr = "Seuil de vie Lay on Hands", pt = "Limite de vida Lay on Hands", es = "Umbral de vida Lay on Hands", de = "Lay on Hands Gesundheitsschwelle", zh = "Lay on Hands 生命阈值" }, 1, 50, 10, " % HP")

	local utility = ui.Card(stack,
		Text({ en = "CONTROL & RECOVERY", fr = "CONTROLE ET RECUPERATION", pt = "CONTROLE E RECUPERAÇÃO", es = "CONTROL Y RECUPERACIÓN", de = "KONTROLLE & ERHOLUNG", zh = "控制和恢复" }))
	Check(utility, "hammer",
		{ en = "Hammer of Justice on casting targets", fr = "Hammer of Justice sur les cibles qui incantent", pt = "Hammer of Justice em alvos conjurando", es = "Hammer of Justice en objetivos lanzando", de = "Hammer of Justice auf zaubernde Ziele", zh = "对施法目标使用 Hammer of Justice" }, "Hammer of Justice")
	Check(utility, "drink", { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" })
	Slider(utility, "drinkMana",
		{ en = "Drink at or below mana", fr = "Boire à ce niveau de mana ou en dessous", pt = "Beber com mana igual ou abaixo de", es = "Beber con maná igual o inferior", de = "Trinken bei oder unter Mana", zh = "法力等于或低于此值时喝水" }, 0, 80, 30, " %")
	ui.Info(utility, Text({
		en = "Purify, Blessing of Freedom and Blessing of Protection remain available in the Spells tab, but are not guessed without a readable player debuff.",
		fr = "Purify, Blessing of Freedom et Blessing of Protection restent disponibles dans l'onglet Sorts, mais ne sont pas devines sans debuff joueur lisible.",
		pt = "Purify, Blessing of Freedom e Blessing of Protection continuam disponíveis na aba Feitiços, mas não são presumidos sem um debuff legível no jogador.",
		es = "Purify, Blessing of Freedom y Blessing of Protection siguen disponibles en la pestaña Hechizos, pero no se suponen sin un perjuicio legible en el jugador.",
		de = "Purify, Blessing of Freedom und Blessing of Protection bleiben im Tab Zauber verfügbar, werden aber ohne lesbaren Spieler-Debuff nicht geraten.",
		zh = "Purify、Blessing of Freedom 和 Blessing of Protection 仍可在法术标签页中使用，但无法读取玩家减益时不会猜测使用。",
	}))

	local last = {}
	local function SetBadge(key, value, color)
		if last[key] == value then return end
		last[key] = value
		badges[key]:SetBadge(value, color)
	end

	local function ShortName(value, fallback)
		if not value then return fallback end
		return value:gsub("Seal of ", ""):gsub(" Aura", ""):gsub("Blessing of ", "")
	end

	local function Paint()
		local state = rotation and rotation.GetUIState and rotation.GetUIState() or {}
		local profile = ui.Profile()
		SetBadge("level", (AL.L and AL.L("LEVEL") or "LEVEL") .. " " .. tostring(state.level or "?"), steel)
		SetBadge("mana", type(state.mana) == "number" and ("MANA " .. math.floor(state.mana + 0.5) .. "%") or "MANA ?",
			type(state.mana) == "number" and theme.gold or (theme.warn or theme.gold))
		SetBadge("spells", tostring(state.knownCount or 0) .. " " .. (AL.L and AL.L("SPELLS"):upper() or "SPELLS"), steel)
		SetBadge("role", state.role == "TANK" and "TANK" or state.shockadin and "SHOCKADIN" or "RETRIBUTION",
			state.role == "TANK" and (theme.warn or theme.gold) or theme.ok)
		SetBadge("seal", "SEAL " .. ShortName(state.seal, "?"), state.seal and theme.gold or steel)
		SetBadge("aura", "AURA " .. ShortName(state.aura, "?"), state.aura and theme.gold or steel)
		SetBadge("blessing", "BUFF " .. ShortName(state.blessing, "?"), state.blessing and theme.gold or steel)
		SetBadge("enemies", "ENEMIES " .. tostring(state.enemyCount or "?"), steel)
		local shield = state.hasShield == true and "SHIELD"
			or (state.hasShield == false and "NO SHIELD" or "SHIELD ?")
		SetBadge("shield", shield, state.hasShield == true and theme.ok or steel)
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
	AL.RegisterClassUI("PALADIN", BuildPaladinUI, UI_VERSION)
end
if AL.rotations and AL.rotations.PALADIN then
	AL.rotations.PALADIN.uiVersion = UI_VERSION
end
