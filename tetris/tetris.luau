--[[
████████╗███████╗████████╗██████╗ ██╗███████╗
╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██║██╔════╝
   ██║   █████╗     ██║   ██████╔╝██║███████╗
   ██║   ██╔══╝     ██║   ██╔══██╗██║╚════██║
   ██║   ███████╗   ██║   ██║  ██║██║███████║
   ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝
  FTAP Tetris | Obsidian UI | Flat Ground Edition
--]]

-- ============================================================
-- [[ 1. SERVICES ]]
-- ============================================================

local LP         = game:GetService("Players").LocalPlayer
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenSvc   = game:GetService("TweenService")
local Workspace  = workspace

-- ============================================================
-- [[ 2. OBSIDIAN UI ]]
-- ============================================================

local repo         = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options

local Window = Library:CreateWindow({
    Title         = "FTAP Tetris",
    Footer        = "flat ground edition",
    NotifySide    = "Right",
    AutoShow      = true,
    Center        = true,
    ToggleKeybind = Enum.KeyCode.RightShift,
})

local function Notify(title, desc, t)
    Library:Notify({ Title = title, Description = desc or "", Time = t or 3 })
end

-- ============================================================
-- [[ 3. REMOTES ]]
-- ============================================================

local Remotes = {}
task.spawn(function()
    local GE = RS:WaitForChild("GrabEvents", 10)
    if GE then
        Remotes.CreateGrabLine  = GE:FindFirstChild("CreateGrabLine")
        Remotes.SetNetworkOwner = GE:FindFirstChild("SetNetworkOwner")
        Remotes.DestroyGrabLine = GE:FindFirstChild("DestroyGrabLine")
    end
    local MT = RS:WaitForChild("MenuToys", 10)
    if MT then
        Remotes.SpawnToy   = MT:FindFirstChild("SpawnToyRemoteFunction")
        Remotes.DestroyToy = MT:FindFirstChild("DestroyToy")
    end
end)

-- ============================================================
-- [[ 4. HELPERS ]]
-- ============================================================

local function getRoot()
    return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    return LP.Character and LP.Character:FindFirstChild("Humanoid")
end

local function getToyFolder()
    return Workspace:FindFirstChild(LP.Name .. "SpawnedInToys")
end

local function waitForToyFolder(timeout)
    timeout = timeout or 8
    local folder = getToyFolder()
    if folder then return folder end
    local ok, result = pcall(function()
        return Workspace:WaitForChild(LP.Name .. "SpawnedInToys", timeout)
    end)
    return ok and result or nil
end

-- ============================================================
-- [[ 5. BOARD CONSTANTS ]]
-- ============================================================

local COLS       = 9
local ROWS       = 9
local BLOCK_SIZE = 2  -- studs per cell

-- Each Tetracube is one single toy that occupies grid cells.
-- The shapes below define which cells are blocked for collision.
-- All pieces are treated as a single model — one toy per piece.
local PIECE_SHAPES = {
    TetracubeI = {{0,0},{1,0},{2,0},{3,0}},
    TetracubeO = {{0,0},{1,0},{0,1},{1,1}},
    TetracubeT = {{0,0},{1,0},{2,0},{1,1}},
    TetracubeS = {{1,0},{2,0},{0,1},{1,1}},
    TetracubeZ = {{0,0},{1,0},{1,1},{2,1}},
    TetracubeL = {{0,0},{1,0},{2,0},{2,1}},
    TetracubeJ = {{0,0},{1,0},{2,0},{0,1}},
}

local PIECE_NAMES = {
    "TetracubeI","TetracubeO","TetracubeT",
    "TetracubeS","TetracubeZ","TetracubeL","TetracubeJ"
}

local function pieceMaxDcol(name)
    local max = 0
    for _, o in ipairs(PIECE_SHAPES[name] or {}) do
        if o[1] > max then max = o[1] end
    end
    return max
end

-- ============================================================
-- [[ 6. GAME STATE ]]
-- ============================================================

local S = { running = false, gameOver = false }

local Grid = {}
local function clearGrid()
    Grid = {}
    for r = 0, ROWS - 1 do Grid[r] = {} end
end
clearGrid()

local Active      = { model = nil, name = "", col = 3, row = 0 }
local LandedModels = {}
local BorderModels = {}
local BoardOrigin  = nil
local fallConn     = nil
local fallTimer    = 0
local advancing    = false
local origCamType  = nil
local linesCleared = 0

