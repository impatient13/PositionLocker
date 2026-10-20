local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============ CONFIG ============
local CHECK_INTERVAL    = 0.15
local DEFAULT_TOLERANCE = 0.35
local SNAP_TWEEN_TIME   = 0.08
local DOCK_ICON_SIZE    = 48
local CREDIT            = "dev by vyv"
local ANTIAFK_INTERVAL  = 60
local ANTIAFK_MODE      = "jump"            -- "jump" | "click" | "look"
local ANTIAFK_HOTKEY    = Enum.KeyCode.F8   -- toggle anti-AFK from anywhere

-- ============ STATE ============
local anchorCFrame    = nil
local locked          = false
local ENABLE_WATCHDOG = true
local DRIFT_TOLERANCE = DEFAULT_TOLERANCE
local minimized       = false
local ENABLE_ANTIAFK  = true
local afkAccum        = 0

-- ============ XP LUNA PALETTE ============
local XP = {
    face         = Color3.fromRGB(236, 233, 216),
    titleTop     = Color3.fromRGB(0, 88, 238),
    titleMid     = Color3.fromRGB(30, 120, 240),
    titleBot     = Color3.fromRGB(0, 60, 200),
    borderDark   = Color3.fromRGB(0, 46, 138),
    btnFace      = Color3.fromRGB(236, 233, 216),
    btnHover     = Color3.fromRGB(255, 255, 255),
    btnPress     = Color3.fromRGB(200, 196, 178),
    btnShadow    = Color3.fromRGB(128, 128, 128),
    btnHighlight = Color3.fromRGB(255, 255, 255),
    text         = Color3.fromRGB(0, 0, 0),
    textMuted    = Color3.fromRGB(80, 80, 80),
    green        = Color3.fromRGB(0, 128, 0),
    red          = Color3.fromRGB(180, 0, 0),
    orange       = Color3.fromRGB(224, 120, 0),
    statusBg     = Color3.fromRGB(214, 210, 190),
    taskbar      = Color3.fromRGB(36, 90, 200),
}

-- ============ HELPERS ============
local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(parent, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 0); c.Parent = parent; return c
end

local function gradient(parent, colors, rot)
    local g = Instance.new("UIGradient")
    local keys, n = {}, #colors
    for i, c in ipairs(colors) do
        table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, n - 1), c))
    end
    g.Color = ColorSequence.new(keys); g.Rotation = rot or 90
    g.Parent = parent; return g
end

local function makeXPButton(parent, text, size, pos, anchor)
    local btn = new("TextButton", {
        Size = size, Position = pos,
        AnchorPoint = anchor or Vector2.new(0, 0),
        BackgroundColor3 = XP.btnFace, BorderSizePixel = 0,
        Text = "", AutoButtonColor = false,
        ClipsDescendants = true, ZIndex = 3,
    }, parent)
    new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = XP.btnShadow, BorderSizePixel = 0, ZIndex = 2 }, btn)
    local face = new("Frame", { Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1), BackgroundColor3 = XP.btnFace, BorderSizePixel = 0, ZIndex = 3 }, btn)
    local highlight = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = XP.btnHighlight, BorderSizePixel = 0, BackgroundTransparency = 0.25, ZIndex = 4 }, face)
    local shadow = new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = XP.btnShadow, BorderSizePixel = 0, ZIndex = 5 }, face)
    local label = new("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = text, TextColor3 = XP.text, Font = Enum.Font.SourceSansBold, TextSize = 13, ZIndex = 6 }, face)
    btn.MouseEnter:Connect(function() if not btn:GetAttribute("Pressed") then face.BackgroundColor3 = XP.btnHover end end)
    btn.MouseLeave:Connect(function() if not btn:GetAttribute("Pressed") then face.BackgroundColor3 = XP.btnFace end end)
    btn.MouseButton1Down:Connect(function() btn:SetAttribute("Pressed", true); face.BackgroundColor3 = XP.btnPress; highlight.Visible = false; shadow.Visible = false end)
    btn.MouseButton1Up:Connect(function() btn:SetAttribute("Pressed", false); face.BackgroundColor3 = XP.btnFace; highlight.Visible = true; shadow.Visible = true end)
    btn:SetAttribute("Pressed", false)
    return btn, label
end

local function makeChromeButton(parent, glyph, baseColor, size, pos)
    local b = new("TextButton", {
        Size = size, Position = pos, BackgroundColor3 = baseColor,
        BorderSizePixel = 1, BorderColor3 = XP.borderDark,
        Text = glyph, TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold, TextSize = 14,
        AutoButtonColor = false, ZIndex = 7,
    }, parent)
    corner(b, 3)
    new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 8 }, b)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = baseColor:Lerp(Color3.new(1,1,1), 0.3) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = baseColor end)
    return b
