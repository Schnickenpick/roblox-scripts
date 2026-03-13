-- ============================================================
--   PALETTE BOAT  v5
--   Fixes:
--     1. Formation — spawn near player THEN move to grid slot
--        (stops the LookVector*-20 from overriding grid positions)
--     2. Server-side movement — SetNetworkOwner fired per-BasePart
--        with CFrame.new(HRP.Position, part.Position) so the server
--        accepts our CFrame writes and replicates them
-- ============================================================

-- ── Services ─────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ── Player / Character ────────────────────────────────────────
local LocalPlayer = Players.LocalPlayer
local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
LocalPlayer.CharacterAdded:Connect(function(c) Character = c end)

local function GetHRP()
    return Character and Character:FindFirstChild("HumanoidRootPart")
end

-- ── Remotes (message(3).txt) ──────────────────────────────────
local MenuToys               = ReplicatedStorage:WaitForChild("MenuToys")
local SpawnToyRemoteFunction = MenuToys:WaitForChild("SpawnToyRemoteFunction")
local DestroyToy             = MenuToys:WaitForChild("DestroyToy")

local GrabEvents      = ReplicatedStorage:WaitForChild("GrabEvents")
local SetNetworkOwner = GrabEvents:WaitForChild("SetNetworkOwner")

-- ── Toy folder ────────────────────────────────────────────────
local function GetToyFolder()
    return workspace:WaitForChild(LocalPlayer.Name .. "SpawnedInToys", 10)
end

-- ── Constants ─────────────────────────────────────────────────
local TOY_NAME      = "PalletLightBrown"
local FLEET_SIZE    = 20
local MASTER_INDEX  = 10
local SPAWN_TIMEOUT = 10
local COLS          = 5
local ROWS          = 4
local SPACING       = 3.5
local LERP_ALPHA    = 0.2

-- ── Global state ──────────────────────────────────────────────
getgenv().MyPaletteFleet = getgenv().MyPaletteFleet or {}
local Fleet         = getgenv().MyPaletteFleet
local MasterPalette = nil
local boatHeight    = 0
local boatActive    = false
local heartbeatConn = nil
local isBuilding    = false

-- ── Obsidian ──────────────────────────────────────────────────
local Library = loadstring(
    game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua")
)()

local function Notify(msg)
    pcall(function() Library:Notify(msg) end)
    print("[PaletteBoat] " .. tostring(msg))
end

-- ============================================================
--   message(3).txt  FUNCTIONS
-- ============================================================

-- Hold() ──────────────────────────────────────────────────────
local function Hold(Food)
    local HoldPart = Food:WaitForChild("HoldPart", 0.5)
    if not HoldPart then return end
    local HoldFunction = HoldPart:WaitForChild("HoldItemRemoteFunction", 0.5)
    if not HoldFunction then return end
    task.spawn(function()
        HoldFunction:InvokeServer(Food, Character)
    end)
end

-- Drop() ──────────────────────────────────────────────────────
local function Drop(Food, CF)
    local HoldPart = Food:FindFirstChild("HoldPart")
    if not HoldPart then return end
    local RC = HoldPart:FindFirstChild("RigidConstraint")
    if not RC then return end
    local LeftGrip = Character
        and Character:FindFirstChild("Left Arm")
        and Character["Left Arm"]:FindFirstChild("LeftGripAttachment")
    if RC.Attachment1 == LeftGrip then
        local DropFn = HoldPart:FindFirstChild("DropItemRemoteFunction")
        if DropFn then
            task.spawn(function()
                DropFn:InvokeServer(Food, CF or CFrame.new(), Vector3.zero)
            end)
        end
    end
end

-- SetNetworkOwner — message(3).txt Grab() signature:
--   SetNetworkOwner:FireServer(Target, CFrame.new(HRP.Position, Target.Position))
-- Called per BasePart so the server grants us ownership of every
-- physics body in the model, allowing our CFrame writes to replicate.
local function ClaimOwnership(model)
    local hrp = GetHRP()
    if not hrp then return end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                SetNetworkOwner:FireServer(
                    part,
                    CFrame.new(hrp.Position, part.Position)
                )
            end)
        end
    end
end

