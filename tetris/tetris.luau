--[[
████████╗███████╗████████╗██████╗ ██╗███████╗
╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██║██╔════╝
   ██║   █████╗     ██║   ██████╔╝██║███████╗
   ██║   ██╔══╝     ██║   ██╔══██╗██║╚════██║
   ██║   ███████╗   ██║   ██║  ██║██║███████║
   ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝
  FTAP Tetris | Flat Ground | No Borders
--]]

-- ============================================================
-- [[ SERVICES ]]
-- ============================================================

local LP         = game:GetService("Players").LocalPlayer
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenSvc   = game:GetService("TweenService")
local Workspace  = workspace

-- ============================================================
-- [[ OBSIDIAN UI ]]
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
-- [[ REMOTES ]]
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
-- [[ HELPERS ]]
-- ============================================================

local function getRoot()
    return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    return LP.Character and LP.Character:FindFirstChild("Humanoid")
end

local function waitForToyFolder(timeout)
    local name   = LP.Name .. "SpawnedInToys"
    local folder = Workspace:FindFirstChild(name)
    if folder then return folder end
    local ok, result = pcall(function()
        return Workspace:WaitForChild(name, timeout or 8)
    end)
    return ok and result or nil
end

-- ============================================================
-- [[ BOARD CONSTANTS ]]
-- ============================================================

local COLS       = 9
local ROWS       = 9
local BLOCK_SIZE = 2   -- studs per cell

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
-- [[ GAME STATE ]]
-- ============================================================

local S = { running = false, gameOver = false }

local Grid = {}
local function clearGrid()
    Grid = {}
    for r = 0, ROWS-1 do Grid[r] = {} end
end
clearGrid()

local Active       = { model = nil, name = "", col = 3, row = 0 }
local LandedModels = {}
local BoardOrigin  = nil
local fallConn     = nil
local fallTimer    = 0
local advancing    = false
local origCamType  = nil
local linesCleared = 0

local LblState, LblPiece, LblCol, LblRow, LblLines
local startBtn

-- ============================================================
-- [[ COORDINATE SYSTEM ]]
-- ============================================================

-- Lay the toy flat on the XZ plane by rotating -90° around X.
-- This is baked into every target CFrame.
local FLAT_ROT = CFrame.Angles(-math.pi / 2, 0, 0)

local function gridToWorld(col, row)
    if not BoardOrigin then return CFrame.new() end
    local x = (col + 0.5) * BLOCK_SIZE
    local z = (row + 0.5) * BLOCK_SIZE
    return BoardOrigin * CFrame.new(x, 0, z) * FLAT_ROT
end

-- ============================================================
-- [[ GRID QUERIES ]]
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
-- [[ SERVERSIDE MOVE — THE ONLY FUNCTION THAT MATTERS ]]
-- ============================================================

--[[
  Exact sequence to replicate a CFrame change serverside:

  1.  TP HRP onto the block (above it)
  2.  wait(0.15)  — let the server see our new position before we grab
  3.  Anchor all parts of the model
  4.  FireServer CreateGrabLine   — server grants network ownership
  5.  wait(0.15)  — let server process the ownership grant
  6.  Set every BasePart.CFrame to the new position
  7.  wait(0.1)   — let server receive and replicate our CFrame writes
  8.  FireServer DestroyGrabLine  — release grab (keep net ownership)
  9.  TP HRP back
  10. wait(0.1)   — settle
--]]
local function moveModel(model, targetCF)
    if not model then return end
    local hrp = getRoot()
    if not hrp then return end

    local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not primary then return end

    -- Compute world-space delta once, before we move anything
    local delta = targetCF.Position - primary.Position

    -- Collect all parts now (before any teleport scrambles things)
    local parts = {}
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then table.insert(parts, p) end
    end
    if model:IsA("BasePart") then table.insert(parts, model) end

    -- 1. TP HRP onto the block
    local savedHRP = hrp.CFrame
    hrp.CFrame = primary.CFrame * CFrame.new(0, 3, 0)
    hrp.AssemblyLinearVelocity = Vector3.zero

    -- 2. Wait so server sees our new position
    task.wait(0.15)

    -- 3. Anchor so physics won't snap parts back
    for _, p in ipairs(parts) do p.Anchored = true end

    -- 4. Grab → server grants us network ownership
    if Remotes.CreateGrabLine then
        Remotes.CreateGrabLine:FireServer(primary, primary.CFrame)
    end

    -- 5. Wait for server to process the ownership grant
    task.wait(0.15)

    -- 6. Move every part by the same world delta
    --    Primary gets the exact targetCF (position + flat rotation)
    --    Other parts just translate (they keep their current rotation)
    primary.CFrame = targetCF
    for _, p in ipairs(parts) do
        if p ~= primary then
            -- translate only, keep rotation
            local rot = p.CFrame - p.CFrame.Position  -- rotation component
            p.CFrame = CFrame.new(p.Position + delta) * rot
        end
    end

    -- 7. Wait so server receives and replicates our CFrame changes
    task.wait(0.1)

    -- 8. Release grab (net ownership stays until someone else grabs it)
    if Remotes.DestroyGrabLine then
        Remotes.DestroyGrabLine:FireServer(primary)
    end

    -- 9. TP HRP back
    hrp.CFrame = savedHRP
    hrp.AssemblyLinearVelocity = Vector3.zero

    -- 10. Settle
    task.wait(0.1)
