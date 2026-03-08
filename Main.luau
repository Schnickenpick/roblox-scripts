--[[
██╗   ██╗███████╗██████╗ ██████╗  █████╗ ██╗         ██╗   ██╗██╗  ██╗
██║   ██║██╔════╝██╔══██╗██╔══██╗██╔══██╗██║         ██║   ██║██║  ██║
██║   ██║█████╗  ██████╔╝██████╔╝███████║██║         ██║   ██║███████║
╚██╗ ██╔╝██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║         ╚██╗ ██╔╝╚════██║
 ╚████╔╝ ███████╗██║  ██║██████╔╝██║  ██║███████╗     ╚████╔╝      ██║
  ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝     ╚═══╝       ╚═╝
  Verbal Sigma Master v4 | Obsidian UI
  All message.txt features + all kick variants + fixed Bring/Build
--]]

-- ============================================================
-- [[ 1. SERVICES ]]
-- ============================================================

local LP          = game:GetService("Players").LocalPlayer
local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local TweenSvc    = game:GetService("TweenService")
local Lighting    = game:GetService("Lighting")
local Workspace   = workspace
local Camera      = Workspace.CurrentCamera

-- ============================================================
-- [[ 2. OBSIDIAN UI ]]
-- ============================================================

local repo         = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Window = Library:CreateWindow({
    Title             = "Verbal Sigma v4",
    Footer            = "Full Edition",
    NotifySide        = "Right",
    ShowCustomCursor  = false,
    MobileButtonsSide = "Right",
})

local function Notify(title, desc, t)
    Library:Notify({ Title = title, Description = desc or "", Time = t or 3 })
end

-- ============================================================
-- [[ 3. REMOTES (resolved async) ]]
-- ============================================================

local Remotes = {}
task.spawn(function()
    local CE = RS:WaitForChild("CharacterEvents", 10)
    if CE then
        Remotes.Struggle      = CE:FindFirstChild("Struggle")
        Remotes.RagdollRemote = CE:FindFirstChild("RagdollRemote")
    end
    local GE = RS:WaitForChild("GrabEvents", 10)
    if GE then
        Remotes.SetNetworkOwner = GE:FindFirstChild("SetNetworkOwner")
        Remotes.CreateGrabLine  = GE:FindFirstChild("CreateGrabLine")
        Remotes.DestroyGrabLine = GE:FindFirstChild("DestroyGrabLine")
        Remotes.ExtendGrabLine  = GE:FindFirstChild("ExtendGrabLine")
    end
    local MT = RS:FindFirstChild("MenuToys")
    if MT then
        Remotes.SpawnToy   = MT:FindFirstChild("SpawnToyRemoteFunction")
        Remotes.DestroyToy = MT:FindFirstChild("DestroyToy")
    end
    local GCE = RS:FindFirstChild("GameCorrectionEvents")
    if GCE then Remotes.StopAllVelocity = GCE:FindFirstChild("StopAllVelocity") end
    local PE = RS:FindFirstChild("PlayerEvents")
    if PE then Remotes.StickyPartEvent = PE:FindFirstChild("StickyPartEvent") end
end)

-- Grab remote copies before Anti-Lag nukes them
local grabLineCopy, extendLineCopy
task.spawn(function()
    local GE = RS:WaitForChild("GrabEvents", 10); if not GE then return end
    local c = GE:FindFirstChild("CreateGrabLine")
    local e = GE:FindFirstChild("ExtendGrabLine")
    if c then grabLineCopy  = c:Clone() end
    if e then extendLineCopy = e:Clone() end
end)

-- Slow-load values
local IsHeldValue = nil
task.spawn(function() IsHeldValue = LP:WaitForChild("IsHeld", 10) end)
local CanSpawnToy = nil
task.spawn(function() CanSpawnToy = LP:WaitForChild("CanSpawnToy", 10) end)

-- ============================================================
-- [[ 4. HELPER FUNCTIONS ]]
-- ============================================================

local function getChar()  return LP.Character end
local function getRoot()  return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") end
local function getHum()   return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end
local function getToyFolder() return Workspace:FindFirstChild(LP.Name.."SpawnedInToys") end
local function disconnect(c) if c and c.Connected then c:Disconnect() end end

local function getMountedBlobman()
    local hum = getHum()
    local seat = hum and hum.SeatPart
    if seat and seat.Parent and seat.Parent.Name == "CreatureBlobman" then
        return seat.Parent
    end
end

-- ── Spawn blobman and anchor head away ───────────────────────
local function spawnBlobman()
    pcall(function()
        RS.MenuToys.SpawnToyRemoteFunction:InvokeServer(
            "CreatureBlobman", CFrame.new(0,-100,0), Vector3.new(0,60,0))
    end)
    task.wait(0.8)
    local f = getToyFolder()
    local b = f and f:FindFirstChild("CreatureBlobman")
    if b then
        local h = b:FindFirstChild("Head")
        if h then h.CFrame = CFrame.new(0,-100,0); h.Anchored = true end
        Notify("Blobman","Spawned!",2)
    end
    return b
end

local function getOrSpawnBlob()
    local f = getToyFolder()
    local b = f and f:FindFirstChild("CreatureBlobman")
    if not b then b = spawnBlobman() end
    return b
end

-- ── Sit on OWN blobman (always in the sky) ──────────────────
local function autoSitMyBlob()
    task.spawn(function()
        local hrp = getRoot(); local hum = getHum()
        if not (hrp and hum) then Notify("Error","No character",2); return end
        local blob = getOrSpawnBlob()
        if not blob then Notify("Error","No blobman",2); return end
        -- Always reposition blobman to sky before trying to sit
        local blobRoot = blob:FindFirstChild("HumanoidRootPart") or blob.PrimaryPart
        if blobRoot then
            blobRoot.CFrame = CFrame.new(0, -100, 0)
            blobRoot.AssemblyLinearVelocity  = Vector3.zero
            blobRoot.AssemblyAngularVelocity = Vector3.zero
        end
        local head = blob:FindFirstChild("Head")
        if head then head.CFrame = CFrame.new(0, -100, 200); head.Anchored = true end
        local seat = blob:WaitForChild("VehicleSeat", 5)
        if not seat then Notify("Error","No VehicleSeat",2); return end
        task.wait(0.15)
        local t = tick()
        repeat
            hrp.CFrame = seat.CFrame + Vector3.new(0,1,0)
            hrp.AssemblyLinearVelocity = Vector3.zero
            seat:Sit(hum)
            RunService.Heartbeat:Wait()
        until hum.SeatPart == seat or tick()-t > 3
        if hum.SeatPart == seat then Notify("Blob","Seated in sky!",2)
        else Notify("Blob","Failed to sit – try again",2) end
    end)
end

-- ── Sit on NEAREST blobman (any player's) ───────────────────
local function sitNearestBlob(maxDist)
    local hrp = getRoot(); local hum = getHum()
    if not (hrp and hum) then return end
    if hum.SeatPart then return end
    local best, bestDist = nil, maxDist or 40
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") and m.Name == "CreatureBlobman" then
            local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            if r then
                local d = (r.Position - hrp.Position).Magnitude
                if d < bestDist then bestDist = d; best = m end
            end
        end
    end
    if not best then Notify("Blob","No nearby blobman",2); return end
    local seat = best:FindFirstChildWhichIsA("VehicleSeat",true)
               or best:FindFirstChildWhichIsA("Seat",true)
    if not seat then Notify("Blob","No seat found",2); return end
    hrp.CFrame = seat.CFrame * CFrame.new(0,1.2,-1)
    task.wait(0.05)
    pcall(function() seat:Sit(hum) end)
end

-- ── Target selector (Obsidian SpecialType="Player") ──────────
local function getTarget()
    local v = Options.TargetPlayer and Options.TargetPlayer.Value
    if type(v) == "string" then return Players:FindFirstChild(v) end
    return v
end

-- ============================================================
-- [[ 5. GLOBAL STATE ]]
-- ============================================================

local S = {
    -- Defense
    physicsAnchor  = false,
    autoStruggle   = false,
    antiVoid       = false,
    godMode        = false,
    antiExplosion  = false,
    antiBurn       = false,
    antiSticky     = false,
    antiLag        = false,
    antiPaint      = false,
    antiGucci      = false,
    antiGucciTrain = false,
    antiBlobman    = false,
    antiKickRag    = false,
    antiKickKunai  = false,
    antiInputLag   = false,
    loopTP         = false,
    ghostMode      = false,
    -- Combat
    kickSpam      = false,
    kickRagdoll   = false,
    kickGrabTroll = false,
    kickBlob      = false,
    dualKickLoop  = false,
    ragdollSnow   = false,
    loopKill      = false,
    flingActive   = false,
    destroyGucci  = false,
    removeAK      = false,
    removeAKAura  = false,
    removeAIL     = false,
    killGrab      = false,
    throwStrength = false,
    masslessGrab  = false,
    -- Player
    infJump       = false,
    thirdPerson   = false,
    spinChar      = false,
    pcldESP       = false,
    nameESP       = false,
    noclip        = false,
    -- Auras
    dualKickAura  = false,
    kickAura1     = false,
    -- Misc
    dreamyNight   = false,
    noBarrier     = false,
    packetLag     = false,
    autoReset     = false,
    triggerbot    = false,
    animPlay      = false,
    joinNotify    = false,
    -- Fun
    jerkOff       = false,
    bang          = false,
    followStare   = false,
    fakeDeath     = false,
    fakeLag       = false,
    heartBuild    = false,
    ufoShuriken   = false,
}

-- ============================================================
-- [[ 6. MOVE SPEED (for Physics Anchor WASD movement) ]]
-- ============================================================

local anchorMoveSpeed = 16
local targetWalkSpeed = 16
local spinSpeed       = 5

-- ============================================================
-- [[ 7. MASTER HEARTBEAT ]]
-- ============================================================

local lastSafeY = 50

RunService.Heartbeat:Connect(function(dt)
    local char = getChar(); if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid")

    -- Physics Anchor (v3 carry-over — keep your own grab protection)
    if S.physicsAnchor and root then
        if IsHeldValue and IsHeldValue.Value then
            root.Anchored = true
            root.AssemblyLinearVelocity  = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if hum and hum.MoveDirection.Magnitude > 0 then
                root.CFrame = root.CFrame + (hum.MoveDirection * anchorMoveSpeed * dt)
            end
            pcall(function()
                if Remotes.Struggle then Remotes.Struggle:FireServer(LP) end
                if Remotes.StopAllVelocity then Remotes.StopAllVelocity:FireServer() end
            end)
        elseif root.Anchored then
            root.Anchored = false
        end
    end

    -- Anti-Void
    if S.antiVoid and root then
        local y = root.Position.Y
        if y >= -50 then lastSafeY = y
        elseif lastSafeY then
            char:SetPrimaryPartCFrame(CFrame.new(root.Position.X, lastSafeY+100, root.Position.Z))
            root.AssemblyLinearVelocity = Vector3.zero
            Notify("Anti-Void","Rescued!",2)
        end
    end

    -- God Mode
    if S.godMode and hum and hum.Health < hum.MaxHealth then
        hum.Health = hum.MaxHealth
    end

    -- Noclip
    if S.noclip then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end

    -- Spin
    if S.spinChar and root then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0)
    end
end)

-- ============================================================
-- [[ 8. AUTO-STRUGGLE LOOP ]]
-- ============================================================

task.spawn(function()
    while true do
        task.wait(0.01)
        if not S.autoStruggle then continue end
        local char = getChar(); if not char then continue end
        local head   = char:FindFirstChild("Head")
        local isHeld = IsHeldValue and IsHeldValue.Value
        if not (isHeld or (head and head:FindFirstChild("PartOwner"))) then continue end
        for _, p in pairs(char:GetChildren()) do
            if p:IsA("BasePart") then p.Anchored = true end
        end
        pcall(function()
            if Remotes.Struggle then Remotes.Struggle:FireServer(LP) end
            if Remotes.StopAllVelocity then Remotes.StopAllVelocity:FireServer() end
        end)
        repeat
            task.wait()
            char = getChar(); if not char then break end
            head = char:FindFirstChild("Head")
        until not (IsHeldValue and IsHeldValue.Value)
           and not (head and head:FindFirstChild("PartOwner"))
        if char then
            for _, p in pairs(char:GetChildren()) do
                if p:IsA("BasePart") then p.Anchored = false end
            end
        end
    end
end)

-- ============================================================
-- [[ 9. RAGDOLL ANTI-KICK LOOP ]]
-- ============================================================

task.spawn(function()
    while true do
        task.wait(0.1)
        if not S.antiKickRag then continue end
        local root  = getRoot()
        local CE    = RS:FindFirstChild("CharacterEvents")
        local remote = CE and CE:FindFirstChild("RagdollRemote")
        if root and remote then pcall(function() remote:FireServer(root,0) end) end
    end
end)

-- ============================================================
-- [[ 10. KUNAI ANTI-KICK (StickyPartEvent shield) ]]
-- ============================================================

_G.ShurikenAntiKick = false

local function clearKunai()
    local inv = getToyFolder()
    local d   = RS:FindFirstChild("MenuToys") and RS.MenuToys:FindFirstChild("DestroyToy")
    if not (inv and d) then return end
    for _, v in pairs(inv:GetChildren()) do
        if v.Name == "AntiKick" or v.Name == "NinjaShuriken" then
            pcall(function() d:FireServer(v) end)
        end
    end
