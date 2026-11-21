--[[ Rudra's Ragebot — Gun + Melee + Throwable (+ Custom passthrough)
     Tabs: Rage | Weapon | Spoofer
     Rage supports Gun / Melee / Throwable
     Weapon tab has Auto Load dropdown with search
     Spoofer tab has Device Spoofer toggle + dropdown (VR/Console/Mobile/PC)
     Bubble opens with "R", close animates to bubble
     Palette: black / gold / purple
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local UserInputService  = game:GetService("UserInputService")

local LP = Players.LocalPlayer

-- ── Palette ────────────────────────────────────────────────────────────────
local C_BLACK      = Color3.fromRGB(14, 12, 18)
local C_BLACK_2    = Color3.fromRGB(24, 20, 30)
local C_BLACK_3    = Color3.fromRGB(34, 28, 44)
local C_GOLD       = Color3.fromRGB(212, 175, 90)
local C_GOLD_DARK  = Color3.fromRGB(160, 128, 60)
local C_PURPLE     = Color3.fromRGB(120, 70, 200)
local C_PURPLE_DIM = Color3.fromRGB(70, 40, 120)
local C_TEXT       = Color3.fromRGB(235, 230, 240)
local C_TEXT_DIM   = Color3.fromRGB(150, 145, 160)
local C_RED        = Color3.fromRGB(200, 50, 60)

local FONT   = Enum.Font.GothamMedium
local FONT_B = Enum.Font.GothamBold

-- ────────────────────────────────────────────────────────────────────────────
-- Resolve local fighter
-- ────────────────────────────────────────────────────────────────────────────
local LocalFighter
do
    local ps   = LP:FindFirstChild("PlayerScripts")
    local ctrl = ps and ps:FindFirstChild("Controllers")
    local fc   = ctrl and ctrl:FindFirstChild("FighterController")
    if fc and fc:IsA("ModuleScript") then
        local ok, mod = pcall(require, fc)
        if ok and type(mod) == "table" then
            LocalFighter = mod.LocalFighter
                or (mod.GetLocalFighter and mod:GetLocalFighter())
                or (mod.Fighters and mod.Fighters[LP])
        end
    end
end

local function isGun(it)
    return it and it.Info and it.Info.ShootCooldown ~= nil
end
local function isMelee(it)
    return it and it.Info and it.Info.AttackCooldown ~= nil
end
local function isThrowable(it)
    return it and it.Info and (
        it.Info.ThrowMaxChargeTime ~= nil
        or it.Info.LobMaxChargeTime ~= nil
        or it.Info.DetonateDelay ~= nil
        or it.Info.ThrowForceMin ~= nil
    )
end
local function isWeapon(it)
    return isGun(it) or isMelee(it) or isThrowable(it)
end

local function getEquippedWeapon()
    if not LocalFighter then return nil end
    local it = LocalFighter.EquippedItem
    if isWeapon(it) then return it end
    return nil
end

local UseItemRemote
local PickWeaponsRemote
local SetControlsRemote
do
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    local rep = rem and rem:FindFirstChild("Replication")
    local fig = rep and rep:FindFirstChild("Fighter")
    if fig then
        UseItemRemote     = fig:FindFirstChild("UseItem")
        PickWeaponsRemote = fig:FindFirstChild("PickWeapons")
        SetControlsRemote = fig:FindFirstChild("SetControls")
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Weapon library
-- ────────────────────────────────────────────────────────────────────────────
local ALL_WEAPON_NAMES = {}
do
    local found = false
    local ok, ItemLibrary = pcall(function()
        return require(ReplicatedStorage.Modules.ItemLibrary)
    end)
    if ok and type(ItemLibrary) == "table" and type(ItemLibrary.Items) == "table" then
        for name, info in pairs(ItemLibrary.Items) do
            if type(info) == "table" then
                local usable =
                    info.ShootCooldown ~= nil
                    or info.AttackCooldown ~= nil
                    or info.ThrowMaxChargeTime ~= nil
                    or info.LobMaxChargeTime ~= nil
                    or info.DetonateDelay ~= nil
                    or info.ThrowForceMin ~= nil
                    or info.Cooldown ~= nil
                if usable then
                    table.insert(ALL_WEAPON_NAMES, name)
                end
            end
        end
        found = #ALL_WEAPON_NAMES > 0
    end
    if not found then
        ALL_WEAPON_NAMES = { "Assault Rifle", "Handgun", "Fists", "Grenade" }
    end
    table.sort(ALL_WEAPON_NAMES, function(a, b) return a:lower() < b:lower() end)
end

local SelectedWeapons = {}
local AutoLoadEnabled = false

local function firePickWeapons(list)
    if not PickWeaponsRemote then return false end
    return pcall(function() PickWeaponsRemote:FireServer(list) end)
end

local function getSelectedArray()
    local arr = {}
    for name, sel in pairs(SelectedWeapons) do
        if sel then table.insert(arr, name) end
    end
    table.sort(arr)
    return arr
end

-- ────────────────────────────────────────────────────────────────────────────
-- Device spoofer state
-- ────────────────────────────────────────────────────────────────────────────
local DeviceSpooferEnabled = false
-- The game accepts: "VR", "Touch", "Gamepad", "MouseKeyboard"
-- UI labels:        VR,   Mobile,   Console,     PC
local DEVICE_OPTIONS = {
    { label = "VR",      arg = "VR"            },
    { label = "Console", arg = "Gamepad"       },
    { label = "Mobile",  arg = "Touch"         },
    { label = "PC",      arg = "MouseKeyboard" },
}
local SelectedDevice = nil   -- stores the {label, arg} table

local function fireSetControls(arg)
    if not SetControlsRemote or not arg then return false end
    return pcall(function() SetControlsRemote:FireServer(arg) end)
end

local function applyDeviceSpoofer()
    if DeviceSpooferEnabled and SelectedDevice then
        fireSetControls(SelectedDevice.arg)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Rage state
-- ────────────────────────────────────────────────────────────────────────────
local RageEnabled   = false
local CurrentTarget = nil
local ShootConn     = nil
local TPConn        = nil

local _savedCameraType    = nil
local _savedCameraSubject = nil

local ExcludedPlayers  = {}
local BulletsPerBullet = 1
local function parseBullets(text)
    local n = tonumber(tostring(text):match("^%s*(.-)%s*$"))
    if not n or n ~= n then return BulletsPerBullet end
    if n < 0 then n = 0 end
    return n
end

local ReloadState = {
    gun = nil, requested_at = 0, cooldown_until = 0, awaiting_full = false,
}
local RELOAD_RETRY_TIMEOUT = 1.5
local function resetReloadState()
    ReloadState.gun = nil
    ReloadState.requested_at = 0
    ReloadState.cooldown_until = 0
    ReloadState.awaiting_full = false
end

-- ────────────────────────────────────────────────────────────────────────────
-- Targeting
-- ────────────────────────────────────────────────────────────────────────────
local function getLocalRoot()
    local ch = LP.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function isValidHumanoid(hum, root, char)
    if not hum or not hum.Parent then return false end
    if hum.Health <= 0 then return false end
    if char == LP.Character then return false end
    if not root then return false end
    return true
end

local function isExcluded(char)
    local plr = Players:GetPlayerFromCharacter(char)
    if not plr then return false end
    return ExcludedPlayers[plr] == true
end

local function getNearestHumanoid()
    local myRoot = getLocalRoot()
    if not myRoot then return nil end
    local best, bestDist = nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if isValidHumanoid(hum, root, plr.Character)
                and not ExcludedPlayers[plr] then
                local d = (root.Position - myRoot.Position).Magnitude
                if d < bestDist then
                    best, bestDist = {hum = hum, root = root, char = plr.Character}, d
                end
            end
        end
    end

    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
            local hum  = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if isValidHumanoid(hum, root, model) then
                local d = (root.Position - myRoot.Position).Magnitude
                if d < bestDist then
                    best, bestDist = {hum = hum, root = root, char = model}, d
                end
            end
        end
    end
    return best
end

-- ────────────────────────────────────────────────────────────────────────────
-- Camera
-- ────────────────────────────────────────────────────────────────────────────
local function applyCameraMode()
    local cam = workspace.CurrentCamera
    if not cam then return end
    if _savedCameraType == nil then
        _savedCameraType    = cam.CameraType
        _savedCameraSubject = cam.CameraSubject
    end
    cam.CameraType = Enum.CameraType.Scriptable
end

local function restoreCameraMode()
    local cam = workspace.CurrentCamera
    if not cam then return end
    cam.CameraType = _savedCameraType or Enum.CameraType.Custom
    if _savedCameraSubject ~= nil and cam.CameraSubject ~= _savedCameraSubject then
        cam.CameraSubject = _savedCameraSubject
    end
    _savedCameraType = nil
    _savedCameraSubject = nil
end

local function snapAim(targetRoot)
    local cam    = workspace.CurrentCamera
    local myRoot = getLocalRoot()
    if not cam or not myRoot or not targetRoot then return end
    local origin = cam.CFrame.Position
    local dir    = targetRoot.Position - origin
    if dir.Magnitude < 1e-3 then return end
    cam.CFrame = CFrame.lookAt(origin, origin + dir.Unit)
end

local AIM_RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local function startAimLoop()
    applyCameraMode()
    RunService:BindToRenderStep("RageAimLoop", AIM_RENDER_PRIORITY, function()
        if not RageEnabled then return end
        local cam = workspace.CurrentCamera
        if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
            cam.CameraType = Enum.CameraType.Scriptable
        end
        if CurrentTarget and CurrentTarget.root and CurrentTarget.root.Parent then
            snapAim(CurrentTarget.root)
        end
    end)
end

local function stopAimLoop()
    RunService:UnbindFromRenderStep("RageAimLoop")
    restoreCameraMode()
end

-- ────────────────────────────────────────────────────────────────────────────
-- Loop TP
-- ────────────────────────────────────────────────────────────────────────────
local function startLoopTP(targetRoot)
    if TPConn then TPConn:Disconnect() end
    TPConn = RunService.Heartbeat:Connect(function()
        if not RageEnabled or not CurrentTarget then return end
        local myRoot = getLocalRoot()
        if not myRoot or not targetRoot.Parent then return end
        myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
        myRoot.AssemblyLinearVelocity = Vector3.zero
    end)
end

local function stopLoopTP()
    if TPConn then TPConn:Disconnect(); TPConn = nil end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Fire
-- ────────────────────────────────────────────────────────────────────────────
local function fireOnce(weapon)
    if not weapon then
        if UseItemRemote and LocalFighter and LocalFighter.EquippedItem then
            local it = LocalFighter.EquippedItem
            pcall(function()
                UseItemRemote:FireServer(it:Get("ObjectID"), "StartShooting")
            end)
        end
        return
    end
    if isThrowable(weapon) then
        pcall(function()
            weapon:Input("StartShooting")
            weapon:Input("FinishShooting")
        end)
    else
        pcall(function() weapon:Input("StartShooting") end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Reload handling
-- ────────────────────────────────────────────────────────────────────────────
local function handleReload(weapon)
    if not (weapon.Info and weapon.Info.ReloadType) then return end
    if isThrowable(weapon) then return end

    if ReloadState.gun ~= weapon then
        resetReloadState()
        ReloadState.gun = weapon
    end
    local ammo = weapon:Get("Ammo") or 0
    local now  = tick()

    if ammo > 0 then
        ReloadState.awaiting_full = false
        ReloadState.cooldown_until = 0
        return
    end
    if ReloadState.awaiting_full then
        if now < ReloadState.cooldown_until then return end
        if now - ReloadState.requested_at < RELOAD_RETRY_TIMEOUT then return end
    end

    local reloadType   = weapon.Info.ReloadType
    local maxAmmo      = weapon.Info.MaxAmmo
    local staleAmmo    = weapon._shot_but_ammo_hasnt_updated == true
    local inReload     = (weapon._reload_cooldown or 0) > now
    local reserveEmpty = (weapon:Get("AmmoReserve") or 0) <= 0
        and not (LocalFighter and LocalFighter:Get("InfiniteAmmoReserve"))
        and not (LocalFighter and LocalFighter:Get("InfiniteAmmo"))

    if not reloadType or not maxAmmo then return end
    if inReload then return end
    if staleAmmo then return end
    if reserveEmpty then return end

    local ok = pcall(function() weapon:StartReloading(true) end)
    if ok then
        ReloadState.awaiting_full = true
        ReloadState.requested_at  = now
        local est = 0
        local rl  = weapon.Info and weapon.Info.ReloadFiles
        if rl and reloadType == "Regular" then
            local key = (ammo <= 0 and "EmptyReload" or "Reload")
            local list = rl[key]
            if list and list[1] and list[1].Length then est = list[1].Length end
        elseif rl and reloadType == "Segmented" then
            local key = (ammo <= 0 and "EmptyReload" or "Reload")
            local list = rl[key]
            if list and list[1] then
                local s = list[1]
                est = (s.StartLength or 0)
                    + (s.SegmentLength or 0) * math.min(maxAmmo, weapon:Get("AmmoReserve") or 1)
                    + (s.FinishLength or 0)
            end
        end
        ReloadState.cooldown_until = now + math.max(est, 0.25)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Rage loop
-- ────────────────────────────────────────────────────────────────────────────
local function startRage()
    RageEnabled = true
    startAimLoop()
    if ShootConn then ShootConn:Disconnect() end

    ShootConn = RunService.Heartbeat:Connect(function()
        if not RageEnabled then return end

        if not CurrentTarget
            or CurrentTarget.hum.Health <= 0
            or not CurrentTarget.hum.Parent
            or not CurrentTarget.root.Parent
            or isExcluded(CurrentTarget.char)
        then
            CurrentTarget = getNearestHumanoid()
        end
        if not CurrentTarget then return end

        startLoopTP(CurrentTarget.root)

        local weapon = getEquippedWeapon()
        if not weapon then fireOnce(nil) return end

        weapon._shoot_cooldown             = 0
        weapon._attack_cooldown            = 0
        weapon._throw_cooldown             = 0
        weapon._is_revolver_quick_shooting = nil
        if isThrowable(weapon) then
            weapon._is_throwing = nil
        end

        local ammo = weapon:Get("Ammo") or 0
        if ammo <= 0 and isGun(weapon) and weapon.Info and weapon.Info.ReloadType then
            handleReload(weapon)
            return
        end
        if ammo <= 0 and isMelee(weapon) and weapon.Info and weapon.Info.NeedsAmmoToAttack then
            return
        end
        if ammo <= 0 and isThrowable(weapon) then
            return
        end

        if ReloadState.awaiting_full then
            resetReloadState()
            ReloadState.gun = weapon
        end

        local n = math.floor(BulletsPerBullet)
        if n <= 0 then return end

        local shots = n
        local maxAmmo = weapon.Info and weapon.Info.MaxAmmo
        if maxAmmo and maxAmmo > 0 then
            shots = math.min(shots, math.max(ammo, 0))
        end

        for i = 1, shots do
            if i % 16 == 0 then
                ammo = weapon:Get("Ammo") or 0
                if ammo <= 0 then break end
            end
            fireOnce(weapon)
        end
    end)
end

local function stopRage()
    RageEnabled   = false
    CurrentTarget = nil
    resetReloadState()
    if ShootConn then ShootConn:Disconnect(); ShootConn = nil end
    stopLoopTP()
    stopAimLoop()
end

-- ────────────────────────────────────────────────────────────────────────────
-- GUI helpers
-- ────────────────────────────────────────────────────────────────────────────
local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color        = color or C_GOLD
    s.Thickness    = thickness or 1
    s.Transparency = transparency or 0
    s.Parent       = parent
    return s
end

local function gradient(parent, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    }
    g.Rotation = rot or 0
    g.Parent   = parent
    return g
end

-- ────────────────────────────────────────────────────────────────────────────
-- Root gui
-- ────────────────────────────────────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "RageGui"
ScreenGui.ResetOnSpawn   = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder   = 9999
ScreenGui.Parent         = CoreGui

local Window = Instance.new("Frame")
Window.Name             = "Window"
Window.Size             = UDim2.new(0, 520, 0, 320)
Window.Position         = UDim2.new(0.5, -260, 0.5, -160)
Window.BackgroundColor3 = C_BLACK
Window.BorderSizePixel  = 0
Window.Active           = true
Window.Draggable        = false
Window.ClipsDescendants = false
Window.Parent           = ScreenGui
corner(Window, 12)
stroke(Window, C_GOLD, 1.5, 0.15)
do
    local bg = Instance.new("Frame")
    bg.Name             = "BG"
    bg.Size             = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = C_BLACK
    bg.BorderSizePixel  = 0
    bg.ZIndex           = 0
    bg.Parent           = Window
    corner(bg, 12)
    gradient(bg, C_BLACK, Color3.fromRGB(30, 22, 44), 135)
end

do
    local dragging, dragStart, startPos
    Window.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = Window.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Name             = "TitleBar"
TitleBar.Size             = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundColor3 = C_BLACK_2
TitleBar.BorderSizePixel  = 0
TitleBar.ZIndex           = 2
TitleBar.Parent           = Window
corner(TitleBar, 12)

local TitleAccent = Instance.new("Frame")
TitleAccent.Size             = UDim2.new(0, 4, 0, 20)
TitleAccent.Position         = UDim2.new(0, 16, 0.5, -10)
TitleAccent.BackgroundColor3 = C_GOLD
TitleAccent.BorderSizePixel  = 0
TitleAccent.ZIndex           = 3
TitleAccent.Parent           = TitleBar
corner(TitleAccent, 2)
gradient(TitleAccent, C_GOLD, C_PURPLE, 90)

local TitleText = Instance.new("TextLabel")
TitleText.Size                   = UDim2.new(0, 400, 1, 0)
TitleText.Position               = UDim2.new(0, 30, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text                   = "Rudra's Ragebot"
TitleText.TextColor3             = C_TEXT
TitleText.Font                   = FONT_B
TitleText.TextSize               = 16
TitleText.TextXAlignment         = Enum.TextXAlignment.Left
TitleText.ZIndex                 = 3
TitleText.Parent                 = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name             = "Close"
CloseBtn.Size             = UDim2.new(0, 26, 0, 26)
CloseBtn.Position         = UDim2.new(1, -36, 0.5, -13)
CloseBtn.BackgroundColor3 = C_BLACK_3
CloseBtn.BorderSizePixel  = 0
CloseBtn.Text             = "×"
CloseBtn.TextColor3       = C_TEXT
CloseBtn.Font             = FONT_B
CloseBtn.TextSize         = 18
CloseBtn.ZIndex           = 4
CloseBtn.Parent           = TitleBar
corner(CloseBtn, 6)
stroke(CloseBtn, C_PURPLE_DIM, 1, 0.2)
CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = C_RED}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = C_BLACK_3}):Play()
end)

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Name             = "Sidebar"
Sidebar.Size             = UDim2.new(0, 130, 1, -40)
Sidebar.Position         = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = C_BLACK_2
Sidebar.BorderSizePixel  = 0
Sidebar.ZIndex           = 2
Sidebar.Parent           = Window

