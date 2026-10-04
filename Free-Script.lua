--// =========================================================
--// ⚡ SJ SCRIPT V1.12
--// REDESIGNED HUD
--// ESP + AIMBOT + PROTECTED PLAYERS
--// =========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--// SPECTATOR STATE
local SpectatorEnabled = false
local SpectatorTarget = nil
local SpectatorIndex = 0
local SpectatorTargets = {}
local SpectatorTargetLabel = nil
local SpectatorPrevButton = nil
local SpectatorNextButton = nil

--// =========================================================
--// VEHICLE / SEAT CAMERA FIX
--// Keeps the camera attached to the local Humanoid when
--// Roblox temporarily changes CameraSubject to a Seat/VehicleSeat.
--// =========================================================

local function ResetSeatCamera()
    local character = LocalPlayer.Character
    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if humanoid then
        Camera.CameraSubject = humanoid
    elseif root then
        Camera.CameraSubject = root
    end
end

local function FixVehicleSeatCamera()
    local subject = Camera.CameraSubject

    if subject and (subject:IsA("VehicleSeat") or subject:IsA("Seat")) then
        ResetSeatCamera()
    end
end

RunService.Heartbeat:Connect(FixVehicleSeatCamera)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if not SpectatorEnabled then
        ResetSeatCamera()
    end
end)

--// =========================================================
--// CONFIG
--// =========================================================

local GUI_KEY = Enum.KeyCode.G

local AimbotEnabled = false
local AimbotSmoothness = 5
local AimbotFOV = 110
local Wallcheck = true

--// AIM PART
local AimPart = "Head"

--// AIM PART SWITCH
local AimPartSwitchEnabled = false
local AimPartSwitchMode = "Alternate"
local AimPartSwitchA = "Head"
local AimPartSwitchB = "UpperTorso"
local AimSwitchOnShot = true
local AimResetOnTargetChange = true
local AimSwitchState = false
local LastSwitchTarget = nil
local LastShotTime = 0
local ShotDebounce = 0.12

--// AIMBOT RPG
local RPGAimEnabled = false
local RPGPrediction = 0.12
local RPGSmoothness = 5
local RPGFootOffset = Vector3.new(0, -2.5, 0)
local RPGBind = Enum.KeyCode.V
local WaitingForRPGBind = false
local RPGAimToggleButton = nil

local AimbotBind = Enum.KeyCode.LeftAlt
local WaitingForBind = false

local ESPEnabled = false
local ESPName = true
local ESPDistance = true
local ESPHealth = true
local ESPWeapon = true
local ESPTracer = true
local ESPHighlight = true

local CurrentTarget = nil
local ProtectedPlayers = {}

--// =========================================================
--// ESP DATA
--// =========================================================

local ESPData = {}

local RarityColors = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 255, 0),
	Rare = Color3.fromRGB(0, 170, 255),
	Epic = Color3.fromRGB(170, 0, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 0, 0)
}

--// =========================================================
--// WEAPON REGISTRY
--// Same matching structure as the ESP supplied by the user.
--// Extra indexes are only fallbacks so numeric/internal Tool
--// names are never preferred over a readable registered name.
--// =========================================================

local Items = game:GetService("ReplicatedStorage"):FindFirstChild("Items")
local WeaponRegistry = {}
local WeaponNameIndex = {}
local WeaponItemIdIndex = {}

local function ReadDisplayName(tool)
	if not tool then return nil end

	local name = tool:GetAttribute("DisplayName")
		or tool:GetAttribute("ItemName")
		or tool:GetAttribute("WeaponName")
		or tool:GetAttribute("Title")

	if typeof(name) == "string" and name ~= "" then
		return name
	end

	for _, childName in ipairs({"DisplayName", "ItemName", "WeaponName", "Title"}) do
		local child = tool:FindFirstChild(childName)
		if child and child:IsA("StringValue") and child.Value ~= "" then
			return child.Value
		end
	end

	return nil
end

local function GetToolRarity(tool)
	return tool:GetAttribute("RarityName")
		or tool:GetAttribute("Rarity")
		or "Common"
end

local function AddRegistryEntry(tool)
	if not tool or not tool:IsA("Tool") then return end

	local handle = tool:FindFirstChild("Handle")
	local displayName = ReadDisplayName(tool) or tool.Name
	local itemId = tool:GetAttribute("ItemId")
		or tool:GetAttribute("Id")
		or tool:GetAttribute("ItemID")
		or tool.Name
	local rarity = GetToolRarity(tool)

	local key

	if handle then
		local mesh = handle:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshId ~= "" then
			key = mesh.MeshId .. (mesh.TextureId or "") .. "_RARITY_" .. rarity
		elseif handle:IsA("MeshPart") and handle.MeshId ~= "" then
			key = handle.MeshId .. (handle.TextureID or "") .. "_RARITY_" .. rarity
		end
	end

	if not key and itemId and itemId ~= "" and itemId ~= tool.Name then
		key = "ITEMID_" .. itemId .. "_RARITY_" .. rarity
	end

	if not key then
		key = "NAME_" .. displayName .. "_" .. tool.Name .. "_RARITY_" .. rarity
	end

	WeaponRegistry[key] = {
		Name = displayName,
		Rarity = rarity,
		ToolName = tool.Name,
		ItemId = itemId
	}

	-- Additional exact-name / ItemId indexes. These do not replace
	-- the original mesh/item/rarity matching; they make it resilient
	-- when the live Tool has a generated numeric name.
	if tool.Name and tool.Name ~= "" then
		WeaponNameIndex[tool.Name] = WeaponRegistry[key]
	end
	if itemId and itemId ~= "" then
		WeaponItemIdIndex[tostring(itemId)] = WeaponRegistry[key]
	end
end

local function RegisterItems(folder)
	if not folder then return end

	for _, tool in ipairs(folder:GetChildren()) do
		if tool:IsA("Tool") then
			AddRegistryEntry(tool)
		end
	end
end

local function ScanFolders(folder)
	if not folder then return end

	RegisterItems(folder)

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Folder") then
			ScanFolders(child)
		end
	end

	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)
		if child:IsA("Folder") then
			ScanFolders(child)
		else
			RegisterItems(folder)
		end
	end)
end

ScanFolders(Items)

local function GetItemKey(tool)
	if not tool then return nil end

	local handle = tool:FindFirstChild("Handle")
	local displayName = ReadDisplayName(tool) or tool.Name
	local itemId = tool:GetAttribute("ItemId")
		or tool:GetAttribute("Id")
		or tool:GetAttribute("ItemID")
		or tool.Name
	local rarity = GetToolRarity(tool)

	if handle then
		local mesh = handle:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshId ~= "" then
			return mesh.MeshId .. (mesh.TextureId or "") .. "_RARITY_" .. rarity
		end
		if handle:IsA("MeshPart") and handle.MeshId ~= "" then
			return handle.MeshId .. (handle.TextureID or "") .. "_RARITY_" .. rarity
		end
	end

	if itemId and itemId ~= "" and itemId ~= tool.Name then
		return "ITEMID_" .. itemId .. "_RARITY_" .. rarity
	end

	return "NAME_" .. displayName .. "_" .. tool.Name .. "_RARITY_" .. rarity
