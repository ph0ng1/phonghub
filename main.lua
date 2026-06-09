
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

local Settings = {
	-- Highlights
	HighlightEnabled     = false,
	FillTransparency     = 0.55,
	OutlineTransparency  = 0.0,

	-- 2D Box
	BoxEnabled           = false,
	BoxThickness         = 1,

	-- Tracers
	TracerEnabled        = false,
	TracerOrigin         = "Bottom",
	TracerThickness      = 1,

	-- Labels
	HealthBarEnabled     = false,
	NameTagEnabled       = false,
	DistanceLabelEnabled = false,

	-- Logic
	TeamCheckEnabled     = false,
	SeparateColors       = false,
	MaxRenderDistance    = 1000,

	-- Enemy Colors
	EnemyFillColor       = Color3.fromRGB(255, 60,  60),
	EnemyOutlineColor    = Color3.fromRGB(255, 160, 160),
	EnemyTracerColor     = Color3.fromRGB(255, 60,  60),
	EnemyBoxColor        = Color3.fromRGB(255, 60,  60),
	EnemyNameColor       = Color3.fromRGB(255, 60,  60),

	-- Team Colors
	TeamFillColor        = Color3.fromRGB(60,  160, 255),
	TeamOutlineColor     = Color3.fromRGB(160, 220, 255),
	TeamTracerColor      = Color3.fromRGB(60,  160, 255),
	TeamBoxColor         = Color3.fromRGB(60,  160, 255),
	TeamNameColor        = Color3.fromRGB(60,  160, 255),

	-- Aim Assist
	AimAssistEnabled     = false,
	AimStrength          = 0.5,
	AimFOV               = 120,
	AimSmoothing         = 6,
	AimBone              = "Head",
	AimTeamCheck         = false,
	AimWallCheck         = false,
	AimFOVCircle         = false,
	AimFOVColor          = Color3.fromRGB(255, 255, 255),
	AimFOVThickness      = 1,

	-- Triggerbot
	TriggerEnabled       = false,
	TriggerDelay         = 0.05,
	TriggerTeamCheck     = false,
	TriggerWallCheck     = false,
	TriggerBone          = "Head",

	-- Wall Check (ESP)
	WallCheckEnabled     = false,
	WallCheckHideBox     = false,
	WallCheckHideHL      = false,
	WallHiddenBoxColor   = Color3.fromRGB(100, 100, 100),
}

-- ============================================================
-- STATE
-- ============================================================
local highlights         = {}
local perPlayerOverride  = {}
local whitelist          = {}
local triggerCooldown    = false

local aimBindKey         = Enum.UserInputType.MouseButton2
local aimBindLabel       = "RMB"
local isListeningForBind = false

-- ============================================================
-- DRAWING POOL
-- ============================================================
local pools    = {}
local poolIdx  = {}

local function acquireDrawing(dtype)
	pools[dtype]   = pools[dtype]   or {}
	poolIdx[dtype] = poolIdx[dtype] or 0
	poolIdx[dtype] += 1
	local idx = poolIdx[dtype]
	if pools[dtype][idx] then
		pools[dtype][idx].Visible = true
		return pools[dtype][idx]
	end
	local d = Drawing.new(dtype)
	pools[dtype][idx] = d
	return d
end

local function resetPool()
	for dtype, tbl in pairs(pools) do
		for _, d in ipairs(tbl) do d.Visible = false end
		poolIdx[dtype] = 0
	end
end

local function newLine()
	local l = acquireDrawing("Line")
	l.Thickness = Settings.BoxThickness
	return l
end

local function newText()
	local t = acquireDrawing("Text")
	t.Size         = 13
	t.Font = 0 -- Drawing.Fonts.UI (0 = UI font)
	t.Outline      = true
	t.OutlineColor = Color3.fromRGB(0, 0, 0)
	return t
end

local function newQuad()
	local q = acquireDrawing("Quad")
	q.Thickness = Settings.BoxThickness
	q.Filled    = false
	return q
end

-- ============================================================
-- TEAM / VISIBILITY HELPERS
-- ============================================================
local function isTeammate(player)
	if not Settings.TeamCheckEnabled then return false end
	if not LocalPlayer.Team or not player.Team then return false end
	return LocalPlayer.Team == player.Team
end

local function shouldShow(player)
	if whitelist[player] then return false end
	if perPlayerOverride[player] == false then return false end
	if perPlayerOverride[player] == true  then return true  end
	if isTeammate(player) and Settings.TeamCheckEnabled then return false end
	return true
end

local function getColors(player)
	local enemy = not isTeammate(player) or not Settings.SeparateColors
	if enemy then
		return Settings.EnemyFillColor, Settings.EnemyOutlineColor,
		       Settings.EnemyTracerColor, Settings.EnemyBoxColor, Settings.EnemyNameColor
	else
		return Settings.TeamFillColor, Settings.TeamOutlineColor,
		       Settings.TeamTracerColor, Settings.TeamBoxColor, Settings.TeamNameColor
	end
end

-- ============================================================
-- HIGHLIGHT MANAGEMENT
-- ============================================================
local function refreshHighlight(player)
	local char = player.Character
	if not char or not Settings.HighlightEnabled or not shouldShow(player) then
		if highlights[player] then highlights[player]:Destroy(); highlights[player] = nil end
		return
	end
	local hl = highlights[player]
	if not hl then
		hl = Instance.new("Highlight")
		hl.Name   = "PhongHub_HL"
		hl.Parent = char
		highlights[player] = hl
	end
	local fill, outline = getColors(player)
	hl.FillColor           = fill
	hl.OutlineColor        = outline
	hl.FillTransparency    = Settings.FillTransparency
	hl.OutlineTransparency = Settings.OutlineTransparency
	hl.Adornee             = char
end

local function refreshAllHighlights()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then refreshHighlight(p) end
	end
end

local function removeHighlight(player)
	if highlights[player] then highlights[player]:Destroy(); highlights[player] = nil end
end

-- ============================================================
-- 2D BOUNDING BOX
-- ============================================================
local function getBoundingBox2D(char)
	local hrp  = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local head = char:FindFirstChild("Head")
	local topPos    = head and (head.Position + Vector3.new(0, head.Size.Y / 2, 0))
	                       or  (hrp.Position  + Vector3.new(0, 3.5, 0))
	local bottomPos = hrp.Position - Vector3.new(0, 3, 0)
	local halfW = 1.5
	local corners = {
		topPos    + Vector3.new( halfW, 0,  halfW),
		topPos    + Vector3.new(-halfW, 0,  halfW),
		topPos    + Vector3.new( halfW, 0, -halfW),
		topPos    + Vector3.new(-halfW, 0, -halfW),
		bottomPos + Vector3.new( halfW, 0,  halfW),
		bottomPos + Vector3.new(-halfW, 0,  halfW),
		bottomPos + Vector3.new( halfW, 0, -halfW),
		bottomPos + Vector3.new(-halfW, 0, -halfW),
	}
	local minX, minY =  math.huge,  math.huge
	local maxX, maxY = -math.huge, -math.huge
	local anyOnScreen = false
	for _, c in ipairs(corners) do
		local sp, onScreen = Camera:WorldToViewportPoint(c)
		if onScreen or sp.Z > 0 then
			anyOnScreen = true
			if sp.X < minX then minX = sp.X end
			if sp.Y < minY then minY = sp.Y end
			if sp.X > maxX then maxX = sp.X end
			if sp.Y > maxY then maxY = sp.Y end
		end
	end
	if not anyOnScreen then return nil end
	return { minX=minX, minY=minY, maxX=maxX, maxY=maxY, width=maxX-minX, height=maxY-minY }
end

-- ============================================================
-- HEALTH COLOR
-- ============================================================
local function healthColor(frac)
	return Color3.fromRGB(math.floor((1-frac)*200), math.floor(frac*200), 0)
end

-- ============================================================
-- WALL CHECK (ESP)
-- ============================================================
local espRayParams = RaycastParams.new()
espRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isVisible(char, hrp)
	local exclude = { char }
	local lc = LocalPlayer.Character
	if lc then table.insert(exclude, lc) end
	espRayParams.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(Camera.CFrame.Position, hrp.Position - Camera.CFrame.Position, espRayParams)
	if not result then return true end
	return result.Instance:IsDescendantOf(char)
end

-- ============================================================
-- TRACER ORIGIN
-- ============================================================
local function getTracerOrigin()
	local vp = Camera.ViewportSize
	if Settings.TracerOrigin == "Top"    then return Vector2.new(vp.X/2, 0)      end
	if Settings.TracerOrigin == "Center" then return Vector2.new(vp.X/2, vp.Y/2) end
	return Vector2.new(vp.X/2, vp.Y)
end

-- ============================================================
-- AIM ASSIST
-- ============================================================
local aimFOVCircle

local function getAimFOVCircle()
	if not aimFOVCircle then
		aimFOVCircle           = Drawing.new("Circle")
		aimFOVCircle.Filled    = false
		aimFOVCircle.Thickness = Settings.AimFOVThickness
		aimFOVCircle.NumSides  = 64
		aimFOVCircle.Visible   = false
	end
	return aimFOVCircle
end

local function getBestTarget()
	local vp     = Camera.ViewportSize
	local center = Vector2.new(vp.X/2, vp.Y/2)
	local bestPlayer, bestDist = nil, math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		if Settings.AimTeamCheck and isTeammate(player) then continue end
		if whitelist[player] then continue end
		if perPlayerOverride[player] == false then continue end

		local char = player.Character
		if not char then continue end

		local bone = char:FindFirstChild(Settings.AimBone) or char:FindFirstChild("HumanoidRootPart")
		if not bone then continue end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then continue end

		local worldDist = (bone.Position - Camera.CFrame.Position).Magnitude
		if Settings.MaxRenderDistance > 0 and worldDist > Settings.MaxRenderDistance then continue end

		local sp, onScreen = Camera:WorldToViewportPoint(bone.Position)
		if not onScreen then continue end

		-- Wall check for aim
		if Settings.AimWallCheck then
			local hrp2   = char:FindFirstChild("HumanoidRootPart") or bone
			local excl   = { char }
			local lc     = LocalPlayer.Character
			if lc then table.insert(excl, lc) end
			local wp = RaycastParams.new()
			wp.FilterType = Enum.RaycastFilterType.Exclude
			wp.FilterDescendantsInstances = excl
			local res = workspace:Raycast(Camera.CFrame.Position, hrp2.Position - Camera.CFrame.Position, wp)
			if res and not res.Instance:IsDescendantOf(char) then continue end
		end

		local screenDist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
		if screenDist < Settings.AimFOV and screenDist < bestDist then
			bestDist   = screenDist
			bestPlayer = player
		end
	end
	return bestPlayer
