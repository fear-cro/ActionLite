local ADDON_NAME, AL = ...

-- ActionLITE Cast Trail v0.1.0
-- Integrated from CastTrail 0.2.2-beta by Cro Olfson. Cast/outcome/channel
-- tracking is retained; settings, anchoring and movement belong to ActionLITE.
-- This frame is parented to UIParent, independently of the recommendation icon.


local SLOT_COUNT = 5
local SLOT_ALPHA = { 1.00, 0.90, 0.60, 0.40, 0.20 }
local BASE_ICON_SIZE = 32
local SLOT_GAP = 4
local CHANNEL_ICON_SIZE = BASE_ICON_SIZE * 0.75
local CHANNEL_SLOT_GAP = SLOT_GAP * 0.75
local ROW_GAP = 4
local GCD_SPELL_ID = 61304
local DEFAULT_GCD = 1.5
local MIN_GCD = 0.75
local MAX_GCD = 2.0
local OUTCOME_WINDOW = 2.5
local CHANNEL_DUPLICATE_WINDOW = 0.5

local records = {}
local slots = {}
local channelRecords = {}
local channelSlots = {}
local pendingByCastGUID = {}
local frame
local mover
local resizeHandle
local hoverBackgroundShown = false
local lastGCD = DEFAULT_GCD
local activeChannel
local lastChannelCastGUID
local lastChannelSpellID
local lastChannelStartedAt = 0
local useCombatLog = false

local moving = false

-- Forever can return secret combat values to tainted addon code. Secret values
-- may be stored or passed back to approved APIs, but Lua comparisons, boolean
-- tests, arithmetic, and table indexing can raise errors. Normalize every
-- combat-event value before the addon performs any of those operations.
local function CanReadValue(value)
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        if ok then return readable == true end
    end

    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok then return secret ~= true end
    end

    return true
end

local function ReadableOrNil(value)
    if not CanReadValue(value) then return nil end
    return value
end

local function SafeEquals(left, right)
    if not CanReadValue(left) or not CanReadValue(right) then return nil end
    return left == right
end

local function GetUnitGUIDSafe(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    return ReadableOrNil(guid)
end

local function UnitMatchesTarget(unit)
    unit = ReadableOrNil(unit)
    if type(unit) ~= "string" then return false end
    if unit == "target" then return true end
    if type(UnitIsUnit) ~= "function" then return false end

    local ok, matches = pcall(UnitIsUnit, unit, "target")
    if not ok then return false end
    matches = ReadableOrNil(matches)
    return matches == true
end

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function CopyDefaults()
    AL.FillDBDefaults()
    local scale = tonumber(ActionLiteDB.castTrailScale) or 1
    if scale ~= scale then scale = 1 end
    ActionLiteDB.castTrailScale = Clamp(scale, 0.50, 2.50)
end

local function GetSpellTextureSafe(spellID)
    spellID = ReadableOrNil(spellID)
    if type(spellID) ~= "number" then return 134400 end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return 134400
end

local function GetGCDDuration()
    if C_Spell and C_Spell.GetSpellCooldown then
        local success, info = pcall(C_Spell.GetSpellCooldown, GCD_SPELL_ID)
        local duration
        if success and CanReadValue(info) then
            local ok, value = pcall(function() return info.duration end)
            if ok then duration = ReadableOrNil(value) end
        end
        if type(duration) == "number" and duration > 0 then
            lastGCD = Clamp(duration, MIN_GCD, MAX_GCD)
            return lastGCD
        end
    end
    return lastGCD
end

local function SetBorderColor(slot, outcome)
    if outcome == "crit" then
        slot.border:SetBackdropBorderColor(0.10, 1.00, 0.10, 1)
    elseif outcome == "miss" then
        slot.border:SetBackdropBorderColor(1.00, 0.08, 0.08, 1)
    else
        slot.border:SetBackdropBorderColor(0, 0, 0, 0.90)
    end
end

local function ClearSlot(slot)
    slot:Hide()
    slot.icon:SetTexture(nil)
    slot.icon:SetDesaturated(false)
    slot.icon:SetVertexColor(1, 1, 1, 1)
end

local function AlphaAtPosition(position)
    if position <= 1 then return SLOT_ALPHA[1] end
    if position >= SLOT_COUNT then return SLOT_ALPHA[SLOT_COUNT] end

    local left = math.floor(position)
    local progress = position - left
    return SLOT_ALPHA[left] + ((SLOT_ALPHA[left + 1] - SLOT_ALPHA[left]) * progress)
end

local function VisualAge(record, now)
    if not record.slideStart then return record.displayAge or record.age end

    local duration = math.max(0.05, record.slideDuration or record.gcd or DEFAULT_GCD)
    local progress = Clamp((now - record.slideStart) / duration, 0, 1)
    local position = record.slideFrom + ((record.slideTo - record.slideFrom) * progress)

    if progress >= 1 then
        record.displayAge = record.slideTo
        record.slideStart = nil
        record.slideFrom = nil
        record.slideTo = nil
        record.slideDuration = nil
        return record.displayAge
    end

    record.displayAge = position
    return position
end

local function StartSlide(record, newAge, duration, now)
    local fromAge = VisualAge(record, now)
    record.age = newAge
    record.displayAge = fromAge
    record.slideFrom = fromAge
    record.slideTo = newAge
    record.slideStart = now
    record.slideDuration = duration or record.gcd or DEFAULT_GCD
end

local function PositionSlot(slot, position, channel)
    local iconSize = channel and CHANNEL_ICON_SIZE or BASE_ICON_SIZE
    local gap = channel and CHANNEL_SLOT_GAP or SLOT_GAP
    local y = channel and -(BASE_ICON_SIZE + ROW_GAP) or 0

    slot:ClearAllPoints()
    slot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -((position - 1) * (iconSize + gap)), y)
