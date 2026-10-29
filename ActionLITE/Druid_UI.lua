local ADDON, AL = ...

local function BuildCheck(key,label,spell)
	return {key=key,label=label,spell=spell,half=false,onChange=function()
		local settings=AL.ES and AL.ES()or(AL.S and AL.S())
		local rotation=AL.rotations and AL.rotations.DRUID
        if settings and rotation and rotation.SelectBuild then
            -- The shared checkbox has already written its new value.
            rotation.SelectBuild(key,settings[key]==true,settings,settings[key]~=true)
        elseif settings and settings[key] then
            for _,other in ipairs({"balance","feralCat","feralBear"})do if other~=key then settings[other]=false end end
        end
		if AL.UI and AL.UI.Repaint then AL.UI.Repaint()end
	end}
end

AL.RegisterSimpleClassUI("DRUID", {
	title = { en = "DRUID - DPS & TANK", fr = "DRUIDE - PROGRESSION DPS", pt = "DRUIDA - EVOLUÇÃO DPS", es = "DRUIDA - SUBIDA DPS", de = "DRUIDE - DPS LEVELN", zh = "德鲁伊 - 输出升级" },
	subtitle = { en = "Adapts to caster, Bear and Cat forms", fr = "S'adapte aux formes lanceur, Ours et Felin", pt = "Adapta-se às formas conjurador, Urso e Felino", es = "Se adapta a las formas lanzador, Oso y Felino", de = "Passt sich an Zauber-, Bären- und Katzengestalt an", zh = "适应施法者、熊和猎豹形态" },
	aoeKey = "aoe",
	cards = {
        {
            title = "LEVELING ROTATION",
            id="leveling-rotation", build="leveling", group="damage",
            controls = {
                { key="leveling", label="Leveling Rotation", spell="Wrath", half=false,
                  tooltip={"Leveling Rotation", "Uses the finalized class rotation from before the level-60 sim builds, with its original priorities and existing settings. Select a DPS or Tank build to switch rotations. Turning the active build off automatically selects Leveling Rotation. One rotation always stays selected."} },
            },
        },
		{
			title = "HEALING ENGINE",
			id = "healing-engine", group = "survival",
			controls = {
				{ key = "healingEngine", label = "Enable HealingEngine", spell = "Healing Touch", half = false,
				  tooltip = { "Enable HealingEngine", "Allows a Druid healing rotation to select friendly party or raid members through the protected Action target pixel. Existing self-healing and damage priorities remain available." } },
				{ type = "slider", key = "healingInitiateHP", label = "Initiate healing at HP", min = 5, max = 100, step = 5, default = 80, suffix = " %" },
				{ type = "slider", key = "healingEmergencyHP", label = "Emergency healing", min = 5, max = 100, step = 5, default = 30, suffix = " %" },
				{ type = "info", text = "The first threshold is reserved for HoTs and efficient heals. The emergency threshold is reserved for the largest heals and defensive cooldowns. Party selection stays disabled while HealingEngine is unchecked." },
			},
		},
        {
            title = "TANK BUILD - FERAL BEAR 0/41/10",
            id="tank-build-feral-bear-0-41-10", build="feralBear", group="damage",
            controls = {
                BuildCheck("feralBear", "Tank - Feral Bear (0/41/10)", "Dire Bear Form"),
                { type="info", text="Selects learned Bear tank priorities through level 60 and unchecks Cat/Balance. Turning Tank off automatically selects Leveling Rotation. Talents, gear and saved icons are not changed. Select Leveling Rotation for the previous form-based profile." },
                { key="bearAutoForm",label="Maintain learned Bear Form",spell="Dire Bear Form",half=false,
                    tooltip={"Tank form","Uses Dire Bear Form when actually learned, otherwise Bear Form. Preserves travel forms and finishes casts/channels. The Tank build does not shift out to cast a heal during combat."} },
                { key="bearPrimalBite",label="Use Primal Bite",spell="Primal Bite" },
                { key="bearLacerate",label="Maintain Lacerate",spell="Lacerate" },
                { type="slider",key="bearLacerateStacks",label="Tank Lacerate stacks",min=1,max=5,step=1,default=5 },
                { key="bearLacerateFiller",label="Use Lacerate as damage filler",spell="Lacerate",half=false },
                { key="bearFaerieFire",label="Tank: maintain Faerie Fire",spell="Faerie Fire" },
                { key="bearDemoRoar",label="Tank: maintain Demoralizing Roar",spell="Demoralizing Roar" },
                { type="info",text="Primal Bite is Forever's renamed Mangle-style Bear attack. Use its learned rank, maintain own Lacerate stacks and refresh an expiring bleed, then queue Maul at the chosen Rage threshold. Optional Lacerate filler can repeat between primary cooldowns. Faerie Fire uses the mana pool while in Bear; Rage is never treated as mana." },
                { key="bearMaul",label="Use queued Maul",spell="Maul" },
                { type="slider",key="bearMaulRage",label="Tank Maul minimum Rage",min=0,max=100,step=5,default=25 },
                { type="info",text="Maul uses the exact selected Rage threshold and its actual spell cost. It is not repeatedly queued while already active. Learned attacks continue between queued swings. The existing Bash, Enrage and preparation/healing checkboxes below also apply to Tank." },
            },
        },
        {
            title = "BEAR DEFENSES & THREAT",
            id="bear-defenses-threat", build="feralBear", group="survival",
            controls = {
                { key="bearBarkskin",label="Use Barkskin",spell="Barkskin" },
                { type="slider",key="bearBarkskinHP",label="Barkskin at or below health",min=0,max=100,step=5,default=45,suffix=" %" },
                { key="bearFrenzied",label="Use Frenzied Regeneration",spell="Frenzied Regeneration" },
                { type="slider",key="bearFrenziedHP",label="Frenzied Regeneration at or below health",min=0,max=100,step=5,default=35,suffix=" %" },
                { type="slider",key="bearFrenziedRage",label="Frenzied Regeneration minimum Rage",min=0,max=100,step=5,default=10 },
                { type="info",text="Defenses work independently of Burst. Frenzied Regeneration stays in Bear Form and converts Rage into healing. While it is active and health is at or below its slider, normal Rage spending pauses so the heal has resources; interrupts and threat recovery retain priority. Protected combat health and Rage use the same selected thresholds." },
                { type="slider",key="bearEnrageBelowRage",label="Tank Enrage below Rage",min=0,max=100,step=5,default=20 },
                { type="slider",key="bearEnrageMinHP",label="Tank Enrage minimum health",min=0,max=100,step=5,default=75,suffix=" %" },
                { type="info",text="The existing Enrage checkbox enables tank Rage generation only below the Rage slider and at or above the health slider. It does not bypass low health or a protected threshold. Tank Demoralizing Roar has its own checkbox above." },
                { key="bearGrowl",label="Growl to recover ally aggro",spell="Growl" },
                { key="bearCharge",label="Use learned Feral Charge",spell="Feral Charge" },
                { key="bearChallengingRoar",label="Use Challenging Roar in AoE",spell="Challenging Roar",half=false },
                { type="info",text="Growl requires a confirmed friendly target victim other than the player. Feral Charge requires positively verified spell range and its cost. Challenging Roar requires AoE On, the area enemy threshold and at least three distinct nearby engaged enemies confirmed to be attacking allies. Some enemies cannot be taunted or stunned." },
            },
        },
        {
            title = "BEAR AREA DAMAGE",
            id="bear-area-damage-burst", build="feralBear", group="aoe",
            controls = {
                { key="bearSwipe",label="Tank AoE: use Swipe",spell="Swipe" },
                { type="slider",key="bearAoeMinEnemies",label="Tank AoE minimum enemies",min=2,max=5,step=1,default=3 },
                { type="info",text="Uses the shared AoE mode checkbox or spell-icon AoE button. Swipe requires AoE On, enough confirmed engaged enemies in melee and its actual Rage cost. Unknown or distant enemies do not enable tank area damage." },
            },
        },
        {
            title="BEAR BURST", id="bear-burst", build="feralBear", group="burst",
            controls={
                { key="bearBerserk",label="Burst + AoE: use Berserk",spell="Berserk" },
                { key="bearElunesLight",label="Tank Burst: learned Elune's Light",spell="Elune's Light" },
                { key="bearBerserking",label="Tank Burst: learned Berserking",spell="Berserking" },
                { type="slider",key="bearBurstMinTargetHP",label="Tank Burst minimum target health",min=0,max=100,step=5,default=35,suffix=" %" },
                { type="info",text="Offensive cooldowns require Burst On, their checkbox, combat, Bear Form and a melee target. Zero removes the target-health limit. Berserk makes Primal Bite hit up to three enemies, so Berserk and empowered Primal Bite also require AoE On and the confirmed enemy threshold. Turning AoE off during Berserk uses single-target Lacerate/Maul until the buff ends. Only actually learned racials are used; the reference Night Elf has Elune's Light." },
                { type="info",text="New Spells-tab entries support Universal icons 1-10: Primal Bite, Lacerate, Barkskin, Frenzied Regeneration, Feral Charge and Challenging Roar. Note: Use a Universal icon for Demoralizing Roar." },
            },
        },

		{
			title = "BALANCE BUILD - 41/0/10",
			id="balance-build-41-0-10", build="balance", group="damage",
			controls = {
				BuildCheck("balance", "Use Balance (41/0/10)", "Moonkin Form"),
				{ type = "info", text = "Uses learned Balance spells through level 60. Selecting Balance unchecks Feral Cat and Tank while keeping their saved settings and icons. Talents and equipment are not changed. Select Leveling Rotation for the previous form-based leveling rotation." },
				{ key = "balanceMoonkin", label = "Maintain learned Moonkin Form", spell = "Moonkin Form", half = false },
				{ key = "balanceInsectSwarm", label = "Maintain Insect Swarm", spell = "Insect Swarm" },
				{ key = "balanceMoonfire", label = "Maintain Moonfire", spell = "Moonfire" },
				{ key = "balanceStarfire", label = "Use Starfire", spell = "Starfire" },
				{ key = "balanceWrath", label = "Use Wrath", spell = "Wrath" },
				{ type = "info", text = "Opens with stationary Starfire when learned. Maintains own Insect Swarm and Moonfire, then builds Eclipse with Wrath and spends its charges on Starfire. Uses confirmed auras or successful Wrath casts with a known Eclipse talent. Unavailable procs fall back to regular damage; moving allows missing instant DoTs. Casts and channels finish." },
				{ type = "slider", key = "balanceMinMana", label = "Balance damage minimum mana", min = 0, max = 100, step = 5, default = 0, suffix = " %" },
				{ type = "slider", key = "balanceDotMinTargetHP", label = "Balance DoT minimum target health", min = 0, max = 100, step = 5, default = 0, suffix = " %" },
				{ type = "info", text = "Actual learned spell costs still apply at zero. A confirmed target lifetime of ten seconds or less skips a new Insect Swarm; six seconds or less skips a new Moonfire. No target lifetime is assumed when it is unavailable. Starfire, Insect Swarm and Moonkin Form support Universal icons in the existing Spells tab." },
			},
		},
		{
			title = "BALANCE MANA",
			id="balance-mana-burst-area-damage", build="balance", group="resources",
			controls = {
				{ key = "balanceInnervate", label = "Balance: Innervate on self", spell = "Innervate", half = false },
				{ type = "slider", key = "balanceInnervateMana", label = "Balance Innervate at or below mana", min = 0, max = 100, step = 5, default = 10, suffix = " %" },
				{ type = "info", text = "Mana recovery requires combat, low mana, its learned spell and no active Innervate. A confirmed target lifetime of twenty seconds or less skips it. Innervate works in Moonkin Form and does not require Burst On." },
            },
        },
        {
            title="BALANCE BURST", id="balance-burst", build="balance", group="burst",
            controls={
				{ key = "balanceElunesLight", label = "Burst: learned Elune's Light", spell = "Elune's Light" },
				{ key = "balanceBerserking", label = "Burst: learned Berserking", spell = "Berserking" },
				{ type = "slider", key = "balanceBurstMinMana", label = "Balance Burst minimum mana", min = 0, max = 100, step = 5, default = 20, suffix = " %" },
				{ type = "slider", key = "balanceBurstMinTargetHP", label = "Balance Burst minimum target health", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "info", text = "Offensive racials require Burst On, combat, their checkbox and an eligible affordable damage spell. Only learned racial abilities are used. The Night Elf reference uses Elune's Light; no Balance damage cooldown is assumed from the build checkbox." },
            },
        },
        {
            title="BALANCE AREA DAMAGE", id="balance-area-damage", build="balance", group="aoe",
            controls={
				{ key = "balanceHurricane", label = "Balance: use Hurricane in AoE", spell = "Hurricane", half = false },
				{ type = "slider", key = "balanceAoeMinEnemies", label = "Balance Hurricane minimum enemies", min = 2, max = 5, step = 1, default = 3 },
				{ type = "slider", key = "balanceAoeMinMana", label = "Balance Hurricane minimum mana", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "info", text = "Hurricane requires AoE On, standing still, enough confirmed engaged enemies and both damage/AoE mana settings. At four or more enemies it can take priority over new DoTs; smaller eligible packs maintain DoTs first. Complete normal ground targeting; the full channel is preserved. Burst On is independent." },
			},
		},
		{
			title = "FERAL CAT BUILD - 9/34/8",
			id="feral-cat-build-9-34-8", build="feralCat", group="damage",
			controls = {
				BuildCheck("feralCat", "Use Feral Cat (9/34/8)", "Cat Form"),
				{ type = "info", text = "Selects learned Feral Cat priorities through level 60 using the live MythicSim 9/34/8 reference. Selecting Cat unchecks Balance and Tank while keeping their saved settings. Select Leveling Rotation for the previous form-based profile. Talents and gear are not changed." },
				{ key = "catFaerieFire", label = "Maintain Faerie Fire", spell = "Faerie Fire" },
				{ key = "catBite", label = "Use Ferocious Bite", spell = "Ferocious Bite" },
				{ key = "catShiftingPower", label = "Use Shifting Power", spell = "Shifting Power", half = false },
				{ type = "slider", key = "catShiftBelowEnergy", label = "Shifting Power below energy", min = 0, max = 100, step = 5, default = 40 },
				{ type = "info", text = "Shifting Power spends mana to restore energy without leaving Cat Form. Uses the energy slider, actual mana cost and enough energy headroom. Once learned it replaces Tiger's Fury. The default build has Improved Shifting Power; readable cooldowns and learned talent ranks take priority." },
				{ key = "catShred", label = "Use Shred from behind (optional)", spell = "Shred", half = false,
					tooltip = { "Rear-position damage", "Default OFF for solo play. Enable when you can stay behind the target, as the simulator assumes. A failed rear-position attempt falls back to Claw for this target. Target changes allow a new attempt." } },
				{ key = "catProwl", label = "Use Prowl before combat", spell = "Prowl" },
				{ key = "catRavage", label = "Use learned Ravage opener", spell = "Ravage" },
				{ type = "info", text = "With Feral Cat selected, the shared Rake and Rip checkboxes below still apply. Maintain Rake, use Rip at five points on durable targets, then Bite at five points when Rip has more than five seconds left. Short confirmed lifetimes use Bite. Zero points always uses a builder. Ordinary hidden critical hits are not guessed." },
			},
		},
		{
			title = "FERAL CAT RESOURCES",
			id="feral-cat-resources-burst", build="feralCat", group="resources",
			controls = {
				{ key = "catInnervate", label = "Use Innervate on self", spell = "Innervate", half = false },
				{ type = "slider", key = "catInnervateMana", label = "Innervate at or below mana", min = 0, max = 100, step = 5, default = 10, suffix = " %" },
				{ type = "info", text = "Innervate is mana recovery, requires combat, low mana and at most 30 energy, and may leave Cat Form. A readable lifetime under 20 seconds skips it. The profile returns to Cat when ready." },
            },
        },
        {
            title="FERAL CAT BURST", id="feral-cat-burst", build="feralCat", group="burst",
            controls={
				{ key = "catBerserk", label = "Use Berserk", spell = "Berserk" },
				{ key = "catElunesLight", label = "Use Elune's Light", spell = "Elune's Light" },
				{ type = "slider", key = "catBurstMinTargetHP", label = "Cat Burst minimum target health", min = 0, max = 100, step = 5, default = 35, suffix = " %" },
				{ type = "slider", key = "catBurstMinEnergy", label = "Cat Burst minimum energy", min = 0, max = 100, step = 5, default = 30 },
				{ type = "info", text = "Berserk and the learned Night Elf racial require Burst On, combat, Cat Form and melee range. Elune's Light waits until Berserk ends to avoid wasting its critical chance bonus. Neither spell is assumed learned from this checkbox." },
			},
		},
		{
			title = "FERAL CAT AREA DAMAGE",
			id="feral-cat-area-damage", build="feralCat", group="aoe",
			controls = {
				{ key = "catHurricane", label = "Use Hurricane (shift out, optional)", spell = "Hurricane", half = false },
				{ type = "slider", key = "catAoeMinEnemies", label = "Cat AoE minimum enemies", min = 2, max = 5, step = 1, default = 3 },
				{ type = "slider", key = "catAoeMinMana", label = "Hurricane minimum mana", min = 0, max = 100, step = 5, default = 50, suffix = " %" },
				{ type = "info", text = "Requires AoE On using the shared mode control or spell-icon button. Swipe is Bear-only in Forever. Optional Hurricane defaults OFF, requires standing still and confirmed engaged enemies, leaves Cat Form and keeps mana for the return to Cat. Complete the ground targeting normally; channels are allowed to finish. With it OFF, Cat keeps its single-target priorities." },
			},
		},
		{
			title = { en = "PREPARATION & SURVIVAL", fr = "PREPARATION ET SURVIE", pt = "PREPARAÇÃO E SOBREVIVÊNCIA", es = "PREPARACIÓN Y SUPERVIVENCIA", de = "VORBEREITUNG & ÜBERLEBEN", zh = "准备与生存" },
			id="preparation-survival", group="preparation",
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
			id="cat-form", build={"feralCat","leveling"}, group="damage",
			controls = {
				{ key = "rake", label = "Rake", spell = "Rake" },
				{ key = "rip", label = { en = "Rip on durable targets", fr = "Rip sur les cibles durables", pt = "Rip em alvos resistentes", es = "Rip en objetivos duraderos", de = "Rip auf zähe Ziele", zh = "对耐久目标Rip" }, spell = "Rip" },
				{ key = "tigersfury", label = "Tiger's Fury", spell = "Tiger's Fury" },
				{ type = "info", text = { en = "With Leveling Rotation selected: Rake above 40% target HP. Rip at 4+ combo points above 60%. Ferocious Bite at 5 points, or 3+ points at or below 40%. Claw builds points; Shred is an optional Prowl opener. These checkboxes also enable the corresponding spells in the selected Feral Cat build." } },
			},
		},
		{
			title = { en = "BEAR FORM", fr = "FORME D'OURS", pt = "FORMA DE URSO", es = "FORMA DE OSO", de = "BÄRENGESTALT", zh = "熊形态" },
			id="bear-form", build={"feralBear","leveling"}, group="damage",
			controls = {
				{ key = "enrage", label = { en = "Enrage and Demoralizing Roar", fr = "Enrage et Demoralizing Roar", pt = "Enrage e Demoralizing Roar", es = "Enrage y Demoralizing Roar", de = "Enrage und Demoralizing Roar", zh = "Enrage和Demoralizing Roar" }, spell = "Enrage" },
				{ key = "bash", label = { en = "Bash interrupt", fr = "Interruption Bash", pt = "Interrupção Bash", es = "Interrupción Bash", de = "Bash-Unterbrechung", zh = "Bash打断" }, spell = "Bash" },
            },
        },
        {
            title="AREA DAMAGE MODE", id="area-damage-mode", group="aoe",
            controls={
				{ key = "aoe", label = { en = "Enable AoE Mode", fr = "Activer le mode AoE", pt = "Ativar modo AoE", es = "Activar modo AoE", de = "AoE-Modus aktivieren", zh = "启用AoE模式" }, spell = "Swipe" },
				{ type = "info", text = { en = "The shared AoE mode also enables the selected Cat or Balance build's area-damage rules. In the older form-based profile, Swipe requires at least two confirmed enemies in melee range. Bear attacks wait for enough rage; Bash takes priority when a target is casting." } },
			},
		},
	},
}, "0.13.0")


-- Keep new Bear slider getters on the same bounded settings as the rotation,
-- while preserving the existing declarative class-page layout.
local originalBuilder=AL.classUIs and AL.classUIs.DRUID
if originalBuilder and AL.RegisterClassUI then
    AL.RegisterClassUI("DRUID",function(page,ui)
        local rotation=AL.rotations and AL.rotations.DRUID
        local adapter=setmetatable({}, {__index=ui})
        adapter.Slider=function(host,opts)
            local key=opts.profileKey
            if type(key)=="string"and key:find("^bear")and rotation and rotation.BearSetting then
                local safe={};for name,value in pairs(opts)do safe[name]=value end
                safe.get=function()return rotation.BearSetting(ui.Profile(),key)end
                return ui.Slider(host,safe)
            end
            return ui.Slider(host,opts)
        end
        return originalBuilder(page,adapter)
    end,"0.13.0")
end
