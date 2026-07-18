local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local TeleportService = game:GetService("TeleportService")

local cloneref = (cloneref or clonereference or function(instance) return instance end)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = cloneref(game:GetService("HttpService"))

local WindUI
do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)
    if ok then
        WindUI = result
    else
        if cloneref(game:GetService("RunService")):IsStudio() then
            WindUI = require(cloneref(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init")))
        else
            WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end
    end
end

-- ================= 参数 =================
local ENTER_INTERVAL = 0.08
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then return end

local masterEnabled = false
local isAnchored = false
local enterEnabled = false
local characterAddedConn = nil

-- 玩家增强
local noclipEnabled = false
local noclipConnection = nil
local speedValue = 16
local jumpValue = 50
local fovValue = 70

-- 飞行
local flying = false
local flyConnection = nil
local flyKeyDown = nil
local flyKeyUp = nil
local flySpeed = 20
local control = { W = 0, S = 0, A = 0, D = 0, Q = 0, E = 0 }

-- ESP
local espEnabled = false
local espMode = "ESP"
local espTransparency = 0.3
local locateTargetName = nil
local espData = {}

-- ================= 辅助函数 =================
local function setAnchoredFunc(state)
    isAnchored = state
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.Anchored = state
    end
    if characterAddedConn then characterAddedConn:Disconnect() end
    if state then
        characterAddedConn = player.CharacterAdded:Connect(function(newChar)
            local hrp = newChar:WaitForChild("HumanoidRootPart")
            if hrp then hrp.Anchored = true end
        end)
    else
        characterAddedConn = nil
    end
end

local function pressF9()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F9, false, nil)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F9, false, nil)
end

local function executeRemoteScript()
    local s, e = pcall(function()
        loadstring(game:HttpGet("https://rawscripts.net/raw/Fisch-Blackhub-Best-Undetected-Script-53591"))()
    end)
    if s then WindUI:Notify({ Title = "成功", Content = "脚本已加载", Icon = "check", Duration = 3 })
    else WindUI:Notify({ Title = "失败", Content = tostring(e), Icon = "x", Duration = 5 }) end
end

-- ================= 服务器信息模块 =================
local function formatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    if hours > 0 then return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then return string.format("%dm %ds", minutes, secs)
    else return string.format("%ds", secs) end
end

local function getServerInfo()
    local placeId = game.PlaceId
    local gameId = game.GameId
    local jobId = game.JobId
    local productInfo = MarketplaceService:GetProductInfo(placeId)
    local creatorType = game.CreatorType
    local creatorId = game.CreatorId
    local creatorName = ""
    if creatorType == Enum.CreatorType.User then
        creatorName = "User " .. creatorId
    elseif creatorType == Enum.CreatorType.Group then
        local groupInfo = GroupService:GetGroupInfoAsync(creatorId)
        creatorName = string.format("Group '%s' (Owner ID: %d)", groupInfo.Name, groupInfo.Owner.Id)
        creatorId = groupInfo.Owner.Id
    end
    local runTime = Workspace.DistributedGameTime
    local runTimeFormatted = formatTime(runTime)
    local currentPlayers = #Players:GetPlayers()
    local maxPlayers = Players.MaxPlayers
    local playerName = player.Name
    local displayName = player.DisplayName
    local userId = player.UserId
    local ping = math.round(player:GetNetworkPing() * 1000) .. "ms"

    return {
        PlaceName = productInfo.Name,
        PlaceId = placeId,
        GameId = gameId,
        JobId = jobId,
        CreatorName = creatorName,
        CreatorId = creatorId,
        RunTimeFormatted = runTimeFormatted,
        CurrentPlayers = currentPlayers,
        MaxPlayers = maxPlayers,
        PlayerName = playerName,
        PlayerDisplayName = displayName,
        PlayerId = userId,
        Ping = ping,
    }
end

local function copyToClipboard(text)
    if setclipboard then setclipboard(text); return true
    else warn("剪贴板不可用"); return false end
end