end

local function DrawRecord(slot, record, position, channel)
    PositionSlot(slot, position, channel)
    slot.icon:SetTexture(record.texture)
    slot.icon:SetDesaturated(record.outcome == "miss")
    if record.outcome == "miss" then
        slot.icon:SetVertexColor(1.00, 0.22, 0.22, 1)
    else
        slot.icon:SetVertexColor(1, 1, 1, 1)
    end
    SetBorderColor(slot, record.outcome)
    slot:SetAlpha(AlphaAtPosition(position))
    slot:Show()
end

local function Render(now)
    now = now or GetTime()
    for index = 1, SLOT_COUNT do
        ClearSlot(slots[index])
        ClearSlot(channelSlots[index])
    end

    for i = 1, #records do
        local record = records[i]
        local slot = slots[record.age]
        if slot then
            DrawRecord(slot, record, VisualAge(record, now), false)
        end
    end

    for i = 1, #channelRecords do
        local record = channelRecords[i]
        local slot = channelSlots[record.age]
        if slot then
            DrawRecord(slot, record, VisualAge(record, now), true)
        end
    end
end

local function RemovePending(record)
    if record.castGUID then
        pendingByCastGUID[record.castGUID] = nil
    end
end

local function PurgeExpired(now)
    local changed = false
    for i = #records, 1, -1 do
        local record = records[i]
        if record.age > SLOT_COUNT then
            RemovePending(record)
            table.remove(records, i)
            changed = true
        elseif record.outcome == "pending" and now - record.castAt > OUTCOME_WINDOW then
            record.outcome = "neutral"
            changed = true
        end
    end
    return changed
end

local function FindRecordAtAge(age)
    for i = 1, #records do
        if records[i].age == age then
            return records[i]
        end
    end
end

local function RemoveRecord(record)
    for i = #records, 1, -1 do
        if records[i] == record then
            RemovePending(record)
            table.remove(records, i)
            return
        end
    end
end

local function MakeRoomForAge(age, now, duration)
    local record = FindRecordAtAge(age)
    if not record then return end

    if age >= SLOT_COUNT then
        RemoveRecord(record)
        return
    end

    MakeRoomForAge(age + 1, now, duration)
    StartSlide(record, age + 1, duration or record.gcd, now)
    record.nextAgeAt = math.max(record.nextAgeAt or 0, now + (record.gcd or duration))
end

local function FindPendingRecord(destGUID, spellID, maxAge)
    destGUID = ReadableOrNil(destGUID)
    spellID = ReadableOrNil(spellID)
    maxAge = maxAge or OUTCOME_WINDOW

    local now = GetTime()
    for i = #records, 1, -1 do
        local record = records[i]
        if record.outcome == "pending"
            and now - record.castAt <= maxAge
            and (not destGUID or not record.targetGUID
                or SafeEquals(destGUID, record.targetGUID) == true)
            and (not spellID or SafeEquals(spellID, record.spellID) == true) then
            return record
        end
    end