end

local function startKunaiAntiKick()
    task.spawn(function()
        local setOwner  = RS:WaitForChild("GrabEvents"):WaitForChild("SetNetworkOwner")
        local stickyEv  = RS:WaitForChild("PlayerEvents"):WaitForChild("StickyPartEvent")
        local spawnRem  = RS.MenuToys.SpawnToyRemoteFunction
        local function getHRP()
            if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
                return LP.Character.HumanoidRootPart
            end
            return LP.CharacterAdded:Wait():WaitForChild("HumanoidRootPart")
        end
        local function stickKunai(kunai)
            if not kunai or not kunai:FindFirstChild("StickyPart") then return end
            local hrp = getHRP(); if not hrp then return end
            local sp = kunai:FindFirstChild("SoundPart")
            if sp and (not sp:FindFirstChild("PartOwner") or sp.PartOwner.Value ~= LP.Name) then
                pcall(function() setOwner:FireServer(sp, sp.CFrame) end)
            end
            local fp = hrp:FindFirstChild("FirePlayerPart") or hrp:WaitForChild("FirePlayerPart",5)
            if fp then
                pcall(function()
                    stickyEv:FireServer(kunai.StickyPart, fp,
                        CFrame.new(0,0,0)*CFrame.Angles(0,math.rad(90),math.rad(90)))
                end)
            end
            for _, obj in pairs(kunai:GetChildren()) do
                if obj:IsA("BasePart") then
                    obj.CanTouch=false; obj.CanCollide=false; obj.CanQuery=false
                    if obj.Name=="Pyramid" then
                        obj.Transparency=0
                        if not obj:FindFirstChild("Highlight") then
                            local h=Instance.new("Highlight",obj); h.FillColor=Color3.fromRGB(0,0,0)
                        end
                    elseif obj.Name=="Main" then
                        obj.Transparency=0
                        if not obj:FindFirstChild("Highlight") then
                            local h=Instance.new("Highlight",obj); h.FillColor=Color3.fromRGB(255,255,255)
                        end
                    else obj.Transparency=1 end
                end
            end
        end
        local function spawnToy(name)
            local t0 = tick()
            while not (CanSpawnToy and CanSpawnToy.Value) do
                if not _G.ShurikenAntiKick or tick()-t0>5 then return nil end
                task.wait(0.1)
            end
            local hrp = getHRP()
            if hrp then
                task.spawn(function()
                    pcall(function() spawnRem:InvokeServer(name, hrp.CFrame*CFrame.new(0,12,20), Vector3.zero) end)
                end)
            end
            local inv = getToyFolder()
            if inv then return inv:WaitForChild(name,2) end
            return nil
        end
        while _G.ShurikenAntiKick do
            task.wait(0.005)
            local char = LP.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health<=0 then continue end
            local inv   = getToyFolder()
            local kunai = inv and (inv:FindFirstChild("AntiKick") or inv:FindFirstChild("NinjaShuriken"))
            if not kunai then
                kunai = spawnToy("NinjaShuriken")
                if not kunai then continue end
                kunai.Name = "AntiKick"
            end
            if kunai:FindFirstChild("StickyPart") and kunai.StickyPart.CanTouch then
                stickKunai(kunai); kunai.Name="AntiKick"
            end
            local hrp  = getHRP()
            local stuck = kunai:FindFirstChild("StickyPart")
            if not (stuck and hrp) then clearKunai(); continue end
            pcall(function()
                repeat
                    task.wait(0.05)
                    local sw   = stuck:FindFirstChild("StickyWeld")
                    local dist = (hrp.Position - stuck.Position).Magnitude
                    if not _G.ShurikenAntiKick then return end
                    if not sw or not sw.Part1 or dist>=20 then clearKunai(); return end
                    if stuck.CanTouch then stickKunai(kunai); kunai.Name="AntiKick" end
                until not _G.ShurikenAntiKick
                   or not kunai or not kunai:FindFirstChild("StickyPart")
                   or not kunai.StickyPart:FindFirstChild("StickyWeld")
                   or not kunai.StickyPart.StickyWeld.Part1
            end)
        end
        clearKunai()
    end)
end

-- ============================================================
-- [[ 11. ANTI-STICKY (3-layer) ]]
-- ============================================================

local asStickyConn, asTouchConn
local function applyAntiSticky(char)
    if not char then return end
    local ls = LP.PlayerScripts:FindFirstChild("StickyPartsTouchDetection")
    if ls then ls.Disabled = true end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then v.CanTouch=false; v.CanQuery=false end
    end
    disconnect(asTouchConn)
    asTouchConn = char.DescendantAdded:Connect(function(obj)
        if not S.antiSticky then disconnect(asTouchConn); return end
        if obj:IsA("BasePart") then obj.CanTouch=false; obj.CanQuery=false end
    end)
    disconnect(asStickyConn)
    asStickyConn = char.DescendantAdded:Connect(function(obj)
        if not S.antiSticky then disconnect(asStickyConn); return end
        if (obj:IsA("WeldConstraint") or obj:IsA("Weld")) and obj.Name:lower():find("sticky") then
            task.defer(function() if obj and obj.Parent then obj:Destroy() end end)
        end
    end)
end
local function removeAntiSticky(char)
    disconnect(asStickyConn); disconnect(asTouchConn)
    local ls = LP.PlayerScripts:FindFirstChild("StickyPartsTouchDetection")
    if ls then ls.Disabled=false end
    if not char then return end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then v.CanTouch=true; v.CanQuery=true end
    end
end

-- ============================================================
-- [[ 12. ANTI-EXPLOSION ]]
-- ============================================================

local antiExplodeConn
local function setupAntiExplosion(char)
    disconnect(antiExplodeConn)
    antiExplodeConn = Workspace.ChildAdded:Connect(function(obj)
        if obj.Name ~= "Part" or not S.antiExplosion then return end
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and (obj.Position-hrp.Position).Magnitude<=20 then
            hrp.Anchored = true
            task.wait(0.01)
            local ra  = char:FindFirstChild("Right Arm")
            local rlp = ra and ra:FindFirstChild("RagdollLimbPart")
            local t0  = tick()
            while rlp and rlp.CanCollide and S.antiExplosion do
                if tick()-t0>3 then break end; task.wait(0.001)
            end
            if hrp and hrp.Parent then hrp.Anchored=false end
        end
    end)
end

-- ============================================================
-- [[ 13. ANTI-BURN ]]
-- ============================================================

local antiBurnConn
local function setupAntiBurn(char)
    disconnect(antiBurnConn)
    local hum = char:WaitForChild("Humanoid",5); if not hum then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local fd  = hum:FindFirstChild("FireDebounce"); if not fd then return end
    antiBurnConn = fd.Changed:Connect(function(isBurning)
        if not isBurning or not S.antiBurn or not hrp then return end
        local plots = Workspace:FindFirstChild("Plots")
        local p2    = plots and plots:FindFirstChild("Plot2")
        local bar   = p2 and p2:FindFirstChild("Barrier")
        local pb    = bar and bar:FindFirstChild("PlotBarrier")
        if not (pb and pb:IsA("BasePart")) then return end
        local oldCF = hrp.CFrame
        char:SetPrimaryPartCFrame(pb.CFrame * CFrame.new(0,6,0))
        task.wait(0.3)
        local fp = char:FindFirstChild("FirePlayerPart",true)
        if fp then
            for _, o in ipairs(fp:GetChildren()) do
                if o:IsA("Sound") then o:Stop() end
                if o:IsA("Light") or o:IsA("ParticleEmitter") then o.Enabled=false end
            end
            local cb = fp:FindFirstChild("CanBurn"); if cb then cb.Value=false end
            local f2 = hum:FindFirstChild("FireDebounce"); if f2 then f2.Value=false end
        end
        task.wait(0.6)
        if char and char.PrimaryPart then char:SetPrimaryPartCFrame(oldCF) end
    end)
end

-- ============================================================
-- [[ 14. ANTI-GUCCI (Blobman + Train) ]]
-- ============================================================

local antiGucciConn, antiGucciTrainConn
local antiGucciJumpConn, antiGucciTrainJumpConn

local function startAntiGucci()
    local char = getChar() or LP.CharacterAdded:Wait()
    local hum  = char:WaitForChild("Humanoid")
    local root = char:WaitForChild("HumanoidRootPart")
    local safe = root.Position
    local blob = getOrSpawnBlob()
    local seat = blob and blob:FindFirstChild("VehicleSeat")
    if seat and seat:IsA("VehicleSeat") then
        root.CFrame = seat.CFrame + Vector3.new(0,2,0)
        seat:Sit(hum)
    end
    local rf = 0
    disconnect(antiGucciJumpConn)
    antiGucciJumpConn = hum:GetPropertyChangedSignal("Jump"):Connect(function()
        if hum.Jump and hum.Sit then rf=15; safe=root.Position end
    end)
    disconnect(antiGucciConn)
    antiGucciConn = RunService.Heartbeat:Connect(function()
        if not root or not hum then return end
        -- Skip ragdoll while seated in own blobman — firing it would immediately unseat us
        if not (seat and hum.SeatPart == seat) then
            pcall(function() RS.CharacterEvents.RagdollRemote:FireServer(root,0) end)
        end
        if rf>0 then root.CFrame=CFrame.new(safe); rf-=1 end
    end)
    task.spawn(function()
        while hum.Sit do task.wait(1) end
        task.wait(0.5)
        if root then root.CFrame=CFrame.new(safe) end
    end)
end

local function stopAntiGucci()
    disconnect(antiGucciConn)
    disconnect(antiGucciJumpConn)
    local f = getToyFolder()
    if f and f:FindFirstChild("CreatureBlobman") then f.CreatureBlobman:Destroy() end
end

local function startAntiGucciTrain()
    local char = getChar() or LP.CharacterAdded:Wait()
    local hum  = char:WaitForChild("Humanoid")
    local root = char:WaitForChild("HumanoidRootPart")
    local safe = root.Position
    local trainF = Workspace:FindFirstChild("Map") and Workspace.Map.AlwaysHereTweenedObjects
    local train  = trainF and trainF:FindFirstChild("Train")
    local seat
    if train then
        for _, d in ipairs(train:GetDescendants()) do
            if d:IsA("Seat") then seat=d; break end
        end
    end
    if seat then
        root.CFrame = seat.CFrame + Vector3.new(0,2,0)
        seat:Sit(hum)
    end
    local rf = 0
    disconnect(antiGucciTrainJumpConn)
    antiGucciTrainJumpConn = hum:GetPropertyChangedSignal("Jump"):Connect(function()
        if hum.Jump and hum.Sit then rf=15; safe=root.Position end
    end)
    disconnect(antiGucciTrainConn)
    antiGucciTrainConn = RunService.Heartbeat:Connect(function()
        if not root or not hum then return end
        pcall(function() RS.CharacterEvents.RagdollRemote:FireServer(root,0) end)
        if rf>0 then root.CFrame=CFrame.new(safe); rf-=1 end
    end)
end

local function stopAntiGucciTrain()
    disconnect(antiGucciTrainConn)
    disconnect(antiGucciTrainJumpConn)
end

-- ============================================================
-- [[ 15. ANTI-PAINT ]]
-- ============================================================

local paintBackup, paintWatchConn = {}, nil
local function setCharTQ(state)
    local char = Workspace:FindFirstChild(LP.Name); if not char then return end
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("BasePart") then v.CanTouch=state; v.CanQuery=state end
    end
end
local function deletePaint()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name=="PaintPlayerPart" then
            local id = obj:GetDebugId()
            paintBackup[id] = {clone=obj:Clone(), parent=obj.Parent}
            obj:Destroy()
        end
    end
end
local function watchPaint()
    disconnect(paintWatchConn)
    paintWatchConn = Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("BasePart") and obj.Name=="PaintPlayerPart" and S.antiPaint then
            task.defer(function()
                if obj and obj.Parent then
                    paintBackup[obj:GetDebugId()]={clone=obj:Clone(),parent=obj.Parent}
                    obj:Destroy()
                end
            end)
        end
    end)
end
local function restorePaint()
    for _, d in pairs(paintBackup) do if d.clone and d.parent then d.clone.Parent=d.parent end end
    paintBackup={}
    disconnect(paintWatchConn)
end

-- ============================================================
-- [[ 16. KILL GRAB & THROW STRENGTH (Workspace.ChildAdded) ]]
-- ============================================================

local throwPower = 750
Workspace.ChildAdded:Connect(function(v)
    if not (v:IsA("Model") and v.Name=="GrabParts") then return end
    local gp = v:FindFirstChild("GrabPart")
    local wc = gp and gp:FindFirstChild("WeldConstraint")
    local p1 = wc and wc.Part1
    if S.killGrab and p1 and p1.Parent and p1.Parent ~= LP.Character then
        task.wait(0.05)
        local tHum = p1.Parent:FindFirstChildOfClass("Humanoid")
        if tHum then pcall(function() tHum.Health=0; p1.Parent:BreakJoints() end) end
    end
    if S.throwStrength and p1 then
        local vel = Instance.new("BodyVelocity", p1)
        v:GetPropertyChangedSignal("Parent"):Connect(function()
            if not v.Parent then
                if UIS:GetLastInputType()==Enum.UserInputType.MouseButton2 then
                    vel.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
                    vel.Velocity = Camera.CFrame.LookVector * throwPower
                    game:GetService("Debris"):AddItem(vel,1)
                else vel:Destroy() end
            end
        end)
    end
end)