local LblState, LblPiece, LblCol, LblRow, LblLines
local startBtn

-- ============================================================
-- [[ 7. COORDINATE SYSTEM ]]
-- ============================================================

-- FLAT_ROT: lay the Tetracube model flat on the ground (XZ plane).
-- Baked into every spawn CFrame. After spawn, the model's PrimaryPart
-- CFrame already includes this rotation, so setModelCFrame preserves it.
local FLAT_ROT = CFrame.Angles(-math.pi / 2, 0, 0)

local function gridToWorld(col, row)
    if not BoardOrigin then return CFrame.new() end
    local x = (col + 0.5) * BLOCK_SIZE
    local z = (row + 0.5) * BLOCK_SIZE
    return BoardOrigin * CFrame.new(x, 0, z) * FLAT_ROT
end

-- ============================================================
-- [[ 8. GRID QUERIES ]]
-- ============================================================

local function isCellBlocked(col, row)
    if col < 0 or col >= COLS then return true end
    if row >= ROWS             then return true end
    if row < 0                 then return false end
    return Grid[row][col] ~= nil
end

local function getPieceCells(col, row, name)
    local cells = {}
    for _, o in ipairs(PIECE_SHAPES[name] or {}) do
        table.insert(cells, { col + o[1], row + o[2] })
    end
    return cells
end

local function canMoveLeft()
    if not Active.model then return false end
    for _, c in ipairs(getPieceCells(Active.col, Active.row, Active.name)) do
        if isCellBlocked(c[1]-1, c[2]) then return false end
    end
    return true
end

local function canMoveRight()
    if not Active.model then return false end
    for _, c in ipairs(getPieceCells(Active.col, Active.row, Active.name)) do
        if isCellBlocked(c[1]+1, c[2]) then return false end
    end
    return true
end

local function canAdvance()
    if not Active.model then return false end
    for _, c in ipairs(getPieceCells(Active.col, Active.row, Active.name)) do
        if isCellBlocked(c[1], c[2]+1) then return false end
    end
    return true
end

-- ============================================================
-- [[ 9. REPLICATION CORE ]]
-- ============================================================

-- Step 1: Anchor every BasePart so physics engine won't fight our CFrame writes.
--         This MUST happen before any CFrame assignment.
local function anchorModel(model)
    if not model then return end
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true end
    end
end

-- Step 2: Move every BasePart directly by offset from PrimaryPart.
--         Never use SetPrimaryPartCFrame (triggers physics, causes flicker).
--         Model must be anchored first.
local function setModelCFrame(model, targetCF)
    if not model then return end
    local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not primary then return end

    if model.PrimaryPart then
        local invPrimary = primary.CFrame:Inverse()
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CFrame = targetCF * (invPrimary * p.CFrame)
            end
        end
    else
        primary.CFrame = targetCF
    end
end

-- Step 3: Claim network ownership.
--         TP HRP point-blank (range check), fire grab remotes, restore HRP.
--         Only called once per action (spawn / move / lock), NOT every frame.
local savedHRPCF = nil  -- global save so nested calls don't clobber it

local function claimOwnership(model)
    if not model then return end
    local hrp  = getRoot()
    if not hrp then return end
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not part then return end

    -- Save position if not already saved by a parent call
    local isMine = (savedHRPCF == nil)
    if isMine then savedHRPCF = hrp.CFrame end

    hrp.CFrame = part.CFrame * CFrame.new(0, 3, 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.06)

    pcall(function()
        if Remotes.CreateGrabLine  then Remotes.CreateGrabLine:FireServer(part, part.CFrame)  end
        if Remotes.SetNetworkOwner then Remotes.SetNetworkOwner:FireServer(part, part.CFrame) end
        if Remotes.DestroyGrabLine then Remotes.DestroyGrabLine:FireServer(part)              end
    end)
    task.wait(0.04)

    if isMine then
        hrp.CFrame = savedHRPCF
        hrp.AssemblyLinearVelocity = Vector3.zero
        savedHRPCF = nil
    end
end

-- ============================================================
-- [[ 10. APPLY PIECE POSITION ]]
-- ============================================================

