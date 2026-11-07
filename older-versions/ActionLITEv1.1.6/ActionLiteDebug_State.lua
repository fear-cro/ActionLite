local _, AL = ...
local ns = AL.ActionLiteDebug
local P = ns.Probe
local State = {}
ns.State = State
local controls = setmetatable({}, { __mode = "k" })
local controlCount = 0

function ns.ClearControls()
    controls = setmetatable({}, { __mode = "k" })
    controlCount = 0
end

local function Raw(object, key)
    if not P.TableAccess(object) then return nil end
    local ok, value = pcall(rawget, object, key)
    if ok and P.Public(value) then return value end
end

local function Getter(fn, ...)
    if type(fn) ~= "function" then return { status = "Missing" } end
    local ok, value = pcall(fn, ...)
    if not ok then return { status = "Call failed", detail = P.Copy(value) } end
    local accessible, reason = P.Public(value)
    return { status = "Observed", visibility = accessible and "Public" or reason, value = P.Copy(value) }
end

local function Functions(object)
    local out = {}
    if P.TableAccess(object) then
        for name, value in pairs(object) do
            if P.Public(name) and type(name) == "string" and P.Public(value) and type(value) == "function" then
                out[#out + 1] = name
            end
        end
    end
    table.sort(out)
    return out
end

local function EffectiveProfile(token, stored)
    local result = {}
    for _, source in ipairs({ AL.defaults or {}, Raw(AL.rotations, token) and AL.rotations[token].defaults or {}, stored or {} }) do
        local copy = P.Copy(source)
        if type(copy) == "table" then for key, value in pairs(copy) do result[key] = value end end
    end
    -- Spell checkboxes default ON unless explicitly disabled. Make the
    -- effective state explicit even for boxes never touched by the user.
    if result.spells == nil then result.spells = {} end
    local module = Raw(AL.rotations, token)
    if type(result.spells) == "table" then
        for _, entry in ipairs(module and module.spells or {}) do
            if result.spells[entry[2]] == nil then result.spells[entry[2]] = true end
        end
    end
    return result
end

function State.Configuration()
    local db = type(ActionLiteDB) == "table" and ActionLiteDB or {}
    local global = {}
    if P.TableAccess(db) then
        for key, value in pairs(db) do
            if P.Public(key) and type(key) == "string" and key ~= "profiles" then global[key] = P.Copy(value) end
        end
    end
    local result = { globals = global, profiles = {}, playerClass = AL.playerClass,
        editedClass = Raw(db, "activeProfile"), language = P.Copy(ActionLiteLanguage),
        globalDefaults = P.Copy(AL.dbDefaults), coreDefaults = P.Copy(AL.defaults),
        universalIcons = P.Copy(AL.UNIVERSAL_ICONS), universalChoices = P.Copy(AL.UNIVERSAL_CHOICES) }
    local profiles = Raw(db, "profiles")
    local mirror = Raw(profiles, "__ACTIONLITE_UI")
    result.uiMirror = { theme = P.Copy(Raw(mirror,"theme")), glowColor = P.Copy(Raw(mirror,"glowColor")) }
    for _, token in ipairs(AL.CLASS_TOKENS or {}) do
        local stored = Raw(profiles, token)
        local module = Raw(AL.rotations, token)
        result.profiles[token] = { configured = type(stored) == "table",
            stored = P.Copy(stored), effective = EffectiveProfile(token, stored),
            defaults = P.Copy(module and module.defaults), uiVersion = Raw(AL.classUIVersions, token),
            functions = Functions(module) }
    end
    return result
end

function ns.RegisterControl(widget, opts, kind)
    if controlCount >= 1600 then return end
    controlCount = controlCount + 1
    controls[widget] = { label = opts.label or opts.caption, key = opts.profileKey,
        kind = kind, class = ns.controlContext or "GLOBAL", scope = opts.debugScope,
        min = opts.min, max = opts.max, step = opts.step, get = opts.get }
end

function State.Controls()
    local result = {}
    local edited = ActionLiteDB and ActionLiteDB.activeProfile or AL.playerClass
    local profiles = ActionLiteDB and ActionLiteDB.profiles or {}
    for widget, control in pairs(controls) do
        local row = { label = P.Copy(control.label), key = control.key, kind = control.kind,
            class = control.class, scope = control.scope, min = control.min, max = control.max, step = control.step }
        if control.class == "GLOBAL" or control.class == edited then
            row.current = Getter(control.get)
        elseif control.key then
            row.current = { status = "Stored profile", value = P.Copy(Raw(Raw(profiles, control.class), control.key)) }
        else row.current = { status = "See class profile; getter belongs to edited class" } end
        row.shown = Getter(widget.IsShown, widget)
        result[#result + 1] = row
    end
    table.sort(result, function(a,b)
        return (a.class .. ":" .. tostring(a.label) .. ":" .. tostring(a.key)) < (b.class .. ":" .. tostring(b.label) .. ":" .. tostring(b.key))
    end)
    return result
end

function ns.ControlChanged(widget)
    if ns.Scanner.state ~= "Recording" then return end
    local control = controls[widget]
    if control then
        ns.Scanner.AddEvent("UI control changed", { label = P.Copy(control.label), key = control.key,
            kind = control.kind, class = control.class, current = Getter(control.get) })
    end
    -- Slider drags can fire every frame. Their precise values stay in the
    -- timeline; the timer and Finish snapshot capture the full configuration.
    if not control or control.kind ~= "slider" then ns.Scanner.CaptureConfiguration("UI control changed") end
end

function ns.RecordUI(name, detail)
    if ns.Scanner.state ~= "Recording" then return end
    ns.Scanner.AddEvent(name, detail)
    ns.Scanner.CaptureConfiguration(name)
end

local function FrameName(frame)
    if not P.Public(frame) then return "<Hidden frame reference>" end
    if not frame then return "none" end
    local ok, name = pcall(function() return frame:GetName() end)
    if ok and P.Public(name) and type(name) == "string" then return name end
    return "unnamed"
end

function State.Frame(frame, depth)
    if not frame then return { status = "Not created" } end
    depth = depth or 0
    local result = { name = FrameName(frame), methods = {} }
    local passed, fields = pcall(function() return { on = P.Copy(frame.on), compact = P.Copy(frame.compact) } end)
    if passed then result.control = fields end
    for _, name in ipairs({ "IsShown", "IsVisible", "IsMouseEnabled", "IsMovable", "GetAlpha", "GetEffectiveAlpha",
        "GetScale", "GetEffectiveScale", "GetWidth", "GetHeight", "GetFrameStrata", "GetFrameLevel",
        "GetLeft", "GetRight", "GetTop", "GetBottom", "GetTexture", "GetText" }) do
        local ok, fn = pcall(function() return frame[name] end)
        if ok and type(fn) == "function" then result.methods[name] = Getter(fn, frame) end
    end
    local ok, point, relative, relativePoint, x, y = pcall(function() return frame:GetPoint(1) end)
    if ok then result.anchor = { point = P.Copy(point), relative = FrameName(relative),
        relativePoint = P.Copy(relativePoint), x = P.Copy(x), y = P.Copy(y) } end
    -- Read a bounded portion of the rendered icon tree, including protected
    -- alpha masks, without doing arithmetic or comparisons on their values.
    if depth < 2 then
        result.children, result.regions = {}, {}
        for _, item in ipairs({ {"GetChildren", result.children, 16}, {"GetRegions", result.regions, 12} }) do
            local passed, packed = pcall(function() return { frame[item[1]](frame) } end)
            if passed then
                for index = 1, math.min(#packed, item[3]) do
                    if P.Public(packed[index]) then item[2][index] = State.Frame(packed[index], depth + 1) end
                end
                if #packed > item[3] then result.truncated = true end
            end
        end
    end
    return result
end

function State.Runtime(detail)
    local token = AL.playerClass
    local module = token and Raw(AL.rotations, token)
    local result = { lastSuggestion = P.Copy(AL.lastSuggestion), burst = P.Copy(AL.burst),
        queue = P.Copy(AL.queue), known = P.Copy(AL.known), unlearned = P.Copy(AL.unlearned),
        rangeSpellRefs = P.Copy(AL.rangeSpellRefs), futureSpells = P.Copy(AL.futureSpells),
        core = Getter(AL.DebugState), manaSources = Getter(AL.ManaDebugSources),
        rotation = {}, visualPlan = P.Copy(AL.rotationSecretVisual),
        resourceDisplay = Getter(AL.ResourceDebugState), buildId = AL.buildId,
		healingEngine = Getter(AL.HealingEngine and AL.HealingEngine.DebugState, AL.HealingEngine),
        loggerPerf = P.Copy(AL.Debug and AL.Debug.perf),
        decision = Getter(AL.Debug and AL.Debug.RotationState) }
    for _, name in ipairs({ "DebugState", "ManaGateState", "DecisionDebugState", "HealingState", "MindBlastState", "WandState", "GetUIState" }) do
        if name == "GetUIState" and ActionLiteDB and ActionLiteDB.activeProfile ~= token then
            result.rotation[name] = { status = "Edited class differs; live profile recorded separately" }
        elseif module and type(module[name]) == "function" then result.rotation[name] = Getter(module[name]) end
    end
    if detail == false then
        result.known, result.unlearned, result.rangeSpellRefs, result.futureSpells = nil, nil, nil, nil
    end
    result.spells = detail ~= false and {} or nil
    local profile = ActionLiteDB and ActionLiteDB.profiles and ActionLiteDB.profiles[token] or {}
    for _, entry in ipairs(detail ~= false and module and module.spells or {}) do
        local id, name = entry[1], entry[2]
        local reference = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
        result.spells[#result.spells + 1] = { name = name, baseID = id,
            learnedID = P.Copy(reference and reference.id), learned = P.Copy(AL.known and AL.known[name]),
            disabled = profile.spells and profile.spells[name] == false or false,
            iconOverride = P.Copy(profile.icons and profile.icons[name]),
            effectiveOverride = Getter(AL.IconFor, name, profile), slot = Getter(AL.SlotFor, name, profile) }
    end
    result.frames = {
        main = State.Frame(AL.frame, detail == false and 2 or 0),
        aoe = State.Frame(AL.aoeToggle, 2), burst = State.Frame(AL.burstToggle, 2), castTrail = State.Frame(AL.castTrailFrame, 2),
        menu = State.Frame(AL.GetMenuFrame and AL.GetMenuFrame(), 2),
        hotkey = State.Frame(AL.keyText, 2), comboText = State.Frame(AL.comboText, 2),
    }
    for slot = 1, 10 do result.frames["A" .. slot] = State.Frame(_G["A" .. slot], 2) end
    return result
end
