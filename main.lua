--[[
  Rage  •  zero  — fixed build
  - Unified nearest-target pick (players + NPCs share one bestDist)
  - Humanoid mode restored to full workspace scan (throttled)
  - Custom + Roblox ForceField detection restored (cached, no lag)
  - Rapid-fire slider (0.5x – 10x), fire rate capped to frame budget
  - LoopTween: out via AssemblyLinearVelocity, back via instant TP
  - Noclip while tweening
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

-- fire tuning
local BASE_RATE_HZ    = 20
local FORCEFIELD_WAIT = 0.1
local RELOAD_WAIT_TIMEOUT = 5
local EQUIP_WAIT_TIMEOUT  = 1
local TARGET_SCAN_INTERVAL = 0.1

local MULT_MIN, MULT_MAX, MULT_DEFAULT = 0.5, 10.0, 1.0
local FireMult = MULT_DEFAULT

-- loop tween target
local LOOP_TWEEN_TARGET = Vector3.new(93949595949494, 39495948484959, 4949595949)
local LOOP_TWEEN_SPEED = 50000 -- very fast outbound

local function currentFireInterval()
    return 1.0 / (BASE_RATE_HZ * FireMult)
end

local function currentBulletsPerFrame()
    if FireMult >= 6.0 then return 3 end
    if FireMult >= 3.0 then return 2 end
    return 1
end

-- ── GUI ─────────────────────────────────────────────
local function getGuiParent()
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then return hui end
    local ok2, cg = pcall(function() return CoreGui end)
    if ok2 and cg then return cg end
    return LP:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RageAimbotUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
pcall(function() ScreenGui.Parent = guiParent end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LP:WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 230, 0, 190)
Main.Position = UDim2.new(0, 40, 0, 120)
Main.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
Main.BackgroundTransparency = 0.08
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(70, 70, 90)
Stroke.Thickness = 1
Stroke.Parent = Main

local Bar = Instance.new("Frame")
Bar.Name = "Bar"
Bar.Size = UDim2.new(1, 0, 0, 26)
Bar.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
Bar.BorderSizePixel = 0
Bar.Active = true
Bar.Parent = Main

local BarLabel = Instance.new("TextLabel")
BarLabel.Size = UDim2.new(1, -10, 1, 0)
BarLabel.Position = UDim2.new(0, 8, 0, 0)
BarLabel.BackgroundTransparency = 1
BarLabel.Text = "Rudra's Ragebot"
BarLabel.Font = Enum.Font.GothamBold
BarLabel.TextSize = 13
BarLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
BarLabel.TextXAlignment = Enum.TextXAlignment.Left
BarLabel.Parent = Bar

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -16, 0, 18)
Status.Position = UDim2.new(0, 8, 1, -22)
Status.BackgroundTransparency = 1
Status.Text = "idle"
Status.Font = Enum.Font.Code
Status.TextSize = 11
Status.TextColor3 = Color3.fromRGB(140, 200, 140)
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

local RageBtn = Instance.new("TextButton")
RageBtn.Size = UDim2.new(0, 100, 0, 34)
RageBtn.Position = UDim2.new(0, 10, 0, 36)
RageBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
RageBtn.BorderSizePixel = 0
RageBtn.Text = "Rage: OFF"
RageBtn.Font = Enum.Font.GothamBold
RageBtn.TextSize = 12
RageBtn.TextColor3 = Color3.fromRGB(240, 240, 250)
RageBtn.AutoButtonColor = true
RageBtn.Parent = Main
local RCB = Instance.new("UICorner")
RCB.CornerRadius = UDim.new(0, 6)
RCB.Parent = RageBtn

local ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(0, 100, 0, 34)
ModeBtn.Position = UDim2.new(0, 120, 0, 36)
ModeBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
ModeBtn.BorderSizePixel = 0
ModeBtn.Text = "Humanoid"
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.TextSize = 12
ModeBtn.TextColor3 = Color3.fromRGB(240, 240, 250)
ModeBtn.Parent = Main
local MCB = Instance.new("UICorner")
MCB.CornerRadius = UDim.new(0, 6)
MCB.Parent = ModeBtn

-- ── Rapid-fire slider ─────────────────────────────
local SliderLabel = Instance.new("TextLabel")
SliderLabel.Size = UDim2.new(1, -16, 0, 14)
SliderLabel.Position = UDim2.new(0, 8, 0, 78)
SliderLabel.BackgroundTransparency = 1
SliderLabel.Text = string.format("Rapid Fire: %.1fx", FireMult)
SliderLabel.Font = Enum.Font.GothamBold
SliderLabel.TextSize = 11
SliderLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
SliderLabel.Parent = Main

local SliderBack = Instance.new("Frame")
SliderBack.Size = UDim2.new(1, -16, 0, 10)
SliderBack.Position = UDim2.new(0, 8, 0, 96)
SliderBack.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
SliderBack.BorderSizePixel = 0
SliderBack.Parent = Main
local SBC = Instance.new("UICorner")
SBC.CornerRadius = UDim.new(1, 0)
SBC.Parent = SliderBack

local SliderFill = Instance.new("Frame")
SliderFill.Size = UDim2.new((FireMult - MULT_MIN) / (MULT_MAX - MULT_MIN), 0, 1, 0)
SliderFill.BackgroundColor3 = Color3.fromRGB(140, 45, 45)
SliderFill.BorderSizePixel = 0
SliderFill.Parent = SliderBack
local SFC = Instance.new("UICorner")
SFC.CornerRadius = UDim.new(1, 0)
SFC.Parent = SliderFill

local SliderKnob = Instance.new("Frame")
SliderKnob.Size = UDim2.new(0, 12, 0, 12)
SliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
SliderKnob.Position = UDim2.new((FireMult - MULT_MIN) / (MULT_MAX - MULT_MIN), 0, 0.5, 0)
SliderKnob.BackgroundColor3 = Color3.fromRGB(240, 240, 250)
SliderKnob.BorderSizePixel = 0
SliderKnob.Parent = SliderBack
local SKC = Instance.new("UICorner")
SKC.CornerRadius = UDim.new(1, 0)
SKC.Parent = SliderKnob

local sliderDragging = false

local function setFireMult(alpha)
    alpha = math.clamp(alpha, 0, 1)
    FireMult = MULT_MIN + alpha * (MULT_MAX - MULT_MIN)
    SliderFill.Size = UDim2.new(alpha, 0, 1, 0)
    SliderKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
    SliderLabel.Text = string.format("Rapid Fire: %.1fx", FireMult)
end

local function sliderUpdateFromX(inputX)
    local absX = SliderBack.AbsolutePosition.X
    local width = SliderBack.AbsoluteSize.X
    if width <= 0 then return end
    setFireMult((inputX - absX) / width)
end

SliderBack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = true
        sliderUpdateFromX(input.Position.X)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if sliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        sliderUpdateFromX(input.Position.X)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = false
    end
end)

