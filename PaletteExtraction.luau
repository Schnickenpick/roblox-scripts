-- ============================================================
--   PALETTE EXTRACTION SCRIPT  v3
--   Key insight: palette lives at workspace.PlotItems.Plot3.PalletLightBrown
--   Grab via CreateGrabLine:FireServer(SoundPart, objectSpaceCF)
--   NOT a spawned toy — no SpawnToyRemoteFunction needed
-- ============================================================

-- [[ SERVICES ]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- [[ LOCAL PLAYER ]]
local LocalPlayer     = Players.LocalPlayer
local playerCharacter = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
LocalPlayer.CharacterAdded:Connect(function(c) playerCharacter = c end)

local function GetHRP()
    local c = playerCharacter
    return c and (c:FindFirstChild("HumanoidRootPart") or c:WaitForChild("HumanoidRootPart", 5))
end

-- [[ REMOTES ]]
local GrabEvents      = ReplicatedStorage:WaitForChild("GrabEvents")
local CreateGrabLine  = GrabEvents:WaitForChild("CreateGrabLine")
local DestroyGrabLine = GrabEvents:WaitForChild("DestroyGrabLine")
local SetNetworkOwner = GrabEvents:WaitForChild("SetNetworkOwner")

-- [[ CONSTANTS ]]
local SCARY_HOUSE_CF  = CFrame.new(269.65, -5.43, 440.34)
local PALETTE_PATH    = {"PlotItems", "Plot3", "PalletLightBrown"}
local PALETTE_TIMEOUT = 8   -- seconds to wait for palette to appear in PlotItems
local OUTSIDE_OFFSET  = CFrame.new(0, 0, -60)  -- studs forward out of the house

-- [[ GLOBAL STORAGE ]]
getgenv().SavedPalettes = getgenv().SavedPalettes or {}

-- [[ OBSIDIAN LIBRARY ]]
local repo    = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

-- ============================================================
--   HELPERS
-- ============================================================

local function Notify(msg)
    pcall(function() Library:Notify(msg) end)
    print("[Extraction] " .. tostring(msg))
end

local function SetCollisions(model, state)
    if not model or not model.Parent then return end
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = state end
    end
end

-- ── Resolve palette from workspace.PlotItems.Plot3 ───────────
--   Waits up to PALETTE_TIMEOUT seconds for it to appear after
--   claiming the plot.
local function WaitForPlotPalette()
    -- Drill down through the path, waiting at each step
    local node = workspace
    for _, name in ipairs(PALETTE_PATH) do
        node = node:WaitForChild(name, PALETTE_TIMEOUT)
        if not node then
            Notify("ERROR: Path broken at '" .. name .. "' in workspace.")
            return nil
        end
    end
    return node  -- this is the PalletLightBrown Model
end

-- ── Claim plot via ProximityPrompt ────────────────────────────
local function ClaimPlot()
    pcall(function()
        local children = workspace.Plots.Plot3.PlotSign:GetChildren()
        local container = children[9]
        if not container then error("child[9] missing") end

        local pgp = container:FindFirstChild("Plus")
                and container.Plus:FindFirstChild("PlusGrabPart")
        if not pgp then error("PlusGrabPart missing") end

        local prompt = pgp:FindFirstChildWhichIsA("ProximityPrompt")
        if prompt then
            local orig = prompt.MaxActivationDistance
            prompt.MaxActivationDistance = math.huge
            fireproximityprompt(prompt)
            task.wait(0.05)
            prompt.MaxActivationDistance = orig
        else
            local cd = pgp:FindFirstChildWhichIsA("ClickDetector")
            if cd then fireclickdetector(cd) end
        end
    end)
end

-- ── Take network ownership of SoundPart ──────────────────────
--   Mirrors VerbalHub: FireServer(targetPart, targetPart.CFrame)
local function ClaimOwnership(soundPart)
    local ok = pcall(function()
        SetNetworkOwner:FireServer(soundPart, soundPart.CFrame)
    end)

    -- Optional PartOwner confirmation (give it 1.5s to replicate)
    local partOwner = soundPart:WaitForChild("PartOwner", 1.5)
    if partOwner and partOwner.Value ~= LocalPlayer.Name then
        Notify("WARN: PartOwner is '" .. tostring(partOwner.Value) .. "' — may snap back.")
    end

    return ok
end

-- ── Grab via CreateGrabLine ───────────────────────────────────
--   Exact pattern from the provided FireServer call:
--     Event:FireServer(palette.SoundPart, SoundPart.CFrame:ToObjectSpace(HRP.CFrame))
--   The second arg is the HRP position expressed in SoundPart's local space.
local function GrabPalette(soundPart, hrp)
    local objectSpaceCF = soundPart.CFrame:ToObjectSpace(hrp.CFrame)
    local ok, err = pcall(function()
        CreateGrabLine:FireServer(soundPart, objectSpaceCF)
    end)
    if not ok then
        Notify("CreateGrabLine error: " .. tostring(err))
        return false
    end
    return true
end

-- ── Release grab line ─────────────────────────────────────────
local function ReleasePalette(soundPart)
    pcall(function()
        DestroyGrabLine:FireServer(soundPart)
    end)
end

-- ============================================================
--   MAIN EXTRACTION SEQUENCE
-- ============================================================

local isRunning = false

local function RunExtraction()
    if isRunning then
        Notify("Already running — please wait.")
        return
    end
    isRunning = true

    local hrp = GetHRP()
    if not hrp then
        Notify("ERROR: No HumanoidRootPart — respawn and retry.")
        isRunning = false
        return
    end

    -- ── 1. Teleport to Scary House ────────────────────────────
    Notify("1/6 — Teleporting to Scary House…")
    hrp.CFrame = SCARY_HOUSE_CF
    task.wait(0.5)

    -- ── 2. Claim Plot 3 ───────────────────────────────────────
    Notify("2/6 — Claiming Plot 3…")
    ClaimPlot()
    task.wait(0.4)

    -- ── 3. Find palette in workspace.PlotItems.Plot3 ──────────
    Notify("3/6 — Waiting for PalletLightBrown in PlotItems…")
    local palette = WaitForPlotPalette()
    if not palette then
        isRunning = false
        return
    end

    -- SoundPart is the grab target (confirmed by provided FireServer snippet)
    local soundPart = palette:WaitForChild("SoundPart", 5)
    if not soundPart then
        Notify("ERROR: SoundPart not found on palette.")
        isRunning = false
        return
    end
    Notify("Found palette at " .. palette:GetFullName())
    task.wait(0.1)

    -- ── 4. Claim network ownership ────────────────────────────
    Notify("4/6 — Claiming network ownership via SetNetworkOwner…")
    ClaimOwnership(soundPart)
    task.wait(0.2)

    -- ── 5. Grab palette + noclip ──────────────────────────────
    Notify("5/6 — Grabbing palette via CreateGrabLine…")
    local grabbed = GrabPalette(soundPart, hrp)
    if not grabbed then
        Notify("Grab failed — aborting.")
        isRunning = false
        return
    end
    task.wait(0.15)

    -- Noclip the palette so it passes through walls
    SetCollisions(palette, false)

    -- Noclip character during the move (Cosmic.Luau Stepped pattern)
    local noclipConn = RunService.Stepped:Connect(function()
        if playerCharacter and playerCharacter.Parent then
            for _, p in ipairs(playerCharacter:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end)

    -- ── 6. Move outside, release, save ───────────────────────
    Notify("6/6 — Moving outside…")
    local outsideCF = SCARY_HOUSE_CF * OUTSIDE_OFFSET
    hrp.CFrame = outsideCF
    task.wait(0.5)  -- give physics time to follow

    -- Stop noclip
    noclipConn:Disconnect()

    -- Release the grab line
    ReleasePalette(soundPart)
    task.wait(0.1)

    -- Restore palette collisions
    SetCollisions(palette, true)

    -- Save
    table.insert(getgenv().SavedPalettes, palette)
    Notify("✔ Done! Total palettes saved: " .. #getgenv().SavedPalettes)
    isRunning = false
end

-- ============================================================
--   OBSIDIAN UI
-- ============================================================

local Window = Library:CreateWindow({
    Title    = "OBSIDIAN | PALETTE EXTRACTION",
    Center   = true,
    AutoShow = true,
})

local Tabs = {
    Main     = Window:AddTab("Main"),
    Settings = Window:AddTab("Settings"),
}

-- ── Main ─────────────────────────────────────────────────────
local MainBox = Tabs.Main:AddLeftGroupbox("Extraction")
MainBox:AddLabel("TP → Claim Plot → Find PlotItem → Own → Grab → Noclip → Move → Save")
MainBox:AddDivider()
MainBox:AddButton({
    Text    = "▶  Start Extraction",
    Func    = RunExtraction,
    Tooltip = "Grabs PalletLightBrown from workspace.PlotItems.Plot3",
})
MainBox:AddDivider()

local InfoBox = Tabs.Main:AddRightGroupbox("Saved Palettes")
InfoBox:AddButton({
    Text = "Check Count",
    Func = function()
        Notify("Palettes in memory: " .. #getgenv().SavedPalettes)
    end,
})
InfoBox:AddButton({
    Text = "Clear All",
    Func = function()
        getgenv().SavedPalettes = {}
        Notify("Memory cleared.")
    end,
})

-- ── Settings ──────────────────────────────────────────────────
local SetBox = Tabs.Settings:AddLeftGroupbox("Menu")
SetBox:AddButton("Unload", function() Library:Unload() end)
SetBox:AddLabel("Toggle"):AddKeyPicker("MenuBind", {
    Default = "End",
    NoUI    = true,
    Text    = "Menu bind",
})
Library.ToggleKeybind = Library.Options.MenuBind

Notify("Script loaded — press Start Extraction to begin.")