-- Full move sequence: claim → anchor → set CFrame.
-- The anchor is already set from spawn, but we call again for safety.
local function applyPieceCFrame()
    if not Active.model then return end
    local target = gridToWorld(Active.col, Active.row)
    anchorModel(Active.model)      -- ensure anchored
    claimOwnership(Active.model)   -- TP point-blank, grab, restore
    setModelCFrame(Active.model, target)
end

-- ============================================================
-- [[ 11. STATUS LABELS ]]
-- ============================================================

local function updateStatus()
    if LblState then LblState:SetText(S.gameOver and "GAME OVER ✗" or S.running and "Running ▶" or "Stopped ■") end
    if LblPiece then LblPiece:SetText("Piece: " .. (Active.name ~= "" and Active.name:gsub("Tetracube","") or "---")) end
    if LblCol   then LblCol:SetText(  "Col:   " .. (Active.model and tostring(Active.col) or "---")) end
    if LblRow   then LblRow:SetText(  "Row:   " .. (Active.model and tostring(Active.row) or "---")) end
    if LblLines then LblLines:SetText("Lines: " .. tostring(linesCleared)) end
end

-- ============================================================
-- [[ 12. SPAWN HELPER ]]
-- ============================================================

-- Spawns a single toy at a world CFrame.
-- IMPORTANT: This BLOCKS the calling thread (no task.spawn wrapper around InvokeServer).
-- The caller must already be running in a task.spawn context.
-- We TP the HRP to the spawn point first so the server range check passes.
local function spawnToyAt(name, cf, retries)
    if not Remotes.SpawnToy then return nil end
    retries = retries or 3

    local hrp   = getRoot()
    local saved = hrp and hrp.CFrame

    for attempt = 1, retries do
        -- TP to spawn point
        if hrp then
            hrp.CFrame = CFrame.new(cf.Position + Vector3.new(0, 3, 0))
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.06)
        end

        -- Get or wait for toy folder
        local folder = waitForToyFolder(6)
        local toy    = nil

        -- Connect ChildAdded BEFORE InvokeServer to avoid race condition
        local conn
        if folder then
            conn = folder.ChildAdded:Connect(function(child)
                if child.Name == name then toy = child end
            end)
        end

        -- InvokeServer blocks — that's correct, gives server time to create toy
        pcall(function()
            Remotes.SpawnToy:InvokeServer(name, cf, Vector3.zero)
        end)

        -- Folder might have been created by first InvokeServer
        if not folder then
            folder = waitForToyFolder(4)
            if folder then
                conn = folder.ChildAdded:Connect(function(child)
                    if child.Name == name then toy = child end
                end)
            end
        end

        -- Scan existing children (toy may have arrived during InvokeServer)
        if folder and not toy then
            for _, child in ipairs(folder:GetChildren()) do
                if child.Name == name then toy = child; break end
            end
        end

        -- Wait a bit more for replication lag
        local t = tick()
        repeat task.wait(0.05) until toy or (tick() - t > 2)
        if conn then conn:Disconnect() end

        -- Restore HRP before returning
        if hrp and saved then
            hrp.CFrame = saved
            hrp.AssemblyLinearVelocity = Vector3.zero
        end

        if toy then return toy end
        Notify("Tetris", "Spawn attempt " .. attempt .. " failed, retrying...", 2)
        task.wait(0.3)
    end

    -- Final restore
    if hrp and saved then
        hrp.CFrame = saved
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    return nil
end

-- ============================================================
-- [[ 13. BOARD SETUP ]]
-- ============================================================

