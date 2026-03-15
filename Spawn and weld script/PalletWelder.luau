--[[
██████╗  █████╗ ██╗     ██╗     ███████╗████████╗    ██╗    ██╗███████╗██╗     ██████╗ ███████╗██████╗
██╔══██╗██╔══██╗██║     ██║     ██╔════╝╚══██╔══╝    ██║    ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗
██████╔╝███████║██║     ██║     █████╗     ██║       ██║ █╗ ██║█████╗  ██║     ██║  ██║█████╗  ██████╔╝
██╔═══╝ ██╔══██║██║     ██║     ██╔══╝     ██║       ██║███╗██║██╔══╝  ██║     ██║  ██║██╔══╝  ██╔══██╗
██║     ██║  ██║███████╗███████╗███████╗   ██║       ╚███╔███╔╝███████╗███████╗██████╔╝███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝        ╚══╝╚══╝ ╚══════╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
  Pallet Welder v2 | CFrame Fake-Weld | Obsidian UI
--]]

-- ============================================================
-- [[ 1. SERVICES ]]
-- ============================================================

local LP         = game:GetService("Players").LocalPlayer
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
    Title            = "Pallet Welder v2",
    Footer           = "cframe weld • obsidian",
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

local Left  = Tabs.Main:AddLeftGroupbox("Spawn & Claim",  "box")
local Right = Tabs.Main:AddRightGroupbox("Status",        "info")

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

local function getToyFolder()
    return workspace:FindFirstChild(LP.Name .. "SpawnedInToys")
end

-- Teleport HRP next to a part so range checks pass, returns original CFrame
local function tpNear(part)
    local root = getRoot()
    if not root then return nil end
    local orig = root.CFrame
    root.CFrame = part.CFrame * CFrame.new(0, 3, 0)
    task.wait(0.1)
    return orig
end

-- Claim network ownership: tp near, grab+release + SetNetworkOwner, tp back
local function claimOwnership(part)
    if not part then return false end
    local root = getRoot()
    if not root then return false end

    local origCF = tpNear(part)

    if Remotes.CreateGrabLine then
        Remotes.CreateGrabLine:FireServer(part, part.CFrame)
        task.wait(0.1)
        if Remotes.DestroyGrabLine then
            Remotes.DestroyGrabLine:FireServer(part)
        end
    end
    if Remotes.SetNetworkOwner then
        Remotes.SetNetworkOwner:FireServer(part, part.CFrame)
    end
    task.wait(0.05)

    if origCF then
        local r = getRoot()
        if r then r.CFrame = origCF end
    end
    return true
end

