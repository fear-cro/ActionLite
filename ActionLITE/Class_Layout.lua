local ADDON, AL = ...

-- Shared presentation only. Existing class callbacks continue to own settings
-- and build selection; this adapter never changes combat priorities.
local Layout = {}
AL.ClassLayout = Layout

local LABELS = {
    WARRIOR = { arms = "Arms 39/10/2", fury = "Fury 18/31/2", protection = "Protection 0/20/31" },
    PALADIN = { shockadin = "Shockadin 23/0/28", retribution = "Retribution 10/8/33", protection = "Protection 8/33/10" },
    HUNTER = { beastMastery = "Beast Mastery 31/20/0", marksmanship = "Marksmanship 5/31/15", survival = "Survival 5/11/35" },
    ROGUE = { combat = "Combat 17/32/2", subtlety = "Subtlety 12/8/31", assassination = "Assassination 38/11/2" },
    PRIEST = { shadow = "Shadow 18/0/33" },
    SHAMAN = { enhancement = "Enhancement 18/33/0", elemental = "Elemental 31/7/13" },
    MAGE = { arcane = "Arcane 35/11/5", frostfire = "Frostfire 0/29/22", fire = "Fire 16/31/4", frost = "Frost 16/3/32" },
    WARLOCK = { demonology = "Demonology 2/31/18", affliction = "Affliction 33/0/18", destruction = "Destruction 11/11/29" },
    DRUID = { feralCat = "Feral Cat 9/34/8", balance = "Balance 41/0/10", feralBear = "Feral Bear Tank 0/41/10" },
}

local ORDER = { status = 1, preparation = 2, damage = 3, resources = 4,
    survival = 5, aoe = 6, burst = 7, advanced = 8 }

-- A few shared cards contain settings that belong to one particular build.
-- Hiding a control leaves its saved value intact.
local SCOPES = {
    WARRIOR = {
        slamReserveRage = { "leveling", "arms", "fury" },
        heroicDumpRage = { "leveling", "arms", "fury" },
        cleaveDumpRage = { "leveling", "arms", "fury" },
        sweepingReserveRage = { "leveling", "arms", "fury" },
    },
    WARLOCK = { demoImpSacrifice = "demonology", soulLink = "demonology" },
    PALADIN = {
        swiftJudgement = "protection",
        tankRighteousFury = function(p) return p.protection == true or p.paladinRole == "TANK" end,
        tankConsecrationMinMana = function(p) return p.protection == true or p.paladinRole == "TANK" end,
        consecrationMinMana = function(p) return p.protection ~= true and p.paladinRole ~= "TANK" end,
        sealTwisting = "retribution", sealTwistMinMana = "retribution",
        holyShock = "shockadin", holyShockMinMana = "shockadin", divineFavor = "shockadin",
        hammerOfWrath = { "shockadin", "retribution", "protection" },
        hammerOfWrathMinMana = { "shockadin", "retribution", "protection" },
        hammerOfTheRighteous = { "retribution", "protection" },
        hammerOfTheRighteousMinMana = { "retribution", "protection" },
        holyWrath = { "retribution", "protection" }, holyWrathMinMana = { "retribution", "protection" },
    },
    SHAMAN = {
        shamanRole = "leveling", enhancementMaelstrom = "enhancement",
        enhancementRage = "enhancement", enhancementRacials = "enhancement",
        enhancementAirTotem = "enhancement", enhancementChainLightning = "enhancement",
        elementalChainLightning = "elemental", elementalChainClearcasting = "elemental",
        elementalChainMana = "elemental",
    },
    PRIEST = { priestRole = "leveling", holyFire = "leveling" },
    ROGUE = {
        rupture = { "leveling", "combat", "assassination" },
        ruptureMinCP = { "leveling", "combat", "assassination" },
    },
}

local function Copy(source)
    local target = {}
    for key, value in pairs(source or {}) do target[key] = value end
    return target
end

local function Applies(rule, profile)
    if rule == nil then return true end
    if type(rule) == "function" then return rule(profile) == true end
    if type(rule) == "string" then return profile[rule] == true end
    for _, key in ipairs(rule) do if profile[key] == true then return true end end
    return false
end