-- ============================================================
-- [[ 17. MASSLESS GRAB ]]
-- ============================================================

local mlConn
task.spawn(function()
    while true do
        RunService.Heartbeat:Wait()
        if not S.masslessGrab then continue end
        local gp = Workspace:FindFirstChild("GrabParts"); if not gp then continue end
        local dp = gp:FindFirstChild("DragPart");         if not dp then continue end
        local ap = dp:FindFirstChild("AlignPosition")
        local ao = dp:FindFirstChild("AlignOrientation")
        if ap then ap.Responsiveness=200; ap.MaxForce=math.huge; ap.MaxVelocity=math.huge end
        if ao then ao.Responsiveness=200; ao.MaxTorque=math.huge end
    end
end)

-- ============================================================
-- [[ 18. LOOP KILL ]]
-- ============================================================

task.spawn(function()
    while true do
        task.wait(0.05)
        if not S.loopKill then continue end
        local t = getTarget(); if not t or not t.Parent then continue end
        local tc = t.Character; local th = tc and tc:FindFirstChildOfClass("Humanoid")
        if th and th.Health>0 then pcall(function() th.Health=0; tc:BreakJoints() end) end
    end
end)

-- ============================================================
-- [[ 19. AUTO-RESET LOOP ]]
-- ============================================================

task.spawn(function()
    while true do
        task.wait(0.5)
        if not S.autoReset then continue end
        local hum = getHum()
        if hum and hum.Health>0 then hum.Health=0 end
    end
end)

-- ============================================================
-- [[ 20. LOOP TP ]]
-- ============================================================

task.spawn(function()
    while true do
        task.wait(0.03)
        if not S.loopTP then continue end
        local root = getRoot(); if not root then continue end
        local x = math.random(-500,500)
        local y = math.random(30,480)
        local z = math.random(-500,500)
        root.CFrame = CFrame.new(x,y,z)
    end
end)

-- ============================================================
-- [[ 21. GHOST MODE ]]
-- ============================================================
-- High-frequency flicker: every Heartbeat —
--   A) Capture post-physics RealCF + velocities.
--   B) Update invisible local proxy to RealCF (camera stays stable).
--   C) Warp HRP to HouseCoord (server registers safe zone, can't be grabbed).
--   D) Immediately restore HRP to RealCF + velocities (client never moves).
-- Camera.CameraSubject = proxy so the camera never sees the HRP flicker.

local ghostConn    = nil
local ghostProxy   = nil   -- invisible Part, parented to Camera (local-only, never replicated)
local ghostHouseCF = nil   -- pre-computed barrier interior CFrame for flicker target

local function findNearestBarrier()
    local hrp = getRoot(); if not hrp then return nil end
    local plots = Workspace:FindFirstChild("Plots"); if not plots then return nil end
    local best, bestDist = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        local bar = plot:FindFirstChild("Barrier")
        local pb  = bar and bar:FindFirstChild("PlotBarrier")
        if pb and pb:IsA("BasePart") then
            local d = (pb.Position - hrp.Position).Magnitude
            if d < bestDist then bestDist = d; best = pb end
        end
    end
    return best
end

local function startGhostMode()
    local hrp = getRoot()
    if not hrp then Notify("Ghost","No character",2); S.ghostMode=false; return end

    local pb = findNearestBarrier()
    if not pb then
        Notify("Ghost","No plot barrier found nearby!",3)
        S.ghostMode=false; Toggles.GhostMode:SetValue(false); return
    end

    -- Compute the interior position (the side of the barrier furthest from the player)
    local bCF  = pb.CFrame
    local half = pb.Size.Z / 2 + 2
    local pA   = (bCF * CFrame.new(0, 0,  half)).Position
    local pB   = (bCF * CFrame.new(0, 0, -half)).Position
    local insidePt = (pA - hrp.Position).Magnitude > (pB - hrp.Position).Magnitude
                     and pA or pB
    ghostHouseCF = CFrame.new(insidePt.X, hrp.Position.Y, insidePt.Z)

    -- Create invisible proxy parented to Camera (never replicated to server)
    if ghostProxy then ghostProxy:Destroy() end
    ghostProxy              = Instance.new("Part")
    ghostProxy.Name         = "GhostProxy"
    ghostProxy.Anchored     = true
    ghostProxy.CanCollide   = false
    ghostProxy.CanQuery     = false
    ghostProxy.CanTouch     = false
    ghostProxy.Size         = Vector3.new(2, 5, 1)
    ghostProxy.CFrame       = hrp.CFrame
    ghostProxy.Transparency = 1          -- fully invisible
    ghostProxy.CastShadow   = false
    ghostProxy.Parent       = Camera     -- Camera children are never replicated

    -- Lock camera onto the proxy so it stays at the player's real position,
    -- completely unaffected by the per-frame HRP flicker to HouseCoord.
    Camera.CameraSubject = ghostProxy

    disconnect(ghostConn)
    ghostConn = RunService.Heartbeat:Connect(function()
        if not S.ghostMode then disconnect(ghostConn); ghostConn = nil; return end
        local root = getRoot(); if not root then return end

        -- A) Capture true post-physics state
        local realCF     = root.CFrame
        local realLinVel = root.AssemblyLinearVelocity
        local realAngVel = root.AssemblyAngularVelocity

        -- B) Anchor proxy at real position so camera never moves
        ghostProxy.CFrame = realCF

        -- C) Warp HRP into the house (server sees this — prevents grabs)
        root.CFrame = ghostHouseCF

        -- D) Snap HRP straight back; preserve momentum so movement is unaffected
        root.CFrame                  = realCF
        root.AssemblyLinearVelocity  = realLinVel
        root.AssemblyAngularVelocity = realAngVel
    end)

    Notify("Ghost","Ghost Mode ON",3)
end

local function stopGhostMode()
    disconnect(ghostConn); ghostConn = nil

    -- Restore camera subject to the humanoid
    local hum = getHum()
    if hum then Camera.CameraSubject = hum end

    if ghostProxy then ghostProxy:Destroy(); ghostProxy = nil end
    ghostHouseCF = nil
    Notify("Ghost","Ghost Mode OFF",2)
end

-- ============================================================
-- [[ 22. PACKET LAG ]]
-- ============================================================

local PacketSpamAmount = 100
task.spawn(function()
    while true do
        task.wait()
        if not S.packetLag then continue end
        local GE    = RS:FindFirstChild("GrabEvents")
        local event = GE and GE:FindFirstChild("ExtendGrabLine")
        if event then
            pcall(function() event:FireServer(string.rep("Balls Balls Balls Balls", PacketSpamAmount)) end)
        end
    end
end)

-- ============================================================
-- [[ 22. REMOVE ANTI-KICK AURA ]]
-- ============================================================

local removeAKRadius = 15
local auraWLFriends  = { removeAK=true, dualKick=true, kick1=true }

task.spawn(function()
    while true do
        RunService.Heartbeat:Wait()
        if not S.removeAKAura and not S.removeAK then continue end
        local myRoot = getRoot(); if not myRoot then continue end
        local GE = RS:FindFirstChild("GrabEvents")
        local SN = GE and GE:FindFirstChild("SetNetworkOwner"); if not SN then continue end

        -- Aura (all players in radius)
        if S.removeAKAura then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr==LP then continue end
                if auraWLFriends.removeAK and LP:IsFriendsWith(plr.UserId) then continue end
                local tChar = plr.Character
                local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
                if not tRoot then continue end
                if (tRoot.Position-myRoot.Position).Magnitude > removeAKRadius then continue end
                local sp = Workspace:FindFirstChild(plr.Name.."SpawnedInToys")
                if sp then
                    for _, name in ipairs({"NinjaKunai","NinjaShuriken","AntiKick"}) do
                        local toy  = sp:FindFirstChild(name)
                        local part = toy and toy:FindFirstChild("SoundPart")
                        if part then
                            pcall(function() SN:FireServer(part, part.CFrame) end)
                            if part:FindFirstChild("PartOwner") and part.PartOwner.Value==LP.Name then
                                part.CFrame = CFrame.new(0,1000,0)
                            end
                        end
                    end
                end
            end
        end

        -- Single target
        if S.removeAK then
            local t = getTarget(); if not t then continue end
            local sp = Workspace:FindFirstChild(t.Name.."SpawnedInToys")
            if sp then
                for _, name in ipairs({"NinjaKunai","NinjaShuriken","AntiKick"}) do
                    local toy  = sp:FindFirstChild(name)
                    local part = toy and toy:FindFirstChild("SoundPart")
                    if part then
                        pcall(function() SN:FireServer(part, part.CFrame) end)
                        if part:FindFirstChild("PartOwner") and part.PartOwner.Value==LP.Name then
                            part.CFrame = CFrame.new(0,1000,0)
                        end
                    end
                end
            end
            task.wait(0.09)
        end
    end
end)

-- ============================================================
-- [[ 23. DUAL KICK AURA ]]
-- ============================================================

local dualKickRadius = 20
local dualKickLast   = 0
task.spawn(function()
    while true do
        RunService.Heartbeat:Wait()
        if not S.dualKickAura then continue end
        if tick()-dualKickLast < 0.12 then continue end
        dualKickLast = tick()
        local hum  = getHum(); local seat = hum and hum.SeatPart
        local root = getRoot()
        if not (seat and root) then continue end
        local sp  = seat.Parent
        local sObj = sp:FindFirstChild("BlobmanSeatAndOwnerScript")
        local grab = sObj and sObj:FindFirstChild("CreatureGrab")
        local drop = sObj and sObj:FindFirstChild("CreatureDrop")
        local LD = sp:FindFirstChild("LeftDetector");  local RD = sp:FindFirstChild("RightDetector")
        local LW = LD and LD:FindFirstChild("LeftWeld"); local RW = RD and RD:FindFirstChild("RightWeld")
        if not (grab and drop and LW and RW) then continue end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr==LP or not plr.Character then continue end
            if auraWLFriends.dualKick and LP:IsFriendsWith(plr.UserId) then continue end
            local tr = plr.Character:FindFirstChild("HumanoidRootPart")
            local th = plr.Character:FindFirstChildOfClass("Humanoid")
            if tr and th and th.Health>0 and (tr.Position-root.Position).Magnitude<=dualKickRadius then
                pcall(function()
                    grab:FireServer(LD,tr,LW); task.wait(0.04); drop:FireServer(LW,tr)
                    grab:FireServer(RD,tr,RW); task.wait(0.04); drop:FireServer(RW,tr)
                    grab:FireServer(LD,tr,LW); grab:FireServer(RD,tr,RW); task.wait(0.03)
                    drop:FireServer(LW,tr);    drop:FireServer(RW,tr)
                end)
            end
        end
    end
end)

-- ============================================================
-- [[ 24. KICK AURA 1 HAND ]]
-- ============================================================

local kickAura1Radius = 20
task.spawn(function()
    while true do
        RunService.Heartbeat:Wait()
        if not S.kickAura1 then continue end
        local hum  = getHum(); local seat = hum and hum.SeatPart
        local root = getRoot()
        if not (seat and root) then continue end
        local blob  = seat.Parent
        local sObj  = blob:FindFirstChild("BlobmanSeatAndOwnerScript")
        local CG = sObj and sObj:FindFirstChild("CreatureGrab")
        local CD = sObj and sObj:FindFirstChild("CreatureDrop")
        local RD = blob:FindFirstChild("RightDetector")
        local RW = RD and (RD:FindFirstChild("RightWeld") or RD:FindFirstChildWhichIsA("Weld"))
        if not (CG and CD and RD and RW) then continue end
        local pt = 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr==LP or not plr.Character then continue end
            if auraWLFriends.kick1 and LP:IsFriendsWith(plr.UserId) then continue end
            local tr = plr.Character:FindFirstChild("HumanoidRootPart")
            local th = plr.Character:FindFirstChildOfClass("Humanoid")
            if tr and th and th.Health>0 and (tr.Position-root.Position).Magnitude<=kickAura1Radius then
                if tick()-pt>0.05 then
                    pt=tick()
                    local w = RD:FindFirstChild("RightWeld") or RD:FindFirstChildWhichIsA("Weld")
                    if w then pcall(function() CD:FireServer(w); CG:FireServer(RD,tr,RW) end) end
                end
            end
        end
    end
end)

-- ============================================================
-- [[ 25. TRIGGERBOT ]]
-- ============================================================

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local Mouse = LP:GetMouse()

local Triggerbot = {
    Enabled = false, canGrab = true,
    maxDistance = 29.3, checkThrottle = 0.05,
    lastCheck = 0, preGrabDelay = 0.05, postGrabDelay = 0.3,
    targetMemoryDuration = 0.15, lastTarget = nil, lastHitTime = 0,
    Connection = nil,
}