end

local function smoothAimAt(worldPos)
	local camCF     = Camera.CFrame
	local desiredCF = CFrame.lookAt(camCF.Position, worldPos)
	local alpha     = math.clamp(Settings.AimStrength / math.max(Settings.AimSmoothing, 1), 0, 1)
	local prevType  = Camera.CameraType
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CFrame     = camCF:Lerp(desiredCF, alpha)
	Camera.CameraType = prevType
end

-- ============================================================
-- RENDER LOOP
-- ============================================================
RunService.RenderStepped:Connect(function()
	resetPool()
	local tracerOrigin = getTracerOrigin()

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		if not shouldShow(player) then continue end
		local char = player.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		local dist = (hrp.Position - Camera.CFrame.Position).Magnitude
		if Settings.MaxRenderDistance > 0 and dist > Settings.MaxRenderDistance then continue end

		local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
		if not onScreen then continue end

		local sp2D = Vector2.new(screenPos.X, screenPos.Y)
		local _, _, tracerColor, boxColor, nameColor = getColors(player)

		-- Wall check
		if Settings.WallCheckEnabled then
			local visible = isVisible(char, hrp)
			if not visible and Settings.WallCheckHideBox then continue end
			if not visible then
				boxColor    = Settings.WallHiddenBoxColor
				tracerColor = Settings.WallHiddenBoxColor
				nameColor   = Settings.WallHiddenBoxColor
			end
			if highlights[player] then
				highlights[player].Enabled = not (not visible and Settings.WallCheckHideHL)
			end
		end

		-- 2D Box
		local box
		if Settings.BoxEnabled then
			box = getBoundingBox2D(char)
			if box then
				local q = newQuad()
				q.PointA    = Vector2.new(box.minX, box.minY)
				q.PointB    = Vector2.new(box.maxX, box.minY)
				q.PointC    = Vector2.new(box.maxX, box.maxY)
				q.PointD    = Vector2.new(box.minX, box.maxY)
				q.Color     = boxColor
				q.Thickness = Settings.BoxThickness
				q.Visible   = true
			end
		end

		-- Health Bar
		if Settings.HealthBarEnabled and box then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				local frac   = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
				local barX   = box.minX - 5
				local bg     = newLine()
				bg.From      = Vector2.new(barX, box.minY)
				bg.To        = Vector2.new(barX, box.maxY)
				bg.Thickness = 4
				bg.Color     = Color3.fromRGB(20, 20, 20)
				bg.Visible   = true
				local fill   = newLine()
				fill.From    = Vector2.new(barX, box.maxY)
				fill.To      = Vector2.new(barX, box.maxY - box.height * frac)
				fill.Thickness = 3
				fill.Color   = healthColor(frac)
				fill.Visible = true
			end
		end

		-- Name Tag
		if Settings.NameTagEnabled and box then
			local t    = newText()
			t.Text     = player.DisplayName
			t.Color    = nameColor
			t.Size     = 13
			t.Position = Vector2.new(box.minX + box.width/2 - (#player.DisplayName * 3.5), box.minY - 16)
			t.Visible  = true
		end

		-- Distance Label
		if Settings.DistanceLabelEnabled and box then
			local lbl  = string.format("[%d studs]", math.floor(dist))
			local t    = newText()
			t.Text     = lbl
			t.Color    = Color3.fromRGB(180, 180, 180)
			t.Size     = 12
			t.Position = Vector2.new(box.minX + box.width/2 - (#lbl * 3), box.maxY + 3)
			t.Visible  = true
		end

		-- Tracer
		if Settings.TracerEnabled then
			local l     = newLine()
			l.From      = tracerOrigin
			l.To        = sp2D
			l.Thickness = Settings.BoxThickness
			l.Color     = tracerColor
			l.Visible   = true
		end
	end

	-- FOV Circle
	local fovC          = getAimFOVCircle()
	local vp            = Camera.ViewportSize
	fovC.Position       = Vector2.new(vp.X/2, vp.Y/2)
	fovC.Radius         = Settings.AimFOV
	fovC.Color          = Settings.AimFOVColor
	fovC.Thickness      = Settings.AimFOVThickness
	fovC.Visible        = Settings.AimFOVCircle and Settings.AimAssistEnabled

	-- Aim Assist
	if Settings.AimAssistEnabled and not isListeningForBind then
		local holding = false
		if typeof(aimBindKey) == "EnumItem" then
			if aimBindKey.EnumType == Enum.UserInputType then
				holding = UserInputService:IsMouseButtonPressed(aimBindKey)
			elseif aimBindKey.EnumType == Enum.KeyCode then
				holding = UserInputService:IsKeyDown(aimBindKey)
			end
		end
		if holding then
			local target = getBestTarget()
			if target and target.Character then
				local bone = target.Character:FindFirstChild(Settings.AimBone)
					or target.Character:FindFirstChild("HumanoidRootPart")
				if bone then smoothAimAt(bone.Position) end
			end
		end
	end

	-- Triggerbot
	if Settings.TriggerEnabled then
		local lc = LocalPlayer.Character
		if lc then
			local cam    = Camera.CFrame
			local vp     = Camera.ViewportSize
			local ray    = Camera:ScreenPointToRay(vp.X/2, vp.Y/2)
			local rp     = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { lc }
			local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, rp)

			if result and result.Instance then
				local hit = result.Instance
				for _, player in ipairs(Players:GetPlayers()) do
					if player == LocalPlayer then continue end
					if Settings.TriggerTeamCheck and isTeammate(player) then continue end
					local tChar = player.Character
					if not tChar then continue end
					if not hit:IsDescendantOf(tChar) then continue end

					-- Wall check
					if Settings.TriggerWallCheck then
						local tHRP = tChar:FindFirstChild("HumanoidRootPart")
						if tHRP then
							local excl = { tChar, lc }
							local wp   = RaycastParams.new()
							wp.FilterType = Enum.RaycastFilterType.Exclude
							wp.FilterDescendantsInstances = excl
							local wr = workspace:Raycast(cam.Position, tHRP.Position - cam.Position, wp)
							if wr then break end
						end
					end

					-- Fire with delay + cooldown so it doesn't spam
					if not triggerCooldown then
						triggerCooldown = true
						task.delay(Settings.TriggerDelay, function()
							if not Settings.TriggerEnabled then
								triggerCooldown = false
								return
							end
							-- Try all executor click methods
							if mouse1click then
								pcall(mouse1click)
							elseif Input and Input.MouseClick then
								pcall(Input.MouseClick)
							elseif syn and syn.mouse_click then
								pcall(syn.mouse_click)
							else
								-- Universal fallback: fire InputBegan/Ended events
								local uis = game:GetService("UserInputService")
								local vib = Instance.new("InputObject")
								vib.UserInputType = Enum.UserInputType.MouseButton1
								vib.UserInputState = Enum.UserInputState.Begin
								uis:FireInputEvent(vib)
								task.wait(0.05)
								vib.UserInputState = Enum.UserInputState.End
								uis:FireInputEvent(vib)
							end
							task.wait(0.15) -- min time between shots
							triggerCooldown = false
						end)
					end
					break
				end
			end
		end
	end
end)

-- ============================================================
-- PLAYER LIFECYCLE
-- ============================================================
local function setupPlayer(player)
	if player == LocalPlayer then return end
	local function applyToChar(char)
		local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
		if not hrp then return end
		refreshHighlight(player)
	end
	if player.Character then applyToChar(player.Character) end
	player.CharacterAdded:Connect(applyToChar)
end

for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end
Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	removeHighlight(player)
	perPlayerOverride[player] = nil
	whitelist[player] = nil
end)

-- ============================================================
-- MOVEMENT FEATURES
-- ============================================================
local movementState = { flyEnabled=false, noclipEnabled=false, infJumpEnabled=false }
local flySpeed      = 50
local flyBodyVel, flyBodyGyro, flyConn, noclipConn, infJumpConn

local function startFly()
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	hum.PlatformStand = true
	flyBodyVel = Instance.new("BodyVelocity")
	flyBodyVel.MaxForce = Vector3.new(1e5,1e5,1e5); flyBodyVel.Velocity = Vector3.zero
	flyBodyVel.Parent = hrp
	flyBodyGyro = Instance.new("BodyGyro")
	flyBodyGyro.MaxTorque = Vector3.new(1e5,1e5,1e5); flyBodyGyro.P = 1e4
	flyBodyGyro.CFrame = hrp.CFrame; flyBodyGyro.Parent = hrp
	flyConn = RunService.RenderStepped:Connect(function()
		if not movementState.flyEnabled then return end
		local camCF = Camera.CFrame
		local dir   = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += camCF.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= camCF.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= camCF.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += camCF.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.new(0,1,0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0,1,0) end
		flyBodyVel.Velocity  = dir.Magnitude > 0 and dir.Unit * flySpeed or Vector3.zero
		flyBodyGyro.CFrame   = camCF
	end)
end

local function stopFly()
	if flyConn     then flyConn:Disconnect();     flyConn     = nil end
	if flyBodyVel  then flyBodyVel:Destroy();      flyBodyVel  = nil end
	if flyBodyGyro then flyBodyGyro:Destroy();     flyBodyGyro = nil end
	local char = LocalPlayer.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.PlatformStand = false end
	end
end

local function startNoclip()
	noclipConn = RunService.Stepped:Connect(function()
		local char = LocalPlayer.Character
		if not char or not movementState.noclipEnabled then return end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end)
end

local function stopNoclip()
	if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
	local char = LocalPlayer.Character
	if char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = true end
		end
	end
end

local function startInfJump()
	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	infJumpConn = hum.StateChanged:Connect(function(_, new)
		if movementState.infJumpEnabled and new == Enum.HumanoidStateType.Freefall then
			task.wait(0.1)
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
end

local function stopInfJump()
	if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
end

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	if movementState.flyEnabled     then startFly()     end
	if movementState.noclipEnabled  then startNoclip()  end
	if movementState.infJumpEnabled then startInfJump() end
end)

-- ============================================================
-- PLAYER TOOLS (Fling, WalkSpeed, JumpPower)
-- ============================================================
local function flingPlayer(target)
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	local tChar = target.Character
	if not tChar then return end
	local tHRP = tChar:FindFirstChild("HumanoidRootPart")
	if not tHRP then return end

	-- Save original state
	local origCF    = hrp.CFrame
	local origPlatform = hum.PlatformStand

	-- Step 1: disable our own collision so we can clip into target
	hum.PlatformStand = true
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = false end
	end

	-- Step 2: teleport directly onto target
	hrp.CFrame = tHRP.CFrame * CFrame.new(0, 0.5, 0)
	task.wait(0.05)

	-- Step 3: slam our OWN HRP with huge velocity — collision pushes target server-side
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.new(
		math.random(-3, 3) * 100,
		900,
		math.random(-3, 3) * 100
	)
	bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	bv.P        = 1e6
	bv.Parent   = hrp

	-- Step 4: briefly re-enable collision so we actually hit them
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = true end
	end

	task.wait(0.15)

	-- Step 5: clean up and restore
	bv:Destroy()
	hum.PlatformStand = origPlatform
	hrp.CFrame = origCF
end

local function setWalkSpeed(player, speed)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = speed end
end

local function setJumpPower(player, power)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.JumpPower = power end
end

-- ============================================================
-- CUSTOM GUI  (SKECH-style: left sidebar + card panels)
-- ============================================================
local ACCENT = Color3.fromRGB(0, 200, 255)  -- default cyan, overridden by config

-- Config save/load
local CONFIG_FILE = "PhongHub_config.json"

local function saveConfig()
	local ok, json = pcall(function()
		return game:GetService("HttpService"):JSONEncode({
			accentR      = math.floor(ACCENT.R * 255),
			accentG      = math.floor(ACCENT.G * 255),
			accentB      = math.floor(ACCENT.B * 255),
			aimBind      = aimBindLabel,
			aimEnabled   = Settings.AimAssistEnabled,
			aimStrength  = Settings.AimStrength,
			aimSmoothing = Settings.AimSmoothing,
			aimFOV       = Settings.AimFOV,
			aimBone      = Settings.AimBone,
			aimWall      = Settings.AimWallCheck,
			aimTeam      = Settings.AimTeamCheck,
			espHL        = Settings.HighlightEnabled,
			espBox       = Settings.BoxEnabled,
			espTracer    = Settings.TracerEnabled,
			espHealth    = Settings.HealthBarEnabled,
			espName      = Settings.NameTagEnabled,
			espDist      = Settings.DistanceLabelEnabled,
			wallCheck    = Settings.WallCheckEnabled,
			teamCheck    = Settings.TeamCheckEnabled,
			sepColors    = Settings.SeparateColors,
			trigEnabled  = Settings.TriggerEnabled,
			trigTeam     = Settings.TriggerTeamCheck,
			trigWall     = Settings.TriggerWallCheck,
		})
	end)
	if ok then pcall(writefile, CONFIG_FILE, json) end
end

local function loadConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok or not raw then return end
	local ok2, cfg = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	if not ok2 or not cfg then return end
	if cfg.accentR then
		ACCENT = Color3.fromRGB(cfg.accentR, cfg.accentG or 200, cfg.accentB or 255)
	end
	aimBindLabel              = cfg.aimBind      or aimBindLabel
	Settings.AimAssistEnabled = cfg.aimEnabled   or false
	Settings.AimStrength      = cfg.aimStrength  or 0.5
	Settings.AimSmoothing     = cfg.aimSmoothing or 6
	Settings.AimFOV           = cfg.aimFOV       or 120
	Settings.AimBone          = cfg.aimBone      or "Head"
	Settings.AimWallCheck         = cfg.aimWall      == true
	Settings.AimTeamCheck         = cfg.aimTeam      == true
	Settings.HighlightEnabled     = cfg.espHL        == true
	Settings.BoxEnabled           = cfg.espBox       == true
	Settings.TracerEnabled        = cfg.espTracer    == true
	Settings.HealthBarEnabled     = cfg.espHealth    == true
	Settings.NameTagEnabled       = cfg.espName      == true
	Settings.DistanceLabelEnabled = cfg.espDist      == true
	Settings.WallCheckEnabled     = cfg.wallCheck    == true
	Settings.TeamCheckEnabled     = cfg.teamCheck    == true
	Settings.SeparateColors       = cfg.sepColors    == true
	Settings.TriggerEnabled       = cfg.trigEnabled  == true
	Settings.TriggerTeamCheck     = cfg.trigTeam     == true
	Settings.TriggerWallCheck     = cfg.trigWall     == true
	-- restore bind key from label
	local keyMap = {
		RMB="MouseButton2", LMB="MouseButton1",
		Q="Q", E="E", F="F", R="R", X="X", C="C",
		LeftAlt="LeftAlt", LeftShift="LeftShift",
		LAlt="LeftAlt", LShift="LeftShift", Caps="CapsLock",
	}
	if cfg.aimBind == "RMB" then
		aimBindKey = Enum.UserInputType.MouseButton2
	elseif cfg.aimBind == "LMB" then
		aimBindKey = Enum.UserInputType.MouseButton1
	else
		local kc = Enum.KeyCode[cfg.aimBind]
		if kc then aimBindKey = kc end
	end
end

-- Load config before building GUI
pcall(loadConfig)

local ACCENT2   = Color3.fromRGB(0, 150, 200)
local BG        = Color3.fromRGB(10, 12, 18)
local SIDEBAR   = Color3.fromRGB(14, 16, 24)
local CARD      = Color3.fromRGB(20, 23, 33)
local CARD2     = Color3.fromRGB(26, 30, 42)
local BORDER    = Color3.fromRGB(35, 40, 58)
local TEXT      = Color3.fromRGB(220, 220, 235)
local TEXTDIM   = Color3.fromRGB(110, 115, 140)
local RED       = Color3.fromRGB(220, 50, 50)
local GREEN     = Color3.fromRGB(50, 200, 100)
local WHITE     = Color3.fromRGB(255,255,255)

local TS  = game:GetService("TweenService")
local UIS = UserInputService
local SG  = Instance.new("ScreenGui")
SG.Name            = "PhongHub"
SG.ResetOnSpawn    = false
SG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset  = true
SG.Parent          = game:GetService("CoreGui")

-- helpers
local function Frame(props, parent)
	local f = Instance.new("Frame")
	for k,v in pairs(props) do f[k]=v end
	f.Parent = parent; return f
end
local function Label(props, parent)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = TEXT
	l.Font = Enum.Font.SourceSansBold
	l.TextSize = 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k,v in pairs(props) do l[k]=v end
	l.Parent = parent; return l
end
local function Btn(props, parent)
	local b = Instance.new("TextButton")
	b.BackgroundTransparency = 1
	b.TextColor3 = TEXT
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 13
	b.AutoButtonColor = false
	for k,v in pairs(props) do b[k]=v end
	b.Parent = parent; return b
end
local function Corner(r, p)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,r); c.Parent = p
end
local function Stroke(c, t, p)
	local s = Instance.new("UIStroke"); s.Color=c; s.Thickness=t; s.Parent=p
end
local function Padding(px, p)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0,px)
	pad.PaddingRight  = UDim.new(0,px)
	pad.PaddingTop    = UDim.new(0,px)
	pad.PaddingBottom = UDim.new(0,px)
	pad.Parent = p