-- ================= ESP =================
local function getRoot(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function round(num) return math.round(num * 10) / 10 end

local function clearESPForPlayer(plr)
    local data = espData[plr]
    if data then
        if data.folder then data.folder:Destroy() end
        if data.connections then for _, conn in pairs(data.connections) do conn:Disconnect() end end
        espData[plr] = nil
    end
end

local function createESP(plr, mode, transparency)
    local char = plr.Character
    if not char then return nil end
    local root = getRoot(char)
    if not root then return nil end
    local folder = Instance.new("Folder")
    folder.Name = plr.Name .. "_ESP"
    folder.Parent = CoreGui
    for _, part in pairs(char:GetChildren()) do
        if part:IsA("BasePart") then
            local box = Instance.new("BoxHandleAdornment")
            box.Adornee = part; box.AlwaysOnTop = true; box.ZIndex = 10
            box.Size = part.Size; box.Transparency = transparency; box.Color = plr.TeamColor
            box.Parent = folder
        end
    end
    if mode == "Chams" then return folder end
    local head = char:FindFirstChild("Head")
    if not head then return folder end
    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = head; billboard.Size = UDim2.new(0,100,0,150)
    billboard.StudsOffset = Vector3.new(0,1,0); billboard.AlwaysOnTop = true; billboard.Parent = folder
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1; label.Size = UDim2.new(0,100,0,100)
    label.Font = Enum.Font.SourceSansSemibold; label.TextSize = 20; label.TextColor3 = Color3.new(1,1,1)
    label.TextStrokeTransparency = 0; label.Parent = billboard
    local updateConnection
    updateConnection = RunService.RenderStepped:Connect(function()
        if not folder.Parent then updateConnection:Disconnect() return end
        if plr.Character and getRoot(plr.Character) and player.Character and getRoot(player.Character) then
            local dist = math.floor((getRoot(player.Character).Position - getRoot(plr.Character).Position).magnitude)
            local humanoid = plr.Character:FindFirstChildWhichIsA("Humanoid")
            local health = humanoid and round(humanoid.Health) or "?"
            label.Text = string.format("Name: %s | Health: %s | Studs: %d", plr.Name, health, dist)
        end
    end)
    return folder, updateConnection
end

local function updatePlayerESP(plr)
    if plr == player then return end
    clearESPForPlayer(plr)
    if not espEnabled then return end
    if espMode == "Locate" and plr.Name ~= locateTargetName then return end
    local folder, updateConn = createESP(plr, espMode, espTransparency)
    if folder then
        local connections = {updateConn}
        table.insert(connections, plr.CharacterAdded:Connect(function() updatePlayerESP(plr) end))
        table.insert(connections, plr:GetPropertyChangedSignal("TeamColor"):Connect(function() updatePlayerESP(plr) end))
        espData[plr] = {folder = folder, connections = connections}
    end
end

local function refreshAllESP()
    for plr,_ in pairs(espData) do clearESPForPlayer(plr) end
    espData = {}
    if not espEnabled then return end
    for _,plr in pairs(Players:GetPlayers()) do if plr ~= player then updatePlayerESP(plr) end end
end

local function espStop()
    espEnabled = false
    for plr,_ in pairs(espData) do clearESPForPlayer(plr) end
    espData = {}
end

Players.PlayerAdded:Connect(function(plr) if plr~=player then task.wait(0.5); updatePlayerESP(plr) end end)
Players.PlayerRemoving:Connect(clearESPForPlayer)
player.CharacterAdded:Connect(refreshAllESP)

-- ================= 飞行 =================
local function startFlyPC()
    if flying then return end
    local char = player.Character; local humanoid = char and char:FindFirstChildOfClass("Humanoid"); local root = getRoot(char)
    if not humanoid or not root then return end
    local bg = Instance.new("BodyGyro"); bg.P = 9e4; bg.MaxTorque = Vector3.new(9e9,9e9,9e9); bg.CFrame = workspace.CurrentCamera.CFrame; bg.Parent = root
    local bv = Instance.new("BodyVelocity"); bv.MaxForce = Vector3.new(9e9,9e9,9e9); bv.Velocity = Vector3.new(); bv.Parent = root
    humanoid.PlatformStand = true; flying = true
    flyKeyDown = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.W then control.W=1 elseif input.KeyCode == Enum.KeyCode.S then control.S=-1
        elseif input.KeyCode == Enum.KeyCode.A then control.A=-1 elseif input.KeyCode == Enum.KeyCode.D then control.D=1
        elseif input.KeyCode == Enum.KeyCode.E then control.E=1 elseif input.KeyCode == Enum.KeyCode.Q then control.Q=-1 end
        workspace.CurrentCamera.CameraType = Enum.CameraType.Track
    end)
    flyKeyUp = UserInputService.InputEnded:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.W then control.W=0 elseif input.KeyCode == Enum.KeyCode.S then control.S=0
        elseif input.KeyCode == Enum.KeyCode.A then control.A=0 elseif input.KeyCode == Enum.KeyCode.D then control.D=0
        elseif input.KeyCode == Enum.KeyCode.E then control.E=0 elseif input.KeyCode == Enum.KeyCode.Q then control.Q=0 end
    end)
    flyConnection = RunService.RenderStepped:Connect(function()
        if not flying then return end
        local char = player.Character; local root = getRoot(char)
        if not root or not root.Parent then stopFly() return end
        local bv = root:FindFirstChildOfClass("BodyVelocity"); local bg = root:FindFirstChildOfClass("BodyGyro")
        if not bv then stopFly() return end
        local cam = workspace.CurrentCamera; local moveDir = Vector3.new(0,0,0)
        if control.W~=0 or control.S~=0 then moveDir += cam.CFrame.LookVector*(control.W+control.S) end
        if control.A~=0 or control.D~=0 then moveDir += cam.CFrame.RightVector*(control.A+control.D) end
        moveDir += Vector3.new(0, control.E+control.Q, 0)
        if moveDir.Magnitude>0 then moveDir = moveDir.Unit*flySpeed*2 end
        bv.Velocity = moveDir; if bg then bg.CFrame = cam.CFrame end
    end)