local SidebarList = Instance.new("Frame")
SidebarList.Size             = UDim2.new(1, 0, 1, 0)
SidebarList.BackgroundTransparency = 1
SidebarList.ZIndex           = 2
SidebarList.Parent           = Sidebar

local SidebarLayout = Instance.new("UIListLayout")
SidebarLayout.Padding   = UDim.new(0, 4)
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
SidebarLayout.Parent    = SidebarList

local SidebarPad = Instance.new("UIPadding")
SidebarPad.PaddingTop  = UDim.new(0, 10)
SidebarPad.PaddingLeft = UDim.new(0, 8)
SidebarPad.PaddingRight= UDim.new(0, 8)
SidebarPad.Parent      = SidebarList

local PagesHolder = Instance.new("Frame")
PagesHolder.Name             = "PagesHolder"
PagesHolder.Size             = UDim2.new(1, -130, 1, -40)
PagesHolder.Position         = UDim2.new(0, 130, 0, 40)
PagesHolder.BackgroundTransparency = 1
PagesHolder.ZIndex           = 1
PagesHolder.ClipsDescendants = true
PagesHolder.Parent           = Window

local function makePage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name             = name
    page.Size             = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel  = 0
    page.ScrollBarThickness = 3
    page.CanvasSize       = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible          = false
    page.ZIndex           = 1
    page.Parent           = PagesHolder

    local pad = Instance.new("UIPadding")
    pad.PaddingTop   = UDim.new(0, 14)
    pad.PaddingLeft  = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 16)
    pad.PaddingBottom= UDim.new(0, 14)
    pad.Parent       = page

    local lay = Instance.new("UIListLayout")
    lay.Padding   = UDim.new(0, 10)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent    = page

    return page
