--[[
████████╗███████╗████████╗██████╗ ██╗███████╗
╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██║██╔════╝
   ██║   █████╗     ██║   ██████╔╝██║███████╗
   ██║   ██╔══╝     ██║   ██╔══██╗██║╚════██║
   ██║   ███████╗   ██║   ██║  ██║██║███████║
   ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝
   FTAP Tetris Mini-Game | Obsidian UI
   Uses Tetracube toys as Tetris pieces
--]]

-- ============================================================
-- [[ 1. SERVICES ]]
-- ============================================================

local LP         = game:GetService("Players").LocalPlayer
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")

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
	Title            = "FTAP Tetris",
	Footer           = "Tetracube Edition",
	AutoShow         = true,
	Center           = true,
	NotifySide       = "Right",
	ToggleKeybind    = Enum.KeyCode.RightShift,
})

local function Notify(title, desc, t)
	Library:Notify({ Title = title, Description = desc or "", Time = t or 3 })
end

-- ============================================================
-- [[ 3. REMOTES ]]
-- ============================================================

local CreateGrabLine, DestroyGrabLine, SetNetworkOwner, SpawnToyRF, DestroyToyRE

task.spawn(function()
	local GE = RS:WaitForChild("GrabEvents", 10)
	if GE then
		CreateGrabLine  = GE:WaitForChild("CreateGrabLine")
		DestroyGrabLine = GE:WaitForChild("DestroyGrabLine")
		SetNetworkOwner = GE:WaitForChild("SetNetworkOwner")
	end
	local MT = RS:WaitForChild("MenuToys", 10)
	if MT then
		SpawnToyRF   = MT:WaitForChild("SpawnToyRemoteFunction")
		DestroyToyRE = MT:WaitForChild("DestroyToy")
	end
end)

-- ============================================================
-- [[ 4. HELPERS ]]
-- ============================================================

local function getRoot()
	return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
end

local function getToyFolder()
	local name = LP.Name .. "SpawnedInToys"
	return workspace:FindFirstChild(name) or workspace:WaitForChild(name, 8)
end

local function GetObject(name)
	for _, obj in (getnilinstances or function() return {} end)() do
		if obj.Name == name then return obj end
	end
	return workspace:FindFirstChild(name, true)
end

-- ============================================================
-- [[ 5. TETRIS CONSTANTS ]]
-- ============================================================

local PIECE_NAMES = {
	"TetracubeI", "TetracubeO", "TetracubeT",
	"TetracubeS", "TetracubeZ", "TetracubeL", "TetracubeJ",
}

-- Grid settings (studs)
local CELL_SIZE   = 2    -- each tetracube block is ~2 studs
local GRID_WIDTH  = 10   -- 10 columns
local GRID_HEIGHT = 20   -- 20 rows

-- ============================================================
-- [[ 6. GAME STATE ]]
-- ============================================================

local S = {
	running      = false,
	fallSpeed    = 1.0,     -- seconds per tick
	activePiece  = nil,     -- current falling Model
	activeBody   = nil,     -- Body BasePart of active piece
	activeCF     = nil,     -- current CFrame of the piece on the grid
	placedPieces = {},      -- list of placed piece Models
	allPieces    = {},      -- all spawned pieces (for cleanup)
	originCF     = nil,     -- world CFrame of the grid origin (bottom-left)
	fallConn     = nil,     -- heartbeat connection for falling
	inputConn    = nil,     -- input connection for controls
	gridCol      = 4,       -- current column (0-indexed from left)
	gridRow      = 19,      -- current row (0 = bottom, 19 = top)
	rotation     = 0,       -- rotation state (0, 90, 180, 270)
}

-- ============================================================
-- [[ 7. PIECE SPAWNING ]]
-- ============================================================

