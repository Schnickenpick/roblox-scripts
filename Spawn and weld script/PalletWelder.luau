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
    Rockets    = Window:AddTab("Rockets",    "zap"),
    UISettings = Window:AddTab("UI",         "settings"),
}

local Left  = Tabs.Main:AddLeftGroupbox("Build",    "box")
local Right = Tabs.Main:AddRightGroupbox("Status",  "info")

local StealLeft  = Tabs.Steal:AddLeftGroupbox("Player Toys",  "box")
local StealRight = Tabs.Steal:AddRightGroupbox("Highlights",  "info")

local IOLeft  = Tabs.IO:AddLeftGroupbox("Export",  "box")
local IORight = Tabs.IO:AddRightGroupbox("Import", "box")

local RocketLeft  = Tabs.Rockets:AddLeftGroupbox("Stockpile",  "box")
local RocketRight = Tabs.Rockets:AddRightGroupbox("Launch",    "zap")

-- ============================================================
-- [[ 4. REMOTES ]]
-- ============================================================

local Remotes = {}
task.spawn(function()
    local GE = RS:WaitForChild("GrabEvents", 10)
    if GE then
        Remotes.CreateGrabLine   = GE:FindFirstChild("CreateGrabLine")  -- for anti-steal detection only
        Remotes.SetNetworkOwner  = GE:FindFirstChild("SetNetworkOwner")
    end
    local MT = RS:WaitForChild("MenuToys", 10)
    if MT then
        Remotes.SpawnToy   = MT:FindFirstChild("SpawnToyRemoteFunction")
        Remotes.DestroyToy = MT:FindFirstChild("DestroyToy")
    end
    local BE = RS:WaitForChild("BombEvents", 10)
    if BE then
        Remotes.BombExplode    = BE:FindFirstChild("BombExplode")
        Remotes.BombReplicator = BE:FindFirstChild("BombReplicator")
    end
end)

-- ============================================================
-- [[ 5. HELPERS ]]
-- ============================================================

local function getRoot()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
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

-- Spawn a toy near player, find it, return (BasePart, rawToyEntry) or (nil, nil).
-- Does NOT teleport — just fires the spawn remote from current position.
local function spawnToyNearby(toyName, excludeSet)
    if not Remotes.SpawnToy then return nil, nil end

    local hrp = getRoot()
    if not hrp then return nil, nil end

    local spawnCF = hrp.CFrame * CFrame.new(0, 0, -5)
    Remotes.SpawnToy:InvokeServer(toyName, spawnCF, Vector3.new(0, 0, 0))
    task.wait(0.4)

    -- Find it in toy folder
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

-- Spawn + claim + move in one operation.
-- Spawns toy near player, claims network ownership with retries, then moves to targetCF.
-- Returns (BasePart, rawToyEntry) or (nil, nil).
local MAX_CLAIM_RETRIES = 3