end

local RagePage    = makePage("Rage")
local WeaponPage  = makePage("Weapon")
local SpooferPage = makePage("Spoofer")

local function sectionHeader(parent, text, order)
    local row = Instance.new("Frame")
    row.Name             = "H_" .. text
    row.Size             = UDim2.new(1, 0, 0, 22)
    row.BackgroundTransparency = 1
    row.LayoutOrder      = order or 1
    row.Parent           = parent

    local accent = Instance.new("Frame")
    accent.Size             = UDim2.new(0, 3, 0, 14)
    accent.Position         = UDim2.new(0, 0, 0.5, -7)
    accent.BackgroundColor3 = C_GOLD
    accent.BorderSizePixel  = 0
    accent.Parent           = row
    corner(accent, 2)

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -10, 1, 0)
    lbl.Position               = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = C_GOLD
    lbl.Font                   = FONT_B
    lbl.TextSize               = 12
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = row
    return row
end

local function card(parent, order, height)
    local c = Instance.new("Frame")
    c.Name             = "Card"
    c.Size             = UDim2.new(1, 0, 0, height or 44)
    c.BackgroundColor3 = C_BLACK_3
    c.BorderSizePixel  = 0
    c.LayoutOrder      = order or 1
    c.Parent           = parent
    corner(c, 8)
    stroke(c, C_PURPLE_DIM, 1, 0.4)
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- RAGE PAGE (unchanged)
-- ════════════════════════════════════════════════════════════════════════════
sectionHeader(RagePage, "COMBAT", 1)

