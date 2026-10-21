--========================================================
--  Position Locker v6 — Windows XP (Luna) edition
--  dev by vyv
--========================================================
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
local menuOpen        = false
local alive           = true

local conns = {}
local function track(conn)
    conns[#conns + 1] = conn
    return conn
end

-- ============ XP LUNA PALETTE ============
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local C = {
    face        = rgb(236, 233, 216),
    white       = rgb(255, 255, 255),
    text        = rgb(0, 0, 0),
    muted       = rgb(90, 90, 90),
    navy        = rgb(0, 24, 120),
    frame       = rgb(0, 84, 227),
    etch        = rgb(172, 168, 153),
    groupLine   = rgb(208, 208, 191),
    groupTitle  = rgb(0, 70, 213),
    inputBorder = rgb(127, 157, 185),
    checkBorder = rgb(28, 81, 128),
    checkGreen  = rgb(33, 161, 33),
    sel         = rgb(49, 106, 197),
    green       = rgb(0, 128, 0),
    red         = rgb(180, 0, 0),
    orange      = rgb(224, 120, 0),
}

local FONT      = Enum.Font.Arial
local FONT_B    = Enum.Font.ArialBold
local FONT_MONO = Enum.Font.Code

-- ============ HELPERS ============
local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 0)
    c.Parent = parent
    return c
end

-- points = { {t, Color3}, ... }  (t de 0 à 1)
local function seq(points)
    local kp = {}
    for _, p in ipairs(points) do
        kp[#kp + 1] = ColorSequenceKeypoint.new(p[1], p[2])
    end
    return ColorSequence.new(kp)
end

local function gradient(parent, points, rot)
    return new("UIGradient", { Color = seq(points), Rotation = rot or 90 }, parent)
end

local function label(parent, text, props)
    local p = {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Text = text, TextColor3 = C.text,
        Font = FONT, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return new("TextLabel", p, parent)
end

local function hitArea(parent, z)
    return new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false, BorderSizePixel = 0, ZIndex = z or 10,
    }, parent)
end

local function makeDraggable(handle, target)
    local dragging, dragStart, startPos = false, nil, nil
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = target.Position
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

-- ============ BOUTON XP (push button Luna) ============
local BTN = {
    normal = {
        ring = { {0, rgb(255, 255, 255)}, {1, rgb(214, 208, 197)} },
        face = { {0, rgb(255, 255, 255)}, {0.85, rgb(236, 235, 230)}, {1, rgb(214, 208, 197)} },
    },
    hover = {
        ring = { {0, rgb(255, 240, 207)}, {0.5, rgb(250, 200, 95)}, {1, rgb(248, 179, 48)} },
        face = { {0, rgb(255, 255, 255)}, {0.85, rgb(236, 235, 230)}, {1, rgb(214, 208, 197)} },
    },
    press = {
        ring = { {0, rgb(190, 186, 170)}, {1, rgb(222, 218, 204)} },
        face = { {0, rgb(205, 202, 190)}, {1, rgb(227, 225, 212)} },
    },
    default = {
        ring = { {0, rgb(206, 231, 255)}, {1, rgb(136, 176, 250)} },
        face = { {0, rgb(255, 255, 255)}, {0.85, rgb(236, 235, 230)}, {1, rgb(214, 208, 197)} },
    },
}

