-- PhongHub.lua
-- LocalScript → StarterPlayerScripts
-- Requires Rayfield: https://sirius.menu/rayfield
-- Uses Drawing API (executor environment)

-- ============================================================
-- SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- ============================================================
-- LOAD RAYFIELD
-- ============================================================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- ============================================================
-- SETTINGS
-- ============================================================
local Settings = {
	-- Highlights
	HighlightEnabled     = true,
	FillTransparency     = 0.55,
	OutlineTransparency  = 0.0,

	-- 2D Box
	BoxEnabled           = true,
	BoxThickness         = 1,

	-- Tracers
	TracerEnabled        = true,
	TracerOrigin         = "Bottom",
	TracerThickness      = 1,

	-- Labels
	HealthBarEnabled     = true,
	NameTagEnabled       = true,
	DistanceLabelEnabled = true,

	-- Logic
	TeamCheckEnabled     = true,
	SeparateColors       = true,
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
	AimWallCheck         = true,
	AimFOVCircle         = true,
	AimFOVColor          = Color3.fromRGB(255, 255, 255),
	AimFOVThickness      = 1,

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
	t.Font         = Drawing.Fonts.UI
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
	if not hrp then return end
	local tChar = target.Character
	if not tChar then return end
	local tHRP  = tChar:FindFirstChild("HumanoidRootPart")
	if not tHRP then return end

	-- Teleport our HRP on top of target then apply massive velocity
	local origCF = hrp.CFrame
	hrp.CFrame   = tHRP.CFrame

	local fv = Instance.new("BodyVelocity")
	fv.Velocity  = Vector3.new(math.random(-1,1)*1e4, 1e4, math.random(-1,1)*1e4)
	fv.MaxForce  = Vector3.new(1e9, 1e9, 1e9)
	fv.Parent    = tHRP

	task.wait(0.15)
	fv:Destroy()
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
-- RAYFIELD WINDOW — Remade UI
-- ============================================================
local Window = Rayfield:CreateWindow({
	Name            = "🌀 Phong Hub",
	LoadingTitle    = "Phong Hub",
	LoadingSubtitle  = "by Phong",
	Theme           = "Amethyst",  -- cleaner purple theme
	ConfigurationSaving = { Enabled = false },
	KeySystem       = false,
})

-- ─────────────────────────────────────────
-- TAB 1 — ESP
-- ─────────────────────────────────────────
local ESPTab = Window:CreateTab("👁 ESP", 4483362458)

ESPTab:CreateSection("Highlights")
ESPTab:CreateToggle({
	Name = "Enable Highlights", CurrentValue = Settings.HighlightEnabled, Flag = "HLEnabled",
	Callback = function(v) Settings.HighlightEnabled = v; refreshAllHighlights() end,
})
ESPTab:CreateSlider({
	Name = "Fill Transparency", Range = {0,1}, Increment = 0.05,
	CurrentValue = Settings.FillTransparency, Flag = "FillTrans",
	Callback = function(v) Settings.FillTransparency = v; for _,h in pairs(highlights) do h.FillTransparency = v end end,
})
ESPTab:CreateSlider({
	Name = "Outline Transparency", Range = {0,1}, Increment = 0.05,
	CurrentValue = Settings.OutlineTransparency, Flag = "OutlineTrans",
	Callback = function(v) Settings.OutlineTransparency = v; for _,h in pairs(highlights) do h.OutlineTransparency = v end end,
})

ESPTab:CreateSection("Box & Tracers")
ESPTab:CreateToggle({
	Name = "Enable 2D Box", CurrentValue = Settings.BoxEnabled, Flag = "BoxEnabled",
	Callback = function(v) Settings.BoxEnabled = v end,
})
ESPTab:CreateToggle({
	Name = "Enable Tracers", CurrentValue = Settings.TracerEnabled, Flag = "TracerEnabled",
	Callback = function(v) Settings.TracerEnabled = v end,
})
ESPTab:CreateDropdown({
	Name = "Tracer Origin", Options = {"Bottom","Center","Top"},
	CurrentOption = {Settings.TracerOrigin}, MultipleOptions = false, Flag = "TracerOrigin",
	Callback = function(v) if type(v)=="table" then v=v[1] end; Settings.TracerOrigin = v end,
})
ESPTab:CreateSlider({
	Name = "Thickness", Range = {1,5}, Increment = 1,
	CurrentValue = Settings.BoxThickness, Flag = "BoxThick",
	Callback = function(v) Settings.BoxThickness = v end,
})

ESPTab:CreateSection("Labels")
ESPTab:CreateToggle({
	Name = "Health Bar", CurrentValue = Settings.HealthBarEnabled, Flag = "HealthBar",
	Callback = function(v) Settings.HealthBarEnabled = v end,
})
ESPTab:CreateToggle({
	Name = "Name Tag", CurrentValue = Settings.NameTagEnabled, Flag = "NameTag",
	Callback = function(v) Settings.NameTagEnabled = v end,
})
ESPTab:CreateToggle({
	Name = "Distance Label", CurrentValue = Settings.DistanceLabelEnabled, Flag = "DistLabel",
	Callback = function(v) Settings.DistanceLabelEnabled = v end,
})
ESPTab:CreateSlider({
	Name = "Max Render Distance (0 = unlimited)", Range = {0,2000}, Increment = 50,
	CurrentValue = Settings.MaxRenderDistance, Flag = "MaxDist",
	Callback = function(v) Settings.MaxRenderDistance = v end,
})

-- ─────────────────────────────────────────
-- TAB 2 — Colors
-- ─────────────────────────────────────────
local ColorTab = Window:CreateTab("🎨 Colors", 4483362458)

ColorTab:CreateSection("Separate Colors")
ColorTab:CreateToggle({
	Name = "Enemy vs Team Colors", CurrentValue = Settings.SeparateColors, Flag = "SepColors",
	Callback = function(v) Settings.SeparateColors = v; refreshAllHighlights() end,
})

ColorTab:CreateSection("Enemy")
ColorTab:CreateColorPicker({ Name="Fill",    Color=Settings.EnemyFillColor,    Flag="EFill",    Callback=function(c) Settings.EnemyFillColor=c;    refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Outline", Color=Settings.EnemyOutlineColor, Flag="EOut",     Callback=function(c) Settings.EnemyOutlineColor=c; refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Box",     Color=Settings.EnemyBoxColor,     Flag="EBox",     Callback=function(c) Settings.EnemyBoxColor=c    end })
ColorTab:CreateColorPicker({ Name="Tracer",  Color=Settings.EnemyTracerColor,  Flag="ETracer",  Callback=function(c) Settings.EnemyTracerColor=c  end })
ColorTab:CreateColorPicker({ Name="Name",    Color=Settings.EnemyNameColor,    Flag="EName",    Callback=function(c) Settings.EnemyNameColor=c    end })

ColorTab:CreateSection("Team")
ColorTab:CreateColorPicker({ Name="Fill",    Color=Settings.TeamFillColor,    Flag="TFill",    Callback=function(c) Settings.TeamFillColor=c;    refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Outline", Color=Settings.TeamOutlineColor, Flag="TOut",     Callback=function(c) Settings.TeamOutlineColor=c; refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Box",     Color=Settings.TeamBoxColor,     Flag="TBox",     Callback=function(c) Settings.TeamBoxColor=c     end })
ColorTab:CreateColorPicker({ Name="Tracer",  Color=Settings.TeamTracerColor,  Flag="TTracer",  Callback=function(c) Settings.TeamTracerColor=c  end })
ColorTab:CreateColorPicker({ Name="Name",    Color=Settings.TeamNameColor,    Flag="TName",    Callback=function(c) Settings.TeamNameColor=c    end })

-- ─────────────────────────────────────────
-- TAB 3 — Aim Assist
-- ─────────────────────────────────────────
local AimTab = Window:CreateTab("🎯 Aim Assist", 4483362458)

AimTab:CreateSection("Toggle")
AimTab:CreateToggle({
	Name = "Enable Aim Assist", CurrentValue = Settings.AimAssistEnabled, Flag = "AimEnabled",
	Callback = function(v)
		Settings.AimAssistEnabled = v
		if not v and aimFOVCircle then aimFOVCircle.Visible = false end
	end,
})

AimTab:CreateSection("Tuning")
AimTab:CreateSlider({
	Name = "Strength (0 = off, 1 = snap)", Range = {0,1}, Increment = 0.05,
	CurrentValue = Settings.AimStrength, Flag = "AimStr",
	Callback = function(v) Settings.AimStrength = v end,
})
AimTab:CreateSlider({
	Name = "Smoothing (higher = smoother)", Range = {1,20}, Increment = 1,
	CurrentValue = Settings.AimSmoothing, Flag = "AimSmooth",
	Callback = function(v) Settings.AimSmoothing = v end,
})
AimTab:CreateSlider({
	Name = "FOV Radius (px)", Range = {20,400}, Increment = 10,
	CurrentValue = Settings.AimFOV, Flag = "AimFOV",
	Callback = function(v) Settings.AimFOV = v end,
})
AimTab:CreateDropdown({
	Name = "Target Bone", Options = {"Head","UpperTorso","HumanoidRootPart"},
	CurrentOption = {Settings.AimBone}, MultipleOptions = false, Flag = "AimBone",
	Callback = function(v) if type(v)=="table" then v=v[1] end; Settings.AimBone = v end,
})

AimTab:CreateSection("FOV Circle")
AimTab:CreateToggle({
	Name = "Show FOV Circle", CurrentValue = Settings.AimFOVCircle, Flag = "AimFOVCircle",
	Callback = function(v) Settings.AimFOVCircle = v end,
})
AimTab:CreateColorPicker({
	Name = "FOV Color", Color = Settings.AimFOVColor, Flag = "AimFOVCol",
	Callback = function(c) Settings.AimFOVColor = c; if aimFOVCircle then aimFOVCircle.Color = c end end,
})
AimTab:CreateSlider({
	Name = "FOV Thickness", Range = {1,4}, Increment = 1,
	CurrentValue = Settings.AimFOVThickness, Flag = "AimFOVThick",
	Callback = function(v) Settings.AimFOVThickness = v; if aimFOVCircle then aimFOVCircle.Thickness = v end end,
})

AimTab:CreateSection("Filters")
AimTab:CreateToggle({
	Name = "Skip Teammates", CurrentValue = false, Flag = "AimTeam",
	Callback = function(v) Settings.AimTeamCheck = v end,
})
AimTab:CreateToggle({
	Name = "Skip Players Behind Walls", CurrentValue = Settings.AimWallCheck, Flag = "AimWall",
	Callback = function(v) Settings.AimWallCheck = v end,
})

AimTab:CreateSection("Keybind")

local bindBtn = AimTab:CreateButton({
	Name = "📌 Bind: [ " .. aimBindLabel .. " ]",
	Callback = function() end,
})

local function updateBind()
	bindBtn.Name = "📌 Bind: [ " .. aimBindLabel .. " ]"
	Rayfield:Notify({ Title="✅ Bind Set", Content="Aim assist: "..aimBindLabel, Duration=3, Image=4483362458 })
end

local function quickBind(key, label)
	aimBindKey = key; aimBindLabel = label; updateBind()
end

AimTab:CreateButton({
	Name = "🎮 Set Keybind (click then press key)",
	Callback = function()
		if isListeningForBind then return end
		isListeningForBind = true
		Rayfield:Notify({ Title="⏳ Press a key...", Content="Keyboard keys only. Use Quick Binds for mouse.", Duration=5, Image=4483362458 })
		task.wait(0.25)
		local conn
		conn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if input.KeyCode == Enum.KeyCode.Unknown then return end
			aimBindLabel = tostring(input.KeyCode):gsub("Enum%.KeyCode%.","")
			aimBindKey   = input.KeyCode
			isListeningForBind = false
			conn:Disconnect()
			updateBind()
		end)
		task.delay(8, function()
			if isListeningForBind then
				isListeningForBind = false; conn:Disconnect()
				Rayfield:Notify({ Title="Cancelled", Content="Kept: "..aimBindLabel, Duration=3, Image=4483362458 })
			end
		end)
	end,
})

