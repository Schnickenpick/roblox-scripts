--[[
██████╗  █████╗ ██╗     ██╗     ███████╗████████╗    ██╗    ██╗███████╗██╗     ██████╗ ███████╗██████╗
██╔══██╗██╔══██╗██║     ██║     ██╔════╝╚══██╔══╝    ██║    ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗
██████╔╝███████║██║     ██║     █████╗     ██║       ██║ █╗ ██║█████╗  ██║     ██║  ██║█████╗  ██████╔╝
██╔═══╝ ██╔══██║██║     ██║     ██╔══╝     ██║       ██║███╗██║██╔══╝  ██║     ██║  ██║██╔══╝  ██╔══██╗
██║     ██║  ██║███████╗███████╗███████╗   ██║       ╚███╔███╔╝███████╗███████╗██████╔╝███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝        ╚══╝╚══╝ ╚══════╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
  Pallet Welder | Obsidian UI
--]]

-- ============================================================
-- [[ 1. SERVICES ]]
-- ============================================================

local LP         = game:GetService("Players").LocalPlayer
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Workspace  = workspace
local Camera     = Workspace.CurrentCamera

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
    Title            = "Pallet Welder",
    Footer           = "serverside • obsidian",
    NotifySide       = "Right",
    AutoShow         = true,
    Center           = true,
    ToggleKeybind    = Enum.KeyCode.RightShift,
})

local function Notify(title, desc, t)
    Library:Notify({ Title = title, Description = desc or "", Time = t or 3 })
end

-- ============================================================
-- [[ 3. TABS & LAYOUT ]]
-- ============================================================

local Tabs = {
    Main       = Window:AddTab("Welder",     "layers"),
    UISettings = Window:AddTab("UI",         "settings"),
}

local Left  = Tabs.Main:AddLeftGroupbox("Spawn & Weld",   "box")
local Right = Tabs.Main:AddRightGroupbox("Status",         "info")

-- ============================================================
-- [[ 4. REMOTES ]]
-- ============================================================

local Remotes = {}
task.spawn(function()
    local GE = RS:WaitForChild("GrabEvents", 10)
    if GE then
        Remotes.CreateGrabLine   = GE:FindFirstChild("CreateGrabLine")
        Remotes.DestroyGrabLine  = GE:FindFirstChild("DestroyGrabLine")
        Remotes.SetNetworkOwner  = GE:FindFirstChild("SetNetworkOwner")
    end
    local MT = RS:WaitForChild("MenuToys", 10)
    if MT then
        Remotes.SpawnToy   = MT:FindFirstChild("SpawnToyRemoteFunction")
        Remotes.DestroyToy = MT:FindFirstChild("DestroyToy")
    end
end)

-- ============================================================
-- [[ 5. HELPERS ]]
-- ============================================================

local function getRoot()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Find a toy by name in nil instances
local function getNilToy(name)
    for _, obj in getnilinstances() do
        if obj.Name == name and obj:IsA("BasePart") then
            return obj
        end
    end
end

-- Teleport HRP to just above a part so range checks pass, returns original CFrame
local function tpOnto(part)
    local root = getRoot()
    if not root then return nil end
    local orig = root.CFrame
    root.CFrame = part.CFrame * CFrame.new(0, 3, 0)
    task.wait(0.1)
    return orig
end

-- Claim ownership: teleport onto part, fire both remotes, teleport back
local function claimOwnership(part, origCF)
    if not part then return end
    -- Fire grab remote while standing right next to it — passes range check
    if Remotes.CreateGrabLine then
        Remotes.CreateGrabLine:FireServer(part, part.CFrame)
        task.wait(0.1)
        Remotes.DestroyGrabLine:FireServer(part)
    end
    -- Belt-and-suspenders: also fire SetNetworkOwner from point-blank range
    if Remotes.SetNetworkOwner then
        Remotes.SetNetworkOwner:FireServer(part, part.CFrame)
    end
    task.wait(0.05)
    -- Teleport back to original position if provided
    if origCF then
        local root = getRoot()
        if root then root.CFrame = origCF end
        task.wait(0.05)
    end