end

local function GetWeaponInfo(tool)
	if not tool or not tool:IsA("Tool") then return nil end

	local info = WeaponRegistry[GetItemKey(tool)]
	if info then return info end

	-- Same structure, with safe fallbacks for generated live names.
	info = WeaponNameIndex[tool.Name]
	if info then return info end

	local itemId = tool:GetAttribute("ItemId")
		or tool:GetAttribute("Id")
		or tool:GetAttribute("ItemID")
	if itemId then
		info = WeaponItemIdIndex[tostring(itemId)]
		if info then return info end
	end

	local displayName = ReadDisplayName(tool)
	if displayName and displayName ~= "" then
		return {
			Name = displayName,
			Rarity = GetToolRarity(tool)
		}
	end

	return nil
end

local function GetWeapons(player)
	local items = {}

	local function scan(container)
		if not container then return end

		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") and tool.Name ~= "Fists" then
				local info = GetWeaponInfo(tool)
				local rarity = GetToolRarity(tool)

				if info then
					table.insert(items, {
						Name = info.Name,
						Rarity = info.Rarity or rarity
					})
				else
					-- Do not intentionally display a generated numeric ID when
					-- the Tool has no readable registry match.
					local fallbackName = ReadDisplayName(tool)
					if fallbackName and fallbackName ~= "" then
						table.insert(items, {
							Name = fallbackName,
							Rarity = rarity
						})
					end
				end
			end
		end
	end

	scan(player:FindFirstChild("Backpack"))
	scan(player.Character)

	return items
end

--// =========================================================
--// GUI
--// =========================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SJ_SCRIPT_V112"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = CoreGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 620, 0, 430)

--// DEVICE ADAPTATION
--// PC keeps the original 620x430 size.
--// Mobile uses UIScale so the entire menu becomes smaller without
--// changing the existing GUI proportions or feature logic.
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)

Main.BackgroundColor3 =
	Color3.fromRGB(10, 10, 16)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local MainScale = Instance.new("UIScale")
MainScale.Scale = 1
MainScale.Parent = Main

local function UpdateDeviceScale()
	local viewport = Camera and Camera.ViewportSize
	if not viewport then
		MainScale.Scale = 1
		return
	end

	-- Touch + no physical keyboard is a reliable mobile/phone indicator.
	local isMobile = UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled

	if isMobile then
		-- Keeps the menu comfortably inside narrow phone screens.
		local widthScale = viewport.X / 700
		MainScale.Scale = math.clamp(
			math.min(0.70, widthScale),
			0.50,
			0.70
		)
	else
		-- PC: exactly the original size.
		MainScale.Scale = 1
	end
end

UpdateDeviceScale()

if Camera then
	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateDeviceScale)
end

Instance.new("UICorner", Main).CornerRadius =
	UDim.new(0, 14)

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 2
MainStroke.Parent = Main

local AuraStroke = Instance.new("UIStroke")
AuraStroke.Thickness = 8
AuraStroke.Transparency = 0.8
AuraStroke.Parent = Main

--// =========================================================
--// HEADER
--// =========================================================

--// =========================================================
--// MINIMIZE BUTTON
--// =========================================================

local MenuMinimized = false
local SavedMenuSize = Main.Size
local SavedMenuPosition = Main.Position
local MinimizedMenuSize = UDim2.new(0, 620, 0, 65)

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 65)
Header.BackgroundColor3 =
	Color3.fromRGB(19, 19, 29)
Header.BorderSizePixel = 0
Header.Parent = Main

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Name = "MinimizeButton"
MinimizeButton.Size = UDim2.new(0, 38, 0, 38)
MinimizeButton.Position = UDim2.new(1, -48, 0.5, -19)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
MinimizeButton.Text = "−"
MinimizeButton.TextColor3 = Color3.fromRGB(235, 235, 240)
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.TextSize = 22
MinimizeButton.AutoButtonColor = false
MinimizeButton.BorderSizePixel = 0
MinimizeButton.ZIndex = 100
MinimizeButton.Active = true
MinimizeButton.Parent = Header

Instance.new("UICorner", MinimizeButton).CornerRadius = UDim.new(0, 8)

MinimizeButton.MouseEnter:Connect(function()
    TweenService:Create(MinimizeButton, TweenInfo.new(0.12), {
        BackgroundColor3 = Color3.fromRGB(55, 55, 70)
    }):Play()
end)

MinimizeButton.MouseLeave:Connect(function()
    TweenService:Create(MinimizeButton, TweenInfo.new(0.12), {
        BackgroundColor3 = Color3.fromRGB(38, 38, 52)
    }):Play()
end)

local function SetMenuMinimized(state)
    if state == MenuMinimized then
        return
    end

    if state then
        -- Save the current position/size so minimizing does not move the menu.
        SavedMenuSize = Main.Size
        SavedMenuPosition = Main.Position

        MenuMinimized = true
        Sidebar.Visible = false
        Content.Visible = false
        Main.Size = MinimizedMenuSize
        MinimizeButton.Text = "+"
    else
        MenuMinimized = false
        Sidebar.Visible = true
        Content.Visible = true
        Main.Size = SavedMenuSize
        Main.Position = SavedMenuPosition
        MinimizeButton.Text = "−"
    end
end

-- Activated works with both mouse clicks and mobile touch input.
MinimizeButton.Activated:Connect(function()
    SetMenuMinimized(not MenuMinimized)
end)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 20, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "⚡ SJ SCRIPT  V1.12"
Title.TextColor3 =
	Color3.fromRGB(255, 215, 0)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 23
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -80, 0, 18)
Subtitle.Position = UDim2.new(0, 20, 1, -22)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "Advanced Control Panel"
Subtitle.TextColor3 =
	Color3.fromRGB(130, 130, 150)
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextSize = 11
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

--// =========================================================
--// SIDEBAR
--// =========================================================

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 150, 1, -65)
Sidebar.Position = UDim2.new(0, 0, 0, 65)
Sidebar.BackgroundColor3 =
	Color3.fromRGB(14, 14, 22)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Main

local SideLayout = Instance.new("UIListLayout")
SideLayout.Padding = UDim.new(0, 7)
SideLayout.HorizontalAlignment =
	Enum.HorizontalAlignment.Center
SideLayout.VerticalAlignment =
	Enum.VerticalAlignment.Top
SideLayout.Parent = Sidebar

local SidePadding = Instance.new("UIPadding")
SidePadding.PaddingTop = UDim.new(0, 15)
SidePadding.Parent = Sidebar

