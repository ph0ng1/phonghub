-- AdminESP.lua
-- LocalScript → StarterPlayerScripts
-- Requires Rayfield: https://sirius.menu/rayfield
-- Uses Drawing API (executor environment)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Camera            = workspace.CurrentCamera
local LocalPlayer       = Players.LocalPlayer

-- ============================================================
-- LOAD RAYFIELD
-- ============================================================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- ============================================================
-- SETTINGS
-- ============================================================
local Settings = {
	-- Highlights
	HighlightEnabled    = true,
	FillTransparency    = 0.55,
	OutlineTransparency = 0.0,

	-- 2D Box
	BoxEnabled          = true,
	BoxThickness        = 1,

	-- Tracers
	TracerEnabled       = true,
	TracerOrigin        = "Bottom",  -- "Bottom" | "Center" | "Top"
	TracerThickness     = 1,

	-- Labels
	HealthBarEnabled    = true,
	NameTagEnabled      = true,
	DistanceLabelEnabled = true,

	-- Logic
	TeamCheckEnabled    = true,
	SeparateColors      = true,
	MaxRenderDistance   = 1000,  -- studs; 0 = unlimited

	-- Colors (Enemy)
	EnemyFillColor      = Color3.fromRGB(255, 60,  60),
	EnemyOutlineColor   = Color3.fromRGB(255, 160, 160),
	EnemyTracerColor    = Color3.fromRGB(255, 60,  60),
	EnemyBoxColor       = Color3.fromRGB(255, 60,  60),
	EnemyNameColor      = Color3.fromRGB(255, 60,  60),

	-- Aim Assist
	AimAssistEnabled    = false,
	AimStrength         = 0.5,   -- 0.0 (off) → 1.0 (snap)
	AimFOV              = 120,   -- radius in pixels
	AimSmoothing        = 6,     -- higher = slower/smoother camera movement
	AimBone             = "Head",-- "Head" | "HumanoidRootPart" | "UpperTorso"
	AimTeamCheck        = true,  -- skip teammates
	AimWallCheck        = true,  -- skip targets behind walls
	AimFOVCircle        = true,  -- draw FOV circle on screen
	AimFOVColor         = Color3.fromRGB(255, 255, 255),
	AimFOVThickness     = 1,

	-- Wall Check
	WallCheckEnabled    = false,  -- false = always show (through walls)
	WallCheckHideBox    = false,  -- true = hide box/tracer when behind wall
	WallCheckHideHL     = false,  -- true = hide highlight when behind wall
	WallHiddenBoxColor  = Color3.fromRGB(100, 100, 100),  -- dimmed color when behind wall
	WallHiddenAlpha     = 0.4,    -- transparency multiplier for hidden players

	-- Colors (Team)
	TeamFillColor       = Color3.fromRGB(60,  160, 255),
	TeamOutlineColor    = Color3.fromRGB(160, 220, 255),
	TeamTracerColor     = Color3.fromRGB(60,  160, 255),
	TeamBoxColor        = Color3.fromRGB(60,  160, 255),
	TeamNameColor       = Color3.fromRGB(60,  160, 255),
}

-- ============================================================
-- STATE
-- ============================================================
local highlights        = {}   -- [Player] = Highlight
local perPlayerOverride = {}   -- [Player] = true/false (force on/force off)
local whitelist         = {}   -- [Player] = true  (silently skip)

-- Aim assist keybind state
local aimBindKey        = Enum.UserInputType.MouseButton2  -- default: RMB
local aimBindLabel      = "RMB"       -- human-readable name shown in UI
local isListeningForBind = false      -- true while waiting for next input

-- ============================================================
-- DRAWING POOL
-- ============================================================
-- Pool tables keyed by type string
local pools = {}
local poolIdx = {}

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
		for _, d in ipairs(tbl) do
			d.Visible = false
		end
		poolIdx[dtype] = 0
	end
end

-- Helpers
local function newLine()
	local l = acquireDrawing("Line")
	l.Thickness = Settings.BoxThickness
	return l
end