local RageCard = card(RagePage, 2)
local RageCardTxt = Instance.new("TextLabel")
RageCardTxt.Size                   = UDim2.new(1, -140, 1, 0)
RageCardTxt.Position               = UDim2.new(0, 14, 0, 0)
RageCardTxt.BackgroundTransparency = 1
RageCardTxt.Text                   = "Rage"
RageCardTxt.TextColor3             = C_TEXT
RageCardTxt.Font                   = FONT
RageCardTxt.TextSize               = 14
RageCardTxt.TextXAlignment         = Enum.TextXAlignment.Left
RageCardTxt.Parent                 = RageCard

local RageToggle = Instance.new("TextButton")
RageToggle.Name             = "RageToggle"
RageToggle.Size             = UDim2.new(0, 100, 0, 30)
RageToggle.Position         = UDim2.new(1, -114, 0.5, -15)
RageToggle.BackgroundColor3 = C_BLACK_2
RageToggle.BorderSizePixel  = 0
RageToggle.Text             = "OFF"
RageToggle.TextColor3       = C_TEXT_DIM
RageToggle.Font             = FONT_B
RageToggle.TextSize         = 13
RageToggle.Parent           = RageCard
corner(RageToggle, 15)
stroke(RageToggle, C_PURPLE_DIM, 1, 0.2)

local RageToggleFill = Instance.new("Frame")
RageToggleFill.Name             = "Fill"
RageToggleFill.Size             = UDim2.new(0, 0, 1, 0)
RageToggleFill.BackgroundColor3 = C_GOLD_DARK
RageToggleFill.BorderSizePixel  = 0
RageToggleFill.ClipsDescendants = true
RageToggleFill.ZIndex           = 1
RageToggleFill.Parent           = RageToggle
corner(RageToggleFill, 15)
gradient(RageToggleFill, C_PURPLE_DIM, C_GOLD_DARK, 90)

local function setRageButtonState(on)
    local target = on and C_GOLD or C_PURPLE_DIM
    TweenService:Create(RageToggleFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
        {Size = on and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 1, 0),
         BackgroundColor3 = target}):Play()
    RageToggle.Text       = on and "ON" or "OFF"
    RageToggle.TextColor3 = on and C_BLACK or C_TEXT_DIM
end

RageToggle.MouseButton1Click:Connect(function()
    if RageEnabled then
        stopRage()
        setRageButtonState(false)
        Status.Text = "idle"
        AmmoLabel.Text = "ammo: —"
    else
        startRage()
        setRageButtonState(true)
        Status.Text = "active"
    end
end)

sectionHeader(RagePage, "FIRE RATE", 3)
local BPC_Card = card(RagePage, 4)
local BPC_Txt = Instance.new("TextLabel")
BPC_Txt.Size = UDim2.new(1, -150, 1, 0)
BPC_Txt.Position = UDim2.new(0, 14, 0, 0)
BPC_Txt.BackgroundTransparency = 1
BPC_Txt.Text = "Bullets / Bullet"
BPC_Txt.TextColor3 = C_TEXT
BPC_Txt.Font = FONT
BPC_Txt.TextSize = 14
BPC_Txt.TextXAlignment = Enum.TextXAlignment.Left
BPC_Txt.Parent = BPC_Card

local BPCBox = Instance.new("TextBox")
BPCBox.Name             = "BulletsBox"
BPCBox.Size             = UDim2.new(0, 110, 0, 28)
BPCBox.Position         = UDim2.new(1, -124, 0.5, -14)
BPCBox.BackgroundColor3 = C_BLACK
BPCBox.BorderSizePixel  = 0
BPCBox.Text             = tostring(BulletsPerBullet)
BPCBox.PlaceholderText  = "any #"
BPCBox.TextColor3       = C_GOLD
BPCBox.PlaceholderColor3= C_TEXT_DIM
BPCBox.Font             = FONT_B
BPCBox.TextSize         = 14
BPCBox.ClearTextOnFocus = false
BPCBox.MaxVisibleGraphemes = -1
BPCBox.Parent           = BPC_Card
corner(BPCBox, 6)
stroke(BPCBox, C_GOLD_DARK, 1, 0.3)

BPCBox:GetPropertyChangedSignal("Text"):Connect(function()
    BulletsPerBullet = parseBullets(BPCBox.Text)
end)
BPCBox.FocusLost:Connect(function()
    BPCBox.Text = tostring(BulletsPerBullet)
end)

sectionHeader(RagePage, "TARGET EXCLUSIONS", 5)
local ExcludeHeader = card(RagePage, 6, 36)
local ExcludeBtn = Instance.new("TextButton")
ExcludeBtn.Name             = "ExcludeToggle"
ExcludeBtn.Size             = UDim2.fromScale(1, 1)
ExcludeBtn.BackgroundTransparency = 1
ExcludeBtn.Text             = ""
ExcludeBtn.Parent           = ExcludeHeader

local ExcludeLbl = Instance.new("TextLabel")
ExcludeLbl.Size                   = UDim2.new(1, -70, 1, 0)
ExcludeLbl.Position               = UDim2.new(0, 14, 0, 0)
ExcludeLbl.BackgroundTransparency = 1
ExcludeLbl.Text                   = "▼ Exclude (0)"
ExcludeLbl.TextColor3             = C_TEXT
ExcludeLbl.Font                   = FONT
ExcludeLbl.TextSize               = 13
ExcludeLbl.TextXAlignment         = Enum.TextXAlignment.Left
ExcludeLbl.Parent                 = ExcludeHeader

local ExcludeChevron = Instance.new("TextLabel")
ExcludeChevron.Size                   = UDim2.new(0, 24, 1, 0)
ExcludeChevron.Position               = UDim2.new(1, -32, 0, 0)
ExcludeChevron.BackgroundTransparency = 1
ExcludeChevron.Text                   = "▼"
ExcludeChevron.TextColor3             = C_GOLD
ExcludeChevron.Font                   = FONT_B
ExcludeChevron.TextSize               = 12
ExcludeChevron.Parent                 = ExcludeHeader

