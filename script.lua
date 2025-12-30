------------------------------------------------
-- SERVICES & PLAYER
------------------------------------------------
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

local DEFAULT_WALKSPEED = 16
local FARM_WALKSPEED = 100

local function onCharacterAdded(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
	humanoid.WalkSpeed = DEFAULT_WALKSPEED
	hrp.Anchored = false
end

player.CharacterAdded:Connect(onCharacterAdded)

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
		hrp.Anchored = false
		humanoid.WalkSpeed = DEFAULT_WALKSPEED
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
	gui.Enabled = false
end)

------------------------------------------------
-- MONSTERS
------------------------------------------------
local function isValidMonster(monster)
	local hum = monster:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
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

------------------------------------------------
-- COLLECTIBLES
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
	local list = {}
	for _, c in ipairs(collectiblesFolder:GetChildren()) do
		local pos = getCollectiblePosition(c)
		if pos and (pos - hrp.Position).Magnitude <= COLLECTIBLE_RANGE then
			table.insert(list, c)
		end
	end
	return list
end

------------------------------------------------
-- AUTOFARM LOOP
------------------------------------------------
task.spawn(function()
	while true do
		if autofarmEnabled then
			refreshMonsters()

			------------------------------------------------
			-- NO ENEMIES → WALK TO COLLECTIBLES
			------------------------------------------------
			if #monsterList == 0 and collectiblesEnabled then
				hrp.Anchored = false
				humanoid.WalkSpeed = FARM_WALKSPEED

				for _, collectible in ipairs(getNearbyCollectibles()) do
					if not autofarmEnabled then break end
					refreshMonsters()
					if #monsterList > 0 then break end

					local pos = getCollectiblePosition(collectible)
					if pos then
						humanoid:MoveTo(pos)
						humanoid.MoveToFinished:Wait(2)
					end
				end

			------------------------------------------------
			-- ENEMIES EXIST → TELEPORT FARM
			------------------------------------------------
			else
				humanoid.WalkSpeed = DEFAULT_WALKSPEED
				hrp.Anchored = true

				local delayTime = #monsterList < 8 and 0.25 or 0.1

				for _, monster in ipairs(monsterList) do
					if not autofarmEnabled then break end
					if isValidMonster(monster) then
						local root = getRoot(monster)
						if root then
							local pos = root.Position + Vector3.new(0, teleportHeight, 0)
							hrp.CFrame = CFrame.lookAt(pos, root.Position)
							enemyCounter += 1
							task.wait(delayTime)
						end
					end
				end
			end
		end
		task.wait(0.1)
	end
end)
