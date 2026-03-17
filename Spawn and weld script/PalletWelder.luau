--[[
██████╗  █████╗ ██╗     ██╗     ███████╗████████╗    ██╗    ██╗███████╗██╗     ██████╗ ███████╗██████╗
██╔══██╗██╔══██╗██║     ██║     ██╔════╝╚══██╔══╝    ██║    ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗
██████╔╝███████║██║     ██║     █████╗     ██║       ██║ █╗ ██║█████╗  ██║     ██║  ██║█████╗  ██████╔╝
██╔═══╝ ██╔══██║██║     ██║     ██╔══╝     ██║       ██║███╗██║██╔══╝  ██║     ██║  ██║██╔══╝  ██╔══██╗
██║     ██║  ██║███████╗███████╗███████╗   ██║       ╚███╔███╔╝███████╗███████╗██████╔╝███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝        ╚══╝╚══╝ ╚══════╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
  Pallet Welder v5 | Multi-Part CFrame Weld | Obsidian UI
--]]

-- ============================================================
-- [[ 1. SERVICES ]]
-- ============================================================

local LP         = game:GetService("Players").LocalPlayer
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Mouse      = LP:GetMouse()
local Camera     = workspace.CurrentCamera

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
    Title            = "Pallet Welder v5",
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
    Steal      = Window:AddTab("Players",    "users"),
    IO         = Window:AddTab("Import/Export", "save"),
    UISettings = Window:AddTab("UI",         "settings"),
}

local Left  = Tabs.Main:AddLeftGroupbox("Build",    "box")
local Right = Tabs.Main:AddRightGroupbox("Status",  "info")

local StealLeft  = Tabs.Steal:AddLeftGroupbox("Player Toys",  "box")
local StealRight = Tabs.Steal:AddRightGroupbox("Highlights",  "info")

local IOLeft  = Tabs.IO:AddLeftGroupbox("Export",  "box")
local IORight = Tabs.IO:AddRightGroupbox("Import", "box")

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

local function getPlayerToyFolder(playerName)
    return workspace:FindFirstChild(playerName .. "SpawnedInToys")
end

-- Get the best BasePart from a toy entry (Model or BasePart)
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

    local found = nil
    for _, child in ipairs(toyFolder:GetChildren()) do
        if child.Name == "PalletLightBrown" then
            found = child
        end
    end

    if not found then return nil, nil end
    return getPartFromToy(found), found
end

-- Round to N decimal places
local function round(n, d)
    local m = 10 ^ (d or 4)
    return math.floor(n * m + 0.5) / m
end

-- CFrame to array of 12 rounded numbers
local function cfToArray(cf)
    local c = { cf:GetComponents() }
    local arr = {}
    for i = 1, 12 do
        arr[i] = round(c[i], 4)
    end
    return arr
end

-- Array of 12 numbers to CFrame
local function arrayToCf(arr)
    return CFrame.new(arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7], arr[8], arr[9], arr[10], arr[11], arr[12])
end

-- Spawn any toy by name at a world CFrame. Anchors HRP, tps 3 studs next to spawn pos, spawns, tps back.
-- Returns (BasePart, rawToyEntry) or (nil, nil)
local function spawnToyAt(toyName, worldCF, excludeSet)
    if not Remotes.SpawnToy then
        return nil, nil
    end

    local root = getRoot()
    if not root then return nil, nil end

    -- Save original state
    local origCF = root.CFrame
    local hum = getHum()

    -- Anchor + disable collision + teleport near spawn position so range check passes
    root.Anchored = true
    if hum then hum.WalkSpeed = 0 end

    -- Disable collision on all character parts while teleporting
    local char = LP.Character
    local collisionParts = {}
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                p.CanCollide = false
                table.insert(collisionParts, p)
            end
        end
    end

    root.CFrame = worldCF * CFrame.new(3, 0, 0)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    task.wait(0.1)

    Remotes.SpawnToy:InvokeServer(toyName, worldCF, Vector3.new(0, 0, 0))
    task.wait(0.3)

    -- Teleport back IMMEDIATELY, kill all velocity
    root.CFrame = origCF
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    task.wait(0.05)

    -- Restore state
    root.Anchored = false
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    -- Restore collision
    for _, p in ipairs(collisionParts) do
        if p and p.Parent then
            p.CanCollide = true
        end
    end
    if hum then hum.WalkSpeed = 16 end

    -- Find the spawned toy
    local toyFolder = getToyFolder()
    if not toyFolder then return nil, nil end

    local found = nil
    for _, child in ipairs(toyFolder:GetChildren()) do
        if child.Name == toyName then
            if not excludeSet or not excludeSet[child] then
                found = child
            end
        end
    end

    if not found then return nil, nil end
    return getPartFromToy(found), found