local ExcludeList = Instance.new("ScrollingFrame")
ExcludeList.Name             = "ExcludeList"
ExcludeList.Size             = UDim2.new(1, 0, 0, 0)
ExcludeList.BackgroundColor3 = C_BLACK_2
ExcludeList.BorderSizePixel  = 0
ExcludeList.ScrollBarThickness = 3
ExcludeList.CanvasSize       = UDim2.new(0, 0, 0, 0)
ExcludeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
ExcludeList.Visible          = false
ExcludeList.LayoutOrder      = 7
ExcludeList.ClipsDescendants = true
ExcludeList.Parent           = RagePage
corner(ExcludeList, 8)
stroke(ExcludeList, C_PURPLE_DIM, 1, 0.3)

local ExcludeLayout = Instance.new("UIListLayout")
ExcludeLayout.Padding   = UDim.new(0, 2)
ExcludeLayout.SortOrder = Enum.SortOrder.LayoutOrder
ExcludeLayout.Parent    = ExcludeList

local ExcludePad = Instance.new("UIPadding")
ExcludePad.PaddingTop    = UDim.new(0, 4)
ExcludePad.PaddingBottom = UDim.new(0, 4)
ExcludePad.PaddingLeft   = UDim.new(0, 4)
ExcludePad.PaddingRight  = UDim.new(0, 4)
ExcludePad.Parent        = ExcludeList

local function refreshExcludeCount()
    local n = 0
    for _ in pairs(ExcludedPlayers) do n += 1 end
    ExcludeLbl.Text = string.format("Exclude (%d)", n)
end

local function rebuildPlayerList()
    for _, c in ipairs(ExcludeList:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local sorted = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then table.insert(sorted, plr) end
    end
    table.sort(sorted, function(a, b) return a.Name:lower() < b.Name:lower() end)
    local order = 0
    for _, plr in ipairs(sorted) do
        order += 1
        local btn = Instance.new("TextButton")
        btn.Name             = plr.Name
        btn.Size             = UDim2.new(1, 0, 0, 26)
        btn.BackgroundColor3 = ExcludedPlayers[plr] and Color3.fromRGB(80, 30, 50) or C_BLACK_3
        btn.BorderSizePixel  = 0
        btn.Text             = plr.Name
        btn.TextColor3       = ExcludedPlayers[plr] and C_GOLD or C_TEXT
        btn.Font             = FONT
        btn.TextSize         = 12
        btn.TextXAlignment   = Enum.TextXAlignment.Left
        btn.LayoutOrder      = order
        btn.Parent           = ExcludeList
        corner(btn, 5)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.Parent      = btn

        local dot = Instance.new("Frame")
        dot.Size             = UDim2.new(0, 6, 0, 6)
        dot.Position         = UDim2.new(1, -16, 0.5, -3)
        dot.BackgroundColor3 = ExcludedPlayers[plr] and C_GOLD or C_PURPLE_DIM
        dot.BorderSizePixel  = 0
        dot.Parent           = btn
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        btn.MouseButton1Click:Connect(function()
            ExcludedPlayers[plr] = (not ExcludedPlayers[plr]) or nil
            btn.BackgroundColor3 = ExcludedPlayers[plr] and Color3.fromRGB(80, 30, 50) or C_BLACK_3
            btn.TextColor3       = ExcludedPlayers[plr] and C_GOLD or C_TEXT
            dot.BackgroundColor3 = ExcludedPlayers[plr] and C_GOLD or C_PURPLE_DIM
            refreshExcludeCount()
        end)
    end
    local rowCount = #sorted
    local targetH  = math.min(rowCount, 5) * 28 + 10
    TweenService:Create(ExcludeList, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.new(1, 0, 0, targetH)}):Play()
end

ExcludeBtn.MouseButton1Click:Connect(function()
    ExcludeList.Visible = not ExcludeList.Visible
    ExcludeChevron.Text = ExcludeList.Visible and "▲" or "▼"
    if ExcludeList.Visible then
        rebuildPlayerList()
    else
        TweenService:Create(ExcludeList, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 0)}):Play()
    end
    refreshExcludeCount()
end)

Players.PlayerAdded:Connect(function()
    if ExcludeList.Visible then rebuildPlayerList(); refreshExcludeCount() end
end)
Players.PlayerRemoving:Connect(function(plr)
    ExcludedPlayers[plr] = nil
    if ExcludeList.Visible then rebuildPlayerList(); refreshExcludeCount() end
end)
refreshExcludeCount()

sectionHeader(RagePage, "STATUS", 8)
local StatusCard = card(RagePage, 9, 74)

local Status = Instance.new("TextLabel")
Status.Size                   = UDim2.new(1, -20, 0, 20)
Status.Position               = UDim2.new(0, 12, 0, 8)
Status.BackgroundTransparency = 1
Status.Text                   = "idle"
Status.TextColor3             = C_TEXT
Status.Font                   = FONT
Status.TextSize               = 13
Status.TextXAlignment         = Enum.TextXAlignment.Left
Status.Parent                 = StatusCard

local AmmoLabel = Instance.new("TextLabel")
AmmoLabel.Size                   = UDim2.new(1, -20, 0, 20)
AmmoLabel.Position               = UDim2.new(0, 12, 0, 30)
AmmoLabel.BackgroundTransparency = 1
AmmoLabel.Text                   = "ammo: —"
AmmoLabel.TextColor3             = C_TEXT_DIM
AmmoLabel.Font                   = FONT
AmmoLabel.TextSize               = 12
AmmoLabel.TextXAlignment         = Enum.TextXAlignment.Left
AmmoLabel.Parent                 = StatusCard

local BulletLabel = Instance.new("TextLabel")
BulletLabel.Size                   = UDim2.new(1, -20, 0, 20)
BulletLabel.Position               = UDim2.new(0, 12, 0, 50)
BulletLabel.BackgroundTransparency = 1
BulletLabel.Text                   = "bullet: 1"
BulletLabel.TextColor3             = C_TEXT_DIM
BulletLabel.Font                   = FONT
BulletLabel.TextSize               = 12
BulletLabel.TextXAlignment         = Enum.TextXAlignment.Left
BulletLabel.Parent                 = StatusCard

-- ════════════════════════════════════════════════════════════════════════════
-- WEAPON PAGE
-- ════════════════════════════════════════════════════════════════════════════
sectionHeader(WeaponPage, "AUTO LOAD", 1)

local AutoCard = card(WeaponPage, 2)
local AutoTxt = Instance.new("TextLabel")
AutoTxt.Size = UDim2.new(1, -140, 1, 0)
AutoTxt.Position = UDim2.new(0, 14, 0, 0)
AutoTxt.BackgroundTransparency = 1
AutoTxt.Text = "Auto Load"
AutoTxt.TextColor3 = C_TEXT
AutoTxt.Font = FONT
AutoTxt.TextSize = 14
AutoTxt.TextXAlignment = Enum.TextXAlignment.Left
AutoTxt.Parent = AutoCard

local AutoToggle = Instance.new("TextButton")
AutoToggle.Name             = "AutoToggle"
AutoToggle.Size             = UDim2.new(0, 100, 0, 30)
AutoToggle.Position         = UDim2.new(1, -114, 0.5, -15)
AutoToggle.BackgroundColor3 = C_BLACK_2
AutoToggle.BorderSizePixel  = 0
AutoToggle.Text             = "OFF"
AutoToggle.TextColor3       = C_TEXT_DIM
AutoToggle.Font             = FONT_B
AutoToggle.TextSize         = 13
AutoToggle.Parent           = AutoCard
corner(AutoToggle, 15)
stroke(AutoToggle, C_PURPLE_DIM, 1, 0.2)

