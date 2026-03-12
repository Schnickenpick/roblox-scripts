-- ============================================================
--   PALETTE BOAT  —  Obsidian Library
--   Spawn logic:  message(3).txt  (SpawnToyRemoteFunction +
--                 HoldItemRemoteFunction pattern)
--   Identity fix: VerbalHub ThisToysNumber/ToyNumber gate
-- ============================================================

-- ── Services ─────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ── Local player / character ──────────────────────────────────
local LocalPlayer     = Players.LocalPlayer
local Character       = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
LocalPlayer.CharacterAdded:Connect(function(c) Character = c end)

local function HRP()
    return Character and Character:FindFirstChild("HumanoidRootPart")
end

-- ── Remotes (message(3).txt names) ───────────────────────────
local MenuToys            = ReplicatedStorage:WaitForChild("MenuToys")
local SpawnToyRemoteFunction = MenuToys:WaitForChild("SpawnToyRemoteFunction")
local DestroyToy          = MenuToys:WaitForChild("DestroyToy")

-- ── Toy folder ────────────────────────────────────────────────
local function ToyFolder()
    return workspace:WaitForChild(LocalPlayer.Name .. "SpawnedInToys", 10)
end

-- ── Constants ─────────────────────────────────────────────────
local TOY_NAME       = "PalletLightBrown"
local SPAWN_AMOUNT   = 20
local SPAWN_TIMEOUT  = 8   -- seconds per palette

-- ── Global fleet table ────────────────────────────────────────
getgenv().MyPaletteFleet = getgenv().MyPaletteFleet or {}

-- ── Obsidian UI ───────────────────────────────────────────────
local Library = loadstring(
    game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua")
)()

-- ── State ─────────────────────────────────────────────────────
local boatMode        = false
local boatOffset      = 0          -- vertical nudge from Slider
local boatConnection  = nil        -- RunService.Heartbeat handle
local isSpawning      = false

-- ============================================================
--   HELPERS
-- ============================================================

local function Notify(msg)
    pcall(function() Library:Notify(msg) end)
    print("[PaletteBoat] " .. tostring(msg))
end

-- Disable / enable collisions on every BasePart of a model
local function SetCollisions(model, state)
    if not model or not model.Parent then return end
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = state end
    end
end

-- Anchor / unanchor every BasePart
local function SetAnchored(model, state)
    if not model or not model.Parent then return end
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = state end
    end
end

-- ── message(3).txt  Hold() ────────────────────────────────────
-- Claims server-side ownership so the item is "ours"
local function Hold(Food)
    local HoldPart = Food:WaitForChild("HoldPart", 0.5)
    if not HoldPart then return end

    local HoldFunction = HoldPart:FindFirstChild("HoldItemRemoteFunction")
    if not HoldFunction then return end

    task.spawn(function()
        HoldFunction:InvokeServer(Food, Character)
    end)
end

-- ── message(3).txt  Drop() ────────────────────────────────────
local function Drop(Food, CF)
    local HoldPart = Food:FindFirstChild("HoldPart")
    if not HoldPart then return end

    local RigidConstraint = HoldPart:FindFirstChild("RigidConstraint")
    if not RigidConstraint then return end

    local LeftGripAttachment = Character
        and Character:FindFirstChild("Left Arm")
        and Character["Left Arm"]:FindFirstChild("LeftGripAttachment")

    if RigidConstraint.Attachment1 == LeftGripAttachment then
        local DropFunction = HoldPart:FindFirstChild("DropItemRemoteFunction")
        if DropFunction then
            task.spawn(function()
                DropFunction:InvokeServer(Food, CF or CFrame.new(), Vector3.zero)
            end)
        end
    end
end

-- ── message(3).txt  Spawn() — with VerbalHub ToyNumber gate ──
-- Spawns ONE palette and returns it (or nil on timeout).
-- Must be called sequentially; the ToyNumber snapshot is taken
-- immediately before InvokeServer so we never misidentify.
local function SpawnOnePalette(spawnCF)
    local folder = ToyFolder()
    if not folder then
        Notify("ERROR: SpawnedInToys folder not found.")
        return nil
    end

    -- Snapshot ToyNumber BEFORE firing (VerbalHub pattern)
    local toyNumVal  = folder:FindFirstChild("ToyNumber")
    local expectedNum = toyNumVal and toyNumVal.Value or nil

    local result = nil
    local done   = false

    -- ChildAdded listener first (message(3).txt Spawn pattern)
    local conn = folder.ChildAdded:Connect(function(child)
        if done or child.Name ~= TOY_NAME then return end

        if expectedNum ~= nil then
            -- Confirm this is OUR toy via ThisToysNumber (VerbalHub gate)
            local numObj = child:WaitForChild("ThisToysNumber", 2)
            if numObj and numObj.Value == expectedNum then
                result = child
                done   = true
            end
        else
            -- ToyNumber missing; fall back to name-only match
            result = child
            done   = true
        end
    end)

    -- Use message(3).txt NewCFrame trick: spawn offset behind the HRP
    local hrp      = HRP()
    local baseCF   = spawnCF or (hrp and hrp.CFrame or CFrame.new())
    local newCF    = baseCF + baseCF.LookVector * -20

    task.spawn(function()
        SpawnToyRemoteFunction:InvokeServer(TOY_NAME, newCF, Vector3.zero)
    end)

    local deadline = tick() + SPAWN_TIMEOUT
    repeat task.wait(0.05) until done or tick() > deadline

    conn:Disconnect()

    if not result or not result.Parent then
        return nil
    end
    return result