end

local function SetOutcome(record, outcome)
    if not record then return end
    record.outcome = outcome
    RemovePending(record)
    Render()
end

local function AddCast(castGUID, spellID, outcome, targetGUID)
    castGUID = ReadableOrNil(castGUID)
    spellID = ReadableOrNil(spellID)
    targetGUID = ReadableOrNil(targetGUID)
    if type(spellID) ~= "number" or spellID <= 0 then return end

    local now = GetTime()
    PurgeExpired(now)
    local gcd = GetGCDDuration()

    -- Preserve closely spaced casts by pushing only occupied
    -- blocks. A cast already farther left keeps its current independent age.
    MakeRoomForAge(1, now, gcd)

    local record = {
        spellID = spellID,
        castGUID = castGUID,
        texture = GetSpellTextureSafe(spellID),
        targetGUID = targetGUID or GetUnitGUIDSafe("target"),
        castAt = now,
        age = 1,
        displayAge = 1,
        outcome = outcome or "pending",
        gcd = gcd,
        nextAgeAt = now + gcd,
    }
    records[#records + 1] = record
    if castGUID and record.outcome == "pending" then
        pendingByCastGUID[castGUID] = record
    end

    Render(now)
    return record
end

local missEvents = {
    MISS = true,
    DODGE = true,
    PARRY = true,
    BLOCK = true,
    RESIST = true,
    IMMUNE = true,
    EVADE = true,
    DEFLECT = true,
}

local critEvents = {
    CRIT = true,
    CRITICAL = true,
    CRUSHING = true,
}

local hitEvents = {
    WOUND = true,
    HEAL = true,
    ENERGIZE = true,
}

local function GetUnitCombatOutcome(eventType, flagText)
    eventType = ReadableOrNil(eventType)
    flagText = ReadableOrNil(flagText)
    if type(eventType) ~= "string" then return end
    if flagText ~= nil and type(flagText) ~= "string" then flagText = nil end

    if missEvents[eventType] or missEvents[flagText] then return "miss" end
    if critEvents[eventType] or critEvents[flagText] then return "crit" end
    if hitEvents[eventType] then return "hit" end
end

local function ChannelMatches(destGUID, spellID, targetUnitMatches)
    if not activeChannel then return false end

    destGUID = ReadableOrNil(destGUID)
    spellID = ReadableOrNil(spellID)

    local spellMatches = not spellID
        or not activeChannel.spellID
        or SafeEquals(spellID, activeChannel.spellID) == true
    if not spellMatches then return false end

    if destGUID and activeChannel.targetGUID then
        return SafeEquals(destGUID, activeChannel.targetGUID) == true
    end

    -- UNIT_COMBAT identifies the affected unit even when its GUID is secret.
    -- Combat-log periodic events can still be correlated by a readable spell ID.
    return targetUnitMatches == true
        or (spellID and activeChannel.spellID
            and SafeEquals(spellID, activeChannel.spellID) == true)
end

local function AddChannelTick(outcome)
    if not activeChannel or not outcome then return end

    local now = GetTime()
    local gcd = GetGCDDuration()

    for i = #channelRecords, 1, -1 do
        local record = channelRecords[i]
        local newAge = record.age + 1
        if newAge > SLOT_COUNT then
            table.remove(channelRecords, i)
        else
            StartSlide(record, newAge, gcd, now)
        end
    end

    channelRecords[#channelRecords + 1] = {
        spellID = activeChannel.spellID,
        texture = GetSpellTextureSafe(activeChannel.spellID),
        outcome = outcome,
        age = 1,
        displayAge = 1,
        gcd = gcd,
    }
    Render(now)
end

local function ClearChannelTicks()
    for i = #channelRecords, 1, -1 do
        channelRecords[i] = nil
    end
    Render()
end

local function HandleUnitCombat(unit, eventType, flagText)
    if useCombatLog then return end

    unit = ReadableOrNil(unit)
    eventType = ReadableOrNil(eventType)
    flagText = ReadableOrNil(flagText)
    if type(unit) ~= "string" or type(eventType) ~= "string" then return end

    local targetUnitMatches = UnitMatchesTarget(unit)
    if not targetUnitMatches then return end

    local destGUID = GetUnitGUIDSafe(unit)
    local outcome = GetUnitCombatOutcome(eventType, flagText)
    if not outcome then return end

    if ChannelMatches(destGUID, nil, targetUnitMatches) then
        AddChannelTick(outcome)
        return
    end

    local record = FindPendingRecord(destGUID)
    if not record then return end
    SetOutcome(record, outcome)
end

local function HandleCombatLog()
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
    local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID, _, _,
        arg15, arg16, arg17, arg18, arg19, arg20, arg21 = CombatLogGetCurrentEventInfo()
    subevent = ReadableOrNil(subevent)
    sourceGUID = ReadableOrNil(sourceGUID)
    destGUID = ReadableOrNil(destGUID)
    spellID = ReadableOrNil(spellID)
    if type(subevent) ~= "string" then return end

    local playerGUID = GetUnitGUIDSafe("player")
    if not sourceGUID or not playerGUID
        or SafeEquals(sourceGUID, playerGUID) ~= true then return end

    if subevent == "SPELL_PERIODIC_MISSED" and ChannelMatches(destGUID, spellID) then
        AddChannelTick("miss")
        return
    elseif (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_HEAL")
        and ChannelMatches(destGUID, spellID) then
        local critical
        if subevent == "SPELL_PERIODIC_HEAL" then
            critical = arg18
        else
            critical = arg21
        end
        critical = ReadableOrNil(critical)
        AddChannelTick(critical == true and "crit" or "hit")
        return
    end

    local record = FindPendingRecord(destGUID, spellID)
    if not record then return end

    if subevent == "SPELL_MISSED" or subevent == "RANGE_MISSED" then
        SetOutcome(record, "miss")
    elseif subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "SPELL_HEAL" then
        local critical
        if subevent == "SPELL_HEAL" then
            critical = arg18
        else
            critical = arg21
        end
        critical = ReadableOrNil(critical)
        SetOutcome(record, critical == true and "crit" or "hit")
    elseif subevent == "SPELL_ENERGIZE" or subevent == "SPELL_AURA_APPLIED" then
        SetOutcome(record, "hit")
    end
end

-- Saved offsets use UIParent units, rather than scaled-frame units, so a
-- custom location remains fixed when the unlocked trail is resized.
local function SavePosition(point)
    if not frame then return end
    point = point or "TOPRIGHT"
    local x = point == "TOPLEFT" and frame:GetLeft() or frame:GetRight()
    local y = frame:GetTop()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local scale = frame:GetScale()
    ActionLiteDB.castTrailPosition = { point = point, x = x * scale, y = y * scale }
end

local function PhysicalPixel()
    -- Match the display's physical-pixel conversion without inheriting its
    -- profile scale. The requested gap stays five pixels at every UI scale.
    if type(GetPhysicalScreenSize) == "function" then
        local _, height = GetPhysicalScreenSize()
        local uiScale = UIParent:GetEffectiveScale()
        if height and height > 0 and uiScale and uiScale > 0 then
            return 768 / (height * uiScale)
        end
    end
    return 1
end

local function ApplyPosition()
    if not frame then return end
    local scale = frame:GetScale()
    local position = ActionLiteDB.castTrailPosition
    frame:ClearAllPoints()
    if type(position) == "table"
        and (position.point == "TOPLEFT" or position.point == "TOPRIGHT")
        and type(position.x) == "number" and position.x == position.x
        and type(position.y) == "number" and position.y == position.y
        and math.abs(position.x) < math.huge and math.abs(position.y) < math.huge then
        frame:SetClampedToScreen(true)
        frame:SetPoint(position.point, UIParent, "BOTTOMLEFT", position.x / scale, position.y / scale)
    else
        ActionLiteDB.castTrailPosition = nil
        -- Screen clamping would break exact alignment when the main icon is
        -- near an edge. A custom, independently moved position is clamped.
        frame:SetClampedToScreen(false)
        frame:SetPoint("TOPRIGHT", AL.frame, "BOTTOMRIGHT", 0, -5 * PhysicalPixel() / scale)
    end
end

local function StopEditing()
    if moving then
        frame:StopMovingOrSizing()
        moving = false
        SavePosition("TOPRIGHT")
        ApplyPosition()
    end
    if resizeHandle then resizeHandle.resizing = false end
end

local function ApplyScale(scale)
    if ActionLiteDB.castTrailLocked or not ActionLiteDB.castTrailOn then return end
    scale = Clamp(scale, 0.50, 2.50)
    ActionLiteDB.castTrailScale = scale
    frame:SetScale(scale)
    ApplyPosition()
end

local function ApplyHoverAppearance(showBackground)
    hoverBackgroundShown = showBackground and true or false
    if not frame then return end

    frame:SetBackdropColor(0, 0, 0, hoverBackgroundShown and 0.22 or 0)

    local showControls = hoverBackgroundShown and ActionLiteDB.castTrailOn and not ActionLiteDB.castTrailLocked
    if mover then
        if showControls then mover:Show() else mover:Hide() end
    end
    if resizeHandle then
        if showControls then resizeHandle:Show() else resizeHandle:Hide() end
    end
end

local function UpdateHoverAppearance()
    if not frame or type(frame.IsMouseOver) ~= "function" then return end
    local ok, hovered = pcall(frame.IsMouseOver, frame)
    hovered = ok and ReadableOrNil(hovered) == true
    if hovered ~= hoverBackgroundShown then
        ApplyHoverAppearance(hovered)
    end
end

local function CreateSlot(index)
    local slot = CreateFrame("Frame", nil, frame)
    slot:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
    -- Cast_1 is right-most; Cast_5 is left-most.
    slot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -((index - 1) * (BASE_ICON_SIZE + SLOT_GAP)), 0)

    slot.border = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    slot.border:SetAllPoints()
    slot.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot:Hide()
    return slot
end

local function CreateChannelSlot(index)
    local slot = CreateFrame("Frame", nil, frame)
    slot:SetSize(CHANNEL_ICON_SIZE, CHANNEL_ICON_SIZE)
    slot:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
        -((index - 1) * (CHANNEL_ICON_SIZE + CHANNEL_SLOT_GAP)),
        -(BASE_ICON_SIZE + ROW_GAP))

    slot.border = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    slot.border:SetAllPoints()
    slot.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot:Hide()
    return slot