-- ── Drag ──────────────────────────────────────────
do
    local dragging, dragStart, startPos
    Bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(0, startPos.X.Offset + delta.X, 0, startPos.Y.Offset + delta.Y)
        end
    end)
end

local State = {
    Rage = false,
    Mode = "Humanoid",
    Busy = false,
    Target = nil,
    OriginalCFrame = nil,
    OriginalCamera = nil,
    SavedOrigin = false,
    LastScan = 0,
    LoopTweenActive = false,
    LoopTweenOriginal = nil,
    NoclipActive = false,
    NoclipConn = nil,
}

local Modes = { "Humanoid", "Player Only" }

local function setStatus(s, color)
    Status.Text = s
    Status.TextColor3 = color or Color3.fromRGB(140, 200, 140)
end

local function localChar() return LP.Character end
local function localRoot()
    local c = localChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function localHum()
    local c = localChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function restoreSavedPos()
    if not State.SavedOrigin then return end
    local root = localRoot()
    if root and root.Parent and State.OriginalCFrame then root.CFrame = State.OriginalCFrame end
    if Workspace.CurrentCamera and State.OriginalCamera then Workspace.CurrentCamera.CFrame = State.OriginalCamera end
    State.SavedOrigin = false
end

-- ── Noclip (only while tweening) ─────────────────
local function startNoclip()
    if State.NoclipActive then return end
    State.NoclipActive = true
    State.NoclipConn = RunService.Stepped:Connect(function()
        local char = localChar()
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end)
end