local function spawnPiece(pieceName)
	if not SpawnToyRF or not CreateGrabLine then
		Notify("Error", "Remotes not ready")
		return nil, nil
	end

	local hrp = getRoot()
	if not hrp then Notify("Error", "No character"); return nil, nil end

	-- Spawn high above the grid origin so it doesn't collide
	local spawnCF = S.originCF * CFrame.new(S.gridCol * CELL_SIZE, (GRID_HEIGHT + 5) * CELL_SIZE, 0)

	local folder = getToyFolder()
	if not folder then Notify("Error", "Toy folder missing"); return nil, nil end

	-- Snapshot existing pieces with this name
	local before = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c.Name == pieceName then before[c] = true end
	end

	local toy, body

	-- Hook ChildAdded before InvokeServer to avoid race
	local conn = folder.ChildAdded:Connect(function(child)
		if child.Name == pieceName and not before[child] then
			toy = child
			local b = child:FindFirstChild("Body")
			if not b then
				pcall(function() b = child:WaitForChild("Body", 3) end)
			end
			if b then
				body = b
				-- Grab immediately for network ownership
				pcall(function()
					CreateGrabLine:FireServer(b, b.CFrame)
				end)
			end
		end
	end)

	pcall(function()
		SpawnToyRF:InvokeServer(pieceName, spawnCF, Vector3.zero)
	end)
	conn:Disconnect()

	-- Fallback: scan folder if ChildAdded missed it
	if not toy then
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name == pieceName and not before[c] then
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

	-- Also check nil instances
	if not toy then
		toy = GetObject(pieceName)
		if toy then
			body = toy:FindFirstChild("Body")
			if body then
				pcall(function()
					CreateGrabLine:FireServer(body, body.CFrame)
				end)
			end
		end
	end

	if not toy or not body then
		Notify("Error", "Failed to spawn " .. pieceName)
		return nil, nil
	end

	-- Wait for ownership confirmation
	local partOwner = body:WaitForChild("PartOwner", 3)
	if partOwner and partOwner.Value == LP.Name then
		-- Good, we own it
	end

	-- Anchor all parts
	for _, p in ipairs(toy:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end

	-- Release grab (keep net ownership)
	pcall(function() DestroyGrabLine:FireServer(body) end)

	table.insert(S.allPieces, toy)
	return toy, body
end

-- ============================================================
-- [[ 8. PIECE MOVEMENT (re-grab pattern) ]]
-- ============================================================

local function movePieceTo(toy, body, targetCF)
	if not toy or not body then return end
	local hrp = getRoot()
	if not hrp then return end

	local savedHRP = hrp.CFrame

	-- 1. TP HRP near the body so grab range is met
	hrp.CFrame = CFrame.new(body.Position + Vector3.new(0, 3, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
	task.wait(0.1)

	-- 2. Re-grab to refresh ownership
	pcall(function()
		CreateGrabLine:FireServer(body, body.CFrame)
	end)
	task.wait(0.1)

	-- 3. Unanchor
	for _, p in ipairs(toy:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	task.wait(0.05)

	-- 4. Move
	pcall(function()
		toy:SetPrimaryPartCFrame(targetCF)
	end)
	task.wait(0.15)

	-- 5. Re-anchor
	for _, p in ipairs(toy:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	task.wait(0.05)

	-- 6. Release grab
	pcall(function() DestroyGrabLine:FireServer(body) end)
	task.wait(0.05)

	-- 7. TP HRP back
	hrp.CFrame = savedHRP
	hrp.AssemblyLinearVelocity = Vector3.zero
end

-- ============================================================
-- [[ 9. COLLISION DETECTION ]]
-- ============================================================

local function isColliding(col, row)
	-- Out of bounds check
	if col < 0 or col >= GRID_WIDTH or row < 0 then
		return true
	end

	-- Check if any placed piece occupies this cell
	local testPos = (S.originCF * CFrame.new(col * CELL_SIZE, row * CELL_SIZE, 0)).Position
	for _, placed in ipairs(S.placedPieces) do
		if placed and placed.Parent then
			for _, p in ipairs(placed:GetDescendants()) do
				if p:IsA("BasePart") then
					local dist = (p.Position - testPos).Magnitude
					if dist < CELL_SIZE * 0.8 then
						return true
					end
				end
			end
		end
	end

	return false
end

local function canMoveDown()
	return not isColliding(S.gridCol, S.gridRow - 1)
end

local function canMoveLeft()
	return not isColliding(S.gridCol - 1, S.gridRow)
end

local function canMoveRight()
	return not isColliding(S.gridCol + 1, S.gridRow)
end

-- ============================================================
-- [[ 10. ROW CLEARING ]]
-- ============================================================

local function checkAndClearRows()
	-- Simple row clearing: check each row for fullness
	-- Since we're working with Models and not a true grid,
	-- this uses approximate position checking
	local rowCounts = {}

	for _, placed in ipairs(S.placedPieces) do
		if placed and placed.Parent then
			for _, p in ipairs(placed:GetDescendants()) do
				if p:IsA("BasePart") then
					local relY = p.Position.Y - S.originCF.Position.Y
					local row = math.floor(relY / CELL_SIZE + 0.5)
					rowCounts[row] = (rowCounts[row] or 0) + 1
				end
			end
		end
	end

	local cleared = 0
	for row, count in pairs(rowCounts) do
		-- A full row needs roughly GRID_WIDTH blocks
		if count >= GRID_WIDTH then
			cleared += 1
			-- Destroy parts in this row
			local rowY = S.originCF.Position.Y + row * CELL_SIZE
			for _, placed in ipairs(S.placedPieces) do
				if placed and placed.Parent then
					for _, p in ipairs(placed:GetDescendants()) do
						if p:IsA("BasePart") then
							local partRow = math.floor((p.Position.Y - S.originCF.Position.Y) / CELL_SIZE + 0.5)
							if partRow == row then
								p:Destroy()
							end
						end
					end
				end
			end
		end
	end

	if cleared > 0 then
		Notify("Lines!", "Cleared " .. cleared .. " row(s)!")
	end
end

-- ============================================================
-- [[ 11. GAME LOGIC ]]
-- ============================================================

local function getTargetCF()
	local rotCF = CFrame.Angles(0, math.rad(S.rotation), 0)
	return S.originCF * CFrame.new(S.gridCol * CELL_SIZE, S.gridRow * CELL_SIZE, 0) * rotCF
end

local function spawnNextPiece()
	if not S.running then return end

	local name = PIECE_NAMES[math.random(1, #PIECE_NAMES)]
	local toy, body = spawnPiece(name)
	if not toy or not body then
		Notify("Game Over", "Failed to spawn piece")
		S.running = false
		return
	end

	S.activePiece = toy
	S.activeBody  = body
	S.gridCol     = math.floor(GRID_WIDTH / 2)
	S.gridRow     = GRID_HEIGHT - 1
	S.rotation    = 0

	-- Move piece to starting position
	task.spawn(function()
		movePieceTo(toy, body, getTargetCF())
	end)
end

local function placePiece()
	if S.activePiece then
		table.insert(S.placedPieces, S.activePiece)
		S.activePiece = nil
		S.activeBody  = nil

		-- Check for cleared rows
		checkAndClearRows()

		-- Check game over (piece placed at top)
		if S.gridRow >= GRID_HEIGHT - 2 then
			Notify("Game Over", "Stack reached the top!")
			S.running = false
			return
		end

		-- Spawn next piece
		task.spawn(function()
			task.wait(0.3)
			spawnNextPiece()
		end)
	end
end

local function tickDown()
	if not S.running or not S.activePiece then return end

	if canMoveDown() then
		S.gridRow -= 1
		task.spawn(function()
			movePieceTo(S.activePiece, S.activeBody, getTargetCF())
		end)
	else
		placePiece()
	end
end

-- ============================================================
-- [[ 12. INPUT HANDLING ]]
-- ============================================================

local function setupInput()
	if S.inputConn then S.inputConn:Disconnect() end

	S.inputConn = UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not S.running or not S.activePiece then return end

		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			-- Move left
			if canMoveLeft() then
				S.gridCol -= 1
				task.spawn(function()
					movePieceTo(S.activePiece, S.activeBody, getTargetCF())
				end)
			end
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			-- Move right
			if canMoveRight() then
				S.gridCol += 1
				task.spawn(function()
					movePieceTo(S.activePiece, S.activeBody, getTargetCF())
				end)
			end
		elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.Up then
			-- Rotate 90 degrees
			S.rotation = (S.rotation + 90) % 360
			task.spawn(function()
				movePieceTo(S.activePiece, S.activeBody, getTargetCF())
			end)
		elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
			-- Soft drop (instant tick down)
			tickDown()
		elseif input.KeyCode == Enum.KeyCode.Space then
			-- Hard drop: move down until collision
			task.spawn(function()
				while S.running and S.activePiece and canMoveDown() do
					S.gridRow -= 1
				end
				movePieceTo(S.activePiece, S.activeBody, getTargetCF())
				task.wait(0.2)
				placePiece()
			end)
		end
	end)
end

-- ============================================================
-- [[ 13. GAME START / STOP / RESET ]]
-- ============================================================

local function cleanupAllPieces()
	for _, toy in ipairs(S.allPieces) do
		if toy and toy.Parent and DestroyToyRE then
			pcall(function() DestroyToyRE:FireServer(toy) end)
		end
	end
	S.allPieces    = {}
	S.placedPieces = {}
	S.activePiece  = nil
	S.activeBody   = nil
end

local function stopGame()
	S.running = false

	if S.fallConn then
		S.fallConn:Disconnect()
		S.fallConn = nil
	end
	if S.inputConn then
		S.inputConn:Disconnect()
		S.inputConn = nil
	end
end

local function startGame()
	if S.running then return end

	local hrp = getRoot()
	if not hrp then Notify("Error", "No character"); return end

	-- Set grid origin: 10 studs in front of the player, at ground level
	-- The origin is the bottom-left corner of the grid
	local playerPos = hrp.Position
	local lookDir   = hrp.CFrame.LookVector
	local gridCenter = playerPos + lookDir * 20

	-- Align to world axes for cleaner grid
	S.originCF = CFrame.new(
		math.floor(gridCenter.X),
		math.floor(playerPos.Y - 3), -- ground level
		math.floor(gridCenter.Z)
	)

	S.running = true
	Notify("Tetris", "Game started! A/D=Move, R/Up=Rotate, S/Down=Drop, Space=Hard Drop")

	-- Setup input
	setupInput()

	-- Start fall loop
	task.spawn(function()
		-- Spawn first piece
		spawnNextPiece()

		-- Fall timer
		local elapsed = 0
		S.fallConn = RunService.Heartbeat:Connect(function(dt)
			if not S.running then return end
			elapsed += dt
			if elapsed >= S.fallSpeed then
				elapsed = 0
				tickDown()
			end
		end)
	end)
end

local function resetGame()
	stopGame()
	cleanupAllPieces()
	Notify("Tetris", "Game reset! All pieces destroyed.")
end

-- ============================================================
-- [[ 14. UI TABS ]]
-- ============================================================

local MainTab = Window:AddTab("Main", "play")
local Left    = MainTab:AddLeftGroupbox("Tetris Controls")
local Right   = MainTab:AddRightGroupbox("Settings")

-- Start toggle
Left:AddToggle("TetrisActive", {
	Text    = "Start Tetris",
	Default = false,
	Tooltip = "Toggle the Tetris game on/off",
}):OnChanged(function(value)
	if value then
		task.spawn(startGame)
	else
		stopGame()
	end
end)

Left:AddDivider()

-- Reset button
Left:AddButton({
	Text    = "Reset Game",
	Tooltip = "Destroy all pieces and reset the game",
	Func    = function()
		task.spawn(resetGame)
		if Toggles.TetrisActive then
			Toggles.TetrisActive:SetValue(false)
		end
	end,
})

Left:AddDivider()

-- Controls info
Left:AddLabel("Controls:")
Left:AddLabel("A / Left Arrow = Move Left")
Left:AddLabel("D / Right Arrow = Move Right")
Left:AddLabel("S / Down Arrow = Soft Drop")
Left:AddLabel("R / Up Arrow = Rotate")
Left:AddLabel("Space = Hard Drop")

-- Fall speed slider
Right:AddSlider("FallSpeed", {
	Text    = "Fall Speed (sec)",
	Default = 1.0,
	Min     = 0.2,
	Max     = 3.0,
	Rounding = 1,
	Suffix  = "s",
}):OnChanged(function(value)
	S.fallSpeed = value
end)

Right:AddDivider()

-- Grid width display
Right:AddLabel("Grid: " .. GRID_WIDTH .. " x " .. GRID_HEIGHT)
Right:AddLabel("Cell Size: " .. CELL_SIZE .. " studs")

-- ============================================================
-- [[ 15. THEME / SAVE ]]
-- ============================================================

local SettingsTab = Window:AddTab("UI Settings", "settings")

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("FTAPTetris")
ThemeManager:ApplyToTab(SettingsTab)

SaveManager:SetLibrary(Library)
SaveManager:SetFolder("FTAPTetris")
SaveManager:BuildConfigSection(SettingsTab)

Notify("FTAP Tetris", "Loaded! Toggle 'Start Tetris' to play.")