local function triggerbotGetTarget()
    local c = LP.Character; if not c or not c:FindFirstChild("HumanoidRootPart") then return end
    if Workspace:FindFirstChild("GrabParts") then return end
    local origin = Camera.CFrame.Position
    local dir    = Camera.CFrame.LookVector
    rayParams.FilterDescendantsInstances = {c, Workspace.Terrain}
    local result = Workspace:Raycast(origin, dir*1000, rayParams)
    if not result then
        for _, d in ipairs({dir, (dir+Vector3.new(0,0.075,0)).Unit, (dir-Vector3.new(0,0.075,0)).Unit}) do
            result = Workspace:Raycast(origin, d*1000, rayParams); if result then break end
        end
    end
    if not result then return end
    local hit = result.Instance
    local model = hit:FindFirstAncestorOfClass("Model")
    if not model or not model:FindFirstChildOfClass("Humanoid") or model==c then return end
    local hum = model:FindFirstChildOfClass("Humanoid"); if hum.Health<=0 then return end
    local root = model:FindFirstChild("HumanoidRootPart"); if not root then return end
    if (c.HumanoidRootPart.Position-root.Position).Magnitude > Triggerbot.maxDistance then return end
    return model
end

local function triggerbotOnHeartbeat()
    if not Triggerbot.Enabled or not Triggerbot.canGrab then return end
    if UIS:GetFocusedTextBox() then return end
    if tick()-Triggerbot.lastCheck < Triggerbot.checkThrottle then return end
    Triggerbot.lastCheck = tick()
    local t = triggerbotGetTarget()
    if t then Triggerbot.lastTarget=t; Triggerbot.lastHitTime=tick()
    elseif Triggerbot.lastTarget and tick()-Triggerbot.lastHitTime>Triggerbot.targetMemoryDuration then
        Triggerbot.lastTarget=nil
    end
    local c    = LP.Character
    local root = Triggerbot.lastTarget and Triggerbot.lastTarget:FindFirstChild("HumanoidRootPart")
    if not (Triggerbot.lastTarget and c and c:FindFirstChild("HumanoidRootPart") and root) then return end
    if (c.HumanoidRootPart.Position-root.Position).Magnitude > Triggerbot.maxDistance then
        Triggerbot.lastTarget=nil; return
    end
    if Triggerbot.lastTarget then
        Triggerbot.canGrab=false
        task.spawn(function()
            task.wait(Triggerbot.preGrabDelay)
            pcall(mouse1press)
            local t0=tick()
            repeat task.wait(0.02) until not Workspace:FindFirstChild("GrabParts") or tick()-t0>1.6
            task.wait(Triggerbot.postGrabDelay)
            Triggerbot.canGrab=true; Triggerbot.lastTarget=nil
        end)
    end
end

RunService.Heartbeat:Connect(function()
    if S.triggerbot then triggerbotOnHeartbeat() end
end)

-- ============================================================
-- [[ 26. ANTI-INPUT-LAG (toy pick+drop spam) ]]
-- ============================================================

local AllowedItems = {
    FoodHamburger=true, FoodCoconut=true, FoodPizzaCheese=true, FoodPizzaPepperoni=true,
    FoodHotdog=true, FoodMushroomPoison=true, FoodBread=true, FoodDippyEgg=true,
    FoodMayonnaise=true, FoodFrenchFries=true, FoodMeatStick=true, FoodDonut=true, FoodCakePink=true,
    InstrumentGuitarBanjo=true, InstrumentGuitarViolin=true, InstrumentGuitarUkulele=true,
    InstrumentWoodwindSaxophone=true, InstrumentWoodwindOcarina=true, InstrumentBrassVuvuzelaQwizik=true,
    InstrumentBrassTrumpet=true, InstrumentDrumBongos=true, InstrumentDrumSnare=true,
    InstrumentPianoMelodica=true, InstrumentVoiceMicrophone=true,
    CupMugWhite=true, CupMugBrown=true, PoopPile=true, PoopPileSparkle=true,
}
local ToyList = {
    Coconut="FoodCoconut", Banana="FoodBanana", Fries="FoodFrenchFries",
    MeatStick="FoodMeatStick", Poop="PoopPile", Donut="FoodDonut",
    Cake="FoodCakePink", Burger="FoodHamburger", Pizza="FoodPizzaCheese",
    Hotdog="FoodHotdog", Mushroom="FoodMushroomPoison", Banjo="InstrumentGuitarBanjo",
    Violin="InstrumentGuitarViolin", Ukulele="InstrumentGuitarUkulele",
    Sax="InstrumentWoodwindSaxophone", Vuvuzela="InstrumentBrassVuvuzelaQwizik",
    Bongos="InstrumentDrumBongos", Mic="InstrumentVoiceMicrophone",
    Pepperoni="FoodPizzaPepperoni", Piano="InstrumentPianoMelodica",
    Bread="FoodBread", Egg="FoodDippyEgg", Mayo="FoodMayonnaise",
    WhiteMug="CupMugWhite", Ocarina="InstrumentWoodwindOcarina",
    SparklePoop="PoopPileSparkle", BrownMug="CupMugBrown",
    Trumpet="InstrumentBrassTrumpet", Snare="InstrumentDrumSnare",
}
local toyDropValues = {}
for k in pairs(ToyList) do table.insert(toyDropValues,k) end
table.sort(toyDropValues)
local selectedAntiLagToy = ToyList[toyDropValues[1]]

task.spawn(function()
    while true do
        task.wait(0.01)
        if not S.antiInputLag then continue end
        local char = LP.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local toysFolder = getToyFolder(); if not toysFolder then continue end
        local toy = toysFolder:FindFirstChild(selectedAntiLagToy)
        if not toy then
            pcall(function()
                RS.MenuToys.SpawnToyRemoteFunction:InvokeServer(
                    selectedAntiLagToy,
                    hrp.CFrame * CFrame.new(0,5,0),
                    Vector3.zero)
            end)
            task.wait(0.3); continue
        end
        local hp = toy:FindFirstChild("HoldPart"); if not hp then continue end
        pcall(function()
            hp.HoldItemRemoteFunction:InvokeServer(toy, char)
        end)
        task.wait()
        pcall(function()
            hp.DropItemRemoteFunction:InvokeServer(toy,
                CFrame.new(hrp.Position + Vector3.new(0,-2000,0)),
                Vector3.zero)
        end)
    end
end)

-- ============================================================
-- [[ 27. REMOVE ANTI-INPUT-LAG (item pickup spam on all items) ]]
-- ============================================================

task.spawn(function()
    local burgers = {}
    Workspace.DescendantAdded:Connect(function(obj)
        if AllowedItems[obj.Name] and obj:IsA("Model") then
            task.spawn(function()
                local hp = obj:WaitForChild("HoldPart",3)
                if hp then table.insert(burgers,obj) end
            end)
        end
    end)
    while true do
        task.wait()
        if not S.removeAIL then continue end
        local char = LP.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not (char and hrp) then continue end
        if #burgers == 0 then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if AllowedItems[v.Name] and v:IsA("Model") and v:FindFirstChild("HoldPart") then
                    table.insert(burgers,v)
                end
            end
        end
        for i=#burgers,1,-1 do
            local b = burgers[i]
            if not b or not b.Parent or not b:FindFirstChild("HoldPart") then
                table.remove(burgers,i)
            else
                local hp = b.HoldPart
                pcall(function() hp.HoldItemRemoteFunction:InvokeServer(b,char) end)
                task.wait()
                pcall(function()
                    hp.DropItemRemoteFunction:InvokeServer(b,
                        CFrame.new(hrp.Position+Vector3.new(0,-2000,0)),
                        Vector3.zero)
                end)
            end
        end
    end
end)

-- ============================================================
-- [[ 28. DREAMY NIGHT SHADER ]]
-- ============================================================

local dreamyEffects = nil
local function enableDreamyNight()
    if not dreamyEffects then
        dreamyEffects = {}
        local blur = Instance.new("BlurEffect"); blur.Size=6; blur.Enabled=false; blur.Parent=Lighting
        table.insert(dreamyEffects, blur)
        local cc = Instance.new("ColorCorrectionEffect")
        cc.Saturation = 0.3; cc.TintColor = Color3.fromRGB(180,170,220)
        cc.Enabled=false; cc.Parent=Lighting
        table.insert(dreamyEffects, cc)
        local atm = Instance.new("Atmosphere"); atm.Density=0.4; atm.Offset=0.2
        atm.Color=Color3.fromRGB(120,100,180); atm.Parent=Lighting
        table.insert(dreamyEffects, atm)
        local skyl = Instance.new("Sky")
        skyl.SkyboxBk="rbxassetid://159454919"; skyl.SkyboxDn="rbxassetid://159454919"
        skyl.SkyboxFt="rbxassetid://159454919"; skyl.SkyboxLf="rbxassetid://159454919"
        skyl.SkyboxRt="rbxassetid://159454919"; skyl.SkyboxUp="rbxassetid://159454919"
        skyl.Parent=Lighting; table.insert(dreamyEffects, skyl)
    end
    for _, e in ipairs(dreamyEffects) do
        if e:IsA("BlurEffect") or e:IsA("ColorCorrectionEffect") then e.Enabled=true
        elseif e:IsA("Atmosphere") or e:IsA("Sky") then e.Parent=Lighting end
    end
    Lighting.Ambient            = Color3.fromRGB(60,40,80)
    Lighting.OutdoorAmbient     = Color3.fromRGB(40,30,70)
    Lighting.Brightness         = 0.5
    Lighting.ClockTime          = 20
    Lighting.GeographicLatitude = 41.7
    Lighting.GlobalShadows      = true
end
local function disableDreamyNight()
    if dreamyEffects then
        for _, e in ipairs(dreamyEffects) do pcall(function() e:Destroy() end) end
        dreamyEffects=nil
    end
    Lighting.Brightness=2; Lighting.ClockTime=14; Lighting.GlobalShadows=true
end

-- ============================================================
-- [[ 29. FUN — ANIMATION PLAYER ]]
-- ============================================================

local ANIM_IDS = {
    Crazy    = "rbxassetid://182435998",
    Insane   = "rbxassetid://148840371",
    Collapse = "rbxassetid://180612465",
    Zombie   = "rbxassetid://616163682",
}
local selectedAnimName = "Crazy"
local currentAnimTrack = nil
local function playAnimation()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local ani  = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    if currentAnimTrack then currentAnimTrack:Stop(); currentAnimTrack=nil end
    local anim = Instance.new("Animation")
    anim.AnimationId = ANIM_IDS[selectedAnimName] or ANIM_IDS.Crazy
    currentAnimTrack = ani:LoadAnimation(anim)
    currentAnimTrack.Priority = Enum.AnimationPriority.Action
    currentAnimTrack:Play()
end
local function stopAnimation()
    if currentAnimTrack then currentAnimTrack:Stop(); currentAnimTrack=nil end
end

-- Jerk Off anim
local jerkAnimId   = "rbxassetid://5915693722"
local jerkTrack    = nil
local function startJerkOff()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local ani  = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator",hum)
    local anim = Instance.new("Animation"); anim.AnimationId=jerkAnimId
    jerkTrack  = ani:LoadAnimation(anim)
    jerkTrack.Priority = Enum.AnimationPriority.Action; jerkTrack:Play()
    task.spawn(function()
        while S.jerkOff do
            task.wait(0.1)
            if jerkTrack and jerkTrack.IsPlaying then jerkTrack.TimePosition=0.3 end
        end
    end)
end
local function stopJerkOff()
    if jerkTrack then jerkTrack:Stop(); jerkTrack=nil end
end

-- Bang anim
local bangAnimId  = "rbxassetid://148840371"
local bangTrack   = nil
local function startBang()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local ani  = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator",hum)
    local anim = Instance.new("Animation"); anim.AnimationId=bangAnimId
    bangTrack  = ani:LoadAnimation(anim)
    bangTrack.Priority = Enum.AnimationPriority.Action; bangTrack:Play()
    bangTrack:AdjustSpeed(10)
    task.spawn(function()
        while S.bang do
            task.wait(0.1)
            if bangTrack and bangTrack.IsPlaying then bangTrack.TimePosition=0.1 end
        end
    end)
end
local function stopBang()
    if bangTrack then bangTrack:Stop(); bangTrack=nil end
end