-- retourne: hit (TextButton pour les events), lbl (TextLabel), outer (Frame)
local function makeXPButton(parent, text, size, pos, opts)
    opts = opts or {}
    local outer = new("Frame", {
        Size = size, Position = pos,
        AnchorPoint = opts.anchor or Vector2.new(0, 0),
        BackgroundColor3 = rgb(0, 60, 116), BorderSizePixel = 0,
    }, parent)
    corner(outer, 3)

    local ring = new("Frame", {
        Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1),
        BackgroundColor3 = C.white, BorderSizePixel = 0,
    }, outer)
    corner(ring, 2)
    local ringG = gradient(ring, BTN.normal.ring)

    local face = new("Frame", {
        Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2),
        BackgroundColor3 = C.white, BorderSizePixel = 0,
    }, ring)
    corner(face, 1)
    local faceG = gradient(face, BTN.normal.face)

    local lbl = label(face, text, {
        Size = UDim2.new(1, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local hit = hitArea(outer)

    local inside, down = false, false
    local function apply()
        local s
        if down and inside then s = BTN.press
        elseif inside then s = BTN.hover
        elseif opts.default then s = BTN.default
        else s = BTN.normal end
        ringG.Color = seq(s.ring)
        faceG.Color = seq(s.face)
    end
    apply()

    track(hit.MouseEnter:Connect(function() inside = true; apply() end))
    track(hit.MouseLeave:Connect(function() inside = false; apply() end))
    track(hit.MouseButton1Down:Connect(function() down = true; apply() end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if down then down = false; apply() end
        end
    end))

    return hit, lbl, outer
end

-- ============ BOUTONS DE BARRE DE TITRE (réduire / fermer) ============
local CHROME = {
    blue = {
        normal = { {0, rgb(114, 166, 250)}, {0.5, rgb(52, 112, 238)}, {1, rgb(34, 86, 210)} },
        hover  = { {0, rgb(160, 196, 255)}, {0.5, rgb(92, 148, 248)}, {1, rgb(60, 114, 226)} },
    },
    red = {
        normal = { {0, rgb(234, 150, 124)}, {0.5, rgb(214, 76, 44)}, {1, rgb(190, 52, 26)} },
        hover  = { {0, rgb(250, 184, 160)}, {0.5, rgb(238, 110, 76)}, {1, rgb(212, 78, 48)} },
    },
}

local function makeChromeButton(parent, kind, pos)
    local scheme = (kind == "close") and CHROME.red or CHROME.blue

    local outer = new("Frame", {
        Size = UDim2.new(0, 21, 0, 21), Position = pos,
        BackgroundColor3 = C.white, BorderSizePixel = 0,
    }, parent)
    corner(outer, 4)

    local face = new("Frame", {
        Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1),
        BackgroundColor3 = C.white, BorderSizePixel = 0,
    }, outer)
    corner(face, 3)
    local g = gradient(face, scheme.normal)

    if kind == "min" then
        new("Frame", {
            Size = UDim2.new(0, 8, 0, 3), Position = UDim2.new(0, 5, 0, 11),
            BackgroundColor3 = C.white, BorderSizePixel = 0,
        }, face)
    else
        for _, rot in ipairs({ 45, -45 }) do
            new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.new(0, 2, 0, 11),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Rotation = rot,
                BackgroundColor3 = C.white, BorderSizePixel = 0,
            }, face)
        end
    end

    local hit = hitArea(outer)
    track(hit.MouseEnter:Connect(function() g.Color = seq(scheme.hover) end))
    track(hit.MouseLeave:Connect(function() g.Color = seq(scheme.normal) end))
    return hit
end

-- ============ GROUPBOX / CHECKBOX / TEXTBOX ============
local function makeGroup(parent, title, size, pos)
    local sh = new("Frame", {
        Size = size, Position = pos + UDim2.new(0, 1, 0, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
    }, parent)
    corner(sh, 4)
    new("UIStroke", { Color = C.white, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sh)

    local g = new("Frame", {
        Size = size, Position = pos,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
    }, parent)
    corner(g, 4)
    new("UIStroke", { Color = C.groupLine, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, g)

    local t = label(g, title, {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 0, 14), Position = UDim2.new(0, 8, 0, -7),
        BackgroundTransparency = 0, BackgroundColor3 = C.face,
        TextColor3 = C.groupTitle,
    })
    new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) }, t)
    return g
end

