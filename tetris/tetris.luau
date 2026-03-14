-- TETRIS BLOCK MOVEMENT TEST
-- Based on confirmed working pattern from research/VerbalHub.luau:
--   1. Grab Body immediately on ChildAdded (no HRP TP needed at spawn)
--   2. Wait for PartOwner value to confirm server granted ownership
--   3. To move: TP HRP point-blank, re-grab, wait, SetPrimaryPartCFrame, anchor, release, TP back

local LP  = game:GetService("Players").LocalPlayer
local RS  = game:GetService("ReplicatedStorage")

local repo         = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title         = "Block Test",
    Footer        = "movement test",
    AutoShow      = true,
    Center        = true,
    ToggleKeybind = Enum.KeyCode.RightShift,
})

local function Notify(t, d) Library:Notify({ Title = t, Description = d or "", Time = 4 }) end

-- ============================================================
-- REMOTES
-- ============================================================

local CreateGrabLine, DestroyGrabLine, SpawnToyRF, DestroyToyRE

task.spawn(function()
    local GE = RS:WaitForChild("GrabEvents", 10)
    if GE then
        CreateGrabLine  = GE:WaitForChild("CreateGrabLine")
        DestroyGrabLine = GE:WaitForChild("DestroyGrabLine")
    end
    local MT = RS:WaitForChild("MenuToys", 10)
    if MT then
        SpawnToyRF   = MT:WaitForChild("SpawnToyRemoteFunction")
        DestroyToyRE = MT:WaitForChild("DestroyToy")
    end
end)

local function getRoot()
    return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
end

-- The saved block
local savedBlock = nil  -- the Model
local savedBody  = nil  -- the Body BasePart inside the model

-- ============================================================
-- STEP 1: Spawn block, grab immediately on ChildAdded,
--         wait for PartOwner to confirm ownership
-- ============================================================

