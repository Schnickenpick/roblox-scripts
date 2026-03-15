--[[
██████╗  █████╗ ██╗     ██╗     ███████╗████████╗    ██╗    ██╗███████╗██╗     ██████╗ ███████╗██████╗
██╔══██╗██╔══██╗██║     ██║     ██╔════╝╚══██╔══╝    ██║    ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗
██████╔╝███████║██║     ██║     █████╗     ██║       ██║ █╗ ██║█████╗  ██║     ██║  ██║█████╗  ██████╔╝
██╔═══╝ ██╔══██║██║     ██║     ██╔══╝     ██║       ██║███╗██║██╔══╝  ██║     ██║  ██║██╔══╝  ██╔══██╗
██║     ██║  ██║███████╗███████╗███████╗   ██║       ╚███╔███╔╝███████╗███████╗██████╔╝███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝        ╚══╝╚══╝ ╚══════╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
  Pallet Welder v3 | Multi-Part CFrame Weld | Obsidian UI
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
    Title            = "Pallet Welder v3",
    Footer           = "multi-part cframe weld • obsidian",
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

local Left  = Tabs.Main:AddLeftGroupbox("Build",    "box")
local Right = Tabs.Main:AddRightGroupbox("Status",  "info")

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

-- Zero out all velocity on character parts so we don't fly off after teleporting
local function killCharVelocity()
    local char = LP.Character
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.AssemblyLinearVelocity = Vector3.zero
            obj.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

-- Disable/restore CanCollide on all character parts
local function setCharCollision(enabled)
    local char = LP.Character
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.CanCollide = enabled
        end
    end
end

-- Claim network ownership: tp near if out of range, grab+release + SetNetworkOwner
local CLAIM_RANGE = 7

local function claimOwnership(part)
    if not part then return false end
    local root = getRoot()
    if not root then return false end

    local dist = (root.Position - part.Position).Magnitude
    local origCF = nil

    -- Teleport near if out of range
    if dist > CLAIM_RANGE then
        origCF = root.CFrame
        setCharCollision(false)
        killCharVelocity()
        root.CFrame = part.CFrame * CFrame.new(0, 3, 0)
        killCharVelocity()
        task.wait(0.1)
    end

    -- Grab + release to establish ownership
    if Remotes.CreateGrabLine then
        Remotes.CreateGrabLine:FireServer(part, part.CFrame)
        task.wait(0.15)
        if Remotes.DestroyGrabLine then
            Remotes.DestroyGrabLine:FireServer(part)
        end
        task.wait(0.05)
    end

    -- Also fire SetNetworkOwner directly
    if Remotes.SetNetworkOwner then
        Remotes.SetNetworkOwner:FireServer(part, part.CFrame)
    end
    task.wait(0.05)

    -- Teleport back, kill velocity, restore collision
    if origCF then
        local r = getRoot()
        if r then
            r.CFrame = origCF
        end
        killCharVelocity()
        task.wait(0.05)
        setCharCollision(true)
        killCharVelocity()
    end

    return true
end

-- Spawn a pallet at the given CFrame, returns (BasePart, rawToyEntry)
-- 'excludeSet' is an optional table of raw entries to skip { [rawEntry] = true }
local function spawnPallet(cf, excludeSet)
    if not Remotes.SpawnToy then
        Notify("Error", "SpawnToy remote not ready!", 4)
        return nil, nil
    end

    Remotes.SpawnToy:InvokeServer("PalletLightBrown", cf, Vector3.new(0, 0, 0))
    task.wait(0.3)

    local toyFolder = getToyFolder()
    if not toyFolder then return nil, nil end

    -- Find the most recently added PalletLightBrown, skipping excluded entries
    local found = nil
    for _, child in ipairs(toyFolder:GetChildren()) do
        if child.Name == "PalletLightBrown" then
            if not excludeSet or not excludeSet[child] then
                found = child
            end
        end
    end

    if not found then return nil, nil end

    if found:IsA("BasePart") then
        return found, found
    elseif found:IsA("Model") then
        -- Prefer the "Main" part for grab/CFrame reliability
        local bp = found:FindFirstChild("Main")
            or found.PrimaryPart
            or found:FindFirstChildWhichIsA("BasePart")
        return bp, found
    end
    return nil, nil
end

-- ============================================================
-- [[ 6. STATE ]]
-- ============================================================

-- Root part (the one you grab and move — everything follows it)
local RootPart    = nil  -- BasePart
local RootPartRaw = nil  -- raw toy folder entry

-- Child parts array. Each entry:
-- { part = BasePart, raw = rawToyEntry, offset = CFrame }
-- offset is set when you "Lock" the part (snapshot relative to RootPart)
local Children = {}

-- The part that was just spawned but not yet locked
local PendingPart    = nil
local PendingPartRaw = nil

-- Weld loop state
local weldActive = false
local weldConn   = nil

-- Build the exclude set from all known raw entries (root + children + pending)
local function buildExcludeSet()
    local set = {}
    if RootPartRaw then set[RootPartRaw] = true end
    for _, child in ipairs(Children) do
        if child.raw then set[child.raw] = true end
    end
    if PendingPartRaw then set[PendingPartRaw] = true end
    return set
end

-- ============================================================
-- [[ 7. STATUS LABELS ]]
-- ============================================================

local StatusLabel   = Right:AddLabel("Idle")
local RootLabel     = Right:AddLabel("Root: none")
local ChildrenLabel = Right:AddLabel("Children: 0")
local PendingLabel  = Right:AddLabel("Pending: none")
local WeldLabel     = Right:AddLabel("Weld: OFF")

local function updateLabels()
    if RootPart and RootPart.Parent then
        RootLabel:SetText("Root: STORED")
    elseif RootPart then
        RootLabel:SetText("Root: DESTROYED!")
    else
        RootLabel:SetText("Root: none")
    end

    local alive = 0
    for _, child in ipairs(Children) do
        if child.part and child.part.Parent then
            alive += 1
        end
    end
    ChildrenLabel:SetText("Children: " .. alive .. " / " .. #Children .. (weldActive and " (welded)" or ""))

    if PendingPart and PendingPart.Parent then
        PendingLabel:SetText("Pending: ready to lock")
    elseif PendingPart then
        PendingLabel:SetText("Pending: DESTROYED!")
    else
        PendingLabel:SetText("Pending: none")
    end

    WeldLabel:SetText(weldActive and "Weld: ACTIVE" or "Weld: OFF")
end

Right:AddDivider()
Right:AddLabel({
    Text     = "1. Spawn Root\n2. Spawn Part\n3. Position it where you want\n4. Add to Build (locks offset\n   + claims netowner)\n5. Repeat 2-4\n6. Toggle CFrame Weld",
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

Left:AddDivider()

-- ============================================================
-- [[ 9. SPAWN ROOT ]]
-- ============================================================

Left:AddButton({
    Text    = "Spawn Root Part",
    Tooltip = "Spawns the root pallet — this is the part you grab to move everything",
    Func    = function()
        task.spawn(function()
            local root = getRoot()
            if not root then Notify("Error", "No character!", 3) return end

            StatusLabel:SetText("Spawning Root...")
            local cf = root.CFrame * CFrame.new(0, 0, -Options.SpawnDist.Value)
            local part, raw = spawnPallet(cf, buildExcludeSet())

            if not part then
                Notify("Error", "Root pallet failed to spawn!", 4)
                StatusLabel:SetText("Failed (Root)")
                return
            end

            RootPart = part
            RootPartRaw = raw
            updateLabels()
            Notify("Welder", "Root spawned! Claiming netowner...", 2)

            -- Auto-claim netownership on root
            StatusLabel:SetText("Claiming Root...")
            claimOwnership(RootPart)

            StatusLabel:SetText("Idle")
            updateLabels()
            Notify("Welder", "Root part spawned & owned!", 2)
        end)
    end,
})

Left:AddDivider()

-- ============================================================
-- [[ 10. SPAWN + LOCK CHILD PARTS ]]
-- ============================================================

Left:AddButton({
    Text    = "Spawn Part",
    Tooltip = "Spawns a new pallet in front of you — grab it, position it, then Lock",
    Func    = function()
        task.spawn(function()
            local root = getRoot()
            if not root then Notify("Error", "No character!", 3) return end

            if PendingPart and PendingPart.Parent then
                Notify("Warning", "You have an unlocked part! Lock or discard it first.", 3)
                return
            end

            StatusLabel:SetText("Spawning part...")
            local cf = root.CFrame * CFrame.new(0, 0, -Options.SpawnDist.Value)
            local part, raw = spawnPallet(cf, buildExcludeSet())

            if not part then
                Notify("Error", "Part failed to spawn!", 4)
                StatusLabel:SetText("Failed (spawn)")
                return
            end

            PendingPart = part
            PendingPartRaw = raw
            StatusLabel:SetText("Idle")
            updateLabels()
            Notify("Welder", "Part spawned! Position it, then click Lock.", 3)
        end)
    end,
})

Left:AddButton({
    Text    = "Add to Build",
    Tooltip = "Locks the pending part's offset relative to Root + claims network ownership on it",
    Func    = function()
        task.spawn(function()
            if not RootPart or not RootPart.Parent then
                Notify("Error", "No Root part! Spawn one first.", 3)
                return
            end
            if not PendingPart or not PendingPart.Parent then
                Notify("Error", "No pending part! Spawn one first.", 3)
                return
            end

            -- Snapshot offset: Root-relative CFrame of this part right now
            local offset = RootPart.CFrame:Inverse() * PendingPart.CFrame
            local part = PendingPart
            local raw  = PendingPartRaw

            table.insert(Children, {
                part   = part,
                raw    = raw,
                offset = offset,
            })

            local idx = #Children
            PendingPart = nil
            PendingPartRaw = nil

            updateLabels()
            Notify("Welder", "Part #" .. idx .. " locked! Claiming netowner...", 2)

            -- Claim network ownership on the newly added part
            StatusLabel:SetText("Claiming #" .. idx .. "...")
            claimOwnership(part)

            StatusLabel:SetText("Idle")
            updateLabels()
            Notify("Welder", "Part #" .. idx .. " added & owned!", 2)
        end)
    end,
})

Left:AddButton({
    Text    = "Remove Last Part",
    Tooltip = "Removes the last locked child from the build (does not destroy the pallet)",
    Func    = function()
        if #Children == 0 then
            Notify("Info", "No children to remove.", 2)
            return
        end
        table.remove(Children)
        updateLabels()
        Notify("Welder", "Removed child #" .. (#Children + 1) .. " from build.", 3)
    end,
})

Left:AddDivider()

-- ============================================================
-- [[ 12. CFRAME FAKE-WELD (MULTI-PART) ]]
-- ============================================================

local function stopWeld()
    weldActive = false
    if weldConn then
        weldConn:Disconnect()
        weldConn = nil
    end
    updateLabels()
end

local function startWeld()
    if not RootPart or not RootPart.Parent then
        Notify("Error", "Root part missing!", 3)
        return
    end
    if #Children == 0 then
        Notify("Error", "No child parts! Spawn and lock some first.", 3)
        return
    end
    if RootPart.Anchored then
        Notify("Error", "Root is Anchored — can't CFrame weld!", 3)
        return
    end

    -- Validate children
    local valid = 0
    for _, child in ipairs(Children) do
        if child.part and child.part.Parent and not child.part.Anchored then
            valid += 1
        end
    end
    if valid == 0 then
        Notify("Error", "All children are destroyed or anchored!", 3)
        return
    end

    weldActive = true

    weldConn = RunService.Heartbeat:Connect(function()
        if not weldActive then
            stopWeld()
            return
        end

        -- If root is gone, stop everything
        if not RootPart or not RootPart.Parent then
            Notify("Welder", "Root destroyed — weld stopped.", 3)
            stopWeld()
            if Toggles.CFrameWeld then
                Toggles.CFrameWeld:SetValue(false)
            end
            return
        end

        local rootCF = RootPart.CFrame

        for _, child in ipairs(Children) do
            if child.part and child.part.Parent and not child.part.Anchored then
                -- Force child to follow root using stored offset
                child.part.CFrame = rootCF * child.offset

                -- Anti-physics-sleep: tiny velocity so server doesn't freeze the part
                child.part.AssemblyLinearVelocity = Vector3.new(0, 0.01, 0)
                child.part.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)

    updateLabels()
    Notify("Welder", "CFrame weld active! " .. valid .. " children following Root.", 4)
end

Left:AddToggle("CFrameWeld", {
    Text    = "CFrame Weld",
    Default = false,
    Tooltip = "All locked children follow Root every frame via CFrame offset",
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
-- [[ 13. UTILITY ]]
-- ============================================================

Left:AddButton({
    Text    = "Reclaim All NetOwner",
    Tooltip = "Re-claims netownership on Root + all children (use if ownership was lost)",
    Func    = function()
        task.spawn(function()
            if not RootPart or not RootPart.Parent then
                Notify("Error", "No Root part!", 3)
                return
            end

            StatusLabel:SetText("Reclaiming Root...")
            claimOwnership(RootPart)

            for i, child in ipairs(Children) do
                if child.part and child.part.Parent then
                    StatusLabel:SetText("Reclaiming #" .. i .. " / " .. #Children .. "...")
                    claimOwnership(child.part)
                end
            end

            StatusLabel:SetText("Idle")
            updateLabels()
            Notify("Welder", "Reclaimed all " .. (#Children + 1) .. " parts!", 3)
        end)
    end,
})

Left:AddButton({
    Text    = "Re-snapshot All Offsets",
    Tooltip = "Recaptures every child's offset from their current position relative to Root",
    Func    = function()
        if not RootPart or not RootPart.Parent then
            Notify("Error", "No Root part!", 3)
            return
        end
        local count = 0
        for _, child in ipairs(Children) do
            if child.part and child.part.Parent then
                child.offset = RootPart.CFrame:Inverse() * child.part.CFrame
                count += 1
            end
        end
        Notify("Welder", "Re-snapshotted " .. count .. " offsets!", 2)
    end,
})

Left:AddButton({
    Text    = "Reset All",
    Tooltip = "Stops weld, clears root + all children, resets everything",
    Func    = function()
        stopWeld()
        if Toggles.CFrameWeld then
            Toggles.CFrameWeld:SetValue(false)
        end
        RootPart = nil
        RootPartRaw = nil
        Children = {}
        PendingPart = nil
        PendingPartRaw = nil
        StatusLabel:SetText("Idle")
        updateLabels()
        Notify("Welder", "Everything reset.", 2)
    end,
})

-- ============================================================
-- [[ 14. UI SETTINGS (ThemeManager + SaveManager) ]]
-- ============================================================

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PalletWelder")
ThemeManager:ApplyToTab(Tabs.UISettings)
ThemeManager:ApplyTheme("Catppuccin")

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("PalletWelder")
SaveManager:BuildConfigSection(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()