local function stopNoclip()
    if not State.NoclipActive then return end
    State.NoclipActive = false
    if State.NoclipConn then
        State.NoclipConn:Disconnect()
        State.NoclipConn = nil
    end
    local char = localChar()
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Name == "HumanoidRootPart" then
                    part.CanCollide = false
                else
                    part.CanCollide = true
                end
            end
        end
    end
end

-- ── LoopTween: out via velocity, back via instant TP ─
local function startLoopTween()
    if State.LoopTweenActive then return end
    local root = localRoot()
    if not root then return end
    State.LoopTweenActive = true
    State.LoopTweenOriginal = root.Position
    startNoclip()
    task.spawn(function()
        while State.LoopTweenActive do
            local r = localRoot()
            if not r then break end
            local current = r.Position
            local target = LOOP_TWEEN_TARGET
            if (current - target).Magnitude < 50 then
                -- return trip: instant teleport back to original
                local back = State.LoopTweenOriginal
                if back then
                    r.CFrame = CFrame.new(back)
                    r.AssemblyLinearVelocity = Vector3.new(0,0,0)
                end
            else
                local dir = (target - current)
                if dir.Magnitude > 0.01 then
                    r.AssemblyLinearVelocity = dir.Unit * LOOP_TWEEN_SPEED
                else
                    r.AssemblyLinearVelocity = Vector3.new(0,0,0)
                end
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

local function stopLoopTween()
    State.LoopTweenActive = false
    local root = localRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.new(0,0,0)
    end
    State.LoopTweenOriginal = nil
    stopNoclip()
end

RageBtn.MouseButton1Click:Connect(function()
    State.Rage = not State.Rage
    RageBtn.Text = "Rage: " .. (State.Rage and "ON" or "OFF")
    RageBtn.BackgroundColor3 = State.Rage and Color3.fromRGB(140, 45, 45) or Color3.fromRGB(55, 55, 70)
    if State.Rage then
        setStatus("armed", Color3.fromRGB(255, 200, 100))
    else
        stopLoopTween()
        restoreSavedPos()
        State.Target = nil
        setStatus("idle — returned", Color3.fromRGB(140, 200, 140))
    end
end)

ModeBtn.MouseButton1Click:Connect(function()
    local idx = 1
    for i, m in ipairs(Modes) do if m == State.Mode then idx = i break end end
    idx = idx % #Modes + 1
    State.Mode = Modes[idx]
    ModeBtn.Text = State.Mode
end)

-- ── Fighter plumbing ─────────────────────────────
local FighterController = nil
do
    local ok, mod = pcall(function()
        return require(LP.PlayerScripts.Controllers:WaitForChild("FighterController", 5))
    end)
    if ok and mod then FighterController = mod end
end

local function getFighter(player)
    if not FighterController then return nil end
    local ok, f = pcall(function() return FighterController:GetFighter(player) end)
    if ok then return f end
    return nil
end

local EnumLibrary = nil
do
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnumLibrary"))
    end)
    if ok then EnumLibrary = mod end
end

local INV_KEYS = {
    "Invincibility", "Invincible", "Invulnerable", "IsInvincible", "IsInvulnerable",
    "Forcefield", "ForceField", "HasForcefield", "HasForceField", "IsForcefielded",
    "Godmode", "GodMode",
}

local function fighterGet(fighter, key)
    if not fighter then return nil end
    local ok, v = pcall(function() return fighter:Get(key) end)
    if ok and v ~= nil then return v end
    if EnumLibrary then
        local ok2, enum = pcall(function() return EnumLibrary:ToEnum(key, true) end)
        if ok2 and enum then
            local ok3, v2 = pcall(function() return fighter:Get(enum) end)
            if ok3 and v2 ~= nil then return v2 end
        end
    end
    return nil
end