end

-- ============ ROOT ============
local screenGui = new("ScreenGui", {
    Name = "XP_PositionLocker", ResetOnSpawn = false,
    IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- ============ MAIN WINDOW ============
local window = new("Frame", {
    Name = "XPMainWindow",
    Size = UDim2.new(0, 340, 0, 260),
    Position = UDim2.new(0, 60, 0, 60),
    BackgroundColor3 = XP.borderDark, BorderSizePixel = 0,
    Active = true, Draggable = true,
    ClipsDescendants = true, ZIndex = 5,
}, screenGui)
new("Frame", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = XP.face, BorderSizePixel = 0, ZIndex = 6 }, window)

local titleBar = new("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, -4, 0, 26), Position = UDim2.new(0, 2, 0, 2),
    BackgroundColor3 = XP.titleMid, BorderSizePixel = 0, ZIndex = 7,
}, window)
corner(titleBar, 4)
gradient(titleBar, { XP.titleTop, XP.titleMid, XP.titleBot }, 90)
new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = XP.borderDark, BorderSizePixel = 0, ZIndex = 8 }, titleBar)
new("TextLabel", {
    Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 8, 0, 0),
    BackgroundTransparency = 1, Text = "Position Locker — Setup",
    TextColor3 = Color3.fromRGB(255,255,255),
    Font = Enum.Font.SourceSansBold, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
}, titleBar)

local minBtn   = makeChromeButton(titleBar, "—", Color3.fromRGB(70, 130, 220), UDim2.new(0, 22, 0, 18), UDim2.new(1, -52, 0, 4))
local closeBtn = makeChromeButton(titleBar, "×", Color3.fromRGB(210, 60, 50), UDim2.new(0, 22, 0, 18), UDim2.new(1, -26, 0, 4))

local body = new("Frame", {
    Size = UDim2.new(1, -16, 1, -80), Position = UDim2.new(0, 8, 0, 34),
    BackgroundTransparency = 1, ZIndex = 7,
}, window)

local statusLabel = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
    Text = "Status: idle", TextColor3 = XP.text,
    Font = Enum.Font.SourceSansBold, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8,
}, body)

local afkStatusLabel = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 18),
    BackgroundTransparency = 1,
    Text = "Anti-AFK: ON  [F8]", TextColor3 = XP.green,
    Font = Enum.Font.SourceSans, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8,
}, body)

local coordsLabel = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 36),
    BackgroundTransparency = 1, Text = "Anchor: (none)\nLive:   (no character)",
    TextColor3 = XP.text, Font = Enum.Font.Code, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 8,
}, body)

local buttonRow = new("Frame", {
    Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -30),
    BackgroundTransparency = 1, ZIndex = 8,
}, body)
local setupBtn, _ = makeXPButton(buttonRow, "Setup", UDim2.new(0, 110, 1, 0), UDim2.new(0, 0, 0, 0))
local setBtn, _   = makeXPButton(buttonRow, "Set",   UDim2.new(0, 110, 1, 0), UDim2.new(1, -110, 0, 0), Vector2.new(1, 0))

local statusBar = new("Frame", {
    Size = UDim2.new(1, -4, 0, 20), Position = UDim2.new(0, 2, 1, -22),
    BackgroundColor3 = XP.statusBg, BorderSizePixel = 1, BorderColor3 = XP.borderDark, ZIndex = 7,
}, window)
new("TextLabel", {
    Size = UDim2.new(1, -80, 1, 0), Position = UDim2.new(0, 4, 0, 0),
    BackgroundTransparency = 1, Text = "Ready", TextColor3 = XP.textMuted,
    Font = Enum.Font.SourceSans, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8,
}, statusBar)
new("TextLabel", {
    Size = UDim2.new(0, 76, 1, 0), Position = UDim2.new(1, -80, 0, 0),
    BackgroundTransparency = 1, Text = CREDIT, TextColor3 = XP.textMuted,
    Font = Enum.Font.SourceSansItalic, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8,
}, statusBar)

-- ============ SETUP SUB-WINDOW ============
local setupWindow = new("Frame", {
    Name = "XPSetupWindow",
    Size = UDim2.new(0, 300, 0, 220),
    Position = UDim2.new(0, 420, 0, 60),
    BackgroundColor3 = XP.borderDark, BorderSizePixel = 0,
    Active = true, Draggable = true,
    Visible = false, ClipsDescendants = true, ZIndex = 5,
}, screenGui)
new("Frame", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = XP.face, BorderSizePixel = 0, ZIndex = 6 }, setupWindow)

