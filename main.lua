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
-- (No external library needed — fully custom GUI)

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
-- CUSTOM GUI  (SKECH-style: left sidebar + card panels)
-- ============================================================
local ACCENT    = Color3.fromRGB(0, 200, 255)   -- cyan accent
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
	l.Font = Enum.Font.GothamBold
	l.TextSize = 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k,v in pairs(props) do l[k]=v end
	l.Parent = parent; return l
end
local function Btn(props, parent)
	local b = Instance.new("TextButton")
	b.BackgroundTransparency = 1
	b.TextColor3 = TEXT
	b.Font = Enum.Font.GothamBold
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
local function makeToggle(state, onToggle, parent, yOffset)
	-- Returns a row frame with label+toggle
	local row = Frame({
		Size = UDim2.new(1,0,0,28),
		BackgroundTransparency = 1,
	}, parent)
	local track = Frame({
		Size = UDim2.new(0,36,0,18),
		Position = UDim2.new(1,-36,0.5,-9),
		BackgroundColor3 = state and ACCENT or BORDER,
	}, row)
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
	return row, update
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
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			local abs = track.AbsolutePosition
			local sz  = track.AbsoluteSize
			local frac = math.clamp((i.Position.X - abs.X) / sz.X, 0, 1)
			local newVal = math.floor(min + frac*(max-min))
			fill.Size = UDim2.new(frac,0,1,0)
			valLabel.Text = tostring(newVal)
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
		Font = Enum.Font.Gotham,
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
			Font = Enum.Font.Gotham,
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
	Label({ Size=UDim2.new(0.55,0,1,0), Text=labelText, Font=Enum.Font.Gotham, TextSize=13, TextColor3=TEXTDIM }, row)
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
		Font = Enum.Font.GothamBold,
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

-- drag
local draggingGui, dragStart, startPos
Main.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingGui = true; dragStart = i.Position
		startPos = Main.Position
	end
end)
Main.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingGui = false end
end)
UIS.InputChanged:Connect(function(i)
	if draggingGui and i.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = i.Position - dragStart
		Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X,
		                          startPos.Y.Scale, startPos.Y.Offset+delta.Y)
	end
end)

-- ── SIDEBAR ───────────────────────────────────────────────────
local Sidebar = Frame({
	Size = UDim2.new(0,170,1,0),
	BackgroundColor3 = SIDEBAR,
}, Main)
Corner(10, Sidebar)