local function fighterIsInvincible(fighter)
    if not fighter then return false end
    for _, k in ipairs(INV_KEYS) do
        local v = fighterGet(fighter, k)
        if v then return true end
    end
    return false
end

-- ── Optimized forcefield detection (cached) ──────
local ffCache = {}

local function bindFFCache(character)
    if ffCache[character] then return end
    ffCache[character] = { dirty = true, value = false }
    character.DescendantAdded:Connect(function()
        local e = ffCache[character]
        if e then e.dirty = true end
    end)
    character.DescendantRemoving:Connect(function()
        local e = ffCache[character]
        if e then e.dirty = true end
    end)
    character.AncestryChanged:Connect(function()
        if not character:IsDescendantOf(Workspace) then
            ffCache[character] = nil
        end
    end)
end

local function scanCharacterForFF(character)
    local entry = ffCache[character]
    if entry and not entry.dirty then return entry.value end

    local found = false
    if character:FindFirstChildOfClass("ForceField") then
        found = true
    else
        for _, inst in ipairs(character:GetDescendants()) do
            if inst:IsA("ForceField") then
                found = true
                break
            end
            local n = inst.Name:lower()
            if n:find("forcefield", 1, true)
                or n:find("force field", 1, true)
                or n:find("invincib", 1, true)
                or n:find("invulner", 1, true)
                or n:find("shield", 1, true)
                or n:find("godmode", 1, true)
                or n == "god" then
                if inst:IsA("BoolValue") then
                    if inst.Value then found = true break end
                elseif inst:IsA("NumberValue") or inst:IsA("IntValue") then
                    if inst.Value > 0 then found = true break end
                elseif inst:IsA("StringValue") then
                    if inst.Value ~= "" and inst.Value ~= "0"
                        and inst.Value:lower() ~= "false" then
                        found = true break
                    end
                elseif inst:IsA("BasePart")
                    or inst:IsA("Highlight")
                    or inst:IsA("ParticleEmitter")
                    or inst:IsA("Beam")
                    or inst:IsA("Trail") then
                    found = true break
                end
            end
        end
    end

    if entry then
        entry.dirty = false
        entry.value = found
    end
    return found
end

local function hasRobloxForcefield(character)
    if not character then return false end
    bindFFCache(character)
    return scanCharacterForFF(character)
end

local function hasAttributeForcefield(player, character)
    local function check(obj)
        if not obj then return false end
        for _, name in ipairs(INV_KEYS) do
            local ok, v = pcall(function() return obj:GetAttribute(name) end)
            if ok and v then return true end
        end
        return false
    end
    if check(player) then return true end
    if check(character) then return true end
    return false
end

-- ── Fighter invincibility signal (cached) ───────
local invConnections = {}
local invDirtyFlag = {}

local function subscribeInvincibility(fighter)
    if not fighter or invConnections[fighter] then return end
    invConnections[fighter] = {}
    invDirtyFlag[fighter] = { dirty = true }
    local flag = invDirtyFlag[fighter]

    local ok, sig = pcall(function() return fighter:GetDataChangedSignal("Invincibility") end)
    if ok and sig then
        table.insert(invConnections[fighter], sig:Connect(function() flag.dirty = true end))
    end

    local ok2, sig2 = pcall(function() return fighter.InvincibilityChanged end)
    if ok2 and sig2 and sig2.Connect then
        table.insert(invConnections[fighter], sig2:Connect(function() flag.dirty = true end))
    end
end

local function fighterIsInvincibleCached(fighter)
    if not fighter then return false end
    local flag = invDirtyFlag[fighter]
    if not flag then return fighterIsInvincible(fighter) end
    if not flag.dirty then return flag.value == true end
    local v = fighterIsInvincible(fighter)
    flag.dirty = false
    flag.value = v
    return v
end

local function clearInvincibilitySubs(fighter)
    if not fighter then return end
    local conns = invConnections[fighter]
    if conns then
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    end
    invConnections[fighter] = nil
    invDirtyFlag[fighter] = nil
end

