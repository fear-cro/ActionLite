local ADDON, AL = ...

-- The menu edits the selected profile, which may differ from the player's.
-- Build selection is exclusive; each build's other saved options are retained.
local function BuildCheck(key,label,spell)
	return { key=key,half=false,label=label,spell=spell,onChange=function()
		local settings=AL.ES and AL.ES() or (AL.S and AL.S())
		if settings and settings[key] then
			for _,other in ipairs({"beastMastery","marksmanship","survival"}) do
				if other~=key then settings[other]=false end
			end
		end
		if AL.UI and AL.UI.Repaint then AL.UI.Repaint() end
	end }
end

-- Interface declarative Hunter. Chaque cle correspond directement a
-- rotation\Hunter.lua ; les seuils ne dupliquent aucune logique dans l'UI.
AL.RegisterSimpleClassUI("HUNTER", {
	title = { en = "HUNTER - LEVELING", fr = "CHASSEUR - PROGRESSION", pt = "CAÇADOR - EVOLUÇÃO", es = "CAZADOR - SUBIDA", de = "JÄGER - LEVELN", zh = "猎人 - 升级" },
	subtitle = { en = "Level 1-60 - pet, ranged, dead zone and AoE", fr = "Niveaux 1-60 - familier, distance, zone morte et AoE", pt = "Níveis 1-60 - mascote, distância, zona morta e AoE", es = "Niveles 1-60 - mascota, distancia, zona muerta y AoE", de = "Stufe 1-60 - Begleiter, Fernkampf, tote Zone und AoE", zh = "1-60级 - 宠物、远程、死区和AoE" },
	aoeKey = "aoe",
	cards = {
        {
            title = "LEVELING ROTATION",
            id="leveling-rotation", build="leveling", group="damage",
            controls = {
                { key="leveling", label="Leveling Rotation", spell="Auto Shot", half=false,
                  tooltip={"Leveling Rotation", "Uses the finalized class rotation from before the level-60 sim builds, with its original priorities and existing settings. Select a DPS or Tank build to switch rotations. Turning the active build off automatically selects Leveling Rotation. One rotation always stays selected."} },
            },
        },
		{
			title = "BEAST MASTERY BUILD - 31/20/0",
			id="beast-mastery-build-31-20-0", build="beastMastery", group="damage",
			controls = {
				BuildCheck("beastMastery", "Use Beast Mastery (31/20/0)", "Bestial Wrath"),
				{ type = "info", text = "Uses the tier-list pet build with learned spells through level 60. Selecting Beast Mastery unchecks Marksmanship and Survival while keeping their other saved settings. Keeps the active pet and its Call/Revive/Mend controls. Talents, gear and pet autocast settings are not changed." },
				{ type = "info", text = "Aimed Shot, an eligible missing Sting, Summon Hawk, then learned Arcane Shot and Auto Shot. Uses shared Aimed Shot, Sting, Hawk, Arcane Shot and Trueshot Aura checkboxes. Favors ranged attacks; close enemies use the existing melee fallback and ranged damage resumes when distance allows." },
				{ type = "slider", key = "beastStingMinMana", label = "Beast Mastery Sting minimum mana", min = 0, max = 100, step = 5, default = 30, suffix = " %" },
				{ type = "slider", key = "beastHawkMinMana", label = "Beast Mastery Summon Hawk minimum mana", min = 0, max = 100, step = 5, default = 0, suffix = " %" },
				{ type = "info", text = "The shared Sting target-health and Arcane Shot mana sliders also apply. Summon Hawk and Arcane Shot share a cooldown; Aimed Shot and Multi-Shot share another. Active casts and channels finish. Keep your pet attacking and its learned attacks on autocast." },
			},
		},
		{
			title = "BEAST MASTERY BURST",
			id="beast-mastery-burst-area-damage", build="beastMastery", group="burst",
			controls = {
				{ key = "bestialWrath", label = "Burst: Bestial Wrath", spell = "Bestial Wrath" },
				{ key = "intimidation", label = "Burst: optional Intimidation", spell = "Intimidation" },
				{ key = "beastElune", label = "Burst: learned Elune's Light", spell = "Elune's Light" },
				{ key = "beastBerserking", label = "Burst: learned Berserking", spell = "Berserking" },
				{ type = "slider", key = "beastBurstMinMana", label = "Beast Mastery Burst minimum mana", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "info", text = "Requires Burst On, combat, each ability's checkbox, enough mana and the shared minimum target-health setting. Bestial Wrath and Intimidation need a confirmed living pet engaged with the selected target. Rapid Fire is paired with a stationary Aimed Shot; its shared checkbox and the Blood Fury checkbox also apply. Intimidation defaults OFF because spending mana and delaying regular shots can lower damage. All four added spells support Universal icons 1-10 in the Spells tab." },
            },
        },
        {
            title="BEAST MASTERY AREA DAMAGE", id="beast-mastery-area-damage", build="beastMastery", group="aoe",
            controls={
				{ type = "slider", key = "beastAoEMinMana", label = "Beast Mastery AoE minimum mana", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "slider", key = "beastVolleyMinEnemies", label = "Beast Mastery Volley minimum enemies", min = 2, max = 5, step = 1, default = 4 },
				{ type = "info", text = "Multi-Shot requires AoE On and enough confirmed engaged enemies. Optional Volley also requires its shared checkbox, mana setting and the higher of the shared enemy count and its own count (four by default). Volley keeps its existing OFF default, uses normal ground placement and completes its channel." },
			},
		},
		{
			title = "MARKSMANSHIP BUILD - 5/31/15",
			id="marksmanship-build-5-31-15", build="marksmanship", group="damage",
			controls = {
				BuildCheck("marksmanship", "Use Marksmanship (5/31/15)", "Sniper Shot"),
				{ type = "info", text = "Selects learned ranged priorities through level 60: Aimed Shot, Stings and Sniper Shot between primary shots, then Arcane Shot and Auto Shot. Build selections are exclusive; your saved options are kept. Talents and equipment are not changed." },
				{ key = "marksmanshipNoPet", half = false, label = "Marksmanship: use learned Lone Wolf (no pet)", spell = "Dismiss Pet" },
				{ type = "info", text = "The reference build learns Lone Wolf. Only a confirmed learned talent disables Call/Revive/Mend Pet and allows stationary out-of-combat dismissal. Before learning it, normal pet controls remain available." },
				{ key = "sniper", label = "Use Sniper Shot", spell = "Sniper Shot" },
				{ type = "slider", key = "sniperMinMana", label = "Sniper Shot minimum mana", min = 0, max = 100, step = 5, default = 30, suffix = " %" },
				{ type = "slider", key = "marksmanshipStingMinMana", label = "Marksmanship Sting minimum mana", min = 0, max = 100, step = 5, default = 30, suffix = " %" },
				{ type = "info", text = "Aimed Shot and Sniper Shot require standing still. Uses the existing Sting target-health and Arcane Shot mana sliders. Close enemies use the melee fallback, then resume ranged attacks when distance allows. Sniper Shot and Trueshot Aura are available in the Spells tab for Universal icon selection." },
			},
		},
		{
			title = "SURVIVAL BUILD - 5/11/35",
			id="survival-build-5-11-35", build="survival", group="damage",
			controls = {
				BuildCheck("survival", "Use Survival (5/11/35)", "Strider Kick"),
				{ type = "info", text = "Uses the default melee Survival priorities with learned spells through level 60. Prefers Aspect of the Beast when learned. Ranged attacks remain available when the target is outside melee. Talents and equipment are not changed." },
				{ key = "survivalNoPet", half = false, label = "Use learned Lone Wolf (no pet)", spell = "Dismiss Pet" },
				{ type = "info", text = "With Survival selected and Lone Wolf confirmed learned, this disables Call/Revive/Mend Pet and dismisses an active pet only out of combat, when Dismiss Pet is learned and you are stationary. Before Lone Wolf is learned, normal pet controls remain available. Disable this option for a pet-based build." },
				{ key = "striderKick", label = "Use Strider Kick", spell = "Strider Kick" },
				{ key = "immolationTrap", label = "Use Immolation Trap", spell = "Immolation Trap" },
				{ key = "survivalWingFiller", half = false, label = "Survival: Wing Clip damage filler", spell = "Wing Clip" },
				{ type = "info", text = "Optional filler uses Wing Clip between Raptor Strike and Strider Kick opportunities. The existing Wing Clip checkbox is also required. Defensive Wing Clip remains available when chased." },
				{ type = "slider", key = "survivalMinMana", label = "Survival melee minimum mana", min = 0, max = 100, step = 5, default = 0, suffix = " %" },
				{ type = "slider", key = "trapMinMana", label = "Trap minimum mana", min = 0, max = 100, step = 5, default = 20, suffix = " %" },
				{ type = "slider", key = "trapMinTargetHP", label = "Trap minimum target health", min = 0, max = 100, step = 5, default = 25, suffix = " %" },
			},
		},
		{
			title = { en = "PET MANAGEMENT", fr = "GESTION DU FAMILIER", pt = "GERENCIAR MASCOTE", es = "GESTIÓN DE MASCOTA", de = "BEGLEITER-VERWALTUNG", zh = "宠物管理" },
			id="pet-management", group="preparation",
			controls = {
				{ key = "callpet", label = { en = "Call or revive pet", fr = "Appeler ou ranimer le familier", pt = "Chamar ou reviver mascote", es = "Llamar o revivir mascota", de = "Begleiter rufen oder wiederbeleben", zh = "召唤或复活宠物" }, spell = "Call Pet" },
				{ key = "mendpet", label = { en = "Mend Pet", fr = "Soigner le familier", pt = "Curar mascote", es = "Curar mascota", de = "Mend Pet", zh = "治疗宠物" }, spell = "Mend Pet" },
				{ type = "slider", key = "petMendHP", label = { en = "Mend Pet health threshold", fr = "Seuil de vie Mend Pet", pt = "Limite de vida Mend Pet", es = "Umbral de salud Mend Pet", de = "Mend Pet Gesundheitsschwelle", zh = "Mend Pet生命值阈值" },
					min = 20, max = 95, step = 5, default = 50, suffix = " %" },
			},
		},
		{
			title = { en = "PREPARATION & OPENING", fr = "PREPARATION ET OUVERTURE", pt = "PREPARAÇÃO E ABERTURA", es = "PREPARACIÓN Y APERTURA", de = "VORBEREITUNG & ERÖFFNUNG", zh = "准备与开场" },
			id="preparation-opening", group="preparation",
			controls = {
				{ key = "aspect", half = false, label = { en = "Combat Aspect upkeep", fr = "Maintenir l'Aspect de combat", pt = "Manter Aspecto de combate", es = "Mantener Aspecto de combate", de = "Kampfaspekt halten", zh = "保持战斗守护" }, spell = "Aspect of the Hawk" },
				{ key = "trueshot", label = "Maintain learned Trueshot Aura (BM/MM)", spell = "Trueshot Aura" },
				{ key = "summonHawk", label = "Use learned Summon Hawk (all builds)", spell = "Summon Hawk" },
				{ key = "mark", label = "Hunter's Mark", spell = "Hunter's Mark" },
				{ type = "slider", key = "markMinTargetHP", label = { en = "Hunter's Mark minimum target health", fr = "Vie cible minimum pour Hunter's Mark", pt = "Vida mínima do alvo para Hunter's Mark", es = "Salud mínima del objetivo para Hunter's Mark", de = "Hunter's Mark: Mindestgesundheit des Ziels", zh = "Hunter's Mark目标最低生命值" },
					min = 0, max = 100, step = 5, default = 45, suffix = " %", half = true },
				{ key = "drink", label = { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" } },
				{ type = "slider", key = "drinkMana", label = { en = "Drink at or below mana", fr = "Boire à ce niveau de mana ou en dessous", pt = "Beber com mana igual ou abaixo de", es = "Beber con maná igual o inferior", de = "Trinken bei oder unter Mana", zh = "法力值等于或低于时喝水" },
					min = 0, max = 80, step = 5, default = 30, suffix = " %", half = true },
			},
		},
		{
			title = { en = "RANGED ROTATION", fr = "ROTATION A DISTANCE", pt = "ROTAÇÃO À DISTÂNCIA", es = "ROTACIÓN A DISTANCIA", de = "FERNKAMPF-ROTATION", zh = "远程循环" },
			id="ranged-rotation", group="damage",
			controls = {
				{ key = "sting", label = "Serpent Sting", spell = "Serpent Sting" },
				{ key = "scorpid", label = { en = "Prefer Scorpid Sting", fr = "Preferer Scorpid Sting", pt = "Preferir Scorpid Sting", es = "Preferir Scorpid Sting", de = "Scorpid Sting bevorzugen", zh = "优先Scorpid Sting" }, spell = "Scorpid Sting" },
				{ type = "slider", key = "stingMinTargetHP", label = { en = "Sting minimum target health", fr = "Vie cible minimum pour Sting", pt = "Vida mínima do alvo para Sting", es = "Salud mínima del objetivo para Sting", de = "Sting: Mindestgesundheit des Ziels", zh = "Sting目标最低生命值" },
					min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ key = "aimed", label = "Aimed Shot", spell = "Aimed Shot" },
				{ key = "arcane", label = "Arcane Shot", spell = "Arcane Shot" },
				{ type = "slider", key = "arcaneMinMana", label = { en = "Arcane Shot minimum mana", fr = "Mana minimum pour Arcane Shot", pt = "Mana mínima para Arcane Shot", es = "Maná mínimo para Arcane Shot", de = "Arcane Shot Mindestmana", zh = "Arcane Shot最低法力值" },
					min = 0, max = 80, step = 5, default = 20, suffix = " %", half = true },
				{ key = "concussive", label = { en = "Concussive Shot when chased", fr = "Concussive Shot si poursuivi", pt = "Concussive Shot se perseguido", es = "Concussive Shot si te persiguen", de = "Concussive Shot bei Verfolgung", zh = "被追击时Concussive Shot" }, spell = "Concussive Shot" },
			},
		},
		{
			title = { en = "DEAD ZONE & MELEE", fr = "ZONE MORTE ET CORPS A CORPS", pt = "ZONA MORTA E CORPO A CORPO", es = "ZONA MUERTA Y CUERPO A CUERPO", de = "TOTE ZONE & NAHKAMPF", zh = "死区与近战" },
			id="dead-zone-melee", group="damage",
			controls = {
				{ key = "survivalMelee", half = false, label = { en = "Survival melee override", fr = "Priorite melee Survie", pt = "Prioridade corpo a corpo Sobrevivência", es = "Prioridad cuerpo a cuerpo Supervivencia", de = "Überleben: Nahkampf bevorzugen", zh = "生存专精近战优先" } },
				{ type = "info", text = {
					en = "Ranged attacks take priority by default. Survival is detected when the client exposes it; enable this override if detection is unavailable. Close targets can use melee, then return to ranged attacks as distance allows.",
					fr = "Les attaques a distance sont prioritaires. Survie est detectee si le client le permet ; activez cette option sinon. Utilisez la melee contre les cibles proches, puis reprenez les attaques a distance quand la portee le permet.",
					pt = "Ataques à distância têm prioridade. Sobrevivência é detectada quando disponível; ative esta opção se necessário. Alvos próximos usam corpo a corpo e voltam aos ataques à distância quando possível.",
					es = "Los ataques a distancia tienen prioridad. Supervivencia se detecta cuando está disponible; activa esta opción si es necesario. Los objetivos cercanos usan cuerpo a cuerpo y vuelven a ataques a distancia cuando sea posible.",
					de = "Fernkampf hat Vorrang. Überleben wird erkannt, wenn der Client es meldet; sonst diese Option aktivieren. Nahe Ziele werden im Nahkampf bekämpft, dann folgt wieder Fernkampf, sobald die Reichweite passt.",
					zh = "默认优先远程攻击。客户端支持时自动识别生存专精；无法识别时启用此选项。目标靠近时可使用近战，距离允许后恢复远程攻击。",
				} },
				{ key = "mongoose", label = "Mongoose Bite", spell = "Mongoose Bite" },
				{ key = "disengage", label = { en = "Disengage back to pet", fr = "Disengage pour rendre l'aggro au familier", pt = "Disengage de volta à mascote", es = "Disengage hacia la mascota", de = "Disengage zurück zum Begleiter", zh = "Disengage将仇恨交还宠物" }, spell = "Disengage" },
				{ key = "wingclip", label = { en = "Wing Clip when chased", fr = "Wing Clip si poursuivi", pt = "Wing Clip se perseguido", es = "Wing Clip si te persiguen", de = "Wing Clip bei Verfolgung", zh = "被追击时Wing Clip" }, spell = "Wing Clip" },
				{ key = "raptor", label = "Raptor Strike", spell = "Raptor Strike" },
			},
		},
		{
			title = { en = "AREA DAMAGE", fr = "AOE ET BURST", pt = "AOE E BURST", es = "AOE Y BURST", de = "AOE & BURST", zh = "AOE与BURST" },
			id="aoe-burst", group="aoe",
			controls = {
				{ key = "aoe", label = { en = "Enable AoE mode", fr = "Activer l'AoE Multi-Shot", pt = "Ativar AoE Multi-Shot", es = "Activar AoE Multi-Shot", de = "Multi-Shot AoE aktivieren", zh = "启用Multi-Shot AoE" }, spell = "Multi-Shot" },
				{ type = "slider", key = "aoeMinEnemies", label = { en = "Minimum enemies", fr = "Ennemis minimum", pt = "Mínimo de inimigos", es = "Enemigos mínimos", de = "Mindestanzahl Gegner", zh = "最少敌人数" },
					min = 2, max = 5, step = 1, default = 2, half = true },
				{ key = "explosiveTrap", label = "Survival: Explosive Trap AoE", spell = "Explosive Trap" },
				{ key = "volley", label = "Volley at range (all builds)", spell = "Volley" },
				{ type = "slider", key = "volleyMinMana", label = "Volley minimum mana", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "info", text = "Explosive Trap requires AoE On and enough engaged enemies in melee, and shares its cooldown with Immolation Trap. Optional Volley is ground-targeted, requires AoE On and a stationary player, and defaults OFF." },
				{ type = "info", text = {
					en = "Multi-Shot requires the selected number of confirmed enemies. An unknown count does not enable AoE.",
					fr = "Multi-Shot nécessite le nombre choisi d'ennemis confirmés. Un nombre inconnu ne déclenche pas l'AoE.",
					pt = "Multi-Shot exige o número escolhido de inimigos confirmados. Uma contagem desconhecida não ativa AoE.",
					es = "Multi-Shot requiere el número elegido de enemigos confirmados. Una cantidad desconocida no activa AoE.",
					de = "Multi-Shot benötigt die gewählte Anzahl bestätigter Gegner. Eine unbekannte Anzahl aktiviert kein AoE.",
					zh = "Multi-Shot需要达到所选的已确认敌人数。未知数量不会启用AoE。",
				} },

            },
        },
        {
            title="BURST LIMITS", id="burst-limits", group="burst",
            controls={
				{ key = "bloodFury", label = "Blood Fury during Burst", spell = "Blood Fury" },
				{ key = "rapidfire", label = { en = "Rapid Fire during Burst", fr = "Rapid Fire pendant le Burst", pt = "Rapid Fire durante o Burst", es = "Rapid Fire durante el Burst", de = "Rapid Fire während Burst", zh = "Burst期间Rapid Fire" }, spell = "Rapid Fire" },
				{ type = "slider", key = "burstMinTargetHP", label = { en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Salud mínima del objetivo para Burst", de = "Burst: Mindestgesundheit des Ziels", zh = "Burst目标最低生命值" },
					min = 0, max = 100, step = 5, default = 40, suffix = " %", half = true },
			},
		},
	},
}, "0.13.3")