end

local function CreateUI()
    local width = SLOT_COUNT * BASE_ICON_SIZE + (SLOT_COUNT - 1) * SLOT_GAP
    frame = CreateFrame("Frame", "ActionLiteCastTrailFrame", UIParent, "BackdropTemplate")
    AL.castTrailFrame = frame
    frame:SetSize(width, BASE_ICON_SIZE + ROW_GAP + CHANNEL_ICON_SIZE)
    frame:SetClampedToScreen(true)
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScale(ActionLiteDB.castTrailScale)
    ApplyPosition()
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdropColor(0, 0, 0, 0)

    frame:SetScript("OnDragStart", function(self)
        if ActionLiteDB.castTrailLocked or not ActionLiteDB.castTrailOn then return end
        moving = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", StopEditing)
    frame:SetScript("OnHide", function()
        StopEditing()
        ApplyHoverAppearance(false)
    end)

    for index = 1, SLOT_COUNT do
        slots[index] = CreateSlot(index)
        channelSlots[index] = CreateChannelSlot(index)
    end

    mover = frame:CreateTexture(nil, "OVERLAY")
    mover:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    mover:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    mover:SetColorTexture(0.25, 0.65, 1, 0.10)

    resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(14, 14)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizeHandle:EnableMouse(false)
    local texture = resizeHandle:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or ActionLiteDB.castTrailLocked or not ActionLiteDB.castTrailOn then return end
        -- Detach only when the user actually moves/resizes the trail. Resizing
        -- keeps its top-left corner fixed as the bottom-right grip moves.
        SavePosition("TOPLEFT")
        ApplyPosition()
        resizeHandle.resizing = true
        local x = GetCursorPosition()
        resizeHandle.startX = x
        resizeHandle.startScale = frame:GetScale()
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        resizeHandle.resizing = false
    end)
    resizeHandle:SetScript("OnUpdate", function(self)
        if not self.resizing then return end
        if ActionLiteDB.castTrailLocked or not ActionLiteDB.castTrailOn then
            self.resizing = false
            return
        end
        local x = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        local delta = (x - self.startX) / uiScale
        ApplyScale(self.startScale + (delta / frame:GetWidth()))
    end)

    ApplyHoverAppearance(false)

    frame:SetScript("OnUpdate", function()
        local now = GetTime()
        local changed = false
        UpdateHoverAppearance()

        -- Each record owns one small timestamp, allowing an older cast to keep
        -- its journey when a new cast or channel tick enters Cast_1.
        for i = 1, #records do
            local record = records[i]
            if now >= record.nextAgeAt then
                local newAge = record.age + 1
                if newAge > SLOT_COUNT then
                    record.age = newAge
                else
                    StartSlide(record, newAge, record.gcd, now)
                end
                record.nextAgeAt = now + record.gcd
                changed = true
            end
            if record.slideStart then changed = true end
        end

        for i = 1, #channelRecords do
            if channelRecords[i].slideStart then changed = true end
        end

        if PurgeExpired(now) then changed = true end
        if changed then
            Render(now)
        end
    end)