local function isProtected(player, character, fighter)
    if hasRobloxForcefield(character) then return true end
    if hasAttributeForcefield(player, character) then return true end
    if fighter then
        subscribeInvincibility(fighter)
        if fighterIsInvincibleCached(fighter) then return true end
    end
    return false
end

-- ── Team plumbing ────────────────────────────────
local LOCAL_TEAM
local function refreshLocalTeam()
    LOCAL_TEAM = nil
    local f = getFighter(LP)
    if f then
        local v = fighterGet(f, "TeamID")
        if v ~= nil then LOCAL_TEAM = v end
    end
    if LOCAL_TEAM == nil then
        local ok, v = pcall(function() return LP:GetAttribute("TeamID") end)
        if ok and v ~= nil then LOCAL_TEAM = v end
    end
end
refreshLocalTeam()
LP.AttributeChanged:Connect(function(name)
    if name == "TeamID" then refreshLocalTeam() end
end)

local function teamOf(player, model)
    if player then
        local f = getFighter(player)
        if f then
            local v = fighterGet(f, "TeamID")
            if v ~= nil then return v end
        end
        local ok, v = pcall(function() return player:GetAttribute("TeamID") end)
        if ok and v ~= nil then return v end
    end
    if model then
        local ok, v = pcall(function() return model:GetAttribute("TeamID") end)
        if ok and v ~= nil then return v end
    end
    return nil
end

local function isEnemy(player, model)
    if LOCAL_TEAM == nil then return true end
    local t = teamOf(player, model)
    if t == nil then return true end
    return t ~= LOCAL_TEAM
end

-- ── Target picking (unified nearest) ─────────────
local function pickNearest()
    local lr = localRoot()
    if not lr then return nil end
    local myChar = localChar()
    local lrPos  = lr.Position

    local best, bestDist = nil, math.huge

    -- 1) players
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local char = plr.Character
            if char and char ~= myChar then
                local hum  = char:FindFirstChildOfClass("Humanoid")
                local head = char:FindFirstChild("Head")
                local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
                if hum and hum.Health > 0 and head and root and isEnemy(plr, char) then
                    local d = (root.Position - lrPos).Magnitude
                    if d < bestDist then
                        best, bestDist = {
                            Humanoid = hum, Model = char, Head = head,
                            Root = root, Player = plr,
                        }, d
                    end
                end
            end
        end
    end

    -- 2) NPCs (Humanoid mode only), same bestDist
    if State.Mode ~= "Player Only" then
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("Humanoid") and inst.Health > 0 then
                local model = inst.Parent
                if model and model ~= myChar and not Players:GetPlayerFromCharacter(model) then
                    local head = model:FindFirstChild("Head")
                    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                    if head and root and isEnemy(nil, model) then
                        local d = (root.Position - lrPos).Magnitude
                        if d < bestDist then
                            best, bestDist = {
                                Humanoid = inst, Model = model, Head = head,
                                Root = root, Player = nil,
                            }, d
                        end
                    end
                end
            end
        end
    end

    return best
end

local function findTarget()
    return pickNearest()
end

-- Camera aim (only writes when direction changes meaningfully)
local function faceAt(pos, cam)
    cam = cam or Workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position
    local dir = pos - camPos
    local mag = dir.Magnitude
    if mag < 0.01 then return end
    local look = cam.CFrame.LookVector
    local dot = (look.X*dir.X + look.Y*dir.Y + look.Z*dir.Z) / mag
    if dot > 0.9995 then return end
    cam.CFrame = CFrame.lookAt(camPos, pos)
end

local function getLocalFighter() return getFighter(LP) end

local function resetWeaponGates(fighter)
    local it = fighter and fighter.EquippedItem
    if not it then return end
    it._shoot_cooldown = 0
    it._shoot_cooldown_no_ammo = 0
    it._reload_cooldown = 0
    it._reload_cancel_cooldown = 0
    it._reload_cancel_expiration = 0
    it._last_shot = 0
    it._burst_count = 0
    it._is_revolver_quick_shooting = nil
    it._equip_finish = 0
    it._is_input_queueing = false
    if it.Data then it.Data.QuickAttackQueued = false end