local function newText()
	local t = acquireDrawing("Text")
	t.Size     = 13
	t.Font     = Drawing.Fonts.UI
	t.Outline  = true
	t.OutlineColor = Color3.fromRGB(0,0,0)
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
		hl.Name   = "AdminESP_HL"
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
-- 2D BOX: derive tight screen box from character parts
-- ============================================================
local function getBoundingBox2D(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- Use HEAD top and HRP bottom as vertical anchors (world-axis aligned, no rotation issues)
	local head = char:FindFirstChild("Head")
	local topPos    = head and head.Position + Vector3.new(0, head.Size.Y / 2, 0)
	                       or  hrp.Position  + Vector3.new(0, 3.5, 0)
	local bottomPos = hrp.Position - Vector3.new(0, 3, 0)

	-- Project 8 world-axis-aligned corners of the character AABB
	local halfW = 1.5  -- half-width / half-depth in studs
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

	local minX, minY = math.huge,  math.huge
	local maxX, maxY = -math.huge, -math.huge
	local anyOnScreen = false

	for _, c in ipairs(corners) do
		local sp, onScreen = Camera:WorldToViewportPoint(c)
		if onScreen or sp.Z > 0 then   -- include corners behind camera edge too
			anyOnScreen = true
			if sp.X < minX then minX = sp.X end
			if sp.Y < minY then minY = sp.Y end
			if sp.X > maxX then maxX = sp.X end
			if sp.Y > maxY then maxY = sp.Y end
		end
	end

	if not anyOnScreen then return nil end

	return {
		minX   = minX,   minY   = minY,
		maxX   = maxX,   maxY   = maxY,
		width  = maxX - minX,
		height = maxY - minY,
	}
end

-- ============================================================
-- HEALTH BAR COLOR  green → red
-- ============================================================
local function healthColor(frac)
	-- green (0,200,0) → red (200,0,0)
	return Color3.fromRGB(
		math.floor((1 - frac) * 200),
		math.floor(frac * 200),
		0
	)
end

-- ============================================================
-- TRACER ORIGIN
-- ============================================================
local function getTracerOrigin()
	local vp = Camera.ViewportSize
	if Settings.TracerOrigin == "Top"    then return Vector2.new(vp.X/2, 0)       end
	if Settings.TracerOrigin == "Center" then return Vector2.new(vp.X/2, vp.Y/2)  end
	return Vector2.new(vp.X/2, vp.Y)
end

-- ============================================================
-- AIM ASSIST FUNCTIONS  (must be before RenderStepped)
-- ============================================================
local aimFOVCircle  -- Drawing.Circle for the FOV ring

local function getAimFOVCircle()
	if not aimFOVCircle then
		aimFOVCircle          = Drawing.new("Circle")
		aimFOVCircle.Filled   = false
		aimFOVCircle.Thickness = Settings.AimFOVThickness
		aimFOVCircle.NumSides  = 64
		aimFOVCircle.Visible   = false
	end
	return aimFOVCircle
end

local function getBestTarget()
	local vp     = Camera.ViewportSize
	local center = Vector2.new(vp.X / 2, vp.Y / 2)
	local bestPlayer, bestDist = nil, math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		if Settings.AimTeamCheck and isTeammate(player) then continue end
		if whitelist[player] then continue end
		if perPlayerOverride[player] == false then continue end

		local char = player.Character
		if not char then continue end

		local bone = char:FindFirstChild(Settings.AimBone)
			or char:FindFirstChild("HumanoidRootPart")
		if not bone then continue end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then continue end

		local worldDist = (bone.Position - Camera.CFrame.Position).Magnitude
		if Settings.MaxRenderDistance > 0 and worldDist > Settings.MaxRenderDistance then continue end

		local sp, onScreen = Camera:WorldToViewportPoint(bone.Position)
		if not onScreen then continue end

		-- Wall check: skip this target if they're behind a wall
		if Settings.AimWallCheck then
			local hrp2 = char:FindFirstChild("HumanoidRootPart") or bone
			local exclude = { char }
			local localChar = LocalPlayer.Character
			if localChar then table.insert(exclude, localChar) end
			local wp = RaycastParams.new()
			wp.FilterType = Enum.RaycastFilterType.Exclude
			wp.FilterDescendantsInstances = exclude
			local origin = Camera.CFrame.Position
			local result = workspace:Raycast(origin, hrp2.Position - origin, wp)
			if result and not result.Instance:IsDescendantOf(char) then
				continue  -- blocked by a wall, skip target
			end
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
	-- Get current camera look direction and desired look direction
	local camCF    = Camera.CFrame
	local desiredCF = CFrame.lookAt(camCF.Position, worldPos)

	-- Lerp the rotation only (keep position fixed)
	local alpha = math.clamp(Settings.AimStrength / math.max(Settings.AimSmoothing, 1), 0, 1)

	-- Temporarily set Scriptable, move, restore immediately
	local prevType = Camera.CameraType
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CFrame = camCF:Lerp(desiredCF, alpha)
	Camera.CameraType = prevType
end

local function releaseCamera()
	if Camera.CameraType == Enum.CameraType.Scriptable then
		Camera.CameraType = Enum.CameraType.Custom
	end
end

-- ============================================================
-- WALL CHECK
-- ============================================================
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function isVisible(char, hrp)
	-- Build exclusion list: local character + target character
	local exclude = { char }
	local localChar = LocalPlayer.Character
	if localChar then table.insert(exclude, localChar) end
	raycastParams.FilterDescendantsInstances = exclude

	local origin    = Camera.CFrame.Position
	local direction = hrp.Position - origin

	local result = workspace:Raycast(origin, direction, raycastParams)
	-- If raycast hits nothing, or hits something inside the target character → visible
	if not result then return true end
	-- Check if the hit instance belongs to the target character
	local hitInst = result.Instance
	return hitInst:IsDescendantOf(char)
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

		-- Distance cull
		local dist = (hrp.Position - Camera.CFrame.Position).Magnitude
		if Settings.MaxRenderDistance > 0 and dist > Settings.MaxRenderDistance then continue end

		local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
		if not onScreen then continue end

		local sp2D = Vector2.new(screenPos.X, screenPos.Y)

		local _, _, tracerColor, boxColor, nameColor = getColors(player)

		-- ── WALL CHECK ───────────────────────────────────────
		local playerVisible = true
		if Settings.WallCheckEnabled then
			playerVisible = isVisible(char, hrp)
			-- If hidden and we should fully hide drawing elements → skip
			if not playerVisible and Settings.WallCheckHideBox then continue end
			-- If hidden, dim the colors
			if not playerVisible then
				boxColor    = Settings.WallHiddenBoxColor
				tracerColor = Settings.WallHiddenBoxColor
				nameColor   = Settings.WallHiddenBoxColor
			end
			-- Manage highlight visibility
			if highlights[player] then
				if not playerVisible and Settings.WallCheckHideHL then
					highlights[player].Enabled = false
				else
					highlights[player].Enabled = true
				end
			end
		end

		-- ── 2D BOX ──────────────────────────────────────────
		local box
		if Settings.BoxEnabled then
			box = getBoundingBox2D(char)
			if box then
				local q = newQuad()
				q.PointA = Vector2.new(box.minX, box.minY)
				q.PointB = Vector2.new(box.maxX, box.minY)
				q.PointC = Vector2.new(box.maxX, box.maxY)
				q.PointD = Vector2.new(box.minX, box.maxY)
				q.Color     = boxColor
				q.Thickness = Settings.BoxThickness
				q.Visible   = true
			end
		end

		-- ── HEALTH BAR ───────────────────────────────────────
		if Settings.HealthBarEnabled and box then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
				local barX    = box.minX - 5
				local barTop  = box.minY
				local barBot  = box.maxY
				local barH    = box.height
				local fillBot = barBot
				local fillTop = barBot - barH * frac

				-- Background (dark)
				local bg = newLine()
				bg.From      = Vector2.new(barX, barTop)
				bg.To        = Vector2.new(barX, barBot)
				bg.Thickness = 4
				bg.Color     = Color3.fromRGB(20, 20, 20)
				bg.Visible   = true

				-- Filled portion
				local fill = newLine()
				fill.From      = Vector2.new(barX, fillBot)
				fill.To        = Vector2.new(barX, fillTop)
				fill.Thickness = 3
				fill.Color     = healthColor(frac)
				fill.Visible   = true
			end
		end

		-- ── NAME TAG ─────────────────────────────────────────
		if Settings.NameTagEnabled and box then
			local t = newText()
			t.Text     = player.DisplayName
			t.Color    = nameColor
			t.Size     = 13
			t.Position = Vector2.new(box.minX + box.width/2 - (#player.DisplayName * 3.5), box.minY - 16)
			t.Visible  = true
		end

		-- ── DISTANCE LABEL ───────────────────────────────────
		if Settings.DistanceLabelEnabled and box then
			local label = string.format("[%d studs]", math.floor(dist))
			local t = newText()
			t.Text     = label
			t.Color    = Color3.fromRGB(180, 180, 180)
			t.Size     = 12
			t.Position = Vector2.new(box.minX + box.width/2 - (#label * 3), box.maxY + 3)
			t.Visible  = true
		end

		-- ── TRACER ───────────────────────────────────────────
		if Settings.TracerEnabled then
			local l = newLine()
			l.From      = tracerOrigin
			l.To        = sp2D
			l.Thickness = Settings.BoxThickness
			l.Color     = tracerColor
			l.Visible   = true
		end
	end

	-- ── FOV CIRCLE ───────────────────────────────────────────
	local fovCircle = getAimFOVCircle()
	local vp = Camera.ViewportSize
	fovCircle.Position  = Vector2.new(vp.X / 2, vp.Y / 2)
	fovCircle.Radius    = Settings.AimFOV
	fovCircle.Color     = Settings.AimFOVColor
	fovCircle.Thickness = Settings.AimFOVThickness
	fovCircle.Visible   = Settings.AimFOVCircle and Settings.AimAssistEnabled

	-- ── AIM ASSIST ────────────────────────────────────────────
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
			if target then
				local tChar = target.Character
				if tChar then
					local bone = tChar:FindFirstChild(Settings.AimBone)
						or tChar:FindFirstChild("HumanoidRootPart")
					if bone then
						smoothAimAt(bone.Position)
					end
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

	-- Apply ESP to an already-loaded character
	local function applyToChar(char)
		-- Wait until HumanoidRootPart exists (character may not be fully loaded)
		local hrp = char:FindFirstChild("HumanoidRootPart")
			or char:WaitForChild("HumanoidRootPart", 5)
		if not hrp then return end
		refreshHighlight(player)
	end

	-- Current character (player was already in-game when script loaded)
	if player.Character then
		applyToChar(player.Character)
	end

	-- Every future spawn / respawn
	player.CharacterAdded:Connect(function(char)
		applyToChar(char)
	end)
end

-- Players already in server when script runs
for _, p in ipairs(Players:GetPlayers()) do
	setupPlayer(p)
end

-- Players who join after script loads
Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	removeHighlight(player)
	perPlayerOverride[player] = nil
	whitelist[player] = nil
end)

-- ============================================================
-- RAYFIELD UI
-- ============================================================
local Window = Rayfield:CreateWindow({
	Name            = "🌀 Phong Hub",
	LoadingTitle    = "Phong Hub",
	LoadingSubtitle = "ESP & Aim Assist",
	Theme           = "Default",
	ConfigurationSaving = { Enabled = false },
	KeySystem       = false,
})

-- ─────────────────────────────────────────
-- TAB 1: Highlights
-- ─────────────────────────────────────────
local HLTab = Window:CreateTab("✨ Highlights", 4483362458)

HLTab:CreateSection("Toggle")
HLTab:CreateToggle({
	Name = "Enable Highlights", CurrentValue = Settings.HighlightEnabled, Flag = "HLEnabled",
	Callback = function(v) Settings.HighlightEnabled = v; refreshAllHighlights() end,
})

HLTab:CreateSection("Transparency")
HLTab:CreateSlider({
	Name = "Fill Transparency", Range = {0,1}, Increment = 0.05,
	CurrentValue = Settings.FillTransparency, Flag = "FillTrans",
	Callback = function(v)
		Settings.FillTransparency = v
		for _, hl in pairs(highlights) do hl.FillTransparency = v end
	end,
})
HLTab:CreateSlider({
	Name = "Outline Transparency", Range = {0,1}, Increment = 0.05,
	CurrentValue = Settings.OutlineTransparency, Flag = "OutlineTrans",
	Callback = function(v)
		Settings.OutlineTransparency = v
		for _, hl in pairs(highlights) do hl.OutlineTransparency = v end
	end,
})

-- ─────────────────────────────────────────
-- TAB 2: Box & Tracers
-- ─────────────────────────────────────────
local DrawTab = Window:CreateTab("📦 Box & Tracers", 4483362458)

DrawTab:CreateSection("2D Box")
DrawTab:CreateToggle({
	Name = "Enable 2D Box", CurrentValue = Settings.BoxEnabled, Flag = "BoxEnabled",
	Callback = function(v) Settings.BoxEnabled = v end,
})

DrawTab:CreateSection("Tracers")
DrawTab:CreateToggle({
	Name = "Enable Tracers", CurrentValue = Settings.TracerEnabled, Flag = "TracerEnabled",
	Callback = function(v) Settings.TracerEnabled = v end,
})
DrawTab:CreateDropdown({
	Name = "Tracer Origin", Options = {"Bottom","Center","Top"},
	CurrentOption = {Settings.TracerOrigin}, MultipleOptions = false, Flag = "TracerOrigin",
	Callback = function(v)
		if type(v) == "table" then v = v[1] end
		Settings.TracerOrigin = v
	end,
})

DrawTab:CreateSection("Thickness (Box & Tracers)")
DrawTab:CreateSlider({
	Name = "Box / Tracer Thickness", Range = {1,5}, Increment = 1,
	CurrentValue = Settings.BoxThickness, Flag = "BoxThick",
	Callback = function(v) Settings.BoxThickness = v end,
})

-- ─────────────────────────────────────────
-- TAB 3: Labels
-- ─────────────────────────────────────────
local LabelTab = Window:CreateTab("🏷️ Labels", 4483362458)

LabelTab:CreateSection("Toggle Labels")
LabelTab:CreateToggle({
	Name = "Health Bar", CurrentValue = Settings.HealthBarEnabled, Flag = "HealthBar",
	Callback = function(v) Settings.HealthBarEnabled = v end,
})
LabelTab:CreateToggle({
	Name = "Name Tag (DisplayName)", CurrentValue = Settings.NameTagEnabled, Flag = "NameTag",
	Callback = function(v) Settings.NameTagEnabled = v end,
})
LabelTab:CreateToggle({
	Name = "Distance Label [N studs]", CurrentValue = Settings.DistanceLabelEnabled, Flag = "DistLabel",
	Callback = function(v) Settings.DistanceLabelEnabled = v end,
})

LabelTab:CreateSection("Render Distance")
LabelTab:CreateSlider({
	Name = "Max Render Distance (studs, 0=unlimited)", Range = {0, 2000}, Increment = 50,
	CurrentValue = Settings.MaxRenderDistance, Flag = "MaxDist",
	Callback = function(v) Settings.MaxRenderDistance = v end,
})

-- ─────────────────────────────────────────
-- TAB 4: Colors
-- ─────────────────────────────────────────
local ColorTab = Window:CreateTab("🎨 Colors", 4483362458)

ColorTab:CreateSection("Separate Enemy / Team")
ColorTab:CreateToggle({
	Name = "Separate Colors", CurrentValue = Settings.SeparateColors, Flag = "SepColors",
	Callback = function(v) Settings.SeparateColors = v; refreshAllHighlights() end,
})

ColorTab:CreateSection("Enemy")
ColorTab:CreateColorPicker({ Name="Enemy Fill",    Color=Settings.EnemyFillColor,    Flag="EFill",    Callback=function(c) Settings.EnemyFillColor=c;    refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Enemy Outline", Color=Settings.EnemyOutlineColor, Flag="EOutline", Callback=function(c) Settings.EnemyOutlineColor=c; refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Enemy Box",     Color=Settings.EnemyBoxColor,     Flag="EBox",     Callback=function(c) Settings.EnemyBoxColor=c end })
ColorTab:CreateColorPicker({ Name="Enemy Tracer",  Color=Settings.EnemyTracerColor,  Flag="ETracer",  Callback=function(c) Settings.EnemyTracerColor=c end })
ColorTab:CreateColorPicker({ Name="Enemy Name Tag",Color=Settings.EnemyNameColor,    Flag="EName",    Callback=function(c) Settings.EnemyNameColor=c end })

ColorTab:CreateSection("Team")
ColorTab:CreateColorPicker({ Name="Team Fill",    Color=Settings.TeamFillColor,    Flag="TFill",    Callback=function(c) Settings.TeamFillColor=c;    refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Team Outline", Color=Settings.TeamOutlineColor, Flag="TOutline", Callback=function(c) Settings.TeamOutlineColor=c; refreshAllHighlights() end })
ColorTab:CreateColorPicker({ Name="Team Box",     Color=Settings.TeamBoxColor,     Flag="TBox",     Callback=function(c) Settings.TeamBoxColor=c end })
ColorTab:CreateColorPicker({ Name="Team Tracer",  Color=Settings.TeamTracerColor,  Flag="TTracer",  Callback=function(c) Settings.TeamTracerColor=c end })
ColorTab:CreateColorPicker({ Name="Team Name Tag",Color=Settings.TeamNameColor,    Flag="TName",    Callback=function(c) Settings.TeamNameColor=c end })

-- ─────────────────────────────────────────
-- TAB 5: Team Check
-- ─────────────────────────────────────────
local TeamTab = Window:CreateTab("🛡️ Team Check", 4483362458)
TeamTab:CreateSection("Settings")
TeamTab:CreateToggle({
	Name = "Skip Teammates (Highlights, Box & Tracers)",
	CurrentValue = Settings.TeamCheckEnabled, Flag = "TeamCheck",
	Callback = function(v) Settings.TeamCheckEnabled = v; refreshAllHighlights() end,
})

-- ─────────────────────────────────────────
-- TAB 5.5: Wall Check
-- ─────────────────────────────────────────
local WallTab = Window:CreateTab("🧱 Wall Check", 4483362458)

WallTab:CreateSection("Toggle")

WallTab:CreateToggle({
	Name         = "Enable Wall Check",
	CurrentValue = Settings.WallCheckEnabled,
	Flag         = "WallCheck",
	Callback     = function(v)
		Settings.WallCheckEnabled = v
		-- Re-enable all highlights when turning off wall check
		if not v then
			for _, hl in pairs(highlights) do
				hl.Enabled = true
			end
		end
	end,
})

WallTab:CreateSection("Behind-Wall Behaviour")

WallTab:CreateToggle({
	Name         = "Hide Box & Tracer (behind wall)",
	CurrentValue = Settings.WallCheckHideBox,
	Flag         = "WallHideBox",
	Callback     = function(v) Settings.WallCheckHideBox = v end,
})

WallTab:CreateToggle({
	Name         = "Hide Highlight (behind wall)",
	CurrentValue = Settings.WallCheckHideHL,
	Flag         = "WallHideHL",
	Callback     = function(v) Settings.WallCheckHideHL = v end,
})

WallTab:CreateParagraph({
	Title   = "Dimmed Mode",
	Content = "When Hide toggles are OFF, players behind walls are still drawn but their box, tracer and name are dimmed to a grey color so you can tell they're occluded.",
})

WallTab:CreateSection("Dimmed Color")

WallTab:CreateColorPicker({
	Name     = "Behind-Wall Color",
	Color    = Settings.WallHiddenBoxColor,
	Flag     = "WallHiddenColor",
	Callback = function(c) Settings.WallHiddenBoxColor = c end,
})

-- ─────────────────────────────────────────
-- TAB 6: Players (Override + Whitelist)
-- ─────────────────────────────────────────
local PlayersTab = Window:CreateTab("👤 Players", 4483362458)

local function getPlayerNames()
	local t = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then table.insert(t, p.Name) end
	end
	if #t == 0 then table.insert(t, "(no players)") end
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

PlayersTab:CreateSection("Per-Player Override")

PlayersTab:CreateButton({
	Name = "✅ Force ON for Selected",
	Callback = function()
		local p = getTarget()
		if p then
			perPlayerOverride[p] = true; refreshHighlight(p)
			Rayfield:Notify({ Title="Force ON", Content=p.Name.." forced visible.", Duration=3, Image=4483362458 })
		end
	end,
})
PlayersTab:CreateButton({
	Name = "❌ Force OFF for Selected",
	Callback = function()
		local p = getTarget()
		if p then
			perPlayerOverride[p] = false; removeHighlight(p)
			Rayfield:Notify({ Title="Force OFF", Content=p.Name.." force hidden.", Duration=3, Image=4483362458 })
		end
	end,
})
PlayersTab:CreateButton({
	Name = "🔁 Clear Override for Selected",
	Callback = function()
		local p = getTarget()
		if p then
			perPlayerOverride[p] = nil; refreshHighlight(p)
			Rayfield:Notify({ Title="Cleared", Content=p.Name.." back to default.", Duration=3, Image=4483362458 })
		end
	end,
})

PlayersTab:CreateSection("Whitelist (silently skip)")

PlayersTab:CreateButton({
	Name = "➕ Whitelist Selected Player",
	Callback = function()
		local p = getTarget()
		if p then
			whitelist[p] = true; removeHighlight(p)
			Rayfield:Notify({ Title="Whitelisted", Content=p.Name.." will be silently skipped.", Duration=3, Image=4483362458 })
		end
	end,
})
PlayersTab:CreateButton({
	Name = "➖ Remove from Whitelist",
	Callback = function()
		local p = getTarget()
		if p then
			whitelist[p] = nil; refreshHighlight(p)
			Rayfield:Notify({ Title="Un-whitelisted", Content=p.Name.." removed from whitelist.", Duration=3, Image=4483362458 })
		end
	end,
})
PlayersTab:CreateButton({
	Name = "📋 Show Whitelist",
	Callback = function()
		local names = {}
		for pl in pairs(whitelist) do table.insert(names, pl.Name) end
		local msg = #names > 0 and table.concat(names, ", ") or "None"
		Rayfield:Notify({ Title="Whitelist", Content=msg, Duration=5, Image=4483362458 })
	end,
})

-- ─────────────────────────────────────────
-- TAB 7: Aim Assist
-- ─────────────────────────────────────────
local AimTab = Window:CreateTab("🎯 Aim Assist", 4483362458)

AimTab:CreateSection("Toggle")

AimTab:CreateToggle({
	Name = "Enable Aim Assist",
	CurrentValue = Settings.AimAssistEnabled,
	Flag = "AimEnabled",
	Callback = function(v)
		Settings.AimAssistEnabled = v
		if not v and aimFOVCircle then
			aimFOVCircle.Visible = false
		end
		Rayfield:Notify({
			Title   = v and "Aim Assist ON" or "Aim Assist OFF",
			Content = v and "Hold RMB to snap to nearest target in FOV." or "Aim assist disabled.",
			Duration = 3, Image = 4483362458,
		})
	end,
})

AimTab:CreateSection("Strength & Smoothing")

AimTab:CreateSlider({
	Name = "Strength (0 = off, 1 = instant snap)",
	Range = {0, 1}, Increment = 0.05,
	CurrentValue = Settings.AimStrength, Flag = "AimStrength",
	Callback = function(v) Settings.AimStrength = v end,
})

AimTab:CreateSlider({
	Name = "Smoothing (higher = slower, more natural)",
	Range = {1, 20}, Increment = 1,
	CurrentValue = Settings.AimSmoothing, Flag = "AimSmooth",
	Callback = function(v) Settings.AimSmoothing = v end,
})

AimTab:CreateSection("FOV")

AimTab:CreateSlider({
	Name = "FOV Radius (pixels)",
	Range = {20, 400}, Increment = 10,
	CurrentValue = Settings.AimFOV, Flag = "AimFOV",
	Callback = function(v) Settings.AimFOV = v end,
})

AimTab:CreateToggle({
	Name = "Show FOV Circle",
	CurrentValue = Settings.AimFOVCircle, Flag = "AimFOVCircle",
	Callback = function(v) Settings.AimFOVCircle = v end,
})

AimTab:CreateColorPicker({
	Name = "FOV Circle Color",
	Color = Settings.AimFOVColor, Flag = "AimFOVColor",
	Callback = function(c)
		Settings.AimFOVColor = c
		if aimFOVCircle then aimFOVCircle.Color = c end
	end,
})

AimTab:CreateSlider({
	Name = "FOV Circle Thickness",
	Range = {1, 4}, Increment = 1,
	CurrentValue = Settings.AimFOVThickness, Flag = "AimFOVThick",
	Callback = function(v)
		Settings.AimFOVThickness = v
		if aimFOVCircle then aimFOVCircle.Thickness = v end
	end,
})

AimTab:CreateSection("Target Bone")

AimTab:CreateDropdown({
	Name = "Aim Bone Target",
	Options = { "Head", "UpperTorso", "HumanoidRootPart" },
	CurrentOption = { Settings.AimBone },
	MultipleOptions = false, Flag = "AimBone",
	Callback = function(v)
		if type(v) == "table" then v = v[1] end
		Settings.AimBone = v
	end,
})

AimTab:CreateSection("Team & Wall Check")

AimTab:CreateToggle({
	Name = "Skip Teammates (Aim Assist)",
	CurrentValue = Settings.AimTeamCheck, Flag = "AimTeamCheck",
	Callback = function(v) Settings.AimTeamCheck = v end,
})

AimTab:CreateToggle({
	Name = "Skip Players Behind Walls",
	CurrentValue = Settings.AimWallCheck, Flag = "AimWallCheck",
	Callback = function(v) Settings.AimWallCheck = v end,
})

AimTab:CreateSection("Keybind")

-- Rayfield has no live-update paragraph/label. We use a disabled-style button name as display.
-- The real live display is kept via Notify on change, and the button name shows on open.
local bindDisplayBtn = AimTab:CreateButton({
	Name     = "📌 Bind: [ " .. aimBindLabel .. " ]",
	Callback = function() end, -- display only
})

local function updateBindDisplay()
	-- Update the display button name (Rayfield supports this via the returned object)
	bindDisplayBtn.Name = "📌 Bind: [ " .. aimBindLabel .. " ]"
	Rayfield:Notify({
		Title   = "✅ Bind Set",
		Content = "Aim assist activates on: " .. aimBindLabel,
		Duration = 3,
		Image   = 4483362458,
	})
end

AimTab:CreateButton({
	Name = "🎮 Set Keybind — click then press a key",
	Callback = function()
		if isListeningForBind then return end
		isListeningForBind = true

		Rayfield:Notify({
			Title   = "⏳ Listening...",
			Content = "Press any keyboard key. Use Quick Binds for mouse buttons.",
			Duration = 5,
			Image   = 4483362458,
		})

		task.wait(0.25) -- let the button click clear before we start listening

		local conn
		conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if input.KeyCode == Enum.KeyCode.Unknown then return end

			local label = tostring(input.KeyCode):gsub("Enum%.KeyCode%.", "")
			aimBindKey        = input.KeyCode
			aimBindLabel      = label
			isListeningForBind = false
			conn:Disconnect()
			updateBindDisplay()
		end)

		task.delay(8, function()
			if isListeningForBind then
				isListeningForBind = false
				conn:Disconnect()
				Rayfield:Notify({
					Title   = "Cancelled",
					Content = "No key pressed. Keeping: " .. aimBindLabel,
					Duration = 3,
					Image   = 4483362458,
				})
			end
		end)
	end,
})

AimTab:CreateSection("Quick Binds")

local function quickBind(key, label)
	aimBindKey        = key
	aimBindLabel      = label
	updateBindDisplay()
end

AimTab:CreateButton({ Name = "🖱️ Right Mouse Button (RMB)", Callback = function() quickBind(Enum.UserInputType.MouseButton2, "RMB")       end })
AimTab:CreateButton({ Name = "🖱️ Left Mouse Button (LMB)",  Callback = function() quickBind(Enum.UserInputType.MouseButton1, "LMB")       end })
AimTab:CreateButton({ Name = "⌨️ Left Alt",                  Callback = function() quickBind(Enum.KeyCode.LeftAlt,            "LeftAlt")   end })
AimTab:CreateButton({ Name = "⌨️ Left Shift",                Callback = function() quickBind(Enum.KeyCode.LeftShift,          "LeftShift") end })
AimTab:CreateButton({ Name = "⌨️ Q",                         Callback = function() quickBind(Enum.KeyCode.Q,                  "Q")         end })
AimTab:CreateButton({ Name = "⌨️ E",                         Callback = function() quickBind(Enum.KeyCode.E,                  "E")         end })
AimTab:CreateButton({ Name = "⌨️ F",                         Callback = function() quickBind(Enum.KeyCode.F,                  "F")         end })
AimTab:CreateButton({ Name = "⌨️ CapsLock",                  Callback = function() quickBind(Enum.KeyCode.CapsLock,           "CapsLock")  end })

-- ============================================================
-- MOVEMENT FEATURES
-- ============================================================
local movementState = {
	flyEnabled     = false,
	noclipEnabled  = false,
	infJumpEnabled = false,
}

-- ── FLY ──────────────────────────────────────────────────────
local flySpeed     = 50
local flyBodyVel   = nil
local flyBodyGyro  = nil
local flyConn      = nil

local function startFly()
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	hum.PlatformStand = true

	flyBodyVel = Instance.new("BodyVelocity")
	flyBodyVel.Velocity       = Vector3.zero
	flyBodyVel.MaxForce       = Vector3.new(1e5, 1e5, 1e5)
	flyBodyVel.Parent         = hrp

	flyBodyGyro = Instance.new("BodyGyro")
	flyBodyGyro.MaxTorque     = Vector3.new(1e5, 1e5, 1e5)
	flyBodyGyro.P             = 1e4
	flyBodyGyro.CFrame        = hrp.CFrame
	flyBodyGyro.Parent        = hrp

	flyConn = RunService.RenderStepped:Connect(function()
		if not movementState.flyEnabled then return end
		local camCF = Camera.CFrame
		local moveDir = Vector3.zero

		if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += camCF.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= camCF.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= camCF.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += camCF.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0,1,0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir -= Vector3.new(0,1,0) end

		if moveDir.Magnitude > 0 then
			flyBodyVel.Velocity = moveDir.Unit * flySpeed
		else
			flyBodyVel.Velocity = Vector3.zero
		end
		flyBodyGyro.CFrame = camCF
	end)
end

local function stopFly()
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	if flyBodyVel  then flyBodyVel:Destroy();  flyBodyVel  = nil end
	if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
	local char = LocalPlayer.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.PlatformStand = false end
	end
end

-- ── NOCLIP ───────────────────────────────────────────────────
local noclipConn = nil

local function startNoclip()
	noclipConn = RunService.Stepped:Connect(function()
		if not movementState.noclipEnabled then return end
		local char = LocalPlayer.Character
		if not char then return end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)
end

local function stopNoclip()
	if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
	local char = LocalPlayer.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end
end

-- ── INF JUMP ─────────────────────────────────────────────────
local infJumpConn = nil

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

-- Re-hook inf jump and fly on respawn
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	if movementState.flyEnabled     then startFly()     end
	if movementState.noclipEnabled  then startNoclip()  end
	if movementState.infJumpEnabled then startInfJump() end
end)

-- ============================================================
-- TAB 8: Movement
-- ============================================================
local MoveTab = Window:CreateTab("🚀 Movement", 4483362458)

MoveTab:CreateSection("Fly")

MoveTab:CreateToggle({
	Name = "Enable Fly",
	CurrentValue = false,
	Flag = "FlyEnabled",
	Callback = function(v)
		movementState.flyEnabled = v
		if v then startFly() else stopFly() end
	end,
})

MoveTab:CreateSlider({
	Name = "Fly Speed",
	Range = {10, 300}, Increment = 10,
	CurrentValue = flySpeed, Flag = "FlySpeed",
	Callback = function(v) flySpeed = v end,
})

MoveTab:CreateParagraph({
	Title   = "Fly Controls",
	Content = "W/A/S/D = direction  |  Space = up  |  Left Ctrl = down",
})

MoveTab:CreateSection("Noclip")

MoveTab:CreateToggle({
	Name = "Enable Noclip",
	CurrentValue = false,
	Flag = "NoclipEnabled",
	Callback = function(v)
		movementState.noclipEnabled = v
		if v then startNoclip() else stopNoclip() end
	end,
})

MoveTab:CreateSection("Infinite Jump")

MoveTab:CreateToggle({
	Name = "Enable Infinite Jump",
	CurrentValue = false,
	Flag = "InfJump",
	Callback = function(v)
		movementState.infJumpEnabled = v
		if v then startInfJump() else stopInfJump() end
	end,
})

-- ============================================================
-- READY
-- ============================================================
Rayfield:Notify({
	Title    = "Phong Hub Loaded",
	Content  = "Welcome, " .. LocalPlayer.Name .. "!",
	Duration = 5,
	Image    = 4483362458,
})