local AutoToggleFill = Instance.new("Frame")
AutoToggleFill.Name             = "Fill"
AutoToggleFill.Size             = UDim2.new(0, 0, 1, 0)
AutoToggleFill.BackgroundColor3 = C_GOLD_DARK
AutoToggleFill.BorderSizePixel  = 0
AutoToggleFill.ClipsDescendants = true
AutoToggleFill.ZIndex           = 1
AutoToggleFill.Parent           = AutoToggle
corner(AutoToggleFill, 15)
gradient(AutoToggleFill, C_PURPLE_DIM, C_GOLD_DARK, 90)

local function setAutoButtonState(on)
    local target = on and C_GOLD or C_PURPLE_DIM
    TweenService:Create(AutoToggleFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
        {Size = on and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 1, 0),
         BackgroundColor3 = target}):Play()
    AutoToggle.Text       = on and "ON" or "OFF"
    AutoToggle.TextColor3 = on and C_BLACK or C_TEXT_DIM
end

sectionHeader(WeaponPage, "SEARCH", 3)
local SearchCard = card(WeaponPage, 4)
local SearchBox = Instance.new("TextBox")
SearchBox.Name             = "Search"
SearchBox.Size             = UDim2.new(1, -20, 0, 30)
SearchBox.Position         = UDim2.new(0, 10, 0.5, -15)
SearchBox.BackgroundColor3 = C_BLACK
SearchBox.BorderSizePixel  = 0
SearchBox.Text             = ""
SearchBox.PlaceholderText  = "Search weapons…"
SearchBox.TextColor3       = C_TEXT
SearchBox.PlaceholderColor3= C_TEXT_DIM
SearchBox.Font             = FONT
SearchBox.TextSize         = 13
SearchBox.ClearTextOnFocus = false
SearchBox.Parent           = SearchCard
corner(SearchBox, 6)
stroke(SearchBox, C_GOLD_DARK, 1, 0.3)

sectionHeader(WeaponPage, "WEAPONS", 5)
local WeaponList = Instance.new("ScrollingFrame")
WeaponList.Name             = "WeaponList"
WeaponList.Size             = UDim2.new(1, 0, 0, 200)
WeaponList.BackgroundColor3 = C_BLACK_2
WeaponList.BorderSizePixel  = 0
WeaponList.ScrollBarThickness = 3
WeaponList.CanvasSize       = UDim2.new(0, 0, 0, 0)
WeaponList.AutomaticCanvasSize = Enum.AutomaticSize.Y
WeaponList.LayoutOrder      = 6
WeaponList.ClipsDescendants = true
WeaponList.Parent           = WeaponPage
corner(WeaponList, 8)
stroke(WeaponList, C_PURPLE_DIM, 1, 0.3)

local WeaponListLayout = Instance.new("UIListLayout")
WeaponListLayout.Padding   = UDim.new(0, 2)
WeaponListLayout.SortOrder = Enum.SortOrder.LayoutOrder
WeaponListLayout.Parent    = WeaponList

local WeaponListPad = Instance.new("UIPadding")
WeaponListPad.PaddingTop    = UDim.new(0, 4)
WeaponListPad.PaddingBottom = UDim.new(0, 4)
WeaponListPad.PaddingLeft   = UDim.new(0, 4)
WeaponListPad.PaddingRight  = UDim.new(0, 4)
WeaponListPad.Parent        = WeaponList

local SelectedLabel = Instance.new("TextLabel")
SelectedLabel.Size                   = UDim2.new(1, 0, 0, 20)
SelectedLabel.BackgroundTransparency = 1
SelectedLabel.LayoutOrder            = 7
SelectedLabel.Text                   = "selected: 0"
SelectedLabel.TextColor3             = C_TEXT_DIM
SelectedLabel.Font                   = FONT
SelectedLabel.TextSize               = 12
SelectedLabel.TextXAlignment         = Enum.TextXAlignment.Left
SelectedLabel.Parent                 = WeaponPage

local function refreshSelectedLabel()
    local n = 0
    for _, v in pairs(SelectedWeapons) do if v then n += 1 end end
    SelectedLabel.Text = string.format("selected: %d", n)
end

local function rebuildWeaponList(filter)
    for _, c in ipairs(WeaponList:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    filter = (filter or ""):lower()
    local order = 0
    for _, name in ipairs(ALL_WEAPON_NAMES) do
        if filter == "" or name:lower():find(filter, 1, true) then
            order += 1
            local selected = SelectedWeapons[name] == true
            local btn = Instance.new("TextButton")
            btn.Name             = name
            btn.Size             = UDim2.new(1, 0, 0, 26)
            btn.BackgroundColor3 = selected and Color3.fromRGB(80, 30, 50) or C_BLACK_3
            btn.BorderSizePixel  = 0
            btn.Text             = name
            btn.TextColor3       = selected and C_GOLD or C_TEXT
            btn.Font             = FONT
            btn.TextSize         = 12
            btn.TextXAlignment   = Enum.TextXAlignment.Left
            btn.LayoutOrder      = order
            btn.Parent           = WeaponList
            corner(btn, 5)

            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 10)
            pad.Parent      = btn

            local dot = Instance.new("Frame")
            dot.Size             = UDim2.new(0, 6, 0, 6)
            dot.Position         = UDim2.new(1, -16, 0.5, -3)
            dot.BackgroundColor3 = selected and C_GOLD or C_PURPLE_DIM
            dot.BorderSizePixel  = 0
            dot.Parent           = btn
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

            btn.MouseButton1Click:Connect(function()
                SelectedWeapons[name] = (not SelectedWeapons[name]) or nil
                local sel = SelectedWeapons[name] == true
                btn.BackgroundColor3 = sel and Color3.fromRGB(80, 30, 50) or C_BLACK_3
                btn.TextColor3       = sel and C_GOLD or C_TEXT
                dot.BackgroundColor3 = sel and C_GOLD or C_PURPLE_DIM
                refreshSelectedLabel()
                if AutoLoadEnabled then
                    firePickWeapons(getSelectedArray())
                end
            end)
        end
    end
    local visibleCount = math.min(order, 7)
    local targetH = visibleCount * 28 + 10
    TweenService:Create(WeaponList, TweenInfo.new(0.2, Enum.EasingStyle.Quad),
        {Size = UDim2.new(1, 0, 0, targetH)}):Play()
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    rebuildWeaponList(SearchBox.Text)
end)

AutoToggle.MouseButton1Click:Connect(function()
    AutoLoadEnabled = not AutoLoadEnabled
    setAutoButtonState(AutoLoadEnabled)
    if AutoLoadEnabled then
        firePickWeapons(getSelectedArray())
    end
end)

refreshSelectedLabel()
rebuildWeaponList("")

LP.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    if AutoLoadEnabled then firePickWeapons(getSelectedArray()) end
end)

-- ════════════════════════════════════════════════════════════════════════════
-- SPOOFER PAGE
-- ════════════════════════════════════════════════════════════════════════════
sectionHeader(SpooferPage, "DEVICE", 1)