AimTab:CreateSection("Quick Binds")
AimTab:CreateButton({ Name="🖱️ RMB",        Callback=function() quickBind(Enum.UserInputType.MouseButton2,"RMB")       end })
AimTab:CreateButton({ Name="🖱️ LMB",        Callback=function() quickBind(Enum.UserInputType.MouseButton1,"LMB")       end })
AimTab:CreateButton({ Name="⌨️ Left Alt",   Callback=function() quickBind(Enum.KeyCode.LeftAlt,   "LeftAlt")   end })
AimTab:CreateButton({ Name="⌨️ Left Shift", Callback=function() quickBind(Enum.KeyCode.LeftShift, "LeftShift") end })
AimTab:CreateButton({ Name="⌨️ Q",          Callback=function() quickBind(Enum.KeyCode.Q,         "Q")         end })
AimTab:CreateButton({ Name="⌨️ E",          Callback=function() quickBind(Enum.KeyCode.E,         "E")         end })
AimTab:CreateButton({ Name="⌨️ CapsLock",   Callback=function() quickBind(Enum.KeyCode.CapsLock,  "CapsLock")  end })

-- ─────────────────────────────────────────
-- TAB 4 — Wall Check
-- ─────────────────────────────────────────
local WallTab = Window:CreateTab("🧱 Wall Check", 4483362458)