local function initBoard()
    local hrp = getRoot()
    if not hrp then return false end

    -- Board origin: 18 studs in front of player at ground level.
    -- BoardOrigin.RightVector = +col, BoardOrigin.LookVector = +row (toward player).
    local fwd     = hrp.CFrame.LookVector
    fwd           = Vector3.new(fwd.X, 0, fwd.Z).Unit
    local groundY = hrp.Position.Y - 3

    local pos = Vector3.new(
        hrp.Position.X + fwd.X * 18,
        groundY,
        hrp.Position.Z + fwd.Z * 18
    )
    local yaw = math.atan2(fwd.X, fwd.Z)
    BoardOrigin = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

    -- U-shaped border (open top):
    --   Left column  (3 pallets, each ~6 studs, running along Z/row axis)
    --   Right column (3 pallets, same)
    --   Bottom row   (3 pallets, running along X/col axis, player-near side)
    local PS = 6  -- pallet size in studs
    local bw = COLS * BLOCK_SIZE   -- 18 studs total board width
    local bd = ROWS * BLOCK_SIZE   -- 18 studs total board depth

    local borders = {}
    for i = 0, 2 do
        local zOff = (i + 0.5) * PS
        -- Left wall
        table.insert(borders, BoardOrigin * CFrame.new(-PS * 0.5, 0, zOff) * FLAT_ROT)
        -- Right wall
        table.insert(borders, BoardOrigin * CFrame.new(bw + PS * 0.5, 0, zOff) * FLAT_ROT)
    end
    -- Bottom / player-near row
    for i = 0, 2 do
        local xOff = (i + 0.5) * PS
        table.insert(borders, BoardOrigin * CFrame.new(xOff, 0, bd + PS * 0.5) * FLAT_ROT)
    end

    BorderModels = {}
    for i, cf in ipairs(borders) do
        local m = spawnToyAt("PalletLightBrown", cf, 3)
        if m then
            anchorModel(m)
            setModelCFrame(m, cf)
            claimOwnership(m)   -- own the border so it stays anchored serverside
            table.insert(BorderModels, m)
            Notify("Tetris", "Border " .. i .. "/9 OK", 1)
        else
            Notify("Tetris", "Border " .. i .. " failed (skipping)", 2)
        end
    end

    return true
end

-- ============================================================
-- [[ 14. DESTROY HELPER ]]
-- ============================================================

local function destroyModel(model)
    if not model then return end
    pcall(function()
        if Remotes.DestroyToy then
            -- Find the nil-instance reference by DebugId for DestroyToy
            local realRef = model
            local ok, dbgId = pcall(function() return model:GetDebugId() end)
            if ok and dbgId then
                for _, obj in ipairs(getnilinstances()) do
                    local match = pcall(function()
                        return obj.Name == model.Name and obj:GetDebugId() == dbgId
                    end)
                    if match then realRef = obj; break end
                end
            end
            Remotes.DestroyToy:FireServer(realRef)
        else
            model:Destroy()
        end
    end)
end

local function teardownBoard()
    if Active.model then destroyModel(Active.model); Active.model = nil end
    for _, m in ipairs(LandedModels) do destroyModel(m) end
    LandedModels = {}
    for _, m in ipairs(BorderModels) do destroyModel(m) end
    BorderModels = {}
    BoardOrigin  = nil
end

-- ============================================================
-- [[ 15. PIECE SPAWNING ]]
-- ============================================================