end

local function getAmmoInfo(item)
    if not item then return { ammo = 0, reserve = 0, infinite = false, infiniteReserve = false } end
    local okA, ammo    = pcall(function() return item:Get("Ammo") end)
    local okR, reserve = pcall(function() return item:Get("AmmoReserve") end)
    local okInf, inf   = pcall(function() return item:Get("InfiniteAmmo") end)
    local okInfR, infR = pcall(function() return item:Get("InfiniteAmmoReserve") end)
    ammo    = okA and ammo or nil
    reserve = okR and reserve or nil
    if ammo == math.huge then
        return { ammo = math.huge, reserve = reserve or 0, infinite = true, infiniteReserve = okInfR and infR or false }
    end
    return {
        ammo    = tonumber(ammo) or 0,
        reserve = tonumber(reserve) or 0,
        infinite = okInf and inf or false,
        infiniteReserve = okInfR and infR or false,
    }
end

local function itemHasAmmo(item)
    local info = getAmmoInfo(item)
    if info.infinite then return true end
    return info.ammo > 0
end

local function isWeaponItem(item)
    if not item then return false end
    if type(item.StartShooting) ~= "function" then return false end
    return item.Info ~= nil
end

local function itemKey(item)
    if not item then return nil end
    local ok, id = pcall(function() return item:Get("ObjectID") end)
    if ok and id ~= nil then return id end
    return item
end

local function indexOfItem(fighter, item)
    if not fighter or not item then return nil end
    for i, v in ipairs(fighter.Items) do
        if v == item then return i end
    end
    return nil
end

local function findNextWeaponWithAmmo(fighter, currentIndex, emptySet)
    if not fighter then return nil end
    local n = #fighter.Items
    if n == 0 then return nil end
    for step = 1, n do
        local idx = ((currentIndex - 1 + step) % n) + 1
        local it = fighter.Items[idx]
        if idx ~= currentIndex and isWeaponItem(it) then
            local key = itemKey(it)
            local live = itemHasAmmo(it)
            if live and emptySet and key then emptySet[key] = nil end
            if live and not (emptySet and emptySet[key]) then return idx end
        end
    end
    return nil
end

local function equipAndWait(fighter, idx, timeout)
    if not fighter or not idx then return false end
    local targetItem = fighter.Items[idx]
    if not targetItem then return false end
    if fighter.EquippedItem ~= targetItem then
        pcall(function() fighter:EquipItem(idx, true) end)
    end
    timeout = timeout or EQUIP_WAIT_TIMEOUT
    local t0 = tick()
    while tick() - t0 < timeout do
        if fighter.EquippedItem == targetItem then return true end
        task.wait(0.02)
    end
    return fighter.EquippedItem == targetItem
end

local function reloadEquipped(fighter, timeout)
    if not fighter then return false end
    local it = fighter.EquippedItem
    if not it then return false end
    resetWeaponGates(fighter)
    it._reload_cooldown = 0
    it._reload_cancel_cooldown = 0
    it._reload_cancel_expiration = 0
    pcall(function() fighter:Input("StartReloading") end)
    timeout = timeout or RELOAD_WAIT_TIMEOUT
    local t0 = tick()
    while tick() - t0 < timeout do
        if not State.Rage then return false end
        local info = getAmmoInfo(it)
        if info.infinite or info.ammo > 0 then return true end
        if info.reserve <= 0 and not info.infiniteReserve then return false end
        task.wait(0.05)
    end
    return false
end

local function handleAmmo(fighter, emptyWeapons)
    if not fighter then return false end
    local equipped = fighter.EquippedItem
    if not equipped then return false end
    if not isWeaponItem(equipped) then return false end

    if itemHasAmmo(equipped) then
        local key = itemKey(equipped)
        if key and emptyWeapons then emptyWeapons[key] = nil end
        return false
    end

    local equippedKey = itemKey(equipped)
    if equippedKey then emptyWeapons[equippedKey] = true end

    local curIdx = indexOfItem(fighter, equipped)
    if not curIdx then return false end

    local nextIdx = findNextWeaponWithAmmo(fighter, curIdx, emptyWeapons)
    if nextIdx then
        setStatus("switching weapon", Color3.fromRGB(255, 210, 90))
        startLoopTween()
        equipAndWait(fighter, nextIdx, EQUIP_WAIT_TIMEOUT)
        stopLoopTween()
        return true
    end

    setStatus("reloading", Color3.fromRGB(140, 200, 255))
    startLoopTween()
    local ok = reloadEquipped(fighter)
    if ok and equippedKey then emptyWeapons[equippedKey] = nil end
    stopLoopTween()
    return true
