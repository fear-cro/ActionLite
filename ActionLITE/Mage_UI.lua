local ADDON, AL = ...

local function ChooseBuild(key,...)
	local others={...}
	return function()
		local s=AL.ES and AL.ES() or (AL.S and AL.S())
		if s and s[key] then for _,other in ipairs(others) do s[other]=false end end
		local rotation = AL.rotations and AL.rotations.MAGE
		if s and rotation and rotation.NormalizeBuild then rotation.NormalizeBuild(s) end
		if AL.UI and AL.UI.Repaint then AL.UI.Repaint() end
	end
end

AL.RegisterSimpleClassUI("MAGE", {
	title = { en = "MAGE - LEVELING", fr = "MAGE - PROGRESSION", pt = "MAGO - EVOLUÇÃO", es = "MAGO - SUBIDA", de = "MAGIER - LEVELN", zh = "法师 - 升级" },
	subtitle = { en = "Level 1-60 - Frost, Fire, Arcane and Frostfire builds, learned spells and wand control", fr = "Niveaux 1-60 - Feu, Arcane et Givrefeu", pt = "Níveis 1-60 - Fogo, Arcano e Fogo Gélido", es = "Niveles 1-60 - Fuego, Arcano y Pirofrío", de = "Stufe 1-60 - Feuer, Arkan und Frostfeuer", zh = "1-60级 - 火焰、奥术与霜火" },
	aoeKey = "aoe",
	cards = {
        {
            title = "LEVELING ROTATION",
            id="leveling-rotation", build="leveling", group="damage",
            controls = {
                { key="leveling", label="Leveling Rotation", spell="Frostbolt", half=false,
                  tooltip={"Leveling Rotation", "Uses the finalized class rotation from before the level-60 sim builds, with its original priorities and existing settings. Select a DPS or Tank build to switch rotations. Turning the active build off automatically selects Leveling Rotation. One rotation always stays selected."} },
            },
        },
		{
			title = "FROST BUILD - 16/3/32",
			id="frost-build-16-3-32", build="frost", group="damage",
			controls = {
				{ key = "frost", label = "Use Frost (16/3/32)", half = false, spell = "Frostbolt", onChange = ChooseBuild("frost","fire","arcane","frostfire","primaryFire") },
				{ type = "info", text = "Selects the tier-list Frost build using learned spells through level 60. Unchecks the other builds and keeps their saved options and icon choices. Does not change talents or gear. Select Leveling Rotation to use the original rotation." },
				{ key = "frostMissiles", label = "Use confirmed Missile Barrage", spell = "Arcane Missiles" },
				{ key = "frostBlast", label = "Use Frost Blast as a quick slow opener", spell = "Frost Blast" },
				{ key = "frostFireBlast", label = "Use Fire Blast while moving", spell = "Fire Blast" },
				{ type = "info", text = "Normal priority: Ice Lance against a confirmed frozen target or with Fingers of Frost, confirmed Missile Barrage, then Frostbolt. The shared Ice Lance checkbox applies. Fire Blast is a moving fallback and needs its shared checkbox and mana setting. Wand mana and target-health settings keep priority; existing casts and channels finish." },
			},
		},
		{
			title = "FROST BURST",
			id="frost-burst-area-damage", build="frost", group="burst",
			controls = {
				{ key = "frostColdSnap", label = "Burst: Cold Snap for close AoE", spell = "Cold Snap", half = false },
				{ key = "frostEureka", label = "Burst: learned Eureka!", spell = "Eureka!" },
				{ key = "frostBerserking", label = "Burst: learned Berserking", spell = "Berserking" },
				{ type = "slider", key = "frostBurstMinMana", label = "Frost Burst minimum mana", min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "info", text = "Requires Frost selected, Burst On, combat, enough mana and the shared minimum target-health setting. Cold Snap is used only with AoE On, enough close engaged enemies, and an enabled, affordable Cone of Cold already on cooldown. Its ten-minute cooldown is saved during ordinary ranged single-target damage. Manual queueing remains available." },
            },
        },
        {
            title="FROST AREA DAMAGE", id="frost-area-damage", build="frost", group="aoe",
            controls={
				{ key = "frostCone", label = "AoE: close Cone of Cold", spell = "Cone of Cold" },
				{ key = "frostWinterChill", label = "AoE: build own Winter's Chill before Cone", spell = "Cone of Cold" },
				{ key = "frostBlizzard", label = "AoE: ranged Blizzard", spell = "Blizzard" },
				{ type = "slider", key = "frostBlizzardMinEnemies", label = "Frost Blizzard minimum enemies", min = 2, max = 8, step = 1, default = 4 },
				{ key = "frostExplosion", label = "AoE: optional close Arcane Explosion", spell = "Arcane Explosion", half = false },
				{ type = "info", text = "Requires AoE On and the shared engaged-enemy count and mana settings. Blizzard also needs its own minimum count (four by default) and uses normal ground placement. Cone of Cold and optional Arcane Explosion need enough confirmed close enemies. Full Blizzard channels finish before the next action." },
			},
		},
		{
			title = "FROST DEFENSE",
			id="frost-defense", build="frost", group="survival",
			controls = {
				{ key = "frostBarrier", label = "Use Ice Barrier", spell = "Ice Barrier" },
				{ type = "slider", key = "frostBarrierHP", label = "Ice Barrier at/below player health", min = 1, max = 100, step = 1, default = 70, suffix = " %" },
				{ type = "slider", key = "frostBarrierMinMana", label = "Ice Barrier minimum mana", min = 0, max = 100, step = 5, default = 25, suffix = " %" },
				{ type = "info", text = "Uses learned Ice Barrier in combat at/below its health setting, when affordable and no active shield is known. Keeps its buff and cooldown instead of repeating the cast. Emergency Ice Block and interrupts retain priority. Cold Snap and Ice Barrier are available in the Spells tab for Universal icons 1-10." },
			},
		},
		{
			title = "FIRE BUILD - 16/31/4",
			id="fire-build-16-31-4", build="fire", group="damage",
			controls = {
				{ key = "fire", label = "Use Fire (16/31/4)", half = false, spell = "Fireball", onChange = ChooseBuild("fire","arcane","frostfire","primaryFire","frost") },
				{ type = "info", text = "The live tier-list Fire reference, using learned spells through level 60. Selecting Fire unchecks Frost, Arcane, Frostfire and the older fire-primary option while preserving their other settings. Build selection does not change talents or gear. Leveling Rotation retains the original rotation." },
				{ key = "fireScorch", label = "Maintain Fire Vulnerability with Scorch", spell = "Scorch" },
				{ key = "firePyroblast", label = "Use proc Pyroblast", spell = "Pyroblast" },
				{ key = "fireMissiles", label = "Use confirmed Missile Barrage", spell = "Arcane Missiles" },
				{ key = "fireClearcasting", label = "Save Clearcasting for a cast or channel", spell = "Fireball", half = false,
					tooltip = { "Clearcasting", "Skips Fire Blast during a positively detected Clearcasting buff or an explicitly free Fireball. Proc Pyroblast, Scorch upkeep and Missile Barrage keep their priority. Hidden data never invents a proc. Disable to permit Fire Blast normally." } },
				{ type = "info", text = "Normal priority: eligible proc Pyroblast, personal Scorch upkeep, Fire Blast, confirmed Missile Barrage, then Fireball and learned fallbacks. The shared Fire Blast checkbox and mana slider apply; the sim reference uses 30% and your saved slider value is retained. The wand mana/target-health sliders keep priority over normal damage, including free procs." },
				{ type = "info", text = "Improved Scorch is a personal player buff in Forever. At confirmed 3/3, successful casts provide a bounded five-cast fallback when auras are protected; partial ranks have an attempt limit. Heating Up needs three confirmed stacks or a readable reduced Pyroblast cast time. Three stacks usually mean a 1.5-second cast, so moving Pyroblast needs a confirmed instant cast." },
			},
		},
		{
			title = "FIRE BURST",
			id="fire-burst-area-damage", build="fire", group="burst",
			controls = {
				{ key = "fireCombustion", label = "Burst: Combustion", spell = "Combustion" },
				{ key = "fireEureka", label = "Burst: learned Eureka!", spell = "Eureka!" },
				{ key = "fireBerserking", label = "Burst: learned Berserking", spell = "Berserking" },
				{ type = "slider", key = "fireBurstMinMana", label = "Fire Burst minimum mana", min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "info", text = "Requires Fire selected, Burst On, combat, the shared minimum target-health slider, enough mana and eligible damage. Enabled Scorch upkeep precedes Combustion. Its three-minute cooldown starts when consumed, and it shares a cooldown with Presence of Mind. Readable buffs, cooldowns or confirmed fire crits establish consumption; unknown crits are never counted. Normal damage continues while the buff is active." },
            },
        },
        {
            title="FIRE AREA DAMAGE", id="fire-area-damage", build="fire", group="aoe",
            controls={
				{ key = "fireFlamestrike", label = "AoE: Flamestrike", spell = "Flamestrike" },
				{ key = "fireBlizzard", label = "AoE: ranged Blizzard", spell = "Blizzard" },
				{ type = "info", text = "Area spells require AoE On and the shared engaged-enemy count/mana settings. Flamestrike waits eight seconds before refresh, with ranged Blizzard between casts. Cone of Cold and Arcane Explosion require enough confirmed close enemies. Ground spells use normal placement; existing casts and channels finish. Combustion is available in the existing Spells tab for Universal icons 1-10." },
			},
		},
		{
			title = "FROSTFIRE BUILD - 0/29/22",
			id="frostfire-build-0-29-22", build="frostfire", group="damage",
			controls = {
				{ key = "frostfire", label = "Use Frostfire (0/29/22)", half = false, spell = "Frostfire Bolt", onChange = ChooseBuild("frostfire","arcane","primaryFire","fire","frost") },
				{ type = "info", text = "Experimental tier-list hybrid. Selecting Frostfire unchecks the other builds while preserving their settings. Uses learned spells through level 60; before Frostfire Bolt is learned, it falls back to learned Fireball/Frostbolt. Selecting a build does not change talents or gear." },
				{ key = "frostfireBolt", label = "Use Frostfire Bolt", spell = "Frostfire Bolt" },
				{ key = "frostfireScorch", label = "Maintain Fire Vulnerability with Scorch", spell = "Scorch" },
				{ key = "frostfirePyroblast", label = "Use proc Pyroblast", spell = "Pyroblast" },
				{ type = "info", text = "Maintain the personal Fire Vulnerability buff at five stacks, refreshing within five seconds. Improved Scorch must be confirmed by the talent API or an active personal buff. Proc Pyroblast requires three Heating Up stacks or a readably reduced cast time. Three stacks still take about 1.5 seconds: stand still unless the live spell is instant. Protected or unknown proc data falls back to regular damage." },
				{ type = "info", text = "With protected aura data and confirmed 3/3 Improved Scorch, successful casts provide a bounded five-cast estimate and a timed refresh. Partial talent ranks use a five-attempt limit before returning to damage; readable personal buffs always resynchronize upkeep." },
				{ type = "info", text = "Wand mana and target-health thresholds retain priority. The shared Fire Blast checkbox and mana slider control Fire Blast on cooldown in combat, after Scorch upkeep and proc Pyroblast; range still applies. Ice Lance is available while moving with a confirmed frozen target or Fingers of Frost. Frostfire prefers learned Mage Armor during preparation." },
			},
		},
		{
			title = "FROSTFIRE BURST",
			id="frostfire-burst-area-damage", build="frostfire", group="burst",
			controls = {
				{ key = "frostfireEureka", label = "Burst: learned Eureka!", spell = "Eureka!" },
				{ key = "frostfireBerserking", label = "Burst: learned Berserking", spell = "Berserking" },
				{ type = "slider", key = "frostfireBurstMinMana", label = "Frostfire Burst minimum mana", min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "info", text = "Racials require Burst On, combat, the existing Burst target-health setting, enough mana and an available damage spell. Single-target Scorch upkeep is completed first; an eligible AoE branch can use Burst directly. The default 0/29/22 build does not learn Combustion, Arcane Power or Presence of Mind." },
            },
        },
        {
            title="FROSTFIRE AREA DAMAGE", id="frostfire-area-damage", build="frostfire", group="aoe",
            controls={
				{ key = "frostfireFlamestrike", label = "AoE: Flamestrike", spell = "Flamestrike" },
				{ key = "frostfireBlizzard", label = "AoE: ranged Blizzard", spell = "Blizzard" },
				{ type = "info", text = "Requires AoE On and the shared enemy-count and mana settings. Flamestrike refreshes after eight seconds, then ranged Blizzard continues while stationary. Both use normal ground targeting. Cone of Cold and Arcane Explosion require enough confirmed close enemies. Active casts and channels finish normally." },
			},
		},
		{
			title = "ARCANE BUILD - 35/11/5",
			id="arcane-build-35-11-5", build="arcane", group="damage",
			controls = {
				{ key = "arcane", label = "Use Arcane (35/11/5)", half = false, spell = "Arcane Blast", onChange = ChooseBuild("arcane","primaryFire","frostfire","fire","frost") },
				{ type = "info", text = "Uses the live tier preset with learned spells through level 60: build the fifteen-second Arcane Blast buff, use confirmed Missile Barrage, then Arcane Wrath on cooldown and Arcane Missiles filler. Other spells retain the buff. Unchecks Frostfire and the fire-primary option while preserving their other settings. Talents and gear are not changed." },
				{ key = "arcaneBlast", label = "Use Arcane Blast", spell = "Arcane Blast" },
				{ key = "arcaneWrath", label = "Use Arcane Wrath", spell = "Arcane Wrath" },
				{ key = "arcaneMissiles", label = "Use Arcane Missiles", spell = "Arcane Missiles" },
				{ type = "slider", key = "arcaneThreeMana", label = "Conserve at 3 stacks below mana", min = 0, max = 100, step = 5, default = 30, suffix = " %" },
				{ type = "slider", key = "arcaneTwoMana", label = "Conserve at 2 stacks below mana", min = 0, max = 100, step = 5, default = 20, suffix = " %" },
				{ type = "info", text = "The existing wand mana/target-health sliders keep priority over ordinary damage, including free Missiles. Before Arcane Blast is learned, available leveling spells remain usable. Arcane prefers learned Mage Armor during preparation. Fire Blast remains available while moving and before Arcane Blast is learned." },
			},
		},
		{
			title = "ARCANE BURST",
			id="arcane-burst-area-damage", build="arcane", group="burst",
			controls = {
				{ key = "arcanePower", label = "Burst: Arcane Power", spell = "Arcane Power" },
				{ key = "presenceOfMind", label = "Burst: Presence of Mind", spell = "Presence of Mind" },
				{ key = "arcanePyroblast", label = "Burst: instant Pyroblast", spell = "Pyroblast" },
				{ key = "arcaneEureka", label = "Burst: learned Eureka!", spell = "Eureka!" },
				{ key = "arcaneBerserking", label = "Burst: learned Berserking", spell = "Berserking" },
				{ type = "slider", key = "arcaneBurstMinMana", label = "Arcane Burst minimum mana", min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "info", text = "Requires Burst On, the existing Burst target-health slider, mana and an eligible damage spell. Presence of Mind prepares a learned Pyroblast at four charges. Automatic Pyroblast requires an active Presence of Mind; ordinary six-second Pyroblasts are not used. Racials require the actual learned spell." },
            },
        },
        {
            title="ARCANE AREA DAMAGE", id="arcane-area-damage", build="arcane", group="aoe",
            controls={
				{ key = "arcaneBlizzard", label = "AoE: optional ranged Blizzard", half = false, spell = "Blizzard" },
				{ type = "info", text = "Cone of Cold and Arcane Explosion require AoE On and enough confirmed close enemies. Ranged Blizzard also requires its checkbox, standing still and confirmed ranged enemies; it defaults OFF and uses normal ground targeting. AoE uses the existing enemy-count and mana sliders." },
			},
		},
		{
			title = { en = "LEVELING AND FALLBACK SPELLS", fr = "SORT PRINCIPAL", pt = "FEITIÇO PRINCIPAL", es = "HECHIZO PRINCIPAL", de = "HAUPTZAUBER", zh = "主要法术" },
			id="primary-spell", group="advanced", collapsed=true,
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
				{ key = "primaryFire", onChange = ChooseBuild("primaryFire","arcane","frostfire","fire","frost"), label = { en = "Primarily use fire spells", fr = "Utiliser principalement les sorts de feu", pt = "Usar principalmente feitiços de fogo", es = "Usar principalmente hechizos de fuego", de = "Hauptsächlich Feuerzauber verwenden", zh = "主要使用火焰法术" }, spell = "Fireball", tooltip = {
					{ en = "Fire-primary rotation", fr = "Rotation principalement Feu", pt = "Rotação principal de Fogo", es = "Rotación principalmente de Fuego", de = "Feuerpriorisierte Rotation", zh = "火焰优先循环" },
					{ en = "Switches to Leveling Rotation with fire priority. Uses Fireball and Fire Blast, and recommends Flamestrike when AoE is enabled and its enemy-count and mana settings are met.", fr = "Désactive la priorité de Frostbolt. Utilise Fireball et Fire Blast, et recommande Flamestrike si l’AoE est activée et que les seuils d’ennemis et de mana sont atteints.", pt = "Desativa a prioridade de Frostbolt. Usa Fireball e Fire Blast e recomenda Flamestrike quando o AoE está ativado e os limites de inimigos e mana são atendidos.", es = "Desactiva la prioridad de Frostbolt. Usa Fireball y Fire Blast y recomienda Flamestrike cuando el AoE está activado y se cumplen los límites de enemigos y maná.", de = "Deaktiviert die Frostbolt-Priorität. Verwendet Fireball und Fire Blast und empfiehlt Flamestrike, wenn AoE aktiviert ist und die Gegner- und Mana-Schwellen erreicht sind.", zh = "禁用 Frostbolt 优先级。使用 Fireball 和 Fire Blast。启用 AoE 且达到敌人数和法力阈值时推荐 Flamestrike。" }
				} },
            },
        },
        {
            title="PREPARATION", id="preparation", group="preparation",
            controls={
				{ key = "buffs", label = { en = "Maintain intellect and armor", fr = "Maintenir intelligence et armure", pt = "Manter intelecto e armadura", es = "Mantener intelecto y armadura", de = "Intelligenz und Rüstung halten", zh = "保持智力和护甲" }, spell = "Arcane Intellect" },
				{ key = "conjure", label = { en = "Conjure missing water, food and gem", fr = "Conjurer eau, nourriture et gemme manquantes", pt = "Conjurar água, comida e gema que faltam", es = "Conjurar agua, comida y gema faltantes", de = "Wasser, Essen und Edelstein herbeizaubern", zh = "制造缺少的水、食物和宝石" }, spell = "Conjure Water" },
			},
		},
		{
			title = { en = "MANA & WAND", fr = "MANA ET BAGUETTE", pt = "MANA E VARINHA", es = "MANÁ Y VARITA", de = "MANA & ZAUBERSTAB", zh = "法力值与魔杖" },
			id="mana-wand", group="resources",
			controls = {
				{ key = "drink", label = { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" } },
				{ type = "slider", key = "drinkMana", label = { en = "Drink below mana", fr = "Boire sous ce niveau de mana", pt = "Beber com mana abaixo de", es = "Beber con maná bajo", de = "Trinken unter Mana", zh = "法力值低于时喝水" }, min = 0, max = 80, step = 5, default = 35, suffix = " %" },
				{ key = "evocation", label = "Evocation", spell = "Evocation" },
				{ type = "slider", key = "evocationMana", label = { en = "Evocation below mana", fr = "Evocation sous ce niveau de mana", pt = "Evocation com mana abaixo de", es = "Evocation con maná bajo", de = "Evocation unter Mana", zh = "法力值低于时Evocation" }, min = 0, max = 60, step = 5, default = 15, suffix = " %" },
				{ key = "wand", icon = "Interface\\Icons\\INV_Wand_01", label = { en = "Use wand to conserve mana", fr = "Utiliser la baguette pour economiser le mana", pt = "Usar varinha para poupar mana", es = "Usar varita para ahorrar maná", de = "Zauberstab nutzen, um Mana zu sparen", zh = "使用魔杖节省法力值" }, spell = "Shoot" },
				{ type = "slider", key = "wandMana", icon = "Interface\\Icons\\INV_Wand_01", label = {
					en = "Wand / Shoot below mana threshold:",
					fr = "Baguette / Shoot sous ce seuil de mana:",
					pt = "Varinha / Shoot abaixo do limite de mana:",
					es = "Varita / Shoot bajo el umbral de maná:",
					de = "Zauberstab / Shoot unter der Mana-Schwelle:",
					zh = "法力低于阈值时使用魔杖 / Shoot："
				}, min = 0, max = 95, step = 5, default = 25, suffix = " %", tooltip = { { en = "Wand mana hard gate", fr = "Seuil strict de mana pour la baguette", pt = "Limite rígida de mana da varinha", es = "Límite estricto de maná para la varita", de = "Harte Mana-Grenze für den Zauberstab", zh = "魔杖法力硬性阈值" }, { en = "At or below this mana, offensive Mage damage spells are blocked and Shoot is recommended while stationary.", fr = "À ce niveau de mana ou en dessous, les sorts de dégâts offensifs sont bloqués et Shoot est conseillé à l'arrêt.", pt = "Neste valor de mana ou abaixo, feitiços ofensivos são bloqueados e Shoot é recomendado parado.", es = "Con este maná o menos, los hechizos ofensivos se bloquean y se recomienda Shoot al estar quieto.", de = "Bei diesem Mana oder weniger werden offensive Schadenszauber blockiert und im Stand Shoot empfohlen.", zh = "法力值低于或等于此阈值时阻止进攻伤害法术，并在静止时推荐 Shoot。" } } },
				{ type = "slider", key = "wandTargetHP", label = { en = "Wand below target health", fr = "Baguette sous la vie cible", pt = "Varinha com vida do alvo abaixo de", es = "Varita con salud del objetivo baja", de = "Zauberstab unter Zielgesundheit", zh = "目标生命值低于时用魔杖" }, min = 0, max = 80, step = 5, default = 20, suffix = " % HP" },
			},
		},
		{
			title = { en = "RANGED COMBAT & CONTROL", fr = "COMBAT DISTANCE ET CONTROLE", pt = "COMBATE À DISTÂNCIA E CONTROLE", es = "COMBATE A DISTANCIA Y CONTROL", de = "FERNKAMPF & KONTROLLE", zh = "远程战斗与控制" },
			id="ranged-combat-control", group="damage",
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
			},
		},
		{
			title = { en = "SURVIVAL", fr = "SURVIE", pt = "SOBREVIVÊNCIA", es = "SUPERVIVENCIA", de = "ÜBERLEBEN", zh = "生存" },
			id="survival", group="survival",
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
			id="confirmed-aoe", group="aoe",
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
        { title="BURST LIMITS", id="burst-limits", group="burst", controls={
				{ type = "slider", key = "burstMinTargetHP", label = { en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Salud mínima del objetivo para Burst", de = "Burst: Mindestgesundheit des Ziels", zh = "Burst目标最低生命值" }, min = 0, max = 100, step = 5, default = 40, suffix = " % HP" },
        } },
	},
}, "0.20.4")