local function makeCheckbox(parent, text, pos, width, onChange)
    local holder = new("Frame", {
        Size = UDim2.new(1, width, 0, 15), Position = pos,
        BackgroundTransparency = 1, BorderSizePixel = 0,
    }, parent)

    local box = new("Frame", {
        Size = UDim2.new(0, 13, 0, 13), Position = UDim2.new(0, 0, 0, 1),
        BackgroundColor3 = C.checkBorder, BorderSizePixel = 0,
    }, holder)
    local inner = new("Frame", {
        Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1),
        BackgroundColor3 = C.white, BorderSizePixel = 0,
    }, box)
    gradient(inner, { {0, rgb(220, 220, 215)}, {1, rgb(255, 255, 255)} }, 45)

    local check = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        BorderSizePixel = 0, Visible = false,
    }, inner)
    new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 2, 0, 4),
        Position = UDim2.new(0, 3, 0, 6), Rotation = -45,
        BackgroundColor3 = C.checkGreen, BorderSizePixel = 0,
    }, check)
    new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 2, 0, 6),
        Position = UDim2.new(0, 7, 0, 5), Rotation = 45,
        BackgroundColor3 = C.checkGreen, BorderSizePixel = 0,
    }, check)

    label(holder, text, {
        Position = UDim2.new(0, 19, 0, 0), Size = UDim2.new(1, -19, 1, 0),
    })

    local api = { state = false }
    function api.set(v)
        api.state = v and true or false
        check.Visible = api.state
    end

    local hit = hitArea(holder)
    track(hit.MouseButton1Click:Connect(function()
        onChange(not api.state)
    end))
    return api
end

-- ============ ROOT ============
local screenGui = new("ScreenGui", {
    Name = "XP_PositionLocker", ResetOnSpawn = false,
    IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- ============ FENÊTRE XP (cadre Luna + barre de titre) ============
local function makeWindow(name, title, size, pos, z, canMinimize)
    local window = new("Frame", {
        Name = name, Size = size, Position = pos,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z,
    }, screenGui)

    -- bas carré (seul le haut est arrondi dans Luna)
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12),
        BackgroundColor3 = C.navy, BorderSizePixel = 0, ZIndex = 1,
    }, window)
    local outer = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = C.navy, BorderSizePixel = 0, ZIndex = 2,
    }, window)
    corner(outer, 8)

    new("Frame", {
        Size = UDim2.new(1, -2, 0, 12), Position = UDim2.new(0, 1, 1, -13),
        BackgroundColor3 = C.frame, BorderSizePixel = 0, ZIndex = 1,
    }, outer)
    local frame = new("Frame", {
        Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1),
        BackgroundColor3 = C.frame, BorderSizePixel = 0, ZIndex = 2,
    }, outer)
    corner(frame, 7)

    local titleBar = new("Frame", {
        Name = "TitleBar", Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = C.white, BorderSizePixel = 0, ZIndex = 2,
    }, frame)
    corner(titleBar, 7)
    gradient(titleBar, {
        {0,   rgb(61, 149, 255)},
        {0.1, rgb(0, 98, 244)},
        {0.5, rgb(0, 84, 227)},
        {0.9, rgb(0, 72, 210)},
        {1,   rgb(0, 60, 190)},
    })

    -- texte avec ombre portée comme XP
    label(titleBar, title, {
        Position = UDim2.new(0, 9, 0, 1), Size = UDim2.new(1, -90, 1, 0),
        Font = FONT_B, TextSize = 13, TextColor3 = rgb(10, 24, 100),
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 1,
    })
    label(titleBar, title, {
        Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(1, -90, 1, 0),
        Font = FONT_B, TextSize = 13, TextColor3 = C.white,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
    })

    local minHit
    if canMinimize then
        minHit = makeChromeButton(titleBar, "min", UDim2.new(1, -49, 0, 4))
    end
    local closeHit = makeChromeButton(titleBar, "close", UDim2.new(1, -26, 0, 4))

    local client = new("Frame", {
        Name = "Client", Size = UDim2.new(1, -6, 1, -31), Position = UDim2.new(0, 3, 0, 28),
        BackgroundColor3 = C.face, BorderSizePixel = 0, ZIndex = 2,
    }, frame)

    makeDraggable(titleBar, window)
    return window, client, minHit, closeHit
end

-- ============ FENÊTRE PRINCIPALE ============
local window, client, minHit, closeHit = makeWindow(
    "XPMainWindow", "Position Locker — Setup",
    UDim2.new(0, 340, 0, 203), UDim2.new(0, 60, 0, 60), 1, true)