end
local function ListLayout(spacing, p)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, spacing)
	l.Parent = p; return l
end
local function makeToggle(state, onToggle, parent)
	local track = Frame({
		Size = UDim2.new(0,36,0,18),
		Position = UDim2.new(1,-36,0.5,-9),
		BackgroundColor3 = state and ACCENT or BORDER,
	}, parent)
	Corner(9, track)
	local knob = Frame({
		Size = UDim2.new(0,12,0,12),
		Position = state and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6),
		BackgroundColor3 = WHITE,
	}, track)
	Corner(6, knob)
	local on = state
	local function update(v)
		on = v
		TS:Create(track, TweenInfo.new(0.15), {BackgroundColor3 = v and ACCENT or BORDER}):Play()
		TS:Create(knob,  TweenInfo.new(0.15), {Position = v and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
		onToggle(v)
	end
	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then update(not on) end
	end)
	return update
end
local function makeSlider(val, min, max, onSlide, parent)
	local row = Frame({ Size=UDim2.new(1,0,0,28), BackgroundTransparency=1 }, parent)
	local track = Frame({
		Size = UDim2.new(1,-50,0,4),
		Position = UDim2.new(0,0,0.5,-2),
		BackgroundColor3 = BORDER,
	}, row)
	Corner(2, track)
	local fill = Frame({
		Size = UDim2.new((val-min)/(max-min),0,1,0),
		BackgroundColor3 = ACCENT,
	}, track)
	Corner(2, fill)
	local valLabel = Label({
		Size = UDim2.new(0,44,1,0),
		Position = UDim2.new(1,-44,0,0),
		Text = tostring(val),
		TextColor3 = ACCENT,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 13,
	}, row)
	local dragging = false

	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			sliderDragging = true   -- block GUI drag
			draggingGui = false     -- force cancel any active GUI drag
		end
	end)

	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			if dragging then
				dragging = false
				sliderDragging = false
			end
		end
	end)

	UIS.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			local abs  = track.AbsolutePosition
			local sz   = track.AbsoluteSize
			local frac = math.clamp((i.Position.X - abs.X) / sz.X, 0, 1)
			local newVal = math.floor(min + frac * (max - min))
			fill.Size      = UDim2.new(frac, 0, 1, 0)
			valLabel.Text  = tostring(newVal)
			onSlide(newVal)
		end
	end)

	return row