-- Spawn a pallet at the given CFrame, returns the BasePart reference
-- 'exclude' is an optional part/model to skip (so we don't re-find StoredA when spawning B)
local function spawnPallet(cf, exclude)
    if not Remotes.SpawnToy then
        Notify("Error", "SpawnToy remote not ready!", 4)
        return nil
    end

    Remotes.SpawnToy:InvokeServer("PalletLightBrown", cf, Vector3.new(0, 0, 0))
    task.wait(0.3)

    local toyFolder = getToyFolder()
    if not toyFolder then return nil end

    -- Find the most recently added PalletLightBrown, skipping 'exclude'
    local found = nil
    for _, child in ipairs(toyFolder:GetChildren()) do
        if child.Name == "PalletLightBrown" and child ~= exclude then
            found = child
        end
    end

    if not found then return nil end

    if found:IsA("BasePart") then
        return found, found
    elseif found:IsA("Model") then
        local bp = found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart")
        return bp, found  -- BasePart for physics, raw entry for exclusion
    end
    return nil, nil
end

-- ============================================================
-- [[ 6. STATE ]]
-- ============================================================

local StoredA    = nil  -- BasePart reference for Pallet A (used for CFrame/grab)
local StoredARaw = nil  -- raw toy folder child for A (used for exclusion when spawning B)
local StoredB    = nil  -- BasePart reference for Pallet B

local weldActive   = false
local weldOffset   = nil   -- CFrame offset: PartA-relative position of PartB
local weldConn     = nil   -- RBXScriptConnection for the Heartbeat loop

-- ============================================================
-- [[ 7. STATUS LABELS ]]
-- ============================================================

local StatusLabel  = Right:AddLabel("Idle")
local PalletALabel = Right:AddLabel("Pallet A: none")
local PalletBLabel = Right:AddLabel("Pallet B: none")
local WeldLabel    = Right:AddLabel("Weld: OFF")

Right:AddDivider()
Right:AddLabel({
    Text     = "1. Spawn A (stores it)\n2. Spawn B (stores it)\n3. Claim NetOwner on both\n4. Toggle CFrame Weld\n\nA = the part you hold\nB = follows A via CFrame",
    DoesWrap = true,
})

-- ============================================================
-- [[ 8. SETTINGS ]]
-- ============================================================

Left:AddSlider("SpawnDist", {
    Text     = "Spawn Distance (studs)",
    Default  = 5,
    Min      = 2,
    Max      = 20,
    Rounding = 0,
    Suffix   = " st",
})

Left:AddSlider("StackHeight", {
    Text     = "B Height Above A (studs)",
    Default  = 4,
    Min      = 1,
    Max      = 15,
    Rounding = 0,
    Suffix   = " st",
})

Left:AddDivider()

-- ============================================================
-- [[ 9. SPAWN BUTTONS ]]
-- ============================================================

Left:AddButton({
    Text    = "Spawn Pallet A",
    Tooltip = "Spawns a pallet in front of you and stores it as Part A",
    Func    = function()
        task.spawn(function()
            local root = getRoot()
            if not root then Notify("Error", "No character!", 3) return end

            StatusLabel:SetText("Spawning A...")
            local cf = root.CFrame * CFrame.new(0, 0, -Options.SpawnDist.Value)
            local part, raw = spawnPallet(cf)

            if not part then
                Notify("Error", "Pallet A failed to spawn!", 4)
                StatusLabel:SetText("Failed (A)")
                PalletALabel:SetText("Pallet A: FAILED")
                return
            end

            StoredA = part
            StoredARaw = raw
            PalletALabel:SetText("Pallet A: STORED")
            StatusLabel:SetText("Idle")
            Notify("Welder", "Pallet A spawned & stored!", 2)
        end)
    end,
})

Left:AddButton({
    Text    = "Spawn Pallet B",
    Tooltip = "Spawns a pallet above A (or in front of you) and stores it as Part B",
    Func    = function()
        task.spawn(function()
            local root = getRoot()
            if not root then Notify("Error", "No character!", 3) return end

            StatusLabel:SetText("Spawning B...")

            local cf
            if StoredA and StoredA.Parent then
                -- Spawn above Pallet A
                cf = StoredA.CFrame * CFrame.new(0, Options.StackHeight.Value, 0)
            else
                -- Fallback: in front of player
                cf = root.CFrame * CFrame.new(0, 0, -Options.SpawnDist.Value)
            end

            local part = spawnPallet(cf, StoredARaw)

            if not part then
                Notify("Error", "Pallet B failed to spawn!", 4)
                StatusLabel:SetText("Failed (B)")
                PalletBLabel:SetText("Pallet B: FAILED")
                return
            end

            StoredB = part
            PalletBLabel:SetText("Pallet B: STORED")
            StatusLabel:SetText("Idle")
            Notify("Welder", "Pallet B spawned & stored!", 2)
        end)
    end,
})

Left:AddDivider()

-- ============================================================
-- [[ 10. CLAIM NETOWNERSHIP ]]
-- ============================================================

Left:AddButton({
    Text    = "Claim NetOwner (Both)",
    Tooltip = "Teleports to each pallet to grab+release and claim network ownership",
    Func    = function()
        task.spawn(function()
            if not StoredA or not StoredA.Parent then
                Notify("Error", "Pallet A not stored or destroyed!", 3)
                return
            end
            if not StoredB or not StoredB.Parent then
                Notify("Error", "Pallet B not stored or destroyed!", 3)
                return
            end

            StatusLabel:SetText("Claiming A...")
            local okA = claimOwnership(StoredA)
            if okA then
                PalletALabel:SetText("Pallet A: OWNED")
            end

            StatusLabel:SetText("Claiming B...")
            local okB = claimOwnership(StoredB)
            if okB then
                PalletBLabel:SetText("Pallet B: OWNED")
            end

            StatusLabel:SetText("Idle")
            if okA and okB then
                Notify("Welder", "NetOwnership claimed on both pallets!", 3)
            else
                Notify("Warning", "Some claims may have failed", 3)
            end
        end)
    end,
})

Left:AddDivider()

-- ============================================================
-- [[ 11. CFRAME FAKE-WELD ]]
-- ============================================================

-- Disconnect and clean up the weld loop
local function stopWeld()
    weldActive = false
    if weldConn then
        weldConn:Disconnect()
        weldConn = nil
    end
    weldOffset = nil
    WeldLabel:SetText("Weld: OFF")
end

-- Start the CFrame weld loop
local function startWeld()
    -- Validation
    if not StoredA or not StoredA.Parent then
        Notify("Error", "Pallet A missing! Spawn & claim first.", 3)
        return
    end
    if not StoredB or not StoredB.Parent then
        Notify("Error", "Pallet B missing! Spawn & claim first.", 3)
        return
    end
    if StoredA.Anchored then
        Notify("Error", "Pallet A is Anchored — cannot CFrame weld!", 3)
        return
    end
    if StoredB.Anchored then
        Notify("Error", "Pallet B is Anchored — cannot CFrame weld!", 3)
        return
    end

    -- Calculate the offset of B relative to A at this moment
    -- offset = A.CFrame:Inverse() * B.CFrame
    -- So later: B.CFrame = A.CFrame * offset
    weldOffset = StoredA.CFrame:Inverse() * StoredB.CFrame
    weldActive = true

    weldConn = RunService.Heartbeat:Connect(function()
        -- Stop if toggle turned off or parts destroyed
        if not weldActive then
            stopWeld()
            return
        end
        if not StoredA or not StoredA.Parent or not StoredB or not StoredB.Parent then
            Notify("Welder", "A pallet was destroyed — weld stopped.", 3)
            stopWeld()
            if Toggles.CFrameWeld then
                Toggles.CFrameWeld:SetValue(false)
            end
            return
        end

        -- Force PartB to follow PartA using the stored offset
        StoredB.CFrame = StoredA.CFrame * weldOffset

        -- Anti-physics-sleep: tiny velocity so the server doesn't put PartB to sleep
        -- This ensures our CFrame changes replicate to all clients
        StoredB.AssemblyLinearVelocity = Vector3.new(0, 0.01, 0)
        StoredB.AssemblyAngularVelocity = Vector3.zero
    end)

    WeldLabel:SetText("Weld: ACTIVE")
    Notify("Welder", "CFrame weld active! Move Pallet A — B follows.", 4)
end

Left:AddToggle("CFrameWeld", {
    Text    = "CFrame Weld (A → B)",
    Default = false,
    Tooltip = "B follows A every frame via CFrame offset + anti-sleep velocity",
    Callback = function(value)
        if value then
            startWeld()
        else
            stopWeld()
            StatusLabel:SetText("Idle")
            Notify("Welder", "CFrame weld stopped.", 2)
        end
    end,
})

Left:AddDivider()

-- ============================================================
-- [[ 12. UTILITY BUTTONS ]]
-- ============================================================

Left:AddButton({
    Text    = "Re-snapshot Offset",
    Tooltip = "Recalculates the A→B offset from current positions (while weld is active)",
    Func    = function()
        if not weldActive then
            Notify("Info", "Weld is not active.", 2)
            return
        end
        if StoredA and StoredA.Parent and StoredB and StoredB.Parent then
            weldOffset = StoredA.CFrame:Inverse() * StoredB.CFrame
            Notify("Welder", "Offset re-captured!", 2)
        end
    end,
})

Left:AddButton({
    Text    = "Reset All",
    Tooltip = "Stops weld, clears stored pallets, resets status",
    Func    = function()
        stopWeld()
        if Toggles.CFrameWeld then
            Toggles.CFrameWeld:SetValue(false)
        end
        StoredA = nil
        StoredARaw = nil
        StoredB = nil
        StatusLabel:SetText("Idle")
        PalletALabel:SetText("Pallet A: none")
        PalletBLabel:SetText("Pallet B: none")
        WeldLabel:SetText("Weld: OFF")
        Notify("Welder", "Everything reset.", 2)
    end,
})

-- ============================================================
-- [[ 13. UI SETTINGS (ThemeManager + SaveManager) ]]
-- ============================================================

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PalletWelder")
ThemeManager:ApplyToTab(Tabs.UISettings)
ThemeManager:ApplyTheme("Catppuccin")

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("PalletWelder")
SaveManager:BuildConfigSection(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()