WallTab:CreateSection("ESP Wall Check")
WallTab:CreateToggle({
	Name = "Enable Wall Check", CurrentValue = Settings.WallCheckEnabled, Flag = "WallCheck",
	Callback = function(v)
		Settings.WallCheckEnabled = v
		if not v then for _,h in pairs(highlights) do h.Enabled = true end end
	end,
})
WallTab:CreateToggle({
	Name = "Hide Box & Tracer Behind Walls", CurrentValue = Settings.WallCheckHideBox, Flag = "WallHideBox",
	Callback = function(v) Settings.WallCheckHideBox = v end,
})
WallTab:CreateToggle({
	Name = "Hide Highlight Behind Walls", CurrentValue = Settings.WallCheckHideHL, Flag = "WallHideHL",
	Callback = function(v) Settings.WallCheckHideHL = v end,
})
WallTab:CreateColorPicker({
	Name = "Behind-Wall Dim Color", Color = Settings.WallHiddenBoxColor, Flag = "WallDimCol",
	Callback = function(c) Settings.WallHiddenBoxColor = c end,
})

-- ─────────────────────────────────────────
-- TAB 5 — Team Check
-- ─────────────────────────────────────────
local TeamTab = Window:CreateTab("🛡 Team", 4483362458)

TeamTab:CreateSection("Team Check")
TeamTab:CreateToggle({
	Name = "Skip Teammates (ESP)", CurrentValue = Settings.TeamCheckEnabled, Flag = "TeamCheck",
	Callback = function(v) Settings.TeamCheckEnabled = v; refreshAllHighlights() end,
})