end

-- ============================================================
-- [[ 6. STATE ]]
-- ============================================================

-- Root part (the one you grab and move)
local RootPart    = nil
local RootPartRaw = nil

-- Child parts: { part = BasePart, raw = rawToyEntry, offset = CFrame, name = string }
local Children = {}

-- Weld loop
local weldActive = false
local weldConn   = nil

-- Highlights: { [rawToyEntry] = Highlight instance }
local ActiveHighlights = {}

-- Click-to-remove connection
local clickConn = nil

-- ============================================================
-- [[ 7. HIGHLIGHT SYSTEM ]]
-- ============================================================

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 170, 0)  -- orange
local HIGHLIGHT_OUTLINE = Color3.fromRGB(255, 85, 0)

-- Add a highlight to a toy (Model or BasePart)
local function addHighlight(toy)
    if ActiveHighlights[toy] then return end -- already highlighted

    local hl = Instance.new("Highlight")
    hl.Name = "PalletWelderHL"
    hl.FillColor = HIGHLIGHT_COLOR
    hl.FillTransparency = 0.7
    hl.OutlineColor = HIGHLIGHT_OUTLINE
    hl.OutlineTransparency = 0
    hl.Adornee = toy
    hl.Parent = toy
    ActiveHighlights[toy] = hl
end

-- Remove highlight from a toy
local function removeHighlight(toy)
    local hl = ActiveHighlights[toy]
    if hl then
        hl:Destroy()
        ActiveHighlights[toy] = nil
    end
end

-- Remove all highlights
local function clearAllHighlights()
    for toy, hl in pairs(ActiveHighlights) do
        if hl and hl.Parent then
            hl:Destroy()
        end
    end
    ActiveHighlights = {}
end

-- Check if a BasePart belongs to a highlighted toy
local function findHighlightedToyFromPart(part)
    -- Check if the part itself is a highlighted toy
    if ActiveHighlights[part] then
        return part
    end
    -- Check if the part's parent model is a highlighted toy
    local parent = part.Parent
    if parent and ActiveHighlights[parent] then
        return parent
    end
    -- Check grandparent (in case part is nested deeper)
    if parent and parent.Parent and ActiveHighlights[parent.Parent] then
        return parent.Parent
    end
    return nil
end

-- Start listening for clicks to remove highlights
local function startClickListener()
    if clickConn then return end -- already listening

    clickConn = Mouse.Button1Down:Connect(function()
        local target = Mouse.Target
        if not target then return end

        local toy = findHighlightedToyFromPart(target)
        if toy then
            removeHighlight(toy)

            -- Count remaining
            local remaining = 0
            for _ in pairs(ActiveHighlights) do
                remaining += 1
            end

            if remaining == 0 then
                Notify("Highlights", "All highlights removed!", 2)
            end
        end
    end)
end

-- Stop click listener
local function stopClickListener()
    if clickConn then
        clickConn:Disconnect()
        clickConn = nil
    end
end

-- ============================================================
-- [[ 8. STATUS LABELS ]]
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
-- [[ 9. SETTINGS ]]
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
-- [[ 10. SPAWN ROOT ]]
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
-- [[ 11. ADD FROM FOLDERS ]]
-- ============================================================

