local _, AL = ...
local ns = AL.ActionLiteDebug
local S, UI = ns.Scanner, {}
ns.UI = UI
local theme = {
    background = {0, 0, 0, 1}, panel = {0, 0, 0, 1},
    accent = {1, 0.843, 0, 1}, text = {1, 0.843, 0, 1},
    hover = {0.14, 0.11, 0.015, 1}, selected = {0.20, 0.16, 0.03, 1},
    green = {0.16, 0.85, 0.36, 1}, yellow = {0.96, 0.78, 0.20, 1}, red = {0.94, 0.16, 0.20, 1},
}
local unpack = unpack or table.unpack
local circle = "Interface\\AddOns\\ActionLITE\\Media\\ActionLiteDebug_Circle"
local resize = "Interface\\AddOns\\ActionLITE\\Media\\ActionLiteDebug_Resize"
local resultsText, settingText = "", false
local main, lamp, status, buttons, results, edit

local function Texture(frame, layer, color)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(unpack(color or theme.background))
    return t
end

local function Font(frame, text, size, color)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "")
    fs:SetTextColor(unpack(color or theme.text))
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Border(frame)
    local top, bottom, left, right = Texture(frame, "BORDER", theme.accent), Texture(frame, "BORDER", theme.accent),
        Texture(frame, "BORDER", theme.accent), Texture(frame, "BORDER", theme.accent)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
end

local function KeepPositionTemporary(frame)
    if type(frame.SetDontSavePosition) == "function" then frame:SetDontSavePosition(true) end
    if type(frame.SetUserPlaced) == "function" then frame:SetUserPlaced(false) end
end

local function Button(parent, text, width, height, click, component)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 64, height or 25)
    button.bg = Texture(button, "BACKGROUND", theme.panel)
    button.bg:SetAllPoints()
    Border(button)
    button.label = Font(button, text, 12)
    button.label:SetPoint("CENTER")
    button.captureEnabled = true
    button:SetScript("OnClick", function(...)
        if button.captureEnabled then ns.Try(component or "Control window", click, ...) end
    end)
    button:SetScript("OnEnter", function(self)
        if self.captureEnabled then self.bg:SetColorTexture(unpack(theme.hover)) end
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, theme.text[1], theme.text[2], theme.text[3])
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(unpack(self.active and theme.selected or theme.panel))
        if GameTooltip then GameTooltip:Hide() end
    end)
    return button
end

local function Shell(name, title, width, height, minimumWidth, minimumHeight, strata)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata(strata or "DIALOG")
    frame:SetAlpha(1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    KeepPositionTemporary(frame)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(minimumWidth, minimumHeight, 1200, 900)
    elseif type(frame.SetMinResize) == "function" then
        frame:SetMinResize(minimumWidth, minimumHeight)
    end
    frame.background = Texture(frame, "BACKGROUND", theme.background)
    frame.background:SetAllPoints()
    Border(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(25)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar.background = Texture(bar, "BACKGROUND", theme.panel)
    bar.background:SetAllPoints()
    local label = Font(bar, title, 12)
    label:SetPoint("LEFT", 9, 0)
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); KeepPositionTemporary(frame) end)
    local close = Button(bar, "X", 24, 20, function() frame:Hide() end)
    close:SetPoint("RIGHT", -3, 0)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip.texture = grip:CreateTexture(nil, "OVERLAY")
    grip.texture:SetAllPoints()
    grip.texture:SetTexture(resize)
    grip.texture:SetVertexColor(unpack(theme.accent))
    grip:SetScript("OnMouseDown", function(_, mouse)
        if mouse == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); KeepPositionTemporary(frame) end)
    frame.titleBar, frame.close, frame.grip = bar, close, grip
    frame:SetScript("OnHide", function() frame:StopMovingOrSizing(); KeepPositionTemporary(frame) end)
    frame:Hide()
    return frame
end

local function BuildMain()
    main = Shell("ActionLiteDebugWindow", "ActionLiteDebug", 310, 112, 292, 106)
    UI.main = main
    lamp = main:CreateTexture(nil, "OVERLAY")
    lamp:SetTexture(circle)
    lamp:SetSize(17, 17)
    lamp:SetPoint("TOPLEFT", 13, -39)
    status = Font(main, "Not Running", 12)
    status:SetPoint("LEFT", lamp, "RIGHT", 8, 0)
    UI.lamp, UI.status = lamp, status
    buttons = {
        Button(main, "Start", 65, 25, function() S.Start() end),
        Button(main, "Pause", 65, 25, function() S.Pause() end),
        Button(main, "Stop", 65, 25, function() S.Stop() end),
        Button(main, "Results", 65, 25, function() UI.OpenResults() end, "Results window"),
    }
    buttons[1].tip = "Start recording. Resumes a paused recording; after Stop, starts a new capture in memory."
    buttons[2].tip = "Pause API reads. Press Start to resume."
    buttons[3].tip = "Stop API reads. The report stays in memory until a new capture, reload or logout."
    buttons[4].tip = "Stop recording and open the copyable report."
    UI.buttons = buttons
    local resizingMain = false
    main:SetScript("OnSizeChanged", function(self, width, height)
        if resizingMain then return end
        if width < 292 or height < 106 then
            resizingMain = true; self:SetSize(math.max(width, 292), math.max(height, 106)); resizingMain = false
            width = self:GetWidth()
        end
        local buttonWidth = (width - 38) / 4
        for i, button in ipairs(buttons) do
            button:ClearAllPoints()
            button:SetSize(buttonWidth, 25)
            button:SetPoint("BOTTOMLEFT", 10 + (i - 1) * (buttonWidth + 6), 22)
        end
    end)
    main:GetScript("OnSizeChanged")(main, main:GetWidth(), main:GetHeight())

    main:HookScript("OnHide", function()
        if S.state == "Recording" or S.state == "Paused" then S.Stop("Debugger closed") end
    end)
    UI.ready = true
    UI.Refresh()
