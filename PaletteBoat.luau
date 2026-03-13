-- ============================================================
--   PALETTE BOAT  v4  —  Welded Formation
--   Spawn  → Capture → Hold → Anchor → Weld → Boat Drive
--   Remote logic: message(3).txt verbatim
--   Network ownership: SetNetworkOwner fallback (Cosmic pattern)
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
local TOY_NAME     = "PalletLightBrown"
local FLEET_SIZE   = 20
local MASTER_INDEX = 10
local SPAWN_TIMEOUT = 10

local COLS    = 5
local ROWS    = 4
local SPACING = 3.5

-- ── State ─────────────────────────────────────────────────────
getgenv().MyPaletteFleet = getgenv().MyPaletteFleet or {}
local Fleet         = getgenv().MyPaletteFleet
local MasterPalette = nil
local boatActive    = false
local boatHeight    = 0
local heartbeatConn = nil
local isBuilding    = false

-- ── Obsidian UI ───────────────────────────────────────────────
local Library = loadstring(
    game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua")
)()

local function Notify(msg)
    pcall(function() Library:Notify(msg) end)
    print("[PaletteBoat] " .. tostring(msg))
end

-- ============================================================
--   MESSAGE(3).TXT  FUNCTIONS
-- ============================================================

-- Hold() — HoldItemRemoteFunction:InvokeServer(Food, Character)
local function Hold(Food)
    local HoldPart = Food:WaitForChild("HoldPart", 0.5)
    if not HoldPart then return end
    local HoldFunction = HoldPart:WaitForChild("HoldItemRemoteFunction", 0.5)
    if not HoldFunction then return end
    task.spawn(function()
        HoldFunction:InvokeServer(Food, Character)
    end)
end

-- Drop() — DropItemRemoteFunction:InvokeServer(Food, CF, Vector3.zero)
local function Drop(Food, CF)
    local HoldPart = Food:FindFirstChild("HoldPart")
    if not HoldPart then return end
    local RigidConstraint = HoldPart:FindFirstChild("RigidConstraint")
    if not RigidConstraint then return end
    local LeftGrip = Character
        and Character:FindFirstChild("Left Arm")
        and Character["Left Arm"]:FindFirstChild("LeftGripAttachment")
    if RigidConstraint.Attachment1 == LeftGrip then
        local DropFunction = HoldPart:FindFirstChild("DropItemRemoteFunction")
        if DropFunction then
            task.spawn(function()
                DropFunction:InvokeServer(Food, CF or CFrame.new(), Vector3.zero)
            end)
        end
    end
end

-- Grab() — SetNetworkOwner fallback (message(3).txt + Cosmic pattern)
-- SetNetworkOwner:FireServer(Target, CFrame.new(HRP.Position, Target.Position))
local function GrabNetworkOwner(palette)
    local hrp  = GetHRP()
    local prim = palette.PrimaryPart or palette:FindFirstChildWhichIsA("BasePart")
    if not prim or not hrp then return end
    pcall(function()
        SetNetworkOwner:FireServer(prim, CFrame.new(hrp.Position, prim.Position))
    end)
end

-- Spawn() — message(3).txt pattern with VerbalHub ToyNumber gate
local function SpawnOnePalette(spawnCF)
    local folder = GetToyFolder()
    if not folder then return nil end

    local toyNumObj   = folder:FindFirstChild("ToyNumber")
    local expectedNum = toyNumObj and toyNumObj.Value

    local result = nil
    local done   = false

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

    -- message(3).txt: NewCFrame = CF + CF.LookVector * -20
    local hrp   = GetHRP()
    local base  = spawnCF or (hrp and hrp.CFrame or CFrame.new())
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
--   GRID OFFSET  —  5×4 deck layout
-- ============================================================

local function GridOffset(i)
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local x   = (col - (COLS - 1) / 2) * SPACING
    local z   = (row - (ROWS - 1) / 2) * SPACING
    local y   = -3 + boatHeight
    return CFrame.new(x, y, z)
end

-- ============================================================
--   WELD PHASE
-- ============================================================