end
local function makeDropdown(options, current, onChange, parent)
	local row = Frame({ Size=UDim2.new(1,0,0,28), BackgroundTransparency=1 }, parent)
	local box = Frame({
		Size = UDim2.new(0,130,0,22),
		Position = UDim2.new(1,-130,0.5,-11),
		BackgroundColor3 = CARD2,
	}, row)
	Corner(4, box)
	Stroke(BORDER, 1, box)
	local cur = Label({
		Size = UDim2.new(1,-20,1,0),
		Position = UDim2.new(0,6,0,0),
		Text = current,
		TextSize = 12,
		TextColor3 = TEXTDIM,
		Font = Enum.Font.SourceSans,
	}, box)
	local arr = Label({
		Size = UDim2.new(0,16,1,0),
		Position = UDim2.new(1,-18,0,0),
		Text = "▾",
		TextColor3 = TEXTDIM,
		TextSize = 12,
	}, box)
	-- dropdown list
	local list = Frame({
		Size = UDim2.new(0,130,0,#options*26+4),
		Position = UDim2.new(1,-130,1,2),
		BackgroundColor3 = CARD2,
		ZIndex = 10,
		Visible = false,
	}, box)
	Corner(4, list)
	Stroke(BORDER,1,list)
	local ll = ListLayout(0, list)
	for _, opt in ipairs(options) do
		local ob = Btn({
			Size = UDim2.new(1,0,0,26),
			Text = opt,
			TextColor3 = TEXTDIM,
			TextSize = 12,
			Font = Enum.Font.SourceSans,
			ZIndex = 10,
		}, list)
		ob.MouseButton1Click:Connect(function()
			cur.Text = opt
			list.Visible = false
			onChange(opt)
		end)
		ob.MouseEnter:Connect(function() ob.TextColor3 = ACCENT end)
		ob.MouseLeave:Connect(function() ob.TextColor3 = TEXTDIM end)
	end
	box.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			list.Visible = not list.Visible
		end
	end)
	return row
end
local function makeRow(labelText, parent)
	local row = Frame({ Size=UDim2.new(1,0,0,28), BackgroundTransparency=1 }, parent)
	Label({ Size=UDim2.new(0.55,0,1,0), Text=labelText, Font=Enum.Font.SourceSans, TextSize=13, TextColor3=TEXTDIM }, row)
	return row
end
local function makeCard(title, iconColor, parent, listParent)
	local card = Frame({
		Size = UDim2.new(0,310,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CARD,
	}, parent)
	Corner(8, card)
	Stroke(BORDER, 1, card)
	-- header
	local header = Frame({
		Size = UDim2.new(1,0,0,36),
		BackgroundColor3 = CARD2,
	}, card)
	Corner(8, header)
	-- dot
	local dot = Frame({
		Size = UDim2.new(0,10,0,10),
		Position = UDim2.new(0,12,0.5,-5),
		BackgroundColor3 = iconColor,
	}, header)
	Corner(5, dot)
	Label({
		Size = UDim2.new(0.7,0,1,0),
		Position = UDim2.new(0,30,0,0),
		Text = title,
		TextSize = 14,
		Font = Enum.Font.SourceSansBold,
		TextColor3 = WHITE,
	}, header)
	-- content
	local content = Frame({
		Size = UDim2.new(1,0,0,0),
		Position = UDim2.new(0,0,0,36),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, card)
	Padding(12, content)
	ListLayout(4, content)
	return card, content, header
end

-- ── MAIN WINDOW ──────────────────────────────────────────────
local Main = Frame({
	Size = UDim2.new(0,820,0,560),
	Position = UDim2.new(0.5,-410,0.5,-280),
	BackgroundColor3 = BG,
}, SG)
Corner(10, Main)
Stroke(BORDER, 1, Main)

-- drag — only triggered from the sidebar (not content area)
local draggingGui, dragStart, startPos
local sliderDragging = false  -- set true by any slider, blocks gui drag

-- ── SIDEBAR ───────────────────────────────────────────────────
local Sidebar = Frame({
	Size = UDim2.new(0,170,1,0),
	BackgroundColor3 = SIDEBAR,
}, Main)
Corner(10, Sidebar)

-- Attach drag to sidebar and tab header only (not content area)
local function attachDrag(target)
	target.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 and not sliderDragging then
			draggingGui = true
			dragStart   = i.Position
			startPos    = Main.Position
		end
	end)
	target.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			draggingGui = false
		end
	end)
end

UIS.InputChanged:Connect(function(i)
	if draggingGui and not sliderDragging and i.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = i.Position - dragStart
		Main.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingGui = false
	end
end)

-- Logo area
local logoArea = Frame({ Size=UDim2.new(1,0,0,70), BackgroundTransparency=1 }, Sidebar)
Label({
	Size = UDim2.new(1,0,0,32),
	Position = UDim2.new(0,0,0,16),
	Text = "PHONG",
	TextSize = 22,
	Font = Enum.Font.SourceSansBold,
	TextColor3 = ACCENT,
	TextXAlignment = Enum.TextXAlignment.Center,
}, logoArea)
Label({
	Size = UDim2.new(1,0,0,16),
	Position = UDim2.new(0,0,0,44),
	Text = "HUB",
	TextSize = 11,
	Font = Enum.Font.SourceSans,
	TextColor3 = TEXTDIM,
	TextXAlignment = Enum.TextXAlignment.Center,
}, logoArea)

-- divider
Frame({ Size=UDim2.new(0.7,0,0,1), Position=UDim2.new(0.15,0,0,70), BackgroundColor3=BORDER }, Sidebar)

-- nav
local navContainer = Frame({
	Size = UDim2.new(1,0,1,-80),
	Position = UDim2.new(0,0,0,80),
	BackgroundTransparency = 1,
}, Sidebar)
Padding(10, navContainer)
ListLayout(4, navContainer)

-- Attach drag to sidebar now that it exists
attachDrag(Sidebar)

-- ── CONTENT AREA ─────────────────────────────────────────────
local ContentArea = Frame({
	Size = UDim2.new(1,-170,1,0),
	Position = UDim2.new(0,170,0,0),
	BackgroundTransparency = 1,
}, Main)

-- Tab header
local tabHeader = Frame({
	Size = UDim2.new(1,0,0,44),
	BackgroundColor3 = SIDEBAR,
}, ContentArea)

-- Attach drag to tab header too
attachDrag(tabHeader)
local tabTitle = Label({
	Size = UDim2.new(1,0,1,0),
	Text = "ESP",
	TextSize = 16,
	Font = Enum.Font.SourceSansBold,
	TextColor3 = TEXT,
	TextXAlignment = Enum.TextXAlignment.Center,
}, tabHeader)

-- Scrollable panels area
local PanelArea = Instance.new("ScrollingFrame")
PanelArea.Size                  = UDim2.new(1,-20,1,-54)
PanelArea.Position              = UDim2.new(0,10,0,54)
PanelArea.BackgroundTransparency = 1
PanelArea.ClipsDescendants      = true
PanelArea.ScrollBarThickness    = 4
PanelArea.ScrollBarImageColor3  = ACCENT
PanelArea.BorderSizePixel       = 0
PanelArea.CanvasSize            = UDim2.new(0,0,0,0)  -- auto updated per page
PanelArea.ScrollingDirection    = Enum.ScrollingDirection.Y
PanelArea.ElasticBehavior       = Enum.ElasticBehavior.Never
PanelArea.Parent                = ContentArea

-- ── PAGE SYSTEM ──────────────────────────────────────────────
local pages    = {}   -- name → Frame
local navBtns  = {}   -- name → button
local activePage = nil

local function showPage(name)
	for n, pg in pairs(pages) do pg.Visible = n == name end
	for n, btn in pairs(navBtns) do
		btn.BackgroundColor3 = n == name and CARD2 or Color3.fromRGB(0,0,0)
		btn.BackgroundTransparency = n == name and 0 or 1
		btn.TextColor3 = n == name and ACCENT or TEXTDIM
	end
	tabTitle.Text = name
	activePage = name
	-- Reset scroll and update canvas height for the new page
	PanelArea.CanvasPosition = Vector2.zero
	task.defer(function()
		local pg = pages[name]
		if not pg then return end
		-- Measure tallest column
		local maxH = 0
		for _, col in ipairs(pg:GetChildren()) do
			if col:IsA("Frame") then
				local h = col.AbsoluteSize.Y
				if h > maxH then maxH = h end
			end
		end
		PanelArea.CanvasSize = UDim2.new(0, 0, 0, maxH + 20)
	end)
end