-- Logo area
local logoArea = Frame({ Size=UDim2.new(1,0,0,70), BackgroundTransparency=1 }, Sidebar)
Label({
	Size = UDim2.new(1,0,0,32),
	Position = UDim2.new(0,0,0,16),
	Text = "PHONG",
	TextSize = 22,
	Font = Enum.Font.GothamBlack,
	TextColor3 = ACCENT,
	TextXAlignment = Enum.TextXAlignment.Center,
}, logoArea)
Label({
	Size = UDim2.new(1,0,0,16),
	Position = UDim2.new(0,0,0,44),
	Text = "HUB",
	TextSize = 11,
	Font = Enum.Font.Gotham,
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
local tabTitle = Label({
	Size = UDim2.new(1,0,1,0),
	Text = "ESP",
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	TextColor3 = TEXT,
	TextXAlignment = Enum.TextXAlignment.Center,
}, tabHeader)

-- Scrollable panels area
local PanelArea = Frame({
	Size = UDim2.new(1,-20,1,-54),
	Position = UDim2.new(0,10,0,54),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, ContentArea)

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
		Font = Enum.Font.GothamBold,
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
	-- page frame (two-column grid)
	local pg = Frame({
		Size = UDim2.new(1,0,1,0),
		BackgroundTransparency = 1,
		Visible = false,
	}, PanelArea)
	pages[name] = pg
	-- left column
	local leftCol = Frame({
		Size = UDim2.new(0.5,-5,1,0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.None,
	}, pg)
	ListLayout(10, leftCol)
	-- right column
	local rightCol = Frame({
		Size = UDim2.new(0.5,-5,1,0),
		Position = UDim2.new(0.5,5,0,0),
		BackgroundTransparency = 1,
	}, pg)
	ListLayout(10, rightCol)
	return pg, leftCol, rightCol
end

-- ──────────────────────────────────────────────────────────────
-- PAGE: ESP
-- ──────────────────────────────────────────────────────────────
local _, espL, espR = addPage("ESP", "👁")

-- Card: Highlights
do
	local card, ct, hdr = makeCard("Highlights", ACCENT, espL, espL)
	local _, updHL = makeToggle(Settings.HighlightEnabled, function(v)
		Settings.HighlightEnabled = v; refreshAllHighlights()
	end, ct)
	-- toggle label
	local r1 = makeRow("Enable Highlights", ct); r1.LayoutOrder=-1
	-- fill trans slider
	local r2 = makeRow("Fill Transparency", ct)
	makeSlider(55, 0, 100, function(v) Settings.FillTransparency = v/100; for _,h in pairs(highlights) do h.FillTransparency=v/100 end end, ct)
	-- toggle in header
	local tgl = Frame({ Size=UDim2.new(0,36,0,18), Position=UDim2.new(1,-48,0.5,-9), BackgroundColor3=ACCENT }, hdr)
	Corner(9,tgl)
	local knob2 = Frame({ Size=UDim2.new(0,12,0,12), Position=UDim2.new(1,-15,0.5,-6), BackgroundColor3=WHITE }, tgl)
	Corner(6,knob2)
	local hlOn = Settings.HighlightEnabled
	tgl.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		hlOn = not hlOn
		Settings.HighlightEnabled = hlOn; refreshAllHighlights()
		TS:Create(tgl, TweenInfo.new(0.15), {BackgroundColor3=hlOn and ACCENT or BORDER}):Play()
		TS:Create(knob2, TweenInfo.new(0.15), {Position=hlOn and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)}):Play()
	end)
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
		setBtn.Text = "⏳ Press any key..."
		setBtn.TextColor3 = ACCENT
		task.wait(0.25)
		local conn
		conn = UIS.InputBegan:Connect(function(inp)
			if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if inp.KeyCode == Enum.KeyCode.Unknown then return end
			local lbl = tostring(inp.KeyCode):gsub("Enum%.KeyCode%.","")
			aimBindKey = inp.KeyCode; aimBindLabel = lbl
			bindLbl.Text = "[ "..lbl.." ]"
			isListeningForBind = false
			setBtn.Text = "🎮 Click then press key"
			setBtn.TextColor3 = TEXT
			conn:Disconnect()
		end)
		task.delay(8, function()
			if isListeningForBind then
				isListeningForBind = false
				setBtn.Text = "🎮 Click then press key"
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
	gl.CellPaddingH = UDim.new(0,3); gl.CellPaddingV = UDim.new(0,3)
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
		Font = Enum.Font.Gotham,
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
				Font = Enum.Font.Gotham,
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
	Label({ Size=UDim2.new(1,0,0,20), Text="W/A/S/D · Space (up) · LCtrl (down)", TextColor3=TEXTDIM, Font=Enum.Font.Gotham, TextSize=11 }, ct)
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
		Label({ Size=UDim2.new(1,0,0,20), Text=cd[1], TextColor3=TEXTDIM, Font=Enum.Font.Gotham, TextSize=13 }, ct)
	end
	Label({ Size=UDim2.new(1,0,0,20), Text="(Use executor color picker for custom colors)", TextColor3=TEXTDIM, Font=Enum.Font.Gotham, TextSize=11 }, ct)
end

do
	local card, ct, hdr = makeCard("Team Colors", Color3.fromRGB(60,160,255), tmR, tmR)
	Label({ Size=UDim2.new(1,0,0,20), Text="Fill / Outline / Box / Tracer", TextColor3=TEXTDIM, Font=Enum.Font.Gotham, TextSize=13 }, ct)
	Label({ Size=UDim2.new(1,0,0,20), Text="(Use executor color picker for custom colors)", TextColor3=TEXTDIM, Font=Enum.Font.Gotham, TextSize=11 }, ct)
end

-- ── Toggle GUI with RightAlt ──────────────────────────────────
UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.RightAlt then
		Main.Visible = not Main.Visible
	end
end)

-- ── Start on ESP page ─────────────────────────────────────────
showPage("ESP")

-- ============================================================
-- READY notification (small, bottom corner)
-- ============================================================
local notif = Frame({
	Size = UDim2.new(0,220,0,44),
	Position = UDim2.new(1,-230,1,-54),
	BackgroundColor3 = CARD,
}, SG)
Corner(8, notif)
Stroke(ACCENT, 1, notif)
Label({ Size=UDim2.new(1,-16,0.5,0), Position=UDim2.new(0,8,0,4), Text="🌀 Phong Hub loaded!", TextSize=13, Font=Enum.Font.GothamBold, TextColor3=ACCENT }, notif)
Label({ Size=UDim2.new(1,-16,0.5,0), Position=UDim2.new(0,8,0.5,0), Text="RAlt to show/hide", TextSize=11, Font=Enum.Font.Gotham, TextColor3=TEXTDIM }, notif)
TS:Create(notif, TweenInfo.new(0.4,Enum.EasingStyle.Quart,Enum.EasingDirection.Out,0,false,3), {Position=UDim2.new(1,-230,1,-54)}):Play()
task.delay(4.5, function()
	TS:Create(notif, TweenInfo.new(0.4), {BackgroundTransparency=1}):Play()
	task.wait(0.4); notif:Destroy()
end)

-- Dummy Window reference (no Rayfield needed anymore)
local Window = { Rayfield = false }

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