end

local function startFlyMobile()
    if flying then return end
    local char = player.Character; local humanoid = char and char:FindFirstChildOfClass("Humanoid"); local root = getRoot(char)
    if not humanoid or not root then return end
    local controlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
    local bg = Instance.new("BodyGyro"); bg.P=9e4; bg.MaxTorque=Vector3.new(9e9,9e9,9e9); bg.CFrame=workspace.CurrentCamera.CFrame; bg.Parent=root
    local bv = Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(9e9,9e9,9e9); bv.Velocity=Vector3.new(); bv.Parent=root
    humanoid.PlatformStand=true; flying=true
    flyConnection = RunService.RenderStepped:Connect(function()
        if not flying then return end
        local char=player.Character; local root=getRoot(char)
        if not root or not root.Parent then stopFly() return end
        local bv=root:FindFirstChildOfClass("BodyVelocity"); local bg=root:FindFirstChildOfClass("BodyGyro")
        if not bv then stopFly() return end
        local cam=workspace.CurrentCamera; local moveDir=controlModule:GetMoveVector(); local vel=Vector3.new()
        if moveDir.X~=0 then vel+=cam.RightVector*moveDir.X end
        if moveDir.Z~=0 then vel-=cam.LookVector*moveDir.Z end
        if vel.Magnitude>0 then vel=vel.Unit*flySpeed*2 end
        bv.Velocity=vel; if bg then bg.CFrame=cam.CFrame end
    end)
end

local function startFly(speed)
    flySpeed = speed or flySpeed; if flying then return end
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then startFlyMobile() else startFlyPC() end
end

function stopFly()
    if flyConnection then flyConnection:Disconnect(); flyConnection=nil end
    if flyKeyDown then flyKeyDown:Disconnect(); flyKeyDown=nil end
    if flyKeyUp then flyKeyUp:Disconnect(); flyKeyUp=nil end
    if flying then
        local char=player.Character; local root=getRoot(char)
        if root then for _,obj in pairs(root:GetChildren()) do if obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") then obj:Destroy() end end end
        if char then local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.PlatformStand=false end end
        flying=false
    end
    control = {W=0,S=0,A=0,D=0,Q=0,E=0}
end

-- ================= 其他增强 =================
local function setWalkSpeed(v) local char=player.Character; if char then local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed=v end end end
local function setJumpPower(v) local char=player.Character; if char then local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.JumpPower=v end end end
local function setFieldOfView(v) local cam=workspace.CurrentCamera; if cam then cam.FieldOfView=v end end
local function enableNoclip(char) for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end end end
local function setNoclip(state)
    noclipEnabled=state; if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end
    if state then if player.Character then enableNoclip(player.Character) end; noclipConnection=player.CharacterAdded:Connect(function(c) task.wait(0.1); enableNoclip(c) end) end
end

player.CharacterAdded:Connect(function(c)
    if isAnchored then local hrp=c:WaitForChild("HumanoidRootPart"); if hrp then hrp.Anchored=true end end
    if noclipEnabled then task.wait(0.1); enableNoclip(c) end
    if flying then stopFly(); task.wait(0.5); startFly(flySpeed) end
end)