local function addPage(name, icon)
	-- sidebar button
	local btn = Btn({
		Size = UDim2.new(1,0,0,34),
		Text = icon .. "  " .. name,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = CARD2,
		BackgroundTransparency = 1,
		TextColor3 = TEXTDIM,
		Font = Enum.Font.SourceSansBold,
		TextSize = 13,
	}, navContainer)
	Corner(6, btn)
	Padding(10, btn)
	navBtns[name] = btn
	btn.MouseButton1Click:Connect(function() showPage(name) end)
	btn.MouseEnter:Connect(function()
		if activePage ~= name then btn.TextColor3 = TEXT end
	end)
	btn.MouseLeave:Connect(function()
		if activePage ~= name then btn.TextColor3 = TEXTDIM end
	end)
	-- page frame — sits inside the ScrollingFrame, auto height
	local pg = Frame({
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
	}, PanelArea)
	pages[name] = pg
	-- left column — auto height
	local leftCol = Frame({
		Size = UDim2.new(0.5,-5,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, pg)
	ListLayout(10, leftCol)
	-- right column — auto height
	local rightCol = Frame({
		Size = UDim2.new(0.5,-5,0,0),
		Position = UDim2.new(0.5,5,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, pg)
	ListLayout(10, rightCol)
	-- Auto-update CanvasSize whenever column content changes height
	local function updateCanvas()
		if activePage ~= name then return end
		task.defer(function()
			local maxH = 0
			for _, col in ipairs(pg:GetChildren()) do
				if col:IsA("Frame") then
					local h = col.AbsoluteSize.Y
					if h > maxH then maxH = h end
				end
			end
			PanelArea.CanvasSize = UDim2.new(0, 0, 0, maxH + 20)
		end)
	end
	leftCol:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas)
	rightCol:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas)
	return pg, leftCol, rightCol
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: ESP
-- ──────────────────────────────────────────────────────────────
local _, espL, espR = addPage("ESP", "👁")

-- Card: Highlights
do
	local card, ct, hdr = makeCard("Highlights", ACCENT, espL, espL)
	-- header toggle
	local hlOn = Settings.HighlightEnabled
	local tgl = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=hlOn and ACCENT or BORDER }, hdr)
	Corner(9,tgl)
	local knob2 = Frame({ Size=UDim2.new(0,12,0,12), Position=hlOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6), BackgroundColor3=WHITE }, tgl)
	Corner(6,knob2)
	tgl.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		hlOn = not hlOn
		Settings.HighlightEnabled = hlOn; refreshAllHighlights()
		TS:Create(tgl,   TweenInfo.new(0.15), {BackgroundColor3=hlOn and ACCENT or BORDER}):Play()
		TS:Create(knob2, TweenInfo.new(0.15), {Position=hlOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)
	-- rows
	local r1 = makeRow("Enable Highlights", ct)
	makeToggle(hlOn, function(v) hlOn=v; Settings.HighlightEnabled=v; refreshAllHighlights() end, r1)
	makeRow("Fill Transparency", ct)
	makeSlider(55, 0, 100, function(v) Settings.FillTransparency=v/100; for _,h in pairs(highlights) do h.FillTransparency=v/100 end end, ct)
	makeRow("Outline Transparency", ct)
	makeSlider(0, 0, 100, function(v) Settings.OutlineTransparency=v/100; for _,h in pairs(highlights) do h.OutlineTransparency=v/100 end end, ct)
end

-- Card: Box & Tracers
do
	local card, ct, hdr = makeCard("Box & Tracers", Color3.fromRGB(255,180,0), espL, espL)
	local r1 = makeRow("Enable 2D Box", ct)
	makeToggle(Settings.BoxEnabled, function(v) Settings.BoxEnabled=v end, r1)
	local r2 = makeRow("Enable Tracers", ct)
	makeToggle(Settings.TracerEnabled, function(v) Settings.TracerEnabled=v end, r2)
	makeRow("Thickness", ct)
	makeSlider(Settings.BoxThickness, 1, 5, function(v) Settings.BoxThickness=v end, ct)
	makeRow("Tracer Origin", ct)
	makeDropdown({"Bottom","Center","Top"}, Settings.TracerOrigin, function(v) Settings.TracerOrigin=v end, ct)
end

-- Card: Labels (right col)
do
	local card, ct, hdr = makeCard("Labels", Color3.fromRGB(80,220,120), espR, espR)
	local r1 = makeRow("Health Bar", ct)
	makeToggle(Settings.HealthBarEnabled, function(v) Settings.HealthBarEnabled=v end, r1)
	local r2 = makeRow("Name Tag", ct)
	makeToggle(Settings.NameTagEnabled, function(v) Settings.NameTagEnabled=v end, r2)
	local r3 = makeRow("Distance Label", ct)
	makeToggle(Settings.DistanceLabelEnabled, function(v) Settings.DistanceLabelEnabled=v end, r3)
	makeRow("Max Render Distance", ct)
	makeSlider(Settings.MaxRenderDistance, 0, 2000, function(v) Settings.MaxRenderDistance=v end, ct)
end

-- Card: Wall Check (right col)
do
	local card, ct, hdr = makeCard("Wall Check", Color3.fromRGB(200,100,255), espR, espR)
	local r1 = makeRow("Enable Wall Check", ct)
	makeToggle(Settings.WallCheckEnabled, function(v)
		Settings.WallCheckEnabled=v
		if not v then for _,h in pairs(highlights) do h.Enabled=true end end
	end, r1)
	local r2 = makeRow("Hide Box Behind Walls", ct)
	makeToggle(Settings.WallCheckHideBox, function(v) Settings.WallCheckHideBox=v end, r2)
	local r3 = makeRow("Hide Highlight Behind Walls", ct)
	makeToggle(Settings.WallCheckHideHL, function(v) Settings.WallCheckHideHL=v end, r3)
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: Aim
-- ──────────────────────────────────────────────────────────────
local _, aimL, aimR = addPage("Aim", "🎯")

-- Card: Aimbot
do
	local card, ct, hdr = makeCard("Aimbot", ACCENT, aimL, aimL)
	-- header toggle
	local aimOn = Settings.AimAssistEnabled
	local tglA = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=aimOn and ACCENT or BORDER }, hdr)
	Corner(9,tglA)
	local knobA = Frame({ Size=UDim2.new(0,12,0,12), Position=aimOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6), BackgroundColor3=WHITE }, tglA)
	Corner(6,knobA)
	tglA.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		aimOn = not aimOn; Settings.AimAssistEnabled = aimOn
		TS:Create(tglA,TweenInfo.new(0.15),{BackgroundColor3=aimOn and ACCENT or BORDER}):Play()
		TS:Create(knobA,TweenInfo.new(0.15),{Position=aimOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)

	local r1 = makeRow("Skip Teammates", ct)
	makeToggle(false, function(v) Settings.AimTeamCheck=v end, r1)
	local r2 = makeRow("Wall Check", ct)
	makeToggle(Settings.AimWallCheck, function(v) Settings.AimWallCheck=v end, r2)
	makeRow("Field Of View", ct)
	makeSlider(Settings.AimFOV, 20, 400, function(v) Settings.AimFOV=v end, ct)
	makeRow("Smoothing", ct)
	makeSlider(Settings.AimSmoothing, 1, 20, function(v) Settings.AimSmoothing=v end, ct)
	makeRow("Strength", ct)
	makeSlider(math.floor(Settings.AimStrength*100), 0, 100, function(v) Settings.AimStrength=v/100 end, ct)
	makeRow("Target Bone", ct)
	makeDropdown({"Head","UpperTorso","HumanoidRootPart"}, Settings.AimBone, function(v) Settings.AimBone=v end, ct)
	local r3 = makeRow("FOV Circle", ct)
	makeToggle(Settings.AimFOVCircle, function(v) Settings.AimFOVCircle=v end, r3)
end

-- Card: Keybind
do
	local card, ct, hdr = makeCard("Keybind", Color3.fromRGB(255,200,0), aimL, aimL)
	local bindRow = makeRow("Active Bind", ct)
	local bindLbl = Label({
		Size = UDim2.new(0,120,1,0),
		Position = UDim2.new(1,-120,0,0),
		Text = "[ "..aimBindLabel.." ]",
		TextColor3 = ACCENT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, bindRow)

	local function doQuickBind(key, label)
		aimBindKey = key; aimBindLabel = label
		bindLbl.Text = "[ "..label.." ]"
		saveConfig()
	end

	local setBtnRow = Frame({ Size=UDim2.new(1,0,0,30), BackgroundTransparency=1 }, ct)
	local setBtn = Btn({
		Size = UDim2.new(1,0,1,0),
		Text = "🎮 Click then press key",
		BackgroundColor3 = CARD2,
		TextColor3 = TEXT,
		TextSize = 12,
	}, setBtnRow)
	Corner(6, setBtn)
	Stroke(BORDER, 1, setBtn)
	setBtn.MouseButton1Click:Connect(function()
		if isListeningForBind then return end
		isListeningForBind = true
		setBtn.Text = "⏳ Press key or mouse btn..."
		setBtn.TextColor3 = ACCENT
		task.wait(0.3)
		local conn
		conn = UIS.InputBegan:Connect(function(inp, gp)
			-- Accept keyboard keys and mouse buttons, skip unknown/UI events
			local isMouse = inp.UserInputType == Enum.UserInputType.MouseButton1
				or inp.UserInputType == Enum.UserInputType.MouseButton2
				or inp.UserInputType == Enum.UserInputType.MouseButton3
			local isKey = inp.UserInputType == Enum.UserInputType.Keyboard
				and inp.KeyCode ~= Enum.KeyCode.Unknown

			if not isMouse and not isKey then return end

			local lbl
			if inp.UserInputType == Enum.UserInputType.MouseButton1 then
				lbl = "LMB"; aimBindKey = Enum.UserInputType.MouseButton1
			elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
				lbl = "RMB"; aimBindKey = Enum.UserInputType.MouseButton2
			elseif inp.UserInputType == Enum.UserInputType.MouseButton3 then
				lbl = "MMB"; aimBindKey = Enum.UserInputType.MouseButton3
			else
				lbl = tostring(inp.KeyCode):gsub("Enum%.KeyCode%.","")
				aimBindKey = inp.KeyCode
			end

			aimBindLabel = lbl
			bindLbl.Text = "[ "..lbl.." ]"
			isListeningForBind = false
			setBtn.Text = "🎮 Click then press key / mouse"
			setBtn.TextColor3 = TEXT
			conn:Disconnect()
			saveConfig()
		end)
		task.delay(8, function()
			if isListeningForBind then
				isListeningForBind = false
				setBtn.Text = "🎮 Click then press key / mouse"
				setBtn.TextColor3 = TEXT
				conn:Disconnect()
			end
		end)
	end)

	-- quick bind buttons
	local qbData = {
		{"RMB", Enum.UserInputType.MouseButton2},
		{"LMB", Enum.UserInputType.MouseButton1},
		{"LAlt", Enum.KeyCode.LeftAlt},
		{"LShift", Enum.KeyCode.LeftShift},
		{"Q", Enum.KeyCode.Q},
		{"E", Enum.KeyCode.E},
		{"F", Enum.KeyCode.F},
		{"Caps", Enum.KeyCode.CapsLock},
	}
	local grid = Frame({ Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1 }, ct)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.23,-3,0,24)
	gl.CellPadding = UDim2.new(0,3,0,3)
	gl.Parent = grid
	for _, qb in ipairs(qbData) do
		local b = Btn({ Size=UDim2.new(0,1,0,24), Text=qb[1], BackgroundColor3=CARD2, TextColor3=TEXTDIM, TextSize=11 }, grid)
		Corner(4, b)
		b.MouseButton1Click:Connect(function() doQuickBind(qb[2], qb[1]) end)
		b.MouseEnter:Connect(function() b.TextColor3=ACCENT end)
		b.MouseLeave:Connect(function() b.TextColor3=TEXTDIM end)
	end
end

-- Card: FOV Circle (right)
do
	local card, ct, hdr = makeCard("FOV Circle", Color3.fromRGB(100,180,255), aimR, aimR)
	local r1 = makeRow("Show FOV Circle", ct)
	makeToggle(Settings.AimFOVCircle, function(v) Settings.AimFOVCircle=v end, r1)
	makeRow("FOV Thickness", ct)
	makeSlider(Settings.AimFOVThickness, 1, 4, function(v)
		Settings.AimFOVThickness=v
		if aimFOVCircle then aimFOVCircle.Thickness=v end
	end, ct)
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: Triggerbot
-- ──────────────────────────────────────────────────────────────
local _, tbL, tbR = addPage("Triggerbot", "⚡")

do
	local card, ct, hdr = makeCard("Triggerbot", Color3.fromRGB(220, 60, 60), tbL, tbL)

	-- Header toggle
	local tbOn = Settings.TriggerEnabled
	local tglT = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=tbOn and ACCENT or BORDER }, hdr)
	Corner(9,tglT)
	local knobT = Frame({ Size=UDim2.new(0,12,0,12), Position=tbOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6), BackgroundColor3=WHITE }, tglT)
	Corner(6,knobT)
	tglT.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		tbOn = not tbOn; Settings.TriggerEnabled = tbOn
		TS:Create(tglT,  TweenInfo.new(0.15), {BackgroundColor3=tbOn and ACCENT or BORDER}):Play()
		TS:Create(knobT, TweenInfo.new(0.15), {Position=tbOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)

	-- Delay slider
	makeRow("Trigger Delay (ms)", ct)
	makeSlider(50, 0, 500, function(v) Settings.TriggerDelay = v / 1000 end, ct)

	-- Target bone
	makeRow("Target Bone", ct)
	makeDropdown({"Head","UpperTorso","HumanoidRootPart"}, Settings.TriggerBone, function(v)
		Settings.TriggerBone = v
	end, ct)

	-- Filters
	local r1 = makeRow("Team Check", ct)
	makeToggle(Settings.TriggerTeamCheck, function(v) Settings.TriggerTeamCheck = v end, r1)

	local r2 = makeRow("Wall Check", ct)
	makeToggle(Settings.TriggerWallCheck, function(v) Settings.TriggerWallCheck = v end, r2)
end

do
	local card, ct, hdr = makeCard("How It Works", Color3.fromRGB(120,120,120), tbR, tbR)
	Label({
		Size = UDim2.new(1,0,0,120),
		Text = "Triggerbot automatically clicks when your crosshair is directly over an enemy.\n\nIt uses a raycast from the center of your screen. If it hits a player part, it fires after the set delay.\n\nNo keybind needed — just enable and play.",
		TextColor3 = TEXTDIM,
		Font = Enum.Font.SourceSans,
		TextSize = 13,
		TextWrapped = true,
		BackgroundTransparency = 1,
	}, ct)
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: Players
-- ──────────────────────────────────────────────────────────────
local _, plL, plR = addPage("Players", "👤")

local selectedTarget = nil

-- Card: Select
do
	local card, ct, hdr = makeCard("Select Player", ACCENT, plL, plL)
	local listFrame = Frame({
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, ct)
	ListLayout(2, listFrame)

	local selLabel = Label({
		Size = UDim2.new(1,0,0,20),
		Text = "None selected",
		TextColor3 = TEXTDIM,
		Font = Enum.Font.SourceSans,
		TextSize = 12,
	}, ct)

	local function refreshList()
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p == LocalPlayer then continue end
			local pb = Btn({
				Size = UDim2.new(1,0,0,26),
				Text = p.Name,
				BackgroundColor3 = CARD2,
				TextColor3 = TEXTDIM,
				TextSize = 12,
				Font = Enum.Font.SourceSans,
			}, listFrame)
			Corner(4, pb)
			pb.MouseButton1Click:Connect(function()
				selectedTarget = p
				selLabel.Text = "Selected: "..p.Name
				selLabel.TextColor3 = ACCENT
				for _, b in ipairs(listFrame:GetChildren()) do
					if b:IsA("TextButton") then b.TextColor3 = TEXTDIM; b.BackgroundColor3=CARD2 end
				end
				pb.TextColor3 = ACCENT; pb.BackgroundColor3 = Color3.fromRGB(0,50,70)
			end)
			pb.MouseEnter:Connect(function() if selectedTarget ~= p then pb.TextColor3=TEXT end end)
			pb.MouseLeave:Connect(function() if selectedTarget ~= p then pb.TextColor3=TEXTDIM end end)
		end
	end

	refreshList()
	local refRow = Frame({ Size=UDim2.new(1,0,0,28), BackgroundTransparency=1 }, ct)
	local refBtn = Btn({ Size=UDim2.new(1,0,1,0), Text="🔄 Refresh", BackgroundColor3=CARD2, TextColor3=TEXTDIM, TextSize=12 }, refRow)
	Corner(5, refBtn)
	refBtn.MouseButton1Click:Connect(refreshList)
end

-- Card: Fling
do
	local card, ct, hdr = makeCard("Fling", RED, plL, plL)
	local function makeActionBtn(label, cb)
		local row = Frame({ Size=UDim2.new(1,0,0,30), BackgroundTransparency=1 }, ct)
		local b = Btn({ Size=UDim2.new(1,0,1,0), Text=label, BackgroundColor3=CARD2, TextColor3=TEXT, TextSize=12 }, row)
		Corner(5, b)
		Stroke(BORDER, 1, b)
		b.MouseButton1Click:Connect(cb)
		b.MouseEnter:Connect(function() b.BackgroundColor3=Color3.fromRGB(30,35,50) end)
		b.MouseLeave:Connect(function() b.BackgroundColor3=CARD2 end)
	end
	makeActionBtn("💥 Fling Selected", function()
		if selectedTarget then flingPlayer(selectedTarget) end
	end)
	makeActionBtn("💥 Fling All Players", function()
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then flingPlayer(p) end
		end
	end)
end

-- Card: ESP Override
do
	local card, ct, hdr = makeCard("ESP Override", Color3.fromRGB(255,160,0), plR, plR)
	local function makeActionBtn(label, cb)
		local row = Frame({ Size=UDim2.new(1,0,0,30), BackgroundTransparency=1 }, ct)
		local b = Btn({ Size=UDim2.new(1,0,1,0), Text=label, BackgroundColor3=CARD2, TextColor3=TEXT, TextSize=12 }, row)
		Corner(5,b); Stroke(BORDER,1,b)
		b.MouseButton1Click:Connect(cb)
		b.MouseEnter:Connect(function() b.BackgroundColor3=Color3.fromRGB(30,35,50) end)
		b.MouseLeave:Connect(function() b.BackgroundColor3=CARD2 end)
	end
	makeActionBtn("✅ Force ON", function()
		if selectedTarget then perPlayerOverride[selectedTarget]=true; refreshHighlight(selectedTarget) end
	end)
	makeActionBtn("❌ Force OFF", function()
		if selectedTarget then perPlayerOverride[selectedTarget]=false; removeHighlight(selectedTarget) end
	end)
	makeActionBtn("🔁 Clear Override", function()
		if selectedTarget then perPlayerOverride[selectedTarget]=nil; refreshHighlight(selectedTarget) end
	end)
	makeActionBtn("➕ Whitelist (hide)", function()
		if selectedTarget then whitelist[selectedTarget]=true; removeHighlight(selectedTarget) end
	end)
	makeActionBtn("➖ Remove Whitelist", function()
		if selectedTarget then whitelist[selectedTarget]=nil; refreshHighlight(selectedTarget) end
	end)
end

-- Card: WalkSpeed & JumpPower
do
	local card, ct, hdr = makeCard("Speed / Jump", Color3.fromRGB(80,220,120), plR, plR)
	makeRow("My WalkSpeed", ct)
	makeSlider(16, 0, 200, function(v) setWalkSpeed(LocalPlayer, v) end, ct)
	makeRow("My JumpPower", ct)
	makeSlider(50, 0, 400, function(v) setJumpPower(LocalPlayer, v) end, ct)
	makeRow("Target WalkSpeed", ct)
	local twsSlider = makeSlider(16, 0, 200, function(v) end, ct)
	local function makeActionBtn(label, cb)
		local row = Frame({ Size=UDim2.new(1,0,0,28), BackgroundTransparency=1 }, ct)
		local b = Btn({ Size=UDim2.new(1,0,1,0), Text=label, BackgroundColor3=CARD2, TextColor3=TEXT, TextSize=12 }, row)
		Corner(5,b); Stroke(BORDER,1,b)
		b.MouseButton1Click:Connect(cb)
	end
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: Movement
-- ──────────────────────────────────────────────────────────────
local _, mvL, mvR = addPage("Movement", "🚀")

do
	local card, ct, hdr = makeCard("Fly", ACCENT, mvL, mvL)
	local flyOn = false
	local tglF = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=BORDER }, hdr)
	Corner(9,tglF)
	local knobF = Frame({ Size=UDim2.new(0,12,0,12), Position=UDim2.new(0,3,0.5,-6), BackgroundColor3=WHITE }, tglF)
	Corner(6,knobF)
	tglF.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		flyOn = not flyOn; movementState.flyEnabled = flyOn
		if flyOn then startFly() else stopFly() end
		TS:Create(tglF,TweenInfo.new(0.15),{BackgroundColor3=flyOn and ACCENT or BORDER}):Play()
		TS:Create(knobF,TweenInfo.new(0.15),{Position=flyOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)
	makeRow("Fly Speed", ct)
	makeSlider(flySpeed, 10, 300, function(v) flySpeed=v end, ct)
	Label({ Size=UDim2.new(1,0,0,20), Text="W/A/S/D · Space (up) · LCtrl (down)", TextColor3=TEXTDIM, Font=Enum.Font.SourceSans, TextSize=11 }, ct)
end

do
	local card, ct, hdr = makeCard("Noclip", Color3.fromRGB(255,120,0), mvL, mvL)
	local ncOn = false
	local tglN = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=BORDER }, hdr)
	Corner(9,tglN)
	local knobN = Frame({ Size=UDim2.new(0,12,0,12), Position=UDim2.new(0,3,0.5,-6), BackgroundColor3=WHITE }, tglN)
	Corner(6,knobN)
	tglN.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		ncOn = not ncOn; movementState.noclipEnabled = ncOn
		if ncOn then startNoclip() else stopNoclip() end
		TS:Create(tglN,TweenInfo.new(0.15),{BackgroundColor3=ncOn and ACCENT or BORDER}):Play()
		TS:Create(knobN,TweenInfo.new(0.15),{Position=ncOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)
end

do
	local card, ct, hdr = makeCard("Infinite Jump", Color3.fromRGB(200,100,255), mvR, mvR)
	local ijOn = false
	local tglI = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=BORDER }, hdr)
	Corner(9,tglI)
	local knobI = Frame({ Size=UDim2.new(0,12,0,12), Position=UDim2.new(0,3,0.5,-6), BackgroundColor3=WHITE }, tglI)
	Corner(6,knobI)
	tglI.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		ijOn = not ijOn; movementState.infJumpEnabled = ijOn
		if ijOn then startInfJump() else stopInfJump() end
		TS:Create(tglI,TweenInfo.new(0.15),{BackgroundColor3=ijOn and ACCENT or BORDER}):Play()
		TS:Create(knobI,TweenInfo.new(0.15),{Position=ijOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: Team
-- ──────────────────────────────────────────────────────────────
local _, tmL, tmR = addPage("Team", "🛡")

do
	local card, ct, hdr = makeCard("Team Check", ACCENT, tmL, tmL)
	local r1 = makeRow("Skip Teammates (ESP)", ct)
	makeToggle(Settings.TeamCheckEnabled, function(v) Settings.TeamCheckEnabled=v; refreshAllHighlights() end, r1)
	local r2 = makeRow("Separate Enemy/Team Colors", ct)
	makeToggle(Settings.SeparateColors, function(v) Settings.SeparateColors=v; refreshAllHighlights() end, r2)
end

-- Colors cards
do
	local card, ct, hdr = makeCard("Enemy Colors", RED, tmL, tmL)
	local colorDefs = {
		{"Fill",    function(c) Settings.EnemyFillColor=c;    refreshAllHighlights() end},
		{"Outline", function(c) Settings.EnemyOutlineColor=c; refreshAllHighlights() end},
		{"Box",     function(c) Settings.EnemyBoxColor=c    end},
		{"Tracer",  function(c) Settings.EnemyTracerColor=c  end},
	}
	for _, cd in ipairs(colorDefs) do
		Label({ Size=UDim2.new(1,0,0,20), Text=cd[1], TextColor3=TEXTDIM, Font=Enum.Font.SourceSans, TextSize=13 }, ct)
	end
	Label({ Size=UDim2.new(1,0,0,20), Text="(Use executor color picker for custom colors)", TextColor3=TEXTDIM, Font=Enum.Font.SourceSans, TextSize=11 }, ct)
end

do
	local card, ct, hdr = makeCard("Team Colors", Color3.fromRGB(60,160,255), tmR, tmR)
	Label({ Size=UDim2.new(1,0,0,20), Text="Fill / Outline / Box / Tracer", TextColor3=TEXTDIM, Font=Enum.Font.SourceSans, TextSize=13 }, ct)
	Label({ Size=UDim2.new(1,0,0,20), Text="(Use executor color picker for custom colors)", TextColor3=TEXTDIM, Font=Enum.Font.SourceSans, TextSize=11 }, ct)
end

-- ──────────────────────────────────────────────────────────────
-- SPIN JUKE SYSTEM
-- ──────────────────────────────────────────────────────────────
local spinBindKey      = Enum.KeyCode.Q
local spinBindLabel    = "Q"
local spinEnabled      = false
local spinAngle        = 45
local spinSpeed        = 0.04
local isSpinning       = false
local isListeningSpin  = false

local function doSpin()
	if isSpinning then return end
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	isSpinning = true

	local rad = math.rad(spinAngle)

	-- one clean snap: left → right → back to center
	local function rotCam(angle)
		local prevType = Camera.CameraType
		Camera.CameraType = Enum.CameraType.Scriptable
		Camera.CFrame = Camera.CFrame * CFrame.Angles(0, angle, 0)
		Camera.CameraType = prevType
	end

	rotCam(rad)            -- snap left
	task.wait(spinSpeed)
	rotCam(-rad * 2)       -- snap right (overshoot)
	task.wait(spinSpeed)
	rotCam(rad)            -- return to center

	isSpinning = false
end

UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	if not spinEnabled then return end
	if isListeningSpin then return end
	if typeof(spinBindKey) == "EnumItem" then
		if spinBindKey.EnumType == Enum.KeyCode and i.KeyCode == spinBindKey then
			task.spawn(doSpin)
		elseif spinBindKey.EnumType == Enum.UserInputType and i.UserInputType == spinBindKey then
			task.spawn(doSpin)
		end
	end
end)

-- ── Spin Juke UI Page ─────────────────────────────────────────
local _, spL, spR = addPage("Spin Juke", "🌀")

do
	local card, ct, hdr = makeCard("Spin Juke", ACCENT, spL, spL)

	-- header master toggle
	local spOn = spinEnabled
	local tglS = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=spOn and ACCENT or BORDER }, hdr)
	Corner(9,tglS)
	local knobS = Frame({ Size=UDim2.new(0,12,0,12), Position=spOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6), BackgroundColor3=WHITE }, tglS)
	Corner(6,knobS)
	tglS.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		spOn = not spOn; spinEnabled = spOn
		TS:Create(tglS,  TweenInfo.new(0.15), {BackgroundColor3=spOn and ACCENT or BORDER}):Play()
		TS:Create(knobS, TweenInfo.new(0.15), {Position=spOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)

	makeRow("Angle (degrees)", ct)
	makeSlider(spinAngle, 10, 90, function(v) spinAngle = v end, ct)

	makeRow("Speed (lower = faster)", ct)
	makeSlider(4, 1, 20, function(v) spinSpeed = v / 100 end, ct)

	-- keybind display
	local bindRow = makeRow("Active Bind", ct)
	local spinBindLbl = Label({
		Size = UDim2.new(0,120,1,0),
		Position = UDim2.new(1,-120,0,0),
		Text = "[ "..spinBindLabel.." ]",
		TextColor3 = ACCENT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.SourceSansBold,
	}, bindRow)

	local setBtnRow = Frame({ Size=UDim2.new(1,0,0,30), BackgroundTransparency=1 }, ct)
	local setSpinBtn = Btn({
		Size = UDim2.new(1,0,1,0),
		Text = "🎮 Click then press key",
		BackgroundColor3 = CARD2,
		TextColor3 = TEXT,
		TextSize = 12,
		Font = Enum.Font.SourceSans,
	}, setBtnRow)
	Corner(6, setSpinBtn)
	Stroke(BORDER, 1, setSpinBtn)

	setSpinBtn.MouseButton1Click:Connect(function()
		if isListeningSpin then return end
		isListeningSpin = true
		setSpinBtn.Text = "⏳ Press any key..."
		setSpinBtn.TextColor3 = ACCENT
		task.wait(0.25)
		local conn
		conn = UIS.InputBegan:Connect(function(inp)
			if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if inp.KeyCode == Enum.KeyCode.Unknown then return end
			spinBindKey   = inp.KeyCode
			spinBindLabel = tostring(inp.KeyCode):gsub("Enum%.KeyCode%.","")
			spinBindLbl.Text = "[ "..spinBindLabel.." ]"
			isListeningSpin = false
			setSpinBtn.Text = "🎮 Click then press key"
			setSpinBtn.TextColor3 = TEXT
			conn:Disconnect()
		end)
		task.delay(8, function()
			if isListeningSpin then
				isListeningSpin = false
				setSpinBtn.Text = "🎮 Click then press key"
				setSpinBtn.TextColor3 = TEXT
				conn:Disconnect()
			end
		end)
	end)
end

-- Quick binds for spin
do
	local card, ct, hdr = makeCard("Quick Binds", Color3.fromRGB(255,200,0), spR, spR)
	local qbData = {
		{"Q",      Enum.KeyCode.Q},
		{"E",      Enum.KeyCode.E},
		{"F",      Enum.KeyCode.F},
		{"R",      Enum.KeyCode.R},
		{"X",      Enum.KeyCode.X},
		{"C",      Enum.KeyCode.C},
		{"LAlt",   Enum.KeyCode.LeftAlt},
		{"LShift", Enum.KeyCode.LeftShift},
	}
	local grid = Frame({ Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1 }, ct)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize    = UDim2.new(0.23,-3,0,26)
	gl.CellPadding = UDim2.new(0,3,0,3)
	gl.Parent      = grid
	for _, qb in ipairs(qbData) do
		local b = Btn({ Text=qb[1], BackgroundColor3=CARD2, TextColor3=TEXTDIM, TextSize=11, Font=Enum.Font.SourceSansBold }, grid)
		Corner(4, b)
		b.MouseButton1Click:Connect(function()
			spinBindKey   = qb[2]
			spinBindLabel = qb[1]
			-- update label if visible
		end)
		b.MouseEnter:Connect(function() b.TextColor3=ACCENT end)
		b.MouseLeave:Connect(function() b.TextColor3=TEXTDIM end)
	end
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: Settings (GUI Color + Config)
-- ──────────────────────────────────────────────────────────────
local _, stL, stR = addPage("Settings", "⚙")

-- We collect all accent-colored elements so we can repaint them
local accentElements = {}  -- { obj, prop }
local function trackAccent(obj, prop)
	table.insert(accentElements, {obj=obj, prop=prop})
end

local function applyAccent(newColor)
	ACCENT = newColor
	PanelArea.ScrollBarImageColor3 = newColor
	for _, e in ipairs(accentElements) do
		pcall(function() e.obj[e.prop] = newColor end)
	end
end

do
	local card, ct, hdr = makeCard("GUI Accent Color", ACCENT, stL, stL)
	trackAccent(hdr:FindFirstChildOfClass("Frame"), "BackgroundColor3") -- dot

	-- Color presets
	local presets = {
		{"Cyan",    Color3.fromRGB(0,   200, 255)},
		{"Red",     Color3.fromRGB(220, 50,  50)},
		{"Green",   Color3.fromRGB(50,  220, 100)},
		{"Purple",  Color3.fromRGB(160, 80,  255)},
		{"Orange",  Color3.fromRGB(255, 140, 0)},
		{"Pink",    Color3.fromRGB(255, 80,  180)},
		{"White",   Color3.fromRGB(230, 230, 230)},
		{"Gold",    Color3.fromRGB(255, 210, 0)},
	}

	local grid = Frame({ Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1 }, ct)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize    = UDim2.new(0.23,-3,0,28)
	gl.CellPadding = UDim2.new(0,3,0,3)
	gl.Parent      = grid

	for _, preset in ipairs(presets) do
		local b = Btn({
			Text = preset[1],
			BackgroundColor3 = preset[2],
			TextColor3 = Color3.fromRGB(0,0,0),
			TextSize = 11,
			Font = Enum.Font.SourceSansBold,
		}, grid)
		Corner(4, b)
		b.MouseButton1Click:Connect(function()
			applyAccent(preset[2])
			saveConfig()
		end)
	end

	-- Custom RGB sliders
	local curR = math.floor(ACCENT.R*255)
	local curG = math.floor(ACCENT.G*255)
	local curB = math.floor(ACCENT.B*255)

	makeRow("Red", ct)
	makeSlider(curR, 0, 255, function(v) curR=v; applyAccent(Color3.fromRGB(curR,curG,curB)) end, ct)
	makeRow("Green", ct)
	makeSlider(curG, 0, 255, function(v) curG=v; applyAccent(Color3.fromRGB(curR,curG,curB)) end, ct)
	makeRow("Blue", ct)
	makeSlider(curB, 0, 255, function(v) curB=v; applyAccent(Color3.fromRGB(curR,curG,curB)) end, ct)
end

do
	local card, ct, hdr = makeCard("Config", Color3.fromRGB(80,220,120), stR, stR)

	local function makeActionBtn(label, cb)
		local row = Frame({ Size=UDim2.new(1,0,0,32), BackgroundTransparency=1 }, ct)
		local b = Btn({
			Size = UDim2.new(1,0,1,0),
			Text = label,
			BackgroundColor3 = CARD2,
			TextColor3 = TEXT,
			TextSize = 13,
			Font = Enum.Font.SourceSansBold,
		}, row)
		Corner(6, b); Stroke(BORDER, 1, b)
		b.MouseButton1Click:Connect(function()
			cb()
			b.Text = "✅ Done!"
			b.TextColor3 = ACCENT
			task.delay(1.5, function() b.Text = label; b.TextColor3 = TEXT end)
		end)
		b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(30,35,50) end)
		b.MouseLeave:Connect(function() b.BackgroundColor3 = CARD2 end)
	end

	makeActionBtn("💾 Save Config", saveConfig)
	makeActionBtn("📂 Load Config", function()
		pcall(loadConfig)
		applyAccent(ACCENT)
	end)
	makeActionBtn("🗑 Reset Config", function()
		pcall(deletefile, CONFIG_FILE)
		ACCENT = Color3.fromRGB(0, 200, 255)
		applyAccent(ACCENT)
	end)

	Label({
		Size = UDim2.new(1,0,0,40),
		Text = "Config saves to:\nPhongHub_config.json",
		TextColor3 = TEXTDIM,
		Font = Enum.Font.SourceSans,
		TextSize = 11,
		TextWrapped = true,
	}, ct)