end

-- ============================================================
-- [[ STATUS LABELS ]]
-- ============================================================

local function updateStatus()
    if LblState then LblState:SetText(S.gameOver and "GAME OVER ✗" or S.running and "Running ▶" or "Stopped ■") end
    if LblPiece then LblPiece:SetText("Piece: " .. (Active.name ~= "" and Active.name:gsub("Tetracube","") or "---")) end
    if LblCol   then LblCol:SetText(  "Col:   " .. (Active.model and tostring(Active.col) or "---")) end
    if LblRow   then LblRow:SetText(  "Row:   " .. (Active.model and tostring(Active.row) or "---")) end
    if LblLines then LblLines:SetText("Lines: " .. tostring(linesCleared)) end
end

-- ============================================================
-- [[ SPAWN HELPER ]]
-- ============================================================

local function spawnAndMove(toyName, targetCF, retries)
    if not Remotes.SpawnToy then return nil end
    retries = retries or 3

    local hrp      = getRoot()
    local savedHRP = hrp and hrp.CFrame

    for attempt = 1, retries do
        -- TP to spawn point so range check passes
        if hrp then
            hrp.CFrame = CFrame.new(targetCF.Position + Vector3.new(0, 3, 0))
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.15)
        end

        local folder = waitForToyFolder(6)
        local toy    = nil

        -- Connect ChildAdded BEFORE InvokeServer — no race condition
        local conn
        if folder then
            conn = folder.ChildAdded:Connect(function(child)
                if child.Name == toyName then toy = child end
            end)
        end

        -- InvokeServer blocks this thread (we're in task.spawn context)
        pcall(function()
            Remotes.SpawnToy:InvokeServer(toyName, targetCF, Vector3.zero)
        end)

        -- Folder may not have existed before first spawn
        if not folder then
            folder = waitForToyFolder(4)
            if folder then
                conn = folder.ChildAdded:Connect(function(child)
                    if child.Name == toyName then toy = child end
                end)
            end
        end

        -- Scan in case ChildAdded fired before we connected
        if folder and not toy then
            for _, child in ipairs(folder:GetChildren()) do
                if child.Name == toyName then toy = child; break end
            end
        end

        local t = tick()
        repeat task.wait(0.05) until toy or (tick() - t > 2)
        if conn then conn:Disconnect() end

        if toy then
            -- Force flat CFrame serverside using full ownership sequence
            moveModel(toy, targetCF)
            return toy
        end

        -- Restore on failure
        if hrp and savedHRP then
            hrp.CFrame = savedHRP
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
        Notify("Tetris", "Spawn attempt " .. attempt .. " failed, retrying...", 2)
        task.wait(0.3)
    end

    if hrp and savedHRP then
        hrp.CFrame = savedHRP
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    return nil
end

-- ============================================================
-- [[ DESTROY HELPER ]]
-- ============================================================

local function destroyModel(model)
    if not model then return end
    pcall(function()
        if Remotes.DestroyToy then
            local realRef = model
            local ok, dbgId = pcall(function() return model:GetDebugId() end)
            if ok and dbgId then
                for _, obj in ipairs(getnilinstances()) do
                    local matched = false
                    pcall(function()
                        matched = (obj.Name == model.Name and obj:GetDebugId() == dbgId)
                    end)
                    if matched then realRef = obj; break end
                end
            end
            Remotes.DestroyToy:FireServer(realRef)
        else
            model:Destroy()
        end
    end)
end

-- ============================================================
-- [[ BOARD SETUP — no borders ]]
-- ============================================================

local function initBoard()
    local hrp = getRoot()
    if not hrp then return false end

    local fwd     = hrp.CFrame.LookVector
    fwd           = Vector3.new(fwd.X, 0, fwd.Z).Unit
    local groundY = hrp.Position.Y - 3
    local pos     = hrp.Position + fwd * 20
    pos           = Vector3.new(pos.X, groundY, pos.Z)

    local yaw   = math.atan2(fwd.X, fwd.Z)
    BoardOrigin = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
    return true
end

-- ============================================================
-- [[ TEARDOWN ]]
-- ============================================================

local function teardownBoard()
    if Active.model then destroyModel(Active.model); Active.model = nil end
    for _, m in ipairs(LandedModels) do destroyModel(m) end
    LandedModels = {}
    BoardOrigin  = nil
end

-- ============================================================
-- [[ PIECE SPAWNING ]]
-- ============================================================

local function spawnPiece()
    if not Remotes.SpawnToy or not BoardOrigin then return false end

    local name     = PIECE_NAMES[math.random(1, #PIECE_NAMES)]
    local maxDcol  = pieceMaxDcol(name)
    local startCol = math.floor((COLS - (maxDcol + 1)) / 2)
    local startRow = 0

    for _, c in ipairs(getPieceCells(startCol, startRow, name)) do
        if c[2] >= 0 and isCellBlocked(c[1], c[2]) then return false end
    end

    local spawnCF = gridToWorld(startCol, startRow)
    local toy = spawnAndMove(name, spawnCF, 3)

    if not toy then
        for _, fallback in ipairs(PIECE_NAMES) do
            if fallback ~= name then
                toy = spawnAndMove(fallback, spawnCF, 2)
                if toy then name = fallback; break end
            end
        end
    end

    if not toy then
        Notify("Tetris", "Piece spawn failed!", 4)
        return false
    end

    Active.model = toy
    Active.name  = name
    Active.col   = startCol
    Active.row   = startRow
    updateStatus()
    return true
end

-- ============================================================
-- [[ LOCK & LINE CLEAR ]]
-- ============================================================

local function lockPiece()
    if not Active.model then return end
    for _, p in ipairs(Active.model:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true end
    end
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
    for c = 0, COLS-1 do
        if not Grid[r][c] then return false end
    end
    return true
end

local function compactAbove(clearedRow)
    for r = clearedRow - 1, 0, -1 do
        for c = 0, COLS-1 do
            if Grid[r][c] then
                local model   = Grid[r][c]
                Grid[r+1][c] = model
                Grid[r][c]   = nil
                local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if part and BoardOrigin then
                    local shift  = BoardOrigin.LookVector * BLOCK_SIZE
                    local newPos = part.CFrame.Position + shift
                    local newCF  = CFrame.new(newPos)
                                   * CFrame.fromMatrix(Vector3.zero,
                                       BoardOrigin.RightVector,
                                       BoardOrigin.UpVector,
                                       BoardOrigin.LookVector)
                                   * FLAT_ROT
                    moveModel(model, newCF)
                end
            end
        end
    end
end

local function clearLines()
    local cleared = 0
    for r = ROWS-1, 0, -1 do
        if rowIsFull(r) then
            local done = {}
            for c = 0, COLS-1 do
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
        Notify("Tetris", cleared .. " line" .. (cleared>1 and "s" or "") .. " cleared! ✓", 2)
        updateStatus()
    end
end

-- ============================================================
-- [[ PIECE MOVEMENT ]]
-- ============================================================

local function movePieceLeft()
    if not Active.model or not S.running then return end
    if not canMoveLeft() then return end
    Active.col = Active.col - 1
    moveModel(Active.model, gridToWorld(Active.col, Active.row))
    updateStatus()
end

local function movePieceRight()
    if not Active.model or not S.running then return end
    if not canMoveRight() then return end
    Active.col = Active.col + 1
    moveModel(Active.model, gridToWorld(Active.col, Active.row))
    updateStatus()
end

local function advancePiece()
    if not Active.model then return false end
    if canAdvance() then
        Active.row = Active.row + 1
        moveModel(Active.model, gridToWorld(Active.col, Active.row))
        updateStatus()
        return true
    end
    return false
end

-- ============================================================
-- [[ FALL LOOP ]]
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
-- [[ CAMERA ]]
-- ============================================================

local function setCameraOverhead()
    origCamType = Workspace.CurrentCamera.CameraType
    if not BoardOrigin then return end
    local center = (BoardOrigin * CFrame.new(COLS*BLOCK_SIZE/2, 0, ROWS*BLOCK_SIZE/2)).Position
    local camPos = center + Vector3.new(0, 30, 0) - BoardOrigin.LookVector * 8
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
-- [[ GAME CONTROL ]]
-- ============================================================

local function startGame()
    if S.running then return end
    if not Remotes.SpawnToy then Notify("Tetris","Remotes not ready!",3); return end
    if not getRoot()        then Notify("Tetris","No character!",3);       return end

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
        if not initBoard() then
            S.running = false
            if startBtn then startBtn:SetText("▶ START") end
            Notify("Tetris","Board setup failed!",3)
            return
        end
        setCameraOverhead()
        task.wait(0.5)
        if not spawnPiece() then
            S.running = false
            if startBtn then startBtn:SetText("▶ START") end
            Notify("Tetris","First piece failed!",3)
            restoreCamera()
            return
        end
        fallConn = RunService.Heartbeat:Connect(onHeartbeat)
        Notify("Tetris","Game started!  ◀ LEFT / RIGHT ▶",5)
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
        Notify("Tetris","Game stopped.",2)
    end)
    updateStatus()
end

-- ============================================================
-- [[ UI ]]
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
    Tooltip = "Stop and clean up",
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
-- [[ UI SETTINGS ]]
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
-- [[ INIT ]]
-- ============================================================

updateStatus()
Notify("Tetris","Loaded!  Press ▶ START to play.", 4)
