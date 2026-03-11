-- [[ 1. INITIALIZATION ]]
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local Options = Library.Options

-- [[ 2. VARIABLES FROM YOUR SOURCE ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage") [cite: 1]
local Players = game:GetService("Players") [cite: 1]
local LocalPlayer = Players.LocalPlayer [cite: 1]
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() [cite: 1]
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 0.5) [cite: 1]

local MenuToys = ReplicatedStorage:WaitForChild("MenuToys") [cite: 2]
local SpawnToyRemoteFunction = MenuToys:WaitForChild("SpawnToyRemoteFunction") [cite: 3]
local DestroyToy = MenuToys:WaitForChild("DestroyToy") [cite: 3]
local ToyFolder = workspace:WaitForChild(LocalPlayer.Name.."SpawnedInToys") [cite: 6, 7]

-- Target House
local BlueHouseCF = CFrame.new(497.69, 85.28, -352.05)

-- [[ 3. BYPASS LOGIC ]]
local function ExecuteBlueHouseGlitch()
    local foodName = Options.BypassToy.Value
    if not HumanoidRootPart then return end

    -- STEP 1: SPAWN OUTSIDE (50 studs away from the house to be safe)
    local outsideCF = BlueHouseCF * CFrame.new(0, 0, 50)
    Library:Notify("Step 1: Spawning " .. foodName .. " outside...")

    local Toy = nil
    local connection
    -- Waiting on it being spawned 
    connection = ToyFolder.ChildAdded:Connect(function(Child)
        if Child.Name == foodName then
            Toy = Child
        end
    end)

    -- Spawn the toy using your source logic 
    task.spawn(function() 
        SpawnToyRemoteFunction:InvokeServer(foodName, outsideCF, Vector3.zero) 
    end)
    
    repeat task.wait() until Toy
    if connection then connection:Disconnect() end

    -- STEP 2: HOLD IT (As Food) 
    Library:Notify("Step 2: Holding item...")
    local HoldPart = Toy:WaitForChild("HoldPart", 1) [cite: 4, 5]
    if HoldPart then
        local HoldFunction = HoldPart:WaitForChild("HoldItemRemoteFunction", 1) [cite: 4, 5]
        if HoldFunction then
            -- Holding it as a food item 
            HoldFunction:InvokeServer(Toy, Character)
            task.wait(0.2) -- Give the server a moment to attach it to your character

            -- STEP 3: TELEPORT INSIDE HOUSE
            Library:Notify("Step 3: Teleporting inside Blue House...")
            HumanoidRootPart.CFrame = BlueHouseCF
            task.wait(0.1) -- Let your character physically register inside the house

            -- STEP 4: DROP & DELETE AT THE SAME TIME
            local DropFunction = HoldPart:WaitForChild("DropItemRemoteFunction", 1) [cite: 5]
            if DropFunction then
                Library:Notify("Step 4: Atomic Drop & Delete!")
                -- Fire Drop and Destroy simultaneously [cite: 4, 5, 7]
                task.spawn(function()
                    DropFunction:InvokeServer(Toy, HumanoidRootPart.CFrame, Vector3.zero) [cite: 4, 5]
                end)
                DestroyToy:FireServer(Toy) [cite: 7]
            end
        end
    end
end

-- [[ 4. UI SETUP ]]
local Window = Library:CreateWindow({ Title = "OBSIDIAN | TP BYPASS", Center = true, AutoShow = true })
local Tabs = { Main = Window:AddTab("Main"), Settings = Window:AddTab("Settings") }

local MainBox = Tabs.Main:AddLeftGroupbox("House Teleport Glitch")

MainBox:AddInput("BypassToy", { 
    Default = "FoodMayonnaise", 
    Text = "Food Item to Use" 
})

MainBox:AddButton({
    Text = "Execute Blue House Bypass",
    Func = ExecuteBlueHouseGlitch,
    Tooltip = "Spawns outside -> Holds -> TPs Inside -> Drops & Deletes"
})

-- [[ 5. SETTINGS & UNLOAD ]]
local SetBox = Tabs.Settings:AddLeftGroupbox("Menu Management")
SetBox:AddButton("Unload Script", function() Library:Unload() end)
SetBox:AddLabel("Toggle UI"):AddKeyPicker("MenuBind", { Default = "End", NoUI = true, Text = "Menu bind" })
Library.ToggleKeybind = Options.MenuBind 

Library:Notify("TP Bypass System Ready")