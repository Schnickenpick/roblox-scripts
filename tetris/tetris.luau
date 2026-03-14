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

-- Wait up to `timeout` seconds for the toy folder to exist (created on first spawn)
local function waitForToyFolder(timeout)
    timeout = timeout or 8
    local folder = getToyFolder()
    if folder then return folder end
    -- The folder is created server-side on first toy spawn, so WaitForChild it
    local ok, result = pcall(function()
        return Workspace:WaitForChild(LP.Name .. "SpawnedInToys", timeout)
    end)
    return ok and result or nil
end

-- Find a nil-instance toy by name for DestroyToy (toys live in nil after spawning)
local function findNilToy(name)
    for _, obj in ipairs(getnilinstances()) do
        if obj.Name == name and obj:IsA("Model") then
            return obj
        end
    end
    return nil
end

-- ============================================================
-- [[ 5. BOARD CONSTANTS ]]
-- ============================================================

-- 9 columns × 9 rows  (each pallet ≈ 3 block widths → 3 pallets = 9 cols / 9 rows)
local COLS       = 9
local ROWS       = 9
local BLOCK_SIZE = 2   -- studs per grid cell (one tetracube sub-block ≈ 2 studs)

-- Piece shape definitions: list of {dcol, drow} offsets from anchor cell
-- All "flat" — pieces lay in the XZ plane, row increases toward the player
local PIECE_SHAPES = {
    TetracubeI = {{0,0},{1,0},{2,0},{3,0}},
    TetracubeO = {{0,0},{1,0},{0,1},{1,1}},
    TetracubeT = {{0,0},{1,0},{2,0},{1,1}},
    TetracubeS = {{1,0},{2,0},{0,1},{1,1}},
    TetracubeZ = {{0,0},{1,0},{1,1},{2,1}},
    TetracubeL = {{0,0},{1,0},{2,0},{2,1}},
    TetracubeJ = {{0,0},{1,0},{2,0},{0,1}},
}

-- Maximum column offset in each piece (used for right-wall check)
local function pieceMaxDcol(name)
    local max = 0
    for _, o in ipairs(PIECE_SHAPES[name] or {}) do
        if o[1] > max then max = o[1] end
    end
    return max
end

local PIECE_NAMES = {
    "TetracubeI","TetracubeO","TetracubeT",
    "TetracubeS","TetracubeZ","TetracubeL","TetracubeJ"
}

-- ============================================================
-- [[ 6. GAME STATE ]]
-- ============================================================

local S = { running = false, gameOver = false }

-- Grid[row][col] = landed model or nil
local Grid = {}
local function clearGrid()
    Grid = {}
    for r = 0, ROWS - 1 do
        Grid[r] = {}
    end
end
clearGrid()

-- Active falling piece
local Active = { model = nil, name = "", col = 3, row = 0 }

-- All spawned models (pieces + borders) for cleanup
local LandedModels = {}
local BorderModels = {}

-- Board origin CFrame (set when game starts)
local BoardOrigin = nil

-- Heartbeat connection handle + fall timer
local fallConn  = nil
local fallTimer = 0

-- Camera state saved before game
local origCamType = nil
local origCamCF   = nil

-- Stats
local linesCleared = 0

-- Label handles (assigned after UI is built)
local LblState, LblPiece, LblCol, LblRow, LblLines
local startBtn   -- start/stop button handle

-- ============================================================
-- [[ 7. COORDINATE SYSTEM ]]
-- ============================================================