end

-- ── Toggle GUI with smooth transition ────────────────────────
Main.Visible = false
Main.BackgroundTransparency = 1
Main.Size = UDim2.new(0, 820, 0, 560)

local guiOpen = false

local function openGui()
	if guiOpen then return end
	guiOpen = true
	Main.Visible = true
	Main.Size = UDim2.new(0, 820, 0, 0)
	Main.BackgroundTransparency = 1
	TS:Create(Main, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 820, 0, 560),
		BackgroundTransparency = 0,
	}):Play()
end

local function closeGui()
	if not guiOpen then return end
	guiOpen = false
	local t = TS:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 820, 0, 0),
		BackgroundTransparency = 1,
	})
	t:Play()
	t.Completed:Connect(function() Main.Visible = false end)
end

UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.RightAlt then
		if guiOpen then closeGui() else openGui() end
	end
end)

-- ── Start on ESP page ─────────────────────────────────────────
showPage("ESP")
-- ============================================================
-- SPLASH SCREEN
-- ============================================================
local Splash = Instance.new("Frame")
Splash.Size               = UDim2.new(1, 0, 1, 0)
Splash.Position           = UDim2.new(0, 0, 0, 0)
Splash.BackgroundColor3   = Color3.fromRGB(6, 8, 14)
Splash.BorderSizePixel    = 0
Splash.ZIndex             = 100
Splash.Parent             = SG

