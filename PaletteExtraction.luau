-- ============================================================
--   PALETTE EXTRACTION SCRIPT
--   Game: Roblox (FTAP / You)
--   UI:   Obsidian Library
-- ============================================================

-- [[ 1. SERVICES ]]
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")

-- [[ 2. LOCAL PLAYER & CHARACTER ]]
local LocalPlayer = Players.LocalPlayer

local function GetCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function GetHRP()
    local char = GetCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5))
end

-- [[ 3. REMOTES ]]
-- MenuToys
local MenuToys         = ReplicatedStorage:WaitForChild("MenuToys")
local SpawnToyRF       = MenuToys:WaitForChild("SpawnToyRemoteFunction")
local DestroyToyRE     = MenuToys:WaitForChild("DestroyToy")

-- GrabEvents  (used for network ownership so item doesn't snap back)
local GrabEvents       = ReplicatedStorage:WaitForChild("GrabEvents")
local SetNetworkOwner  = GrabEvents:WaitForChild("SetNetworkOwner")
local CreateGrabLine   = GrabEvents:WaitForChild("CreateGrabLine")
local DestroyGrabLine  = GrabEvents:WaitForChild("DestroyGrabLine")

-- [[ 4. CONSTANTS ]]
local SCARY_HOUSE_CF   = CFrame.new(269.65, -5.43, 440.34)
local TOY_NAME         = "PalletLightBrown"
local SPAWN_TIMEOUT    = 6   -- seconds to wait for toy to appear
local OUTSIDE_OFFSET   = CFrame.new(0, 0, -55)   -- 55 studs forward from player

-- [[ 5. GLOBAL PALETTE STORAGE ]]
getgenv().SavedPalettes = getgenv().SavedPalettes or {}

-- [[ 6. OBSIDIAN LIBRARY ]]
local repo    = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

-- ============================================================
--   HELPER FUNCTIONS
-- ============================================================

-- Notify wrapper (safe; won't error if Library not ready)
local function Notify(msg)
    pcall(function() Library:Notify(msg) end)
    print("[Extraction] " .. tostring(msg))
end

-- Set CanCollide on every BasePart in a model
local function SetCollisions(model, state)
    if not model or not model.Parent then return end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = state
        end
    end
end

-- Claim the plot via ProximityPrompt; pcall-wrapped so a taken plot won't crash us
local function ClaimPlot()
    local ok, err = pcall(function()
        local plotSignChildren = workspace.Plots.Plot3.PlotSign:GetChildren()
        -- index 9 as specified; guard against the list being shorter
        local plusContainer = plotSignChildren[9]
        if not plusContainer then
            error("PlotSign child [9] not found (plot list may differ)")
        end

        local plusGrabPart = plusContainer:FindFirstChild("Plus") and
                             plusContainer.Plus:FindFirstChild("PlusGrabPart")
        if not plusGrabPart then
            error("PlusGrabPart not found inside child [9]")
        end

        local prompt = plusGrabPart:FindFirstChildWhichIsA("ProximityPrompt")
                    or plusGrabPart:FindFirstChildWhichIsA("ClickDetector")
        if prompt then
            if prompt:IsA("ProximityPrompt") then
                -- Temporarily extend reach so we can trigger from wherever we TP'd to
                local origDist = prompt.MaxActivationDistance
                prompt.MaxActivationDistance = math.huge
                fireproximityprompt(prompt)
                task.wait(0.05)
                prompt.MaxActivationDistance = origDist
            elseif prompt:IsA("ClickDetector") then
                fireclickdetector(prompt)
            end
        else
            -- No prompt found; this plot may already be ours — that's fine
            Notify("No claim prompt found — plot may already be owned or claimed.")
        end
    end)

    if not ok then
        Notify("Plot claim skipped: " .. tostring(err))
    end
end

-- Spawn the toy and return it (waits via ChildAdded, with timeout fallback)
local function SpawnAndWaitForToy(spawnCF)
    local ToyFolder = workspace:WaitForChild(LocalPlayer.Name .. "SpawnedInToys", 10)
    if not ToyFolder then
        Notify("ERROR: Toy folder not found! Are you in-game?")
        return nil
    end

    local toy     = nil
    local done    = false

    -- ChildAdded listener first (reactive, from message (3).txt Spawn logic)
    local conn = ToyFolder.ChildAdded:Connect(function(child)
        if child.Name == TOY_NAME and not done then
            toy  = child
            done = true
        end
    end)

    -- Also scan existing children in case it already existed
    for _, child in ipairs(ToyFolder:GetChildren()) do
        if child.Name == TOY_NAME then
            toy  = child
            done = true
            break
        end
    end

    if not done then
        -- Fire the spawn remote off the main thread so our wait loop isn't blocked
        task.spawn(function()
            SpawnToyRF:InvokeServer(TOY_NAME, spawnCF, Vector3.zero)
        end)

        -- Wait up to SPAWN_TIMEOUT seconds
        local deadline = tick() + SPAWN_TIMEOUT
        repeat
            task.wait(0.05)
        until done or tick() > deadline
    end

    conn:Disconnect()

    if not toy or not toy.Parent then
        Notify("ERROR: Toy did not spawn within " .. SPAWN_TIMEOUT .. "s.")
        return nil
    end

    return toy
end

-- Hold the palette using HoldItemRemoteFunction (from message (3).txt Hold())
local function HoldPalette(palette, character)
    local holdPart = palette:WaitForChild("HoldPart", 3)
    if not holdPart then
        Notify("ERROR: HoldPart not found on palette.")
        return false
    end

    local holdRemote = holdPart:WaitForChild("HoldItemRemoteFunction", 3)
    if not holdRemote then
        Notify("ERROR: HoldItemRemoteFunction not found.")
        return false
    end

    local ok, err = pcall(function()
        holdRemote:InvokeServer(palette, character)
    end)

    if not ok then
        Notify("Hold invoke failed: " .. tostring(err))
        return false
    end
    return true, holdPart
end

-- Drop the palette using DropItemRemoteFunction (from message (3).txt Drop())
local function DropPalette(palette, dropCF)
    local holdPart = palette:FindFirstChild("HoldPart")
    if not holdPart then return end

    local dropRemote = holdPart:FindFirstChild("DropItemRemoteFunction")
    if not dropRemote then return end

    pcall(function()
        dropRemote:InvokeServer(palette, dropCF, Vector3.zero)
    end)
end

-- Take network ownership of the palette so the server can't snap it back
-- Uses SetNetworkOwner remote from GrabEvents (BlizT / Cosmic source reference)
local function ClaimNetworkOwnership(palette, hrp)
    pcall(function()
        -- SetNetworkOwner:FireServer(Target, CFrame) — points from HRP toward item
        SetNetworkOwner:FireServer(
            hrp,
            CFrame.new(hrp.Position, palette.PrimaryPart and palette.PrimaryPart.Position or hrp.Position)
        )
    end)

    -- Also create a grab line so the server registers us as the item's handler
    pcall(function()
        local primary = palette.PrimaryPart or palette:FindFirstChildWhichIsA("BasePart")
        if primary then
            CreateGrabLine:FireServer(primary, primary.CFrame:ToObjectSpace(hrp.CFrame))
        end
    end)
end

-- Release the network grab line after extraction is done
local function ReleaseNetworkOwnership(palette)
    pcall(function()
        local primary = palette.PrimaryPart or palette:FindFirstChildWhichIsA("BasePart")
        if primary then
            DestroyGrabLine:FireServer(primary)
        end
    end)
end

-- ============================================================
--   MAIN EXTRACTION SEQUENCE
-- ============================================================

local isRunning = false  -- guard against double-clicks

local function RunExtraction()
    if isRunning then
        Notify("Extraction already running — please wait.")
        return
    end
    isRunning = true

    -- Validate character
    local hrp = GetHRP()
    if not hrp then
        Notify("ERROR: No HumanoidRootPart found. Respawn and retry.")
        isRunning = false
        return
    end
    local character = hrp.Parent

    -- ── STEP 1: Teleport to Scary House ──────────────────────
    Notify("Step 1/7 — Teleporting to Scary House…")
    hrp.CFrame = SCARY_HOUSE_CF
    task.wait(0.4)   -- short wait for the server to register position

    -- ── STEP 2: Claim the plot ────────────────────────────────
    Notify("Step 2/7 — Claiming Plot 3…")
    ClaimPlot()
    task.wait(0.3)

    -- ── STEP 3: Spawn PalletLightBrown ───────────────────────
    Notify("Step 3/7 — Spawning " .. TOY_NAME .. "…")
    local spawnCF  = hrp.CFrame * CFrame.new(0, 0, -4)   -- 4 studs in front
    local palette  = SpawnAndWaitForToy(spawnCF)
    if not palette then
        isRunning = false
        return
    end
    task.wait(0.2)

    -- ── STEP 4: Hold the palette ──────────────────────────────
    Notify("Step 4/7 — Holding palette…")
    local held, holdPart = HoldPalette(palette, character)
    if not held then
        isRunning = false
        return
    end
    task.wait(0.25)

    -- ── STEP 5: Claim network ownership (anti-snapback) ───────
    Notify("Step 5/7 — Claiming network ownership…")
    ClaimNetworkOwnership(palette, hrp)
    task.wait(0.15)

    -- ── STEP 6: Noclip palette ────────────────────────────────
    Notify("Step 6/7 — Disabling palette collisions…")
    SetCollisions(palette, false)
    task.wait(0.1)

    -- Also noclip the character briefly so we can walk through the wall
    -- (mirrors Cosmic.Luau's Noclip loop but as a one-shot burst)
    local noclipConn
    noclipConn = RunService.Stepped:Connect(function()
        if character and character.Parent then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and not part.Name:find("HumanoidRootPart") then
                    part.CanCollide = false
                end
            end
        end
    end)

    -- ── STEP 7: Move outside & store ─────────────────────────
    Notify("Step 7/7 — Moving outside…")
    local outsideCF = hrp.CFrame * OUTSIDE_OFFSET
    hrp.CFrame = outsideCF
    task.wait(0.35)

    -- Stop noclipping character
    noclipConn:Disconnect()

    -- Drop the palette at the outside position
    DropPalette(palette, outsideCF)
    task.wait(0.2)

    -- Release the server-side grab line
    ReleaseNetworkOwnership(palette)

    -- Re-enable palette collisions
    SetCollisions(palette, true)
    task.wait(0.1)

    -- Save to global table
    table.insert(getgenv().SavedPalettes, palette)

    Notify("✔ Done! Palettes saved: " .. #getgenv().SavedPalettes)
    isRunning = false
end

-- ============================================================
--   OBSIDIAN UI
-- ============================================================

local Window = Library:CreateWindow({
    Title     = "OBSIDIAN | PALETTE EXTRACTION",
    Center    = true,
    AutoShow  = true,
})

local Tabs = {
    Main     = Window:AddTab("Main"),
    Settings = Window:AddTab("Settings"),
}

-- ── Main Tab ─────────────────────────────────────────────────
local MainBox = Tabs.Main:AddLeftGroupbox("Extraction")

MainBox:AddLabel("Teleport → Claim Plot → Spawn → Hold → Noclip → Move Outside → Save")
MainBox:AddDivider()

MainBox:AddButton({
    Text    = "▶  Start Extraction",
    Func    = RunExtraction,
    Tooltip = "Runs the full extraction sequence automatically",
})

MainBox:AddDivider()

local StatusBox = Tabs.Main:AddRightGroupbox("Saved Palettes")

StatusBox:AddButton({
    Text = "Check Count",
    Func = function()
        Notify("Palettes in memory: " .. #getgenv().SavedPalettes)
    end,
})

StatusBox:AddButton({
    Text = "Delete Last Saved",
    Func = function()
        local palettes = getgenv().SavedPalettes
        if #palettes == 0 then
            Notify("No palettes saved.")
            return
        end
        local last = table.remove(palettes)
        pcall(function()
            if last and last.Parent then
                DestroyToyRE:FireServer(last)
            end
        end)
        Notify("Last palette removed. Remaining: " .. #palettes)
    end,
})

StatusBox:AddButton({
    Text = "Clear All Memory",
    Func = function()
        getgenv().SavedPalettes = {}
        Notify("Palette memory cleared.")
    end,
})

-- ── Settings Tab ─────────────────────────────────────────────
local SetBox = Tabs.Settings:AddLeftGroupbox("Menu")

SetBox:AddButton("Unload Script", function()
    Library:Unload()
end)

SetBox:AddLabel("Toggle Keybind"):AddKeyPicker("MenuBind", {
    Default = "End",
    NoUI    = true,
    Text    = "Menu bind",
})

Library.ToggleKeybind = Library.Options.MenuBind

-- ── Done ─────────────────────────────────────────────────────
Notify("Palette Extraction script loaded. Press 'Start Extraction' to begin.")