end

-- ============================================================
-- [[ 6. STATUS LABELS ]]
-- ============================================================

local StatusLabel   = Right:AddLabel("Idle")
local Pallet1Label  = Right:AddLabel("Pallet A: —")
local Pallet2Label  = Right:AddLabel("Pallet B: —")
local WeldLabel     = Right:AddLabel("Weld: none")

Right:AddDivider()
Right:AddLabel({
    Text     = "1. Spawn both pallets\n2. Click Weld!\nNetOwnership is claimed\nautomatically.",
    DoesWrap = true,
})

-- ============================================================
-- [[ 7. SETTINGS ]]
-- ============================================================

Left:AddSlider("FrontDist", {
    Text    = "Front Distance (studs)",
    Default = 5,
    Min     = 2,
    Max     = 20,
    Rounding = 0,
    Suffix  = " st",
})

Left:AddSlider("UpDist", {
    Text    = "Stack Height (studs)",
    Default = 4,
    Min     = 1,
    Max     = 15,
    Rounding = 0,
    Suffix  = " st",
})

Left:AddDivider()

-- ============================================================
-- [[ 8. STATE ]]
-- ============================================================

local spawnedPallets = {}   -- { part, model } entries

-- ============================================================
-- [[ 9. SPAWN + WELD LOGIC ]]
-- ============================================================

-- Spawns one pallet at the given world CFrame, returns the BasePart
local function spawnPallet(cf)
    if not Remotes.SpawnToy then
        Notify("Error", "SpawnToy remote not ready yet!", 4)
        return nil
    end

    -- SpawnToyRemoteFunction:InvokeServer(toyName, CFrame, Vector3)
    -- Vector3 arg is rotation hint; zero is fine for a fresh spawn
    local result = Remotes.SpawnToy:InvokeServer(
        "PalletLightBrown",
        cf,
        Vector3.new(0, 0, 0)
    )

    -- Give the server a moment to replicate the toy into workspace
    task.wait(0.25)

    -- Find the pallet BasePart — it lands in a player-named folder in workspace
    -- e.g. workspace.[username]SpawnedInToys.PalletLightBrown
    local toyFolder = Workspace:FindFirstChild(LP.Name .. "SpawnedInToys")
    if not toyFolder then
        -- fallback: search all nil instances
        local nil_part = getNilToy("PalletLightBrown")
        return nil_part
    end

    -- Get the most recently added child named PalletLightBrown
    local found = nil
    for _, child in ipairs(toyFolder:GetChildren()) do
        if child.Name == "PalletLightBrown" then
            found = child
        end
    end

    -- If it's a model, get its primary part or first BasePart
    if found then
        if found:IsA("BasePart") then
            return found
        elseif found:IsA("Model") then
            return found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart")
        end
    end

    return nil
end