local statusGroup = makeGroup(client, "Status", UDim2.new(1, -16, 0, 96), UDim2.new(0, 8, 0, 14))

local statusLabel = label(statusGroup, "Status: idle", {
    Position = UDim2.new(0, 10, 0, 14), Size = UDim2.new(1, -20, 0, 16),
    Font = FONT_B, TextSize = 12,
})
local afkStatusLabel = label(statusGroup, "Anti-AFK: ON  [F8]", {
    Position = UDim2.new(0, 10, 0, 32), Size = UDim2.new(1, -20, 0, 14),
    TextSize = 11, TextColor3 = C.green,
})
local coordsLabel = label(statusGroup, "Anchor: (none)\nLive:   (no character)", {
    Position = UDim2.new(0, 10, 0, 52), Size = UDim2.new(1, -20, 0, 36),
    Font = FONT_MONO, TextSize = 12,
    TextYAlignment = Enum.TextYAlignment.Top,
})

local setupHit = makeXPButton(client, "Setup", UDim2.new(0, 100, 0, 23), UDim2.new(0, 8, 0, 122))
local setHit   = makeXPButton(client, "Set",   UDim2.new(0, 100, 0, 23), UDim2.new(1, -8, 0, 122),
    { anchor = Vector2.new(1, 0), default = true })

-- barre d'état
local statusBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22),
    BackgroundColor3 = C.face, BorderSizePixel = 0,
}, client)
new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.etch, BorderSizePixel = 0 }, statusBar)
label(statusBar, "Ready", {
    Position = UDim2.new(0, 8, 0, 2), Size = UDim2.new(1, -120, 1, -3), TextColor3 = C.text,
})
-- séparateur gravé
new("Frame", { Size = UDim2.new(0, 1, 1, -6), Position = UDim2.new(1, -106, 0, 4), BackgroundColor3 = C.etch, BorderSizePixel = 0 }, statusBar)
new("Frame", { Size = UDim2.new(0, 1, 1, -6), Position = UDim2.new(1, -105, 0, 4), BackgroundColor3 = C.white, BorderSizePixel = 0 }, statusBar)
label(statusBar, CREDIT, {
    Position = UDim2.new(1, -100, 0, 2), Size = UDim2.new(0, 78, 1, -3),
    Font = Enum.Font.ArialBold, TextSize = 11, TextColor3 = C.muted,
    TextXAlignment = Enum.TextXAlignment.Right,
})
-- poignée de redimensionnement (grip)
for c = 0, 2 do
    for r = 0, 2 - c do
        local x = -(3 + 4 * c) - 2
        local y = -(3 + 4 * r) - 2
        new("Frame", { Size = UDim2.new(0, 2, 0, 2), Position = UDim2.new(1, x + 1, 1, y + 1), BackgroundColor3 = C.white, BorderSizePixel = 0 }, statusBar)
        new("Frame", { Size = UDim2.new(0, 2, 0, 2), Position = UDim2.new(1, x, 1, y), BackgroundColor3 = C.etch, BorderSizePixel = 0 }, statusBar)
    end
end

-- ============ FENÊTRE OPTIONS ============
local setupWindow, setupClient, _, setupCloseHit = makeWindow(
    "XPSetupWindow", "Position Locker — Options",
    UDim2.new(0, 300, 0, 238), UDim2.new(0, 420, 0, 60), 2, false)
setupWindow.Visible = false

-- groupe Watchdog
local wdGroup = makeGroup(setupClient, "Watchdog", UDim2.new(1, -16, 0, 86), UDim2.new(0, 8, 0, 14))
label(wdGroup, "Drift tolerance (studs):", {
    Position = UDim2.new(0, 10, 0, 14), Size = UDim2.new(1, -20, 0, 14),
})
local tolWrap = new("Frame", {
    Size = UDim2.new(0, 80, 0, 21), Position = UDim2.new(0, 10, 0, 32),
    BackgroundColor3 = C.inputBorder, BorderSizePixel = 0,
}, wdGroup)
local tolBox = new("TextBox", {
    Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1),
    BackgroundColor3 = C.white, BorderSizePixel = 0,
    Text = tostring(DRIFT_TOLERANCE), TextColor3 = C.text,
    Font = FONT_MONO, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
}, tolWrap)
new("UIPadding", { PaddingLeft = UDim.new(0, 4) }, tolBox)
track(tolBox.FocusLost:Connect(function()
    local n = tonumber(tolBox.Text)
    if n and n >= 0 then DRIFT_TOLERANCE = n end
    tolBox.Text = tostring(DRIFT_TOLERANCE)
end))