end

function UI.Initialize()
    if UI.ready then return true end
    if not ns.Catalog or not ns.Probe or not S or not S.ready then
        error("The debugger did not finish loading. Reopen the Bug report tab or reload the UI.", 0)
    end
    if UI.initializationError then error(UI.initializationError, 0) end
    local ok, problem = pcall(BuildMain)
    if not ok then
        UI.ready = false
        UI.initializationError = ns.ErrorText(problem)
        local frame = main or _G.ActionLiteDebugWindow
        if frame then pcall(frame.Hide, frame) end
        error(UI.initializationError, 0)
    end
    return true
end

local function BuildResults()
    results = Shell("ActionLiteDebugResultsWindow", "ActionLiteDebug - Results", 740, 440, 500, 280, "FULLSCREEN_DIALOG")
    UI.results = results
    local resultsLamp = results.titleBar:CreateTexture(nil, "OVERLAY")
    resultsLamp:SetTexture(circle)
    resultsLamp:SetSize(14, 14)
    resultsLamp:SetVertexColor(unpack(theme.red))
    resultsLamp:SetPoint("RIGHT", results.close, "LEFT", -138, 0)
    local resultsStatus = Font(results.titleBar, "Not Running", 11)
    resultsStatus:SetPoint("LEFT", resultsLamp, "RIGHT", 7, 0)
    UI.resultsLamp, UI.resultsStatus = resultsLamp, resultsStatus
    local hint = Font(results, "Select All highlights the complete results. Press Ctrl+C (Cmd+C on Mac) to copy.", 12)
    hint:SetPoint("TOPLEFT", 14, -35)
    hint:SetPoint("TOPRIGHT", -14, -35)
    hint:SetHeight(28)
    local scroll = CreateFrame("ScrollFrame", nil, results)
    scroll:SetPoint("TOPLEFT", 14, -66)
    scroll:SetPoint("BOTTOMRIGHT", -32, 54)
    scroll:EnableMouseWheel(true)
    local textBackground = Texture(results, "BACKGROUND", theme.panel)
    textBackground:SetPoint("TOPLEFT", scroll, "TOPLEFT", -3, 3)
    textBackground:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 3, -3)
    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont("Fonts\\ARIALN.TTF", 13, "")
    edit:SetTextColor(unpack(theme.text))
    edit:SetMaxLetters(0)
    if type(edit.SetMaxBytes) == "function" then edit:SetMaxBytes(0) end
    edit:SetTextInsets(5, 5, 4, 4)
    edit:SetWidth(680)
    edit:SetHeight(1)
    scroll:SetScrollChild(edit)
    UI.edit, UI.scroll, UI.hint = edit, scroll, hint
    
    local scrollbar = CreateFrame("Slider", nil, results)
    scrollbar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 7, 0)
    scrollbar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 7, 0)
    scrollbar:SetWidth(12)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValueStep(20)
    scrollbar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = scrollbar:GetThumbTexture()
    thumb:SetSize(9, 24)
    thumb:SetVertexColor(unpack(theme.accent))
    scrollbar.track = Texture(scrollbar, "BACKGROUND", theme.panel)
    scrollbar.track:SetAllPoints()
    local syncingScroll = false
    local function ScrollTo(value)
        local maximum = scroll:GetVerticalScrollRange() or 0
        value = math.max(0, math.min(value or 0, maximum))
        scroll:SetVerticalScroll(value)
        if not syncingScroll then syncingScroll = true; scrollbar:SetValue(value); syncingScroll = false end
    end
    scrollbar:SetScript("OnValueChanged", function(_, value) if not syncingScroll then ScrollTo(value) end end)
    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollTo(scroll:GetVerticalScroll() - delta * 50) end)
    scroll:SetScript("OnScrollRangeChanged", function(_, _, maximum)
        scrollbar:SetMinMaxValues(0, math.max(0, maximum or 0))
        ScrollTo(scroll:GetVerticalScroll())
    end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local position, visibleHeight = scroll:GetVerticalScroll(), scroll:GetHeight()
        local bottom = -y + height
        if -y < position then ScrollTo(-y)
        elseif bottom > position + visibleHeight then ScrollTo(bottom - visibleHeight) end
    end)
    edit:SetScript("OnEscapePressed", function() results:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not settingText then
            settingText = true; self:SetText(resultsText); settingText = false
            self:HighlightText(0, #resultsText)
        end
    end)
    
    function UI.SelectAll()
        if not results:IsShown() then return end
        edit:SetFocus()
        edit:SetCursorPosition(0)
        edit:HighlightText(0, #resultsText)
        ScrollTo(0)
        hint:SetText("All data selected. Press Ctrl+C (Cmd+C on Mac), then paste it where needed.")
    end
    
    local selectAll = Button(results, "Select All", 106, 27, function() UI.SelectAll() end)
    selectAll:SetPoint("BOTTOMLEFT", 14, 14)
    local done = Button(results, "Close", 90, 27, function() results:Hide() end)
    done:SetPoint("BOTTOMLEFT", selectAll, "BOTTOMRIGHT", 9, 0)
    UI.selectAllButton, UI.closeResultsButton = selectAll, done
    local resultsResizing = false
    results:SetScript("OnSizeChanged", function(self, width, height)
        if resultsResizing then return end
        if width < 500 or height < 280 then
            resultsResizing = true; self:SetSize(math.max(width, 500), math.max(height, 280)); resultsResizing = false
        end
        edit:SetWidth(math.max(100, self:GetWidth() - 46))
    end)
    results:HookScript("OnHide", function()
        edit:ClearFocus()
        if UI.returnToMain then main:Show() end
        UI.returnToMain = false
    end)

    UI.resultsReady = true
end

local function EnsureResults()
    if UI.resultsReady then return end
    if UI.resultsError then error(UI.resultsError, 0) end
    local ok, problem = pcall(BuildResults)
    if not ok then
        UI.resultsError = ns.ErrorText(problem)
        local frame = results or _G.ActionLiteDebugResultsWindow
        if frame then pcall(frame.Hide, frame) end
        error(UI.resultsError, 0)
    end
end

function UI.CloseResults(showMain)
    if not results then return end
    UI.returnToMain = showMain == true
    results:Hide()
end

function UI.ClearResults()
    resultsText = ""
    if not edit then return end
    settingText = true; edit:SetText(""); settingText = false
    edit:ClearFocus()
end

function UI.OpenResults()
    UI.Initialize()
    local text = S.Results()
    EnsureResults()
    resultsText = text
    main:Hide()
    UI.returnToMain = true
    results:Show()
    settingText = true; edit:SetText(resultsText); settingText = false
    edit:SetWidth(results:GetWidth() - 46)
    UI.SelectAll()
    UI.Refresh()
end

function UI.Toggle()
    UI.Initialize()
    if results and results:IsShown() then UI.CloseResults(true); return end
    if main:IsShown() then main:Hide() else main:Show() end
end

function UI.Show()
    UI.Initialize()
    if results and results:IsShown() then UI.CloseResults(true) end
    if AL.HideMenu then AL.HideMenu() end
    local legacy = _G.ActionLiteDebugFrame
    if legacy then legacy:Hide() end
    main:Show()
    return true
end

function UI.Hide()
    UI.CloseResults(false)
    if main then main:Hide() end
end

local function SetButtonEnabled(button, enabled)
    button.captureEnabled = enabled
    if type(button.Enable) == "function" and type(button.Disable) == "function" then
        if enabled then button:Enable() else button:Disable() end
    elseif type(button.SetEnabled) == "function" then button:SetEnabled(enabled) end
end

function UI.Refresh()
    if not UI.ready then return end
    local recording, paused = S.state == "Recording", S.state == "Paused"
    local color = recording and theme.green or theme.red
    lamp:SetVertexColor(unpack(color))
    status:SetTextColor(unpack(theme.text))
    local remaining = recording and S.PostCombatRemaining()
    local text = recording and "Running" or paused and "Paused" or "Not Running"
    if remaining then text = "Finishing: " .. math.ceil(remaining) .. "s"
    elseif S.stopReason == "Complete: five seconds after combat" then text = "Complete - Results ready" end
    if ns.message then text = ns.message end
    status:SetText(text)
    for i, button in ipairs(buttons) do
        button.active = i == 1 and recording or i == 2 and paused or i == 3 and not recording and not paused
        button.bg:SetColorTexture(unpack(button.active and theme.selected or theme.panel))
        button.label:SetAlpha((i == 1 and recording or i == 2 and not recording or i == 3 and not recording and not paused) and 0.5 or 1)
    end
    SetButtonEnabled(buttons[1], not recording)
    SetButtonEnabled(buttons[2], recording)
    SetButtonEnabled(buttons[3], recording or paused)
end

-- Windows are created only when opened from ActionLITE.
if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "ActionLiteDebugWindow")
    table.insert(UISpecialFrames, "ActionLiteDebugResultsWindow")
end

-- Existing ActionLITE debug shortcuts open this same copy/paste platform.
function AL.OpenActionLiteDebug()
    return ns.Try("Control window", UI.Show)
end
function AL.OpenDebug() return AL.OpenActionLiteDebug() end
function AL.ToggleDebug()
    return ns.Try("Control window", function()
        if main and main:IsShown() then UI.Hide() else UI.Show() end
    end)
end