local DeviceCard = card(SpooferPage, 2)
local DeviceCardTxt = Instance.new("TextLabel")
DeviceCardTxt.Size                   = UDim2.new(1, -140, 1, 0)
DeviceCardTxt.Position               = UDim2.new(0, 14, 0, 0)
DeviceCardTxt.BackgroundTransparency = 1
DeviceCardTxt.Text                   = "Device Spoofer"
DeviceCardTxt.TextColor3             = C_TEXT
DeviceCardTxt.Font                   = FONT
DeviceCardTxt.TextSize               = 14
DeviceCardTxt.TextXAlignment         = Enum.TextXAlignment.Left
DeviceCardTxt.Parent                 = DeviceCard

local DeviceToggle = Instance.new("TextButton")
DeviceToggle.Name             = "DeviceToggle"
DeviceToggle.Size             = UDim2.new(0, 100, 0, 30)
DeviceToggle.Position         = UDim2.new(1, -114, 0.5, -15)
DeviceToggle.BackgroundColor3 = C_BLACK_2
DeviceToggle.BorderSizePixel  = 0
DeviceToggle.Text             = "OFF"
DeviceToggle.TextColor3       = C_TEXT_DIM
DeviceToggle.Font             = FONT_B
DeviceToggle.TextSize         = 13
DeviceToggle.Parent           = DeviceCard
corner(DeviceToggle, 15)
stroke(DeviceToggle, C_PURPLE_DIM, 1, 0.2)

local DeviceToggleFill = Instance.new("Frame")
DeviceToggleFill.Name             = "Fill"
DeviceToggleFill.Size             = UDim2.new(0, 0, 1, 0)
DeviceToggleFill.BackgroundColor3 = C_GOLD_DARK
DeviceToggleFill.BorderSizePixel  = 0
DeviceToggleFill.ClipsDescendants = true
DeviceToggleFill.ZIndex           = 1
DeviceToggleFill.Parent           = DeviceToggle
corner(DeviceToggleFill, 15)
gradient(DeviceToggleFill, C_PURPLE_DIM, C_GOLD_DARK, 90)

local function setDeviceButtonState(on)
    local target = on and C_GOLD or C_PURPLE_DIM
    TweenService:Create(DeviceToggleFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
        {Size = on and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 1, 0),
         BackgroundColor3 = target}):Play()
    DeviceToggle.Text       = on and "ON" or "OFF"
    DeviceToggle.TextColor3 = on and C_BLACK or C_TEXT_DIM
end

sectionHeader(SpooferPage, "SELECT DEVICE", 3)

local DevHeader = card(SpooferPage, 4, 36)
local DevBtn = Instance.new("TextButton")
DevBtn.Name             = "DevDropdownToggle"
DevBtn.Size             = UDim2.fromScale(1, 1)
DevBtn.BackgroundTransparency = 1
DevBtn.Text             = ""
DevBtn.Parent           = DevHeader

local DevLbl = Instance.new("TextLabel")
DevLbl.Size                   = UDim2.new(1, -70, 1, 0)
DevLbl.Position               = UDim2.new(0, 14, 0, 0)
DevLbl.BackgroundTransparency = 1
DevLbl.Text                   = "▼ Select Device"
DevLbl.TextColor3             = C_TEXT
DevLbl.Font                   = FONT
DevLbl.TextSize               = 13
DevLbl.TextXAlignment         = Enum.TextXAlignment.Left
DevLbl.Parent                 = DevHeader

local DevChevron = Instance.new("TextLabel")
DevChevron.Size                   = UDim2.new(0, 24, 1, 0)
DevChevron.Position               = UDim2.new(1, -32, 0, 0)
DevChevron.BackgroundTransparency = 1
DevChevron.Text                   = "▼"
DevChevron.TextColor3             = C_GOLD
DevChevron.Font                   = FONT_B
DevChevron.TextSize               = 12
DevChevron.Parent                 = DevHeader

local DevList = Instance.new("Frame")
DevList.Name             = "DevList"
DevList.Size             = UDim2.new(1, 0, 0, 0)
DevList.BackgroundColor3 = C_BLACK_2
DevList.BorderSizePixel  = 0
DevList.Visible          = false
DevList.LayoutOrder      = 5
DevList.ClipsDescendants = true
DevList.Parent           = SpooferPage
corner(DevList, 8)
stroke(DevList, C_PURPLE_DIM, 1, 0.3)

local DevListLayout = Instance.new("UIListLayout")
DevListLayout.Padding   = UDim.new(0, 2)
DevListLayout.SortOrder = Enum.SortOrder.LayoutOrder
DevListLayout.Parent    = DevList

local DevListPad = Instance.new("UIPadding")
DevListPad.PaddingTop    = UDim.new(0, 4)
DevListPad.PaddingBottom = UDim.new(0, 4)
DevListPad.PaddingLeft   = UDim.new(0, 4)
DevListPad.PaddingRight  = UDim.new(0, 4)
DevListPad.Parent        = DevList

local devButtons = {}

local function refreshDevButtons()
    for _, opt in ipairs(DEVICE_OPTIONS) do
        local btn = devButtons[opt.label]
        if btn then
            local selected = (SelectedDevice == opt)
            btn.BackgroundColor3 = selected and Color3.fromRGB(80, 30, 50) or C_BLACK_3
            btn.TextColor3       = selected and C_GOLD or C_TEXT
            local dot = btn:FindFirstChild("Dot")
            if dot then
                dot.BackgroundColor3 = selected and C_GOLD or C_PURPLE_DIM
            end
        end
    end
    if SelectedDevice then
        DevLbl.Text = "▼ " .. SelectedDevice.label
    else
        DevLbl.Text = "▼ Select Device"
    end
end

