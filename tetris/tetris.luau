-- TETRIS MOVEMENT TEST
-- Step 1: Spawn block, save it
-- Step 2: Get block's Body CFrame, TP onto it, grab it, KEEP grab active
-- Step 3: While grabbed — unanchor, move down, reanchor
-- Step 4: Release grab, TP back
-- Repeat step 2-4 for each move

local LP  = game:GetService("Players").LocalPlayer
local RS  = game:GetService("ReplicatedStorage")

local repo    = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title         = "Block Test",
    Footer        = "movement test",
    AutoShow      = true,
    Center        = true,
    ToggleKeybind = Enum.KeyCode.RightShift,
})

local function Notify(t, d) Library:Notify({ Title = t, Description = d or "", Time = 3 }) end

-- Remotes
local GrabEvents, SpawnToyRF, DestroyToyRE
task.spawn(function()
    local GE = RS:WaitForChild("GrabEvents", 10)
    if GE then
        GrabEvents = {
            Create  = GE:WaitForChild("CreateGrabLine"),
            Destroy = GE:WaitForChild("DestroyGrabLine"),
        }
    end
    local MT = RS:WaitForChild("MenuToys", 10)
    if MT then
        SpawnToyRF  = MT:WaitForChild("SpawnToyRemoteFunction")
        DestroyToyRE = MT:WaitForChild("DestroyToy")
    end
end)

local function getRoot()
    return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
end

-- The one saved block
local savedBlock = nil

-- ============================================================
-- STEP 1: Spawn block, save reference
-- ============================================================
local function spawnBlock()
    local hrp = getRoot()
    if not hrp or not SpawnToyRF then Notify("Error", "not ready"); return end

    -- Spawn 10 studs in front of player
    local spawnPos = hrp.CFrame * CFrame.new(0, 0, -10)

    -- TP to spawn point so server range check passes
    local savedHRP = hrp.CFrame
    hrp.CFrame = spawnPos * CFrame.new(0, 3, 0)
    task.wait(0.2)

    -- Hook ChildAdded BEFORE invoke so we don't miss it
    local folderName = LP.Name .. "SpawnedInToys"
    local folder = workspace:FindFirstChild(folderName)
                   or workspace:WaitForChild(folderName, 8)
    local toy = nil
    local conn = folder and folder.ChildAdded:Connect(function(c)
        if c.Name == "TetracubeT" then toy = c end
    end)

    pcall(function()
        SpawnToyRF:InvokeServer("TetracubeT", spawnPos, Vector3.zero)
    end)

    -- Scan existing in case ChildAdded already fired
    if folder and not toy then
        for _, c in ipairs(folder:GetChildren()) do
            if c.Name == "TetracubeT" then toy = c; break end
        end
    end

    -- Wait up to 3s for toy to appear
    local t = tick()
    repeat task.wait(0.05) until toy or tick() - t > 3
    if conn then conn:Disconnect() end

    -- Restore HRP
    hrp.CFrame = savedHRP
    task.wait(0.05)

    if not toy then Notify("Error", "block didnt spawn"); return end

    -- Wait for Body child to replicate
    local body = toy:FindFirstChild("Body")
    if not body then
        local ok, result = pcall(function() return toy:WaitForChild("Body", 3) end)
        body = ok and result or nil
    end

    if not body then Notify("Error", "no Body part found"); return end

    savedBlock = toy
    Notify("Step 1", "Block spawned! Body at " .. tostring(body.Position))
end

-- ============================================================
-- STEP 2-4: Grab block at its exact position, move it down, release
-- ============================================================
local function moveBlockDown()
    if not savedBlock then Notify("Error", "no block spawned yet"); return end

    local hrp = getRoot()
    if not hrp or not GrabEvents then Notify("Error", "not ready"); return end

    -- Get Body — the actual part we grab
    local body = savedBlock:FindFirstChild("Body")
    if not body then Notify("Error", "Body missing"); return end

    -- STEP 2: TP HRP to exact Body position + 3 studs up
    local savedHRP = hrp.CFrame
    hrp.CFrame = CFrame.new(body.Position + Vector3.new(0, 3, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.2)  -- server sees HRP next to Body

    -- Grab Body at its exact CFrame — keep grab active the whole move
    GrabEvents.Create:FireServer(body, body.CFrame)
    task.wait(0.2)  -- server grants ownership

    -- STEP 3: while grabbed — unanchor, move down 2 studs, reanchor
    for _, p in ipairs(savedBlock:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = false end
    end
    task.wait(0.05)

    -- Move every part down 2 studs
    for _, p in ipairs(savedBlock:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CFrame = p.CFrame * CFrame.new(0, -2, 0)
        end
    end
    task.wait(0.1)  -- server replicates the move

    for _, p in ipairs(savedBlock:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true end
    end
    task.wait(0.05)

    -- STEP 4: release grab, TP back
    GrabEvents.Destroy:FireServer(body)
    task.wait(0.05)

    hrp.CFrame = savedHRP
    hrp.AssemblyLinearVelocity = Vector3.zero

    Notify("Moved!", "block moved down 2 studs")
end

-- ============================================================
-- UI
-- ============================================================

local Tab  = Window:AddTab("Test", "play")
local Left = Tab:AddLeftGroupbox("Controls", "box")

Left:AddButton({
    Text = "1. Spawn Block",
    Func = function() task.spawn(spawnBlock) end,
})

Left:AddDivider()

Left:AddButton({
    Text    = "2. Move Down",
    Tooltip = "Grabs body, moves down 2 studs, releases",
    Func    = function() task.spawn(moveBlockDown) end,
})

Left:AddDivider()

Left:AddButton({
    Text = "Destroy Block",
    Func = function()
        if savedBlock and DestroyToyRE then
            pcall(function() DestroyToyRE:FireServer(savedBlock) end)
            savedBlock = nil
        end
    end,
})

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("TetrisTest")
ThemeManager:ApplyToTab(Tab)

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("TetrisTest")

Notify("Loaded", "Press 'Spawn Block' then 'Move Down'")
