local ADDON, AL = ...

AL.RegisterSimpleClassUI("DRUID", {
	title = { en = "DRUID - FERAL LEVELING", fr = "DRUIDE - PROGRESSION FAROUCHE", pt = "DRUIDA - EVOLUÇÃO FERAL", es = "DRUIDA - SUBIDA FERAL", de = "DRUIDE - WILDER KAMPF LEVELN", zh = "德鲁伊 - 野性升级" },
	subtitle = { en = "Adapts to caster, Bear and Cat forms", fr = "S'adapte aux formes lanceur, Ours et Felin", pt = "Adapta-se às formas conjurador, Urso e Felino", es = "Se adapta a las formas lanzador, Oso y Felino", de = "Passt sich an Zauber-, Bären- und Katzengestalt an", zh = "适应施法者、熊和猎豹形态" },
	aoeKey = "aoe",
	cards = {
		{
			title = { en = "PREPARATION & SURVIVAL", fr = "PREPARATION ET SURVIE", pt = "PREPARAÇÃO E SOBREVIVÊNCIA", es = "PREPARACIÓN Y SUPERVIVENCIA", de = "VORBEREITUNG & ÜBERLEBEN", zh = "准备与生存" },
			controls = {
				{ key = "buffs", label = { en = "Mark of the Wild upkeep", fr = "Maintenir Mark of the Wild", pt = "Manter Mark of the Wild", es = "Mantener Mark of the Wild", de = "Mark of the Wild halten", zh = "保持Mark of the Wild" }, spell = "Mark of the Wild" },
				{ key = "thorns", label = { en = "Thorns upkeep", fr = "Maintenir Thorns", pt = "Manter Thorns", es = "Mantener Thorns", de = "Thorns halten", zh = "保持Thorns" }, spell = "Thorns" },
				{ key = "heal", label = { en = "Healing reminders", fr = "Rappels de soins", pt = "Lembretes de cura", es = "Recordatorios de sanación", de = "Heil-Erinnerungen", zh = "治疗提醒" }, spell = "Rejuvenation" },
				{ key = "drink", label = { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" } },
				{ type = "info", text = { en = "Heal at or below 60% HP out of combat, 50% in caster combat, and 25% for an emergency in form. Drink at or below 30% mana in caster form." } },
			},
		},
		{
			title = { en = "CAT FORM", fr = "FORME DE FELIN", pt = "FORMA DE FELINO", es = "FORMA FELINA", de = "KATZENGESTALT", zh = "猎豹形态" },
			controls = {
				{ key = "rake", label = "Rake", spell = "Rake" },
				{ key = "rip", label = { en = "Rip on durable targets", fr = "Rip sur les cibles durables", pt = "Rip em alvos resistentes", es = "Rip en objetivos duraderos", de = "Rip auf zähe Ziele", zh = "对耐久目标Rip" }, spell = "Rip" },
				{ key = "tigersfury", label = "Tiger's Fury", spell = "Tiger's Fury" },
				{ type = "info", text = { en = "Rake above 40% target HP. Rip at 4+ combo points above 60%. Ferocious Bite at 5 points, or 3+ points at or below 40%. Claw builds points; Shred is an optional Prowl opener." } },
			},
		},
		{
			title = { en = "BEAR FORM", fr = "FORME D'OURS", pt = "FORMA DE URSO", es = "FORMA DE OSO", de = "BÄRENGESTALT", zh = "熊形态" },
			controls = {
				{ key = "enrage", label = { en = "Enrage and Demoralizing Roar", fr = "Enrage et Demoralizing Roar", pt = "Enrage e Demoralizing Roar", es = "Enrage y Demoralizing Roar", de = "Enrage und Demoralizing Roar", zh = "Enrage和Demoralizing Roar" }, spell = "Enrage" },
				{ key = "bash", label = { en = "Bash interrupt", fr = "Interruption Bash", pt = "Interrupção Bash", es = "Interrupción Bash", de = "Bash-Unterbrechung", zh = "Bash打断" }, spell = "Bash" },
				{ key = "aoe", label = { en = "Enable Swipe AoE", fr = "Activer l'AoE Swipe", pt = "Ativar AoE Swipe", es = "Activar AoE Swipe", de = "Swipe AoE aktivieren", zh = "启用Swipe AoE" }, spell = "Swipe" },
				{ type = "info", text = { en = "Swipe requires at least two confirmed enemies in melee range. Bear attacks wait for enough rage; Bash takes priority when a target is casting." } },
			},
		},
	},
}, "0.8.1")