local function CreateTab(text, icon)

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -20, 0, 48)
	button.BackgroundColor3 =
		Color3.fromRGB(25, 25, 38)
	button.Text = icon .. "   " .. text
	button.TextColor3 =
		Color3.fromRGB(180, 180, 195)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Parent = Sidebar

	Instance.new("UICorner", button).CornerRadius =
		UDim.new(0, 9)

	button.MouseEnter:Connect(function()

		TweenService:Create(
			button,
			TweenInfo.new(
				0.15,
				Enum.EasingStyle.Quad
			),
			{
				BackgroundColor3 =
					Color3.fromRGB(38, 38, 55),

				TextColor3 =
					Color3.fromRGB(255, 255, 255)
			}
		):Play()
	end)

	button.MouseLeave:Connect(function()

		if not button:GetAttribute("Selected") then

			TweenService:Create(
				button,
				TweenInfo.new(0.15),
				{
					BackgroundColor3 =
						Color3.fromRGB(25, 25, 38),

					TextColor3 =
						Color3.fromRGB(180, 180, 195)
				}
			):Play()
		end
	end)

	return button
end

local ESPTab =
	CreateTab("ESP", "👁")

local AimTab =
	CreateTab("Aimbot", "🎯")

local ProtectTab =
	CreateTab("Protected", "🛡")

--// =========================================================
--// CONTENT AREA
--// =========================================================

local Content = Instance.new("Frame")
Content.Size = UDim2.new(
	1,
	-170,
	1,
	-80
)
Content.Position = UDim2.new(
	0,
	165,
	0,
	75
)
Content.BackgroundTransparency = 1
Content.Parent = Main

local Pages = {}

local function CreatePage()

	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 3
	page.ScrollBarImageTransparency = 0.3
	page.AutomaticCanvasSize =
		Enum.AutomaticSize.Y
	page.CanvasSize =
		UDim2.new(0, 0, 0, 0)
	page.Visible = false
	page.Parent = Content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 9)
	layout.SortOrder =
		Enum.SortOrder.LayoutOrder
	layout.Parent = page

	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 15)
	padding.Parent = page

	table.insert(Pages, page)

	return page
end

local ESPPage = CreatePage()
local AimPage = CreatePage()
local ProtectPage = CreatePage()

--// =========================================================
--// UI HELPERS
--// =========================================================