local setAntiAfk, setWatchdog

local watchdogCb = makeCheckbox(wdGroup, "Enable watchdog", UDim2.new(0, 10, 0, 62), -20, function(v)
    setWatchdog(v)
end)

-- groupe Anti-AFK
local afkGroup = makeGroup(setupClient, "Anti-AFK", UDim2.new(1, -16, 0, 44), UDim2.new(0, 8, 0, 112))
local afkCb = makeCheckbox(afkGroup, "Enable anti-AFK  [F8]", UDim2.new(0, 10, 0, 18), -20, function(v)
    setAntiAfk(v)
end)

setWatchdog = function(enabled)
    ENABLE_WATCHDOG = enabled
    watchdogCb.set(enabled)
end

setAntiAfk = function(enabled)
    ENABLE_ANTIAFK = enabled
    afkCb.set(enabled)
    afkStatusLabel.Text = "Anti-AFK: " .. (enabled and "ON" or "OFF") .. "  [F8]"
    afkStatusLabel.TextColor3 = enabled and C.green or C.red
end

setWatchdog(ENABLE_WATCHDOG)
setAntiAfk(ENABLE_ANTIAFK)

local clearHit = makeXPButton(setupClient, "Clear Anchor", UDim2.new(0, 100, 0, 23), UDim2.new(0, 8, 0, 168))
local closeOptHit = makeXPButton(setupClient, "Close", UDim2.new(0, 80, 0, 23), UDim2.new(1, -8, 0, 168),
    { anchor = Vector2.new(1, 0), default = true })

label(setupClient, CREDIT, {
    Position = UDim2.new(0, 10, 1, -18), Size = UDim2.new(1, -20, 0, 14),
    Font = Enum.Font.ArialBold, TextSize = 11, TextColor3 = C.muted,
    TextXAlignment = Enum.TextXAlignment.Right,
})

-- ============ BARRE DES TÂCHES ============
local TB_H = 30
local taskbar = new("Frame", {
    Name = "Taskbar", Size = UDim2.new(1, 0, 0, TB_H), Position = UDim2.new(0, 0, 1, -TB_H),
    BackgroundColor3 = C.white, BorderSizePixel = 0, ZIndex = 60,
}, screenGui)
gradient(taskbar, {
    {0,    rgb(66, 136, 244)},
    {0.08, rgb(36, 94, 220)},
    {0.9,  rgb(30, 84, 208)},
    {1,    rgb(20, 58, 168)},
})

-- bouton Démarrer
local START = {
    normal = { {0, rgb(114, 200, 106)}, {0.15, rgb(70, 168, 60)}, {0.8, rgb(52, 140, 44)}, {1, rgb(36, 108, 30)} },
    hover  = { {0, rgb(150, 222, 140)}, {0.15, rgb(94, 190, 84)}, {0.8, rgb(68, 160, 58)}, {1, rgb(46, 124, 40)} },
    open   = { {0, rgb(40, 104, 34)}, {0.5, rgb(52, 124, 44)}, {1, rgb(60, 136, 50)} },
}
local startBtn = new("Frame", {
    Size = UDim2.new(0, 104, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
}, taskbar)
local startMain = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.white, BorderSizePixel = 0 }, startBtn)
corner(startMain, 12)
local startSq = new("Frame", { Size = UDim2.new(0, 16, 1, 0), BackgroundColor3 = C.white, BorderSizePixel = 0 }, startBtn)
local startG1 = gradient(startMain, START.normal)
local startG2 = gradient(startSq, START.normal)

