--[[
██████╗  █████╗ ██╗     ██╗     ███████╗████████╗    ██╗    ██╗███████╗██╗     ██████╗ ███████╗██████╗
██╔══██╗██╔══██╗██║     ██║     ██╔════╝╚══██╔══╝    ██║    ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗
██████╔╝███████║██║     ██║     █████╗     ██║       ██║ █╗ ██║█████╗  ██║     ██║  ██║█████╗  ██████╔╝
██╔═══╝ ██╔══██║██║     ██║     ██╔══╝     ██║       ██║███╗██║██╔══╝  ██║     ██║  ██║██╔══╝  ██╔══██╗
██║     ██║  ██║███████╗███████╗███████╗   ██║       ╚███╔███╔╝███████╗███████╗██████╔╝███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝        ╚══╝╚══╝ ╚══════╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
  Pallet Welder v4 | Multi-Part CFrame Weld | Obsidian UI
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
    Title            = "Pallet Welder v4",
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

-- Get the best BasePart from a toy entry (Model or BasePart)
-- Prefers "Main" child, then PrimaryPart, then any BasePart
local function getPartFromToy(toy)
    if toy:IsA("BasePart") then
        return toy
    elseif toy:IsA("Model") then
        return toy:FindFirstChild("Main")
            or toy.PrimaryPart
            or toy:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- Spawn a root pallet at the given CFrame, returns (BasePart, rawToyEntry)
local function spawnRootPallet(cf)
    if not Remotes.SpawnToy then
        Notify("Error", "SpawnToy remote not ready!", 4)
        return nil, nil
    end

    Remotes.SpawnToy:InvokeServer("PalletLightBrown", cf, Vector3.new(0, 0, 0))
    task.wait(0.3)

    local toyFolder = getToyFolder()
    if not toyFolder then return nil, nil end

    -- Find the most recently added PalletLightBrown
    local found = nil
    for _, child in ipairs(toyFolder:GetChildren()) do
        if child.Name == "PalletLightBrown" then
            found = child
        end
    end

    if not found then return nil, nil end
    return getPartFromToy(found), found
end

-- ============================================================
-- [[ 6. STATE ]]
-- ============================================================

-- Root part (the one you grab and move — everything follows it)
local RootPart    = nil  -- BasePart (the "Main" or first BasePart)
local RootPartRaw = nil  -- raw toy folder entry (Model or BasePart)

-- Child parts array. Each entry:
-- { part = BasePart, raw = rawToyEntry, offset = CFrame, name = string }
local Children = {}

-- Weld loop state
local weldActive = false
local weldConn   = nil

-- ============================================================
-- [[ 7. STATUS LABELS ]]
-- ============================================================

local StatusLabel   = Right:AddLabel("Idle")
local RootLabel     = Right:AddLabel("Root: none")
local ChildrenLabel = Right:AddLabel("Children: 0")
local WeldLabel     = Right:AddLabel("Weld: OFF")

local function updateLabels()
    if RootPart and RootPart.Parent then
        RootLabel:SetText("Root: " .. (RootPartRaw and RootPartRaw.Name or "OK"))
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

    WeldLabel:SetText(weldActive and "Weld: ACTIVE" or "Weld: OFF")
end

Right:AddDivider()
Right:AddLabel({
    Text     = "1. Spawn Root (pallet)\n2. Spawn & position toys\n   from in-game menu\n3. Grab each toy to get\n   network ownership\n4. Add All from Folder\n5. Toggle CFrame Weld\n6. Grab Root to move all!",
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
    Tooltip = "Spawns a pallet as the root — this is what you grab to move everything",
    Func    = function()
        task.spawn(function()
            local root = getRoot()
            if not root then Notify("Error", "No character!", 3) return end

            StatusLabel:SetText("Spawning Root...")
            local cf = root.CFrame * CFrame.new(0, 0, -Options.SpawnDist.Value)
            local part, raw = spawnRootPallet(cf)

            if not part then
                Notify("Error", "Root pallet failed to spawn!", 4)
                StatusLabel:SetText("Failed (Root)")
                return
            end

            RootPart = part
            RootPartRaw = raw
            StatusLabel:SetText("Idle")
            updateLabels()
            Notify("Welder", "Root pallet spawned! Grab it to get netowner.", 3)
        end)
    end,
})

Left:AddDivider()

-- ============================================================
-- [[ 10. ADD ALL FROM FOLDER ]]
-- ============================================================

Left:AddButton({
    Text    = "Add All from Folder",
    Tooltip = "Scans your SpawnedInToys folder, adds everything (except Root) as children",
    Func    = function()
        if not RootPart or not RootPart.Parent then
            Notify("Error", "No Root part! Spawn one first.", 3)
            return
        end

        local toyFolder = getToyFolder()
        if not toyFolder then
            Notify("Error", "No SpawnedInToys folder found!", 3)
            return
        end

        -- Build a set of raw entries already in the build (to avoid duplicates)
        local alreadyAdded = {}
        if RootPartRaw then alreadyAdded[RootPartRaw] = true end
        for _, child in ipairs(Children) do
            if child.raw then alreadyAdded[child.raw] = true end
        end

        local added = 0
        for _, toy in ipairs(toyFolder:GetChildren()) do
            -- Skip root and already-added entries
            if not alreadyAdded[toy] then
                local bp = getPartFromToy(toy)
                if bp then
                    local offset = RootPart.CFrame:Inverse() * bp.CFrame
                    table.insert(Children, {
                        part   = bp,
                        raw    = toy,
                        offset = offset,
                        name   = toy.Name,
                    })
                    alreadyAdded[toy] = true
                    added += 1
                end
            end
        end

        updateLabels()
        if added > 0 then
            Notify("Welder", "Added " .. added .. " parts from folder! Total: " .. #Children, 3)
        else
            Notify("Info", "No new parts found in folder.", 3)
        end
    end,
})

Left:AddButton({
    Text    = "Remove Last Part",
    Tooltip = "Removes the last child from the build (does not destroy the toy)",
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

Left:AddButton({
    Text    = "Clear Children",
    Tooltip = "Removes all children from the build (keeps Root, does not destroy toys)",
    Func    = function()
        Children = {}
        updateLabels()
        Notify("Welder", "All children cleared.", 2)
    end,
})

Left:AddDivider()

-- ============================================================
-- [[ 11. CFRAME FAKE-WELD (MULTI-PART) ]]
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
        Notify("Error", "No child parts! Use Add All from Folder first.", 3)
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
    Tooltip = "All children follow Root every frame via CFrame offset",
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
-- [[ 12. UTILITY ]]
-- ============================================================

Left:AddButton({
    Text    = "Re-snapshot All Offsets",
    Tooltip = "Recaptures every child's offset from current positions relative to Root",
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
        StatusLabel:SetText("Idle")
        updateLabels()
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
