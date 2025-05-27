local TweenService = game:GetService("TweenService")

local function CreateRounded(instance, radius)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = instance
end

local function LoadExternalScript(url)
	local success, result = pcall(function()
		return loadstring(game:HttpGet(url))()
	end)
	if not success then
		warn("Failed to load script from " .. url .. ": " .. tostring(result))
	end
	return success
end

local Update = {}
function Update:StartLoad(scriptUrl)
	local Loader = Instance.new("ScreenGui")
	Loader.Parent = game.CoreGui
	Loader.ZIndexBehavior = Enum.ZIndexBehavior.Global
	Loader.DisplayOrder = 2147483647
	Loader.IgnoreGuiInset = true

	local LoaderFrame = Instance.new("Frame")
	LoaderFrame.Name = "LoaderFrame"
	LoaderFrame.Parent = Loader
	LoaderFrame.ClipsDescendants = true
	LoaderFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 5)
	LoaderFrame.BackgroundTransparency = 0
	LoaderFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	LoaderFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	LoaderFrame.Size = UDim2.new(0.1, 0, 0.1, 0)
	LoaderFrame.BorderSizePixel = 0
	LoaderFrame.ZIndex = 100000

	local MainLoaderFrame = Instance.new("Frame")
	MainLoaderFrame.Name = "MainLoaderFrame"
	MainLoaderFrame.Parent = LoaderFrame
	MainLoaderFrame.ClipsDescendants = true
	MainLoaderFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 5)
	MainLoaderFrame.BackgroundTransparency = 0
	MainLoaderFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	MainLoaderFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	MainLoaderFrame.Size = UDim2.new(0.5, 0, 0.5, 0)
	MainLoaderFrame.BorderSizePixel = 0
	MainLoaderFrame.ZIndex = 100001

	local TitleLoader = Instance.new("TextLabel")
	TitleLoader.Parent = MainLoaderFrame
	TitleLoader.Text = "DuongApi"
	TitleLoader.Font = Enum.Font.FredokaOne
	TitleLoader.TextSize = 50
	TitleLoader.TextColor3 = Color3.fromRGB(255, 255, 255)
	TitleLoader.BackgroundTransparency = 1
	TitleLoader.AnchorPoint = Vector2.new(0.5, 0.5)
	TitleLoader.Position = UDim2.new(0.5, 0, 0.3, 0) -- Cùng vị trí với Door
	TitleLoader.Size = UDim2.new(0.6, 0, 0.2, 0)
	TitleLoader.TextTransparency = 1
	TitleLoader.ZIndex = 100003

	local DoorLabel = Instance.new("TextLabel")
	DoorLabel.Parent = MainLoaderFrame
	DoorLabel.Text = "Door"
	DoorLabel.Font = Enum.Font.FredokaOne
	DoorLabel.TextSize = 50
	DoorLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	DoorLabel.BackgroundTransparency = 1
	DoorLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	DoorLabel.Position = UDim2.new(0.5, 0, 0.3, 0) -- Cùng vị trí với DuongApi
	DoorLabel.Size = UDim2.new(0.6, 0, 0.2, 0)
	DoorLabel.TextTransparency = 1
	DoorLabel.ZIndex = 100003

	local DescriptionLoader = Instance.new("TextLabel")
	DescriptionLoader.Parent = MainLoaderFrame
	DescriptionLoader.Text = "Đang tải.."
	DescriptionLoader.Font = Enum.Font.Gotham
	DescriptionLoader.TextSize = 15
	DescriptionLoader.TextColor3 = Color3.fromRGB(255, 255, 255)
	DescriptionLoader.BackgroundTransparency = 1
	DescriptionLoader.AnchorPoint = Vector2.new(0.5, 0.5)
	DescriptionLoader.Position = UDim2.new(0.5, 0, 0.6, 0)
	DescriptionLoader.Size = UDim2.new(0.8, 0, 0.2, 0)
	DescriptionLoader.TextTransparency = 0
	DescriptionLoader.ZIndex = 100002

	local LoadingBarBackground = Instance.new("Frame")
	LoadingBarBackground.Parent = MainLoaderFrame
	LoadingBarBackground.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	LoadingBarBackground.AnchorPoint = Vector2.new(0.5, 0.5)
	LoadingBarBackground.Position = UDim2.new(0.5, 0, 0.7, 0)
	LoadingBarBackground.Size = UDim2.new(0.7, 0, 0.05, 0)
	LoadingBarBackground.ClipsDescendants = true
	LoadingBarBackground.BorderSizePixel = 0
	LoadingBarBackground.ZIndex = 100002

	local LoadingBar = Instance.new("Frame")
	LoadingBar.Parent = LoadingBarBackground
	LoadingBar.Size = UDim2.new(0, 0, 1, 0)
	LoadingBar.ZIndex = 100003

	CreateRounded(LoadingBarBackground, 20)
	CreateRounded(LoadingBar, 20)

	local function rainbowColor(t)
		local frequency = 1
		local r = math.sin(frequency * t + 0) * 127 + 128
		local g = math.sin(frequency * t + 2) * 127 + 128
		local b = math.sin(frequency * t + 4) * 127 + 128
		return Color3.fromRGB(r, g, b)
	end

	-- Hiệu ứng cầu vồng cho thanh tiến trình và phát sáng chữ DuongApi
	spawn(function()
		while LoadingBar.Parent do
			for i = 0, 2 * math.pi, 0.1 do
				LoadingBar.BackgroundColor3 = rainbowColor(i)
				local glow = Instance.new("UIGlow")
				glow.Parent = TitleLoader
				glow.Intensity = 0.5
				glow.Spread = UDim.new(0, 10)
				glow.Color = rainbowColor(i)
				wait(0.1)
				glow:Destroy()
			end
		end
	end)

	-- Hiệu ứng luân phiên chữ DuongApi và Door (2 giây mỗi chu kỳ)
	spawn(function()
		while TitleLoader.Parent do
			local fadeInDuong = TweenService:Create(TitleLoader, TweenInfo.new(1, Enum.EasingStyle.Linear), {TextTransparency = 0})
			local fadeOutDuong = TweenService:Create(TitleLoader, TweenInfo.new(1, Enum.EasingStyle.Linear), {TextTransparency = 1})
			local fadeInDoor = TweenService:Create(DoorLabel, TweenInfo.new(1, Enum.EasingStyle.Linear), {TextTransparency = 0})
			local fadeOutDoor = TweenService:Create(DoorLabel, TweenInfo.new(1, Enum.EasingStyle.Linear), {TextTransparency = 1})

			fadeInDuong:Play()
			fadeInDuong.Completed:Wait()
			fadeOutDuong:Play()
			fadeOutDuong.Completed:Wait()
			fadeInDoor:Play()
			fadeInDoor.Completed:Wait()
			fadeOutDoor:Play()
			fadeOutDoor.Completed:Wait()
		end
	end)

	local tweenInfoZoomIn = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenZoomIn = TweenService:Create(LoaderFrame, tweenInfoZoomIn, {
		Size = UDim2.new(1.5, 0, 1.5, 0)
	})

	local barTweenInfoInstant = TweenInfo.new(0, Enum.EasingStyle.Linear) -- Tải thẳng tức thì
	local barTweenPart1 = TweenService:Create(LoadingBar, barTweenInfoInstant, {
		Size = UDim2.new(0.25, 0, 1, 0)
	})
	local barTweenPart2 = TweenService:Create(LoadingBar, barTweenInfoInstant, {
		Size = UDim2.new(0.6, 0, 1, 0)
	})
	local barTweenPart3 = TweenService:Create(LoadingBar, barTweenInfoInstant, {
		Size = UDim2.new(0.9, 0, 1, 0)
	})
	local barTweenInfoPart4 = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local barTweenPart4 = TweenService:Create(LoadingBar, barTweenInfoPart4, {
		Size = UDim2.new(1, 0, 1, 0)
	})

	local tweenInfoZoomOut = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tweenZoomOut = TweenService:Create(LoaderFrame, tweenInfoZoomOut, {
		Size = UDim2.new(0.1, 0, 0.1, 0)
	})

	local dotCount = 0
	local running = true
	spawn(function()
		while running do
			dotCount = (dotCount + 1) % 4
			local dots = string.rep(".", dotCount)
			DescriptionLoader.Text = "Vui lòng đợi" .. dots
			wait(0.5)
		end
	end)

	tweenZoomIn:Play()
	barTweenPart1:Play()
	barTweenPart1.Completed:Connect(function()
		wait(2) -- Giai đoạn 1: 1 giây
		barTweenPart2:Play()
		barTweenPart2.Completed:Connect(function()
			wait(3) -- Giai đoạn 2: 3 giây
			barTweenPart3:Play()
			local scriptLoaded
			spawn(function()
				scriptLoaded = LoadExternalScript(scriptUrl) -- Tải script ở 90%
			end)
			barTweenPart3.Completed:Connect(function()
				barTweenPart4:Play()
				barTweenPart4.Completed:Connect(function()
					running = false
					DescriptionLoader.Text = scriptLoaded and "Đã tải thành công!" or "Đã tải thành công, chơi vui vẻ :D!"
					wait(scriptLoaded and 0.5 or 1)
					tweenZoomOut:Play()
					tweenZoomOut.Completed:Connect(function()
						Loader:Destroy()
					end)
				end)
			end)
		end)
	end)
end

Update:StartLoad("https://raw.githubusercontent.com/laitung1122/Score.M4/refs/heads/main/Script.luau")
