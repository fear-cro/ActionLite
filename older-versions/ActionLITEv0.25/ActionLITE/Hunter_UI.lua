local ADDON, AL = ...

-- Interface declarative Hunter. Chaque cle correspond directement a
-- rotation\Hunter.lua ; les seuils ne dupliquent aucune logique dans l'UI.
AL.RegisterSimpleClassUI("HUNTER", {
	title = { en = "HUNTER - LEVELING", fr = "CHASSEUR - PROGRESSION", pt = "CAÇADOR - EVOLUÇÃO", es = "CAZADOR - SUBIDA", de = "JÄGER - LEVELN", zh = "猎人 - 升级" },
	subtitle = { en = "Level 1-30 - pet, ranged, dead zone and AoE", fr = "Niveaux 1-30 - familier, distance, zone morte et AoE", pt = "Níveis 1-30 - mascote, distância, zona morta e AoE", es = "Niveles 1-30 - mascota, distancia, zona muerta y AoE", de = "Stufe 1-30 - Begleiter, Fernkampf, tote Zone und AoE", zh = "1-30级 - 宠物、远程、死区和AoE" },
	aoeKey = "aoe",
	cards = {
		{
			title = { en = "PET MANAGEMENT", fr = "GESTION DU FAMILIER", pt = "GERENCIAR MASCOTE", es = "GESTIÓN DE MASCOTA", de = "BEGLEITER-VERWALTUNG", zh = "宠物管理" },
			controls = {
				{ key = "callpet", label = { en = "Call or revive pet", fr = "Appeler ou ranimer le familier", pt = "Chamar ou reviver mascote", es = "Llamar o revivir mascota", de = "Begleiter rufen oder wiederbeleben", zh = "召唤或复活宠物" }, spell = "Call Pet" },
				{ key = "mendpet", label = { en = "Mend Pet", fr = "Soigner le familier", pt = "Curar mascote", es = "Curar mascota", de = "Mend Pet", zh = "治疗宠物" }, spell = "Mend Pet" },
				{ type = "slider", key = "petMendHP", label = { en = "Mend Pet health threshold", fr = "Seuil de vie Mend Pet", pt = "Limite de vida Mend Pet", es = "Umbral de salud Mend Pet", de = "Mend Pet Gesundheitsschwelle", zh = "Mend Pet生命值阈值" },
					min = 20, max = 95, step = 5, default = 50, suffix = " %" },
			},
		},
		{
			title = { en = "PREPARATION & OPENING", fr = "PREPARATION ET OUVERTURE", pt = "PREPARAÇÃO E ABERTURA", es = "PREPARACIÓN Y APERTURA", de = "VORBEREITUNG & ERÖFFNUNG", zh = "准备与开场" },
			controls = {
				{ key = "aspect", half = false, label = { en = "Combat Aspect upkeep", fr = "Maintenir l'Aspect de combat", pt = "Manter Aspecto de combate", es = "Mantener Aspecto de combate", de = "Kampfaspekt halten", zh = "保持战斗守护" }, spell = "Aspect of the Hawk" },
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
			title = { en = "AOE & BURST", fr = "AOE ET BURST", pt = "AOE E BURST", es = "AOE Y BURST", de = "AOE & BURST", zh = "AOE与BURST" },
			controls = {
				{ key = "aoe", label = { en = "Enable Multi-Shot AoE", fr = "Activer l'AoE Multi-Shot", pt = "Ativar AoE Multi-Shot", es = "Activar AoE Multi-Shot", de = "Multi-Shot AoE aktivieren", zh = "启用Multi-Shot AoE" }, spell = "Multi-Shot" },
				{ type = "slider", key = "aoeMinEnemies", label = { en = "Minimum enemies", fr = "Ennemis minimum", pt = "Mínimo de inimigos", es = "Enemigos mínimos", de = "Mindestanzahl Gegner", zh = "最少敌人数" },
					min = 2, max = 5, step = 1, default = 2, half = true },
				{ key = "rapidfire", label = { en = "Rapid Fire during Burst", fr = "Rapid Fire pendant le Burst", pt = "Rapid Fire durante o Burst", es = "Rapid Fire durante el Burst", de = "Rapid Fire während Burst", zh = "Burst期间Rapid Fire" }, spell = "Rapid Fire" },
				{ type = "slider", key = "burstMinTargetHP", label = { en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Salud mínima del objetivo para Burst", de = "Burst: Mindestgesundheit des Ziels", zh = "Burst目标最低生命值" },
					min = 0, max = 100, step = 5, default = 40, suffix = " %", half = true },
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
	},
}, "0.9.4")