-- logo (4 carrés colorés)
local logo = new("Frame", { Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, 12, 0.5, -8), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, startBtn)
local logoCols = { rgb(240, 80, 40), rgb(120, 200, 60), rgb(30, 130, 240), rgb(255, 200, 0) }
for i = 0, 3 do
    new("Frame", {
        Size = UDim2.new(0, 7, 0, 7),
        Position = UDim2.new(0, (i % 2) * 9, 0, math.floor(i / 2) * 9),
        BackgroundColor3 = logoCols[i + 1], BorderSizePixel = 0,
    }, logo)
end
local startText = label(startBtn, "start", {
    Position = UDim2.new(0, 34, 0, 0), Size = UDim2.new(1, -38, 1, 0),
    TextColor3 = C.white, TextSize = 22, ZIndex = 3,
})
pcall(function()
    startText.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
end)

local startHit = hitArea(startBtn, 10)
local startHover = false
local function startApply()
    local s = menuOpen and START.open or (startHover and START.hover or START.normal)
    startG1.Color = seq(s); startG2.Color = seq(s)
end
track(startHit.MouseEnter:Connect(function() startHover = true; startApply() end))
track(startHit.MouseLeave:Connect(function() startHover = false; startApply() end))

-- bouton de tâche (fenêtre principale)
local TASK = {
    inactive = { {0, rgb(90, 150, 248)}, {0.5, rgb(54, 118, 238)}, {1, rgb(40, 98, 220)} },
    hover    = { {0, rgb(120, 174, 252)}, {0.5, rgb(76, 138, 246)}, {1, rgb(56, 116, 232)} },
    active   = { {0, rgb(24, 64, 170)}, {0.5, rgb(30, 80, 196)}, {1, rgb(38, 92, 212)} },
}
local taskOuter = new("Frame", {
    Size = UDim2.new(0, 170, 0, 24), Position = UDim2.new(0, 112, 0, 3),
    BackgroundColor3 = rgb(10, 40, 130), BorderSizePixel = 0, ZIndex = 2,
}, taskbar)
corner(taskOuter, 4)
local taskFace = new("Frame", {
    Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1),
    BackgroundColor3 = C.white, BorderSizePixel = 0,
}, taskOuter)
corner(taskFace, 3)
local taskG = gradient(taskFace, TASK.inactive)
-- mini icône
local taskIcon = new("Frame", { Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 6, 0.5, -7), BackgroundColor3 = C.white, BorderSizePixel = 0 }, taskFace)
corner(taskIcon, 2)
new("Frame", { Size = UDim2.new(1, -2, 1, -2), Position = UDim2.new(0, 1, 0, 1), BackgroundColor3 = rgb(0, 84, 227), BorderSizePixel = 0 }, taskIcon)
label(taskFace, "Position Locker", {
    Position = UDim2.new(0, 26, 0, 0), Size = UDim2.new(1, -30, 1, 0),
    TextColor3 = C.white, Font = FONT,
})
local taskHit = hitArea(taskOuter, 10)
local taskHover = false
local function refreshTask()
    local s = window.Visible and TASK.active or (taskHover and TASK.hover or TASK.inactive)
    taskG.Color = seq(s)
end
track(taskHit.MouseEnter:Connect(function() taskHover = true; refreshTask() end))
track(taskHit.MouseLeave:Connect(function() taskHover = false; refreshTask() end))

-- zone de notification (horloge)
local tray = new("Frame", {
    Size = UDim2.new(0, 84, 1, 0), Position = UDim2.new(1, -84, 0, 0),
    BackgroundColor3 = C.white, BorderSizePixel = 0, ZIndex = 2,
}, taskbar)
gradient(tray, {
    {0,   rgb(26, 152, 246)},
    {0.1, rgb(16, 128, 236)},
    {0.9, rgb(12, 116, 228)},
    {1,   rgb(8, 96, 200)},
})
new("Frame", { Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = rgb(10, 60, 160), BorderSizePixel = 0 }, tray)
local clockLabel = label(tray, "00:00", {
    Size = UDim2.new(1, 0, 1, 0), TextColor3 = C.white,
    TextXAlignment = Enum.TextXAlignment.Center,
})

