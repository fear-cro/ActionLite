local ADDON, AL = ...

local CURSE_KEYS = { "curseElements", "curseWeakness", "curseRecklessness", "curseTongues" }
local BUILD_KEYS = { "destruction", "affliction", "demonology" }

local function BuildCheck(key,label,spell)
	return { key=key,label=label,spell=spell,half=false,onChange=function()
		local settings=AL.ES and AL.ES() or (AL.S and AL.S())
		if settings and settings[key] then
			for _,other in ipairs(BUILD_KEYS) do if other~=key then settings[other]=false end end
		end
		if AL.UI and AL.UI.Repaint then AL.UI.Repaint() end
	end }
end

-- Les cases restent des checkbox, mais cocher l'une decoche les autres.
-- Aucune case cochee desactive les maledictions utilitaires.
local function CurseCheck(key, spell)
	return {
		key = key, label = spell, spell = spell, half = false,
		onChange = function()
			local settings = AL.ES and AL.ES() or (AL.S and AL.S())
			if settings and settings[key] then
				for _, other in ipairs(CURSE_KEYS) do
					if other ~= key then settings[other] = false end
				end
			end
			if AL.UI and AL.UI.Repaint then AL.UI.Repaint() end
		end,
	}
end

AL.RegisterSimpleClassUI("WARLOCK", {
	title = { en = "WARLOCK - DPS LEVELING", fr = "DEMONISTE - PROGRESSION DPS", pt = "BRUXO - EVOLUÇÃO DPS", es = "BRUJO - SUBIDA DPS", de = "HEXENMEISTER - DPS LEVELN", zh = "术士 - 输出升级" },
	subtitle = { en = "Level 1-60 profile", fr = "Profil niveaux 1-60", pt = "Perfil níveis 1-60", es = "Perfil niveles 1-60", de = "Profil Stufe 1-60", zh = "1-60级配置" },
	aoeKey = "aoe",
	cards = {
        {
            title = "LEVELING ROTATION",
            controls = {
                { key="leveling", label="Leveling Rotation", spell="Shadow Bolt", half=false,
                  tooltip={"Leveling Rotation", "Uses the finalized class rotation from before the level-60 sim builds, with its original priorities and existing settings. Select a DPS or Tank build to switch rotations. Turning the active build off automatically selects Leveling Rotation. One rotation always stays selected."} },
            },
        },
		{
			title = "DESTRUCTION BUILD - 11/11/29", subtitle = "MythicSim Shadow and Flame reference; learned spells through level 60.",
			controls = {
				BuildCheck("destruction", "Use Destruction (11/11/29)", "Conflagrate"),
				{ type = "info", text = "Destruction, Affliction and Demonology are exclusive. Each build's options and icon assignments are kept; Leveling Rotation uses the original leveling priority. This selects priorities, without changing talents or equipment. The reference learns Conflagrate and Shadowburn, uses Shadow Bolt, and does not learn Incinerate." },
				{ key = "destConflagrate", label = "Use Conflagrate", spell = "Conflagrate", half = false,
					tooltip = { "Conflagrate", "Requires your applied Immolate and uses the actual cooldown, with a 10-second successful-cast fallback. Confirmed 5/5 Shadow and Flame preserves Immolate. Below 5/5, or if the rank is unreadable, wait for its final two seconds to avoid consuming most of the DoT. Casting Immolate alone never proves it has landed." } },
				{ key = "destShadowburn", label = "Use Shadowburn on cooldown", spell = "Shadowburn", half = false,
					tooltip = { "Shadowburn", "Follows maintained DoTs and Conflagrate. Needs a readable Soul Shard above your saved reserve, mana above the Shoot threshold, and the learned spell. Does not assume a shard refund." } },
				{ key = "destDoom", label = "Destruction: Bane of Doom for long fights", spell = "Bane of Doom", half = false,
					tooltip = { "Bane of Doom", "Requires a readable remaining target lifetime of at least 60 seconds. Otherwise use Bane of Agony. Never replaces an active Bane early." } },
				{ key = "destFinishers", label = "Use confirmed short-fight finishers", spell = "Searing Pain", half = false,
					tooltip = { "Finishers", "With a readable remaining target lifetime: learned Shadowburn at 1.5 seconds or less, if enabled and shards allow; otherwise Searing Pain at 3.5 seconds or less if its cast fits. Unknown lifetime keeps normal priorities." } },
				{ key = "destImpSacrifice", label = "Destruction: prepare Imp sacrifice", spell = "Demonic Sacrifice", half = false,
					tooltip = { "Imp sacrifice", "Out of combat, with Summon pet enabled: summon a learned Imp and sacrifice it for Burning Shadow, then keep the buff without resummoning. Demonic Pact is not required. Does not sacrifice an unidentified demon or prepare a sacrifice during combat. Disable to keep a living pet instead." } },
			},
		},
		{
			title = "DESTRUCTION BURST", subtitle = "Requires Destruction selected and Burst On at the spell icon.",
			controls = {
				{ key = "destEureka", label = "Use Eureka!", spell = "Eureka!" },
				{ key = "destRacials", label = "Use learned offensive racials", spell = "Blood Fury", half = false },
				{ key = "destDeathCoil", label = "Use Death Coil (optional)", spell = "Death Coil",
					tooltip = { "Death Coil", "Default OFF. Optional Burst damage and healing; Horror can move the target." } },
				{ key = "destSoulFire", label = "Use Soul Fire (optional)", spell = "Soul Fire",
					tooltip = { "Soul Fire", "Default OFF. Optional stationary Burst cast; requires enough mana, a readable target lifetime at least as long as the cast, and a Soul Shard above the saved reserve." } },
				{ type = "slider", key = "destBurstMinTargetHP", label = "Destruction Burst minimum target health", min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "slider", key = "destBurstMinMana", label = "Destruction Burst minimum mana", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "info", text = "Burst follows the maintained DoTs. Only learned, enabled and affordable abilities qualify. The Undead reference has no offensive racial; Burst On does not invent one. AoE uses the separate Area Damage controls. Conflagrate, Blood Fury and Berserking are available in the existing Spells tab for Universal icons 1-10." },
			},
		},
		{
			title = "AFFLICTION BUILD - 33/0/18", subtitle = "MythicSim default level-60 talents; learned spells through level 60.",
			controls = {
				BuildCheck("affliction", "Use Affliction (33/0/18)", "Corruption"),
				{ type = "info", text = "The three Warlock builds are exclusive; each build's saved options are kept. Leveling Rotation uses the previous leveling priority. Talents and equipment are not changed. The reference keeps a Succubus and does not learn Siphon Life, Wrack or Shadowburn; optional spells require actual learning." },
				{ key = "affNightfall", label = "Prioritize Nightfall Shadow Bolt", spell = "Shadow Bolt", half = false,
					tooltip = { "Nightfall", "Prioritizes Shadow Bolt when Shadow Trance is positively detected. A confirmed instant proc may be used while moving. Hidden auras do not invent a proc." } },
				{ key = "affDoom", label = "Affliction: Bane of Doom for long fights", spell = "Bane of Doom", half = false,
					tooltip = { "Bane of Doom", "Needs a readable target lifetime of at least 60 seconds. Otherwise use Bane of Agony. Never replace an active Bane early." } },
				{ key = "affFastImmolate", label = "Immolate only with a fast cast", spell = "Immolate", half = false,
					tooltip = { "Fast Immolate", "The live reference uses Immolate only at a readable cast time of 1.5 seconds or less. Unknown or slower casts are skipped. Disable this limit to allow slower learned Immolate while leveling. The main Immolate checkbox is also required." } },
				{ key = "affFinishers", label = "Use confirmed short-fight finishers", spell = "Searing Pain", half = false,
					tooltip = { "Short-fight finishers", "With a readable lifetime estimate: use learned Shadowburn at 1.5 seconds or less, preserving the Soul Shard reserve; otherwise Searing Pain at 3.5 seconds or less if its cast fits and Immolate is fast. Unknown lifetimes keep the normal rotation." } },
				{ key = "affWrack", label = "Use learned Wrack (optional)", spell = "Wrack", half = false,
					tooltip = { "Wrack", "Default OFF; not learned by 33/0/18. If learned and enabled, channels after Corruption and Bane of Agony are active. Requires standing still and enough mana. Existing channels are allowed to finish." } },
			},
		},
		{
			title = "AFFLICTION BURST", subtitle = "Requires Affliction selected and Burst On at the spell icon.",
			controls = {
				{ key = "affAmplifyCurse", label = "Use Amplify Curse", spell = "Amplify Curse", half = false,
					tooltip = { "Amplify Curse", "Empowers the next eligible missing Bane of Agony. Requires its mana, range and permission checks. Never clips an active Bane or uses Amplify with an active Bane of Doom." } },
				{ key = "affEureka", label = "Use Eureka!", spell = "Eureka!" },
				{ key = "affDeathCoil", label = "Use Death Coil (optional)", spell = "Death Coil",
					tooltip = { "Offensive Death Coil", "Default OFF for Affliction: it reduced damage in the one-minute reference. Enable for optional Burst damage and self-healing when learned. Horror can make the target move." } },
				{ type = "slider", key = "affBurstMinTargetHP", label = "Affliction Burst minimum target health", min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "slider", key = "affBurstMinMana", label = "Affliction Burst minimum mana", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "info", text = "Eureka!, Death Coil and learned offensive racials follow the maintained DoTs. The reference race is Undead, so Gnome/Orc/Troll racials are not assumed. No consumables are used. Amplify Curse, Shadowburn and Wrack are listed in the Spells tab for Universal icons." },
			},
		},
		{
			title = "DPS BUILD - DEMONOLOGY", subtitle = "MythicSim default level-60 talents: 2/31/18",
			controls = {
				BuildCheck("demonology", "Use Demonology (2/31/18)", "Summon Succubus"),
				{ type = "info", text = "Uses learned Demonology priorities and prefers Succubus when summoning a missing pet. Selecting Demonology unchecks the other builds and preserves their saved options. Talents and equipment are not changed." },
				{ key = "demoBrand", label = "Searing Pain for Demonic Brand", spell = "Searing Pain", half = false,
					tooltip = { "Demonic Brand", "Uses Searing Pain when the talent is learned, a pet is active and the target's Brand is missing. Brand is a passive effect, not a separate cast. Requires mana above the Shoot threshold." } },
				{ key = "demoDoom", label = "Bane of Doom for long fights", spell = "Bane of Doom", half = false,
					tooltip = { "Bane of Doom", "Only when learned and a readable time-to-die estimate confirms at least 60 seconds remain. Otherwise use Bane of Agony. Never replace an active Bane before it expires." } },
			},
		},
		{
			title = "DEMONOLOGY BURST", subtitle = "Requires Burst On at the spell icon; only learned abilities are used.",
			controls = {
				{ key = "demoEureka", label = "Use Eureka!", spell = "Eureka!", tooltip = { "Eureka!", "Gnome racial. Burst On only, after the maintained DoTs, with usable Shadow Bolt and sufficient mana." } },
				{ key = "demoDeathCoil", label = "Use Death Coil", spell = "Death Coil", tooltip = { "Death Coil", "Offensive Death Coil requires Burst On, range, cooldown and mana checks. Damages the target, restores health and causes Horror." } },
				{ key = "demoSoulFire", label = "Use Soul Fire (optional)", spell = "Soul Fire", tooltip = { "Soul Fire", "Optional Burst cast, default OFF. Requires stationary casting, a target estimated to survive the cast, and a Soul Shard above your saved reserve. Native cooldowns take priority over the fallback." } },
				{ key = "demoFelDomination", label = "Fel Domination for a missing pet", spell = "Fel Domination", tooltip = { "Fel Domination", "Burst On only. Speeds a learned, affordable replacement summon in combat when the pet is missing. The 2/31/18 reference does not take this talent; it is used only if you actually learned it." } },
				{ type = "slider", key = "demoBurstMinTargetHP", label = "Burst minimum target health", min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "slider", key = "demoBurstMinMana", label = "Burst minimum mana", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
			},
		},
		{
			title = "AREA DAMAGE",
			controls = {
				{ key = "aoe", label = "Enable AoE Mode", spell = "Rain of Fire" },
				{ key = "rainOfFire", label = "Rain of Fire", spell = "Rain of Fire" },
				{ key = "hellfire", label = "Hellfire (optional)", spell = "Hellfire", tooltip = { "Hellfire", "AoE On only; default OFF. Requires enough nearby engaged enemies and player health above the health slider. Hellfire damages the player." } },
				{ type = "slider", key = "aoeMinEnemies", label = "AoE minimum enemies", min = 2, max = 5, step = 1 },
				{ type = "slider", key = "aoeMinMana", label = "AoE minimum mana", min = 0, max = 100, step = 1, suffix = " %" },
				{ type = "slider", key = "hellfireMinHP", label = "Hellfire minimum player health", min = 20, max = 100, step = 5, default = 70, suffix = " % HP" },
			},
		},
		{
			title = { en = "PREPARATION", fr = "PREPARATION", pt = "PREPARAÇÃO", es = "PREPARACIÓN", de = "VORBEREITUNG", zh = "准备" },
			controls = {
				{ key = "armor", label = { en = "Demon Armor upkeep", fr = "Maintenir Demon Armor", pt = "Manter Demon Armor", es = "Mantener Demon Armor", de = "Demon Armor halten", zh = "保持Demon Armor" }, spell = "Demon Armor" },
				{ key = "pet", label = { en = "Summon pet", fr = "Invoquer le familier", pt = "Invocar mascote", es = "Invocar mascota", de = "Diener beschwören", zh = "召唤宠物" }, spell = "Summon Voidwalker" },
				{ key = "demoImpSacrifice", label = "Prepare Imp sacrifice", spell = "Demonic Sacrifice", half = false,
					tooltip = { "Imp sacrifice", "Demonology out of combat only. Requires learned Demonic Pact and Demonic Sacrifice, enabled Imp/Succubus summons, enough mana for both summons, and at least one Soul Shard. Prepares Burning Shadow, then summons Succubus. An unidentified pet is kept." } },
				{ key = "soulLink", label = "Maintain Soul Link", spell = "Soul Link", tooltip = { "Soul Link", "Demonology only. Keeps learned Soul Link active while a living pet is present, including after a replacement summon." } },
				{ key = "drink", label = { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" } },
			},
		},
		{
			title = { en = "CURSE SELECTION", fr = "CHOIX DE MALEDICTION", pt = "SELEÇÃO DE MALDIÇÃO", es = "SELECCIÓN DE MALDICIÓN", de = "FLUCHAUSWAHL", zh = "诅咒选择" },
			subtitle = {
				en = "Select one curse before damage DoTs. Selecting it unchecks the others; all unchecked disables curses. An active utility curse advances to DoTs. Bane of Agony is separate.",
				fr = "Choisissez une malediction avant les DoT. La cocher decoche les autres ; aucune coche les desactive. Une malediction utilitaire active permet de passer aux DoT. Bane of Agony reste separe.",
				pt = "Selecione uma maldição antes dos DoTs. Marcar uma desmarca as outras; nenhuma marcada desativa maldições. Uma maldição ativa permite seguir para os DoTs. Bane of Agony é separado.",
				es = "Selecciona una maldición antes de los DoTs. Marcar una desmarca las otras; ninguna marcada desactiva maldiciones. Una maldición activa permite pasar a los DoTs. Bane of Agony es independiente.",
				de = "Einen Fluch vor den DoTs auswählen. Aktivieren deaktiviert die anderen; alle aus deaktiviert Flüche. Ein aktiver Fluch lässt die Rotation zu DoTs weitergehen. Bane of Agony ist separat.",
				zh = "选择一个诅咒，在伤害DoT前施放。勾选后会取消其他诅咒；全部取消则禁用诅咒。已有有效诅咒时继续施放DoT。Bane of Agony独立。",
			},
			controls = {
				CurseCheck("curseElements", "Curse of the Elements"),
				CurseCheck("curseWeakness", "Curse of Weakness"),
				CurseCheck("curseRecklessness", "Curse of Recklessness"),
				CurseCheck("curseTongues", "Curse of Tongues"),
			},
		},
		{
			title = { en = "DAMAGE OVER TIME", fr = "DEGATS SUR LA DUREE", pt = "DANO CONTÍNUO", es = "DAÑO PERIÓDICO", de = "SCHADEN ÜBER ZEIT", zh = "持续伤害" },
			controls = {
				{ key = "immolate", label = "Immolate", spell = "Immolate" },
				{ key = "corruption", label = "Corruption", spell = "Corruption" },
				{ key = "agony", label = "Bane of Agony", spell = "Bane of Agony" },
				{ key = "siphonLife", label = "Siphon Life (if learned)", spell = "Siphon Life" },
				{ key = "shadowBolt", label = "Shadow Bolt", spell = "Shadow Bolt" },
			},
		},
		{
			title = { en = "SURVIVAL & RESOURCES", fr = "SURVIE ET RESSOURCES", pt = "SOBREVIVÊNCIA E RECURSOS", es = "SUPERVIVENCIA Y RECURSOS", de = "ÜBERLEBEN & RESSOURCEN", zh = "生存与资源" },
			controls = {
				{ key = "lifetap", label = "Life Tap", spell = "Life Tap" },
				{ type = "slider", key = "lifeTapMana", label = {
					en = "Life Tap below mana",
					fr = "Life Tap sous ce niveau de mana",
					pt = "Life Tap abaixo desta mana",
					es = "Life Tap por debajo de este maná",
					de = "Life Tap unter Mana",
					zh = "法力低于此值时使用Life Tap"
				}, min = 5, max = 95, step = 5, default = 25, suffix = " %" },
				{ type = "slider", key = "shootMana", label = {
					en = "Shoot below mana",
					fr = "Shoot sous ce niveau de mana",
					pt = "Shoot abaixo desta mana",
					es = "Shoot por debajo de este maná",
					de = "Shoot unter Mana",
					zh = "法力低于此值时使用Shoot"
				}, min = 5, max = 95, step = 5, default = 25, suffix = " %", tooltip = {
					{ en = "Shoot mana protection" },
					{ en = "Shoot uses the higher of this slider or 10% mana. Setting the slider below 10% keeps the 10% reserve." },
				} },
				{ key = "drainsoul", label = { en = "Drain Soul to maintain Soul Shards", fr = "Drain Soul pour maintenir les Soul Shards", pt = "Drain Soul para manter Soul Shards", es = "Drain Soul para mantener Soul Shards", de = "Drain Soul zum Halten von Soul Shards", zh = "使用Drain Soul维持Soul Shard数量" }, spell = "Drain Soul" },
				{ type = "dynamic_info", getText = function()
					local rotation = AL.rotations and AL.rotations.WARLOCK
					local count, source
					if rotation and rotation.SoulShardCount then
						count, source = rotation.SoulShardCount()
					end
					if count == nil then
						return "Soul Shards currently in bag: unreadable"
					end
					return "Soul Shards currently in bag: " .. tostring(count)
						.. " (" .. tostring(source or "unknown") .. ")"
				end },
				{ type = "slider", key = "drainSoulMinShards", label = { en = "Minimum Soul Shards", fr = "Soul Shards minimum", pt = "Soul Shards mínimos", es = "Soul Shards mínimos", de = "Mindestanzahl Soul Shards", zh = "最低Soul Shard数量" }, min = 1, max = 5, step = 1, default = 1 },
				{ key = "fear", label = { en = "Fear at melee", fr = "Fear au corps a corps", pt = "Fear em corpo a corpo", es = "Fear en cuerpo a cuerpo", de = "Fear im Nahkampf", zh = "近战时Fear" }, spell = "Fear" },
				{ key = "healthfunnel", label = { en = "Health Funnel for injured pet", fr = "Health Funnel pour familier blesse", pt = "Health Funnel para mascote ferido", es = "Health Funnel para mascota herida", de = "Health Funnel für verletzten Diener", zh = "宠物受伤时使用Health Funnel" }, spell = "Health Funnel" },
				{ type = "slider", key = "healthFunnelPetHP", label = { en = "Health Funnel below pet health", fr = "Health Funnel sous cette vie du familier", pt = "Health Funnel abaixo desta vida do mascote", es = "Health Funnel por debajo de esta salud de mascota", de = "Health Funnel unter Diener-Gesundheit", zh = "宠物生命低于此值时Health Funnel" }, min = 10, max = 80, step = 5, default = 40, suffix = " % HP" },
				{ type = "slider", key = "healthFunnelMinPlayerHP", label = { en = "Minimum player health for Health Funnel", fr = "Vie joueur minimum pour Health Funnel", pt = "Vida mínima do jogador para Health Funnel", es = "Salud mínima del jugador para Health Funnel", de = "Mindest-Gesundheit für Health Funnel", zh = "Health Funnel最低玩家生命值" }, min = 20, max = 100, step = 5, default = 60, suffix = " % HP" },
			},
		},
	},
}, "0.20.3")