end

function AL.ApplyCastTrail()
    CopyDefaults()
    if not frame then return end
    if ActionLiteDB.castTrailLocked or not ActionLiteDB.castTrailOn then StopEditing() end
    frame:SetScale(ActionLiteDB.castTrailScale)
    if not moving then ApplyPosition() end
    local editable = ActionLiteDB.castTrailOn and not ActionLiteDB.castTrailLocked
    frame:SetMovable(editable)
    frame:EnableMouse(editable)
    resizeHandle:EnableMouse(editable)
    ApplyHoverAppearance(editable and hoverBackgroundShown)
    if not ActionLiteDB.castTrailOn then
        wipe(records)
        wipe(channelRecords)
        wipe(pendingByCastGUID)
        activeChannel = nil
        lastChannelCastGUID, lastChannelSpellID = nil, nil
        lastChannelStartedAt = 0
        Render()
    end
    frame:SetShown(ActionLiteDB.castTrailOn)
end

function AL.ResetCastTrail()
    -- Stop first so a drag in progress cannot overwrite the reset position.
    StopEditing()
    ActionLiteDB.castTrailOn = true
    ActionLiteDB.castTrailLocked = true
    ActionLiteDB.castTrailScale = 1
    ActionLiteDB.castTrailPosition = nil
    AL.ApplyCastTrail()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ReadableOrNil(...)
        if loadedName ~= ADDON_NAME then return end
        if frame then return end
        CopyDefaults()
        CreateUI()
        AL.ApplyCastTrail()
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        self:RegisterEvent("UNIT_COMBAT")
        if type(CombatLogGetCurrentEventInfo) == "function" then
            useCombatLog = true
            self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        AL.ApplyCastTrail()
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        if not moving and not (resizeHandle and resizeHandle.resizing) then ApplyPosition() end
    elseif event == "PLAYER_LOGOUT" then
        StopEditing()
    elseif not frame or not ActionLiteDB.castTrailOn then
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        unit = ReadableOrNil(unit)
        castGUID = ReadableOrNil(castGUID)
        spellID = ReadableOrNil(spellID)

        if unit == "player" and type(spellID) == "number" then
            local duplicateChannel = false
            if castGUID and lastChannelCastGUID then
                duplicateChannel = SafeEquals(castGUID, lastChannelCastGUID) == true
            elseif lastChannelSpellID
                and SafeEquals(spellID, lastChannelSpellID) == true
                and GetTime() - lastChannelStartedAt <= CHANNEL_DUPLICATE_WINDOW then
                duplicateChannel = true
            end

            if not duplicateChannel then AddCast(castGUID, spellID) end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, castGUID, spellID = ...
        unit = ReadableOrNil(unit)
        castGUID = ReadableOrNil(castGUID)
        spellID = ReadableOrNil(spellID)

        if unit == "player" and type(spellID) == "number" then
            ClearChannelTicks()

            local targetGUID = GetUnitGUIDSafe("target")
            local existing = castGUID and pendingByCastGUID[castGUID] or nil
            if not existing then
                existing = FindPendingRecord(targetGUID, spellID, CHANNEL_DUPLICATE_WINDOW)
            end

            if not existing then AddCast(castGUID, spellID, nil, targetGUID) end

            lastChannelCastGUID = castGUID
            lastChannelSpellID = spellID
            lastChannelStartedAt = GetTime()
            activeChannel = {
                castGUID = castGUID,
                spellID = spellID,
                targetGUID = targetGUID,
            }
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit = ReadableOrNil(...)
        -- Only the player's channel-stop event is registered, so identifiers
        -- are unnecessary here and may themselves be secret in combat.
        if unit == "player" and activeChannel then
            activeChannel = nil
            ClearChannelTicks()
        end
    elseif event == "UNIT_COMBAT" then
        local unit, eventType, flagText = ...
        HandleUnitCombat(unit, eventType, flagText)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog()
    end
end)

