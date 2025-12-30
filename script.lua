------------------------------------------------
-- SERVICES & PLAYER
------------------------------------------------
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
	character = char
	hrp = char:WaitForChild("HumanoidRootPart")
end)

------------------------------------------------
-- FOLDERS
------------------------------------------------
local monstersFolder = workspace:WaitForChild("Monsters")
local collectiblesFolder = workspace:WaitForChild("Collectibles")

------------------------------------------------
-- STATE
------------------------------------------------
local autofarmEnabled = false
local collectiblesEnabled = true
local monsterList = {}
local teleportHeight = 4
local enemyCounter = 0
local COLLECTIBLE_RANGE = 400

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
	if num then
		teleportHeight = math.clamp(num, 0, 50)
	end
	heightBox.Text = "Height: " .. teleportHeight
end)

toggleButton.MouseButton1Click:Connect(function()
	autofarmEnabled = not autofarmEnabled
	toggleButton.Text = autofarmEnabled and "Autofarm: ON" or "Autofarm: OFF"
	toggleButton.BackgroundColor3 = autofarmEnabled and Color3.fromRGB(0,170,0) or Color3.fromRGB(170,0,0)
end)

collectibleButton.MouseButton1Click:Connect(function()
	collectiblesEnabled = not collectiblesEnabled
	collectibleButton.Text = collectiblesEnabled and "Collectibles: ON" or "Collectibles: OFF"
	collectibleButton.BackgroundColor3 = collectiblesEnabled and Color3.fromRGB(0,120,170) or Color3.fromRGB(100,100,100)
end)

closeButton.MouseButton1Click:Connect(function()
	gui.Enabled = false
end)

------------------------------------------------
-- MONSTER HANDLING
------------------------------------------------
local function isValidMonster(monster)
	if not monster or not monster.Parent then return false end
	local humanoid = monster:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0
end

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function refreshMonsters()
	monsterList = {}
	for _, m in ipairs(monstersFolder:GetChildren()) do
		if m:IsA("Model") and isValidMonster(m) then
			table.insert(monsterList, m)
		end
	end
end

monstersFolder.ChildAdded:Connect(refreshMonsters)
monstersFolder.ChildRemoved:Connect(refreshMonsters)
refreshMonsters()

------------------------------------------------
-- COLLECTIBLES (OPTIONAL)
------------------------------------------------
local function getCollectiblePosition(obj)
	if obj:IsA("BasePart") then
		return obj.Position
	elseif obj:IsA("Model") then
		local root = getRoot(obj)
		return root and root.Position
	end
end

local function getNearbyCollectibles()
	if not collectiblesEnabled or not hrp then
		return {}
	end

	local nearby = {}
	for _, collectible in ipairs(collectiblesFolder:GetChildren()) do
		local pos = getCollectiblePosition(collectible)
		if pos and (pos - hrp.Position).Magnitude <= COLLECTIBLE_RANGE then
			table.insert(nearby, collectible)
		end
	end
	return nearby
end

local function teleportToCollectible(obj)
	if not collectiblesEnabled then return end
	local pos = getCollectiblePosition(obj)
	if pos then
		hrp.CFrame = CFrame.new(pos + Vector3.new(0, teleportHeight, 0))
	end
end

------------------------------------------------
-- AUTOFARM LOOP
------------------------------------------------
task.spawn(function()
	while true do
		if autofarmEnabled and hrp then
			refreshMonsters()
			local enemyCount = #monsterList

			-- NO ENEMIES → COLLECTIBLES (IF ENABLED)
			if enemyCount == 0 then
				if collectiblesEnabled then
					for _, collectible in ipairs(getNearbyCollectibles()) do
						if not autofarmEnabled or not collectiblesEnabled then break end
						teleportToCollectible(collectible)
						task.wait(0.1)
					end
				end
			else
				local delayTime = enemyCount < 8 and 0.2 or 0.05

				for _, monster in ipairs(monsterList) do
					if not autofarmEnabled then break end
					if isValidMonster(monster) then
						local root = getRoot(monster)
						if root then
							local pos = root.Position + Vector3.new(0, teleportHeight, 0)
							hrp.CFrame = CFrame.lookAt(pos, root.Position)
							enemyCounter += 1
							task.wait(delayTime)

							-- EVERY 3 ENEMIES → COLLECTIBLE (IF ENABLED)
							if collectiblesEnabled and enemyCounter % 3 == 0 then
								local nearby = getNearbyCollectibles()
								if #nearby > 0 then
									teleportToCollectible(nearby[math.random(#nearby)])
									task.wait(0.1)
								end
							end
						end
					end
				end
			end
		end
		task.wait(0.1)
	end
end)
