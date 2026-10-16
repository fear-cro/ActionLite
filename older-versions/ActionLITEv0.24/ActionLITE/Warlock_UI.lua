local ADDON, AL = ...

local CURSE_KEYS = { "curseElements", "curseWeakness", "curseRecklessness", "curseTongues" }

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
	title = { en = "WARLOCK - AFFLICTION LEVELING", fr = "DEMONISTE - PROGRESSION AFFLICTION", pt = "BRUXO - EVOLUÇÃO AFLIÇÃO", es = "BRUJO - SUBIDA AFLICCIÓN", de = "HEXENMEISTER - GEBRECHEN LEVELN", zh = "术士 - 痛苦升级" },
	subtitle = { en = "Level 1-30 profile", fr = "Profil niveaux 1-30", pt = "Perfil níveis 1-30", es = "Perfil niveles 1-30", de = "Profil Stufe 1-30", zh = "1-30级配置" },
	cards = {
		{
			title = { en = "PREPARATION", fr = "PREPARATION", pt = "PREPARAÇÃO", es = "PREPARACIÓN", de = "VORBEREITUNG", zh = "准备" },
			controls = {
				{ key = "armor", label = { en = "Demon Armor upkeep", fr = "Maintenir Demon Armor", pt = "Manter Demon Armor", es = "Mantener Demon Armor", de = "Demon Armor halten", zh = "保持Demon Armor" }, spell = "Demon Armor" },
				{ key = "pet", label = { en = "Summon pet", fr = "Invoquer le familier", pt = "Invocar mascote", es = "Invocar mascota", de = "Diener beschwören", zh = "召唤宠物" }, spell = "Summon Voidwalker" },
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
				{ key = "agony", label = "Bane of Agony", spell = "Bane of Agony" },
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
}, "0.16.1")