-- ─────────────────────────────────────────
-- TAB 6 — Players
-- ─────────────────────────────────────────
local PlayersTab = Window:CreateTab("👤 Players", 4483362458)

local function getPlayerNames()
	local t = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then table.insert(t, p.Name) end
	end
	if #t == 0 then table.insert(t, "(empty)") end
	return t
end

PlayersTab:CreateSection("Select Player")

local playerDrop = PlayersTab:CreateDropdown({
	Name = "Select Player", Options = getPlayerNames(),
	CurrentOption = {getPlayerNames()[1]}, MultipleOptions = false, Flag = "TargetPlayer",
	Callback = function() end,
})

PlayersTab:CreateButton({
	Name = "🔄 Refresh List",
	Callback = function()
		local names = getPlayerNames()
		playerDrop:Set(names[1])
	end,
})

local function getTarget()
	local name = Rayfield.Flags.TargetPlayer
	if type(name) == "table" then name = name[1] end
	return Players:FindFirstChild(name)
end

PlayersTab:CreateSection("ESP Override")
PlayersTab:CreateButton({
	Name = "✅ Force ESP ON",
	Callback = function()
		local p = getTarget(); if not p then return end
		perPlayerOverride[p] = true; refreshHighlight(p)
		Rayfield:Notify({ Title="ON", Content=p.Name.." forced visible.", Duration=3, Image=4483362458 })
	end,
})
PlayersTab:CreateButton({
	Name = "❌ Force ESP OFF",
	Callback = function()
		local p = getTarget(); if not p then return end
		perPlayerOverride[p] = false; removeHighlight(p)
		Rayfield:Notify({ Title="OFF", Content=p.Name.." hidden.", Duration=3, Image=4483362458 })
	end,
})
PlayersTab:CreateButton({
	Name = "🔁 Clear Override",
	Callback = function()
		local p = getTarget(); if not p then return end
		perPlayerOverride[p] = nil; refreshHighlight(p)
		Rayfield:Notify({ Title="Cleared", Content=p.Name.." back to default.", Duration=3, Image=4483362458 })
	end,
})

PlayersTab:CreateSection("Whitelist")
PlayersTab:CreateButton({
	Name = "➕ Whitelist (hide ESP)",
	Callback = function()
		local p = getTarget(); if not p then return end
		whitelist[p] = true; removeHighlight(p)
		Rayfield:Notify({ Title="Whitelisted", Content=p.Name.." skipped.", Duration=3, Image=4483362458 })
	end,
})
PlayersTab:CreateButton({
	Name = "➖ Remove from Whitelist",
	Callback = function()
		local p = getTarget(); if not p then return end
		whitelist[p] = nil; refreshHighlight(p)
		Rayfield:Notify({ Title="Removed", Content=p.Name.." un-whitelisted.", Duration=3, Image=4483362458 })
	end,
})

