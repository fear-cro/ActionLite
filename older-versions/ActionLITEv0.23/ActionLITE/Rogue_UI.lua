local ADDON, AL = ...
local UI_VERSION = "0.12.1"

-- Interface Rogue dediee. Toutes les cles ecrites ici sont lues directement
-- par rotation\Rogue.lua ; aucune priorite de combat n'est dupliquee dans l'UI.

local function Text(value)
	if type(value) ~= "table" then return tostring(value or "") end
	local language = AL.GetUILanguage and AL.GetUILanguage() or "en"
	return value[language] or value.en or value.fr or ""
end

local function BuildRogueUI(page, ui)
	local rotation = AL.rotations and AL.rotations.ROGUE
	local theme = ui.Theme
	local stack = ui.Body(page)
	local spellIDs = {}
	for _, entry in ipairs((rotation and rotation.spells) or {}) do
		spellIDs[entry[2]] = entry[1]
	end

	local function SpellIcon(name)
		return ui.SpellIcon(name, spellIDs[name])
	end
	local function Check(card, key, label, spell, help)
		return ui.SettingCheck(card, key, {
			label = Text(label),
			icon = spell and SpellIcon(spell) or nil,
			half = true,
			tooltip = help and { Text(label), Text(help) } or nil,
			onChange = ui.Repaint,
		})
	end
	local function Slider(card, key, label, minimum, maximum, default, suffix, help)
		return ui.Slider(card, {
			profileKey = key,
			label = Text(label), half = true,
			min = minimum, max = maximum, step = 1, suffix = suffix or "",
			get = function() return tonumber(ui.Profile()[key]) or default end,
			set = function(value) ui.Profile()[key] = value end,
			tooltip = help and { Text(label), Text(help) } or nil,
		})
	end
	local function ComboSlider(card, key, label, default, help)
		return Slider(card, key, label, 1, 5, default, "", help)
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
			get = function() return ui.Profile()[key] or default end,
			set = function(value) ui.Profile()[key] = value end,
			onSelect = ui.Repaint,
		})
	end

	local steel = { 0.72, 0.62, 0.50, 1 }
	local head = ui.Card(stack,
		Text({ en = "ROGUE - COMBAT LEVELING", fr = "VOLEUR - PROGRESSION COMBAT", pt = "LADINO - PROGRESSÃO COMBATE", es = "PÍCARO - PROGRESIÓN COMBATE", de = "SCHURKE - KAMPF-LEVELN", zh = "潜行者 - 战斗升级" }),
		Text({ en = "Level 1-30 - interface " .. UI_VERSION, fr = "Niveaux 1-30 - interface " .. UI_VERSION, pt = "Níveis 1-30 - interface " .. UI_VERSION, es = "Niveles 1-30 - interfaz " .. UI_VERSION, de = "Stufe 1-30 - Interface " .. UI_VERSION, zh = "等级 1-30 - 界面 " .. UI_VERSION }))
	local rowA = ui.BadgeRow(head, 3)
	local rowB = ui.BadgeRow(head, 3)
	local rowC = ui.BadgeRow(head, 2)
	local badges = {
		level = rowA.badges[1], energy = rowA.badges[2], combo = rowA.badges[3],
		spells = rowB.badges[1], aoe = rowB.badges[2], burst = rowB.badges[3],
		stealth = rowC.badges[1], weapon = rowC.badges[2],
	}
	ui.Info(head, Text({
		en = "Forever may protect energy and combo points. ActionLITE uses readable values first, then cast and combat-log inference without treating unknown values as zero.",
		fr = "Forever peut proteger l'energie et les points de combo. ActionLITE utilise d'abord les valeurs lisibles, puis une inference des lancers et du journal de combat sans assimiler l'inconnu a zero.",
		pt = "Forever pode proteger a energia e os pontos de combo. O ActionLITE usa primeiro os valores legíveis, depois a inferência de lançamentos e do registro de combate, sem tratar o desconhecido como zero.",
		es = "Forever puede proteger la energía y los puntos de combo. ActionLITE usa primero los valores legibles y luego la inferencia de lanzamientos y del registro de combate, sin tratar lo desconocido como cero.",
		de = "Forever kann Energie und Combopunkte schützen. ActionLITE nutzt zuerst lesbare Werte, dann Ableitungen aus Zaubern und Kampflog, ohne Unbekanntes als null zu werten.",
		zh = "Forever 可能会保护能量和连击点。ActionLITE 优先使用可读数值，然后根据施法和战斗日志推断，不会把未知值当作零。",
	}), { justify = "CENTER" })

	local opening = ui.Card(stack,
		Text({ en = "STEALTH & OPENING", fr = "FURTIVITE ET OUVERTURE", pt = "FURTIVIDADE E ABERTURA", es = "SIGILO Y APERTURA", de = "STEALTH & ERÖFFNUNG", zh = "潜行与起手" }))
	Check(opening, "stealth",
		{ en = "Suggest entering Stealth", fr = "Proposer le passage en Stealth", pt = "Sugerir entrar em Stealth", es = "Sugerir entrar en Stealth", de = "Stealth vorschlagen", zh = "建议进入 Stealth" }, "Stealth",
		{ en = "Suggest Stealth outside combat when a hostile target is within approximately 10 yards. Manual Stealth is still detected when this option is off." })
	Dropdown(opening, "openerMode",
		{ en = "Preferred opener", fr = "Ouverture preferee", pt = "Abertura preferida", es = "Apertura preferida", de = "Bevorzugter Eröffner", zh = "首选起手技" }, {
			{ label = { en = "Automatic", fr = "Automatique", pt = "Automático", es = "Automático", de = "Automatisch", zh = "自动" }, value = "AUTO" },
			{ label = "Backstab", value = "BACKSTAB" },
			{ label = "Cheap Shot", value = "CHEAP_SHOT" },
			{ label = "Ambush", value = "AMBUSH" },
			{ label = "Garrote", value = "GARROTE" },
		}, "BACKSTAB")
	ui.Info(opening, "Automatic tries Backstab first with a dagger, then another learned opener. Backstab still requires melee range and standing behind the target. A reported position failure selects a fallback; combat uses Sinister Strike.")

	local builders = ui.Card(stack,
		Text({ en = "BUILDERS & PROCS", fr = "GENERATEURS ET PROCS", pt = "GERADORES E PROCS", es = "GENERADORES Y PROCS", de = "AUFBAUER & PROCS", zh = "生成技与触发" }))
	ui.Info(builders, "Energy sliders set the minimum energy before using a builder. The spell must also be affordable.")
	ui.Info(builders, "Sinister Strike is the combat builder. Backstab is a Stealth opener; general spell usability does not prove that you are behind the target.")
	Slider(builders, "sinisterMinEnergy", "Sinister Strike", 20, 100, 45, " energy",
		{ en = "Minimum energy before suggesting Sinister Strike.", fr = "Energie minimale avant de proposer Sinister Strike.", pt = "Energia mínima antes de sugerir Sinister Strike.", es = "Energía mínima antes de sugerir Sinister Strike.", de = "Minimale Energie, bevor Sinister Strike vorgeschlagen wird.", zh = "建议 Sinister Strike 前所需的最低能量。" })
	Slider(builders, "backstabMinEnergy", "Backstab", 20, 100, 60, " energy",
		{ en = "Minimum energy before suggesting Backstab.", fr = "Energie minimale avant de proposer Backstab.", pt = "Energia mínima antes de sugerir Backstab.", es = "Energía mínima antes de sugerir Backstab.", de = "Minimale Energie, bevor Backstab vorgeschlagen wird.", zh = "建议 Backstab 前所需的最低能量。" })
	Check(builders, "riposte", "Riposte", "Riposte",
		{ en = "Suggested only when the learned talent becomes usable after a parry.", fr = "Propose uniquement lorsque le talent appris devient utilisable apres une parade.", pt = "Sugerido apenas quando o talento aprendido fica utilizável após um aparo.", es = "Solo se sugiere cuando el talento aprendido se vuelve utilizable tras una parada.", de = "Wird nur vorgeschlagen, wenn das erlernte Talent nach einer Parade nutzbar wird.", zh = "仅在招架后已学会的天赋变为可用时建议。" })

	local finishers = ui.Card(stack,
		Text({ en = "FINISHERS", fr = "COUPS DE GRACE", pt = "FINALIZADORES", es = "REMATES", de = "FINISHER", zh = "终结技" }))
	Check(finishers, "snd", "Slice and Dice", "Slice and Dice",
		{ en = "Use exactly one combo point, only while the player attack-speed buff is absent. Slice and Dice is a player buff, not an enemy debuff." })
	ui.Info(finishers, "Slice and Dice: exactly one combo point, learned/enabled, and only when its player buff is missing. Preserve accumulated points for Eviscerate. The same one-point rule applies to normal, rare and elite targets.")

	Check(finishers, "rupture", "Rupture", "Rupture",
		{ en = "Optional damage-over-time finisher for durable targets.", fr = "Coup de grace periodique optionnel pour les cibles durables.", pt = "Finalizador de dano periódico opcional para alvos resistentes.", es = "Remate de daño periódico opcional para objetivos resistentes.", de = "Optionaler DoT-Finisher für zähe Ziele.", zh = "针对耐打目标的可选持续伤害终结技。" })
	ComboSlider(finishers, "ruptureMinCP",
		{ en = "Rupture combo points", fr = "Points de combo Rupture", pt = "Pontos de combo Rupture", es = "Puntos de combo Rupture", de = "Combopunkte für Rupture", zh = "Rupture 连击点" }, 4)


	Check(finishers, "expose", "Expose Armor", "Expose Armor",
		{ en = "Disabled by default because it consumes combo points and may conflict with group armor reductions.", fr = "Desactive par defaut car il consomme les points de combo et peut entrer en conflit avec les reductions d'armure du groupe.", pt = "Desativado por padrão, pois consome pontos de combo e pode conflitar com as reduções de armadura do grupo.", es = "Desactivado por defecto porque consume puntos de combo y puede entrar en conflicto con las reducciones de armadura del grupo.", de = "Standardmäßig aus, da es Combopunkte verbraucht und mit Rüstungsreduzierungen der Gruppe kollidieren kann.", zh = "默认关闭，因为它会消耗连击点，且可能与队伍的护甲削弱效果冲突。" })
	ComboSlider(finishers, "exposeMinCP",
		{ en = "Expose Armor combo points", fr = "Points de combo Expose Armor", pt = "Pontos de combo Expose Armor", es = "Puntos de combo Expose Armor", de = "Combopunkte für Expose Armor", zh = "Expose Armor 连击点" }, 4)


	ui.Divider(finishers)
	ui.Info(finishers, "Eviscerate: target health at or below 50%, with 1+ combo points on normal targets or five on rare/elite targets. At zero points, build first. Above 50%, keep using builders. The old finisher sliders no longer override these rules.")
	ui.Info(finishers, "Optional Rupture/Expose Armor are used only at or below 50% target health when Eviscerate is unavailable or disabled, with the selected combo-point minimum and no active debuff.")

	local control = ui.Card(stack,
		Text({ en = "CONTROL & SURVIVAL", fr = "CONTROLE ET SURVIE", pt = "CONTROLE E SOBREVIVÊNCIA", es = "CONTROL Y SUPERVIVENCIA", de = "KONTROLLE & ÜBERLEBEN", zh = "控制与生存" }))
	Check(control, "kick", "Kick", "Kick",
		{ en = "Highest-priority interrupt when the target is casting.", fr = "Interruption prioritaire lorsque la cible incante.", pt = "Interrupção prioritária quando o alvo está conjurando.", es = "Interrupción prioritaria cuando el objetivo está lanzando.", de = "Unterbrechung mit höchster Priorität, wenn das Ziel zaubert.", zh = "目标施法时最优先的打断。" })
	Check(control, "kidney", "Kidney Shot", "Kidney Shot",
		{ en = "Fallback control when Kick cannot be used.", fr = "Controle de secours lorsque Kick ne peut pas etre utilise.", pt = "Controle de reserva quando Kick não pode ser usado.", es = "Control de respaldo cuando no se puede usar Kick.", de = "Ersatzkontrolle, wenn Kick nicht nutzbar ist.", zh = "无法使用 Kick 时的备用控制。" })
	ComboSlider(control, "kidneyMinCP",
		{ en = "Kidney Shot combo points", fr = "Points de combo Kidney Shot", pt = "Pontos de combo Kidney Shot", es = "Puntos de combo Kidney Shot", de = "Combopunkte für Kidney Shot", zh = "Kidney Shot 连击点" }, 3)
	Check(control, "gouge", "Gouge", "Gouge",
		{ en = "Creates a short recovery window when player health is low.", fr = "Cree une courte fenetre de recuperation lorsque la vie du joueur est basse.", pt = "Cria uma curta janela de recuperação quando a vida do jogador está baixa.", es = "Crea una breve ventana de recuperación cuando la salud del jugador es baja.", de = "Verschafft dir eine kurze Erholungspause, wenn deine Gesundheit niedrig ist.", zh = "玩家生命值低时创造短暂的恢复窗口。" })
	Slider(control, "gougeHP",
		{ en = "Gouge health threshold", fr = "Seuil de vie Gouge", pt = "Limite de vida Gouge", es = "Umbral de salud Gouge", de = "Gesundheitsschwelle für Gouge", zh = "Gouge 生命值阈值" }, 5, 95, 50, " % HP")
	Check(control, "evasion", "Evasion", "Evasion",
		{ en = "Defensive cooldown for dangerous melee pressure.", fr = "Temps de recharge defensif contre une forte pression de melee.", pt = "Recarga defensiva contra forte pressão corpo a corpo.", es = "Reutilización defensiva contra una fuerte presión cuerpo a cuerpo.", de = "Defensiver Cooldown gegen gefährlichen Nahkampfdruck.", zh = "应对危险近战压力的防御冷却技能。" })
	Slider(control, "evasionHP",
		{ en = "Evasion health threshold", fr = "Seuil de vie Evasion", pt = "Limite de vida Evasion", es = "Umbral de salud Evasion", de = "Gesundheitsschwelle für Evasion", zh = "Evasion 生命值阈值" }, 5, 90, 35, " % HP")
	Check(control, "vanish", "Vanish", "Vanish",
		{ en = "Optional emergency escape. Disabled by default to avoid spending the cooldown automatically.", fr = "Fuite d'urgence optionnelle. Desactivee par defaut pour ne pas depenser automatiquement le temps de recharge.", pt = "Fuga de emergência opcional. Desativada por padrão para não gastar a recarga automaticamente.", es = "Huida de emergencia opcional. Desactivada por defecto para no gastar la reutilización automáticamente.", de = "Optionale Notflucht. Standardmäßig aus, damit der Cooldown nicht automatisch verbraucht wird.", zh = "可选的紧急脱离。默认关闭，以免自动消耗冷却时间。" })
	Slider(control, "vanishHP",
		{ en = "Vanish health threshold", fr = "Seuil de vie Vanish", pt = "Limite de vida Vanish", es = "Umbral de salud Vanish", de = "Gesundheitsschwelle für Vanish", zh = "Vanish 生命值阈值" }, 5, 80, 20, " % HP")

	ui.Info(control, "Health thresholds include equality: Evasion at or below its slider, Gouge/Vanish at or below theirs. The spell must be learned, enabled and ready.")

	local aoe = ui.Card(stack,
		Text({ en = "AOE & BURST", fr = "AOE ET BURST", pt = "AOE E BURST", es = "AOE Y BURST", de = "AOE & BURST", zh = "AOE 与爆发" }))
	Check(aoe, "aoe",
		{ en = "Enable AoE mode", fr = "Activer le mode AoE", pt = "Ativar modo AoE", es = "Activar modo AoE", de = "AoE-Modus aktivieren", zh = "启用 AoE 模式" })
	Slider(aoe, "aoeMinEnemies",
		{ en = "Minimum enemies", fr = "Ennemis minimum", pt = "Mínimo de inimigos", es = "Enemigos mínimos", de = "Mindestanzahl Gegner", zh = "最少敌人数" }, 2, 5, 2, "")
	Check(aoe, "bladeFlurry", "Blade Flurry", "Blade Flurry",
		{ en = "Used when AoE reaches its enemy threshold or when Burst is enabled.", fr = "Utilise lorsque l'AoE atteint son seuil d'ennemis ou lorsque Burst est actif.", pt = "Usado quando o AoE atinge seu limite de inimigos ou quando Burst está ativo.", es = "Se usa cuando el AoE alcanza su umbral de enemigos o cuando Burst está activo.", de = "Wird genutzt, wenn AoE die Gegnerschwelle erreicht oder Burst aktiv ist.", zh = "当 AoE 达到敌人数阈值或启用 Burst 时使用。" })
	Slider(aoe, "burstMinTargetHP",
		{ en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Salud mínima del objetivo para Burst", de = "Min. Zielgesundheit für Burst", zh = "Burst 最低目标生命值" }, 0, 100, 40, " %")
	ui.Info(aoe, Text({
		en = "AoE requires a confirmed melee enemy count at or above the slider. An unavailable count does not meet the minimum. Manual Burst remains independent; its target-health slider applies even when HP is protected.",
		fr = "AoE exige un nombre confirme d'ennemis en melee atteignant le seuil. Un nombre inconnu ne suffit pas. Burst manuel reste independant et respecte son seuil de vie cible, meme protegee.",
		pt = "AoE exige uma contagem confirmada de inimigos corpo a corpo que alcance o limite. Uma contagem indisponível não é suficiente. Burst manual é independente e respeita o limite de vida do alvo, mesmo protegida.",
		es = "AoE requiere una cantidad confirmada de enemigos cuerpo a cuerpo que alcance el umbral. Una cantidad desconocida no cumple el mínimo. Burst manual es independiente y respeta el umbral de salud del objetivo, incluso protegida.",
		de = "AoE erfordert eine bestätigte Anzahl von Gegnern in Nahkampfreichweite ab dem Schiebereglerwert. Eine unbekannte Anzahl reicht nicht aus. Manueller Burst bleibt unabhängig und beachtet die Zielgesundheitsschwelle auch bei geschützten Werten.",
		zh = "AoE 需要确认近战敌人数达到滑块阈值。未知数量不能满足最低要求。手动 Burst 独立启用，并在生命值受保护时仍遵守目标生命值阈值。",
	}))

	local last = {}
	local function SetBadge(key, value, color)
		if last[key] == value then return end
		last[key] = value
		badges[key]:SetBadge(value, color)
	end

	local function Paint()
		local state = rotation and rotation.GetUIState and rotation.GetUIState() or {}
		local profile = ui.Profile()
		SetBadge("level", AL.L("LEVEL") .. " " .. tostring(state.level or "?"), steel)
		if type(state.energy) == "number" then
			SetBadge("energy", "ENERGY " .. tostring(state.energy), theme.gold)
		else
			SetBadge("energy", "ENERGY ?", theme.warn or theme.gold)
		end
		if type(state.combo) == "number" then
			SetBadge("combo", "CP " .. tostring(state.combo) .. "/5", theme.gold)
		else
			SetBadge("combo", "CP ?/5", theme.warn or theme.gold)
		end
		SetBadge("spells", tostring(state.knownCount or 0) .. " " .. AL.L("SPELLS"):upper(), steel)
		SetBadge("aoe", profile.aoe and AL.L("AOE_ON") or AL.L("AOE_OFF"),
			profile.aoe and theme.ok or theme.textFaint)
		SetBadge("burst", AL.burst and AL.L("BURST_ON") or AL.L("BURST_OFF"),
			AL.burst and theme.gold or theme.textFaint)
		SetBadge("stealth", state.stealthed and "STEALTH" or "VISIBLE",
			state.stealthed and theme.ok or theme.textFaint)
		local weapon = state.mainHandDagger == true and "DAGGER"
			or (state.mainHandDagger == false and "NON-DAGGER" or "WEAPON ?")
		SetBadge("weapon", weapon, state.mainHandDagger == true and theme.ok or steel)
		rowA:Layout()
		rowB:Layout()
		rowC:Layout()
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
	AL.RegisterClassUI("ROGUE", BuildRogueUI, UI_VERSION)
end
if AL.rotations and AL.rotations.ROGUE then
	AL.rotations.ROGUE.uiVersion = UI_VERSION
end