local setupTitle = new("Frame", {
    Size = UDim2.new(1, -4, 0, 26), Position = UDim2.new(0, 2, 0, 2),
    BackgroundColor3 = XP.titleMid, BorderSizePixel = 0, ZIndex = 7,
}, setupWindow)
corner(setupTitle, 4)
gradient(setupTitle, { XP.titleTop, XP.titleMid, XP.titleBot }, 90)
new("TextLabel", {
    Size = UDim2.new(1, -30, 1, 0), Position = UDim2.new(0, 8, 0, 0),
    BackgroundTransparency = 1, Text = "Position Locker — Options",
    TextColor3 = Color3.fromRGB(255,255,255),
    Font = Enum.Font.SourceSansBold, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8,
}, setupTitle)
local setupClose = makeChromeButton(setupTitle, "×", Color3.fromRGB(210, 60, 50), UDim2.new(0, 22, 0, 18), UDim2.new(1, -26, 0, 4))

local setupBody = new("Frame", {
    Size = UDim2.new(1, -16, 1, -52), Position = UDim2.new(0, 8, 0, 32),
    BackgroundTransparency = 1, ZIndex = 7,
}, setupWindow)

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
    Text = "Drift tolerance (studs):", TextColor3 = XP.text,
    Font = Enum.Font.SourceSans, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8,
}, setupBody)

local tolBox = new("TextBox", {
    Size = UDim2.new(0, 80, 0, 22), Position = UDim2.new(0, 0, 0, 20),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 1, BorderColor3 = XP.borderDark,
    Text = tostring(DRIFT_TOLERANCE), TextColor3 = XP.text,
    Font = Enum.Font.Code, TextSize = 13,
    ClearTextOnFocus = false, ZIndex = 8,
}, setupBody)
tolBox.FocusLost:Connect(function()
    local n = tonumber(tolBox.Text)
    if n and n >= 0 then DRIFT_TOLERANCE = n end
    tolBox.Text = tostring(DRIFT_TOLERANCE)
end)

local toggleBtn, toggleLbl = makeXPButton(setupBody, "Watchdog: ON", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 50))
toggleBtn.MouseButton1Click:Connect(function()
    ENABLE_WATCHDOG = not ENABLE_WATCHDOG
    toggleLbl.Text = "Watchdog: " .. (ENABLE_WATCHDOG and "ON" or "OFF")
end)

-- anti-AFK button + shared setter
local afkBtn, afkLbl = makeXPButton(setupBody, "Anti-AFK: ON", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 82))

local function setAntiAfk(enabled)
    ENABLE_ANTIAFK = enabled
    afkLbl.Text = "Anti-AFK: " .. (enabled and "ON" or "OFF")
    afkStatusLabel.Text = "Anti-AFK: " .. (enabled and "ON" or "OFF") .. "  [F8]"
    afkStatusLabel.TextColor3 = enabled and XP.green or XP.red
end

local function toggleAntiAfk()
    setAntiAfk(not ENABLE_ANTIAFK)
end

afkBtn.MouseButton1Click:Connect(toggleAntiAfk)

local clearBtn, _ = makeXPButton(setupBody, "Clear Anchor", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 114))
clearBtn.MouseButton1Click:Connect(function()
    anchorCFrame = nil; locked = false
    statusLabel.Text = "Status: idle — anchor cleared"
    statusLabel.TextColor3 = XP.orange
end)

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -16),
    BackgroundTransparency = 1, Text = CREDIT, TextColor3 = XP.textMuted,
    Font = Enum.Font.SourceSansItalic, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8,
}, setupBody)

-- ============ DOCK ICON ============
local dockIcon = new("TextButton", {
    Name = "XPDockIcon",
    Size = UDim2.new(0, DOCK_ICON_SIZE, 0, DOCK_ICON_SIZE),
    Position = UDim2.new(0, 8, 0.5, -DOCK_ICON_SIZE / 2),
    BackgroundColor3 = XP.taskbar, BorderSizePixel = 1, BorderColor3 = XP.borderDark,
    Text = "", AutoButtonColor = false, Visible = false, ZIndex = 20,
}, screenGui)
corner(dockIcon, 6)
new("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 140, 240)),
        ColorSequenceKeypoint.new(1, XP.taskbar),
    }), Rotation = 90,
}, dockIcon)
new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 2),
    BackgroundTransparency = 1, Text = "PL",
    TextColor3 = Color3.fromRGB(255,255,255),
    Font = Enum.Font.SourceSansBold, TextSize = 18, ZIndex = 21,
}, dockIcon)
new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -14),
    BackgroundTransparency = 1, Text = "vyv",
    TextColor3 = Color3.fromRGB(255,255,255),
    Font = Enum.Font.SourceSansItalic, TextSize = 9, ZIndex = 21,
}, dockIcon)
dockIcon.MouseEnter:Connect(function() dockIcon.BackgroundColor3 = XP.taskbar:Lerp(Color3.new(1,1,1), 0.2) end)
dockIcon.MouseLeave:Connect(function() dockIcon.BackgroundColor3 = XP.taskbar end)

