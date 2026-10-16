local _, AL = ...
local ns = AL.ActionLiteDebug
local C, P = ns.Catalog, {}
ns.Probe = P
local unpack = unpack or table.unpack

-- Either guard suffices on Forever. If both are exposed, both must allow
-- access. A missing/failed guard never turns a protected value into a number.
function P.GuardsReady()
    return type(issecretvalue) == "function" or type(canaccessvalue) == "function"
end

function P.Public(value)
    if not P.GuardsReady() then return false, "Guards unavailable" end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or type(secret) ~= "boolean" then return false, "Guard failed" end
        if secret then return false, "Hidden" end
    end
    if type(canaccessvalue) == "function" then
        local ok, allowed = pcall(canaccessvalue, value)
        if not ok or type(allowed) ~= "boolean" then return false, "Guard failed" end
        if not allowed then return false, "Inaccessible" end
    end
    return true
end

function P.TableAccess(value)
    local allowed, reason = P.Public(value)
    if not allowed then return false, reason end
    if type(value) ~= "table" then return false, "Not a table" end
    if type(canaccesstable) == "function" then
        local ok, accessible = pcall(canaccesstable, value)
        if not ok or type(accessible) ~= "boolean" then return false, "Guard failed" end
        if not accessible then return false, "Table inaccessible" end
    end
    return true
end

function P.Resolve(path)
    local object = _G
    for key in string.gmatch(path, "[^.]+") do
        if not P.TableAccess(object) then return nil end
        local ok, value = pcall(rawget, object, key)
        if not ok or not P.Public(value) then return nil end
        object = value
    end
    return object
end

local function ReadField(record, key)
    return pcall(function() return record[key] end)
end

function P.Value(value, spec, depth)
    local allowed, reason = P.Public(value)
    if not allowed then return {status = reason} end
    local kind = type(value)
    if kind == "nil" then return {status = "No data"} end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return {status = "Invalid number"}
        end
        return {status = "Visible", type = kind, value = value}
    elseif kind == "boolean" then
        return {status = "Visible", type = kind, value = value}
    elseif kind == "string" then
        if #value > 4096 then return {status = "Text exceeds limit", bytes = #value} end
        return {status = "Visible", type = kind, value = value}
    elseif kind == "userdata" then
        return {status = "Object only", type = kind}
    elseif kind ~= "table" then
        return {status = "Not verified", type = kind}
    end
    local accessible, tableReason = P.TableAccess(value)
    if not accessible then return {status = tableReason} end
    depth = depth or 0
    if depth >= 3 then return {status = "Depth limit", type = kind} end
    local node = {status = "Visible table", type = kind}
    local fields = spec and C.structures[spec.Type]
    if fields then
        node.fields = {}
        for _, field in ipairs(fields) do
            local ok, raw = ReadField(value, field.Name)
            node.fields[field.Name] = ok and P.Value(raw, field, depth + 1)
                or {status = "Field access failed"}
        end
    elseif spec and spec.InnerType then
        node.items, node.itemLimit = {}, spec.InnerType == "AuraData" and 3 or 8
        node.bounded = true
        for i = 1, node.itemLimit do
            local ok, raw = ReadField(value, i)
            node.items[i] = ok and P.Value(raw, {Type = spec.InnerType}, depth + 1)
                or {status = "Field access failed"}
            if node.items[i].status == "No data" then break end
        end
    else
        node.status = "Table contents not verified"
    end
    return node
end

function P.Call(path, args, failures, key)
    if not P.GuardsReady() then return {api = path, status = "Guards unavailable"} end
    local fn = P.Resolve(path)
    if type(fn) ~= "function" then return {api = path, status = "Missing"} end
    if failures and key and failures[key] then
        return {api = path, status = "Skipped after error"}
    end
    args = args or {}
    local schema = C.returns[path]
    local function Capture(...)
        local count = select("#", ...)
        local result = {api = path, status = count == 0 and "No data" or "Called",
            returnCount = count, values = {}}
        for i = 1, math.min(count, 32) do
            local spec = schema and schema.returns[i]
            if not spec and schema and #schema.returns > 0 then
                local tail = schema.returns[#schema.returns]
                if tail.StrideIndex then spec = tail end
            end
            local node = P.Value(select(i, ...), spec)
            node.name = spec and spec.Name or nil
            result.values[i] = node
        end
        if count > 32 then result.truncatedReturns = true end
        return result
    end
    local ok, result = pcall(function()
        return Capture(fn(unpack(args, 1, args.n or #args)))
    end)
    if not ok then
        if failures and key then failures[key] = true end
        local detail = P.Value(result)
        return {api = path, status = "Call failed", error = detail.type == "string"
            and detail.value or "Error detail unavailable"}
    end
    return result
end

function P.First(path, ...)
    local result = P.Call(path, {...})
    local node = result.values and result.values[1]
    if node and node.status == "Visible" then return node.value end
end

function P.Inventory()
    local rows = {}
    for _, name in ipairs(C.references) do
        local object = P.Resolve(name)
        rows[#rows + 1] = {api = name, reference = not P.GuardsReady() and "Guards unavailable" or type(object) == "function"
            and "Visible function" or object == nil and "Missing" or "Other reference"}
    end
    return rows
end

-- Sanitize addon-owned state immediately. Never retain a raw API table,
-- protected value, frame, function, or a reference to mutable live settings.
function P.Copy(value, depth, seen)
    local allowed, reason = P.Public(value)
    if not allowed then return "<" .. reason .. ">" end
    local kind = type(value)
    if kind == "nil" then return nil end
    if kind == "boolean" then return value end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "<Invalid number>" end
        return value
    end
    if kind == "string" then
        return #value > 4096 and (value:sub(1,4096) .. "<Text truncated>") or value
    end
    if kind ~= "table" then return "<" .. kind .. ">" end
    local accessible, why = P.TableAccess(value)
    if not accessible then return "<" .. why .. ">" end
    depth, seen = depth or 0, seen or {}
    if depth >= 8 then return "<Depth limit>" end
    if seen[value] then return "<Cycle>" end
    seen[value] = true
    local result, previous, count = {}, nil, 0
    while true do
        local ok, key, item = pcall(next, value, previous)
        if not ok then result._access = "Iteration failed"; break end
        if not P.Public(key) then result._access = "Hidden key"; break end
        if key == nil then break end
        count = count + 1
        if count > 512 then result._truncatedEntries = true; break end
        if type(key) == "string" or (type(key) == "number" and key == key and math.abs(key) < math.huge) then
            result[key] = P.Copy(item, depth + 1, seen)
        else result._unsupportedKey = true end
        previous = key
    end
    seen[value] = nil
    return result
end

local escapes = {["\""] = "\\\"", ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
local function Quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
        return escapes[char] or string.format("\\u%04x", string.byte(char))
    end) .. '"'
end

-- Only pass classified, public records to this encoder, never raw API values.
function P.JSON(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then return string.format("%.17g", value) end
    if kind == "string" then return Quote(value) end
    assert(kind == "table", "Report contains an unsupported value")
    local size, array = #value, #value > 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > size or key ~= math.floor(key) then
            array = false; break
        end
    end
    local parts = {}
    if array then
        for i = 1, size do parts[i] = P.JSON(value[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local label = type(key) == "number" and ("@index:" .. tostring(key)) or key
        parts[#parts + 1] = Quote(label) .. ":" .. P.JSON(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