local function spawnClaimAndMove(toyName, targetCF, excludeSet)
    if not Remotes.SpawnToy then return nil, nil end

    local hrp = getRoot()
    if not hrp then return nil, nil end

    -- Spawn 5 studs in front of player
    local spawnCF = hrp.CFrame * CFrame.new(0, 0, -5)
    Remotes.SpawnToy:InvokeServer(toyName, spawnCF, Vector3.new(0, 0, 0))
    task.wait(0.5)

    -- Find it in toy folder
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
    local bp = getPartFromToy(found)
    if not bp then return nil, nil end

    -- Find SoundPart — this is what the game uses for SetNetworkOwner
    local soundPart = nil
    if found:IsA("Model") then
        soundPart = found:FindFirstChild("SoundPart", true)
    end
    -- Fallback to bp if no SoundPart (e.g. for simple BasePart toys)
    local netPart = soundPart or bp

    warn("[Import] Toy: " .. toyName .. " | SoundPart: " .. tostring(soundPart ~= nil) .. " | NetPart: " .. netPart.Name)

    -- Claim with retries + verification
    local claimed = false
    for attempt = 1, MAX_CLAIM_RETRIES do
        -- Always re-read the part's CURRENT position (it may have fallen/moved)
        local partPos = bp.CFrame.Position
        local dist = (hrp.Position - partPos).Magnitude

        warn("[Import] Attempt " .. attempt .. " | Part at: " .. tostring(partPos) .. " | Dist: " .. string.format("%.1f", dist))

        -- SetNetworkOwner: SoundPart (or bp fallback), player's HRP CFrame
        if Remotes.SetNetworkOwner then
            Remotes.SetNetworkOwner:FireServer(netPart, hrp.CFrame)
            task.wait(0.3)
        end

        -- Verify: try moving the part and see if it sticks
        local testCF = bp.CFrame * CFrame.new(0, 1, 0)
        bp.CFrame = testCF
        bp.AssemblyLinearVelocity = Vector3.zero
        bp.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.1)

        local afterPos = bp.CFrame.Position
        local drift = (afterPos - testCF.Position).Magnitude
        warn("[Import] Verify drift: " .. string.format("%.2f", drift))

        if drift < 2 then
            claimed = true
            warn("[Import] Ownership claimed on attempt " .. attempt)
            break
        else
            warn("[Import] Attempt " .. attempt .. " failed (drift=" .. string.format("%.1f", drift) .. "), retrying...")
            task.wait(0.3)
        end
    end

    if not claimed then
        warn("[Import] Failed to claim " .. toyName .. " after " .. MAX_CLAIM_RETRIES .. " attempts")
    end

    -- Move to sky target + anchor ALL parts so nothing falls
    bp.CFrame = targetCF
    bp.AssemblyLinearVelocity = Vector3.zero
    bp.AssemblyAngularVelocity = Vector3.zero

    -- Anchor every BasePart in the model
    if found:IsA("Model") then
        for _, p in ipairs(found:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = true
                p.AssemblyLinearVelocity = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    elseif found:IsA("BasePart") then
        found.Anchored = true
    end

    warn("[Import] " .. toyName .. " moved to sky + anchored | Pos: " .. tostring(bp.Position))

    return bp, found
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

-- Rocket system
local RocketStockpile = {}    -- { part = BasePart, raw = rawToyEntry }
local ActiveRockets = {}      -- { part = BasePart, raw = rawToyEntry, conn = RBXScriptConnection, startTime = number }
local stockpileInProgress = false
local ROCKET_SKY_HEIGHT = 1000
local ROCKET_SKY_SPREAD = 5

-- Button system: cooldown tracking per child (child -> last trigger tick)
local ButtonCooldowns = {}

-- Follow link system: { [groupName] = { player = Player, buttonChild = childEntry } }
local ActiveFollowLinks = {}

-- Forward declarations (defined later, referenced in anti-steal listener)
local fireRocket

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

    -- Unanchor root + all children (needed after import where everything is anchored in sky)
    -- Unanchor all parts in RootPartRaw (the model)
    if RootPartRaw and RootPartRaw:IsA("Model") then
        for _, p in ipairs(RootPartRaw:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = false
                p.AssemblyLinearVelocity = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    elseif RootPart and RootPart.Anchored then
        RootPart.Anchored = false
        RootPart.AssemblyLinearVelocity = Vector3.zero
        RootPart.AssemblyAngularVelocity = Vector3.zero
    end

    local valid = 0
    for _, child in ipairs(Children) do
        if child.part and child.part.Parent then
            -- Unanchor all parts in the raw model
            if child.raw and child.raw:IsA("Model") then
                for _, p in ipairs(child.raw:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.Anchored = false
                        p.AssemblyLinearVelocity = Vector3.zero
                        p.AssemblyAngularVelocity = Vector3.zero
                    end
                end
            elseif child.part.Anchored then
                child.part.Anchored = false
                child.part.AssemblyLinearVelocity = Vector3.zero
                child.part.AssemblyAngularVelocity = Vector3.zero
            end
            valid += 1
        end
    end
    if valid == 0 then
        Notify("Error", "All children are destroyed!", 3)
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

        -- Pre-compute follow group pivots and head rotations
        local followPivots = {}  -- { [groupName] = { headRot = CFrame, pivotOffset = CFrame } }
        for groupName, link in pairs(ActiveFollowLinks) do
            local plr = link.player
            local char = plr and plr.Character
            local head = char and char:FindFirstChild("Head")
            if head and link.buttonChild and link.buttonChild.offset then
                -- Head rotation only (strip position)
                local headRot = head.CFrame - head.CFrame.Position
                followPivots[groupName] = {
                    headRot = headRot,
                    pivotOffset = link.buttonChild.offset,
                }
            end
        end

        for _, child in ipairs(Children) do
            if child.part and child.part.Parent and not child.part.Anchored then
                -- Check if this child is in an active follow group
                local followData = child.followGroup and followPivots[child.followGroup]

                if followData then
                    -- Follow mode: rotate around the button pivot using the player's head rotation
                    local pivotWorld = rootCF * followData.pivotOffset
                    local localOffset = followData.pivotOffset:Inverse() * child.offset
                    child.part.CFrame = pivotWorld * followData.headRot * localOffset
                else
                    -- Normal weld
                    child.part.CFrame = rootCF * child.offset
                end

                child.part.AssemblyLinearVelocity = Vector3.new(0, 0.01, 0)
                child.part.AssemblyAngularVelocity = Vector3.zero

                -- Hide RocketSpawn marker during weld
                if child.name and child.name:find("RocketSpawn") then
                    child.part.Transparency = 1
                    if child.raw and child.raw:IsA("Model") then
                        for _, p in ipairs(child.raw:GetDescendants()) do
                            if p:IsA("BasePart") then p.Transparency = 1 end
                            if p:IsA("Decal") then p.Transparency = 1 end
                        end
                    end
                end
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

        -- Clear rocket stockpile
        for _, r in ipairs(RocketStockpile) do
            if r.raw and r.raw.Parent and Remotes.DestroyToy then
                Remotes.DestroyToy:FireServer(r.raw)
            end
        end
        RocketStockpile = {}

        -- Disconnect active rockets
        for _, r in ipairs(ActiveRockets) do
            if r.conn then r.conn:Disconnect() end
        end
        ActiveRockets = {}

        -- Clear follow links
        ActiveFollowLinks = {}

        StatusLabel:SetText("Idle")
        updateLabels()
        Notify("Welder", "Everything reset.", 2)
    end,
})

-- ============================================================
-- [[ 13.5. AUTO REGRAB (ANTI-STEAL) ]]
-- ============================================================

local regrabActive = false
local regrabConn = nil

-- Get all SoundParts (or bp fallbacks) from our build for quick lookup
local function getOurParts()
    local parts = {}
    local toyFolder = getToyFolder()
    if not toyFolder then return parts end

    -- Root
    if RootPartRaw and RootPartRaw.Parent then
        local sp = RootPartRaw:FindFirstChild("SoundPart", true)
        if sp then parts[sp] = true end
        local bp = getPartFromToy(RootPartRaw)
        if bp then parts[bp] = true end
        -- Add all BaseParts in the model
        if RootPartRaw:IsA("Model") then
            for _, p in ipairs(RootPartRaw:GetDescendants()) do
                if p:IsA("BasePart") then parts[p] = true end
            end
        end
    end

    -- Children
    for _, child in ipairs(Children) do
        if child.raw and child.raw.Parent then
            local sp = child.raw:FindFirstChild("SoundPart", true)
            if sp then parts[sp] = true end
            if child.part then parts[child.part] = true end
            if child.raw:IsA("Model") then
                for _, p in ipairs(child.raw:GetDescendants()) do
                    if p:IsA("BasePart") then parts[p] = true end
                end
            end
        end
    end

    -- Rocket stockpile
    for _, r in ipairs(RocketStockpile) do
        if r.raw and r.raw.Parent then
            local sp = r.raw:FindFirstChild("SoundPart", true)
            if sp then parts[sp] = true end
            if r.part then parts[r.part] = true end
            if r.raw:IsA("Model") then
                for _, p in ipairs(r.raw:GetDescendants()) do
                    if p:IsA("BasePart") then parts[p] = true end
                end
            end
        end
    end

    return parts
end

local function startRegrab()
    if regrabConn then return end
    regrabActive = true

    local grabRemote = Remotes.CreateGrabLine
    if not grabRemote then
        warn("[Regrab] CreateGrabLine remote not found!")
        return
    end

    regrabConn = grabRemote.OnClientEvent:Connect(function(player, grabbedPart, grabCFrame)
        -- Ignore our own grabs
        if player == LP then return end
        if not regrabActive then return end

        -- Check if the grabbed part belongs to our build
        local ourParts = getOurParts()
        if not ourParts[grabbedPart] then return end

        -- Someone grabbed one of our parts! Reclaim it.
        local hrp = getRoot()
        if not hrp then return end

        -- Find the SoundPart of the toy that owns this part
        local toyRaw = grabbedPart
        -- Walk up to find the toy model in our folder
        local toyFolder = getToyFolder()
        if toyFolder then
            local current = grabbedPart
            for _ = 1, 5 do
                if current.Parent == toyFolder then
                    toyRaw = current
                    break
                end
                current = current.Parent
                if not current then break end
            end
        end

        local soundPart = nil
        if toyRaw:IsA("Model") then
            soundPart = toyRaw:FindFirstChild("SoundPart", true)
        end
        local netPart = soundPart or grabbedPart

        -- Check if this is a button (child with a tag)
        local buttonChild = nil
        for _, child in ipairs(Children) do
            if child.tag and child.raw and child.raw == toyRaw then
                buttonChild = child
                break
            end
        end

        if buttonChild then
            -- Button press detected! Check cooldown
            local cooldown = Options.ButtonCooldown and Options.ButtonCooldown.Value or 1
            local lastPress = ButtonCooldowns[buttonChild] or 0
            if tick() - lastPress < cooldown then
                warn("[Button] Cooldown active for " .. buttonChild.tag)
            else
                ButtonCooldowns[buttonChild] = tick()
                warn("[Button] " .. player.Name .. " pressed button: " .. buttonChild.tag)
                Notify("Button", player.Name .. " pressed " .. buttonChild.tag .. "!", 2)

                -- Dispatch action based on tag
                if buttonChild.tag == "Rocket" then
                    task.spawn(fireRocket)
                elseif buttonChild.tag == "Explode" then
                    local btnPos = RootPart and RootPart.CFrame * buttonChild.offset
                    if btnPos then
                        Notify("Button", "Boom!", 1)
                    end
                elseif buttonChild.tag == "Follow" then
                    local groupName = buttonChild.followGroup
                    if groupName then
                        local existing = ActiveFollowLinks[groupName]
                        if existing and existing.player == player then
                            -- Same player pressed again → deactivate
                            ActiveFollowLinks[groupName] = nil
                            warn("[Follow] " .. player.Name .. " released " .. groupName)
                            Notify("Follow", player.Name .. " released " .. groupName, 2)
                        else
                            -- New player or first activation → activate/overwrite
                            ActiveFollowLinks[groupName] = {
                                player = player,
                                buttonChild = buttonChild,
                            }
                            warn("[Follow] " .. player.Name .. " now controls " .. groupName)
                            Notify("Follow", player.Name .. " controls " .. groupName .. "!", 2)
                        end
                    else
                        warn("[Follow] Button has Follow tag but no followGroup!")
                        Notify("Button", "Follow button needs a followGroup!", 3)
                    end
                end
            end
        else
            warn("[Regrab] " .. player.Name .. " grabbed our " .. grabbedPart.Name .. " — reclaiming!")
            Notify("Anti-Steal", player.Name .. " grabbed your build! Reclaiming...", 3)
        end

        -- Always reclaim regardless of button or not
        task.spawn(function()
            for attempt = 1, 3 do
                if Remotes.SetNetworkOwner then
                    Remotes.SetNetworkOwner:FireServer(netPart, hrp.CFrame)
                end
                if attempt < 3 then task.wait(0.3) end
            end
        end)
    end)

    warn("[Regrab] Anti-steal active — listening for grabs on our parts")
end

local function stopRegrab()
    regrabActive = false
    if regrabConn then
        regrabConn:Disconnect()
        regrabConn = nil
    end
end

Right:AddDivider()

Right:AddToggle("AutoRegrab", {
    Text    = "Anti-Steal (Auto Regrab)",
    Default = false,
    Tooltip = "Detects when someone grabs your build and automatically reclaims it",
    Callback = function(v)
        if v then
            startRegrab()
            Notify("Anti-Steal", "Active! Will reclaim if someone grabs your build.", 3)
        else
            stopRegrab()
            Notify("Anti-Steal", "Disabled.", 2)
        end
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
Players.PlayerRemoving:Connect(function(leavingPlayer)
    task.wait(0.1)
    Options.TargetPlayer:SetValues(getPlayerList())

    -- Auto-release follow links for the leaving player
    for groupName, link in pairs(ActiveFollowLinks) do
        if link.player == leavingPlayer then
            ActiveFollowLinks[groupName] = nil
            warn("[Follow] " .. leavingPlayer.Name .. " left — released " .. groupName)
        end
    end
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
            -- Include virtual markers (RocketSpawn) even though they have no part
            if (child.part and child.part.Parent) or (child.name == "RocketSpawn") then
                local arr = cfToArray(child.offset)
                local offsetStr = "[" .. table.concat(arr, ",") .. "]"
                local toyName = (child.name or "Unknown"):gsub('"', '\\"')
                local entry = '{"toy":"' .. toyName .. '","offset":' .. offsetStr
                if child.tag then
                    entry = entry .. ',"tag":"' .. tostring(child.tag):gsub('"', '\\"') .. '"'
                end
                if child.followGroup then
                    entry = entry .. ',"followGroup":"' .. tostring(child.followGroup):gsub('"', '\\"') .. '"'
                end
                entry = entry .. '}'
                table.insert(childrenStr, entry)
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

IORight:AddInput("ImportJSON", {
    Text     = "Import JSON",
    Default  = "",
    Placeholder = "Paste JSON here...",
})

IORight:AddSlider("SkyHeight", {
    Text    = "Sky Height",
    Default = 300,
    Min     = 50,
    Max     = 1000,
    Rounding = 0,
    Suffix  = " studs",
    Tooltip = "How high above you to build in the sky",
})

local ImportStatusLabel = IORight:AddLabel("Paste JSON above, then click Import.")

IORight:AddButton({
    Text    = "Import Build",
    Tooltip = "Spawns build in sky with auto network ownership",
    Func    = function()
        task.spawn(function()
            local json = Options.ImportJSON and Options.ImportJSON.Value
            if not json or json == "" then
                Notify("Error", "Paste JSON into the input first!", 3)
                return
            end

            local ok, data = pcall(function()
                return HttpService:JSONDecode(json)
            end)
            if not ok or type(data) ~= "table" then
                Notify("Error", "Invalid JSON! " .. tostring(data), 4)
                return
            end

            if not data.root or not data.children or #data.children == 0 then
                Notify("Error", "JSON missing root or children!", 3)
                return
            end

            local hrp = getRoot()
            if not hrp then
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

            local skyHeight = Options.SkyHeight and Options.SkyHeight.Value or 300
            local playerPos = hrp.Position
            -- Sky position for the root (directly above player)
            local skyCF = CFrame.new(playerPos.X, playerPos.Y + skyHeight, playerPos.Z)

            ImportStatusLabel:SetText("Spawning Root...")
            StatusLabel:SetText("Importing...")
            Notify("Import", "Spawning root near you...", 3)

            local excludeSet = {}

            -- 1. Spawn root near player, claim ownership, move to sky
            ImportStatusLabel:SetText("Spawning + claiming Root...")
            local rootBP, rootRaw = spawnClaimAndMove(data.root, skyCF, excludeSet)
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

            ImportStatusLabel:SetText("Root in sky! Spawning children...")
            Notify("Import", "Root placed! Spawning " .. #data.children .. " children...", 3)

            local spawned = 0
            local failed = 0

            for i, entry in ipairs(data.children) do
                local offset = arrayToCf(entry.offset)

                -- RocketSpawn is an editor-only marker — don't spawn, just store offset
                if entry.toy == "RocketSpawn" then
                    table.insert(Children, {
                        part       = nil,
                        raw        = nil,
                        offset     = offset,
                        name       = "RocketSpawn",
                        followGroup = entry.followGroup,
                    })
                    warn("[Import] RocketSpawn marker stored (virtual, no spawn)")
                    spawned += 1
                    continue
                end

                ImportStatusLabel:SetText("Spawning #" .. i .. "/" .. #data.children .. " (" .. (entry.toy or "?") .. ")")

                -- Target position in sky (relative to root)
                local targetCF = rootBP.CFrame * offset

                -- Spawn near player, claim, move to sky — all in one
                local bp, raw = spawnClaimAndMove(entry.toy, targetCF, excludeSet)
                if bp then
                    if raw then excludeSet[raw] = true end

                    table.insert(Children, {
                        part        = bp,
                        raw         = raw,
                        offset      = offset,
                        name        = entry.toy,
                        tag         = entry.tag,
                        followGroup = entry.followGroup,
                    })
                    spawned += 1
                else
                    failed += 1
                end
            end

            -- TP player 20 studs above root BEFORE activating weld
            local rootPos = rootBP.Position
            warn("[Import] TPing to " .. tostring(rootPos) .. " + 20 Y")
            hrp.Anchored = true
            hrp.CFrame = CFrame.new(rootPos.X, rootPos.Y + 20, rootPos.Z)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            task.wait(0.3)
            hrp.Anchored = false

            -- Now activate weld
            ImportStatusLabel:SetText("Activating weld...")
            if Toggles.CFrameWeld then
                Toggles.CFrameWeld:SetValue(true)
            end

            StatusLabel:SetText("Idle")
            updateLabels()

            local msg = "Import done! " .. spawned .. " spawned"
            if failed > 0 then
                msg = msg .. ", " .. failed .. " failed"
            end
            ImportStatusLabel:SetText(msg)
            Notify("Import", msg .. "\nWeld active! Grab Root to move.", 6)
        end)
    end,
})

IORight:AddDivider()
IORight:AddLabel({
    Text     = "Import flow:\n1. Spawns each part near you\n2. Auto-grabs for net ownership\n3. Moves to sky position\n4. Auto-welds + TPs you up\n5. Grab Root to fly!",
    DoesWrap = true,
})

-- ============================================================
-- [[ 17. ROCKET SYSTEM ]]
-- ============================================================

-- Find RocketSpawn child (if user placed a marker in the build)
-- Returns the child entry { part, raw, offset, name } or nil
local function getRocketSpawnChild()
	for _, child in ipairs(Children) do
		if child.name and child.name:find("RocketSpawn") and child.offset then
			return child
		end
	end
	return nil
end

-- Stockpile UI
RocketLeft:AddDropdown("RocketToy", {
	Text    = "Rocket Toy",
	Default = 1,
	Values  = {"BombMissile", "NinjaShuriken", "NinjaKunai", "BaseballBat", "NinjaSword"},
	Multi   = false,
	Tooltip = "Which toy to use as a rocket projectile (BombMissile explodes on impact!)",
})

RocketLeft:AddSlider("RocketCount", {
	Text     = "Rockets to Stockpile",
	Default  = 5,
	Min      = 1,
	Max      = 20,
	Rounding = 0,
	Suffix   = " rockets",
})

local RocketStockLabel = RocketLeft:AddLabel("Stockpile: 0 rockets ready")

RocketLeft:AddButton({
	Text    = "Stockpile Rockets",
	Tooltip = "Spawn + claim rockets, store in sky",
	Func    = function()
		task.spawn(function()
			if stockpileInProgress then
				Notify("Rockets", "Already stockpiling!", 2)
				return
			end
			stockpileInProgress = true

			local hrp = getRoot()
			if not hrp then
				Notify("Error", "No character!", 3)
				stockpileInProgress = false
				return
			end

			local toyName = Options.RocketToy and Options.RocketToy.Value or "NinjaShuriken"
			local count = Options.RocketCount and Options.RocketCount.Value or 5

			-- Build exclude set from existing stockpile
			local excludeSet = {}
			for _, r in ipairs(RocketStockpile) do
				if r.raw then excludeSet[r.raw] = true end
			end
			-- Also exclude build parts
			if RootPartRaw then excludeSet[RootPartRaw] = true end
			for _, child in ipairs(Children) do
				if child.raw then excludeSet[child.raw] = true end
			end

			Notify("Rockets", "Stockpiling " .. count .. " rockets...", 3)

			local success = 0
			for i = 1, count do
				RocketStockLabel:SetText("Stockpiling " .. i .. "/" .. count .. "...")

				local skyCF = CFrame.new(
					hrp.Position.X + (i * ROCKET_SKY_SPREAD),
					hrp.Position.Y + ROCKET_SKY_HEIGHT,
					hrp.Position.Z
				)

				local bp, raw = spawnClaimAndMove(toyName, skyCF, excludeSet)
				if bp and raw then
					excludeSet[raw] = true
					table.insert(RocketStockpile, { part = bp, raw = raw })
					success += 1
				end
			end

			RocketStockLabel:SetText("Stockpile: " .. #RocketStockpile .. " rockets ready")
			stockpileInProgress = false
			Notify("Rockets", "Stockpiled " .. success .. "/" .. count .. " rockets!", 3)
		end)
	end,
})

RocketLeft:AddButton({
	Text    = "Clear Stockpile",
	Tooltip = "Destroy all stockpiled rockets",
	Func    = function()
		for _, r in ipairs(RocketStockpile) do
			if r.raw and r.raw.Parent and Remotes.DestroyToy then
				Remotes.DestroyToy:FireServer(r.raw)
			end
		end
		RocketStockpile = {}
		RocketStockLabel:SetText("Stockpile: 0 rockets ready")
		Notify("Rockets", "Stockpile cleared!", 2)
	end,
})

-- Launch UI
RocketRight:AddSlider("RocketSpeed", {
	Text     = "Rocket Speed",
	Default  = 200,
	Min      = 50,
	Max      = 1000,
	Rounding = 0,
	Suffix   = " st/s",
	Tooltip  = "Studs per second the rocket travels",
})

RocketRight:AddSlider("RocketLifetime", {
	Text     = "Rocket Lifetime",
	Default  = 5,
	Min      = 1,
	Max      = 20,
	Rounding = 1,
	Suffix   = " sec",
	Tooltip  = "How long before the rocket auto-destroys",
})

RocketRight:AddToggle("RocketExplode", {
	Text    = "Explode on Impact",
	Default = true,
	Tooltip = "BombMissile rockets explode when they hit something (Touched event)",
})

local RocketActiveLabel = RocketRight:AddLabel("Active: 0 | Stockpile: 0")

RocketRight:AddDivider()
RocketRight:AddLabel({
	Text     = "Press C to fire a rocket!\nRockets fly from RocketSpawn\nmarker on build, or from\nplayer look direction.\nBombMissile = explodes on hit!",
	DoesWrap = true,
})

-- Trigger BombMissile explosion via game events
local function explodeRocket(rocketRaw, position)
	if not rocketRaw or not rocketRaw.Parent then return end

	-- Find bomb parts inside the model
	local hitbox = rocketRaw:FindFirstChild("PartHitDetector", true)
	local body = rocketRaw:FindFirstChild("Body", true)

	local explodeData = {
		Radius = 17.5,
		TimeLength = 0.5,
		ExplodedOnce = false,
		Model = rocketRaw,
		ExplodesByFire = true,
		ImpactSpeed = 100,
		Hitbox = hitbox,
		DestroysModel = true,
		ExplodesByPointy = false,
		MaxForcePerStudSquared = 225,
		PositionPart = body,
	}

	-- Fire BombExplode (visual explosion for all clients)
	if Remotes.BombExplode then
		firesignal(Remotes.BombExplode.OnClientEvent, explodeData, position)
	end

	-- Fire BombReplicator (replicates to other clients)
	if Remotes.BombReplicator then
		firesignal(Remotes.BombReplicator.OnClientEvent, explodeData)
	end
end

-- Fire rocket function
fireRocket = function()
	-- Remove dead rockets from stockpile first
	for i = #RocketStockpile, 1, -1 do
		if not RocketStockpile[i].part or not RocketStockpile[i].part.Parent then
			table.remove(RocketStockpile, i)
		end
	end

	if #RocketStockpile == 0 then
		Notify("Rockets", "No rockets! Stockpile some first.", 2)
		return
	end

	local rocket = table.remove(RocketStockpile, 1)
	local bp = rocket.part
	if not bp or not bp.Parent then
		-- Try next one recursively
		fireRocket()
		return
	end

	-- Determine launch CFrame (position + direction)
	local launchCF
	local spawnChild = getRocketSpawnChild()

	if weldActive and RootPart and RootPart.Parent and spawnChild then
		-- Use the marker's world CFrame — its LookVector (front face / decal direction) is the fire direction
		launchCF = RootPart.CFrame * spawnChild.offset
	else
		local hrp = getRoot()
		if not hrp then return end
		launchCF = hrp.CFrame * CFrame.new(0, 0, -3)
	end

	-- Unanchor everything in the rocket
	if rocket.raw and rocket.raw:IsA("Model") then
		for _, p in ipairs(rocket.raw:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.AssemblyLinearVelocity = Vector3.zero
				p.AssemblyAngularVelocity = Vector3.zero
			end
		end
	else
		bp.Anchored = false
	end

	-- Teleport to launch position
	bp.CFrame = launchCF
	bp.AssemblyLinearVelocity = Vector3.zero
	bp.AssemblyAngularVelocity = Vector3.zero

	local direction = launchCF.LookVector
	local speed = Options.RocketSpeed and Options.RocketSpeed.Value or 200
	local lifetime = Options.RocketLifetime and Options.RocketLifetime.Value or 5
	local startTime = tick()
	local exploded = false

	-- Touched-based explosion for BombMissile
	local touchConn = nil
	local isBomb = rocket.raw and rocket.raw.Name == "BombMissile"
	local shouldExplode = Toggles.RocketExplode and Toggles.RocketExplode.Value

	if isBomb and shouldExplode then
		-- Connect Touched on all BaseParts in the rocket
		local function onTouched(hit)
			if exploded then return end
			-- Ignore touches with our own build parts or other rockets
			if hit:IsDescendantOf(rocket.raw) then return end
			-- Ignore our own character
			local char = LP.Character
			if char and hit:IsDescendantOf(char) then return end

			exploded = true
			if touchConn then touchConn:Disconnect() end

			explodeRocket(rocket.raw, bp.Position)
		end

		-- Find the main collidable part (Body or bp)
		local touchPart = rocket.raw:FindFirstChild("Body", true) or bp
		if touchPart and touchPart:IsA("BasePart") then
			touchConn = touchPart.Touched:Connect(onTouched)
		end
	end

	-- Heartbeat flight loop
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if exploded or not bp or not bp.Parent then
			conn:Disconnect()
			if touchConn then touchConn:Disconnect() end
			return
		end

		bp.CFrame = bp.CFrame + direction * speed * dt
		bp.AssemblyLinearVelocity = Vector3.new(0, 0.01, 0)
		bp.AssemblyAngularVelocity = Vector3.zero

		if tick() - startTime > lifetime then
			conn:Disconnect()
			if touchConn then touchConn:Disconnect() end
			-- Explode on timeout too if it's a bomb
			if isBomb and shouldExplode and not exploded then
				exploded = true
				explodeRocket(rocket.raw, bp.Position)
			elseif Remotes.DestroyToy and rocket.raw and rocket.raw.Parent then
				Remotes.DestroyToy:FireServer(rocket.raw)
			end
		end
	end)

	table.insert(ActiveRockets, { part = bp, raw = rocket.raw, conn = conn, startTime = startTime })
	RocketStockLabel:SetText("Stockpile: " .. #RocketStockpile .. " rockets ready")
end

-- C key to fire
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.C then
		fireRocket()
	end
end)

-- Background cleanup loop for active rockets + label updates
task.spawn(function()
	while task.wait(1) do
		for i = #ActiveRockets, 1, -1 do
			local r = ActiveRockets[i]
			if not r.part or not r.part.Parent then
				if r.conn then r.conn:Disconnect() end
				table.remove(ActiveRockets, i)
			end
		end
		RocketActiveLabel:SetText("Active: " .. #ActiveRockets .. " | Stockpile: " .. #RocketStockpile)
		RocketStockLabel:SetText("Stockpile: " .. #RocketStockpile .. " rockets ready")
	end
end)

-- ============================================================
-- [[ 18. BUTTON SYSTEM UI ]]
-- ============================================================

RocketRight:AddDivider()
RocketRight:AddLabel({
	Text     = "--- Buttons ---",
	DoesWrap = false,
})

RocketRight:AddSlider("ButtonCooldown", {
	Text     = "Button Cooldown",
	Default  = 1,
	Min      = 0.2,
	Max      = 5,
	Rounding = 1,
	Suffix   = " sec",
	Tooltip  = "Cooldown between button presses (per button)",
})

RocketRight:AddLabel({
	Text     = "Buttons use BellSmall toys.\nAdd tag in JSON to link:\n  tag: Rocket = fire rocket\n  tag: Explode = boom\nAnyone grabbing the bell\ntriggers the action!",
	DoesWrap = true,
})

-- ============================================================
-- [[ 19. UI SETTINGS (ThemeManager + SaveManager) ]]
-- ============================================================

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PalletWelder")
ThemeManager:ApplyToTab(Tabs.UISettings)
ThemeManager:ApplyTheme("Catppuccin")

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("PalletWelder")
SaveManager:BuildConfigSection(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()