-- ================= UI =================
local Window = WindUI:CreateWindow({
    Title = "XiaoBai 功能脚本 [ 开发中 ]",
    Folder = "MultiHelper",
    Icon = "solar:settings-bold-duotone",
    NewElements = true,
    HideSearchBar = true,
    OpenButton = {
        Title = " XiaoBai ",
        CornerRadius = UDim.new(1,0),
        StrokeThickness = 3,
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Scale = 0.5,
        Color = ColorSequence.new(Color3.fromHex("#30FF6A"), Color3.fromHex("#e7ff2f")),
    },
    Topbar = { Height = 44, ButtonsType = "Mac" },
})
pcall(function() Window:SetCloseButtonText("关闭窗口") end)

-- ================= Fisch =================
local FischTab = Window:Tab({ Title = "Fisch", Icon = "solar:fishing-bold", IconColor = Color3.fromHex("#30A0FF"), IconShape = "Square", Border = true })
local FischSection = FischTab:Section({ Title = "Fisch 脚本控制", Box = true, BoxBorder = true, Opened = true })
local EnterToggle = FischSection:Toggle({ Title = "自动抖动", Desc = "间隔 ".. ENTER_INTERVAL .." 秒自动抖动", Callback = function(s) enterEnabled = s end })
FischSection:Space()
FischSection:Button({ Title = "激活 BlackHub", Icon = "terminal", Color = Color3.fromHex("#9B30FF"), Justify = "Center", Callback = executeRemoteScript })

local NameSection = FischTab:Section({ Title = "名字控制", Box = true, BoxBorder = true, Opened = true })
NameSection:Button({ Title = "改为「匿名状态」", Icon = "edit", Color = Color3.fromHex("#FF6B35"), Justify = "Center", Callback = function()
    for _,plr in pairs(Players:GetPlayers()) do
        local char=plr.Character; if not char then continue end
        local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
        local ub=hrp:FindFirstChild("user")
        if ub and ub:IsA("BillboardGui") then local ut=ub:FindFirstChild("user"); if ut and ut:IsA("TextLabel") then ut.Text="脚本小白匿名" end end
    end
end})
NameSection:Space()
NameSection:Button({ Title = "恢复原始名字", Icon = "refresh-cw", Color = Color3.fromHex("#30A0FF"), Justify = "Center", Callback = function()
    for _,plr in pairs(Players:GetPlayers()) do
        local char=plr.Character; if not char then continue end
        local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
        local ub=hrp:FindFirstChild("user")
        if ub and ub:IsA("BillboardGui") then local ut=ub:FindFirstChild("user"); if ut and ut:IsA("TextLabel") then ut.Text=plr.Name end end
    end
end})
NameSection:Space()
NameSection:Toggle({ Title = "隐藏名字", Desc = "隐藏所有玩家头顶名字", Callback = function(s)
    for _,plr in pairs(Players:GetPlayers()) do
        local char=plr.Character; if not char then continue end
        local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
        local ub=hrp:FindFirstChild("user")
        if ub and ub:IsA("BillboardGui") then ub.Enabled = not s end
    end
end})

-- ================= 玩家增强 =================
local EnhanceTab = Window:Tab({ Title = "玩家增强", Icon = "solar:user-bold", IconColor = Color3.fromHex("#10C550"), IconShape = "Square", Border = true })
local CharSection = EnhanceTab:Section({ Title = "角色控制", Box = true, BoxBorder = true, Opened = true })
local AnchorToggle = CharSection:Toggle({ Title = "角色锚固", Desc = "固定位置（重生保留）", Callback = function(s) setAnchoredFunc(s) end })
CharSection:Space()
local NoclipToggle = CharSection:Toggle({ Title = "NoClip 穿墙", Desc = "关闭角色碰撞", Callback = function(s) setNoclip(s) end })

local FlySection = EnhanceTab:Section({ Title = "飞行控制", Box = true, BoxBorder = true, Opened = true })
local FlyToggle = FlySection:Toggle({ Title = "启用飞行", Desc = " [ 仅限电脑使用 ] ", Callback = function(s) if s then startFly(flySpeed) else stopFly() end end })
FlySection:Space()
FlySection:Slider({ Title = "飞行速度", Desc = "1-500", IsTooltip=true, IsTextbox=true, Step=1, Value={Min=1,Max=500,Default=flySpeed}, Callback=function(v) flySpeed=v end })