local function CreateSectionTitle(parent, text)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 32)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 =
		Color3.fromRGB(255, 215, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextXAlignment =
		Enum.TextXAlignment.Left
	label.Parent = parent

	return label
end

local function CreateToggle(
	parent,
	text,
	initial,
	callback
)

	local button = Instance.new("TextButton")

	button.Size =
		UDim2.new(1, 0, 0, 40)

	button.BackgroundColor3 =
		initial
		and Color3.fromRGB(25, 95, 55)
		or Color3.fromRGB(38, 38, 52)

	button.TextColor3 =
		Color3.fromRGB(235, 235, 240)

	button.Text =
		text
		.. "    "
		.. (initial and "ON" or "OFF")

	button.Font =
		Enum.Font.GothamSemibold

	button.TextSize = 13
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Parent = parent

	Instance.new("UICorner", button).CornerRadius =
		UDim.new(0, 8)

	local state = initial

	local function Update()

		button.Text =
			text
			.. "    "
			.. (state and "ON" or "OFF")

		TweenService:Create(
			button,
			TweenInfo.new(
				0.18,
				Enum.EasingStyle.Quad
			),
			{
				BackgroundColor3 =
					state
					and Color3.fromRGB(25, 95, 55)
					or Color3.fromRGB(38, 38, 52)
			}
		):Play()
	end

	button.MouseButton1Click:Connect(function()

		state = not state

		callback(state)

		Update()
	end)

	return button
end

local function CreateValueBox(
	parent,
	text,
	value,
	callback
)

	local holder = Instance.new("Frame")
	holder.Size =
		UDim2.new(1, 0, 0, 42)
	holder.BackgroundColor3 =
		Color3.fromRGB(24, 24, 36)
	holder.BorderSizePixel = 0
	holder.Parent = parent

	Instance.new("UICorner", holder).CornerRadius =
		UDim.new(0, 8)

	local label = Instance.new("TextLabel")
	label.Size =
		UDim2.new(0.55, 0, 1, 0)
	label.Position =
		UDim2.new(0, 12, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 =
		Color3.fromRGB(220, 220, 230)
	label.Font = Enum.Font.GothamSemibold
	label.TextSize = 13
	label.TextXAlignment =
		Enum.TextXAlignment.Left
	label.Parent = holder

	local box = Instance.new("TextBox")
	box.Size =
		UDim2.new(0.35, 0, 0, 28)
	box.Position =
		UDim2.new(0.62, 0, 0.5, -14)
	box.BackgroundColor3 =
		Color3.fromRGB(40, 40, 55)
	box.TextColor3 =
		Color3.fromRGB(255, 215, 0)
	box.Text =
		tostring(value)
	box.Font =
		Enum.Font.GothamBold
	box.TextSize = 13
	box.ClearTextOnFocus = false
	box.BorderSizePixel = 0
	box.Parent = holder

	Instance.new("UICorner", box).CornerRadius =
		UDim.new(0, 6)

	box.FocusLost:Connect(function()

		local number =
			tonumber(box.Text)

		if number then

			callback(number)

			box.Text =
				tostring(number)

		else

			box.Text =
				tostring(value)
		end
	end)

	return box
end

local function CreateBindButton(parent)

	local holder = Instance.new("Frame")
	holder.Size =
		UDim2.new(1, 0, 0, 45)
	holder.BackgroundColor3 =
		Color3.fromRGB(24, 24, 36)
	holder.BorderSizePixel = 0
	holder.Parent = parent

	Instance.new("UICorner", holder).CornerRadius =
		UDim.new(0, 8)

	local label = Instance.new("TextLabel")
	label.Size =
		UDim2.new(0.5, 0, 1, 0)
	label.Position =
		UDim2.new(0, 12, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "Aimbot Bind"
	label.TextColor3 =
		Color3.fromRGB(220, 220, 230)
	label.Font =
		Enum.Font.GothamSemibold
	label.TextSize = 13
	label.TextXAlignment =
		Enum.TextXAlignment.Left
	label.Parent = holder

	local bindButton = Instance.new("TextButton")
	bindButton.Size =
		UDim2.new(0.35, 0, 0, 30)
	bindButton.Position =
		UDim2.new(0.62, 0, 0.5, -15)
	bindButton.BackgroundColor3 =
		Color3.fromRGB(50, 50, 70)
	bindButton.Text =
		AimbotBind.Name
	bindButton.TextColor3 =
		Color3.fromRGB(255, 215, 0)
	bindButton.Font =
		Enum.Font.GothamBold
	bindButton.TextSize = 12
	bindButton.AutoButtonColor = false
	bindButton.BorderSizePixel = 0
	bindButton.Parent = holder

	Instance.new("UICorner", bindButton).CornerRadius =
		UDim.new(0, 6)

	bindButton.MouseButton1Click:Connect(function()

		WaitingForBind = true

		bindButton.Text =
			"PRESS ANY KEY"

		bindButton.TextColor3 =
			Color3.fromRGB(255, 100, 100)
	end)

	return bindButton
end

--// =========================================================
--// SPECTATOR SYSTEM
--// =========================================================

local function RefreshSpectatorTargets()
    SpectatorTargets = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(SpectatorTargets, player)
        end
    end

    if #SpectatorTargets == 0 then
        SpectatorIndex = 0
        SpectatorTarget = nil
        if SpectatorTargetLabel then
            SpectatorTargetLabel.Text = "Spectating: nobody"
        end
        return
    end

    if SpectatorTarget then
        for i, player in ipairs(SpectatorTargets) do
            if player == SpectatorTarget then
                SpectatorIndex = i
                break
            end
        end
    end

    SpectatorIndex = math.clamp(SpectatorIndex, 1, #SpectatorTargets)
end

local function GetSpectatorHumanoid(player)
    if not player then return nil end
    local character = player.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        return humanoid
    end
    return nil
end

local function ApplySpectatorCamera(player)
    if not SpectatorEnabled or not player then return false end

    local humanoid = GetSpectatorHumanoid(player)
    if not humanoid then return false end

    SpectatorTarget = player
    Camera.CameraType = Enum.CameraType.Custom
    Camera.CameraSubject = humanoid

    if SpectatorTargetLabel then
        SpectatorTargetLabel.Text = "Spectating: " .. player.Name
    end
    return true
end

local function StopSpectating()
    SpectatorEnabled = false
    SpectatorTarget = nil
    SpectatorIndex = 0

    if SpectatorTargetLabel then
        SpectatorTargetLabel.Text = "Spectating: nobody"
    end

    ResetSeatCamera()
end

local function StartSpectating(player)
    RefreshSpectatorTargets()
    if #SpectatorTargets == 0 then
        SpectatorEnabled = false
        return false
    end

    if player then
        for i, candidate in ipairs(SpectatorTargets) do
            if candidate == player then
                SpectatorIndex = i
                break
            end
        end
    elseif not SpectatorTarget then
        SpectatorIndex = math.clamp(SpectatorIndex, 1, #SpectatorTargets)
        player = SpectatorTargets[SpectatorIndex]
    else
        player = SpectatorTarget
    end

    SpectatorEnabled = true

    if not ApplySpectatorCamera(player) then
        -- If the selected player is dead/respawning, find the next valid player.
        for offset = 1, #SpectatorTargets do
            local idx = ((SpectatorIndex - 1 + offset) % #SpectatorTargets) + 1
            if ApplySpectatorCamera(SpectatorTargets[idx]) then
                SpectatorIndex = idx
                return true
            end
        end
        StopSpectating()
        return false
    end

    return true
end

local function SpectatorStep(direction)
    RefreshSpectatorTargets()
    if #SpectatorTargets == 0 then
        StopSpectating()
        return
    end

    SpectatorEnabled = true
    local base = SpectatorIndex
    if base < 1 or base > #SpectatorTargets then
        base = 1
    end

    for offset = 1, #SpectatorTargets do
        local idx = ((base - 1 + (direction * offset)) % #SpectatorTargets) + 1
        if idx < 1 then idx = idx + #SpectatorTargets end
        SpectatorIndex = idx
        if ApplySpectatorCamera(SpectatorTargets[idx]) then
            return
        end
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.25)
        if SpectatorEnabled and SpectatorTarget == player then
            ApplySpectatorCamera(player)
        end
    end)
    RefreshSpectatorTargets()
end)

Players.PlayerRemoving:Connect(function(player)
    local wasTarget = SpectatorTarget == player
    RefreshSpectatorTargets()

    if wasTarget and SpectatorEnabled then
        if #SpectatorTargets > 0 then
            SpectatorIndex = math.clamp(SpectatorIndex, 1, #SpectatorTargets)
            if not ApplySpectatorCamera(SpectatorTargets[SpectatorIndex]) then
                SpectatorStep(1)
            end
        else
            StopSpectating()
        end
    end
end)

-- Keep the spectator camera stable through respawns/deaths without fighting Roblox's camera system.
RunService.Heartbeat:Connect(function()
    if not SpectatorEnabled then return end

    local target = SpectatorTarget
    if not target or target.Parent ~= Players then
        RefreshSpectatorTargets()
        if #SpectatorTargets > 0 then
            SpectatorStep(1)
        else
            StopSpectating()
        end
        return
    end

    local humanoid = GetSpectatorHumanoid(target)
    if not humanoid then
        -- Target is dead/respawning. Do not leave the camera attached to a dead Humanoid.
        RefreshSpectatorTargets()
        for offset = 0, #SpectatorTargets - 1 do
            local idx = ((SpectatorIndex - 1 + offset) % #SpectatorTargets) + 1
            if ApplySpectatorCamera(SpectatorTargets[idx]) then
                SpectatorIndex = idx
                return
            end
        end
        return
    end

    if Camera.CameraSubject ~= humanoid or Camera.CameraType ~= Enum.CameraType.Custom then
        Camera.CameraType = Enum.CameraType.Custom
        Camera.CameraSubject = humanoid
    end
end)

--// =========================================================
--// ESP PAGE
--// =========================================================

CreateSectionTitle(
	ESPPage,
	"👁  ESP SETTINGS"
)

CreateToggle(
	ESPPage,
	"ESP Master",
	false,
	function(state)

		ESPEnabled = state

		if not state then

			for player in pairs(ESPData) do
				RemoveESP(player)
			end
		end
	end
)

CreateToggle(
	ESPPage,
	"Name ESP",
	true,
	function(state)

		ESPName = state
	end
)

CreateToggle(
	ESPPage,
	"Distance",
	true,
	function(state)

		ESPDistance = state
	end
)

CreateToggle(
	ESPPage,
	"Health",
	true,
	function(state)

		ESPHealth = state
	end
)

CreateToggle(
	ESPPage,
	"Weapon ESP",
	true,
	function(state)

		ESPWeapon = state
	end
)

CreateToggle(
	ESPPage,
	"Tracer",
	true,
	function(state)

		ESPTracer = state
	end
)

CreateToggle(
	ESPPage,
	"Highlight",
	true,
	function(state)

		ESPHighlight = state
	end
)

--// =========================================================
--// SPECTATOR
--// =========================================================

CreateSectionTitle(ESPPage, "👁‍🗨  SPECTATOR")

local SpectatorToggleButton = CreateToggle(ESPPage, "Spectator", false, function(state)
    SpectatorEnabled = state
    if state then
        StartSpectating()
    else
        StopSpectating()
    end
end)

SpectatorTargetLabel = Instance.new("TextLabel")
SpectatorTargetLabel.Size = UDim2.new(1, 0, 0, 30)
SpectatorTargetLabel.BackgroundTransparency = 1
SpectatorTargetLabel.Text = "Spectating: nobody"
SpectatorTargetLabel.TextColor3 = Color3.fromRGB(180, 180, 195)
SpectatorTargetLabel.Font = Enum.Font.GothamSemibold
SpectatorTargetLabel.TextSize = 12
SpectatorTargetLabel.Parent = ESPPage

local SpectatorControls = Instance.new("Frame")
SpectatorControls.Size = UDim2.new(1, 0, 0, 40)
SpectatorControls.BackgroundTransparency = 1
SpectatorControls.Parent = ESPPage

local SpectatorLayout = Instance.new("UIListLayout")
SpectatorLayout.FillDirection = Enum.FillDirection.Horizontal
SpectatorLayout.Padding = UDim.new(0, 6)
SpectatorLayout.Parent = SpectatorControls

local function MakeSpectatorButton(text)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.333, -4, 1, 0)
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 52)
    button.Text = text
    button.TextColor3 = Color3.fromRGB(255, 215, 0)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 12
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.Parent = SpectatorControls
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
    return button
end

SpectatorPrevButton = MakeSpectatorButton("◀ PREV")
local SpectatorStopButton = MakeSpectatorButton("■ STOP")
SpectatorNextButton = MakeSpectatorButton("NEXT ▶")

SpectatorPrevButton.MouseButton1Click:Connect(function()
    SpectatorStep(-1)
end)

SpectatorNextButton.MouseButton1Click:Connect(function()
    SpectatorStep(1)
end)

SpectatorStopButton.MouseButton1Click:Connect(function()
    StopSpectating()
    if SpectatorToggleButton then
        SpectatorToggleButton.Text = "Spectator    OFF"
    end
end)

--// =========================================================
--// AIMBOT PAGE
--// =========================================================

CreateSectionTitle(
	AimPage,
	"🎯  AIMBOT SETTINGS"
)

local AimbotToggleButton = CreateToggle(
	AimPage,
	"Aimbot",
	false,
	function(state)

		AimbotEnabled = state
	end
)

CreateValueBox(
	AimPage,
	"Smoothness",
	AimbotSmoothness,
	function(value)
		AimbotSmoothness = math.clamp(math.floor(value), 1, 20)
	end
)

CreateValueBox(
	AimPage,
	"FOV",
	AimbotFOV,
	function(value)
		AimbotFOV = math.clamp(math.floor(value), 20, 600)
	end
)

local AimParts = {
	{Name = "Head", Part = "Head"},
	{Name = "UpperTorso", Part = "UpperTorso"},
	{Name = "LowerTorso", Part = "LowerTorso"},
	{Name = "HumanoidRootPart", Part = "HumanoidRootPart"},
	{Name = "Right Arm", Part = "RightUpperArm"},
	{Name = "Left Arm", Part = "LeftUpperArm"}
}

local function MakePartButton(parent, label, initial, setter)
	local index = 1
	for i, item in ipairs(AimParts) do
		if item.Part == initial then index = i break end
	end
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 40)
	button.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
	button.TextColor3 = Color3.fromRGB(255,255,255)
	button.Font = Enum.Font.GothamSemibold
	button.TextSize = 13
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = label .. ": " .. AimParts[index].Name
	button.Parent = parent
	Instance.new("UICorner", button).CornerRadius = UDim.new(0,8)
	button.MouseEnter:Connect(function()
		TweenService:Create(button,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(60,55,75)}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(45,45,65)}):Play()
	end)
	button.MouseButton1Click:Connect(function()
		index = index % #AimParts + 1
		setter(AimParts[index].Part)
		button.Text = label .. ": " .. AimParts[index].Name
	end)
	return button
end

CreateSectionTitle(AimPage, "🎯  AIM PART")

MakePartButton(AimPage, "Aim Part", AimPart, function(part)
	AimPart = part
end)

CreateSectionTitle(AimPage, "🔄  AIM PART SWITCH")

CreateToggle(AimPage, "Enable Switch", AimPartSwitchEnabled, function(state)
	AimPartSwitchEnabled = state
	if not state then AimSwitchState = false end
end)

CreateToggle(AimPage, "Switch on Shot", AimSwitchOnShot, function(state)
	AimSwitchOnShot = state
end)

CreateToggle(AimPage, "Reset on Target Change", AimResetOnTargetChange, function(state)
	AimResetOnTargetChange = state
end)

local SwitchModes = {"Alternate", "Random"}
local SwitchModeIndex = 1
local SwitchModeButton = Instance.new("TextButton")
SwitchModeButton.Size = UDim2.new(1,0,0,40)
SwitchModeButton.BackgroundColor3 = Color3.fromRGB(45,45,65)
SwitchModeButton.Text = "Switch Mode: Alternate"
SwitchModeButton.TextColor3 = Color3.fromRGB(255,255,255)
SwitchModeButton.Font = Enum.Font.GothamSemibold
SwitchModeButton.TextSize = 13
SwitchModeButton.AutoButtonColor = false
SwitchModeButton.BorderSizePixel = 0
SwitchModeButton.Parent = AimPage
Instance.new("UICorner", SwitchModeButton).CornerRadius = UDim.new(0,8)
SwitchModeButton.MouseButton1Click:Connect(function()
	SwitchModeIndex = SwitchModeIndex % #SwitchModes + 1
	AimPartSwitchMode = SwitchModes[SwitchModeIndex]
	SwitchModeButton.Text = "Switch Mode: " .. AimPartSwitchMode
end)

MakePartButton(AimPage, "Part A", AimPartSwitchA, function(part)
	AimPartSwitchA = part
end)

MakePartButton(AimPage, "Part B", AimPartSwitchB, function(part)
	AimPartSwitchB = part
end)

CreateToggle(
	AimPage,
	"Wallcheck",
	true,
	function(state)

		Wallcheck = state
	end
)

local BindButton =
	CreateBindButton(AimPage)

local BindInfo = Instance.new("TextLabel")
BindInfo.Size =
	UDim2.new(1, 0, 0, 28)
BindInfo.BackgroundTransparency = 1
BindInfo.Text =
	"Press the bind to toggle Aimbot instantly"
BindInfo.TextColor3 =
	Color3.fromRGB(115, 115, 135)
BindInfo.Font =
	Enum.Font.Gotham
BindInfo.TextSize = 11
BindInfo.Parent = AimPage

--// =========================================================
--// AIMBOT RPG
--// =========================================================

CreateSectionTitle(AimPage, "🚀  AIMBOT RPG")

RPGAimToggleButton = CreateToggle(AimPage, "Aimbot RPG", false, function(state)
    RPGAimEnabled = state
end)

CreateValueBox(AimPage, "Prediction", RPGPrediction, function(value)
    RPGPrediction = math.clamp(tonumber(value) or RPGPrediction, 0, 2)
end)

CreateValueBox(AimPage, "Smoothness", RPGSmoothness, function(value)
    RPGSmoothness = math.clamp(math.floor(tonumber(value) or RPGSmoothness), 1, 100)
end)

local RPGKeyButton = Instance.new("TextButton")
RPGKeyButton.Size = UDim2.new(1, 0, 0, 40)
RPGKeyButton.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
RPGKeyButton.Text = "RPG Keybind: " .. RPGBind.Name
RPGKeyButton.TextColor3 = Color3.fromRGB(255, 215, 0)
RPGKeyButton.Font = Enum.Font.GothamSemibold
RPGKeyButton.TextSize = 13
RPGKeyButton.AutoButtonColor = false
RPGKeyButton.BorderSizePixel = 0
RPGKeyButton.Parent = AimPage
Instance.new("UICorner", RPGKeyButton).CornerRadius = UDim.new(0, 8)

RPGKeyButton.MouseButton1Click:Connect(function()
    WaitingForRPGBind = true
    RPGKeyButton.Text = "RPG Keybind: PRESS ANY KEY"
    RPGKeyButton.TextColor3 = Color3.fromRGB(255, 100, 100)
end)

--// =========================================================
--// PROTECTED PAGE
--// =========================================================

CreateSectionTitle(
	ProtectPage,
	"🛡  PROTECTED PLAYERS"
)

local PlayerList =
	Instance.new("ScrollingFrame")

PlayerList.Size =
	UDim2.new(1, 0, 0, 300)

PlayerList.BackgroundTransparency = 1
PlayerList.BorderSizePixel = 0
PlayerList.ScrollBarThickness = 4
PlayerList.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
PlayerList.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayerList.Parent = ProtectPage

local PlayerLayout =
	Instance.new("UIListLayout")

PlayerLayout.Padding =
	UDim.new(0, 5)

PlayerLayout.Parent = PlayerList

--// =========================================================
--// SHOW PAGE
--// =========================================================

local function ShowPage(page, selected)

	for _, p in ipairs(Pages) do
		p.Visible = false
	end

	page.Visible = true

	for _, button in ipairs({
		ESPTab,
		AimTab,
		ProtectTab
	}) do

		button:SetAttribute(
			"Selected",
			button == selected
		)

		TweenService:Create(
			button,
			TweenInfo.new(0.18),
			{
				BackgroundColor3 =
					button == selected
					and Color3.fromRGB(55, 45, 25)
					or Color3.fromRGB(25, 25, 38),

				TextColor3 =
					button == selected
					and Color3.fromRGB(255, 215, 0)
					or Color3.fromRGB(180, 180, 195)
			}
		):Play()
	end
end

ESPTab.MouseButton1Click:Connect(function()
	ShowPage(ESPPage, ESPTab)
end)

AimTab.MouseButton1Click:Connect(function()
	ShowPage(AimPage, AimTab)
end)

ProtectTab.MouseButton1Click:Connect(function()
	ShowPage(ProtectPage, ProtectTab)
end)

ShowPage(ESPPage, ESPTab)

--// =========================================================
--// PROTECTED PLAYERS UPDATE
--// =========================================================

local function IsFriend(player)
	if not player or player == LocalPlayer then
		return false
	end

	local ok, result = pcall(function()
		return LocalPlayer:IsFriendsWith(player.UserId)
	end)

	return ok and result == true
end

local function AutoProtectFriend(player)
	if player and player ~= LocalPlayer and IsFriend(player) then
		ProtectedPlayers[player] = true
		return true
	end
	return false
end

local function UpdateProtectedList()
	-- La lista SIEMPRE muestra a todos los jugadores del servidor.
	-- El click solamente cambia su estado de protegido; no elimina la fila.
	for _, child in ipairs(PlayerList:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)

	for _, player in ipairs(players) do
		if player ~= LocalPlayer then
			local isProtected = ProtectedPlayers[player] == true

			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, 0, 0, 35)
			button.BackgroundColor3 = isProtected
				and Color3.fromRGB(35, 95, 60)
				or Color3.fromRGB(25, 25, 38)
			button.Text = player.DisplayName .. " (@" .. player.Name .. ")"
			button.TextColor3 = isProtected
				and Color3.fromRGB(235, 255, 240)
				or Color3.fromRGB(215, 215, 225)
			button.Font = Enum.Font.GothamSemibold
			button.TextSize = 12
			button.AutoButtonColor = false
			button.BorderSizePixel = 0
			button.Parent = PlayerList

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 7)
			corner.Parent = button

			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Color = isProtected
				and Color3.fromRGB(45, 190, 100)
				or Color3.fromRGB(45, 45, 65)
			stroke.Transparency = 0.35
			stroke.Parent = button

			local status = Instance.new("TextLabel")
			status.AnchorPoint = Vector2.new(1, 0.5)
			status.Position = UDim2.new(1, -12, 0.5, 0)
			status.Size = UDim2.new(0, 82, 0, 22)
			status.BackgroundTransparency = 1
			status.Text = isProtected and "✓ PROTECTED" or "PROTECT"
			status.TextColor3 = isProtected
				and Color3.fromRGB(80, 255, 145)
				or Color3.fromRGB(135, 135, 155)
			status.Font = Enum.Font.GothamBold
			status.TextSize = 10
			status.Parent = button

			button.MouseButton1Click:Connect(function()
				if ProtectedPlayers[player] == true then
					ProtectedPlayers[player] = nil
				else
					ProtectedPlayers[player] = true
				end
				UpdateProtectedList()
			end)
		end
	end

	task.defer(function()
		PlayerList.CanvasSize = UDim2.new(0, 0, 0, PlayerLayout.AbsoluteContentSize.Y + 4)
	end)