local function spawnPiece()
    if not Remotes.SpawnToy then return false end

    local name     = PIECE_NAMES[math.random(1, #PIECE_NAMES)]
    local maxDcol  = pieceMaxDcol(name)
    local startCol = math.floor((COLS - (maxDcol + 1)) / 2)
    local startRow = 0

    -- Game over check
    for _, c in ipairs(getPieceCells(startCol, startRow, name)) do
        if c[2] >= 0 and isCellBlocked(c[1], c[2]) then return false end
    end

    local spawnCF = gridToWorld(startCol, startRow)
    local toy = spawnToyAt(name, spawnCF, 3)

    -- Fallback to another piece type if this one fails
    if not toy then
        for _, fallback in ipairs(PIECE_NAMES) do
            if fallback ~= name then
                toy = spawnToyAt(fallback, spawnCF, 2)
                if toy then name = fallback; break end
            end
        end
    end

    if not toy then
        Notify("Tetris", "Piece spawn failed after all retries!", 4)
        return false
    end

    Active.model = toy
    Active.name  = name
    Active.col   = startCol
    Active.row   = startRow

    -- Anchor + claim + place the piece
    anchorModel(toy)
    claimOwnership(toy)
    setModelCFrame(toy, spawnCF)
    updateStatus()
    return true
end

-- ============================================================
-- [[ 16. LOCK & LINE CLEAR ]]
-- ============================================================

local function lockPiece()
    if not Active.model then return end
    anchorModel(Active.model)
    for _, c in ipairs(getPieceCells(Active.col, Active.row, Active.name)) do
        local col, row = c[1], c[2]
        if row >= 0 and row < ROWS and col >= 0 and col < COLS then
            Grid[row][col] = Active.model
        end
    end
    table.insert(LandedModels, Active.model)
    Active.model = nil
    Active.name  = ""
end

local function rowIsFull(r)
    for c = 0, COLS - 1 do
        if not Grid[r][c] then return false end
    end
    return true
end

local function compactAbove(clearedRow)
    for r = clearedRow - 1, 0, -1 do
        for c = 0, COLS - 1 do
            if Grid[r][c] then
                local model   = Grid[r][c]
                Grid[r+1][c] = model
                Grid[r][c]   = nil
                -- Shift model 1 row toward player (along +LookVector)
                local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if part then
                    claimOwnership(model)
                    local shift = BoardOrigin.LookVector * BLOCK_SIZE
                    -- Build a new CFrame shifted by one row, preserving rotation
                    local newCF = CFrame.new(part.CFrame.Position + shift)
                                  * CFrame.fromMatrix(Vector3.zero,
                                      part.CFrame.RightVector,
                                      part.CFrame.UpVector,
                                      part.CFrame.LookVector)
                    setModelCFrame(model, newCF)
                end
            end
        end
    end
end

local function clearLines()
    local cleared = 0
    for r = ROWS - 1, 0, -1 do
        if rowIsFull(r) then
            local done = {}
            for c = 0, COLS - 1 do
                local m = Grid[r][c]
                if m and not done[m] then
                    done[m] = true
                    destroyModel(m)
                    for i = #LandedModels, 1, -1 do
                        if LandedModels[i] == m then table.remove(LandedModels, i); break end
                    end
                end
                Grid[r][c] = nil
            end
            compactAbove(r)
            cleared      = cleared + 1
            linesCleared = linesCleared + 1
        end
    end
    if cleared > 0 then
        Notify("Tetris", cleared .. " line" .. (cleared > 1 and "s" or "") .. " cleared! ✓", 2)
        updateStatus()
    end
end

-- ============================================================
-- [[ 17. PIECE MOVEMENT ]]
-- ============================================================

local function movePieceLeft()
    if not Active.model or not S.running then return end
    if not canMoveLeft() then return end
    Active.col = Active.col - 1
    applyPieceCFrame()
    updateStatus()
end

local function movePieceRight()
    if not Active.model or not S.running then return end
    if not canMoveRight() then return end
    Active.col = Active.col + 1
    applyPieceCFrame()
    updateStatus()
end

local function advancePiece()
    if not Active.model then return false end
    if canAdvance() then
        Active.row = Active.row + 1
        applyPieceCFrame()
        updateStatus()
        return true
    end
    return false
end

-- ============================================================
-- [[ 18. FALL LOOP ]]
-- ============================================================

local function onHeartbeat(dt)
    if not S.running or not Active.model then return end
    if advancing then return end

    fallTimer = fallTimer + dt
    local speed = Options.FallSpeed and Options.FallSpeed.Value or 1.5

    if fallTimer >= speed then
        fallTimer = 0
        advancing = true
        task.spawn(function()
            local moved = advancePiece()
            if not moved then
                lockPiece()
                clearLines()
                local ok = spawnPiece()
                if not ok then
                    S.running  = false
                    S.gameOver = true
                    if fallConn then fallConn:Disconnect(); fallConn = nil end
                    updateStatus()
                    if startBtn then startBtn:SetText("▶ START") end
                    Notify("Tetris", "GAME OVER!  Lines: " .. linesCleared, 7)
                end
            end
            advancing = false
        end)
    end
end

-- ============================================================
-- [[ 19. CAMERA ]]
-- ============================================================

local function setCameraOverhead()
    origCamType = Workspace.CurrentCamera.CameraType
    if not BoardOrigin then return end
    local center = (BoardOrigin * CFrame.new(COLS*BLOCK_SIZE/2, 0, ROWS*BLOCK_SIZE/2)).Position
    local camPos = center + Vector3.new(0, 30, 0) - BoardOrigin.LookVector * 10
    Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
    TweenSvc:Create(Workspace.CurrentCamera,
        TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
        { CFrame = CFrame.lookAt(camPos, center) }
    ):Play()
end

local function restoreCamera()
    Workspace.CurrentCamera.CameraType = origCamType or Enum.CameraType.Custom
    local hum = getHum()
    if hum then Workspace.CurrentCamera.CameraSubject = hum end
end

-- ============================================================
-- [[ 20. GAME CONTROL ]]
-- ============================================================

local function startGame()
    if S.running then return end
    if not Remotes.SpawnToy then Notify("Tetris", "Remotes not ready!", 3); return end
    if not getRoot()        then Notify("Tetris", "No character!", 3);       return end

    S.running    = true
    S.gameOver   = false
    linesCleared = 0
    fallTimer    = 0
    advancing    = false
    Active.model = nil
    Active.name  = ""
    LandedModels = {}
    clearGrid()

    updateStatus()
    if startBtn then startBtn:SetText("■ STOP") end

    task.spawn(function()
        -- Build the board (borders) first
        local ok = initBoard()
        if not ok then
            S.running = false
            if startBtn then startBtn:SetText("▶ START") end
            Notify("Tetris", "Board setup failed!", 3)
            return
        end

        setCameraOverhead()
        task.wait(0.5)

        -- Spawn the first piece
        local spawned = spawnPiece()
        if not spawned then
            S.running = false
            if startBtn then startBtn:SetText("▶ START") end
            Notify("Tetris", "First piece failed to spawn!", 3)
            restoreCamera()
            return
        end

        -- Start the fall loop (no per-frame teleporting — only on moves)
        fallConn = RunService.Heartbeat:Connect(onHeartbeat)
        Notify("Tetris", "Game started!  ◀ LEFT / RIGHT ▶", 5)
    end)
end

local function stopGame()
    S.running  = false
    S.gameOver = false
    advancing  = false
    if fallConn then fallConn:Disconnect(); fallConn = nil end
    if startBtn then startBtn:SetText("▶ START") end
    task.spawn(function()
        teardownBoard()
        clearGrid()
        Active.model = nil
        Active.name  = ""
        fallTimer    = 0
        restoreCamera()
        updateStatus()
        Notify("Tetris", "Game stopped.", 2)
    end)
    updateStatus()
end

-- ============================================================
-- [[ 21. UI ]]
-- ============================================================

local Tabs = {
    Game       = Window:AddTab("Game", "play"),
    UISettings = Window:AddTab("UI",   "settings"),
}

local Left  = Tabs.Game:AddLeftGroupbox("Controls", "gamepad-2")
local Right = Tabs.Game:AddRightGroupbox("Status",  "bar-chart-2")

startBtn = Left:AddButton({
    Text    = "▶ START",
    Tooltip = "Start the Tetris game",
    Func    = function() if S.running then stopGame() else startGame() end end,
})

Left:AddDivider()

Left:AddButton({
    Text    = "◀  LEFT",
    Tooltip = "Move active piece left",
    Func    = function() task.spawn(movePieceLeft) end,
})

Left:AddButton({
    Text    = "RIGHT  ▶",
    Tooltip = "Move active piece right",
    Func    = function() task.spawn(movePieceRight) end,
})

Left:AddDivider()

Left:AddSlider("FallSpeed", {
    Text     = "Fall Speed",
    Default  = 1.5,
    Min      = 0.4,
    Max      = 3.0,
    Rounding = 1,
    Suffix   = " s",
    Tooltip  = "Seconds between auto row advances",
})

Left:AddDivider()

Left:AddButton({
    Text    = "Reset / Stop",
    Tooltip = "Stop game and clean up all spawned toys",
    Risky   = true,
    Func    = function() stopGame() end,
})

LblState = Right:AddLabel("State:  Stopped ■")
LblPiece = Right:AddLabel("Piece:  ---")
LblCol   = Right:AddLabel("Col:    ---")
LblRow   = Right:AddLabel("Row:    ---")
LblLines = Right:AddLabel("Lines:  0")

Right:AddDivider()
Right:AddLabel({
    Text     = "Row 0 = spawn (far)\nRow 8 = near player\nPieces fall toward you.",
    DoesWrap = true,
})

-- ============================================================
-- [[ 22. UI SETTINGS ]]
-- ============================================================

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("FTAPTetris")
ThemeManager:ApplyToTab(Tabs.UISettings)
ThemeManager:ApplyTheme("Catppuccin")

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("FTAPTetris")
SaveManager:BuildConfigSection(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()

-- ============================================================
-- [[ 23. INIT ]]
-- ============================================================

updateStatus()
Notify("Tetris", "Loaded!  Press ▶ START to play.", 4)