-- ============ MINIMIZE / RESTORE ============
local function minimizeWindow()
    minimized = true
    window.Visible = false
    setupWindow.Visible = false
    dockIcon.Visible = true
end
local function restoreWindow()
    minimized = false
    window.Visible = true
    dockIcon.Visible = false
end
minBtn.MouseButton1Click:Connect(minimizeWindow)
dockIcon.MouseButton1Click:Connect(restoreWindow)

-- ============ CLOSE = KILL LOCK + ANTI-AFK ============
closeBtn.MouseButton1Click:Connect(function()
    locked = false
    anchorCFrame = nil
    ENABLE_WATCHDOG = false
    setAntiAfk(false)
    window.Visible = false
    setupWindow.Visible = false
    dockIcon.Visible = false
    minimized = false
    statusLabel.Text = "Status: killed — lock released"
    statusLabel.TextColor3 = XP.red
end)

-- ============ SETUP TOGGLE ============
setupBtn.MouseButton1Click:Connect(function()
    setupWindow.Visible = not setupWindow.Visible
end)
setupClose.MouseButton1Click:Connect(function()
    setupWindow.Visible = false
end)

-- ============ SET (anchor) ============
local function getCharacterCFrame()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.CFrame end
    local pp = char.PrimaryPart
    return pp and pp.CFrame or nil
end

setBtn.MouseButton1Click:Connect(function()
    local cf = getCharacterCFrame()
    if not cf then
        statusLabel.Text = "Status: no character to anchor"
        statusLabel.TextColor3 = XP.red
        return
    end
    anchorCFrame = cf; locked = true
    statusLabel.Text = "Status: anchored"
    statusLabel.TextColor3 = XP.green
end)

-- ============ WATCHDOG ============
local lastCheck = 0
RunService.Heartbeat:Connect(function(dt)
    if not ENABLE_WATCHDOG then return end
    lastCheck += dt
    if lastCheck < CHECK_INTERVAL then return end
    lastCheck = 0

    local char = player.Character
    if not char then
        coordsLabel.Text = "Anchor: " .. (anchorCFrame and string.format("(%.0f, %.0f, %.0f)", anchorCFrame.X, anchorCFrame.Y, anchorCFrame.Z) or "(none)") .. "\nLive:   (no character)"
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local liveCF = hrp.CFrame

    coordsLabel.Text = string.format(
        "Anchor: %s\nLive:   (%.0f, %.0f, %.0f)",
        anchorCFrame and string.format("(%.0f, %.0f, %.0f)", anchorCFrame.X, anchorCFrame.Y, anchorCFrame.Z) or "(none)",
        liveCF.X, liveCF.Y, liveCF.Z
    )

    if not locked or not anchorCFrame then return end
    if (liveCF.Position - anchorCFrame.Position).Magnitude > DRIFT_TOLERANCE then
        if SNAP_TWEEN_TIME > 0 then
            TweenService:Create(hrp,
                TweenInfo.new(SNAP_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                { CFrame = anchorCFrame }):Play()
        else
            hrp.CFrame = anchorCFrame
        end
    end
end)

-- ============ ANTI-AFK ============
local function antiafkNudge()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    if ANTIAFK_MODE == "jump" then
        if hum:GetState() == Enum.HumanoidStateType.Seated then
            hum.Sit = false
        end
        hum.Jump = true
    elseif ANTIAFK_MODE == "click" then
        pcall(function()
            local VU = game:GetService("VirtualUser")
            VU:CaptureController()
            VU:ClickButton2(Vector2.new(0, 0))
        end)
    elseif ANTIAFK_MODE == "look" then
        local cam = workspace.CurrentCamera
        if cam then
            cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(0.1), 0)
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    if not ENABLE_ANTIAFK then return end
    afkAccum += dt
    if afkAccum >= ANTIAFK_INTERVAL then
        afkAccum = 0
        pcall(antiafkNudge)
    end
end)

-- ============ INPUT: hotkey + real-input reset ============
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == ANTIAFK_HOTKEY then
        toggleAntiAfk()
        return
    end
    if input.UserInputType == Enum.UserInputType.Keyboard
    or input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.MouseButton2
    or input.UserInputType == Enum.UserInputType.Touch then
        afkAccum = 0
    end
end)

print("[PositionLocker v5] charted — dev by vyv. anti-afk: " .. ANTIAFK_MODE .. " | hotkey: F8")