end

-- ── Engage loop ──────────────────────────────────
local function engage(target)
    local hum  = localHum()
    local root = localRoot()
    if not hum or not root then return end

    State.Target = target
    State.OriginalCFrame = root.CFrame
    State.OriginalCamera = Workspace.CurrentCamera.CFrame
    State.SavedOrigin = true

    local head          = target.Head
    local targetHum     = target.Humanoid
    local targetPlayer  = target.Player
    local targetModel   = target.Model
    local targetFighter = targetPlayer and getFighter(targetPlayer)

    local shooterFighter = getLocalFighter()

    setStatus("engaging", Color3.fromRGB(255, 140, 140))

    local cam = Workspace.CurrentCamera
    local offsetVec = Vector3.new(0, 2.5, 0)
    local nextFire = 0
    local emptyWeapons = {}

    while State.Rage and State.Target == target do
        if not targetHum or targetHum.Health <= 0
            or not targetModel or not targetModel.Parent
            or not head or not head.Parent then break end

        if isProtected(targetPlayer, targetModel, targetFighter) then
            setStatus("forcefield — waiting", Color3.fromRGB(255, 210, 90))
            startLoopTween()
            root.CFrame = CFrame.new(head.Position + offsetVec)
            faceAt(head.Position, cam)
            task.wait(FORCEFIELD_WAIT)
            continue
        end

        if shooterFighter then
            local handled = handleAmmo(shooterFighter, emptyWeapons)
            if handled then
                startLoopTween()
                root.CFrame = CFrame.new(head.Position + offsetVec)
                faceAt(head.Position, cam)
                if not State.Rage then break end
                task.wait(0.02)
                continue
            end
        end

        local now = tick()
        if now < nextFire then
            root.CFrame = CFrame.new(head.Position + offsetVec)
            faceAt(head.Position, cam)
            task.wait(0.01)
            continue
        end

        setStatus("killing: " .. (targetPlayer and targetPlayer.Name or tostring(targetModel)), Color3.fromRGB(255, 100, 100))

        root.CFrame = CFrame.new(head.Position + offsetVec)
        faceAt(head.Position, cam)

        if shooterFighter and not isProtected(targetPlayer, targetModel, targetFighter) then
            resetWeaponGates(shooterFighter)
            local bpf = currentBulletsPerFrame()
            for _ = 1, bpf do
                shooterFighter:Input("StartShooting")
            end
        end

        local interval = currentFireInterval()
        if interval < 0.0166 then interval = 0.0166 end
        nextFire = now + interval

        task.wait(interval)
    end

    if targetFighter then clearInvincibilitySubs(targetFighter) end
    stopLoopTween()
    restoreSavedPos()
    State.Target = nil
    setStatus("idle", Color3.fromRGB(140, 200, 140))
end

RunService.Heartbeat:Connect(function()
    if not State.Rage or State.Busy then return end
    if not localChar() or not localRoot() or not localHum() then return end
    if localHum().Health <= 0 then return end

    local now = tick()
    if now - State.LastScan < TARGET_SCAN_INTERVAL and State.Target then return end
    State.LastScan = now

    State.Busy = true
    local ok, err = pcall(function()
        local t = findTarget()
        if t then engage(t) else startLoopTween() end
    end)
    State.Busy = false
    if not ok then
        warn("[RageAimbot] engage error: " .. tostring(err))
    end
end)

setStatus("loaded — arm Rage", Color3.fromRGB(140, 200, 140))
print("[RageAimbot] fixed build loaded — title changed to Rudra's Ragebot")