local function buildDevList()
    for _, c in ipairs(DevList:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    devButtons = {}
    local order = 0
    for _, opt in ipairs(DEVICE_OPTIONS) do
        order += 1
        local btn = Instance.new("TextButton")
        btn.Name             = "Dev_" .. opt.label
        btn.Size             = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = C_BLACK_3
        btn.BorderSizePixel  = 0
        btn.Text             = opt.label
        btn.TextColor3       = C_TEXT
        btn.Font             = FONT
        btn.TextSize         = 12
        btn.TextXAlignment   = Enum.TextXAlignment.Left
        btn.LayoutOrder      = order
        btn.Parent           = DevList
        corner(btn, 5)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.Parent      = btn

        local dot = Instance.new("Frame")
        dot.Name             = "Dot"
        dot.Size             = UDim2.new(0, 6, 0, 6)
        dot.Position         = UDim2.new(1, -16, 0.5, -3)
        dot.BackgroundColor3 = C_PURPLE_DIM
        dot.BorderSizePixel  = 0
        dot.Parent           = btn
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        btn.MouseButton1Click:Connect(function()
            SelectedDevice = opt
            refreshDevButtons()
            if DeviceSpooferEnabled then
                applyDeviceSpoofer()
            end
        end)

        devButtons[opt.label] = btn
    end
    refreshDevButtons()
end

DevBtn.MouseButton1Click:Connect(function()
    DevList.Visible = not DevList.Visible
    DevChevron.Text = DevList.Visible and "▲" or "▼"
    local targetH = DevList.Visible and (#DEVICE_OPTIONS * 30 + 10) or 0
    TweenService:Create(DevList, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
        {Size = UDim2.new(1, 0, 0, targetH)}):Play()
end)

DeviceToggle.MouseButton1Click:Connect(function()
    DeviceSpooferEnabled = not DeviceSpooferEnabled
    setDeviceButtonState(DeviceSpooferEnabled)
    if DeviceSpooferEnabled then
        applyDeviceSpoofer()
    end
end)

buildDevList()

-- ── Tabs ────────────────────────────────────────────────────────────────────
local Tabs = {
    { name = "Rage",    page = RagePage    },
    { name = "Weapon",  page = WeaponPage  },
    { name = "Spoofer", page = SpooferPage },
}

local tabButtons = {}
local activeTab  = nil

local function selectTab(name)
    if activeTab == name then return end
    activeTab = name
    for _, t in ipairs(Tabs) do
        local btn = tabButtons[t.name]
        local isSel = t.name == name
        t.page.Visible = isSel
        if btn then
            TweenService:Create(btn, TweenInfo.new(0.2),
                {BackgroundColor3 = isSel and C_BLACK_3 or C_BLACK_2}):Play()
            local bar = btn:FindFirstChild("Bar")
            if bar then
                TweenService:Create(bar, TweenInfo.new(0.2),
                    {Size = UDim2.new(0, isSel and 3 or 0, 1, -14),
                     BackgroundColor3 = isSel and C_GOLD or C_PURPLE_DIM}):Play()
            end
            local lbl = btn:FindFirstChild("Label")
            if lbl then
                lbl.TextColor3 = isSel and C_GOLD or C_TEXT_DIM
            end
        end
    end
end

for i, t in ipairs(Tabs) do
    local btn = Instance.new("TextButton")
    btn.Name             = "Tab_" .. t.name
    btn.Size             = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = C_BLACK_2
    btn.BorderSizePixel  = 0
    btn.Text             = ""
    btn.LayoutOrder      = i
    btn.Parent           = SidebarList
    corner(btn, 6)

    local bar = Instance.new("Frame")
    bar.Name             = "Bar"
    bar.Size             = UDim2.new(0, 0, 1, -14)
    bar.Position         = UDim2.new(0, 0, 0, 7)
    bar.BackgroundColor3 = C_PURPLE_DIM
    bar.BorderSizePixel  = 0
    bar.Parent           = btn
    corner(bar, 2)

    local lbl = Instance.new("TextLabel")
    lbl.Name                   = "Label"
    lbl.Size                   = UDim2.new(1, -20, 1, 0)
    lbl.Position               = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = t.name
    lbl.TextColor3             = C_TEXT_DIM
    lbl.Font                   = FONT
    lbl.TextSize               = 13
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = btn

    btn.MouseButton1Click:Connect(function()
        selectTab(t.name)
    end)
    tabButtons[t.name] = btn
end

selectTab("Rage")

-- ────────────────────────────────────────────────────────────────────────────
-- Open bubble
-- ────────────────────────────────────────────────────────────────────────────
local OpenBubble = Instance.new("TextButton")
OpenBubble.Name             = "OpenBubble"
OpenBubble.Size             = UDim2.new(0, 52, 0, 52)
OpenBubble.Position         = UDim2.new(0, 20, 0.5, -26)
OpenBubble.BackgroundColor3 = C_BLACK
OpenBubble.BorderSizePixel  = 0
OpenBubble.Text             = "R"
OpenBubble.TextColor3       = C_GOLD
OpenBubble.Font             = FONT_B
OpenBubble.TextSize         = 24
OpenBubble.Visible          = false
OpenBubble.Parent           = ScreenGui
corner(OpenBubble, 26)
stroke(OpenBubble, C_GOLD, 1.5, 0.1)
gradient(OpenBubble, C_BLACK, C_PURPLE_DIM, 135)

OpenBubble.MouseEnter:Connect(function()
    TweenService:Create(OpenBubble, TweenInfo.new(0.15), {BackgroundColor3 = C_PURPLE_DIM}):Play()
end)
OpenBubble.MouseLeave:Connect(function()
    TweenService:Create(OpenBubble, TweenInfo.new(0.15), {BackgroundColor3 = C_BLACK}):Play()
end)

local bubbleDragging, bubbleStart, bubbleStartPos
OpenBubble.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        bubbleDragging = true
        bubbleStart    = input.Position
        bubbleStartPos = OpenBubble.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                bubbleDragging = false
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if bubbleDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - bubbleStart
        OpenBubble.Position = UDim2.new(
            bubbleStartPos.X.Scale, bubbleStartPos.X.Offset + delta.X,
            bubbleStartPos.Y.Scale, bubbleStartPos.Y.Offset + delta.Y
        )
    end
end)

local function animateClose()
    local tween = TweenService:Create(
        Window,
        TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0.5, -20, 0.5, -20), BackgroundTransparency = 1}
    )
    tween:Play()
    tween.Completed:Connect(function()
        Window.Visible    = false
        Window.Size       = UDim2.new(0, 520, 0, 320)
        Window.Position   = UDim2.new(0.5, -260, 0.5, -160)
        Window.BackgroundTransparency = 0
        OpenBubble.Visible = true
        OpenBubble.Size    = UDim2.new(0, 0, 0, 0)
        TweenService:Create(OpenBubble, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 52, 0, 52)}):Play()
    end)
end

local function animateOpen()
    OpenBubble.Visible = false
    Window.Visible     = true
    Window.Size        = UDim2.new(0, 40, 0, 40)
    Window.Position    = UDim2.new(0.5, -20, 0.5, -20)
    local tween = TweenService:Create(
        Window,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 520, 0, 320), Position = UDim2.new(0.5, -260, 0.5, -160)}
    )
    tween:Play()
end

CloseBtn.MouseButton1Click:Connect(animateClose)
OpenBubble.MouseButton1Click:Connect(animateOpen)

-- ────────────────────────────────────────────────────────────────────────────
-- Live status
-- ────────────────────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not RageEnabled then return end

    if CurrentTarget and CurrentTarget.hum then
        Status.Text = string.format(
            "target: %s   hp: %.0f",
            CurrentTarget.char.Name,
            CurrentTarget.hum.Health
        )
    else
        Status.Text = "searching…"
    end

    local weapon = getEquippedWeapon()
    if weapon then
        if isThrowable(weapon) then
            local a = weapon:Get("Ammo") or 0
            AmmoLabel.Text = string.format("throws: %s", tostring(a))
        elseif isMelee(weapon) then
            if weapon.Info.NeedsAmmoToAttack then
                local a = weapon:Get("Ammo") or 0
                AmmoLabel.Text = string.format("melee ammo: %s", tostring(a))
            else
                AmmoLabel.Text = "melee: ∞"
            end
        else
            local a  = weapon:Get("Ammo") or 0
            local ar = weapon:Get("AmmoReserve") or 0
            if weapon.Info and weapon.Info.MaxAmmo == nil then
                AmmoLabel.Text = string.format("ammo: %s / ∞", tostring(a))
            else
                AmmoLabel.Text = string.format(
                    "ammo: %s / %s  %s",
                    tostring(a), tostring(ar),
                    ReloadState.awaiting_full and "[reloading]" or ""
                )
            end
        end
    else
        AmmoLabel.Text = "ammo: —"
    end

    BulletLabel.Text = string.format("bullet: %s", tostring(BulletsPerBullet))
end)