end

-- Automatically protect Roblox friends as soon as they are detected in the server.
for _, player in ipairs(Players:GetPlayers()) do
	AutoProtectFriend(player)
end

Players.PlayerAdded:Connect(function(player)
	-- Give Roblox a moment to finish initializing the Player object before checking friendship.
	task.spawn(function()
		task.wait(0.2)
		AutoProtectFriend(player)
		UpdateProtectedList()
	end)

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		if ESPEnabled then
			CreateESP(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	ProtectedPlayers[player] = nil
	RemoveESP(player)
	UpdateProtectedList()
end)

--// =========================================================
--// ESP CREATE
--// =========================================================

function CreateESP(player)

	if not player
	or player == LocalPlayer then
		return
	end

	if ESPData[player] then
		return
	end

	local data = {

		Name = Drawing.new("Text"),

		Distance = Drawing.new("Text"),

		Health = Drawing.new("Text"),

		Tracer = Drawing.new("Line"),

		Weapons = {},

		Highlight = Instance.new(
			"Highlight"
		)
	}

	for _, drawing in ipairs({
		data.Name,
		data.Distance,
		data.Health
	}) do

		drawing.Center = true
		drawing.Outline = true
		drawing.Font = 2
	end

	data.Name.Size = 13
	data.Distance.Size = 12
	data.Health.Size = 12

	data.Tracer.Thickness = 1
	data.Tracer.Transparency = 0.8

	data.Highlight.Name =
		"SJ_ESP_Highlight"

	data.Highlight.DepthMode =
		Enum.HighlightDepthMode.AlwaysOnTop

	data.Highlight.FillTransparency = 1
	data.Highlight.OutlineTransparency = 0

	if player.Character then
		data.Highlight.Parent = player.Character
		data.Highlight.Adornee = player.Character
	end

	ESPData[player] = data
end

--// =========================================================
--// ESP REMOVE
--// =========================================================

function RemoveESP(player)

	local data = ESPData[player]

	if not data then
		return
	end

	for _, drawing in ipairs({
		data.Name,
		data.Distance,
		data.Health,
		data.Tracer
	}) do

		if drawing then
			drawing:Remove()
		end
	end

	for _, drawing in ipairs(
		data.Weapons
	) do

		if drawing then
			drawing:Remove()
		end
	end

	if data.Highlight then
		data.Highlight:Destroy()
	end

	ESPData[player] = nil
end

--// =========================================================
--// ESP UPDATE
--// =========================================================

local function UpdateESP(player)
	local data = ESPData[player]
	if not data then
		CreateESP(player)
		data = ESPData[player]
	end
	if not data then return end

	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	local function hide2D()
		data.Name.Visible = false
		data.Distance.Visible = false
		data.Health.Visible = false
		data.Tracer.Visible = false
		for _, draw in ipairs(data.Weapons) do
			draw.Visible = false
		end
	end

	if not char or not head or not root or not humanoid or humanoid.Health <= 0 then
		hide2D()
		if data.Highlight then
			data.Highlight.Adornee = nil
			data.Highlight.Enabled = false
		end
		return
	end

	if data.Highlight then
		data.Highlight.Parent = char
		data.Highlight.Adornee = char
		data.Highlight.Enabled = ESPHighlight
	end

	if not ESPEnabled then
		hide2D()
		if data.Highlight then
			-- Target Indicator remains visible even when the normal ESP is off.
			data.Highlight.Enabled = isTarget or ESPHighlight
		end
		return
	end

	local headPos, headVisible = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
	local rootPos, rootVisible = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 2.3, 0))

	-- Highlight stays active independently of 2D screen visibility.
	local protected = ProtectedPlayers[player] == true
	local isTarget = CurrentTarget == player
	local espColor

	if protected then
		espColor = Color3.fromRGB(0, 255, 100)
	elseif isTarget then
		espColor = Color3.fromRGB(255, 0, 0)
	else
		espColor = Color3.fromRGB(255, 215, 0)
	end

	if data.Highlight then
		if isTarget then
			data.Highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
			data.Highlight.FillColor = Color3.fromRGB(255, 0, 0)
			data.Highlight.OutlineTransparency = 0
			data.Highlight.FillTransparency = 0
		else
			data.Highlight.OutlineColor = espColor
			data.Highlight.FillColor = espColor
			data.Highlight.OutlineTransparency = 0
			data.Highlight.FillTransparency = 1
		end
	end

	if not headVisible or not rootVisible or headPos.Z < 0 or rootPos.Z < 0 then
		hide2D()
		return
	end

	local height = math.abs(headPos.Y - rootPos.Y)
	local width = height / 2
	local x = rootPos.X - width / 2
	local y = headPos.Y

	local anchorX = x + width + 6
	local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local distanceFromPlayer = localRoot and (localRoot.Position - root.Position).Magnitude or 0
	local anchorY = distanceFromPlayer > 25 and y - 24.5 or y - 12

	-- NAME: same positioning/structure as the supplied ESP.
	if ESPName then
		data.Name.Text = player.Name
		data.Name.Position = Vector2.new(anchorX, anchorY)
		data.Name.Color = espColor
		data.Name.Visible = true
	else
		data.Name.Visible = false
	end

	-- DISTANCE
	if ESPDistance and localRoot then
		data.Distance.Text = math.floor(distanceFromPlayer) .. "m"
		data.Distance.Position = Vector2.new(anchorX, anchorY + 12)
		data.Distance.Color = Color3.fromRGB(180, 180, 180)
		data.Distance.Visible = true
	else
		data.Distance.Visible = false
	end

	-- HEALTH
	if ESPHealth then
		local percent = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		data.Health.Text = math.floor(math.max(0, humanoid.Health)) .. "/" .. math.floor(humanoid.MaxHealth)
		data.Health.Position = Vector2.new(anchorX, anchorY + 24)
		data.Health.Color = Color3.fromRGB(255 * (1 - percent), 255 * percent, 0)
		data.Health.Visible = true
	else
		data.Health.Visible = false
	end

	-- WEAPON ESP: exact layout/rendition style from the supplied ESP.
	for _, draw in ipairs(data.Weapons) do
		draw.Visible = false
	end

	if ESPWeapon then
		local weapons = GetWeapons(player)

		for i, weapon in ipairs(weapons) do
			if not data.Weapons[i] then
				local txt = Drawing.new("Text")
				txt.Size = 13.75
				txt.Center = true
				txt.Outline = true
				txt.Font = 2
				data.Weapons[i] = txt
			end

			local draw = data.Weapons[i]
			draw.Text = "[" .. tostring(weapon.Rarity) .. "] " .. tostring(weapon.Name)
			draw.Color = RarityColors[weapon.Rarity] or Color3.new(1, 1, 1)
			draw.Position = Vector2.new(x + width / 2, y + height + 6 + ((i - 1) * 12))
			draw.Visible = true
		end
	end

	-- TRACER
	if ESPTracer then
		data.Tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
		data.Tracer.To = Vector2.new(headPos.X, headPos.Y)
		data.Tracer.Color = espColor
		data.Tracer.Visible = true
	else
		data.Tracer.Visible = false
	end
