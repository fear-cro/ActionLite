local ADDON, AL = ...

local function HealingSpecCheck(key, label, spell, tooltip)
	return {
		key = key, label = label, spell = spell, half = false, tooltip = tooltip,
		onChange = function()
			local profile = AL.ES and AL.ES() or (AL.S and AL.S())
			local rotation = AL.rotations and AL.rotations.PRIEST
			if profile and rotation and type(rotation.SetHealingSpec) == "function" then
				rotation.SetHealingSpec(key, profile[key] == true, profile)
			elseif profile and profile[key] == true then
				local other = key == "healingDiscipline" and "healingHoly" or "healingDiscipline"
				profile[other] = false
			end
			if AL.UI and AL.UI.Repaint then AL.UI.Repaint() end
		end,
	}
end

AL.RegisterSimpleClassUI("PRIEST", {
	title = { en = "PRIEST - LEVELING", fr = "PRETRE - PROGRESSION", pt = "SACERDOTE - PROGRESSÃO", es = "SACERDOTE - PROGRESIÓN", de = "PRIESTER - LEVELN", zh = "牧师 - 升级" },
	subtitle = { en = "Shadow or Smite solo profile - interface 0.31.0", fr = "Profil solo Ombre ou Smite - interface 0.31.0", pt = "Perfil solo Sombra ou Smite - interface 0.31.0", es = "Perfil en solitario Sombra o Smite - interfaz 0.31.0", de = "Solo-Profil Schatten oder Smite - Interface 0.31.0", zh = "暗影或 Smite 单刷配置 - 界面 0.31.0" },
	aoeKey = "aoe",
	cards = {
        {
            title = "LEVELING ROTATION",
            id="leveling-rotation", build="leveling", group="damage",
            controls = {
                { key="leveling", label="Leveling Rotation", spell="Smite", half=false,
                  tooltip={"Leveling Rotation", "Uses the finalized class rotation from before the level-60 sim builds, with its original priorities and existing settings. Select a DPS or Tank build to switch rotations. Turning the active build off automatically selects Leveling Rotation. One rotation always stays selected."} },
            },
        },
		{
			title = "HEALING ROTATION",
			id = "healing-engine", group = "survival",
			controls = {
				{ key = "healingEngine", label = "Enable Healing Rotation", spell = "Lesser Heal", half = false,
				  tooltip = { "Enable Healing Rotation", "Enables grouped healing, selected-ally distress healing, and the protected Action focus pixel. Solo characters continue using the selected leveling or damage rotation." } },
				{ type = "slider", key = "healingInitiateHP", label = "Initiate healing at HP", min = 5, max = 100, step = 5, default = 80, suffix = " %" },
				{ type = "slider", key = "healingEmergencyHP", label = "Emergency healing", min = 5, max = 100, step = 5, default = 30, suffix = " %" },
				HealingSpecCheck("healingDiscipline", "Discipline Priest", "Penance", {
					"Discipline Priest", "Selects the Discipline-only party priority: tracked shields, caster Power Infusion, Penance at 20 points below the heal slider, Binding/Flash filler, and Inner Focus with Prayer of Healing for emergencies."
				}),
				HealingSpecCheck("healingHoly", "Holy Priest", "Prayer of Mending", {
					"Holy Priest", "Selects the Holy-only party priority: tracked Renew, efficient Heal, Binding/Flash for larger heals, and Prayer of Mending or Inner Focus with Greater Heal for emergencies."
				}),
				{ type = "info", text = "Discipline and Holy are mutually exclusive. Tank and healer thresholds use the selected value; known DPS members use 10 points less. Damage pauses for five seconds after a healing cast. Learned race-specific abilities are used for emergency healing; Dark Sacrifice requires the Priest to remain above 70% health. Prayer of Healing stays manual except for Discipline's Inner Focus emergency sequence. Inspiration is a passive critical-heal proc, so direct tank heals are prioritized rather than trying to cast it." },
			},
		},
        {
            title = "SHADOW BUILD — 18/0/33",
            id="shadow-build-18-0-33", build="shadow", group="damage",
            controls = {
                { key="shadow",label="Use Shadow (18/0/33)",spell="Shadowform",half=false,
                  tooltip={"Shadow 18/0/33","Uses your learned Shadow spells through level 60. Overrides the older role while checked; unchecking selects Leveling Rotation. Does not change talents or equipment."} },
                { key="shadowForm",label="Maintain Shadowform",spell="Shadowform" },
                { key="shadowMindFlay",label="Use Mind Flay filler",spell="Mind Flay" },
                { key="shadowWordDeath",label="Use Shadow Word: Death",spell="Shadow Word: Death" },
                { type="slider",key="shadowDeathMinHP",label="Shadow Word: Death above player health",min=20,max=95,step=5,default=50,suffix=" % HP" },
                { type="info",text="Shadowform, Shadow Word: Pain, Devouring Plague, Mind Blast, Shadow Word: Death, then Mind Flay. Uses existing spell checkboxes and health/mana settings. Preserve active casts and channels; no automatic clipping." },
                { type="info",text="Self-healing retains Renew below 80% and Lesser Heal below 60% in combat / below 80% out of combat after Renew. The build leaves a confirmed Shadowform to heal, then restores it. The shield health slider applies in combat." },
            },
        },
        {
            title = "SHADOW BURST",
            id="shadow-burst", build="shadow", group="burst",
            controls = {
                { key="shadowInnerFocus",label="Inner Focus for Mind Blast (Burst)",spell="Inner Focus" },
                { key="shadowRacials",label="Learned racial cooldowns (Burst)",spell="Berserking" },
                { key="shadowFiend",label="Shadowfiend (Burst)",spell="Shadowfiend" },
                { type="slider",key="shadowFiendMana",label="Shadowfiend at/below mana",min=0,max=100,step=5,default=70,suffix=" %" },
                { key="shadowSacrifice",label="Dark Sacrifice (Burst, optional)",spell="Dark Sacrifice" },
                { type="slider",key="shadowSacrificeMana",label="Dark Sacrifice at/below mana",min=0,max=100,step=5,default=30,suffix=" %" },
                { type="slider",key="shadowSacrificeHP",label="Dark Sacrifice minimum player health",min=20,max=100,step=5,default=80,suffix=" % HP" },
                { type="info",text="Requires Burst On, a hostile combat target and the existing Burst target-health slider. Inner Focus and racials wait for eligible Mind Blast after five readable Shadow Weaving stacks, or eight seconds of combat when stacks are hidden. Dark Sacrifice is OFF by default because it drains health over time." },
            },
        },
        {
            title = "SHADOW AOE",
            id="shadow-aoe", build="shadow", group="aoe",
            controls = {
                { key="aoe",label="Enable AoE mode" },
                { key="shadowHolyNova",label="Allow learned Holy Nova outside Shadowform",spell="Holy Nova" },
                { type="slider",key="aoeMinEnemies",label="AoE minimum engaged enemies within 10 yards",min=2,max=5,step=1,default=2,suffix="" },
                { type="slider",key="aoeMinMana",label="AoE minimum mana",min=0,max=100,step=5,default=40,suffix=" %" },
                { type="info",text="The default 18/0/33 build has no Holy Nova talent. This optional spell is OFF by default and requires learned Holy Nova, AoE On, confirmed nearby engaged enemies and the mana setting. It never cancels Shadowform for area damage. Without an eligible area spell, normal Shadow damage continues." },
            },
        },
		{
			title = { en = "DAMAGE PROFILE", fr = "PROFIL DE DEGATS", pt = "PERFIL DE DANO", es = "PERFIL DE DAÑO", de = "SCHADENSPROFIL", zh = "伤害配置" },
			id="damage-profile", group="damage",
			controls = {
				{ type = "dropdown", key = "priestRole", label = { en = "Leveling playstyle", fr = "Rotation active", pt = "Rotação ativa", es = "Rotación activa", de = "Aktive Rotation", zh = "当前循环" }, default = "SHADOW", options = {
					{ label = { en = "Shadow - Mind Flay", fr = "Ombre - Mind Flay", pt = "Sombra - Mind Flay", es = "Sombra - Mind Flay", de = "Schatten - Mind Flay", zh = "暗影 - Mind Flay" }, value = "SHADOW" },
					{ label = { en = "Smite - Holy damage", fr = "Smite - degats Sacre", pt = "Smite - dano Sagrado", es = "Smite - daño Sagrado", de = "Smite - Heiligschaden", zh = "Smite - 神圣伤害" }, value = "SMITE" },
				} },
				{ key = "mindBlast", label = { en = "Mind Blast on cooldown", fr = "Mind Blast des que disponible", pt = "Mind Blast assim que disponível", es = "Mind Blast en cuanto esté disponible", de = "Mind Blast sobald bereit", zh = "Mind Blast 冷却完毕即用" }, spell = "Mind Blast" },
				{ key = "holyFire", label = { en = "Holy Fire in Smite profile", fr = "Holy Fire avec le profil Smite", pt = "Holy Fire no perfil Smite", es = "Holy Fire en el perfil Smite", de = "Holy Fire im Smite-Profil", zh = "Smite 配置中使用 Holy Fire" }, spell = "Holy Fire" },
				{ key = "usePenance", label = "Use Penance", spell = "Penance" },
				{ type = "slider", key = "offensivePenanceMana", label = "Offensive Penance minimum mana", min = 0, max = 100, step = 5, default = 80, suffix = " % Mana" },
			},
		},
		{
			title = { en = "BUFFS & SHIELD", fr = "BUFFS ET BOUCLIER", pt = "BUFFS E ESCUDO", es = "BUFFS Y ESCUDO", de = "BUFFS & SCHILD", zh = "增益与护盾" },
			id="buffs-shield", group="preparation",
			controls = {
				{ key = "buffs", label = { en = "Maintain Fortitude", fr = "Maintenir Fortitude", pt = "Manter Fortitude", es = "Mantener Fortitude", de = "Fortitude aufrechterhalten", zh = "保持 Fortitude" }, spell = "Power Word: Fortitude" },
				{ key = "divineSpirit", label = "Maintain Divine Spirit", spell = "Divine Spirit" },
				{ key = "innerfire", label = { en = "Maintain Inner Fire", fr = "Maintenir Inner Fire", pt = "Manter Inner Fire", es = "Mantener Inner Fire", de = "Inner Fire aufrechterhalten", zh = "保持 Inner Fire" }, spell = "Inner Fire" },
				{ key = "shield", label = { en = "Pre-shield and shield at low health", fr = "Pre-bouclier et bouclier a faible vie", pt = "Pré-escudo e escudo com vida baixa", es = "Preescudo y escudo con salud baja", de = "Vorab-Schild und Schild bei wenig Gesundheit", zh = "预先护盾及低血量护盾" }, spell = "Power Word: Shield" },
				{ type = "slider", key = "shieldHP", label = { en = "Shield health threshold", fr = "Seuil de vie du bouclier", pt = "Limite de vida do escudo", es = "Umbral de salud del escudo", de = "Gesundheitsschwelle für Schild", zh = "护盾生命值阈值" }, min = 5, max = 100, step = 5, default = 65, suffix = " % HP" },
			},
		},
		{
			title = { en = "SELF HEALING", fr = "SOINS PERSONNELS", pt = "AUTOCURA", es = "AUTOSANACIÓN", de = "SELBSTHEILUNG", zh = "自我治疗" },
			id="self-healing", group="survival",
			subtitle = {
				en = "This profile heals the player only; party target selection remains manual.",
				fr = "Ce profil soigne uniquement le joueur ; la selection des allies reste manuelle.",
				pt = "Este perfil cura apenas o jogador; a seleção de aliados continua manual.",
				es = "Este perfil solo cura al jugador; la selección de aliados sigue siendo manual.",
				de = "Dieses Profil heilt nur dich selbst; Gruppenziele wählst du weiterhin manuell.",
				zh = "此配置只治疗玩家自己；队友目标选择仍需手动。",
			},
			controls = {
				{ key = "fade", label = { en = "Fade emergency", fr = "Fade d'urgence", pt = "Fade de emergência", es = "Fade de emergencia", de = "Fade-Notfall", zh = "Fade 紧急模式" }, spell = "Fade" },
				{ key = "touchOfWeakness", label = "Touch of Weakness", spell = "Touch of Weakness" },
				{ key = "renew", label = { en = "Renew below 80% HP (in or out of combat)", fr = "Renew sous 80% PV (combat ou hors combat)", pt = "Renew abaixo de 80% HP (em ou fora de combate)", es = "Renew por debajo de 80% de vida (en o fuera de combate)", de = "Renew unter 80% HP (im oder außerhalb des Kampfes)", zh = "生命低于 80% 时使用 Renew（战斗内外）" }, spell = "Renew" },
				{ key = "heal", label = { en = "Lesser Heal: combat <60%; OOC <80% after Renew", fr = "Lesser Heal : combat <60%; hors combat <80% après Renew", pt = "Lesser Heal: combate <60%; fora <80% após Renew", es = "Lesser Heal: combate <60%; fuera <80% tras Renew", de = "Lesser Heal: Kampf <60%; außerhalb <80% nach Renew", zh = "Lesser Heal：战斗 <60%；非战斗且 Renew 后 <80%" }, spell = "Lesser Heal" },
				{ type = "info", text = { en = "Fixed healing rules: Renew below 80% if absent. Lesser Heal in combat below 60%; out of combat below 80% only while Renew is present. Forever secret-health thresholds are driven by the display/glow visual layer.", fr = "Règles fixes de soin avec seuils protégés par Forever.", pt = "Regras fixas de cura com limites protegidos pelo Forever.", es = "Reglas fijas de sanación con umbrales protegidos por Forever.", de = "Feste Heilregeln mit geschützten Forever-Schwellen.", zh = "固定治疗规则；Forever 的受保护生命阈值由显示层处理。" } },
			},
		},
		{
			title = { en = "SHADOW EFFECTS", fr = "EFFETS D'OMBRE", pt = "EFEITOS DE SOMBRA", es = "EFECTOS DE SOMBRA", de = "SCHATTENEFFEKTE", zh = "暗影效果" },
			id="shadow-effects", group="damage",
			controls = {
				{ key = "shadowWordPain", label = "Shadow Word: Pain", spell = "Shadow Word: Pain" },
				{ type = "slider", key = "dotMinTargetHP", label = { en = "DoT minimum target health", fr = "Vie cible minimum pour les DoT", pt = "Vida mínima do alvo para DoT", es = "Salud mínima del objetivo para DoT", de = "Min. Zielgesundheit für DoTs", zh = "DoT 最低目标生命值" }, min = 0, max = 100, step = 5, default = 35, suffix = " % HP" },
				{ key = "devouringPlague", label = "Devouring Plague", spell = "Devouring Plague" },
				{ type = "slider", key = "plagueMinMana", label = { en = "Plague minimum mana", fr = "Mana minimum Devouring Plague", pt = "Mana mínima Devouring Plague", es = "Maná mínimo Devouring Plague", de = "Min. Mana für Devouring Plague", zh = "Devouring Plague 最低法力值" }, min = 0, max = 100, step = 5, default = 40, suffix = " %" },
				{ type = "slider", key = "plagueMinTargetHP", label = { en = "Plague minimum target health", fr = "Vie cible minimum Devouring Plague", pt = "Vida mínima do alvo Devouring Plague", es = "Salud mínima del objetivo Devouring Plague", de = "Min. Zielgesundheit für Devouring Plague", zh = "Devouring Plague 最低目标生命值" }, min = 0, max = 100, step = 5, default = 60, suffix = " % HP" },
				{ key = "vampiricEmbrace", label = "Vampiric Embrace", spell = "Vampiric Embrace" },
				{ type = "slider", key = "vampiricMinTargetHP", label = { en = "Vampiric minimum target health", fr = "Vie cible minimum Vampiric Embrace", pt = "Vida mínima do alvo Vampiric Embrace", es = "Salud mínima del objetivo Vampiric Embrace", de = "Min. Zielgesundheit für Vampiric Embrace", zh = "Vampiric Embrace 最低目标生命值" }, min = 0, max = 100, step = 5, default = 60, suffix = " % HP" },
			},
		},
		{
			title = { en = "CONTROL & SURVIVAL", fr = "CONTROLE ET SURVIE", pt = "CONTROLE E SOBREVIVÊNCIA", es = "CONTROL Y SUPERVIVENCIA", de = "KONTROLLE & ÜBERLEBEN", zh = "控制与生存" },
			id="control-survival", group="survival",
			controls = {
				{ key = "fear", label = { en = "Psychic Scream in melee", fr = "Psychic Scream au corps a corps", pt = "Psychic Scream no corpo a corpo", es = "Psychic Scream cuerpo a cuerpo", de = "Psychic Scream im Nahkampf", zh = "近战时使用 Psychic Scream" }, spell = "Psychic Scream" },
				{ type = "slider", key = "fearHP", label = { en = "Psychic Scream health threshold", fr = "Seuil de vie Psychic Scream", pt = "Limite de vida Psychic Scream", es = "Umbral de salud Psychic Scream", de = "Gesundheitsschwelle für Psychic Scream", zh = "Psychic Scream 生命值阈值" }, min = 5, max = 95, step = 5, default = 50, suffix = " % HP" },
				{ key = "silence", label = { en = "Silence enemy casts", fr = "Silence sur les incantations", pt = "Silence nas conjurações inimigas", es = "Silence en lanzamientos enemigos", de = "Silence gegen gegnerische Zauber", zh = "用 Silence 打断敌方施法" }, spell = "Silence" },
			},
		},
		{
			title = { en = "MANA & WAND", fr = "MANA ET BAGUETTE", pt = "MANA E VARINHA", es = "MANÁ Y VARITA", de = "MANA & ZAUBERSTAB", zh = "法力与魔杖" },
			id="mana-wand", group="resources",
			controls = {
				{ key = "wand", icon = "Interface\\Icons\\INV_Wand_01", label = { en = "Use wand to conserve mana", fr = "Utiliser la baguette pour economiser le mana", pt = "Usar varinha para poupar mana", es = "Usar varita para ahorrar maná", de = "Zauberstab nutzen, um Mana zu sparen", zh = "使用魔杖节省法力" }, spell = "Shoot" },
				{ type = "slider", key = "wandMana", icon = "Interface\\Icons\\INV_Wand_01", label = {
					en = "Wand / Shoot below mana threshold (Smite):",
					fr = "Baguette / Shoot sous ce seuil de mana (Smite):",
					pt = "Varinha / Shoot abaixo do limite de mana (Smite):",
					es = "Varita / Shoot bajo el umbral de maná (Smite):",
					de = "Zauberstab / Shoot unter der Mana-Schwelle (Smite):",
					zh = "法力低于阈值时使用魔杖 / Shoot（Smite）："
				}, min = 0, max = 95, step = 5, default = 25, suffix = " %" },
				{ type = "slider", key = "mindBlastMana", icon = "Interface\\Icons\\INV_Wand_01", label = {
					en = "Skip Mind Blast at or below mana:",
					fr = "Ignorer Mind Blast à ce niveau de mana ou moins :",
					pt = "Ignorar Mind Blast com mana igual ou inferior a:",
					es = "Omitir Mind Blast con maná igual o inferior a:",
					de = "Mind Blast bei diesem Mana oder weniger auslassen:",
					zh = "法力等于或低于此值时跳过 Mind Blast："
				}, min = 0, max = 95, step = 5, default = 50, suffix = " %" },
				{ type = "slider", key = "wandTargetHP", label = { en = "Wand below target health", fr = "Baguette sous la vie cible", pt = "Varinha abaixo da vida do alvo", es = "Varita bajo la salud del objetivo", de = "Zauberstab unter Zielgesundheit", zh = "目标生命值低于此值时用魔杖" }, min = 0, max = 80, step = 5, default = 20, suffix = " % HP" },
				{ key = "drink", label = { en = "Drink reminder", fr = "Rappel de boisson", pt = "Lembrete de bebida", es = "Recordatorio de bebida", de = "Trink-Erinnerung", zh = "喝水提醒" } },
				{ type = "slider", key = "drinkMana", label = { en = "Drink below mana", fr = "Boire sous ce niveau de mana", pt = "Beber abaixo deste nível de mana", es = "Beber por debajo de este maná", de = "Trinken unter Mana", zh = "法力低于此值时喝水" }, min = 0, max = 80, step = 5, default = 35, suffix = " %" },
			},
		},
        { title="BURST LIMITS", id="burst-limits", group="burst", controls={
				{ type = "slider", key = "burstMinTargetHP", label = { en = "Burst minimum target health", fr = "Vie cible minimum pour Burst", pt = "Vida mínima do alvo para Burst", es = "Salud mínima del objetivo para Burst", de = "Min. Zielgesundheit für Burst", zh = "Burst 最低目标生命值" }, min = 0, max = 100, step = 5, default = 40, suffix = " % HP" },
        } },
	},
}, "0.31.0")

-- Selecting Smite returns the profile to Leveling Rotation.
local BuildPriestUI = AL.classUIs and AL.classUIs.PRIEST
if BuildPriestUI then
	AL.classUIs.PRIEST = function(page, ui)
		local priestUI = {}
		for key, value in pairs(ui) do priestUI[key] = value end
        priestUI.StackDropdown = function(host, options)
            local entries=options.options
            if entries and entries[1] and entries[1].value=="SHADOW" and entries[2] and entries[2].value=="SMITE" then
                local priorSet=options.set
                options.set=function(value)
                    priorSet(value)
                    if value=="SMITE" then ui.Profile().shadow=false end
                end
            end
            return ui.StackDropdown(host, options)
        end
		return BuildPriestUI(page, priestUI)
	end
end