-- Spawn() — message(3).txt ChildAdded pattern + VerbalHub ToyNumber gate.
-- NOTE: We intentionally pass the HRP CFrame as the spawn point, NOT the
-- grid offset — the game's NewCFrame = CF + CF.LookVector*-20 means it
-- lands near the player regardless.  We reposition to the grid slot AFTER
-- capture (see BuildFleet).
local function SpawnOnePalette()
    local folder = GetToyFolder()
    if not folder then return nil end

    local toyNumObj   = folder:FindFirstChild("ToyNumber")
    local expectedNum = toyNumObj and toyNumObj.Value

    local result = nil
    local done   = false

    -- Listener connected BEFORE invoke so we never miss the child
    local conn = folder.ChildAdded:Connect(function(child)
        if done or child.Name ~= TOY_NAME then return end
        if expectedNum then
            local numObj = child:WaitForChild("ThisToysNumber", 2)
            if numObj and numObj.Value == expectedNum then
                result = child
                done   = true
            end
        else
            result = child
            done   = true
        end
    end)

    local hrp   = GetHRP()
    local base  = hrp and hrp.CFrame or CFrame.new()
    -- message(3).txt: NewCFrame = CF + CF.LookVector*-20
    local newCF = base + base.LookVector * -20

    task.spawn(function()
        SpawnToyRemoteFunction:InvokeServer(TOY_NAME, newCF, Vector3.zero)
    end)

    local deadline = tick() + SPAWN_TIMEOUT
    repeat task.wait(0.05) until done or tick() > deadline
    conn:Disconnect()

    if not result or not result.Parent then return nil end
    return result
end

-- ============================================================
--   GRID MATH  —  5 × 4 deck
-- ============================================================

local function GridOffset(i)
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local x   = (col - (COLS - 1) / 2) * SPACING
    local z   = (row - (ROWS - 1) / 2) * SPACING
    local y   = -3 + boatHeight
    return CFrame.new(x, y, z)
end

-- Move every BasePart of a model to a target CFrame.
-- Uses SetPrimaryPartCFrame when available so relative offsets
-- between internal parts are preserved.
local function MovePalette(palette, targetCF)
    if not palette or not palette.Parent then return end
    if palette.PrimaryPart then
        palette:SetPrimaryPartCFrame(targetCF)
    else
        -- Flat model — move every BasePart directly
        for _, p in ipairs(palette:GetDescendants()) do
            if p:IsA("BasePart") then p.CFrame = targetCF end
        end
    end
end

-- ============================================================
--   WELD PHASE
-- ============================================================