-- Follow & Stare
local followConn
task.spawn(function()
    while true do
        task.wait(0.3)
        if not S.followStare then continue end
        local lp  = LP
        local all = Players:GetPlayers()
        local t   = all[math.random(#all)]
        if t~=lp and t.Character and t.Character:FindFirstChild("HumanoidRootPart") then
            local hrp  = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            local thrp = t.Character.HumanoidRootPart
            if hrp then hrp.CFrame = CFrame.new(thrp.Position + thrp.CFrame.LookVector*-2, thrp.Position) end
        end
    end
end)

-- Fake Lag
local fakeLagConn
task.spawn(function()
    while true do
        RunService.Heartbeat:Wait()
        if not S.fakeLag then continue end
        local root = getRoot(); if not root then continue end
        if math.random(1,5)==1 then
            root.CFrame = root.CFrame * CFrame.new(
                math.random(-2,2)/10, 0, math.random(-2,2)/10)
        end
    end
end)

-- ============================================================
-- [[ 30. HEART SPARKLER BUILD ]]
-- Fixed version:
-- 1. Spawns FireworkSparkler above player
-- 2. Breaks joints, makes parts massless, attaches BodyPosition+BodyGyro
-- 3. Heartbeat animates a heart-shaped oscillation
-- The original had a t variable it used but never initialized the sine wave.
-- ============================================================

local heartToy, heartConn
local function startHeartBuild()
    task.spawn(function()
        local hrp = getRoot(); if not hrp then return end
        pcall(function()
            RS.MenuToys.SpawnToyRemoteFunction:InvokeServer(
                "FireworkSparkler",
                hrp.CFrame * CFrame.new(0,50,0),
                Vector3.zero)
        end)
        local folder = getToyFolder()
        if not folder then Notify("Build","Could not find toy folder",3); return end
        heartToy = folder:WaitForChild("FireworkSparkler",5)
        if not heartToy then Notify("Build","FireworkSparkler not found",3); return end
        local part = heartToy:FindFirstChild("Handle") or heartToy:FindFirstChildWhichIsA("BasePart")
        if not part then Notify("Build","No part in sparkler",3); return end
        task.wait(0.2)
        for _, v in ipairs(heartToy:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Anchored=false; v.CanCollide=false; v.Massless=true
            end
        end
        part:BreakJoints()
        local bp = Instance.new("BodyPosition")
        bp.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
        bp.P = 20000; bp.D = 500; bp.Parent = part
        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
        bg.P = 3000; bg.CFrame = CFrame.new(); bg.Parent = part
        disconnect(heartConn)
        local t0 = tick()
        heartConn = RunService.Heartbeat:Connect(function()
            if not S.heartBuild or not part.Parent then
                disconnect(heartConn)
                if heartToy then pcall(function() heartToy:Destroy() end); heartToy=nil end
                return
            end
            local hrp2 = getRoot(); if not hrp2 then return end
            local ti = tick()-t0
            -- Heart parametric curve (x = 16sin^3, y = 13cos-5cos2t-2cos3t-cos4t)
            local scale  = 3
            local angle  = (ti*1.5) % (2*math.pi)
            local sinA   = math.sin(angle)
            local cosA   = math.cos(angle)
            local hx     = scale * 16 * sinA^3 * 0.1
            local hy     = scale * (13*cosA - 5*math.cos(2*angle) - 2*math.cos(3*angle) - math.cos(4*angle)) * 0.1
            bp.Position  = hrp2.Position + Vector3.new(hx, hy+8, 0)
            bg.CFrame    = CFrame.new(part.Position, hrp2.Position)
        end)
    end)
end

-- ============================================================
-- [[ 31. CHARACTER ADDED ]]
-- ============================================================

LP.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid")
    hum.WalkSpeed  = targetWalkSpeed
    hum.Changed:Connect(function(p)
        if p=="WalkSpeed" then hum.WalkSpeed=targetWalkSpeed end
    end)
    if S.antiExplosion then setupAntiExplosion(char) end
    if S.antiBurn      then setupAntiBurn(char) end
    if S.antiSticky    then applyAntiSticky(char) end
end)

UIS.JumpRequest:Connect(function()
    if S.infJump then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- ============================================================
-- [[ 32. PCLD / BOX ESP ]]
-- ============================================================

local espBoxes = {}
local function isEspTarget(obj)
    if not obj:IsA("BasePart") then return false end
    local n = obj.Name:lower()
    return n=="partesp" or n=="playercharacterlocationdetector"
end
local function addBox(obj)
    if espBoxes[obj] then return end
    local box = Instance.new("BoxHandleAdornment")
    box.Adornee=obj; box.AlwaysOnTop=true; box.ZIndex=5
    box.Color3=Color3.fromRGB(255,255,255); box.Transparency=0.5
    box.Size=obj.Size; box.Parent=game.CoreGui
    espBoxes[obj]=box
    obj.AncestryChanged:Connect(function(_, p)
        if not p and espBoxes[obj] then espBoxes[obj]:Destroy(); espBoxes[obj]=nil end
    end)
end
local function removeAllBoxes()
    for _, box in pairs(espBoxes) do if box then box:Destroy() end end
    espBoxes={}
end
Workspace.DescendantAdded:Connect(function(obj)
    if S.pcldESP and isEspTarget(obj) then addBox(obj) end
end)

-- Nickname ESP
local function createNameESP(plr)
    if plr==LP then return end
    if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
        local hrp = plr.Character.HumanoidRootPart
        if hrp:FindFirstChild("NameESP") then return end
        local bb = Instance.new("BillboardGui"); bb.Name="NameESP"; bb.Adornee=hrp
        bb.Size=UDim2.new(0,100,0,30); bb.StudsOffset=Vector3.new(0,3,0)
        bb.AlwaysOnTop=true; bb.Parent=hrp
        local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0)
        lbl.BackgroundTransparency=1; lbl.Text=plr.Name
        lbl.TextColor3=Color3.fromRGB(255,255,255); lbl.TextStrokeTransparency=0
        lbl.TextScaled=true; lbl.Parent=bb
    end
end

-- FPS Boost
local oldProps = {}
local function boostFPS()
    for _, v in pairs(Workspace:GetDescendants()) do
        if v:IsA("BasePart") then
            if not oldProps[v] then oldProps[v]={Material=v.Material,Reflectance=v.Reflectance,CastShadow=v.CastShadow} end
            v.Material=Enum.Material.Plastic; v.Reflectance=0; v.CastShadow=false
        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") then
            if not oldProps[v] then oldProps[v]={Enabled=v.Enabled} end; v.Enabled=false
        end
    end
    if not oldProps["Lighting"] then
        oldProps["Lighting"]={GlobalShadows=Lighting.GlobalShadows, FogEnd=Lighting.FogEnd, Brightness=Lighting.Brightness}
    end
    Lighting.GlobalShadows=false; Lighting.FogEnd=100000; Lighting.Brightness=2
    Notify("FPS","Boost applied!",3)
end
local function restoreFPS()
    for obj, props in pairs(oldProps) do
        if typeof(obj)=="Instance" and obj.Parent then
            for p,v in pairs(props) do obj[p]=v end
        elseif obj=="Lighting" then
            for p,v in pairs(props) do Lighting[p]=v end
        end
    end
    oldProps={}; Notify("FPS","Restored.",3)
end

-- ============================================================
-- [[ 33. TARGET JOINED NOTIFY ]]
-- ============================================================

local notifyConn
local function startJoinNotify()
    disconnect(notifyConn)
    notifyConn = Players.PlayerAdded:Connect(function(newPlr)
        if not S.joinNotify then return end
        local ml = Options.MultiWhitelist and Options.MultiWhitelist.Value
        if ml then
            for nameStr, selected in pairs(ml) do
                if selected then
                    local actual = nameStr:match("%((.-)%)")
                    if actual==newPlr.Name then
                        Notify("Detected","[Whitelist] "..newPlr.Name,8)
                        return
                    end
                end
            end
        end
        local selDrop = Options.TargetPlayer and Options.TargetPlayer.Value
        if selDrop then
            local sName = type(selDrop)=="string" and selDrop or (selDrop.Name or "")
            if sName==newPlr.Name then
                Notify("Detected","[Target] "..newPlr.Name,8)
            end
        end
    end)
end

-- ============================================================
-- [[ 34. LIMB DELETION ]]
-- ============================================================

local LIMBS = {
    ["Right Arm"]  = {"Right Arm","RightUpperArm","RightLowerArm","RightHand"},
    ["Left Arm"]   = {"Left Arm","LeftUpperArm","LeftLowerArm","LeftHand"},
    ["Right Leg"]  = {"Right Leg","RightUpperLeg","RightLowerLeg","RightFoot"},
    ["Left Leg"]   = {"Left Leg","LeftUpperLeg","LeftLowerLeg","LeftFoot"},
    ["Head"]       = {"Head"},
}
local function deleteLimb(char, key)
    if not char then return end
    local names = LIMBS[key]; if not names then return end
    for _, name in ipairs(names) do
        local part = char:FindFirstChild(name)
        if part then
            for _, c in ipairs(part:GetChildren()) do
                if c:IsA("Weld") or c:IsA("WeldConstraint") or c:IsA("Motor6D") then c:Destroy() end
            end
        end
    end
    Notify("Limbs","Removed: "..key,2)
end

-- ============================================================
-- [[ 35. TABS ]]
-- ============================================================

local Tabs = {
    Defense  = Window:AddTab("Defense",  "shield"),
    Combat   = Window:AddTab("Combat",   "crosshair"),
    Auras    = Window:AddTab("Auras",    "star"),
    Player   = Window:AddTab("Player",   "user"),
    Misc     = Window:AddTab("Misc",     "tool"),
    Fun      = Window:AddTab("Fun",      "smile"),
    Settings = Window:AddTab("Settings", "settings"),
}

-- ============================================================
-- [[ 36. DEFENSE TAB ]]
-- ============================================================

local DefLeft  = Tabs.Defense:AddLeftGroupbox("Anti-Grab")
local DefRight = Tabs.Defense:AddRightGroupbox("Anti-Death")
local DefEnv   = Tabs.Defense:AddLeftGroupbox("Environment")
local DefExtra = Tabs.Defense:AddRightGroupbox("Anti-Misc")

-- === Anti-Grab ===
DefLeft:AddToggle("PhysicsAnchor",{Text="Physics Anchor",Tooltip="Anchors HRP when grabbed. WASD still moves you.",Default=false,
    Callback=function(v) S.physicsAnchor=v; if not v then local r=getRoot(); if r then r.Anchored=false end end end})
DefLeft:AddSlider("AnchorSpeed",{Text="Anchor WASD Speed",Default=16,Min=16,Max=100,Rounding=0,
    Callback=function(v) anchorMoveSpeed=v end})
DefLeft:AddToggle("AutoStruggle",{Text="Auto-Struggle",Tooltip="Fires Struggle + StopAllVelocity every tick when IsHeld or PartOwner detected.",Default=false,
    Callback=function(v)
        S.autoStruggle=v
        if not v then local c=getChar(); if c then for _,p in pairs(c:GetChildren()) do if p:IsA("BasePart") then p.Anchored=false end end end end
    end})
DefLeft:AddToggle("GhostMode",{Text="Ghost Mode",
    Tooltip="Every frame: flickers HRP into the nearest house barrier and back so the server can never register a grab. Camera is anchored to a local proxy — no stutter.",
    Default=false,
    Callback=function(v)
        S.ghostMode=v
        if v then startGhostMode() else stopGhostMode() end
    end})

-- === Anti-Death ===
DefRight:AddToggle("AntiVoid",{Text="Anti-Void",Default=false,Callback=function(v) S.antiVoid=v end})
DefRight:AddToggle("GodMode",{Text="God Mode",Default=false,Risky=true,Callback=function(v) S.godMode=v end})
DefRight:AddToggle("AntiExplosion",{Text="Anti-Explosion",Default=false,
    Callback=function(v) S.antiExplosion=v; if v and getChar() then setupAntiExplosion(getChar()) end end})
DefRight:AddToggle("AntiBurn",{Text="Anti-Burn",Default=false,
    Callback=function(v) S.antiBurn=v; if v and getChar() then setupAntiBurn(getChar()) elseif not v then disconnect(antiBurnConn) end end})
DefRight:AddToggle("AntiSticky",{Text="Anti-Sticky",Tooltip="3-layer: kills StickyScript, CanTouch=false, destroys StickyWelds.",Default=false,
    Callback=function(v) S.antiSticky=v; if v then applyAntiSticky(getChar()) else removeAntiSticky(getChar()) end end})
local antiBlobmanConn
DefRight:AddToggle("AntiBlobman",{Text="Anti-Blobman",Default=false,
    Callback=function(v)
        S.antiBlobman=v
        disconnect(antiBlobmanConn); antiBlobmanConn=nil
        if v then
            antiBlobmanConn = Workspace.DescendantAdded:Connect(function(toy)
                if toy.Name=="CreatureBlobman" and S.antiBlobman then
                    -- Never destroy detectors on our own blobman (combat needs them)
                    local f = getToyFolder()
                    if f and toy:IsDescendantOf(f) then return end
                    local ld=toy:FindFirstChild("LeftDetector"); local rd=toy:FindFirstChild("RightDetector")
                    if ld then ld:Destroy() end; if rd then rd:Destroy() end
                end
            end)
        end
    end})

-- === Environment ===
DefEnv:AddToggle("AntiKickRag",{Text="Anti-Kick (RagdollRemote)",Tooltip="Spams RagdollRemote:FireServer(root,0) every 0.1s.",Default=false,
    Callback=function(v) S.antiKickRag=v end})
DefEnv:AddToggle("AntiKickKunai",{Text="Anti-Kick (Kunai Shield)",Tooltip="Spawns NinjaShuriken and sticks it to your FirePlayerPart via StickyPartEvent.",Default=false,
    Callback=function(v) S.antiKickKunai=v; _G.ShurikenAntiKick=v; if v then startKunaiAntiKick() else clearKunai() end end})
DefEnv:AddToggle("AntiLag",{Text="Anti-Lag (Destroy GrabLines)",Default=false,
    Callback=function(v)
        S.antiLag=v
        local GE=RS:FindFirstChild("GrabEvents"); if not GE then return end
        if v then
            for _,n in ipairs({"CreateGrabLine","ExtendGrabLine"}) do
                local r=GE:FindFirstChild(n); if r and r:IsA("RemoteEvent") then r:Destroy() end
            end
            for _,obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("Beam") or obj.Name:lower():find("line") then pcall(function() obj:Destroy() end) end
            end
        else
            if grabLineCopy and not GE:FindFirstChild("CreateGrabLine") then grabLineCopy:Clone().Parent=GE end
            if extendLineCopy and not GE:FindFirstChild("ExtendGrabLine") then extendLineCopy:Clone().Parent=GE end
        end
    end})
DefEnv:AddToggle("LoopTP",{Text="Loop TP (Chaos)",Default=false,Risky=true,
    Callback=function(v)
        S.loopTP=v
        local hum=getHum(); if hum then hum.PlatformStand=v end
    end})

-- === Anti-Misc ===
DefExtra:AddToggle("AntiPaint",{Text="Anti-Paint",Default=false,
    Callback=function(v)
        S.antiPaint=v
        if v then deletePaint(); watchPaint(); setCharTQ(false)
        else restorePaint(); setCharTQ(true) end
    end})
DefExtra:AddToggle("AntiGucci",{Text="Anti-Gucci (Blobman)",Default=false,
    Callback=function(v)
        S.antiGucci=v
        if v then
            startAntiGucci()
            task.spawn(function()
                while S.antiGucci do
                    local f=getToyFolder()
                    if not (f and f:FindFirstChild("CreatureBlobman")) then
                        stopAntiGucci(); Notify("Anti-Gucci","Blobman lost, re-spawning...",3)
                        local tries=0
                        repeat task.wait(0.2); tries+=1; f=getToyFolder()
                        until (f and f:FindFirstChild("CreatureBlobman")) or tries>25 or not S.antiGucci
                        if S.antiGucci then startAntiGucci(); Notify("Anti-Gucci","Restored.",2) end
                    end
                    task.wait(0.5)
                end
            end)
        else stopAntiGucci() end
    end})
DefExtra:AddToggle("AntiGucciTrain",{Text="Anti-Gucci (Train Seat)",Default=false,
    Callback=function(v)
        S.antiGucciTrain=v
        if v then startAntiGucciTrain() else stopAntiGucciTrain() end
    end})
DefExtra:AddDropdown("AntiInputLagToyDrop",{Values=toyDropValues,Default=toyDropValues[1],Text="Input Lag Item",
    Callback=function(v) selectedAntiLagToy=ToyList[v] end})
DefExtra:AddToggle("AntiInputLag",{Text="Anti Input Lag (toy cycle)",Tooltip="Cycles pick+drop on an item every frame to keep the game's physics responsive.",Default=false,
    Callback=function(v) S.antiInputLag=v end})

-- ============================================================
-- [[ 37. COMBAT TAB ]]
-- ============================================================

local CombatLeft  = Tabs.Combat:AddLeftGroupbox("Target")
local CombatKick  = Tabs.Combat:AddRightGroupbox("Kick Methods")
local CombatGrab  = Tabs.Combat:AddLeftGroupbox("Grab")
local CombatLimbs = Tabs.Combat:AddRightGroupbox("Limbs")

-- Target
CombatLeft:AddDropdown("TargetPlayer",{SpecialType="Player",ExcludeLocalPlayer=true,Text="Select Target",Callback=function(_)end})
CombatLeft:AddButton({Text="Spawn My Blobman",Func=function() task.spawn(spawnBlobman) end})
CombatLeft:AddButton({Text="Sit In My Blobman",Func=function() autoSitMyBlob() end})
CombatLeft:AddButton({Text="Delete All Seats",Func=function()
    local count=0
    for _,obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Seat") or obj:IsA("VehicleSeat") then
            local f=getToyFolder()
            if not (f and obj:IsDescendantOf(f)) then pcall(function() obj:Destroy(); count+=1 end) end
        end
    end
    Notify("Seats","Deleted "..count.." seats.",3)
end})
CombatLeft:AddToggle("LoopKill",{Text="Loop Kill",Default=false,Risky=true,
    Callback=function(v) S.loopKill=v end})
CombatLeft:AddToggle("DestroyGucci",{Text="Destroy Target Gucci (sit)",Default=false,Risky=true,
    Callback=function(v)
        S.destroyGucci=v
        if not v then return end
        local target=getTarget(); if not target then Notify("Error","Select a target!",2); Toggles.DestroyGucci:SetValue(false); return end
        local myRoot=getRoot(); if not myRoot then return end
        local safeSpot=myRoot.CFrame
        task.spawn(function()
            while S.destroyGucci do
                local t=getTarget(); if not t or not t.Parent then task.wait(0.5); continue end
                local folder=Workspace:FindFirstChild(t.Name.."SpawnedInToys")
                if folder then
                    for _,obj in ipairs(folder:GetChildren()) do
                        if not S.destroyGucci then break end
                        if obj.Name=="CreatureBlobman" then
                            local seat=obj:FindFirstChild("VehicleSeat") or obj:FindFirstChildWhichIsA("VehicleSeat",true)
                            if seat then
                                local mc=getChar(); local mr=getRoot(); local mh=getHum()
                                if mr and mh and mh.SeatPart~=seat then
                                    local mc2=RunService.Stepped:Connect(function()
                                        if mr and seat then mr.CFrame=seat.CFrame; mr.AssemblyLinearVelocity=Vector3.zero end
                                    end)
                                    local t0=tick()
                                    while tick()-t0<1 and mh.SeatPart~=seat do seat:Sit(mh); task.wait() end
                                    mc2:Disconnect()
                                    if mh.SeatPart==seat then
                                        task.wait(0.3); mh.Sit=false; mh.Jump=true
                                        task.wait(0.05); mr.CFrame=safeSpot; mr.AssemblyLinearVelocity=Vector3.zero
                                        Notify("Gucci","Destroyed!",2); task.wait(0.5)
                                    else mr.CFrame=safeSpot end
                                end
                            end
                        end
                    end
                end
                task.wait(1)
            end
        end)
    end})
CombatLeft:AddToggle("RemoveAK",{Text="Remove Target Anti-Kick",Default=false,
    Callback=function(v) S.removeAK=v end})
CombatLeft:AddToggle("RemoveAIL",{Text="Remove Target Anti-Input-Lag",Default=false,
    Callback=function(v) S.removeAIL=v end})

-- Bring (FIXED) — requires you to be seated in your own Blobman
-- Works by: teleport blobRoot to target, fire CreatureGrab, bring blobRoot back,
-- then repeatedly set tRoot to home+offset for 12 cycles to drag them in.
CombatLeft:AddButton({Text="Bring Target (Blob)",Tooltip="Must be seated in YOUR blobman first. Teleports blob to target, grabs, drags them back.",Func=function()
    local t=getTarget(); if not t then Notify("Error","Select a target!",2); return end
    local blob=getMountedBlobman()
    if not blob then Notify("Error","You must be seated in your own Blobman!",2); return end
    local blobRoot = blob:FindFirstChild("HumanoidRootPart"); if not blobRoot then return end
    local sObj = blob:FindFirstChild("BlobmanSeatAndOwnerScript"); if not sObj then return end
    local CG = sObj:FindFirstChild("CreatureGrab"); local CD = sObj:FindFirstChild("CreatureDrop")
    local RD = blob:FindFirstChild("RightDetector"); local RW = RD and RD:FindFirstChild("RightWeld")
    if not (CG and CD and RD and RW) then Notify("Error","Blob remotes not found.",2); return end
    local tChar=t.Character; local tRoot=tChar and tChar:FindFirstChild("HumanoidRootPart")
    if not tRoot then Notify("Error","Target has no HRP",2); return end
    task.spawn(function()
        local home = blobRoot.CFrame
        -- Step 1: teleport blob to target
        blobRoot.CFrame = tRoot.CFrame
        blobRoot.AssemblyLinearVelocity = Vector3.zero
        blobRoot.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.3)
        -- Step 2: grab
        pcall(function() CG:FireServer(RD, tRoot, RW) end)
        task.wait(0.5)
        -- Step 3: return blob to home
        blobRoot.CFrame = home
        blobRoot.AssemblyLinearVelocity = Vector3.zero
        blobRoot.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.05)
        -- Step 4: drag target to home in a loop
        for i=1,12 do
            tRoot.CFrame = home * CFrame.new(0,3,0)
            tRoot.AssemblyLinearVelocity = Vector3.zero
            tRoot.AssemblyAngularVelocity = Vector3.zero
            task.wait(0.03)
        end
        -- Step 5: drop
        for i=1,8 do
            local w = RD:FindFirstChild("RightWeld")
            if w then pcall(function() CD:FireServer(w) end) end
            task.wait(0.03)
        end
        Notify("Bring","Done!",2)
    end)
end})