PlayersTab:CreateSection("Fling")
PlayersTab:CreateButton({
	Name = "💥 Fling Selected Player",
	Callback = function()
		local p = getTarget(); if not p then return end
		flingPlayer(p)
		Rayfield:Notify({ Title="💥 Flung!", Content=p.Name.." has been flung.", Duration=3, Image=4483362458 })
	end,
})
PlayersTab:CreateButton({
	Name = "💥 Fling ALL Players",
	Callback = function()
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then flingPlayer(p) end
		end
		Rayfield:Notify({ Title="💥 Flung All!", Content="Everyone got flung.", Duration=3, Image=4483362458 })
	end,
})

PlayersTab:CreateSection("WalkSpeed")
PlayersTab:CreateSlider({
	Name = "WalkSpeed for Selected", Range = {0, 200}, Increment = 5,
	CurrentValue = 16, Flag = "TargetWalkSpeed",
	Callback = function(v)
		local p = getTarget(); if not p then return end
		setWalkSpeed(p, v)
	end,
})
PlayersTab:CreateButton({
	Name = "⚡ Apply WalkSpeed",
	Callback = function()
		local p = getTarget(); if not p then return end
		setWalkSpeed(p, Rayfield.Flags.TargetWalkSpeed or 16)
		Rayfield:Notify({ Title="WalkSpeed", Content=p.Name.." WalkSpeed set.", Duration=2, Image=4483362458 })
	end,
})
PlayersTab:CreateSlider({
	Name = "MY WalkSpeed", Range = {0, 200}, Increment = 5,
	CurrentValue = 16, Flag = "SelfWalkSpeed",
	Callback = function(v) setWalkSpeed(LocalPlayer, v) end,
})

PlayersTab:CreateSection("JumpPower")
PlayersTab:CreateSlider({
	Name = "JumpPower for Selected", Range = {0, 400}, Increment = 10,
	CurrentValue = 50, Flag = "TargetJumpPower",
	Callback = function(v)
		local p = getTarget(); if not p then return end
		setJumpPower(p, v)
	end,
})
PlayersTab:CreateButton({
	Name = "🦘 Apply JumpPower",
	Callback = function()
		local p = getTarget(); if not p then return end
		setJumpPower(p, Rayfield.Flags.TargetJumpPower or 50)
		Rayfield:Notify({ Title="JumpPower", Content=p.Name.." JumpPower set.", Duration=2, Image=4483362458 })
	end,
})
PlayersTab:CreateSlider({
	Name = "MY JumpPower", Range = {0, 400}, Increment = 10,
	CurrentValue = 50, Flag = "SelfJumpPower",
	Callback = function(v) setJumpPower(LocalPlayer, v) end,
})

-- ─────────────────────────────────────────
-- TAB 7 — Movement
-- ─────────────────────────────────────────
local MoveTab = Window:CreateTab("🚀 Movement", 4483362458)

MoveTab:CreateSection("Fly")
MoveTab:CreateToggle({
	Name = "Enable Fly", CurrentValue = false, Flag = "FlyEnabled",
	Callback = function(v) movementState.flyEnabled = v; if v then startFly() else stopFly() end end,
})
MoveTab:CreateSlider({
	Name = "Fly Speed", Range = {10,300}, Increment = 10,
	CurrentValue = flySpeed, Flag = "FlySpeed",
	Callback = function(v) flySpeed = v end,
})
MoveTab:CreateParagraph({ Title="Controls", Content="W/A/S/D · Space (up) · Left Ctrl (down)" })

MoveTab:CreateSection("Noclip")
MoveTab:CreateToggle({
	Name = "Enable Noclip", CurrentValue = false, Flag = "NoclipEnabled",
	Callback = function(v) movementState.noclipEnabled = v; if v then startNoclip() else stopNoclip() end end,
})

MoveTab:CreateSection("Infinite Jump")
MoveTab:CreateToggle({
	Name = "Enable Infinite Jump", CurrentValue = false, Flag = "InfJump",
	Callback = function(v) movementState.infJumpEnabled = v; if v then startInfJump() else stopInfJump() end end,
})

-- ============================================================
-- READY
-- ============================================================
Rayfield:Notify({
	Title    = "🌀 Phong Hub",
	Content  = "Loaded! Welcome, " .. LocalPlayer.Name .. ".",
	Duration = 5,
	Image    = 4483362458,
})