-- Maps grid (col, row) → world CFrame (flat on XZ plane)
-- BoardOrigin.RightVector = col direction (+col = right from player's view)
-- BoardOrigin.LookVector  = row direction (+row = toward player)
-- Row 0 = far/spawn end   Row 8 = near/player end
-- The -90° X rotation lays the piece model flat on the ground (models stand
-- upright by default; rotating around X tips them onto the XZ plane).
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
    if col < 0 or col >= COLS then return true end   -- walls
    if row >= ROWS             then return true end   -- floor (player side)
    if row < 0                 then return false end  -- above board = open
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
        if isCellBlocked(c[1] - 1, c[2]) then return false end
    end
    return true
end

local function canMoveRight()
    if not Active.model then return false end
    for _, c in ipairs(getPieceCells(Active.col, Active.row, Active.name)) do
        if isCellBlocked(c[1] + 1, c[2]) then return false end
    end
    return true
end

local function canAdvance()
    if not Active.model then return false end
    for _, c in ipairs(getPieceCells(Active.col, Active.row, Active.name)) do
        if isCellBlocked(c[1], c[2] + 1) then return false end
    end
    return true
end

-- ============================================================
-- [[ 9. OWNERSHIP ]]
-- ============================================================

-- Full claim: grab+own+ungrab. No HRP teleport — pieces are placed near
-- the player already and we don't want jarring TP every move.
local function claimOwnership(model)
    if not model then return end
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not part then return end
    pcall(function()
        if Remotes.CreateGrabLine  then Remotes.CreateGrabLine:FireServer(part, part.CFrame)  end
        if Remotes.SetNetworkOwner then Remotes.SetNetworkOwner:FireServer(part, part.CFrame) end
        if Remotes.DestroyGrabLine then Remotes.DestroyGrabLine:FireServer(part)              end
    end)
end

-- Lightweight per-tick refresh: SetNetworkOwner only, no grab lines
local function refreshOwnership(model)
    if not model or not Remotes.SetNetworkOwner then return end
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not part then return end
    pcall(function() Remotes.SetNetworkOwner:FireServer(part, part.CFrame) end)
end

-- ============================================================
-- [[ 10. MODEL MOVEMENT ]]
-- ============================================================

local function applyPieceCFrame()
    if not Active.model then return end
    local target = gridToWorld(Active.col, Active.row)
    if Active.model.PrimaryPart then
        Active.model:SetPrimaryPartCFrame(target)
    else
        Active.model:MoveTo(target.Position)
    end
end

-- ============================================================
-- [[ 11. STATUS LABELS ]]
-- ============================================================

local function updateStatus()
    if LblState then
        LblState:SetText(
            S.gameOver and "GAME OVER ✗"
            or S.running and "Running ▶"
            or "Stopped ■"
        )
    end
    if LblPiece then LblPiece:SetText("Piece: " .. (Active.name ~= "" and Active.name:gsub("Tetracube","") or "---")) end
    if LblCol   then LblCol:SetText(  "Col:   " .. (Active.model and tostring(Active.col) or "---")) end
    if LblRow   then LblRow:SetText(  "Row:   " .. (Active.model and tostring(Active.row) or "---")) end
    if LblLines then LblLines:SetText("Lines: " .. tostring(linesCleared)) end
end

-- ============================================================
-- [[ 12. BOARD SETUP ]]
-- ============================================================

-- Teleport HRP to a world position for the duration of a callback, then restore.
-- Used to pass the server range check on every spawn/ownership call.
local function atPosition(worldPos, fn)
    local hrp = getRoot()
    if not hrp then return fn() end
    local saved = hrp.CFrame
    hrp.CFrame = CFrame.new(worldPos)
    task.wait(0.05)
    local result = { fn() }
    task.wait(0.05)
    hrp.CFrame = saved
    hrp.AssemblyLinearVelocity = Vector3.zero
    return table.unpack(result)
end

-- Returns the world-space center of the board (used as TP point during spawns)
local function boardCenter()
    if not BoardOrigin then return Vector3.new(0, 0, 0) end
    return (BoardOrigin * CFrame.new(
        COLS * BLOCK_SIZE / 2,
        3,   -- slightly above ground so we land cleanly
        ROWS * BLOCK_SIZE / 2
    )).Position
end

local function spawnToyAt(name, cf, retries)
    if not Remotes.SpawnToy then return nil end
    retries = retries or 3

    for attempt = 1, retries do
        -- Ensure toy folder exists (created on very first spawn)
        local folder = waitForToyFolder(6)

        local toy = nil

        -- ChildAdded BEFORE invoking — never miss the event
        local conn
        if folder then
            conn = folder.ChildAdded:Connect(function(child)
                if child.Name == name then toy = child end
            end)
        end

        -- Spawn the toy. The CFrame already encodes flat orientation via the
        -- rotation baked into gridToWorld (BoardOrigin is on the XZ plane).
        -- Third arg Vector3.zero = use the CFrame's own rotation (no extra spin).
        task.spawn(function()
            pcall(function()
                Remotes.SpawnToy:InvokeServer(name, cf, Vector3.zero)
            end)
        end)

        -- If folder didn't exist before, try to get it now
        if not folder then
            folder = waitForToyFolder(6)
            if folder and not conn then
                conn = folder.ChildAdded:Connect(function(child)
                    if child.Name == name then toy = child end
                end)
            end
        end

        -- Scan existing children in case it arrived instantly
        if folder and not toy then
            for _, child in ipairs(folder:GetChildren()) do
                if child.Name == name then toy = child; break end
            end
        end

        -- Wait up to 6 s
        local t = tick()
        repeat task.wait(0.05) until toy or (tick() - t > 6)
        if conn then conn:Disconnect() end

        if toy then return toy end

        Notify("Tetris", "Spawn attempt " .. attempt .. " failed, retrying...", 2)
        task.wait(0.3)
    end

    return nil
end

local function initBoard()
    local hrp = getRoot()
    if not hrp then return false end

    -- Place board origin 18 studs ahead of player, on the ground
    local fwd     = hrp.CFrame.LookVector
    fwd           = Vector3.new(fwd.X, 0, fwd.Z).Unit
    local groundY = hrp.Position.Y - 3   -- approximate ground level

    local pos = Vector3.new(
        hrp.Position.X + fwd.X * 18,
        groundY,
        hrp.Position.Z + fwd.Z * 18
    )
    local yaw = math.atan2(fwd.X, fwd.Z)
    BoardOrigin = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

    -- Board is 9×9 blocks = 18×18 studs. Each pallet ≈ 6 studs → 3 pallets per side.
    local PS = 6  -- pallet size in studs

    -- Teleport to board center once so ALL spawns pass the range check
    local center   = boardCenter()
    local savedHRP = hrp.CFrame
    hrp.CFrame = CFrame.new(center)
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.1)

    -- Flat pallet CFrame: lay the pallet on the ground with -90° X rotation
    local palletRot = CFrame.Angles(-math.pi / 2, 0, 0)

    -- Build a 3×3 outline of pallets (border only, not filled inside).
    -- Grid positions in pallet units: 3 columns (0,1,2) × 3 rows (0,1,2).
    -- Only the border cells: top row, bottom row, left col, right col.
    BorderModels = {}
    for pr = 0, 2 do      -- pallet row (0=far/spawn, 2=near/player)
        for pc = 0, 2 do  -- pallet col (0=left, 2=right)
            local isBorder = (pr == 0 or pr == 2 or pc == 0 or pc == 2)
            if isBorder then
                local x  = (pc + 0.5) * PS
                local z  = (pr + 0.5) * PS
                -- Offset so the 3×3 pallet grid lines up with the 9×9 block grid
                local cf = BoardOrigin * CFrame.new(x - PS * 0, 0, z - PS * 0) * palletRot
                local m  = spawnToyAt("PalletLightBrown", cf, 3)
                if m then
                    table.insert(BorderModels, m)
                else
                    Notify("Tetris", "Border pallet failed (" .. pc .. "," .. pr .. ")", 2)
                end
            end
        end
    end

    -- Restore player position
    hrp.CFrame = savedHRP
    hrp.AssemblyLinearVelocity = Vector3.zero

    return true