-- Kick Methods
CombatKick:AddLabel("=== No Blob Required ===")
CombatKick:AddToggle("KickSpamGrab",{Text="Kick: Spam Grab (lift to +17Y)",Default=false,Risky=true,
    Callback=function(v)
        S.kickSpam=v; if not v then return end
        task.spawn(function()
            local GE=RS:WaitForChild("GrabEvents",5); if not GE then S.kickSpam=false; return end
            local myChar=getChar(); local myRoot=getRoot(); if not myRoot then S.kickSpam=false; return end
            local savedPos=myRoot.CFrame; local dragging,grabStart=false,0
            while S.kickSpam do
                local target=getTarget()
                if not target or not target.Parent then
                    dragging=false; grabStart=0; task.wait(0.3); continue
                end
                myChar=getChar(); myRoot=getRoot()
                if not myRoot then task.wait(0.5); continue end
                local tChar=target.Character; local tRoot=tChar and tChar:FindFirstChild("HumanoidRootPart")
                local tHum=tChar and tChar:FindFirstChild("Humanoid")
                if tRoot and tHum and tHum.Health>0 then
                    tRoot.AssemblyLinearVelocity=Vector3.zero; tRoot.AssemblyAngularVelocity=Vector3.zero
                    if not dragging then
                        myRoot.CFrame=tRoot.CFrame; myRoot.AssemblyLinearVelocity=Vector3.zero
                        pcall(function()
                            tHum.PlatformStand=true; tHum.Sit=true
                            GE.SetNetworkOwner:FireServer(tRoot,myRoot.CFrame)
                            GE.CreateGrabLine:FireServer(tRoot,Vector3.zero,tRoot.Position,false)
                        end)
                        if grabStart==0 then grabStart=tick() end
                        if tick()-grabStart>0.35 then dragging=true; grabStart=0 end
                    else
                        myRoot.CFrame=savedPos; local lp=savedPos*CFrame.new(0,17,0)
                        tRoot.CFrame=lp; tRoot.AssemblyLinearVelocity=Vector3.zero
                        pcall(function()
                            tHum.PlatformStand=true; tHum.Sit=false
                            GE.SetNetworkOwner:FireServer(tRoot,lp)
                            GE.DestroyGrabLine:FireServer(tRoot)
                            GE.CreateGrabLine:FireServer(tRoot,Vector3.zero,tRoot.Position,false)
                        end)
                    end
                else dragging=false; grabStart=0 end
                RunService.Heartbeat:Wait()
            end
            local r=getRoot(); if r then r.CFrame=savedPos; r.AssemblyLinearVelocity=Vector3.zero end
            Toggles.KickSpamGrab:SetValue(false)
        end)
    end})

CombatKick:AddToggle("KickRagdoll",{Text="Kick: Ragdoll Grab (random angles)",Default=false,Risky=true,
    Callback=function(v)
        S.kickRagdoll=v; if not v then return end
        task.spawn(function()
            local GE=RS:WaitForChild("GrabEvents",5); if not GE then S.kickRagdoll=false; return end
            local myChar=getChar(); local myRoot=getRoot(); if not myRoot then S.kickRagdoll=false; return end
            local savedPos=myRoot.CFrame; local dragging,grabStart=false,0
            while S.kickRagdoll do
                local target=getTarget()
                if not target or not target.Parent then
                    dragging=false; grabStart=0; task.wait(0.3); continue
                end
                myChar=getChar(); myRoot=getRoot()
                if not myRoot then task.wait(0.5); continue end
                local tChar=target.Character; local tRoot=tChar and tChar:FindFirstChild("HumanoidRootPart")
                local tHum=tChar and tChar:FindFirstChild("Humanoid")
                if tRoot and tHum and tHum.Health>0 then
                    tRoot.AssemblyLinearVelocity=Vector3.zero; tRoot.AssemblyAngularVelocity=Vector3.zero
                    if not dragging then
                        myRoot.CFrame=tRoot.CFrame
                        pcall(function()
                            tHum.PlatformStand=true; tHum.Sit=true
                            GE.SetNetworkOwner:FireServer(tRoot,myRoot.CFrame)
                            GE.CreateGrabLine:FireServer(tRoot,Vector3.zero,tRoot.Position,false)
                        end)
                        if grabStart==0 then grabStart=tick() end
                        if tick()-grabStart>0.15 then dragging=true; grabStart=0; myRoot.CFrame=savedPos end
                    else
                        local lockCF = CFrame.new(savedPos.Position+Vector3.new(0,7,0))
                            * CFrame.Angles(math.rad(math.random(-180,180)),math.rad(math.random(-180,180)),math.rad(math.random(-180,180)))
                        tRoot.CFrame=tRoot.CFrame:Lerp(lockCF,0.2)
                        tRoot.AssemblyLinearVelocity=Vector3.zero; tRoot.AssemblyAngularVelocity=Vector3.zero
                        pcall(function()
                            tHum.PlatformStand=true; tHum.Sit=false
                            GE.SetNetworkOwner:FireServer(tRoot,tRoot.CFrame)
                            GE.DestroyGrabLine:FireServer(tRoot)
                            GE.CreateGrabLine:FireServer(tRoot,Vector3.zero,tRoot.Position,false)
                        end)
                    end
                else dragging=false; grabStart=0 end
                RunService.Heartbeat:Wait()
            end
            local r=getRoot(); if r then r.CFrame=savedPos; r.AssemblyLinearVelocity=Vector3.zero end
            Toggles.KickRagdoll:SetValue(false)
        end)
    end})