-- Gradient overlay
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(0,  30, 50)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(6,  8,  14)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(0,  10, 25)),
})
grad.Rotation = 135
grad.Parent = Splash

-- Glow circle behind text
local glow = Instance.new("Frame")
glow.Size                    = UDim2.new(0, 400, 0, 400)
glow.Position                = UDim2.new(0.5, -200, 0.5, -220)
glow.BackgroundColor3        = ACCENT
glow.BackgroundTransparency  = 0.92
glow.BorderSizePixel         = 0
glow.ZIndex                  = 101
glow.Parent                  = Splash
Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)

-- Title
local splashTitle = Instance.new("TextLabel")
splashTitle.Size                 = UDim2.new(1, 0, 0, 90)
splashTitle.Position             = UDim2.new(0, 0, 0.5, -110)
splashTitle.BackgroundTransparency = 1
splashTitle.Text                 = "PHONG HUB"
splashTitle.TextColor3           = ACCENT
splashTitle.Font                 = Enum.Font.SourceSansBold
splashTitle.TextSize             = 62
splashTitle.TextTransparency     = 1
splashTitle.ZIndex               = 102
splashTitle.Parent               = Splash

-- Subtitle
local splashSub = Instance.new("TextLabel")
splashSub.Size                   = UDim2.new(1, 0, 0, 24)
splashSub.Position               = UDim2.new(0, 0, 0.5, -18)
splashSub.BackgroundTransparency = 1
splashSub.Text                   = "Loading..."
splashSub.TextColor3             = Color3.fromRGB(130, 140, 160)
splashSub.Font                   = Enum.Font.SourceSans
splashSub.TextSize               = 16
splashSub.TextTransparency       = 1
splashSub.ZIndex                 = 102
splashSub.Parent                 = Splash