task.spawn(function()
    while alive and screenGui.Parent do
        local ok, txt = pcall(function()
            return DateTime.now():FormatLocalTime("HH:mm", "fr-fr")
        end)
        clockLabel.Text = ok and txt or os.date("%H:%M")
        task.wait(1)
    end
end)

-- ============ MENU DÉMARRER ============
local MENU_W, MENU_H = 220, 150

local menuCatcher = new("TextButton", {
    Size = UDim2.new(1, 0, 1, -TB_H), BackgroundTransparency = 1,
    Text = "", AutoButtonColor = false, Visible = false, ZIndex = 40,
}, screenGui)

local menu = new("Frame", {
    Name = "StartMenu", Size = UDim2.new(0, MENU_W, 0, MENU_H),
    Position = UDim2.new(0, 0, 1, -TB_H - MENU_H),
    BackgroundColor3 = C.white, BorderSizePixel = 0, Visible = false, ZIndex = 61,
}, screenGui)
new("UIStroke", { Color = rgb(0, 40, 140), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, menu)

local function setMenu(open)
    menuOpen = open
    menu.Visible = open
    menuCatcher.Visible = open
    startApply()
end
track(startHit.MouseButton1Click:Connect(function() setMenu(not menuOpen) end))
track(menuCatcher.MouseButton1Click:Connect(function() setMenu(false) end))

-- en-tête bleu
local menuHeader = new("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = C.white, BorderSizePixel = 0 }, menu)
gradient(menuHeader, { {0, rgb(24, 92, 230)}, {0.5, rgb(10, 76, 214)}, {1, rgb(6, 64, 194)} })
local avatar = new("Frame", { Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(0, 8, 0, 6), BackgroundColor3 = C.white, BorderSizePixel = 0 }, menuHeader)
corner(avatar, 4)
local avatarIn = new("Frame", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = rgb(120, 160, 230), BorderSizePixel = 0 }, avatar)
corner(avatarIn, 3)
label(avatarIn, string.upper(string.sub(player.DisplayName, 1, 1)), {
    Size = UDim2.new(1, 0, 1, 0), Font = FONT_B, TextSize = 16, TextColor3 = C.white,
    TextXAlignment = Enum.TextXAlignment.Center,
})
label(menuHeader, player.DisplayName, {
    Position = UDim2.new(0, 46, 0, 0), Size = UDim2.new(1, -52, 1, 0),
    Font = FONT_B, TextSize = 14, TextColor3 = C.white,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
-- liseré orange sous l'en-tête
new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 0, 42), BackgroundColor3 = rgb(240, 150, 50), BorderSizePixel = 0 }, menu)

local function menuItem(y, text, iconColor, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, -8, 0, 34), Position = UDim2.new(0, 4, 0, y),
        BackgroundColor3 = C.sel, BackgroundTransparency = 1, BorderSizePixel = 0,
    }, menu)
    local icon = new("Frame", {
        Size = UDim2.new(0, 24, 0, 24), Position = UDim2.new(0, 8, 0.5, -12),
        BackgroundColor3 = iconColor, BorderSizePixel = 0,
    }, row)
    corner(icon, 4)
    local lbl = label(row, text, {
        Position = UDim2.new(0, 42, 0, 0), Size = UDim2.new(1, -46, 1, 0),
        Font = FONT_B, TextSize = 12,
    })
    local hit = hitArea(row, 10)
    track(hit.MouseEnter:Connect(function() row.BackgroundTransparency = 0; lbl.TextColor3 = C.white end))
    track(hit.MouseLeave:Connect(function() row.BackgroundTransparency = 1; lbl.TextColor3 = C.text end))
    track(hit.MouseButton1Click:Connect(function() setMenu(false); callback() end))
end

