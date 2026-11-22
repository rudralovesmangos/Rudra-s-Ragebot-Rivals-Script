local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

local FIRE_INTERVAL = 0.01
local BULLETS_PER_FRAME = 2
local FORCEFIELD_WAIT = 0.1
local EQUIP_WAIT_TIMEOUT = 3
local RELOAD_WAIT_TIMEOUT = 8
local POLL_INTERVAL = 0.1

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
Main.Size = UDim2.new(0, 230, 0, 130)
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
BarLabel.Text = "Rage  •  zero"
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

do
 local dragging, dragStart, startPos
 Bar.InputBegan:Connect(function(input)
  if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
   dragging = true
   dragStart = input.Position
   startPos = Main.Position
   input.Changed:Connect(function()
    if input.UserInputState == Enum.UserInputState.End then
     dragging = false
    end
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
}

local Modes = { "Humanoid", "Player Only" }

local function setStatus(s, color)
 Status.Text = s
 Status.TextColor3 = color or Color3.fromRGB(140, 200, 140)
end

local function localChar()
 return LP.Character
end

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
 if root and root.Parent and State.OriginalCFrame then
  root.CFrame = State.OriginalCFrame
 end
 if Workspace.CurrentCamera and State.OriginalCamera then
  Workspace.CurrentCamera.CFrame = State.OriginalCamera
 end
 State.SavedOrigin = false
end

RageBtn.MouseButton1Click:Connect(function()
 State.Rage = not State.Rage
 RageBtn.Text = "Rage: " .. (State.Rage and "ON" or "OFF")
 RageBtn.BackgroundColor3 = State.Rage and Color3.fromRGB(140, 45, 45) or Color3.fromRGB(55, 55, 70)
 if State.Rage then
  setStatus("armed", Color3.fromRGB(255, 200, 100))
 else
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

local INV_KEYS = { "Invincibility", "Invincible", "Invulnerable", "IsInvincible", "IsInvulnerable", "Forcefield", "ForceField", "HasForcefield", "HasForceField", "IsForcefielded", "Godmode", "GodMode" }

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

local ffCache = {}
local function bindFFCache(character)
 if ffCache[character] ~= nil then return end
 ffCache[character] = { dirty = true, value = false }
 character.DescendantAdded:Connect(function() ffCache[character].dirty = true end)
 character.DescendantRemoving:Connect(function() ffCache[character].dirty = true end)
 character.AncestryChanged:Connect(function() ffCache[character] = nil end)
end

local function scanCharacterForFF(character)
 local entry = ffCache[character]
 if entry and not entry.dirty then return entry.value end
 local found = false
 if character:FindFirstChildOfClass("ForceField") then
  found = true
 else
  for _, inst in ipairs(character:GetDescendants()) do
   if inst:IsA("ForceField") then found = true break end
   local n = inst.Name:lower()
   if (n:find("forcefield") or n:find("force field") or n:find("invincib") or n:find("invulner") or n:find("shield") or n:find("godmode") or n == "god") then
    if inst:IsA("BoolValue") then
     if inst.Value then found = true break end
    elseif inst:IsA("NumberValue") or inst:IsA("IntValue") then
     if inst.Value > 0 then found = true break end
    elseif inst:IsA("StringValue") then
     if inst.Value ~= "" and inst.Value ~= "0" and inst.Value:lower() ~= "false" then found = true break end
    elseif inst:IsA("BasePart") or inst:IsA("Highlight") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
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

local invConnections = {}
local function subscribeInvincibility(fighter, onChange)
 if not fighter then return end
 invConnections[fighter] = invConnections[fighter] or {}
 local ok, sig = pcall(function() return fighter:GetDataChangedSignal("Invincibility") end)
 if ok and sig then
  table.insert(invConnections[fighter], sig:Connect(function() onChange() end))
 end
 local ok2, sig2 = pcall(function() return fighter.InvincibilityChanged end)
 if ok2 and sig2 and sig2.Connect then
  table.insert(invConnections[fighter], sig2:Connect(function() onChange() end))
 end
end

local function clearInvincibilitySubs(fighter)
 if not fighter or not invConnections[fighter] then return end
 for _, c in ipairs(invConnections[fighter]) do pcall(function() c:Disconnect() end) end
 invConnections[fighter] = nil
end

local function isProtected(player, character, fighter)
 if hasRobloxForcefield(character) then return true end
 if hasAttributeForcefield(player, character) then return true end
 if fighter and fighterIsInvincible(fighter) then return true end
 return false
end

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

local function pickNearestHumanoid()
 local lr = localRoot()
 if not lr then return nil end
 local best, bestDist = nil, math.huge
 for _, inst in ipairs(Workspace:GetDescendants()) do
  if inst:IsA("Humanoid") and inst.Health > 0 then
   local model = inst.Parent
   local head = model and model:FindFirstChild("Head")
   local rootPart = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
   if head and rootPart and model ~= localChar() then
    local d = (rootPart.Position - lr.Position).Magnitude
    if d < bestDist then
     local plr = Players:GetPlayerFromCharacter(model)
     if isEnemy(plr, model) then
      best, bestDist = { Humanoid = inst, Model = model, Head = head, Root = rootPart, Player = plr }, d
     end
    end
   end
  end
 end
 return best
end

local function pickNearestPlayer()
 local lr = localRoot()
 if not lr then return nil end
 local best, bestDist = nil, math.huge
 for _, plr in ipairs(Players:GetPlayers()) do
  if plr ~= LP and isEnemy(plr, plr.Character) then
   local char = plr.Character
   local hum = char and char:FindFirstChildOfClass("Humanoid")
   local head = char and char:FindFirstChild("Head")
   local root = char and char:FindFirstChild("HumanoidRootPart")
   if hum and hum.Health > 0 and head and root then
    local d = (root.Position - lr.Position).Magnitude
    if d < bestDist then
     best, bestDist = { Humanoid = hum, Model = char, Head = head, Root = root, Player = plr }, d
    end
   end
  end
 end
 return best
end

local function findTarget()
 if State.Mode == "Player Only" then
  return pickNearestPlayer()
 end
 return pickNearestHumanoid()
end

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

local function getLocalFighter()
 return getFighter(LP)
end

-- only shoot gates; leaves reload state alone
local function resetShootGates(fighter)
 local it = fighter and fighter.EquippedItem
 if not it then return end
 it._shoot_cooldown = 0
 it._shoot_cooldown_no_ammo = 0
 it._last_shot = 0
 it._burst_count = 0
 it._is_revolver_quick_shooting = nil
 it._equip_finish = 0
 it._is_input_queueing = false
 if it.Data then it.Data.QuickAttackQueued = false end
end

local function ammoOf(it)
 local a = tonumber(it:Get("Ammo"))
 if a == nil then return math.huge end
 return a
end

local function reserveOf(it)
 local r = tonumber(it:Get("AmmoReserve"))
 if r == nil then return math.huge end
 return r
end

local function isGun(it)
 return it ~= nil and type(it.StartReloading) == "function"
end

local function listGuns(fighter)
 local guns = {}
 for i, it in ipairs(fighter.Items) do
  if isGun(it) then
   table.insert(guns, { index = i, item = it })
  end
 end
 return guns
end

local function indexOfGun(guns, item)
 for _, g in ipairs(guns) do
  if g.item == item then return g.index end
 end
 return nil
end

local function findNextFiringGun(fighter, currentItem)
 local guns = listGuns(fighter)
 if #guns == 0 then return nil end
 local currentIndex = indexOfGun(guns, currentItem) or 0
 local startPos = 1
 for i, g in ipairs(guns) do
  if g.index == currentIndex then startPos = i % #guns + 1 break end
 end
 for off = 0, #guns - 1 do
  local g = guns[(startPos - 1 + off) % #guns + 1]
  if ammoOf(g.item) > 0 then return g end
 end
 return nil
end

-- gun is "reloading" if its own _reload_cooldown field is in the future
local function isReloadingByGun(it)
 local rc = it._reload_cooldown
 return type(rc) == "number" and rc > tick()
end

local function engage(target)
 local hum = localHum()
 local root = localRoot()
 if not hum or not root then return end

 State.Target = target
 State.OriginalCFrame = root.CFrame
 State.OriginalCamera = Workspace.CurrentCamera.CFrame
 State.SavedOrigin = true

 local head = target.Head
 local targetHum = target.Humanoid
 local targetPlayer = target.Player
 local targetModel = target.Model
 local targetFighter = targetPlayer and getFighter(targetPlayer)

 local shooterFighter = getLocalFighter()

 local protectionDirty = false
 if targetFighter then
  subscribeInvincibility(targetFighter, function() protectionDirty = true end)
 end

 setStatus("engaging", Color3.fromRGB(255, 140, 140))

 local cam = Workspace.CurrentCamera
 local offsetVec = Vector3.new(0, 2.5, 0)
 local nextFire = 0

 local cycle = {
  phase = "fire",
  switchTargetItem = nil,
  reloadGuns = nil,
  reloadPos = 1,
  reloadDone = {},
  reloadWaitStart = {},
 }

 while State.Rage and State.Target == target do
  if not targetHum or targetHum.Health <= 0 or not targetModel or not targetModel.Parent or not head or not head.Parent then
   break
  end

  local protected = isProtected(targetPlayer, targetModel, targetFighter)
  root.CFrame = CFrame.new(head.Position + offsetVec)
  faceAt(head.Position, cam)

  if protected then
   if not protectionDirty then
    setStatus("forcefield — waiting", Color3.fromRGB(255, 210, 90))
   end
   protectionDirty = false
   cycle.phase = "fire"
   cycle.switchTargetItem = nil
   cycle.reloadGuns = nil
   task.wait(FORCEFIELD_WAIT)
   continue
  end

  if not shooterFighter then
   task.wait(0.1)
   continue
  end

  if cycle.phase == "fire" then
   local equipped = shooterFighter.EquippedItem
   if not equipped then
    local nextGun = findNextFiringGun(shooterFighter, nil)
    if nextGun then
     shooterFighter:EquipItem(nextGun.index)
     cycle.phase = "switch-wait"
     cycle.switchTargetItem = nextGun.item
    else
     cycle.reloadGuns = listGuns(shooterFighter)
     cycle.reloadPos = 1
     cycle.reloadDone = {}
     cycle.reloadWaitStart = {}
     cycle.phase = "reload"
    end
    task.wait(0.05)
    continue
   end

   if isGun(equipped) then
    if equipped:IsEquipping() then
     task.wait(POLL_INTERVAL)
     continue
    end

    local ammo = ammoOf(equipped)
    if ammo > 0 then
     if tick() >= nextFire then
      setStatus("killing: " .. (targetPlayer and targetPlayer.Name or tostring(targetModel)), Color3.fromRGB(255, 100, 100))
      resetShootGates(shooterFighter)
      for _ = 1, BULLETS_PER_FRAME do
       shooterFighter:Input("StartShooting")
      end
      nextFire = tick() + FIRE_INTERVAL
     end
     RunService.PreRender:Wait()
     continue
    else
     local nextGun = findNextFiringGun(shooterFighter, equipped)
     if nextGun and nextGun.item ~= equipped then
      setStatus("switching: " .. (nextGun.item.Name or "gun"), Color3.fromRGB(200, 200, 255))
      shooterFighter:EquipItem(nextGun.index)
      cycle.phase = "switch-wait"
      cycle.switchTargetItem = nextGun.item
      task.wait(0.05)
      continue
     else
      setStatus("reloading all", Color3.fromRGB(255, 180, 255))
      cycle.reloadGuns = listGuns(shooterFighter)
      cycle.reloadPos = 1
      cycle.reloadDone = {}
      cycle.reloadWaitStart = {}
      cycle.phase = "reload"
      task.wait(0.05)
      continue
     end
    end
   else
    local nextGun = findNextFiringGun(shooterFighter, equipped)
    if nextGun then
     shooterFighter:EquipItem(nextGun.index)
     cycle.phase = "switch-wait"
     cycle.switchTargetItem = nextGun.item
    else
     cycle.reloadGuns = listGuns(shooterFighter)
     cycle.reloadPos = 1
     cycle.reloadDone = {}
     cycle.reloadWaitStart = {}
     cycle.phase = "reload"
    end
    task.wait(0.05)
    continue
   end
  elseif cycle.phase == "switch-wait" then
   local it = cycle.switchTargetItem
   if not it or it.Parent == nil then
    cycle.phase = "fire"
    continue
   end
   if shooterFighter.EquippedItem == it and not it:IsEquipping() then
    cycle.phase = "fire"
    cycle.switchTargetItem = nil
   else
    task.wait(0.05)
   end
   continue
  elseif cycle.phase == "reload" then
   local guns = cycle.reloadGuns
   if not guns or cycle.reloadPos > #guns then
    cycle.phase = "fire"
    continue
   end

   local g = guns[cycle.reloadPos]
   local item = g.item
   local idx = g.index
   local now = tick()

   -- already done this pass
   if cycle.reloadDone[idx] then
    cycle.reloadPos = cycle.reloadPos + 1
    continue
   end

   -- ammo already full, or no reserve
   local ammo = ammoOf(item)
   local reserve = reserveOf(item)
   if ammo > 0 or reserve <= 0 then
    cycle.reloadDone[idx] = true
    cycle.reloadPos = cycle.reloadPos + 1
    continue
   end

   -- already being reloaded by the gun's own _CheckReload thread
   if isReloadingByGun(item) then
    if not cycle.reloadWaitStart[idx] then
     cycle.reloadWaitStart[idx] = now
    end
    if ammoOf(item) > 0 then
     cycle.reloadDone[idx] = true
     cycle.reloadPos = cycle.reloadPos + 1
    elseif now - cycle.reloadWaitStart[idx] > RELOAD_WAIT_TIMEOUT then
     cycle.reloadDone[idx] = true
     cycle.reloadPos = cycle.reloadPos + 1
    else
     task.wait(POLL_INTERVAL)
    end
    continue
   end

   -- ensure this gun is equipped
   if shooterFighter.EquippedItem ~= item then
    setStatus("equipping for reload: " .. tostring(item.Name or idx), Color3.fromRGB(255, 180, 255))
    shooterFighter:EquipItem(idx)
    local t0 = now
    while shooterFighter.EquippedItem ~= item and tick() - t0 < EQUIP_WAIT_TIMEOUT do
     task.wait(POLL_INTERVAL)
    end
    if shooterFighter.EquippedItem ~= item then
     cycle.reloadDone[idx] = true
     cycle.reloadPos = cycle.reloadPos + 1
    end
    continue
   end

   if item:IsEquipping() then
    task.wait(POLL_INTERVAL)
    continue
   end

   -- issue reload ONCE; do NOT reset reload cooldown, gun's own check will pass because it's empty
   if type(item.StartReloading) == "function" then
    -- make sure the call is accepted: only clear the minimum gate
    item._reload_cooldown = 0
    item._reload_cancel_cooldown = 0
    item._reload_cancel_expiration = 0
    item:Input("StartReloading")
    cycle.reloadWaitStart[idx] = tick()
   else
    cycle.reloadDone[idx] = true
    cycle.reloadPos = cycle.reloadPos + 1
   end
   continue
  end

  task.wait(POLL_INTERVAL)
 end

 if targetFighter then
  clearInvincibilitySubs(targetFighter)
 end

 restoreSavedPos()
 State.Target = nil
 setStatus("idle", Color3.fromRGB(140, 200, 140))
end

RunService.Heartbeat:Connect(function()
 if not State.Rage or State.Busy then return end
 if not localChar() or not localRoot() or not localHum() then return end
 if localHum().Health <= 0 then return end

 State.Busy = true
 task.spawn(function()
  local t = findTarget()
  if t then
   pcall(engage, t)
  end
  State.Busy = false
 end)
end)

setStatus("loaded — arm Rage", Color3.fromRGB(140, 200, 140))
print("[RageAimbot] script loaded successfully — end of script reached")