-- Main weld function — spawns both pallets and welds them
local function doWeldPallets()
    local root = getRoot()
    if not root then
        Notify("Error", "No character!", 3)
        return
    end

    local frontDist = Options.FrontDist.Value
    local upDist    = Options.UpDist.Value

    StatusLabel:SetText("Spawning Pallet A...")
    Pallet1Label:SetText("Pallet A: spawning...")

    -- CFrame 'frontDist' studs in front of player (no Y offset = ground level of HRP)
    local cf1 = root.CFrame * CFrame.new(0, 0, -frontDist)
    local partA = spawnPallet(cf1)

    if not partA then
        Notify("Error", "Pallet A failed to spawn!", 4)
        StatusLabel:SetText("Failed (Pallet A)")
        Pallet1Label:SetText("Pallet A: FAILED")
        return
    end

    Pallet1Label:SetText("Pallet A: OK ✓")
    Notify("Welder", "Pallet A spawned!", 2)

    -- ---- Claim ownership of Pallet A ----
    -- Teleport onto it first so the range check on CreateGrabLine/SetNetworkOwner passes
    StatusLabel:SetText("Claiming Pallet A ownership...")
    local origCF = tpOnto(partA)
    claimOwnership(partA, nil) -- stay there for now, teleport back after B

    -- ---- Spawn Pallet B above Pallet A ----
    StatusLabel:SetText("Spawning Pallet B...")
    Pallet2Label:SetText("Pallet B: spawning...")

    local cf2 = partA.CFrame * CFrame.new(0, upDist, 0)
    local partB = spawnPallet(cf2)

    if not partB then
        -- Teleport back before returning
        local root = getRoot()
        if root and origCF then root.CFrame = origCF end
        Notify("Error", "Pallet B failed to spawn!", 4)
        StatusLabel:SetText("Failed (Pallet B)")
        Pallet2Label:SetText("Pallet B: FAILED")
        return
    end

    Pallet2Label:SetText("Pallet B: OK ✓")
    Notify("Welder", "Pallet B spawned!", 2)

    -- ---- Claim ownership of Pallet B ----
    -- Teleport onto B (it's above A, still close)
    StatusLabel:SetText("Claiming Pallet B ownership...")
    tpOnto(partB)
    claimOwnership(partB, nil)

    -- ---- Weld them together (serverside) ----
    -- We own both parts now (grabbed point-blank). Create WeldConstraint while
    -- standing right next to partA so the engine replicates it serverside.
    StatusLabel:SetText("Welding...")
    WeldLabel:SetText("Weld: working...")

    tpOnto(partA)

    -- Re-grab partA to confirm ownership at weld time
    if Remotes.CreateGrabLine then
        Remotes.CreateGrabLine:FireServer(partA, partA.CFrame)
        task.wait(0.1)
    end

    -- Create WeldConstraint while we actively own partA
    local weld = Instance.new("WeldConstraint")
    weld.Part0   = partA
    weld.Part1   = partB
    weld.Enabled = true
    weld.Parent  = partA  -- parented to owned part → server replicates it

    task.wait(0.1)

    if Remotes.DestroyGrabLine then
        Remotes.DestroyGrabLine:FireServer(partA)
    end

    -- Teleport back to where player was originally
    local root = getRoot()
    if root and origCF then root.CFrame = origCF end

    -- Done!
    StatusLabel:SetText("Welded! ✓")
    WeldLabel:SetText("Weld: ACTIVE ✓")
    Notify("Welder", "Pallets welded together! Serverside ✓", 5)

    -- Store refs in case we want to clean up later
    table.insert(spawnedPallets, { a = partA, b = partB, weld = weld })
end

-- ============================================================
-- [[ 10. BUTTONS ]]
-- ============================================================

Left:AddButton({
    Text    = "Spawn & Weld Pallets",
    Tooltip = "Spawns 2 pallets in front of you and welds them together serverside",
    Func    = function()
        task.spawn(doWeldPallets)
    end,
})

Left:AddDivider()

Left:AddButton({
    Text    = "Reset Status",
    Tooltip = "Clear the status labels",
    Func    = function()
        StatusLabel:SetText("Idle")
        Pallet1Label:SetText("Pallet A: —")
        Pallet2Label:SetText("Pallet B: —")
        WeldLabel:SetText("Weld: none")
        spawnedPallets = {}
    end,
})

-- ============================================================
-- [[ 11. UI SETTINGS (ThemeManager + SaveManager) ]]
-- ============================================================

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PalletWelder")
ThemeManager:ApplyToTab(Tabs.UISettings)
ThemeManager:ApplyTheme("Catppuccin")   -- cool default theme

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("PalletWelder")
SaveManager:BuildConfigSection(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()