end

--// =========================================================
--// AIMBOT RPG TARGET
--// =========================================================

local function GetRPGAimPoint(character)
    if not character then return nil end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return nil end

    -- Keep movement prediction, but aim at the ground below the predicted X/Z.
    local velocity = root.AssemblyLinearVelocity or root.Velocity
    local predicted = root.Position + (velocity * RPGPrediction)

    local rayOrigin = predicted + Vector3.new(0, 6, 0)
    local rayDirection = Vector3.new(0, -500, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}

    local result = workspace:Raycast(rayOrigin, rayDirection, params)
    if result then
        return result.Position
    end

    -- Fallback if the map has no surface below the predicted position.
    return Vector3.new(predicted.X, predicted.Y - 3, predicted.Z)
end

local function FindRPGTarget()
    local closest
    local closestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not ProtectedPlayers[player] then
            local character = player.Character
            local point = GetRPGAimPoint(character)
            if point then
                local screen, onScreen = Camera:WorldToViewportPoint(point)
                if onScreen then
                    local distance = (Vector2.new(screen.X, screen.Y) - (Camera.ViewportSize / 2)).Magnitude
                    if distance < closestDistance then
                        local visible = true
                        if Wallcheck then
                            local params = RaycastParams.new()
                            params.FilterType = Enum.RaycastFilterType.Blacklist
                            params.FilterDescendantsInstances = {LocalPlayer.Character, character}
                            local result = workspace:Raycast(Camera.CFrame.Position, point - Camera.CFrame.Position, params)
                            visible = result == nil
                        end
                        if visible then
                            closest = player
                            closestDistance = distance
                        end
                    end
                end
            end
        end
    end

    return closest
