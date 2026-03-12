-- [[ 1. INITIALIZATION ]]
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

-- [[ 2. CORE SERVICES FROM YOUR SOURCE ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- [cite: 1]
local Players = game:GetService("Players") -- [cite: 1]
local LocalPlayer = Players.LocalPlayer -- [cite: 1]

-- Remotes and Folders exactly as defined in your file
local MenuToys = ReplicatedStorage:WaitForChild("MenuToys") -- [cite: 1]
local SpawnToyRemoteFunction = MenuToys:WaitForChild("SpawnToyRemoteFunction") -- [cite: 3]
local DestroyToy = MenuToys:WaitForChild("DestroyToy") -- [cite: 3]
local ToyFolder = workspace:WaitForChild(LocalPlayer.Name.."SpawnedInToys") -- [cite: 6]

-- Coordinates
local BlueHouseCF = CFrame.new(497.69, 85.28, -352.05)

-- [[ 3. BYPASS LOGIC ]]
local function RunAtomicBypass()
    -- FIX: Pulling values directly inside the function to avoid the 'nil' error
    local toyName = Library.Options.ToyInput.Value
    local Character = LocalPlayer.Character
    local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart") -- [cite: 1]

    if not HumanoidRootPart then return Library:Notify("Wait for character to load!") end

    -- STEP 1: SPAWN OUTSIDE (Offset 30 studs from house)
    local outsidePos = BlueHouseCF * CFrame.new(0, 0, 30)
    Library:Notify("Step 1: Spawning " .. toyName .. " outside...")

    local Toy = nil
    -- Using the listener logic from your source [cite: 6]
    local connection = ToyFolder.ChildAdded:Connect(function(Child)
        if Child.Name == toyName then
            Toy = Child
        end
    end)

    -- Invoking spawn [cite: 6]
    task.spawn(function()
        SpawnToyRemoteFunction:InvokeServer(toyName, outsidePos, Vector3.zero)
    end)

    -- Wait for spawn [cite: 6]
    local timeout = tick() + 4
    repeat task.wait() until Toy or tick() > timeout
    connection:Disconnect()

    if not Toy then return Library:Notify("Spawn failed - check name!") end

    -- STEP 2: HOLD IT (Food Logic) 
    Library:Notify("Step 2: Holding item...")
    local HoldPart = Toy:WaitForChild("HoldPart", 2)
    local HoldFunction = HoldPart and HoldPart:WaitForChild("HoldItemRemoteFunction", 2)

    if HoldFunction then
        HoldFunction:InvokeServer(Toy, Character) -- 
        task.wait(0.2) -- Sync delay

        -- STEP 3: TELEPORT INSIDE HOUSE
        Library:Notify("Step 3: Teleporting inside Blue House...")
        HumanoidRootPart.CFrame = BlueHouseCF
        task.wait(0.1)

        -- STEP 4: DROP & DELETE (Same Tick) [cite: 5, 6]
        local DropFunction = HoldPart:WaitForChild("DropItemRemoteFunction", 2)
        if DropFunction then
            Library:Notify("Step 4: Atomic Drop/Destroy!")
            task.spawn(function()
                DropFunction:InvokeServer(Toy, HumanoidRootPart.CFrame, Vector3.zero) -- [cite: 5]
            end)
            DestroyToy:FireServer(Toy) -- [cite: 3, 6]
        end
    end
end

-- [[ 4. UI SETUP ]]
local Window = Library:CreateWindow({ Title = "BYPASS V4", Center = true, AutoShow = true })
local Tabs = { Main = Window:AddTab("Main"), Settings = Window:AddTab("Settings") }
local MainBox = Tabs.Main:AddLeftGroupbox("Blue House Glitch")

-- Use the specific name 'ToyInput' to match your error logs
MainBox:AddInput("ToyInput", { Default = "FoodMayonnaise", Text = "Toy/Food Name" })

MainBox:AddButton({
    Text = "Run Bypass Glitch",
    Func = RunAtomicBypass
})

-- [[ 5. SETTINGS ]]
local SetBox = Tabs.Settings:AddLeftGroupbox("Menu")
SetBox:AddButton("Unload", function() Library:Unload() end)
SetBox:AddLabel("Toggle"):AddKeyPicker("MenuBind", { Default = "End", NoUI = true, Text = "Menu bind" })
Library.ToggleKeybind = Library.Options.MenuBind

Library:Notify("V4")