Left:AddButton({
    Text    = "Add All from My Folder",
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

        local alreadyAdded = {}
        if RootPartRaw then alreadyAdded[RootPartRaw] = true end
        for _, child in ipairs(Children) do
            if child.raw then alreadyAdded[child.raw] = true end
        end

        local added = 0
        for _, toy in ipairs(toyFolder:GetChildren()) do
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
            Notify("Welder", "Added " .. added .. " parts! Total: " .. #Children, 3)
        else
            Notify("Info", "No new parts found.", 3)
        end
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
        Notify("Error", "No child parts! Add some first.", 3)
        return
    end
    if RootPart.Anchored then
        Notify("Error", "Root is Anchored — can't CFrame weld!", 3)
        return
    end

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
                child.part.CFrame = rootCF * child.offset
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
-- [[ 13. UTILITY ]]
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
    Tooltip = "Stops weld, clears root + all children, clears highlights, resets everything",
    Func    = function()
        stopWeld()
        if Toggles.CFrameWeld then
            Toggles.CFrameWeld:SetValue(false)
        end
        clearAllHighlights()
        stopClickListener()
        RootPart = nil
        RootPartRaw = nil
        Children = {}
        StatusLabel:SetText("Idle")
        updateLabels()
        Notify("Welder", "Everything reset.", 2)
    end,
})

-- ============================================================
-- [[ 14. PLAYER TOYS TAB ]]
-- ============================================================

-- Player dropdown
local function getPlayerList()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            table.insert(list, p.Name)
        end
    end
    if #list == 0 then
        table.insert(list, "No players")
    end
    return list
end

StealLeft:AddDropdown("TargetPlayer", {
    Text     = "Select Player",
    Default  = 1,
    Values   = getPlayerList(),
    Multi    = false,
    Tooltip  = "Pick a player to add their toys to your build",
})

-- Refresh dropdown on player join/leave
Players.PlayerAdded:Connect(function()
    Options.TargetPlayer:SetValues(getPlayerList())
end)
Players.PlayerRemoving:Connect(function()
    task.wait(0.1)
    Options.TargetPlayer:SetValues(getPlayerList())
end)

StealLeft:AddButton({
    Text    = "Refresh Player List",
    Tooltip = "Manually refresh the player dropdown",
    Func    = function()
        Options.TargetPlayer:SetValues(getPlayerList())
        Notify("Players", "Player list refreshed!", 2)
    end,
})

StealLeft:AddDivider()

StealLeft:AddButton({
    Text    = "Add Player's Toys + Highlight",
    Tooltip = "Adds all toys from the selected player's folder to the build and highlights them",
    Func    = function()
        if not RootPart or not RootPart.Parent then
            Notify("Error", "No Root part! Spawn one first (Welder tab).", 3)
            return
        end

        local playerName = Options.TargetPlayer.Value
        if not playerName or playerName == "No players" then
            Notify("Error", "No player selected!", 3)
            return
        end

        local folder = getPlayerToyFolder(playerName)
        if not folder then
            Notify("Error", "No SpawnedInToys folder for " .. playerName .. "!", 3)
            return
        end

        -- Build set of already-added raw entries
        local alreadyAdded = {}
        if RootPartRaw then alreadyAdded[RootPartRaw] = true end
        for _, child in ipairs(Children) do
            if child.raw then alreadyAdded[child.raw] = true end
        end

        local added = 0
        for _, toy in ipairs(folder:GetChildren()) do
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

                    -- Add highlight so you can see what needs grabbing
                    addHighlight(toy)
                end
            end
        end

        -- Start click listener to remove highlights on click
        if added > 0 then
            startClickListener()
        end

        updateLabels()
        if added > 0 then
            Notify("Players", "Added " .. added .. " toys from " .. playerName .. "! Click each to remove highlight after grabbing.", 5)
        else
            Notify("Info", "No new toys found for " .. playerName .. ".", 3)
        end
    end,
})

StealLeft:AddButton({
    Text    = "Add Player's Toys (No Highlight)",
    Tooltip = "Same as above but without highlights",
    Func    = function()
        if not RootPart or not RootPart.Parent then
            Notify("Error", "No Root part! Spawn one first (Welder tab).", 3)
            return
        end

        local playerName = Options.TargetPlayer.Value
        if not playerName or playerName == "No players" then
            Notify("Error", "No player selected!", 3)
            return
        end

        local folder = getPlayerToyFolder(playerName)
        if not folder then
            Notify("Error", "No SpawnedInToys folder for " .. playerName .. "!", 3)
            return
        end

        local alreadyAdded = {}
        if RootPartRaw then alreadyAdded[RootPartRaw] = true end
        for _, child in ipairs(Children) do
            if child.raw then alreadyAdded[child.raw] = true end
        end

        local added = 0
        for _, toy in ipairs(folder:GetChildren()) do
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
            Notify("Players", "Added " .. added .. " toys from " .. playerName .. "!", 3)
        else
            Notify("Info", "No new toys found for " .. playerName .. ".", 3)
        end
    end,
})

-- ============================================================
-- [[ 15. HIGHLIGHT CONTROLS ]]
-- ============================================================

StealRight:AddLabel("Click a highlighted toy\nin-game to remove its\nhighlight after grabbing it.")

StealRight:AddDivider()

local HighlightCountLabel = StealRight:AddLabel("Highlights: 0")

-- Update highlight count periodically
task.spawn(function()
    while task.wait(1) do
        local count = 0
        for _ in pairs(ActiveHighlights) do
            count += 1
        end
        HighlightCountLabel:SetText("Highlights: " .. count)
    end
end)

StealRight:AddDivider()

StealRight:AddButton({
    Text    = "Clear All Highlights",
    Tooltip = "Removes all highlight outlines from toys",
    Func    = function()
        clearAllHighlights()
        stopClickListener()
        Notify("Highlights", "All highlights cleared.", 2)
    end,
})

-- ============================================================
-- [[ 16. IMPORT / EXPORT ]]
-- ============================================================

local HttpService = game:GetService("HttpService")

-- ---- EXPORT ----

local ExportOutput = IOLeft:AddLabel("Export output will appear here.")

IOLeft:AddButton({
    Text    = "Export Build",
    Tooltip = "Exports the current build (Root + Children offsets) to JSON",
    Func    = function()
        if not RootPart or not RootPart.Parent then
            Notify("Error", "No Root part to export!", 3)
            return
        end
        if #Children == 0 then
            Notify("Error", "No children to export!", 3)
            return
        end

        local buildName = "Build_" .. os.date("%Y-%m-%d_%H-%M-%S")

        local rootName = RootPartRaw and RootPartRaw.Name or "PalletLightBrown"

        -- Build JSON string manually to ensure clean array format
        local childrenStr = {}
        local count = 0
        for _, child in ipairs(Children) do
            if child.part and child.part.Parent then
                local arr = cfToArray(child.offset)
                local offsetStr = "[" .. table.concat(arr, ",") .. "]"
                local toyName = (child.name or "Unknown"):gsub('"', '\\"')
                table.insert(childrenStr, '{"toy":"' .. toyName .. '","offset":' .. offsetStr .. '}')
                count += 1
            end
        end

        local safeName = buildName:gsub('"', '\\"')
        local json = '{"version":1,"name":"' .. safeName .. '","root":"' .. rootName .. '","children":[' .. table.concat(childrenStr, ",") .. ']}'

        ExportOutput:SetText(json)
        Notify("Export", "Build exported! " .. count .. " parts. Use Copy button.", 4)
    end,
})

IOLeft:AddButton({
    Text    = "Copy to Clipboard",
    Tooltip = "Copies the export output to your clipboard",
    Func    = function()
        local text = ExportOutput.Text
        if not text or text == "" or text == "Export output will appear here." then
            Notify("Error", "Nothing to copy! Export first.", 3)
            return
        end
        if setclipboard then
            setclipboard(text)
            Notify("Export", "Copied to clipboard!", 2)
        else
            Notify("Error", "setclipboard not available on your executor!", 3)
        end
    end,
})

-- ---- IMPORT ----

local ImportStatusLabel = IORight:AddLabel("Copy JSON to clipboard, then click Import.")

IORight:AddButton({
    Text    = "Import from Clipboard",
    Tooltip = "Reads JSON from your clipboard and spawns the build",
    Func    = function()
        task.spawn(function()
            local clipRead = readclipboard or getclipboard
            if not clipRead then
                Notify("Error", "Clipboard reading not available on your executor!", 3)
                return
            end

            local json = clipRead()
            if not json or json == "" then
                Notify("Error", "Clipboard is empty! Copy the JSON first.", 3)
                return
            end

            local ok, data = pcall(function()
                return HttpService:JSONDecode(json)
            end)
            if not ok or type(data) ~= "table" then
                Notify("Error", "Invalid JSON!", 3)
                return
            end

            if not data.root or not data.children or #data.children == 0 then
                Notify("Error", "JSON missing root or children!", 3)
                return
            end

            local root = getRoot()
            if not root then
                Notify("Error", "No character!", 3)
                return
            end

            if not Remotes.SpawnToy then
                Notify("Error", "SpawnToy remote not ready!", 3)
                return
            end

            -- Stop any active weld
            stopWeld()
            if Toggles.CFrameWeld then
                Toggles.CFrameWeld:SetValue(false)
            end

            -- Clear existing build
            Children = {}

            -- The root spawns in front of the player
            local rootSpawnCF = root.CFrame * CFrame.new(0, 0, -Options.SpawnDist.Value)

            ImportStatusLabel:SetText("Spawning Root...")
            StatusLabel:SetText("Importing...")

            -- Build exclude set as we go
            local excludeSet = {}

            -- Spawn root
            local rootBP, rootRaw = spawnToyAt(data.root, rootSpawnCF, excludeSet)
            if not rootBP then
                Notify("Error", "Root (" .. data.root .. ") failed to spawn!", 4)
                ImportStatusLabel:SetText("Failed (Root)")
                StatusLabel:SetText("Idle")
                return
            end

            RootPart = rootBP
            RootPartRaw = rootRaw
            if rootRaw then excludeSet[rootRaw] = true end
            updateLabels()

            ImportStatusLabel:SetText("Root OK! Spawning children...")
            Notify("Import", "Root spawned! Now spawning " .. #data.children .. " children...", 3)

            local spawned = 0
            local failed = 0

            for i, entry in ipairs(data.children) do
                ImportStatusLabel:SetText("Spawning #" .. i .. " / " .. #data.children .. " (" .. (entry.toy or "?") .. ")")

                -- Calculate world CFrame: root position * stored offset
                local offset = arrayToCf(entry.offset)
                local worldCF = rootBP.CFrame * offset

                local bp, raw = spawnToyAt(entry.toy, worldCF, excludeSet)
                if bp then
                    if raw then excludeSet[raw] = true end

                    table.insert(Children, {
                        part   = bp,
                        raw    = raw,
                        offset = offset,
                        name   = entry.toy,
                    })
                    spawned += 1
                else
                    failed += 1
                end
            end

            StatusLabel:SetText("Idle")
            updateLabels()

            local msg = "Import done! " .. spawned .. " spawned"
            if failed > 0 then
                msg = msg .. ", " .. failed .. " failed"
            end
            ImportStatusLabel:SetText(msg)
            Notify("Import", msg .. ". Grab all parts for netowner, then toggle weld!", 5)
        end)
    end,
})

IORight:AddDivider()
IORight:AddLabel({
    Text     = "After importing:\n1. Grab each part to get\n   network ownership\n2. Toggle CFrame Weld\n3. Grab Root to move all!",
    DoesWrap = true,
})

-- ============================================================
-- [[ 17. UI SETTINGS (ThemeManager + SaveManager) ]]
-- ============================================================

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PalletWelder")
ThemeManager:ApplyToTab(Tabs.UISettings)
ThemeManager:ApplyTheme("Catppuccin")

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("PalletWelder")
SaveManager:BuildConfigSection(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()