-- Loading bar background
local barBg = Instance.new("Frame")
barBg.Size                   = UDim2.new(0, 320, 0, 4)
barBg.Position               = UDim2.new(0.5, -160, 0.5, 30)
barBg.BackgroundColor3       = Color3.fromRGB(30, 35, 50)
barBg.BorderSizePixel        = 0
barBg.BackgroundTransparency = 1
barBg.ZIndex                 = 102
barBg.Parent                 = Splash
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

-- Loading bar fill
local barFill = Instance.new("Frame")
barFill.Size                   = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3       = ACCENT
barFill.BorderSizePixel        = 0
barFill.ZIndex                 = 103
barFill.Parent                 = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

-- Version label
local versionLbl = Instance.new("TextLabel")
versionLbl.Size                   = UDim2.new(1, 0, 0, 20)
versionLbl.Position               = UDim2.new(0, 0, 0.5, 50)
versionLbl.BackgroundTransparency = 1
versionLbl.Text                   = "v1.0  ·  Press RightAlt to toggle"
versionLbl.TextColor3             = Color3.fromRGB(60, 70, 90)
versionLbl.Font                   = Enum.Font.SourceSans
versionLbl.TextSize               = 13
versionLbl.TextTransparency       = 1
versionLbl.ZIndex                 = 102
versionLbl.Parent                 = Splash

-- Animate splash
task.spawn(function()
	-- Fade in title + subtitle
	TS:Create(splashTitle, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {TextTransparency=0}):Play()
	task.wait(0.3)
	TS:Create(splashSub, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {TextTransparency=0}):Play()
	TS:Create(barBg,     TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {BackgroundTransparency=0}):Play()
	TS:Create(versionLbl,TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {TextTransparency=0}):Play()
	task.wait(0.5)

	-- Loading bar fills with fake steps
	local steps = {
		{0.25, "Loading ESP system..."},
		{0.50, "Loading Aim Assist..."},
		{0.72, "Loading Movement..."},
		{0.88, "Loading Player Tools..."},
		{1.00, "Ready!"},
	}
	for _, step in ipairs(steps) do
		splashSub.Text = step[2]
		TS:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.new(step[1], 0, 1, 0)
		}):Play()
		task.wait(0.45)
	end

	task.wait(0.3)

	-- Glow pulse on complete
	TS:Create(glow, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), {
		BackgroundTransparency = 0.80
	}):Play()
	task.wait(0.6)

	-- Fade out splash
	TS:Create(Splash, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		BackgroundTransparency = 1
	}):Play()
	TS:Create(splashTitle,  TweenInfo.new(0.4), {TextTransparency = 1}):Play()
	TS:Create(splashSub,    TweenInfo.new(0.4), {TextTransparency = 1}):Play()
	TS:Create(barBg,        TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
	TS:Create(versionLbl,   TweenInfo.new(0.4), {TextTransparency = 1}):Play()
	TS:Create(glow,         TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
	task.wait(0.5)

	Splash:Destroy()

	-- GUI stays closed — press RightAlt to open
end)

local Window = { Rayfield = false }