local function WeldFleet()
    local masterIdx = math.min(MASTER_INDEX, #Fleet)
    MasterPalette   = Fleet[masterIdx]

    if not MasterPalette or not MasterPalette.PrimaryPart then
        Notify("ERROR: Master palette has no PrimaryPart.")
        return false
    end

    local masterPart = MasterPalette.PrimaryPart
    Notify("Welding fleet to master palette #" .. masterIdx .. "…")

    for i, palette in ipairs(Fleet) do
        if i == masterIdx then continue end
        if not palette or not palette.Parent then continue end

        local slavePart = palette.PrimaryPart
                       or palette:FindFirstChildWhichIsA("BasePart")
        if not slavePart then continue end

        -- Part0 = master, Part1 = slave; parented to master model
        local weld   = Instance.new("WeldConstraint")
        weld.Part0   = masterPart
        weld.Part1   = slavePart
        weld.Parent  = MasterPalette

        -- Unanchor slaves — weld holds them relative to master
        for _, p in ipairs(palette:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored   = false
                p.CanCollide = false
            end
        end
    end

    -- Master stays anchored; Heartbeat drives it
    for _, p in ipairs(MasterPalette:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Anchored   = true
            p.CanCollide = false
        end
    end

    Notify("Weld complete.")
    return true
end

-- ============================================================
--   BOAT DRIVE  —  Heartbeat, master palette only
-- ============================================================

local function StartBoatDrive()
    if heartbeatConn then heartbeatConn:Disconnect() end
    if not MasterPalette or not MasterPalette.PrimaryPart then
        Notify("No master palette — build the fleet first.")
        return
    end

    local masterPart = MasterPalette.PrimaryPart

    heartbeatConn = RunService.Heartbeat:Connect(function()
        local hrp = GetHRP()
        if not hrp or not masterPart or not masterPart.Parent then return end

        -- Target position: offset below HRP
        local targetCF = hrp.CFrame * CFrame.new(0, -3 + boatHeight, 0)

        -- Smooth lerp — welds instantly carry the rest of the fleet
        masterPart.CFrame = masterPart.CFrame:Lerp(targetCF, 0.25)
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
--   BUILD FLEET  —  main entry point
-- ============================================================

local function BuildFleet()
    if isBuilding then Notify("Already building — wait.") return end

    local hrp = GetHRP()
    if not hrp then Notify("ERROR: No character.") return end

    StopBoatDrive()
    boatActive = false

    -- Destroy old fleet
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
    Notify("Building fleet of " .. FLEET_SIZE .. " palettes…")

    -- ── Per-palette: Spawn → Hold → NetworkOwner → Anchor ─────
    for i = 1, FLEET_SIZE do
        Notify(i .. "/" .. FLEET_SIZE .. "…")

        local offset   = GridOffset(i)
        local targetCF = hrp.CFrame * offset
        local palette  = SpawnOnePalette(targetCF)

        if not palette then
            Notify("✘ Slot " .. i .. " timed out.")
            table.insert(Fleet, false)
            task.wait(0.1)
            continue
        end

        -- STEP 3: Hold — server registers us as controller
        Hold(palette)
        task.wait(0.08)

        -- SetNetworkOwner fallback
        GrabNetworkOwner(palette)
        task.wait(0.05)

        -- STEP 4: Move to grid slot and anchor
        if palette.PrimaryPart then
            palette:SetPrimaryPartCFrame(targetCF)
        else
            for _, p in ipairs(palette:GetDescendants()) do
                if p:IsA("BasePart") then p.CFrame = targetCF end
            end
        end

        for _, p in ipairs(palette:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored   = true
                p.CanCollide = false
            end
        end

        table.insert(Fleet, palette)
        Notify("✔ Palette " .. i .. " anchored.")
        task.wait(0.12)
    end

    -- Strip false placeholders
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

    -- ── Weld phase ────────────────────────────────────────────
    local ok = WeldFleet()
    if not ok then isBuilding = false return end

    Notify("Fleet ready! " .. #Fleet .. " palettes. Enable Boat Drive.")
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

-- ── Main Tab ──────────────────────────────────────────────────
local BuildBox = Tabs.Main:AddLeftGroupbox("Fleet Builder")

BuildBox:AddLabel("Spawn → Hold → Anchor → Weld → Drive")
BuildBox:AddDivider()

BuildBox:AddButton({
    Text    = "▶  Build Welded Fleet",
    Func    = function() task.spawn(BuildFleet) end,
    Tooltip = "Spawns " .. FLEET_SIZE .. " palettes then welds all to palette #" .. MASTER_INDEX,
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
    Text = "Fleet Count",
    Func = function()
        local master = MasterPalette ~= nil and "YES" or "NO"
        Notify("Fleet: " .. #Fleet .. " palettes | Master welded: " .. master)
    end,
})

-- ── Drive Tab ─────────────────────────────────────────────────
local DriveBox = Tabs.Drive:AddLeftGroupbox("Boat Drive")

DriveBox:AddLabel("Master palette lerps to HRP. Welds carry everything else.")
DriveBox:AddDivider()

DriveBox:AddToggle("BoatDriveToggle", {
    Text    = "Activate Boat Drive",
    Default = false,
    Tooltip = "Heartbeat lerps only the master palette — welds do the rest",
    Callback = function(val)
        boatActive = val
        if val then
            StartBoatDrive()
        else
            StopBoatDrive()
        end
    end,
})

DriveBox:AddDivider()

DriveBox:AddSlider("BoatHeightSlider", {
    Text     = "Boat Height",
    Default  = 0,
    Min      = -10,
    Max      = 10,
    Rounding = 1,
    Tooltip  = "Raise or lower the deck (updates live if Drive is on)",
    Callback = function(val)
        boatHeight = val
        Notify("Height: " .. val)
    end,
})

local PhysicsBox = Tabs.Drive:AddRightGroupbox("Physics Tools")

PhysicsBox:AddButton({
    Text    = "Re-apply Noclip",
    Tooltip = "Force CanCollide=false on every fleet part",
    Func    = function()
        for _, p in ipairs(Fleet) do
            if p and p.Parent then
                for _, part in ipairs(p:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
        Notify("Noclip re-applied to " .. #Fleet .. " palettes.")
    end,
})

PhysicsBox:AddButton({
    Text    = "Re-weld Fleet",
    Tooltip = "Strips old WeldConstraints and re-creates them",
    Func    = function()
        if #Fleet == 0 then Notify("No fleet to re-weld.") return end
        if MasterPalette then
            for _, w in ipairs(MasterPalette:GetDescendants()) do
                if w:IsA("WeldConstraint") then w:Destroy() end
            end
        end
        WeldFleet()
    end,
})

-- ── Settings Tab ──────────────────────────────────────────────
local SetBox = Tabs.Settings:AddLeftGroupbox("Menu")
SetBox:AddButton("Unload", function() Library:Unload() end)
SetBox:AddLabel("Toggle Keybind"):AddKeyPicker("MenuBind", {
    Default = "End",
    NoUI    = true,
    Text    = "Menu bind",
})
Library.ToggleKeybind = Library.Options.MenuBind

Notify("Palette Boat loaded — hit Build Welded Fleet to start!")