end

-- ============================================================
--   BOAT 3D GRID MATH
-- ============================================================
-- Builds a flat list of CFrame offsets for SPAWN_AMOUNT items.
-- Layout: 5 columns × 4 rows arranged as a deck under the player.
-- Items are placed at Y = -3 + boatOffset (just below feet).
-- Extra items beyond the grid are stacked as a hull below.

local COLS     = 5
local ROWS     = 4   -- 5×4 = 20
local SPACING  = 3.5 -- studs between palettes

local function BuildOffsets()
    local offsets = {}
    local idx     = 0

    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            idx = idx + 1
            local x = (col - (COLS - 1) / 2) * SPACING
            local z = (row - (ROWS - 1) / 2) * SPACING
            local y = -3 + boatOffset
            offsets[idx] = CFrame.new(x, y, z)
        end
    end

    -- Any overflow beyond the grid: stack as a second hull layer
    for i = idx + 1, #getgenv().MyPaletteFleet do
        local extra = i - idx
        offsets[i]  = CFrame.new(0, -3 + boatOffset - extra * 1.5, 0)
    end

    return offsets
end

-- ============================================================
--   BOAT MODE — Heartbeat follow loop
-- ============================================================

local function StartBoat()
    if boatConnection then boatConnection:Disconnect() end

    boatConnection = RunService.Heartbeat:Connect(function()
        local fleet = getgenv().MyPaletteFleet
        if #fleet == 0 then return end

        local root = HRP()
        if not root then return end

        local offsets = BuildOffsets()

        for i, palette in ipairs(fleet) do
            if palette and palette.Parent then
                local targetCF = root.CFrame * (offsets[i] or CFrame.new(0, -3, 0))

                -- Move every BasePart of this palette to the target
                -- Using SetPrimaryPartCFrame if PrimaryPart exists, otherwise
                -- move all parts individually.
                local prim = palette.PrimaryPart
                if prim then
                    palette:SetPrimaryPartCFrame(targetCF)
                else
                    for _, p in ipairs(palette:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.CFrame = targetCF
                        end
                    end
                end
            end
        end
    end)
end

local function StopBoat()
    if boatConnection then
        boatConnection:Disconnect()
        boatConnection = nil
    end
end

-- ============================================================
--   MASS SPAWNER
-- ============================================================

local function SpawnFleet()
    if isSpawning then
        Notify("Already spawning — please wait.")
        return
    end

    local hrp = HRP()
    if not hrp then
        Notify("ERROR: No character found.")
        return
    end

    isSpawning = true
    Notify("Spawning " .. SPAWN_AMOUNT .. " palettes…")

    -- Spawn sequentially so ToyNumber snapshots are accurate
    for i = 1, SPAWN_AMOUNT do
        Notify("Spawning palette " .. i .. "/" .. SPAWN_AMOUNT .. "…")

        local palette = SpawnOnePalette(hrp.CFrame)

        if palette then
            -- Claim ownership via Hold (message(3).txt)
            Hold(palette)
            task.wait(0.1)

            -- Physics bypass: noclip + anchor so they don't collide/fling
            SetCollisions(palette, false)
            SetAnchored(palette, true)

            table.insert(getgenv().MyPaletteFleet, palette)
            Notify("✔ Palette " .. i .. " captured.")
        else
            Notify("✘ Palette " .. i .. " timed out — skipping.")
        end

        task.wait(0.15)  -- small gap between spawns to avoid rate limiting
    end

    Notify("Fleet ready! Total: " .. #getgenv().MyPaletteFleet .. " palettes.")
    isSpawning = false

    -- Auto-start boat mode if it was already on
    if boatMode then StartBoat() end
end

-- ============================================================
--   CLEAR FLEET
-- ============================================================

local function ClearFleet()
    StopBoat()

    local fleet = getgenv().MyPaletteFleet
    local count = #fleet

    for _, palette in ipairs(fleet) do
        pcall(function()
            if palette and palette.Parent then
                -- Drop first if held (message(3).txt Drop)
                Drop(palette)
                task.wait(0.05)
                DestroyToy:FireServer(palette)
            end
        end)
    end

    getgenv().MyPaletteFleet = {}
    Notify("Fleet cleared (" .. count .. " palettes removed).")

    -- Restart boat connection if mode is still on (now with empty table)
    if boatMode then StartBoat() end
end

-- ============================================================
--   OBSIDIAN UI
-- ============================================================

local Window = Library:CreateWindow({
    Title    = "OBSIDIAN | PALETTE BOAT",
    Center   = true,
    AutoShow = true,
})

local Tabs = {
    Main  = Window:AddTab("Main"),
    Fleet = Window:AddTab("Fleet"),
    Settings = Window:AddTab("Settings"),
}

-- ── Main Tab ─────────────────────────────────────────────────
local SpawnBox = Tabs.Main:AddLeftGroupbox("Spawner")

SpawnBox:AddLabel("Spawns " .. SPAWN_AMOUNT .. " PalletLightBrown via server remote")
SpawnBox:AddDivider()

SpawnBox:AddButton({
    Text    = "▶  Spawn " .. SPAWN_AMOUNT .. " Palettes",
    Func    = function() task.spawn(SpawnFleet) end,
    Tooltip = "Uses SpawnToyRemoteFunction + HoldItemRemoteFunction",
})

SpawnBox:AddButton({
    Text    = "✕  Clear Fleet",
    Func    = ClearFleet,
    Tooltip = "Drops and destroys all fleet palettes",
})

local InfoBox = Tabs.Main:AddRightGroupbox("Fleet Info")

InfoBox:AddButton({
    Text = "Check Count",
    Func = function()
        Notify("Fleet size: " .. #getgenv().MyPaletteFleet .. " palettes")
    end,
})

-- ── Fleet Tab ─────────────────────────────────────────────────
local BoatBox = Tabs.Fleet:AddLeftGroupbox("Boat Mode")

BoatBox:AddLabel("Arranges fleet in a 5×4 deck that follows you every frame")
BoatBox:AddDivider()

BoatBox:AddToggle("BoatModeToggle", {
    Text    = "Boat Mode",
    Default = false,
    Tooltip = "Locks all palettes into formation around HumanoidRootPart",
    Callback = function(val)
        boatMode = val
        if val then
            Notify("Boat Mode ON")
            StartBoat()
        else
            Notify("Boat Mode OFF")
            StopBoat()
        end
    end,
})

BoatBox:AddDivider()

BoatBox:AddSlider("BoatOffsetSlider", {
    Text    = "Vertical Offset",
    Default = 0,
    Min     = -10,
    Max     = 10,
    Rounding = 1,
    Tooltip = "Raise or lower the deck relative to your feet",
    Callback = function(val)
        boatOffset = val
        -- Rebuild if boat is running
        if boatMode and boatConnection then
            -- Offsets are rebuilt dynamically inside Heartbeat, nothing extra needed
            Notify("Offset set to " .. val)
        end
    end,
})

local NoclipBox = Tabs.Fleet:AddRightGroupbox("Physics")

NoclipBox:AddButton({
    Text    = "Re-apply Noclip",
    Tooltip = "Force CanCollide=false + Anchored=true on all fleet items",
    Func    = function()
        local fleet = getgenv().MyPaletteFleet
        for _, p in ipairs(fleet) do
            SetCollisions(p, false)
            SetAnchored(p, true)
        end
        Notify("Re-applied noclip to " .. #fleet .. " palettes.")
    end,
})

NoclipBox:AddButton({
    Text    = "Restore Physics",
    Tooltip = "Re-enable collisions and unanchor all fleet items",
    Func    = function()
        local fleet = getgenv().MyPaletteFleet
        for _, p in ipairs(fleet) do
            SetCollisions(p, true)
            SetAnchored(p, false)
        end
        Notify("Physics restored on " .. #fleet .. " palettes.")
    end,
})

-- ── Settings Tab ──────────────────────────────────────────────
local SetBox = Tabs.Settings:AddLeftGroupbox("Menu")

SetBox:AddButton("Unload", function() Library:Unload() end)
SetBox:AddLabel("Toggle Keybind"):AddKeyPicker("MenuBind", {
    Default = "End",
    NoUI    = true,
    Text    = "Menu bind",
})
Library.ToggleKeybind = Library.Options.MenuBind

-- ── Done ──────────────────────────────────────────────────────
Notify("Palette Boat loaded. Spawn your fleet then enable Boat Mode!")