end

--// =========================================================
--// AIMBOT TARGET PART
--// =========================================================

local function GetTargetPart(character)
	if not character then return nil end
	local selectedPart = AimPart
	if AimPartSwitchEnabled then
		selectedPart = AimSwitchState and AimPartSwitchB or AimPartSwitchA
	end
	local part = character:FindFirstChild(selectedPart)
	if part then return part end
	if selectedPart == "RightUpperArm" then
		part = character:FindFirstChild("Right Arm")
	elseif selectedPart == "LeftUpperArm" then
		part = character:FindFirstChild("Left Arm")
	end
	return part or character:FindFirstChild("Head") or character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
end

--// =========================================================
--// WALLCHECK
--// =========================================================

local function VisibleFromCamera(part)

	if not part then
		return false
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Blacklist

	params.FilterDescendantsInstances = {
		LocalPlayer.Character,
		part.Parent
	}

	local origin =
		Camera.CFrame.Position

	local direction =
		part.Position - origin

	local result =
		workspace:Raycast(
			origin,
			direction,
			params
		)

	return result == nil
end

--// =========================================================
--// FIND AIM TARGET
--// =========================================================

local function FindTarget()

	local closest
	local closestDistance =
		math.huge

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if player ~= LocalPlayer
		and not ProtectedPlayers[player] then

			local character =
				player.Character

			if character then

				local humanoid =
					character:FindFirstChildOfClass(
						"Humanoid"
					)

				if humanoid
				and humanoid.Health > 0 then

					local part =
						GetTargetPart(
							character
						)

					if part then

						local screen,
							onScreen =
							Camera:WorldToViewportPoint(
								part.Position
							)

						if onScreen then

							local distance =
								(
									Vector2.new(
										screen.X,
										screen.Y
									)
									- (
										Camera.ViewportSize
										/ 2
									)
								).Magnitude

							if distance
							<= AimbotFOV
							and distance
							< closestDistance then

								if not Wallcheck
								or VisibleFromCamera(
									part
								) then

									closest =
										player

									closestDistance =
										distance
								end
							end
						end
					end
				end
			end
		end
	end

	return closest
