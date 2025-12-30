------------------------------------------------
-- SERVICES & PLAYER
------------------------------------------------
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

local DEFAULT_WALKSPEED = 16
local FARM_WALKSPEED = 100
local DEFAULT_GRAVITY = Workspace.Gravity

local function onCharacterAdded(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
	
	-- Preserve autofarm state on respawn
	if autofarmEnabled then
		humanoid.WalkSpeed = FARM_WALKSPEED
	else
		humanoid.WalkSpeed = DEFAULT_WALKSPEED
	end
end

player.CharacterAdded:Connect(onCharacterAdded)

------------------------------------------------
-- FOLDERS
------------------------------------------------
local monstersFolder = workspace:FindFirstChild("Monsters")
local collectiblesFolder = workspace:FindFirstChild("Collectibles")

if not monstersFolder then
	warn("Monsters folder not found in workspace!")
	monstersFolder = workspace:WaitForChild("Monsters", 10)
end

if not collectiblesFolder then
	warn("Collectibles folder not found in workspace!")
	collectiblesFolder = workspace:WaitForChild("Collectibles", 10)
end

if not monstersFolder or not collectiblesFolder then
	error("Required folders not found - script cannot run")
end

------------------------------------------------
-- STATE
------------------------------------------------
local autofarmEnabled = false
local collectiblesEnabled = true

local monsterList = {}
local teleportHeight = 4

local COLLECTIBLE_RANGE = 150
local COLLECTIBLE_HEIGHT = 0.5

------------------------------------------------
-- GUI
------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AutofarmGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(0.22, 0.36)
frame.Position = UDim2.fromScale(0.39, 0.3)
frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.fromScale(0.9, 0.18)
toggleButton.Position = UDim2.fromScale(0.05, 0.05)
toggleButton.Text = "Autofarm: OFF"
toggleButton.BackgroundColor3 = Color3.fromRGB(170,0,0)
toggleButton.TextColor3 = Color3.new(1,1,1)
toggleButton.Parent = frame

local collectibleButton = Instance.new("TextButton")
collectibleButton.Size = UDim2.fromScale(0.9, 0.18)
collectibleButton.Position = UDim2.fromScale(0.05, 0.27)
collectibleButton.Text = "Collectibles: ON"
collectibleButton.BackgroundColor3 = Color3.fromRGB(0,120,170)
collectibleButton.TextColor3 = Color3.new(1,1,1)
collectibleButton.Parent = frame

local heightBox = Instance.new("TextBox")
heightBox.Size = UDim2.fromScale(0.9, 0.18)
heightBox.Position = UDim2.fromScale(0.05, 0.49)
heightBox.Text = "Height: 4"
heightBox.BackgroundColor3 = Color3.fromRGB(40,40,40)
heightBox.TextColor3 = Color3.new(1,1,1)
heightBox.ClearTextOnFocus = false
heightBox.Parent = frame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromScale(0.9, 0.15)
closeButton.Position = UDim2.fromScale(0.05, 0.75)
closeButton.Text = "Close GUI"
closeButton.BackgroundColor3 = Color3.fromRGB(70,70,70)
closeButton.TextColor3 = Color3.new(1,1,1)
closeButton.Parent = frame

------------------------------------------------
-- GUI LOGIC
------------------------------------------------
heightBox.FocusLost:Connect(function()
	local num = tonumber(heightBox.Text:match("[%d%.]+"))
	if num then teleportHeight = math.clamp(num, 0, 50) end
	heightBox.Text = "Height: " .. teleportHeight
end)

toggleButton.MouseButton1Click:Connect(function()
	autofarmEnabled = not autofarmEnabled

	if not autofarmEnabled then
		humanoid.WalkSpeed = DEFAULT_WALKSPEED
		Workspace.Gravity = DEFAULT_GRAVITY
	end

	toggleButton.Text = autofarmEnabled and "Autofarm: ON" or "Autofarm: OFF"
	toggleButton.BackgroundColor3 =
		autofarmEnabled and Color3.fromRGB(0,170,0) or Color3.fromRGB(170,0,0)
end)

collectibleButton.MouseButton1Click:Connect(function()
	collectiblesEnabled = not collectiblesEnabled
	collectibleButton.Text = collectiblesEnabled and "Collectibles: ON" or "Collectibles: OFF"
	collectibleButton.BackgroundColor3 =
		collectiblesEnabled and Color3.fromRGB(0,120,170) or Color3.fromRGB(100,100,100)
end)

closeButton.MouseButton1Click:Connect(function()
	-- Turn off autofarm before closing
	autofarmEnabled = false
	humanoid.WalkSpeed = DEFAULT_WALKSPEED
	Workspace.Gravity = DEFAULT_GRAVITY
	
	gui.Enabled = false
end)

------------------------------------------------
-- MONSTERS
------------------------------------------------
local function isValidMonster(monster)
	if not monster or not monster.Parent then return false end
	local hum = monster:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

local function getRoot(model)
	if not model or not model.Parent then return nil end
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function refreshMonsters()
	monsterList = {}
	if not monstersFolder then return end
	
	for _, m in ipairs(monstersFolder:GetChildren()) do
		if m:IsA("Model") and isValidMonster(m) then
			table.insert(monsterList, m)
		end
	end
end

------------------------------------------------
-- COLLECTIBLES
------------------------------------------------
local function collectibleExists(obj)
	return obj and obj.Parent and (obj.Parent == collectiblesFolder or obj.Parent.Parent == collectiblesFolder)
end

local function getCollectiblePosition(obj)
	if not collectibleExists(obj) then return nil end
	
	if obj:IsA("BasePart") then
		return obj.Position
	elseif obj:IsA("Model") then
		local root = getRoot(obj)
		return root and root.Position
	end
end

------------------------------------------------
-- AUTOFARM LOOP
------------------------------------------------
local farmLoop = task.spawn(function()
	while true do
		-- Safety check for character
		if not character or not character.Parent or not hrp or not hrp.Parent or not humanoid or not humanoid.Parent then
			task.wait(1)
			continue
		end
		
		if autofarmEnabled then
			refreshMonsters()

			-- NO ENEMIES → WALK TO COLLECTIBLES (chain closest)
			if #monsterList == 0 and collectiblesEnabled then
				humanoid.WalkSpeed = FARM_WALKSPEED

				-- Wait for a collectible to appear if none exist
				local allCollectibles = collectiblesFolder:GetChildren()
				if #allCollectibles == 0 then
					-- Wait for new collectible to be added
					local newCollectible = collectiblesFolder.ChildAdded:Wait()
				end

				-- Find closest collectible to player as starting point
				local currentTarget = nil
				local closestDist = math.huge
				
				for _, c in ipairs(collectiblesFolder:GetChildren()) do
					if collectibleExists(c) then
						local pos = getCollectiblePosition(c)
						if pos then
							local dist = (pos - hrp.Position).Magnitude
							if dist < closestDist then
								closestDist = dist
								currentTarget = c
							end
						end
					end
				end

				-- Chain through collectibles, always picking the closest to current target
				local visitedCollectibles = {}
				
				while currentTarget and autofarmEnabled do
					-- Double-check monster list before moving
					refreshMonsters()
					if #monsterList > 0 then break end

					-- Verify target still exists
					if not collectibleExists(currentTarget) then
						-- Find a new target that hasn't been visited
						currentTarget = nil
						closestDist = math.huge
						
						for _, c in ipairs(collectiblesFolder:GetChildren()) do
							if collectibleExists(c) and not visitedCollectibles[c] then
								local pos = getCollectiblePosition(c)
								if pos then
									local dist = (pos - hrp.Position).Magnitude
									if dist < closestDist then
										closestDist = dist
										currentTarget = c
									end
								end
							end
						end
						
						if not currentTarget then break end
					end

					local targetPos = getCollectiblePosition(currentTarget)
					if targetPos and humanoid and humanoid.Parent then
						humanoid:MoveTo(targetPos)
						
						-- Wait for move to finish with timeout
						local moveConnection
						local finished = false
						
						moveConnection = humanoid.MoveToFinished:Connect(function()
							finished = true
						end)
						
						-- Wait up to 2 seconds for move to complete
						local startTime = tick()
						while not finished and tick() - startTime < 2 do
							task.wait(0.04)
							-- Check if collectible was collected/removed during movement
							if not collectibleExists(currentTarget) then
								break
							end
						end
						
						if moveConnection then
							moveConnection:Disconnect()
						end
					end

					-- Mark as visited
					visitedCollectibles[currentTarget] = true

					-- Find next closest collectible to CURRENT TARGET (not player)
					local nextTarget = nil
					closestDist = math.huge
					
					for _, c in ipairs(collectiblesFolder:GetChildren()) do
						if collectibleExists(c) and not visitedCollectibles[c] then
							local pos = getCollectiblePosition(c)
							if pos and targetPos then
								local dist = (pos - targetPos).Magnitude
								if dist < closestDist then
									closestDist = dist
									nextTarget = c
								end
							end
						end
					end

					currentTarget = nextTarget
				end

			-- ENEMIES EXIST → TELEPORT FARM
			else
				humanoid.WalkSpeed = DEFAULT_WALKSPEED
				
				-- Set gravity to 0 while farming enemies
				Workspace.Gravity = 0

				local delayTime = #monsterList < 8 and 0.1 or 0.05

				for _, monster in ipairs(monsterList) do
					if not autofarmEnabled then break end
					if isValidMonster(monster) then
						local root = getRoot(monster)
						if root and root.Parent then
							local pos = root.Position + Vector3.new(0, teleportHeight, 0)
							hrp.CFrame = CFrame.lookAt(pos, root.Position)
							hrp.AssemblyLinearVelocity = Vector3.zero
							hrp.AssemblyAngularVelocity = Vector3.zero
							task.wait(delayTime)
						end
					end
				end
				
				-- Reset gravity after farming enemies
				Workspace.Gravity = DEFAULT_GRAVITY
			end
		end
		task.wait(0.1)
	end
end)

-- Cleanup on script removal
script.Destroying:Connect(function()
	-- Turn off autofarm and reset states
	autofarmEnabled = false
	humanoid.WalkSpeed = DEFAULT_WALKSPEED
	Workspace.Gravity = DEFAULT_GRAVITY
	
	if farmLoop then
		task.cancel(farmLoop)
	end
	if gui then
		gui:Destroy()
	end
end)

-- Cleanup when GUI is destroyed
gui.Destroying:Connect(function()
	-- Turn off autofarm and reset states
	autofarmEnabled = false
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = DEFAULT_WALKSPEED
	end
	Workspace.Gravity = DEFAULT_GRAVITY
	
	if farmLoop then
		task.cancel(farmLoop)
	end
end)