local function WeldFleet()
    local masterIdx = math.min(MASTER_INDEX, #Fleet)
    MasterPalette   = Fleet[masterIdx]

    if not MasterPalette then
        Notify("ERROR: no master palette at index " .. masterIdx)
        return false
    end

    local masterPart = MasterPalette.PrimaryPart
                    or MasterPalette:FindFirstChildWhichIsA("BasePart")
    if not masterPart then
        Notify("ERROR: master has no BasePart")
        return false
    end

    Notify("Welding to master #" .. masterIdx .. "…")

    for i, palette in ipairs(Fleet) do
        if i == masterIdx or not palette or not palette.Parent then continue end

        local slavePart = palette.PrimaryPart
                       or palette:FindFirstChildWhichIsA("BasePart")
        if not slavePart then continue end

        local weld  = Instance.new("WeldConstraint")
        weld.Part0  = masterPart
        weld.Part1  = slavePart
        weld.Parent = MasterPalette

        -- Slaves unanchored — weld locks them to master
        for _, p in ipairs(palette:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored   = false
                p.CanCollide = false
            end
        end
    end

    -- Master anchored — driven by Heartbeat
    for _, p in ipairs(MasterPalette:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Anchored   = true
            p.CanCollide = false
        end
    end

    Notify("Weld done. Fleet moves as one object.")
    return true
end

-- ============================================================
--   BOAT DRIVE  —  Heartbeat on master only
-- ============================================================

local function StartBoatDrive()
    if heartbeatConn then heartbeatConn:Disconnect() end
    if not MasterPalette then
        Notify("Build fleet first.")
        return
    end

    local masterPart = MasterPalette.PrimaryPart
                    or MasterPalette:FindFirstChildWhichIsA("BasePart")
    if not masterPart then return end

    heartbeatConn = RunService.Heartbeat:Connect(function()
        local hrp = GetHRP()
        if not hrp or not masterPart.Parent then return end

        -- Target: centred under HRP at chosen height
        local target = hrp.CFrame * CFrame.new(0, -3 + boatHeight, 0)

        -- Lerp so movement is smooth even after teleports
        -- Writing masterPart.CFrame replicates because we called
        -- SetNetworkOwner for all parts during BuildFleet
        masterPart.CFrame = masterPart.CFrame:Lerp(target, LERP_ALPHA)
    end)

    Notify("Boat Drive ON.")
end

local function StopBoatDrive()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    Notify("Boat Drive OFF.")
end

-- ============================================================
--   BUILD FLEET
-- ============================================================

local function BuildFleet()
    if isBuilding then Notify("Already building.") return end
    local hrp = GetHRP()
    if not hrp then Notify("No character.") return end

    StopBoatDrive()
    boatActive = false

    -- Destroy previous fleet
    for _, palette in ipairs(Fleet) do
        pcall(function()
            if palette and palette.Parent then
                Drop(palette)
                task.wait(0.03)
                DestroyToy:FireServer(palette)
            end
        end)
    end
    table.clear(Fleet)
    MasterPalette = nil

    isBuilding = true
    Notify("Spawning " .. FLEET_SIZE .. " palettes…")

    -- ── Phase 1: Spawn all palettes near the player ───────────
    -- We intentionally do NOT try to spawn at grid positions — the
    -- server ignores our CFrame and applies LookVector*-20 anyway.
    -- Instead: spawn → capture → own → anchor, then mass-reposition.
    for i = 1, FLEET_SIZE do
        Notify(i .. "/" .. FLEET_SIZE .. "…")

        local palette = SpawnOnePalette()

        if not palette then
            Notify("✘ Slot " .. i .. " timed out.")
            table.insert(Fleet, false)
            task.wait(0.1)
            continue
        end

        -- Claim server network ownership per-part (message(3).txt Grab signature)
        ClaimOwnership(palette)
        task.wait(0.06)

        -- Hold via HoldItemRemoteFunction (message(3).txt Hold)
        Hold(palette)
        task.wait(0.08)

        -- Disable collisions; anchor temporarily while remaining
        -- palettes spawn so they don't float / fling
        for _, p in ipairs(palette:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
                p.Anchored   = true
            end
        end

        table.insert(Fleet, palette)
        Notify("✔ " .. i .. " captured.")
        task.wait(0.1)
    end

    -- Strip failed slots
    local clean = {}
    for _, v in ipairs(Fleet) do
        if v then table.insert(clean, v) end
    end
    table.clear(Fleet)
    for _, v in ipairs(clean) do table.insert(Fleet, v) end

    if #Fleet == 0 then
        Notify("ERROR: No palettes captured.")
        isBuilding = false
        return
    end

    -- ── Phase 2: Reposition into formation ───────────────────
    -- Now all palettes are captured and owned.  We move them to
    -- their grid slots.  Because we have network ownership the
    -- CFrame write replicates to every client / the server.
    Notify("Positioning fleet into formation…")
    hrp = GetHRP()  -- refresh after spawning delay
    for i, palette in ipairs(Fleet) do
        local targetCF = hrp.CFrame * GridOffset(i)
        MovePalette(palette, targetCF)
    end
    task.wait(0.2)  -- let physics settle

    -- ── Phase 3: Weld ─────────────────────────────────────────
    Notify("Welding fleet…")
    local ok = WeldFleet()
    if not ok then isBuilding = false return end

    Notify("Fleet ready — " .. #Fleet .. " palettes. Toggle Boat Drive!")
    isBuilding = false
    if boatActive then StartBoatDrive() end
end

-- ============================================================
--   OBSIDIAN UI
-- ============================================================

local Window = Library:CreateWindow({
    Title    = "OBSIDIAN | PALETTE BOAT",
    Center   = true,
    AutoShow = true,
})

local Tabs = {
    Main     = Window:AddTab("Main"),
    Drive    = Window:AddTab("Drive"),
    Settings = Window:AddTab("Settings"),
}

-- ── Main ──────────────────────────────────────────────────────
local BuildBox = Tabs.Main:AddLeftGroupbox("Fleet Builder")

BuildBox:AddLabel("Spawn → Own → Hold → Anchor → Formation → Weld")
BuildBox:AddDivider()

BuildBox:AddButton({
    Text    = "▶  Build Welded Fleet",
    Func    = function() task.spawn(BuildFleet) end,
    Tooltip = "Spawns " .. FLEET_SIZE .. " palettes, claims ownership, positions into 5×4 grid, welds to master #" .. MASTER_INDEX,
})

BuildBox:AddButton({
    Text    = "✕  Destroy Fleet",
    Func    = function()
        StopBoatDrive()
        boatActive = false
        for _, palette in ipairs(Fleet) do
            pcall(function()
                if palette and palette.Parent then
                    DestroyToy:FireServer(palette)
                end
            end)
        end
        table.clear(Fleet)
        MasterPalette = nil
        Notify("Fleet destroyed.")
    end,
})

local InfoBox = Tabs.Main:AddRightGroupbox("Status")

InfoBox:AddButton({
    Text = "Fleet Info",
    Func = function()
        Notify(
            "Fleet: " .. #Fleet ..
            " | Master: " .. tostring(MasterPalette ~= nil) ..
            " | Drive: " .. tostring(boatActive)
        )
    end,
})

-- ── Drive ─────────────────────────────────────────────────────
local DriveBox = Tabs.Drive:AddLeftGroupbox("Boat Drive")

DriveBox:AddLabel("Only master palette moves. WeldConstraints carry the rest.")
DriveBox:AddDivider()

DriveBox:AddToggle("BoatToggle", {
    Text    = "Activate Boat Drive",
    Default = false,
    Tooltip = "Heartbeat lerps master under HRP — welds do the rest",
    Callback = function(val)
        boatActive = val
        if val then StartBoatDrive() else StopBoatDrive() end
    end,
})

DriveBox:AddDivider()

DriveBox:AddSlider("HeightSlider", {
    Text     = "Boat Height",
    Default  = 0,
    Min      = -10,
    Max      = 10,
    Rounding = 1,
    Tooltip  = "Raise/lower the deck relative to your feet",
    Callback = function(val)
        boatHeight = val
        Notify("Height → " .. val)
    end,
})

local PhysBox = Tabs.Drive:AddRightGroupbox("Physics Tools")

PhysBox:AddButton({
    Text    = "Re-apply Noclip",
    Func    = function()
        for _, p in ipairs(Fleet) do
            if p and p.Parent then
                for _, part in ipairs(p:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
        Notify("Noclip re-applied.")
    end,
})

PhysBox:AddButton({
    Text    = "Re-claim Ownership",
    Tooltip = "Re-fires SetNetworkOwner for all fleet parts",
    Func    = function()
        for _, p in ipairs(Fleet) do
            if p and p.Parent then ClaimOwnership(p) end
        end
        Notify("Ownership re-claimed for " .. #Fleet .. " palettes.")
    end,
})

PhysBox:AddButton({
    Text    = "Snap to Formation",
    Tooltip = "Immediately moves all palettes back to grid offsets",
    Func    = function()
        local hrp = GetHRP()
        if not hrp then Notify("No character.") return end
        for i, palette in ipairs(Fleet) do
            MovePalette(palette, hrp.CFrame * GridOffset(i))
        end
        Notify("Snapped " .. #Fleet .. " palettes to formation.")
    end,
})

-- ── Settings ──────────────────────────────────────────────────
local SetBox = Tabs.Settings:AddLeftGroupbox("Menu")
SetBox:AddButton("Unload", function() Library:Unload() end)
SetBox:AddLabel("Toggle Keybind"):AddKeyPicker("MenuBind", {
    Default = "End",
    NoUI    = true,
    Text    = "Menu bind",
})
Library.ToggleKeybind = Library.Options.MenuBind

Notify("Palette Boat v5 loaded — Build Fleet to begin!")
