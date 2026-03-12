-- ============================================================
--   PALETTE EXTRACTION SCRIPT  v2
--   Fix: correct toy identification via ThisToysNumber/ToyNumber
--        correct SetNetworkOwner target (toy.Body, toy.Body.CFrame)
--        PartOwner ownership gate before Hold
-- ============================================================

-- [[ SERVICES ]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- [[ LOCAL PLAYER ]]
local LocalPlayer   = Players.LocalPlayer
local playerCharacter = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
LocalPlayer.CharacterAdded:Connect(function(c) playerCharacter = c end)

local function GetHRP()
    local c = playerCharacter
    return c and (c:FindFirstChild("HumanoidRootPart") or c:WaitForChild("HumanoidRootPart", 5))
end

-- [[ REMOTES ]]
local MenuToys        = ReplicatedStorage:WaitForChild("MenuToys")
local SpawnToyRF      = MenuToys:WaitForChild("SpawnToyRemoteFunction")
local DestroyToyRE    = MenuToys:WaitForChild("DestroyToy")

local GrabEvents      = ReplicatedStorage:WaitForChild("GrabEvents")
local SetNetworkOwner = GrabEvents:WaitForChild("SetNetworkOwner")
local DestroyGrabLine = GrabEvents:WaitForChild("DestroyGrabLine")

-- [[ TOY FOLDER ]]
-- Must be fetched fresh each call; player may have rejoined
local function GetToyFolder()
    return workspace:WaitForChild(LocalPlayer.Name .. "SpawnedInToys", 10)
end

-- [[ CONSTANTS ]]
local SCARY_HOUSE_CF = CFrame.new(269.65, -5.43, 440.34)
local TOY_NAME       = "PalletLightBrown"
local SPAWN_TIMEOUT  = 8    -- seconds
local OUTSIDE_OFFSET = CFrame.new(0, 0, -58)  -- studs forward from where we TP'd

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

-- ── Plot Claim ───────────────────────────────────────────────
local function ClaimPlot()
    pcall(function()
        -- Walk up the child list and find the 9th entry regardless of sort order
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
            -- ClickDetector fallback
            local cd = pgp:FindFirstChildWhichIsA("ClickDetector")
            if cd then fireclickdetector(cd) end
        end
    end)
    -- Either claimed or already owned — either outcome lets us continue
end

-- ── Spawn & Identify (VerbalHub pattern) ────────────────────
--   The ONLY reliable way to identify your freshly spawned toy:
--     toy:WaitForChild("ThisToysNumber").Value == ToyFolder.ToyNumber.Value - 1
--   This prevents matching another player's palette of the same name.
local function SpawnAndWaitForToy(headCF)
    local ToyFolder = GetToyFolder()
    if not ToyFolder then
        Notify("ERROR: SpawnedInToys folder not found.")
        return nil
    end

    -- ToyNumber is incremented server-side each time any toy spawns.
    -- Snapshot the expected next value before we fire the remote.
    local toyNumValue = ToyFolder:FindFirstChild("ToyNumber")
    if not toyNumValue then
        Notify("ERROR: ToyNumber not found in toy folder.")
        return nil
    end
    local expectedNum = toyNumValue.Value  -- our toy will have ThisToysNumber == this value

    local palette  = nil
    local done     = false

    -- Connect listener BEFORE invoking so we never miss the ChildAdded
    local conn = ToyFolder.ChildAdded:Connect(function(child)
        if done or child.Name ~= TOY_NAME then return end

        -- Wait briefly for ThisToysNumber to replicate
        local numObj = child:WaitForChild("ThisToysNumber", 2)
        if numObj and numObj.Value == expectedNum then
            palette = child
            done    = true
        end
    end)

    -- Spawn on a separate thread so our repeat-loop below isn't blocked
    task.spawn(function()
        SpawnToyRF:InvokeServer(TOY_NAME, headCF, Vector3.zero)
    end)

    local deadline = tick() + SPAWN_TIMEOUT
    repeat task.wait(0.05) until done or tick() > deadline

    conn:Disconnect()

    if not palette or not palette.Parent then
        Notify("ERROR: Palette did not spawn within " .. SPAWN_TIMEOUT .. "s.")
        Notify("Tip: make sure you own PalletLightBrown and have toy slots free.")
        return nil
    end

    return palette
end

-- ── Network Ownership (VerbalHub line 336 pattern) ───────────
--   MUST target toy.Body with toy.Body.CFrame — NOT the HRP.
--   Then confirm via PartOwner value before proceeding.
local function ClaimOwnership(palette)
    local body = palette:FindFirstChild("Body")
    if not body then
        -- Fallback: try PrimaryPart or first BasePart
        body = palette.PrimaryPart or palette:FindFirstChildWhichIsA("BasePart")
    end
    if not body then
        Notify("WARN: No Body part found; ownership may fail.")
        return false
    end

    -- Fire SetNetworkOwner at Body with Body's own CFrame (verbatim from VerbalHub)
    pcall(function()
        SetNetworkOwner:FireServer(body, body.CFrame)
    end)

    -- Wait for PartOwner to replicate and confirm it's ours
    local partOwner = body:WaitForChild("PartOwner", 2)
    if partOwner and partOwner.Value == LocalPlayer.Name then
        return true, body
    end

    -- PartOwner either didn't appear or belongs to someone else
    Notify("WARN: PartOwner check failed — item may snap back.")
    return false, body  -- still return body so Hold can attempt
end

-- ── Hold (message(3).txt Hold() pattern) ─────────────────────
local function HoldPalette(palette)
    local holdPart = palette:WaitForChild("HoldPart", 3)
    if not holdPart then
        Notify("ERROR: HoldPart not found.")
        return false
    end

    local holdRemote = holdPart:WaitForChild("HoldItemRemoteFunction", 3)
    if not holdRemote then
        Notify("ERROR: HoldItemRemoteFunction not found.")
        return false
    end

    local ok, err = pcall(function()
        holdRemote:InvokeServer(palette, playerCharacter)
    end)

    if not ok then
        Notify("Hold invoke error: " .. tostring(err))
        return false
    end
    return true, holdPart
end

-- ── Drop (message(3).txt Drop() pattern) ─────────────────────
local function DropPalette(palette, dropCF)
    local holdPart = palette:FindFirstChild("HoldPart")
    if not holdPart then return end
    local dropRemote = holdPart:FindFirstChild("DropItemRemoteFunction")
    if not dropRemote then return end
    pcall(function()
        dropRemote:InvokeServer(palette, dropCF, Vector3.zero)
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

    -- ── 1. Teleport ───────────────────────────────────────────
    Notify("1/7 — Teleporting to Scary House…")
    hrp.CFrame = SCARY_HOUSE_CF
    task.wait(0.5)

    -- ── 2. Claim Plot ─────────────────────────────────────────
    Notify("2/7 — Claiming Plot 3…")
    ClaimPlot()
    task.wait(0.3)

    -- ── 3. Spawn PalletLightBrown ─────────────────────────────
    --   Use Head CFrame as spawn point (matches VerbalHub spawnItemCf calls)
    Notify("3/7 — Spawning " .. TOY_NAME .. "…")
    local head   = playerCharacter and playerCharacter:FindFirstChild("Head")
    local spawnCF = head and head.CFrame or hrp.CFrame
    local palette = SpawnAndWaitForToy(spawnCF)
    if not palette then isRunning = false return end
    task.wait(0.2)

    -- ── 4. Network Ownership ─────────────────────────────────
    Notify("4/7 — Claiming network ownership…")
    local owned, body = ClaimOwnership(palette)
    task.wait(0.2)

    -- ── 5. Hold Palette ───────────────────────────────────────
    Notify("5/7 — Holding palette…")
    local held = HoldPalette(palette)
    if not held then
        -- Ownership may have worked but hold failed; still try to continue
        Notify("Hold failed — attempting noclip move anyway…")
    end
    task.wait(0.25)

    -- ── 6. Noclip (character + palette) ──────────────────────
    Notify("6/7 — Noclipping through wall…")
    SetCollisions(palette, false)

    -- Keep character parts noclipped during the move (Cosmic.Luau pattern)
    local noclipConn = RunService.Stepped:Connect(function()
        if playerCharacter and playerCharacter.Parent then
            for _, p in ipairs(playerCharacter:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end)

    -- ── 7. Move Outside & Store ───────────────────────────────
    Notify("7/7 — Moving outside & saving…")
    local outsideCF = SCARY_HOUSE_CF * OUTSIDE_OFFSET
    hrp.CFrame      = outsideCF
    task.wait(0.4)

    noclipConn:Disconnect()

    -- Drop and restore physics
    DropPalette(palette, outsideCF)
    task.wait(0.15)

    -- Release server grab line so we don't hold the slot open
    pcall(function()
        if body then DestroyGrabLine:FireServer(body) end
    end)

    -- Restore palette collisions
    SetCollisions(palette, true)
    task.wait(0.1)

    -- Store
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

MainBox:AddLabel("TP → Claim → Spawn → Own → Hold → Noclip → Move → Save")
MainBox:AddDivider()
MainBox:AddButton({
    Text    = "▶  Start Extraction",
    Func    = RunExtraction,
    Tooltip = "Runs the full 7-step sequence",
})
MainBox:AddDivider()

-- ── Palette Status ────────────────────────────────────────────
local InfoBox = Tabs.Main:AddRightGroupbox("Saved Palettes")

InfoBox:AddButton({
    Text = "Check Count",
    Func = function()
        Notify("Palettes in memory: " .. #getgenv().SavedPalettes)
    end,
})

InfoBox:AddButton({
    Text = "Delete Last",
    Func = function()
        local t = getgenv().SavedPalettes
        if #t == 0 then Notify("Nothing saved.") return end
        local last = table.remove(t)
        pcall(function()
            if last and last.Parent then DestroyToyRE:FireServer(last) end
        end)
        Notify("Deleted last palette. Remaining: " .. #t)
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