local AttrSection = EnhanceTab:Section({ Title = "属性调整", Box = true, BoxBorder = true, Opened = true })
AttrSection:Slider({ Title="移动速度", IsTooltip=true, IsTextbox=true, Step=1, Value={Min=16,Max=200,Default=16}, Callback=function(v) setWalkSpeed(v) end })
AttrSection:Space()
AttrSection:Slider({ Title="跳跃高度", IsTooltip=true, IsTextbox=true, Step=1, Value={Min=50,Max=300,Default=50}, Callback=function(v) setJumpPower(v) end })
AttrSection:Space()
AttrSection:Slider({ Title="最大视野", IsTooltip=true, IsTextbox=true, Step=1, Value={Min=30,Max=120,Default=70}, Callback=function(v)
    setFieldOfView(v)
    task.delay(0.6, function() WindUI:Notify({Title="视野更新",Content=v,Icon="eye",Duration=1.5}) end)
end})

local ESPSection = EnhanceTab:Section({ Title = "ESP 透视", Box = true, BoxBorder = true, Opened = true })
local ESPToggle = ESPSection:Toggle({ Title = "启用 ESP", Desc = "玩家透视", Callback = function(s) espEnabled=s; if s then refreshAllESP() else espStop() end end })
ESPSection:Space()
ESPSection:Dropdown({ Title = "显示模式", Values = {"ESP (全信息)", "Chams (高亮HitBox)", "Locate (单独追踪)"}, Value = "ESP (全信息)", Callback = function(v)
    if v=="ESP (全信息)" then espMode="ESP" elseif v=="Chams (仅边框)" then espMode="Chams" else espMode="Locate" end
    if espEnabled then refreshAllESP() end
end})
ESPSection:Space()
ESPSection:Slider({ Title = "HitBox透明调整", IsTooltip=true, IsTextbox=true, Step=0.05, Value={Min=0,Max=1,Default=espTransparency}, Callback=function(v) espTransparency=v; if espEnabled then refreshAllESP() end end })

-- ================= 快捷执行 =================
local QuickTab = Window:Tab({ Title = "快捷执行", Icon = "solar:play-circle-bold", IconColor = Color3.fromHex("#FF6B35"), IconShape = "Square", Border = true })
local QuickSection = QuickTab:Section({ Title = "脚本执行", Box = true, BoxBorder = true, Opened = true })
QuickSection:Button({ Title = "执行 Dex++", Desc = "注入 Dex++ 脚本", Icon = "terminal", Color = Color3.fromHex("#FF6B35"), Justify = "Center", Callback = function()
    loadstring(game:HttpGet("https://github.com/AZYsGithub/DexPlusPlus/releases/latest/download/out.lua"))()
end})

-- ================= 信息 =================
local InfoTab = Window:Tab({ Title = "信息", Icon = "solar:info-square-bold", IconColor = Color3.fromHex("#83889E"), IconShape = "Square", Border = true })

-- 存储所有信息按钮，用标题作为键
local infoButtons = {}

-- 创建一个信息块（Section + 内部按钮），返回按钮对象
local function createInfoButton(title, value)
    local sec = InfoTab:Section({
        Title = title,
        Box = true,
        BoxBorder = true,
        Opened = true,
    })
    local btn = sec:Button({
        Title = tostring(value),
        Desc = "点击复制",
        Icon = "copy",
        Justify = "Center",
        Callback = function()
            copyToClipboard(tostring(value))
            WindUI:Notify({ Title = "已复制", Content = title .. " 已复制", Icon = "check", Duration = 1.5 })
        end
    })
    return btn
end

-- 刷新所有信息：直接修改按钮标题
local function refreshAllInfo()
    local data = getServerInfo()
    local mappings = {
        ["地点"] = data.PlaceName,
        ["Place ID"] = data.PlaceId,
        ["Game ID"] = data.GameId,
        ["Job ID"] = data.JobId,
        ["创建者"] = data.CreatorName .. " (ID: " .. data.CreatorId .. ")",
        ["运行时间"] = data.RunTimeFormatted,
        ["玩家"] = data.CurrentPlayers .. " / " .. data.MaxPlayers,
        ["本地玩家"] = data.PlayerName .. " (" .. data.PlayerDisplayName .. ")",
        ["玩家 ID"] = data.PlayerId,
        ["延迟"] = data.Ping,
    }
    
    for title, newValue in pairs(mappings) do
        local btn = infoButtons[title]
        if btn then
            pcall(function()
                btn:SetTitle(tostring(newValue))
            end)
        end
    end
    
    WindUI:Notify({ Title = "刷新成功", Content = "服务器信息已更新", Icon = "check", Duration = 2 })
end