local function spawnBlock()
    if not SpawnToyRF or not CreateGrabLine then
        Notify("Error", "remotes not ready yet")
        return
    end
    local hrp = getRoot()
    if not hrp then Notify("Error", "no character"); return end

    -- Spawn position: 10 studs in front of player at ground level
    local spawnCF = hrp.CFrame * CFrame.new(0, 0, -10)

    -- Get/wait for toy folder
    local folderName = LP.Name .. "SpawnedInToys"
    local folder = workspace:FindFirstChild(folderName)
                   or workspace:WaitForChild(folderName, 8)
    if not folder then Notify("Error", "toy folder not found"); return end

    -- Snapshot existing TetracubeT toys so we can find the NEW one
    local before = {}
    for _, c in ipairs(folder:GetChildren()) do
        if c.Name == "TetracubeT" then before[c] = true end
    end

    local toy  = nil
    local body = nil

    -- Hook ChildAdded BEFORE InvokeServer — no race condition
    local conn = folder.ChildAdded:Connect(function(child)
        if child.Name == "TetracubeT" and not before[child] then
            toy = child

            -- Get Body — wait for it to replicate
            local b = child:FindFirstChild("Body")
            if not b then
                local ok, res = pcall(function() return child:WaitForChild("Body", 3) end)
                b = ok and res or nil
            end
            if not b then return end
            body = b

            -- Grab Body IMMEDIATELY at its own CFrame
            -- No HRP TP needed: server just spawned the toy near our player
            pcall(function()
                CreateGrabLine:FireServer(body, body.CFrame)
            end)
        end
    end)

    -- Spawn the toy (blocks this thread — we're already in task.spawn context)
    pcall(function()
        SpawnToyRF:InvokeServer("TetracubeT", spawnCF, Vector3.zero)
    end)
    conn:Disconnect()

    -- If ChildAdded didn't catch it, scan for the new toy now
    if not toy then
        for _, c in ipairs(folder:GetChildren()) do
            if c.Name == "TetracubeT" and not before[c] then
                toy = c
                body = toy:FindFirstChild("Body")
                if body then
                    pcall(function()
                        CreateGrabLine:FireServer(body, body.CFrame)
                    end)
                end
                break
            end
        end
    end

    if not toy or not body then
        Notify("Error", "block or Body not found")
        return
    end

    -- Wait for PartOwner value to appear in Body — this is the server confirming ownership
    local partOwner = body:WaitForChild("PartOwner", 3)
    if not partOwner then
        Notify("Warn", "PartOwner not found — may still work")
    elseif partOwner.Value ~= LP.Name then
        Notify("Warn", "PartOwner is '" .. tostring(partOwner.Value) .. "' not us!")
    else
        Notify("Step 1 OK", "Owned! PartOwner = " .. partOwner.Value)
    end

    -- Anchor all parts now that we own it
    for _, p in ipairs(toy:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true end
    end

    -- Release grab (keep network ownership)
    pcall(function() DestroyGrabLine:FireServer(body) end)

    savedBlock = toy
    savedBody  = body
    Notify("Block saved", "ready to move!")
end

-- ============================================================
-- STEP 2-4: Re-grab, move, anchor, release
-- ============================================================

local function moveBlock(offsetCF)
    if not savedBlock or not savedBody then
        Notify("Error", "no block saved yet")
        return
    end
    local hrp = getRoot()
    if not hrp then Notify("Error", "no character"); return end

    local body = savedBody

    -- 1. TP HRP right above Body's current position
    local savedHRP = hrp.CFrame
    hrp.CFrame = CFrame.new(body.Position + Vector3.new(0, 3, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero

    -- 2. Wait — server sees HRP next to Body
    task.wait(0.2)

    -- 3. Re-grab Body at its exact CFrame to refresh ownership
    pcall(function()
        CreateGrabLine:FireServer(body, body.CFrame)
    end)

    -- 4. Wait — server grants/refreshes ownership
    task.wait(0.2)

    -- 5. Unanchor
    for _, p in ipairs(savedBlock:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = false end
    end
    task.wait(0.05)

    -- 6. Move using SetPrimaryPartCFrame (confirmed working in VerbalHub reference)
    local newCF = savedBlock:GetPrimaryPartCFrame() * offsetCF
    savedBlock:SetPrimaryPartCFrame(newCF)

    -- 7. Wait — server replicates the move
    task.wait(0.2)

    -- 8. Anchor all parts
    for _, p in ipairs(savedBlock:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true end
    end
    task.wait(0.05)

    -- 9. Release grab (keep net ownership)
    pcall(function() DestroyGrabLine:FireServer(body) end)
    task.wait(0.05)

    -- 10. TP HRP back
    hrp.CFrame = savedHRP
    hrp.AssemblyLinearVelocity = Vector3.zero

    Notify("Moved", "offset: " .. tostring(offsetCF))
end

-- ============================================================
-- UI
-- ============================================================

local Tab  = Window:AddTab("Test", "play")
local Left = Tab:AddLeftGroupbox("Controls", "box")

Left:AddButton({
    Text    = "1. Spawn Block",
    Tooltip = "Spawns TetracubeT and grabs it immediately",
    Func    = function() task.spawn(spawnBlock) end,
})

Left:AddDivider()

Left:AddButton({
    Text    = "2. Move Down",
    Tooltip = "Re-grabs, moves block down 2 studs, releases",
    Func    = function()
        task.spawn(function()
            moveBlock(CFrame.new(0, -2, 0))
        end)
    end,
})

Left:AddButton({
    Text    = "Move Forward",
    Tooltip = "Moves block 2 studs forward (Z+)",
    Func    = function()
        task.spawn(function()
            moveBlock(CFrame.new(0, 0, 2))
        end)
    end,
})

Left:AddButton({
    Text    = "Move Back",
    Tooltip = "Moves block 2 studs back (Z-)",
    Func    = function()
        task.spawn(function()
            moveBlock(CFrame.new(0, 0, -2))
        end)
    end,
})

Left:AddDivider()

Left:AddButton({
    Text  = "Destroy Block",
    Risky = true,
    Func  = function()
        if savedBlock and DestroyToyRE then
            pcall(function() DestroyToyRE:FireServer(savedBlock) end)
            savedBlock = nil
            savedBody  = nil
        end
    end,
})

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("TetrisTest")
ThemeManager:ApplyToTab(Tab)

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("TetrisTest")

Notify("Loaded", "Press '1. Spawn Block' first")