function Layout.Wrap(token, page, base)
    local ui = Copy(base)
    local rotation = AL.rotations[token]
    local buildKeys, records, byCard = {}, {}, {}
    for _, key in ipairs(rotation.buildKeys or {}) do buildKeys[key] = true end
    local root, buildCard

    ui.State = function()
        -- A live getter can read the player's resources and, for Warrior,
        -- initialize the edited profile. Call it only for this character's
        -- visible class page; other profiles contain settings, not live data.
        local edited = ActionLiteDB and ActionLiteDB.activeProfile or AL.playerClass
        if token ~= AL.playerClass or token ~= edited then return {} end
        if type(rotation.GetUIState) == "function" then return rotation.GetUIState() or {} end
        return {}
    end

    ui.Body = function(panel, opts)
        local stack, scroll = base.Body(panel, opts)
        root = stack
        buildCard = base.Card(stack, "ROTATION")
        base.Tooltip(buildCard, "Rotation selection", {
            "Choose one rotation. Turning a talent build off returns to Leveling Rotation.",
            "Selecting a build changes priorities; your talents, equipment and other saved options are retained.",
        })
        return stack, scroll
    end

    ui.Card = function(host, title, subtitle, opts)
        opts = Copy(opts)
        local index = #records + 1
        opts.collapsible = true
        opts.collapseKey = token .. ":" .. (opts.id or tostring(index))
        if opts.collapsed == nil then opts.collapsed = opts.status == true or opts.group == "advanced" end
        local card = base.Card(host, title, nil, opts)
        local record = { card = card, controls = {}, help = {}, order = ORDER[opts.group] or 3,
            build = opts.build, status = opts.status, levelingTank = opts.levelingTank, index = index }
        records[index], byCard[card] = record, record
        if subtitle and subtitle ~= "" then record.help[#record.help + 1] = subtitle end
        return card
    end

    ui.Help = function(card, text)
        local record = byCard[card]
        if record and text and text ~= "" then record.help[#record.help + 1] = text end
    end

    local function Capture(card, item, key)
        local record = byCard[card]
        if record then
            record.controls[#record.controls + 1] = { item = item, scope = SCOPES[token] and SCOPES[token][key] }
        end
        return item
    end

    local function BuildOptions(key, opts)
        opts = Copy(opts)
        opts.label = key == "leveling" and "Leveling Rotation" or (LABELS[token] or {})[key] or opts.label
        opts.half = true
        return opts
    end

    local function FitOptions(opts)
        local copy = Copy(opts)
        if type(copy.label) == "string" and #copy.label > 34 then copy.half = false end
        return copy
    end

    ui.SettingCheck = function(card, key, opts)
        if buildKeys[key] then
            local item = base.SettingCheck(buildCard, key, BuildOptions(key, opts))
            item.alBuildKey = key
            return item
        end
        return Capture(card, base.SettingCheck(card, key, FitOptions(opts)), key)
    end
    ui.Check = function(card, opts)
        local key = opts.profileKey
        if key and buildKeys[key] then
            local item = base.Check(buildCard, BuildOptions(key, opts))
            item.alBuildKey = key
            return item
        end
        return Capture(card, base.Check(card, FitOptions(opts)), key)
    end
    ui.Slider = function(card, opts)
        return Capture(card, base.Slider(card, FitOptions(opts)), opts.profileKey)
    end
    ui.StackDropdown = function(card, opts)
        return Capture(card, base.StackDropdown(card, opts), opts.profileKey)
    end
    ui.Info = function(card, ...)
        return Capture(card, base.Info(card, ...))
    end
    ui.BadgeRow = function(card, ...)
        return Capture(card, base.BadgeRow(card, ...))
    end

    local function Refresh()
        local profile = ui.Profile()
        for _, record in ipairs(records) do
            local card, any, changed = record.card, false, false
            for _, control in ipairs(record.controls) do
                local visible = Applies(control.scope, profile)
                local item = control.item
                if item.alSkip ~= not visible then changed = true; item.alSkip = not visible end
                item:SetShown(visible and not card.collapsed)
                if visible then any = true end
            end
            if changed then card.stack:Reflow() end
            local visible = any and Applies(record.build, profile)
                and (not record.status or token == AL.playerClass)
            if visible and record.levelingTank and profile.leveling == true then
                local state = ui.State()
                visible = profile.warriorRole == "TANK" or state.role == "TANK"
            end
            if card.alSkip ~= not visible then
                card.alSkip = not visible
                card:SetShown(visible)
                root:Reflow()
            end
        end
    end

    function ui.FinishLayout()
        for _, record in ipairs(records) do
            if #record.help > 0 and #record.controls > 0 then
                local help = base.Button(record.card, { label = "?", width = 18, height = 18 })
                help:SetPoint("TOPRIGHT", -6, -7)
                base.Tooltip(help, record.card.title:GetText(), record.help)
            end
        end
        local priorities = { [buildCard] = 0 }
        for _, record in ipairs(records) do priorities[record.card] = record.order * 100 + record.index end
        table.sort(root.items, function(a, b) return (priorities[a] or 9999) < (priorities[b] or 9999) end)
        root:Reflow()
        base.Paint(Refresh)
        Refresh()
        -- Useful to the integrated state recorder and automated UI validation.
        page.classLayout = { token = token, records = records, buildCard = buildCard, root = root, Refresh = Refresh }
    end

    return ui
end