CombatKick:AddToggle("RagdollSnowball",{Text="Ragdoll Snowball Spam",Default=false,Risky=true,
    Callback=function(v)
        S.ragdollSnow=v; if not v then return end
        task.spawn(function()
            while S.ragdollSnow do
                local target=getTarget()
                if not target or not target.Parent then RunService.Heartbeat:Wait(); continue end
                local tChar=target.Character
                local torso=tChar and (tChar:FindFirstChild("UpperTorso") or tChar:FindFirstChild("Torso"))
                if torso then
                    pcall(function()
                        RS.MenuToys.SpawnToyRemoteFunction:InvokeServer("BallSnowball",
                            torso.CFrame*CFrame.new(math.random(-30,30)/100,math.random(-30,30)/100,math.random(-30,30)/100),
                            Vector3.zero)
                    end)
                    local folder=getToyFolder()
                    if folder then
                        for _,sb in pairs(folder:GetChildren()) do
                            if sb.Name=="BallSnowball" and sb.Parent then
                                local part=sb.PrimaryPart or sb:FindFirstChildWhichIsA("BasePart")
                                if part then
                                    part.CFrame=torso.CFrame*CFrame.new(math.random(-30,30)/100,math.random(-30,30)/100,math.random(-30,30)/100)
                                    part.AssemblyLinearVelocity=Vector3.zero; part.AssemblyAngularVelocity=Vector3.zero
                                end
                            end
                        end
                    end
                end
                RunService.Heartbeat:Wait()
            end
        end)
    end})

CombatKick:AddLabel("=== Blob Required ===")
CombatKick:AddToggle("KickBlob",{Text="Kick: Blob 1-Hand (best)",Tooltip="Requires blob seat. Teleports blob to target, grabs with right arm, lifts to +23Y, spam releases & re-grabs every 0.05s.",Default=false,Risky=true,
    Callback=function(v)
        S.kickBlob=v; if not v then return end
        task.spawn(function()
            local GE=RS:WaitForChild("GrabEvents",5)
            while S.kickBlob do
                local target=getTarget(); local hum=getHum(); local seat=hum and hum.SeatPart
                if not (seat and target and target.Parent) then task.wait(0.5); continue end
                local blob=seat.Parent; local blobRoot=blob:FindFirstChild("HumanoidRootPart") or blob.PrimaryPart
                local sObj=blob:FindFirstChild("BlobmanSeatAndOwnerScript")
                local CG=sObj and sObj:FindFirstChild("CreatureGrab"); local CD=sObj and sObj:FindFirstChild("CreatureDrop")
                local RD=blob:FindFirstChild("RightDetector")
                local RW=RD and (RD:FindFirstChild("RightWeld") or RD:FindFirstChildWhichIsA("Weld"))
                local tChar=target.Character; local tRoot=tChar and tChar:FindFirstChild("HumanoidRootPart")
                local tHum=tChar and tChar:FindFirstChildOfClass("Humanoid")
                if not (CG and CD and tRoot and tHum and tHum.Health>0 and blobRoot) then task.wait(0.1); continue end
                local SavedPos=blobRoot.CFrame
                -- Bring phase
                local t0=tick()
                while tick()-t0<0.35 and S.kickBlob do
                    blobRoot.CFrame=tRoot.CFrame; blobRoot.AssemblyLinearVelocity=Vector3.zero
                    pcall(function()
                        if CG and RD then CG:FireServer(RD,tRoot,RW) end
                        GE.CreateGrabLine:FireServer(tRoot,Vector3.zero,tRoot.Position,false)
                        GE.SetNetworkOwner:FireServer(tRoot,blobRoot.CFrame)
                    end)
                    RunService.Heartbeat:Wait()
                end
                blobRoot.CFrame=SavedPos; blobRoot.AssemblyLinearVelocity=Vector3.zero; task.wait(0.05)
                -- Kick phase
                local pt=0
                while S.kickBlob do
                    if not target or not target.Parent or not target.Character then break end
                    tChar=target.Character; tRoot=tChar and tChar:FindFirstChild("HumanoidRootPart")
                    tHum=tChar and tChar:FindFirstChild("Humanoid")
                    if tRoot and tHum and tHum.Health>0 and blobRoot then
                        blobRoot.CFrame=SavedPos; blobRoot.AssemblyLinearVelocity=Vector3.zero
                        local lockPos=SavedPos*CFrame.new(0,23,0)
                        tRoot.CFrame=lockPos; tRoot.AssemblyLinearVelocity=Vector3.zero; tRoot.AssemblyAngularVelocity=Vector3.zero
                        if tick()-pt>0.05 then
                            pt=tick()
                            pcall(function()
                                tHum.PlatformStand=true; tHum.Sit=true
                                GE.SetNetworkOwner:FireServer(tRoot,lockPos)
                                local w=RD and (RD:FindFirstChild("RightWeld") or RD:FindFirstChildWhichIsA("Weld"))
                                if w then CD:FireServer(w) end
                                GE.DestroyGrabLine:FireServer(tRoot)
                                if RD then CG:FireServer(RD,tRoot,RW) end
                                GE.CreateGrabLine:FireServer(tRoot,Vector3.zero,tRoot.Position,false)
                            end)
                        end
                    else
                        if blobRoot then blobRoot.CFrame=SavedPos; blobRoot.AssemblyLinearVelocity=Vector3.zero end
                    end
                    if not S.kickBlob then break end
                    RunService.Heartbeat:Wait()
                end
                if blobRoot then blobRoot.CFrame=SavedPos; blobRoot.AssemblyLinearVelocity=Vector3.zero end
                -- Target was lost – outer loop will re-acquire on next iteration
            end
        end)
    end})

CombatKick:AddToggle("DualKickLoop",{Text="Kick: Dual Hand Loop",Tooltip="Requires blob seat. Full left+right alternating kick with BodyPosition trap.",Default=false,Risky=true,
    Callback=function(v)
        S.dualKickLoop=v; if not v then return end
        task.spawn(function()
            local lastTChar=nil; local bp=nil
            while S.dualKickLoop do
                local target=getTarget(); local hum=getHum(); local seat=hum and hum.SeatPart
                if not (seat and target and target.Parent) then task.wait(0.5); continue end
                local sp=seat.Parent
                local sObj=sp:FindFirstChild("BlobmanSeatAndOwnerScript")
                local grab=sObj and sObj:FindFirstChild("CreatureGrab")
                local drop=sObj and sObj:FindFirstChild("CreatureDrop")
                local LD=sp:FindFirstChild("LeftDetector"); local RD=sp:FindFirstChild("RightDetector")
                local LW=LD and LD:FindFirstChild("LeftWeld"); local RW=RD and RD:FindFirstChild("RightWeld")
                local hrp=getChar() and getChar():FindFirstChild("HumanoidRootPart")
                local tChar=target.Character; local tHRP=tChar and tChar:FindFirstChild("HumanoidRootPart")
                local tHum=tChar and tChar:FindFirstChildOfClass("Humanoid")
                if not (grab and drop and tHRP and tHum and tHum.Health>0) then task.wait(0.1); continue end
                if tChar~=lastTChar then
                    lastTChar=tChar
                    if bp then bp:Destroy(); bp=nil end
                    if hrp then hrp.CFrame=tHRP.CFrame*CFrame.new(0,25,0) end
                    task.wait(0.2)
                    grab:FireServer(LD,tHRP,LW); task.wait(0.3); drop:FireServer(LW,tHRP); task.wait(0.1)
                    bp=Instance.new("BodyPosition"); bp.Position=Vector3.new(0,999999,0)
                    bp.MaxForce=Vector3.new(math.huge,math.huge,math.huge); bp.Parent=tHRP
                    grab:FireServer(LD,tHRP,LW); task.wait(0.2); drop:FireServer(LW,tHRP)
                end
                grab:FireServer(LD,tHRP,LW); task.wait(); drop:FireServer(LW,tHRP); task.wait()
                grab:FireServer(RD,tHRP,RW); task.wait(); drop:FireServer(RW,tHRP); task.wait()
                grab:FireServer(LD,tHRP,LW); grab:FireServer(RD,tHRP,RW); task.wait()
                drop:FireServer(LW,tHRP); drop:FireServer(RW,tHRP); task.wait()
            end
            if bp then bp:Destroy() end
            S.dualKickLoop=false; Toggles.DualKickLoop:SetValue(false)
        end)
    end})

local flingBAV, flingOrig
CombatKick:AddToggle("FlingTarget",{Text="Fling (10k BAV)",Default=false,Risky=true,
    Callback=function(v)
        S.flingActive=v
        if not v then
            if flingBAV then flingBAV:Destroy(); flingBAV=nil end
            local hrp=getRoot()
            if hrp then hrp.AssemblyAngularVelocity=Vector3.zero; hrp.AssemblyLinearVelocity=Vector3.zero end
            if flingOrig and hrp then hrp.CFrame=flingOrig end
            return
        end
        flingOrig=getRoot() and getRoot().CFrame
        task.spawn(function()
            while S.flingActive do
                local target=getTarget(); local myHRP=getRoot()
                if not (myHRP and target and target.Parent) then task.wait(0.5); continue end
                local tRoot=target.Character and target.Character:FindFirstChild("HumanoidRootPart")
                local tHum=target.Character and target.Character:FindFirstChildOfClass("Humanoid")
                if tRoot and tHum and tHum.Health>0 then
                    if not flingBAV or not flingBAV.Parent then
                        if flingBAV then flingBAV:Destroy() end
                        flingBAV=Instance.new("BodyAngularVelocity")
                        flingBAV.MaxTorque=Vector3.new(math.huge,math.huge,math.huge)
                        flingBAV.AngularVelocity=Vector3.new(0,10000,0); flingBAV.P=10000
                        flingBAV.Parent=myHRP
                    end
                    local c=RunService.Heartbeat:Connect(function()
                        if not S.flingActive or not tRoot.Parent then return end
                        myHRP.CFrame=tRoot.CFrame; myHRP.AssemblyLinearVelocity=Vector3.zero
                    end)
                    local t0=tick()
                    repeat task.wait(0.1) until not S.flingActive or not tRoot.Parent or tick()-t0>1.5
                    c:Disconnect()
                else task.wait(0.2) end
                task.wait(0.1)
            end
            if flingBAV then flingBAV:Destroy(); flingBAV=nil end
            Toggles.FlingTarget:SetValue(false)
        end)
    end})

-- Grab
CombatGrab:AddSlider("ThrowPower",{Text="Throw Power",Default=750,Min=1,Max=20000,Rounding=0,
    Callback=function(v) throwPower=v end})
CombatGrab:AddToggle("ThrowStr",{Text="Throw Strength (RMB)",Default=false,Callback=function(v) S.throwStrength=v end})
CombatGrab:AddToggle("KillGrab",{Text="Kill Grab",Default=false,Risky=true,Callback=function(v) S.killGrab=v end})
CombatGrab:AddToggle("MasslessGrab",{Text="Massless Grab",Tooltip="Makes DragPart's AlignPosition responsiveness max — things fly when grabbed.",Default=false,
    Callback=function(v) S.masslessGrab=v end})

-- Limbs
CombatLimbs:AddLabel("Target limbs:")
for _, limb in ipairs({"Right Arm","Left Arm","Right Leg","Left Leg","Head"}) do
    CombatLimbs:AddButton({Text="Del "..limb,Func=function()
        local t=getTarget(); if not t or not t.Character then Notify("Error","No target",2); return end
        deleteLimb(t.Character,limb)
    end})
end
CombatLimbs:AddDivider()
CombatLimbs:AddLabel("My limbs:")
for _, limb in ipairs({"Right Arm","Left Arm","Right Leg","Left Leg"}) do
    CombatLimbs:AddButton({Text="Del "..limb,Func=function() deleteLimb(getChar(),limb) end})
end

-- ============================================================
-- [[ 38. AURAS TAB ]]
-- ============================================================

local AurasLeft  = Tabs.Auras:AddLeftGroupbox("Anti-Kick Aura")
local AurasRight = Tabs.Auras:AddRightGroupbox("Kick Auras")

AurasLeft:AddSlider("RAKARadius",{Text="Radius",Default=15,Min=5,Max=50,Rounding=0,
    Callback=function(v) removeAKRadius=v end})
AurasLeft:AddToggle("RAKAWhitelist",{Text="Whitelist Friends",Default=true,
    Callback=function(v) auraWLFriends.removeAK=v end})
AurasLeft:AddToggle("RemoveAKAura",{Text="Remove Anti-Kick Aura",Default=false,
    Callback=function(v) S.removeAKAura=v end})