end

--// =========================================================
--// AIMBOT
--// =========================================================

local FOVCircle =
	Drawing.new("Circle")

FOVCircle.Thickness = 2
FOVCircle.Filled = false
FOVCircle.Transparency = 0.65
FOVCircle.Color =
	Color3.fromRGB(
		255,
		215,
		0
	)

RunService.RenderStepped:Connect(
	function()

		FOVCircle.Position =
			Camera.ViewportSize / 2

		FOVCircle.Radius =
			AimbotFOV

		FOVCircle.Visible =
			AimbotEnabled

		CurrentTarget = nil

		if not AimbotEnabled or SpectatorEnabled then
			return
		end

		local target =
			FindTarget()

		CurrentTarget =
			target

		if AimResetOnTargetChange and target ~= LastSwitchTarget then
			AimSwitchState = false
			LastSwitchTarget = target
		end

		if not target
		or not target.Character then
			return
		end

		local part =
			GetTargetPart(
				target.Character
			)

		if not part then
			return
		end

		local current =
			Camera.CFrame

		local desired =
			CFrame.new(
				current.Position,
				part.Position
			)

		local alpha =
			math.clamp(
				1 / math.max(AimbotSmoothness, 1),
				0.02,
				1
			)

		Camera.CFrame =
			current:Lerp(
				desired,
				alpha
			)
	end
)

--// =========================================================
--// AIM PART SWITCH - SHOT DETECTION
--// =========================================================

local function TriggerAimPartSwitch()
	if not AimPartSwitchEnabled or not AimSwitchOnShot then return end
	local now = tick()
	if now - LastShotTime < ShotDebounce then return end
	LastShotTime = now
	if AimPartSwitchMode == "Alternate" then
		AimSwitchState = not AimSwitchState
	else
		AimSwitchState = (math.random(0, 1) == 1)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		TriggerAimPartSwitch()
	end
end)

--// =========================================================
--// AIMBOT RPG LOOP
--// =========================================================

RunService.RenderStepped:Connect(function()
    if not RPGAimEnabled or SpectatorEnabled then return end

    local target = FindRPGTarget()
    if not target or not target.Character then return end

    local point = GetRPGAimPoint(target.Character)
    if not point then return end

    local current = Camera.CFrame
    local desired = CFrame.new(current.Position, point)
    local alpha = math.clamp(1 / math.max(RPGSmoothness, 1), 0.01, 1)
    Camera.CFrame = current:Lerp(desired, alpha)
end)

--// =========================================================
--// RPG KEYBIND
--// =========================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if WaitingForRPGBind then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            RPGBind = input.KeyCode
            WaitingForRPGBind = false
            RPGKeyButton.Text = "RPG Keybind: " .. RPGBind.Name
            RPGKeyButton.TextColor3 = Color3.fromRGB(255, 215, 0)
            return
        end
    end

    if not processed and input.KeyCode == RPGBind then
        RPGAimEnabled = not RPGAimEnabled

        if RPGAimToggleButton then
            RPGAimToggleButton.Text = "Aimbot RPG    " .. (RPGAimEnabled and "ON" or "OFF")
            TweenService:Create(
                RPGAimToggleButton,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad),
                {
                    BackgroundColor3 = RPGAimEnabled
                        and Color3.fromRGB(25, 95, 55)
                        or Color3.fromRGB(38, 38, 52)
                }
            ):Play()
        end
    end
end)

--// =========================================================
--// AIMBOT BIND
--// =========================================================

UserInputService.InputBegan:Connect(
	function(input, processed)

		if WaitingForBind then

			if input.UserInputType ==
				Enum.UserInputType.Keyboard then

				AimbotBind =
					input.KeyCode

				WaitingForBind = false

				BindButton.Text =
					AimbotBind.Name

				BindButton.TextColor3 =
					Color3.fromRGB(
						255,
						215,
						0
					)

				return
			end
		end

		if input.KeyCode ==
			AimbotBind then

			AimbotEnabled =
				not AimbotEnabled

			-- Keep the GUI state synchronized with the keybind.
			if AimbotToggleButton then
				AimbotToggleButton.Text =
					"Aimbot    " .. (AimbotEnabled and "ON" or "OFF")

				TweenService:Create(
					AimbotToggleButton,
					TweenInfo.new(0.18, Enum.EasingStyle.Quad),
					{
						BackgroundColor3 = AimbotEnabled
							and Color3.fromRGB(25, 95, 55)
							or Color3.fromRGB(38, 38, 52)
					}
				):Play()
			end
		end

		if not processed
		and input.KeyCode == GUI_KEY then

			Main.Visible =
				not Main.Visible
		end
	end
)

--// =========================================================
--// UPDATE ESP
--// =========================================================

RunService.Heartbeat:Connect(
	function()

		if ESPEnabled then

			for _, player in ipairs(
				Players:GetPlayers()
			) do

				if player ~= LocalPlayer then
					UpdateESP(player)
				end
			end

		else

			for player in pairs(
				ESPData
			) do

				RemoveESP(player)
			end
		end
	end
)

--// =========================================================
--// DRAG (PC + TOUCH)
--// =========================================================

local dragging = false
local dragStart
local startPosition

local function StartDrag(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = Main.Position
	end
end

Header.InputBegan:Connect(function(input)
	StartDrag(input)
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart

		Main.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

--// =========================================================
--// RGB ANIMATION
--// =========================================================

local RGBTime = 0

RunService.RenderStepped:Connect(
	function(dt)

		RGBTime += dt * 0.18

		local function RGB(offset)

			return Color3.fromHSV(
				(RGBTime + offset) % 1,
				0.9,
				1
			)
		end

		local C1 = RGB(0)
		local C2 = RGB(0.33)

		MainStroke.Color = C1
		AuraStroke.Color = C2

		Title.TextColor3 = C1
	end
)

--// =========================================================
--// START
--// =========================================================

UpdateProtectedList()

print("⚡ SJ IA SCRIPT V1.12 LOADED")