-- pied de menu
local menuFooter = new("Frame", { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, -34), BackgroundColor3 = C.white, BorderSizePixel = 0 }, menu)
local footerG = gradient(menuFooter, { {0, rgb(66, 130, 230)}, {1, rgb(40, 100, 214)} })
local footIcon = new("Frame", { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -150, 0.5, -11), BackgroundColor3 = rgb(214, 76, 44), BorderSizePixel = 0 }, menuFooter)
corner(footIcon, 4)
label(footIcon, "×", {
    Size = UDim2.new(1, 0, 1, 0), Font = FONT_B, TextSize = 16, TextColor3 = C.white,
    TextXAlignment = Enum.TextXAlignment.Center,
})
label(menuFooter, "Close Position Locker", {
    Position = UDim2.new(1, -122, 0, 0), Size = UDim2.new(0, 120, 1, 0),
    Font = FONT_B, TextSize = 12, TextColor3 = C.white,
})
local footHit = hitArea(menuFooter, 10)
track(footHit.MouseEnter:Connect(function() footerG.Color = seq({ {0, rgb(100, 156, 246)}, {1, rgb(64, 120, 228)} }) end))
track(footHit.MouseLeave:Connect(function() footerG.Color = seq({ {0, rgb(66, 130, 230)}, {1, rgb(40, 100, 214)} }) end))

-- ============ AFFICHER / RÉDUIRE / RESTAURER ============
local function minimizeWindow()
    minimized = true
    window.Visible = false
    setupWindow.Visible = false
    refreshTask()
end
local function restoreWindow()
    minimized = false
    window.Visible = true
    refreshTask()
end

track(minHit.MouseButton1Click:Connect(minimizeWindow))
track(taskHit.MouseButton1Click:Connect(function()
    if window.Visible then minimizeWindow() else restoreWindow() end
end))

menuItem(48, "Position Locker", rgb(0, 84, 227), restoreWindow)
menuItem(82, "Options", rgb(128, 128, 128), function()
    restoreWindow()
    setupWindow.Visible = true
end)
refreshTask()

-- ============ CLOSE = KILL LOCK + ANTI-AFK ============
local function killAll()
    locked = false
    anchorCFrame = nil
    ENABLE_WATCHDOG = false
    ENABLE_ANTIAFK = false
    alive = false
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    screenGui:Destroy()
    print("[PositionLocker v6] killed — lock released")
end
track(closeHit.MouseButton1Click:Connect(killAll))
track(footHit.MouseButton1Click:Connect(function() setMenu(false); killAll() end))

-- ============ SETUP TOGGLE ============
track(setupHit.MouseButton1Click:Connect(function()
    setupWindow.Visible = not setupWindow.Visible
end))
track(setupCloseHit.MouseButton1Click:Connect(function() setupWindow.Visible = false end))
track(closeOptHit.MouseButton1Click:Connect(function() setupWindow.Visible = false end))

track(clearHit.MouseButton1Click:Connect(function()
    anchorCFrame = nil; locked = false
    statusLabel.Text = "Status: idle — anchor cleared"
    statusLabel.TextColor3 = C.orange
end))

-- ============ SET (anchor) ============
local function getCharacterCFrame()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.CFrame end
    local pp = char.PrimaryPart
    return pp and pp.CFrame or nil
end

track(setHit.MouseButton1Click:Connect(function()
    local cf = getCharacterCFrame()
    if not cf then
        statusLabel.Text = "Status: no character to anchor"
        statusLabel.TextColor3 = C.red
        return
    end
    anchorCFrame = cf; locked = true
    statusLabel.Text = "Status: anchored"
    statusLabel.TextColor3 = C.green
end))

-- ============ WATCHDOG ============
local lastCheck = 0
track(RunService.Heartbeat:Connect(function(dt)
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
end))

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

track(RunService.Heartbeat:Connect(function(dt)
    if not ENABLE_ANTIAFK then return end
    afkAccum += dt
    if afkAccum >= ANTIAFK_INTERVAL then
        afkAccum = 0
        pcall(antiafkNudge)
    end
end))

-- ============ INPUT: hotkey + real-input reset ============
track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == ANTIAFK_HOTKEY then
        setAntiAfk(not ENABLE_ANTIAFK)
        return
    end
    if input.UserInputType == Enum.UserInputType.Keyboard
    or input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.MouseButton2
    or input.UserInputType == Enum.UserInputType.Touch then
        afkAccum = 0
    end
end))

print("[PositionLocker v6 XP] loaded — dev by vyv. anti-afk: " .. ANTIAFK_MODE .. " | hotkey: F8")