-- 初次创建所有信息块
do
    local data = getServerInfo()
    infoButtons["地点"] = createInfoButton("地点", data.PlaceName)
    infoButtons["Place ID"] = createInfoButton("Place ID", data.PlaceId)
    infoButtons["Game ID"] = createInfoButton("Game ID", data.GameId)
    infoButtons["Job ID"] = createInfoButton("Job ID", data.JobId)
    infoButtons["游戏开发者"] = createInfoButton("创建者", data.CreatorName .. " (ID: " .. data.CreatorId .. ")")
    infoButtons["你的加入累计时间"] = createInfoButton("时间", data.RunTimeFormatted)
    infoButtons["玩家"] = createInfoButton("玩家", data.CurrentPlayers .. " / " .. data.MaxPlayers)
    infoButtons["本地玩家"] = createInfoButton("个人信息", data.PlayerName .. " (" .. data.PlayerDisplayName .. ")")
    infoButtons[" 玩家 ID"] = createInfoButton("玩家 ID", data.PlayerId)
    infoButtons["延迟"] = createInfoButton("延迟", data.Ping)
end

-- 刷新按钮
local refreshSection = InfoTab:Section({
    Title = "操作",
    Box = true,
    BoxBorder = true,
    Opened = true,
})
refreshSection:Button({
    Title = "刷新信息",
    Icon = "refresh-cw",
    Justify = "Center",
    Color = Color3.fromHex("#305dff"),
    Callback = refreshAllInfo
})

-- 重新加入服务器
refreshSection:Space()
refreshSection:Button({
    Title = "重新加入该服务器 (ReJoin)",
    Icon = "log-in",
    Justify = "Center",
    Color = Color3.fromHex("#FF6B35"),
    Callback = function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end
})

-- 作者信息（固定内容，不变）
local AuthorSection = InfoTab:Section({
    Title = "作者信息",
    Box = true,
    BoxBorder = true,
    Opened = true,
})
AuthorSection:Button({
    Title = "复制作者 QQ: 8234967309",
    Icon = "copy",
    Justify = "Center",
    Callback = function()
        copyToClipboard("8234967309")
        WindUI:Notify({ Title = "已复制", Content = "作者 QQ 已复制", Icon = "check", Duration = 1.5 })
    end
})
AuthorSection:Space()
AuthorSection:Button({
    Title = "复制 QQ 群: 823754480",
    Icon = "copy",
    Justify = "Center",
    Callback = function()
        copyToClipboard("823754480")
        WindUI:Notify({ Title = "已复制", Content = "QQ 群号已复制", Icon = "check", Duration = 1.5 })
    end
})

-- ================= 更多操作 =================
local MoreTab = Window:Tab({ Title = "更多操作", Icon = "solar:widget-3-bold", IconColor = Color3.fromHex("#ECA201"), IconShape = "Square", Border = true })
local MainSection = MoreTab:Section({ Title = "主控制", Box = true, BoxBorder = true, Opened = true })
local MasterToggle = MainSection:Toggle({ Title = "总开关", Desc = "启用/禁用所有功能", Callback = function(s)
    masterEnabled = s
    if not s then
        stopFly() enterEnabled=false isAnchored=false noclipEnabled=false
        espStop()
        setAnchoredFunc(false) setNoclip(false)
        if EnterToggle then EnterToggle:Set(false) end
        if AnchorToggle then AnchorToggle:Set(false) end
        if NoclipToggle then NoclipToggle:Set(false) end
        if FlyToggle then FlyToggle:Set(false) end
        if ESPToggle then ESPToggle:Set(false) end
    end
end})
local ActSection = MoreTab:Section({ Title = "操作按钮", Box = true, BoxBorder = true, Opened = true })
ActSection:Button({ Title="模拟 F9", Color=Color3.fromHex("#B87814"), Justify="Center", Callback=pressF9 })
ActSection:Space()
ActSection:Button({ Title="销毁界面", Color=Color3.fromHex("#ff4830"), Justify="Center", Callback=function()
    masterEnabled=false enterEnabled=false isAnchored=false noclipEnabled=false
    stopFly() setAnchoredFunc(false) setNoclip(false) espStop()
    if characterAddedConn then characterAddedConn:Disconnect() end
    Window:Destroy()
end})

-- ================= 自动回车心跳 =================
local enterTimer = 0
RunService.Heartbeat:Connect(function(dt)
    if masterEnabled and enterEnabled then
        enterTimer += dt
        if enterTimer >= ENTER_INTERVAL then
            enterTimer -= ENTER_INTERVAL
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, nil)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, nil)
        end
    else enterTimer = 0 end
end)