AurasRight:AddSlider("DualKickAuraRad",{Text="Dual Kick Radius",Default=20,Min=5,Max=50,Rounding=0,
    Callback=function(v) dualKickRadius=v end})
AurasRight:AddToggle("DualKickAuraWL",{Text="Whitelist Friends",Default=true,
    Callback=function(v) auraWLFriends.dualKick=v end})
AurasRight:AddToggle("DualKickAura",{Text="Dual Hand Kick Aura",Default=false,Risky=true,
    Callback=function(v) S.dualKickAura=v end})
AurasRight:AddDivider()
AurasRight:AddSlider("KickAura1Rad",{Text="1-Hand Aura Radius",Default=20,Min=5,Max=50,Rounding=0,
    Callback=function(v) kickAura1Radius=v end})
AurasRight:AddToggle("KickAura1WL",{Text="Whitelist Friends",Default=true,
    Callback=function(v) auraWLFriends.kick1=v end})
AurasRight:AddToggle("KickAura1",{Text="Kick Aura 1-Hand",Default=false,Risky=true,
    Callback=function(v) S.kickAura1=v end})

-- ============================================================
-- [[ 39. PLAYER TAB ]]
-- ============================================================

local PlyrLeft  = Tabs.Player:AddLeftGroupbox("Movement")
local PlyrRight = Tabs.Player:AddRightGroupbox("View & ESP")
local PlyrPerf  = Tabs.Player:AddLeftGroupbox("Performance")

PlyrLeft:AddSlider("WalkSpeed",{Text="Walk Speed",Default=16,Min=16,Max=150,Rounding=0,
    Callback=function(v) targetWalkSpeed=v; local h=getHum(); if h then h.WalkSpeed=v end end})
PlyrLeft:AddSlider("JumpPower",{Text="Jump Power",Default=50,Min=50,Max=1000,Rounding=0,
    Callback=function(v) local h=getHum(); if h then h.JumpPower=v end end})
PlyrLeft:AddToggle("InfJump",{Text="Infinite Jump",Default=false,Callback=function(v) S.infJump=v end})
PlyrLeft:AddToggle("Noclip",{Text="Noclip",Default=false,Callback=function(v) S.noclip=v end})
PlyrLeft:AddToggle("SpinChar",{Text="Spin Character",Default=false,Callback=function(v) S.spinChar=v end})
PlyrLeft:AddSlider("SpinSpeedSlider",{Text="Spin Speed",Default=5,Min=1,Max=50,Rounding=0,
    Callback=function(v) spinSpeed=v end})

PlyrRight:AddToggle("ThirdPerson",{Text="3rd Person View",Default=false,
    Callback=function(v)
        S.thirdPerson=v
        if v then
            LP.CameraMode=Enum.CameraMode.Classic
            Camera.CameraType=Enum.CameraType.Custom
            Camera.CameraSubject=LP.Character and LP.Character:WaitForChild("Humanoid")
            LP.CameraMaxZoomDistance=9999; LP.CameraMinZoomDistance=0.5
        else
            LP.CameraMode=Enum.CameraMode.Classic
            LP.CameraMaxZoomDistance=128; LP.CameraMinZoomDistance=0.5
        end
    end})
PlyrRight:AddToggle("PCLDView",{
    Text="PCLD View (Box ESP)",
    Tooltip="Shows white boxes on 'partesp' and 'playercharacterlocationdetector' parts — these are used by the game to detect your location for kicking/grabs.",
    Default=false,
    Callback=function(v)
        S.pcldESP=v
        if v then
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if isEspTarget(obj) then addBox(obj) end
            end
        else removeAllBoxes() end
    end})
local nameESPConns = {}
PlyrRight:AddToggle("NicknameESP",{Text="Nickname ESP",Default=false,
    Callback=function(v)
        S.nameESP=v
        if v then
            for _, plr in pairs(Players:GetPlayers()) do
                createNameESP(plr)
                local c = plr.CharacterAdded:Connect(function() createNameESP(plr) end)
                table.insert(nameESPConns, c)
            end
            local c = Players.PlayerAdded:Connect(function(plr)
                local cc = plr.CharacterAdded:Connect(function() createNameESP(plr) end)
                table.insert(nameESPConns, cc)
            end)
            table.insert(nameESPConns, c)
        else
            for _, c in ipairs(nameESPConns) do disconnect(c) end
            nameESPConns = {}
            for _, plr in pairs(Players:GetPlayers()) do
                if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                    local nESP = plr.Character.HumanoidRootPart:FindFirstChild("NameESP")
                    if nESP then nESP:Destroy() end
                end
            end
        end
    end})

PlyrPerf:AddButton({Text="Boost FPS",Func=boostFPS})
PlyrPerf:AddButton({Text="Restore FPS",Func=restoreFPS})
PlyrPerf:AddSlider("FOVSlider",{Text="FOV",Default=70,Min=1,Max=120,Rounding=0,Suffix="°",
    Callback=function(v) Camera.FieldOfView=v end})

-- ============================================================
-- [[ 40. MISC TAB ]]
-- ============================================================

local MiscLeft = Tabs.Misc:AddLeftGroupbox("Tools")

MiscLeft:AddToggle("DreamyNight",{Text="Dreamy Night Shader",Default=false,
    Callback=function(v) S.dreamyNight=v; if v then enableDreamyNight() else disableDreamyNight() end end})
MiscLeft:AddToggle("NoBarrier",{Text="Ignore House Barriers",Default=false,
    Callback=function(v)
        S.noBarrier=v
        local plots=Workspace:FindFirstChild("Plots"); if not plots then return end
        for _, plot in ipairs(plots:GetChildren()) do
            local barrier=plot:FindFirstChild("Barrier")
            if barrier then
                for _, obj in ipairs(barrier:GetDescendants()) do
                    if obj:IsA("BasePart") then obj.CanCollide=not v end
                end
            end
        end
    end})
MiscLeft:AddSlider("PacketLagAmount",{Text="Packet Lag Amount",Default=100,Min=10,Max=5000,Rounding=0,
    Callback=function(v) PacketSpamAmount=v end})
MiscLeft:AddToggle("PacketLag",{Text="Packet Lag",Default=false,Risky=true,
    Callback=function(v) S.packetLag=v end})
MiscLeft:AddToggle("AutoReset",{Text="Auto Reset",Default=false,Risky=true,
    Callback=function(v) S.autoReset=v end})
MiscLeft:AddToggle("Triggerbot",{Text="Trigger Bot",Tooltip="Auto-grabs players in your crosshair within 29.3 studs.",Default=false,
    Callback=function(v) S.triggerbot=v; Triggerbot.Enabled=v end})

-- Keybinds
local KeyGroup = Tabs.Misc:AddRightGroupbox("Keybinds")
KeyGroup:AddLabel("Teleport Tool"):AddKeyPicker("TPKeybind",{Default="X",Text="Teleport to Mouse",NoUI=false,
    Callback=function()
        local hrp=getRoot(); if not hrp then return end
        local mouse=LP:GetMouse()
        hrp.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0,3,0))
    end})
KeyGroup:AddLabel("Blobman"):AddKeyPicker("SitBlobKey",{Default="Z",Text="Sit nearest Blobman",NoUI=false,
    Callback=function() sitNearestBlob(40) end})

-- Whitelist / Radar
local WLGroup = Tabs.Misc:AddLeftGroupbox("Target Radar")
WLGroup:AddDropdown("MultiWhitelist",{Values={},Multi=true,Text="Whitelist Players",Callback=function(_)end})
WLGroup:AddButton({Text="Refresh List",Func=function()
    local list={}
    for _, p in ipairs(Players:GetPlayers()) do
        if p~=LP then table.insert(list, "("..p.Name..")") end
    end
    Options.MultiWhitelist:SetValues(list)
end})
WLGroup:AddToggle("JoinNotify",{Text="Target Joined Notify",Default=false,
    Callback=function(v) S.joinNotify=v; if v then startJoinNotify() end end})

-- ============================================================
-- [[ 41. FUN TAB ]]
-- ============================================================

local FunLeft  = Tabs.Fun:AddLeftGroupbox("Animations")
local FunRight = Tabs.Fun:AddRightGroupbox("Troll")
local FunBuild = Tabs.Fun:AddLeftGroupbox("Build")

FunLeft:AddDropdown("AnimSelect",{Values={"Crazy","Insane","Collapse","Zombie"},Default="Crazy",Text="Animation",
    Callback=function(v) selectedAnimName=v; if S.animPlay then playAnimation() end end})
FunLeft:AddToggle("AnimPlay",{Text="Play Animation",Default=false,
    Callback=function(v) S.animPlay=v; if v then playAnimation() else stopAnimation() end end})
FunLeft:AddToggle("JerkOff",{Text="Jerk Off",Default=false,
    Callback=function(v) S.jerkOff=v; if v then startJerkOff() else stopJerkOff() end end})
FunLeft:AddToggle("Bang",{Text="Bang (Slow)",Default=false,
    Callback=function(v) S.bang=v; if v then startBang() else stopBang() end end})

FunRight:AddToggle("FollowStare",{Text="Follow & Stare (random player)",Default=false,
    Callback=function(v) S.followStare=v end})
FunRight:AddToggle("FakeDeath",{Text="Fake Death",Default=false,
    Callback=function(v)
        local hum=getHum(); if not hum then return end
        if v then hum:ChangeState(Enum.HumanoidStateType.Physics); hum.PlatformStand=true
        else hum.PlatformStand=false; hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end})
FunRight:AddToggle("FakeLag",{Text="Fake Lag",Default=false,
    Callback=function(v) S.fakeLag=v end})
FunRight:AddToggle("UFOShuriken",{Text="Stick Shuriken to UFO",Default=false,
    Callback=function(v)
        S.ufoShuriken=v; if not v then return end
        task.spawn(function()
            local StickyEv = RS:WaitForChild("PlayerEvents"):WaitForChild("StickyPartEvent")
            local SpawnRem = RS.MenuToys:WaitForChild("SpawnToyRemoteFunction")
            local CanSpawn = LP:WaitForChild("CanSpawnToy")
            local ToysF    = Workspace:WaitForChild(LP.Name.."SpawnedInToys")
            local UFOs = {}
            local map  = Workspace:FindFirstChild("Map")
            local ato  = map and map.AlwaysHereTweenedObjects
            if ato then
                UFOs = {ato:FindFirstChild("InnerUFO"), ato:FindFirstChild("OuterUFO")}
            end
            local function getHRP()
                if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
                    return LP.Character.HumanoidRootPart
                end
                return LP.CharacterAdded:Wait():WaitForChild("HumanoidRootPart")
            end
            for i=1,12 do
                local t0=tick()
                while not CanSpawn.Value do
                    if tick()-t0>5 then break end; task.wait(0.1)
                end
                local hrp=getHRP()
                if hrp then
                    pcall(function() SpawnRem:InvokeServer("NinjaShuriken",hrp.CFrame*CFrame.new(0,10,15),Vector3.zero) end)
                end
                task.wait(0.15)
            end
            task.wait(1)
            for _, toy in ipairs(ToysF:GetChildren()) do
                if toy.Name=="NinjaShuriken" and toy:FindFirstChild("StickyPart") then
                    for _, ufo in ipairs(UFOs) do
                        if ufo and ufo:FindFirstChild("Object") and ufo.Object:FindFirstChild("ObjectModel") and ufo.Object.ObjectModel:FindFirstChild("Body") then
                            StickyEv:FireServer(toy.StickyPart, ufo.Object.ObjectModel.Body, CFrame.new())
                            local f=ufo.Object:FindFirstChild("FollowThisPart")
                            if f then
                                local ao=f:FindFirstChild("AlignOrientation"); if ao then ao.Enabled=false end
                                local ap=f:FindFirstChild("AlignPosition");    if ap then ap.Enabled=false end
                            end
                        end
                    end
                end
            end
        end)
    end})

-- Build
FunBuild:AddLabel("Heart Sparkler Build"):AddLabel("Spawn a sparkler and animate it in a heart curve around you.")
FunBuild:AddToggle("HeartBuild",{Text="Heart Sparkler",Default=false,
    Callback=function(v)
        S.heartBuild=v
        if v then startHeartBuild()
        else
            disconnect(heartConn)
            if heartToy then pcall(function() heartToy:Destroy() end); heartToy=nil end
        end
    end})
FunBuild:AddButton({Text="Spawn Blobman",Func=function() task.spawn(spawnBlobman) end})
FunBuild:AddButton({Text="Sit Nearest Blob",Func=function() sitNearestBlob(40) end})

-- ============================================================
-- [[ 42. SETTINGS TAB ]]
-- ============================================================

local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu")
MenuGroup:AddToggle("ShowCursor",{Text="Custom Cursor",Default=false,
    Callback=function(v) Library.ShowCustomCursor=v end})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind",{Default="RightShift",NoUI=true,Text="Toggle Menu"})
MenuGroup:AddButton({Text="Unload",Func=function() Library:Unload() end})
Library.ToggleKeybind = Options.MenuKeybind

-- ============================================================
-- [[ 43. THEME + SAVE ]]
-- ============================================================

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("VerbalSigma")
SaveManager:SetFolder("VerbalSigma/configs")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()