end

local function destroyModel(model)
    if not model then return end
    pcall(function()
        if Remotes.DestroyToy then
            -- DestroyToy requires the nil-instance reference, not the workspace proxy.
            -- Find it by matching name + DebugId.
            local realRef = model
            local debugId = pcall(function() return model:GetDebugId() end) and model:GetDebugId() or nil
            if debugId then
                for _, obj in ipairs(getnilinstances()) do
                    if obj.Name == model.Name and obj:GetDebugId() == debugId then
                        realRef = obj
                        break
                    end
                end
            end
            Remotes.DestroyToy:FireServer(realRef)
        else
            model:Destroy()
        end
    end)
end

local function teardownBoard()
    if Active.model then
        destroyModel(Active.model)
        Active.model = nil
    end
    for _, m in ipairs(LandedModels) do destroyModel(m) end
    LandedModels = {}
    for _, m in ipairs(BorderModels) do destroyModel(m) end
    BorderModels = {}
    BoardOrigin  = nil
end

-- ============================================================
-- [[ 13. PIECE SPAWNING ]]
-- ============================================================

local function spawnPiece()
    if not Remotes.SpawnToy then return false end

    local name     = PIECE_NAMES[math.random(1, #PIECE_NAMES)]
    local maxDcol  = pieceMaxDcol(name)
    local startCol = math.floor((COLS - (maxDcol + 1)) / 2)
    local startRow = 0

    -- Game over check: any spawn cell already occupied?
    for _, c in ipairs(getPieceCells(startCol, startRow, name)) do
        if c[2] >= 0 and isCellBlocked(c[1], c[2]) then
            return false
        end
    end

    local spawnCF = gridToWorld(startCol, startRow)

    -- Teleport to board center so range check always passes, then restore
    local toy = spawnToyAt(name, spawnCF, 3)
    if not toy then
        -- Last-ditch: try a different piece
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

    task.wait(0.1)
    Active.model = toy
    Active.name  = name
    Active.col   = startCol
    Active.row   = startRow

    claimOwnership(toy)
    applyPieceCFrame()
    updateStatus()
    return true
end

-- ============================================================
-- [[ 14. LOCK & LINE CLEAR ]]
-- ============================================================

local function lockPiece()
    if not Active.model then return end

    -- Anchor all parts in the model
    for _, p in ipairs(Active.model:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true end
    end

    -- Write cells into grid
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
    -- Shift every row above clearedRow down by 1 (both grid data and world position)
    for r = clearedRow - 1, 0, -1 do
        for c = 0, COLS - 1 do
            if Grid[r][c] then
                local model      = Grid[r][c]
                Grid[r + 1][c]  = model
                Grid[r][c]      = nil
                -- Move model one row forward (toward player = +LookVector)
                claimOwnership(model)
                if model.PrimaryPart then
                    model:SetPrimaryPartCFrame(
                        model.PrimaryPart.CFrame * CFrame.new(0, 0, BLOCK_SIZE)
                    )
                else
                    model:MoveTo(
                        model:GetModelCFrame().Position
                        + BoardOrigin.LookVector * BLOCK_SIZE
                    )
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
                        if LandedModels[i] == m then
                            table.remove(LandedModels, i); break
                        end
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
-- [[ 15. PIECE MOVEMENT (player controls) ]]
-- ============================================================

local function movePieceLeft()
    if not Active.model or not S.running then return end
    if not canMoveLeft() then return end
    Active.col = Active.col - 1
    claimOwnership(Active.model)
    applyPieceCFrame()
    updateStatus()
end

local function movePieceRight()
    if not Active.model or not S.running then return end
    if not canMoveRight() then return end
    Active.col = Active.col + 1
    claimOwnership(Active.model)
    applyPieceCFrame()
    updateStatus()
end

-- Returns true if the piece advanced, false if it needs to lock
local function advancePiece()
    if not Active.model then return false end
    if canAdvance() then
        Active.row = Active.row + 1
        claimOwnership(Active.model)
        applyPieceCFrame()
        updateStatus()
        return true
    end
    return false
end

-- ============================================================
-- [[ 16. FALL LOOP ]]
-- ============================================================

local advancing = false   -- guard against overlapping task.spawns

local function onHeartbeat(dt)
    if not S.running or not Active.model then return end

    -- Lightweight ownership refresh every frame
    refreshOwnership(Active.model)

    fallTimer = fallTimer + dt
    local speed = Options.FallSpeed and Options.FallSpeed.Value or 1.5

    if fallTimer >= speed and not advancing then
        fallTimer = 0
        advancing = true
        task.spawn(function()
            local moved = advancePiece()
            if not moved then
                lockPiece()
                clearLines()
                local ok = spawnPiece()
                if not ok then
                    -- Game over
                    S.running  = false
                    S.gameOver = true
                    if fallConn then fallConn:Disconnect(); fallConn = nil end
                    updateStatus()
                    if startBtn then startBtn:SetText("▶ START") end
                    Notify("Tetris", "GAME OVER!  Lines cleared: " .. linesCleared, 7)
                end
            end
            advancing = false
        end)
    end
end

-- ============================================================
-- [[ 17. CAMERA ]]
-- ============================================================

local function setCameraOverhead()
    origCamType = Workspace.CurrentCamera.CameraType
    origCamCF   = Workspace.CurrentCamera.CFrame
    if not BoardOrigin then return end

    local center = (BoardOrigin * CFrame.new(
        COLS * BLOCK_SIZE / 2, 0,
        ROWS * BLOCK_SIZE / 2
    )).Position

    -- Above and slightly behind board, looking down at ~45°
    local camPos = center + Vector3.new(0, 26, 0) - BoardOrigin.LookVector * 14
    local camCF  = CFrame.lookAt(camPos, center)

    Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
    local tw = TweenSvc:Create(
        Workspace.CurrentCamera,
        TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
        { CFrame = camCF }
    )
    tw:Play()
end

local function restoreCamera()
    Workspace.CurrentCamera.CameraType = origCamType or Enum.CameraType.Custom
    local hum = getHum()
    if hum then Workspace.CurrentCamera.CameraSubject = hum end
end

-- ============================================================
-- [[ 18. GAME CONTROL ]]
-- ============================================================

local function startGame()
    if S.running then return end
    if not Remotes.SpawnToy then
        Notify("Tetris", "Remotes not ready yet, wait a moment!", 4)
        return
    end
    local hrp = getRoot()
    if not hrp then Notify("Tetris", "No character found!", 3) return end

    -- Reset everything
    S.running    = true
    S.gameOver   = false
    linesCleared = 0
    fallTimer    = 0
    advancing    = false
    Active.model = nil
    Active.name  = ""
    LandedModels = {}
    clearGrid()

    -- Build border
    local ok = initBoard()
    if not ok then
        S.running = false
        Notify("Tetris", "Board setup failed!", 3)
        return
    end

    updateStatus()
    if startBtn then startBtn:SetText("■ STOP") end

    -- Camera + first piece (async — InvokeServer yields)
    task.spawn(function()
        setCameraOverhead()
        task.wait(0.6)

        local spawned = spawnPiece()
        if not spawned then
            S.running = false
            if startBtn then startBtn:SetText("▶ START") end
            Notify("Tetris", "First piece failed to spawn!", 3)
            restoreCamera()
            return
        end

        fallConn = RunService.Heartbeat:Connect(onHeartbeat)
        Notify("Tetris", "Game started!  ◀ LEFT / RIGHT ▶ to steer", 5)
    end)
end

local function stopGame()
    S.running  = false
    S.gameOver = false
    advancing  = false

    if fallConn then fallConn:Disconnect(); fallConn = nil end

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

    if startBtn then startBtn:SetText("▶ START") end
    updateStatus()
end

-- ============================================================
-- [[ 19. UI ]]
-- ============================================================

local Tabs = {
    Game       = Window:AddTab("Game", "play"),
    UISettings = Window:AddTab("UI",   "settings"),
}

local Left  = Tabs.Game:AddLeftGroupbox("Controls",  "gamepad-2")
local Right = Tabs.Game:AddRightGroupbox("Status",   "bar-chart-2")

-- ---- START / STOP ----
startBtn = Left:AddButton({
    Text    = "▶ START",
    Tooltip = "Start the Tetris game",
    Func    = function()
        if S.running then stopGame() else startGame() end
    end,
})

Left:AddDivider()

-- ---- MOVEMENT ----
Left:AddButton({
    Text    = "◀  LEFT",
    Tooltip = "Move active piece one column left",
    Func    = function() task.spawn(movePieceLeft) end,
})

Left:AddButton({
    Text    = "RIGHT  ▶",
    Tooltip = "Move active piece one column right",
    Func    = function() task.spawn(movePieceRight) end,
})

Left:AddDivider()

-- ---- FALL SPEED ----
Left:AddSlider("FallSpeed", {
    Text     = "Fall Speed",
    Default  = 1.5,
    Min      = 0.4,
    Max      = 3.0,
    Rounding = 1,
    Suffix   = " s",
    Tooltip  = "Seconds between automatic row advances",
})

Left:AddDivider()

Left:AddButton({
    Text    = "Reset / Stop",
    Tooltip = "Stop the game and clean up all pieces",
    Risky   = true,
    Func    = function() stopGame() end,
})

-- ---- STATUS ----
LblState = Right:AddLabel("State:  Stopped ■")
LblPiece = Right:AddLabel("Piece:  ---")
LblCol   = Right:AddLabel("Col:    ---")
LblRow   = Right:AddLabel("Row:    ---")
LblLines = Right:AddLabel("Lines:  0")

Right:AddDivider()
Right:AddLabel({
    Text     = "Row 0 = spawn end (far)\nRow 8 = player end (near)\nPieces fall toward you.",
    DoesWrap = true,
})

-- ============================================================
-- [[ 20. UI SETTINGS ]]
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
-- [[ 21. INIT ]]
-- ============================================================

updateStatus()
Notify("Tetris", "Loaded!  Press ▶ START to play.", 4)
