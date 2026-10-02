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
local Lighting = game:GetService("Lighting")

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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then return end

local isAnchored = false
local characterAddedConn = nil
local noclipEnabled = false
local noclipConnection = nil
local flySpeed = 20
local flying = false
local flyConnection = nil
local flyKeyDown = nil
local flyKeyUp = nil
local control = { W = 0, S = 0, A = 0, D = 0, Q = 0, E = 0 }

local stopFly

local espEnabled = false
local espMode = "ESP"
local espTransparency = 0.3
local locateTargetName = nil
local espData = {}

local trackModels = false
local trackTools = false
local trackMonsters = false
local trackRoomDoor = false
local trackTaskNPC = false
local trackedObjects = {}
local IGNORE_FOLDER = "ElevatorCollect"
local maxRenderDistance = 50

local presetColors = {
    {Name = "红色", Color = Color3.fromRGB(255, 0, 0)},
    {Name = "橙色", Color = Color3.fromRGB(255, 165, 0)},
    {Name = "黄色", Color = Color3.fromRGB(255, 255, 0)},
    {Name = "绿色", Color = Color3.fromRGB(0, 255, 0)},
    {Name = "蓝色", Color = Color3.fromRGB(0, 0, 255)},
    {Name = "紫色", Color = Color3.fromRGB(128, 0, 128)},
    {Name = "粉色", Color = Color3.fromRGB(255, 192, 203)},
    {Name = "白色", Color = Color3.fromRGB(255, 255, 255)},
}
local presetColorNames = {}
for _, p in ipairs(presetColors) do
    table.insert(presetColorNames, p.Name)
end

local colorSettings = {
    Model = "蓝色",
    Tool = "黄色",
    Monster = "红色",
    RoomDoor = "紫色",
    TaskNPC = "橙色",
}

local function getColorForCategory(category)
    local name = colorSettings[category] or "白色"
    for _, p in ipairs(presetColors) do
        if p.Name == name then
            return p.Color
        end
    end
    return Color3.new(1, 1, 1)
end

local NPC_CHINESE_MAP = {
    Gordon = "戈登",
    ["The Lost W"] = "迷失的 W",
    ["Radio Kid"] = "无线电小子",
    ["Zom. Hong"] = "僵尸洪",
    Quackingtonia = "鸭鸭镇",
    Leoo = "里奥",
    ["Dungeon Master"] = "地牢领主",
    ["Mr. G"] = "G 先生",
    Polar = "北极",
    Khoi = "科伊",
    ["The Chief"] = "首领",
    XanderGrey = "赞德·格雷",
    Babysitter = "保姆",
    Marx = "马克思",
    Spy = "间谍",
    Cupid = "丘比特",
    Exterminator = "灭绝者",
    ["Subject G"] = "实验体 G",
    Evelyn = "伊芙琳",
    Graves = "格雷夫斯",
    Sam = "山姆",
    Psionic = "灵能者",
    Nora = "诺拉",
    ["Mr. Bill"] = "比尔先生",
}

local TASK_NPC_NAMES = {}
for name, _ in pairs(NPC_CHINESE_MAP) do
    table.insert(TASK_NPC_NAMES, name)
end

local function isMonsterTopLevel(obj)
    if not obj:IsA("Model") then return false end
    local parent = obj.Parent
    if parent and parent.Name == "Monsters" and parent:IsA("Folder") then
        return true
    end
    if parent and parent:IsA("Model") and isMonsterTopLevel(parent) then
        return false
    end
    return false
end

local function getDisplayInfo(obj)
    if not (obj:IsA("Model") or obj:IsA("Tool")) then
        return nil, nil
    end

    if isMonsterTopLevel(obj) then
        return "怪物", "Monster"
    end

    local name = obj.Name

    if obj:IsA("Model") and name == "F_room_Door" then
        return "门", "RoomDoor"
    end

    if string.match(name, "^SoilMound_%d+$") then
        return "奖励洞口", "Model"
    end

    if obj:IsA("Model") and obj.Parent and obj.Parent.Name == "World" then
        local num = tonumber(name)
        if num and num >= 0 and num <= 1000 then
            return "金币", "Tool"
        end
    end

    if string.match(name, "^Cabinet_%d+$") then
        return "柜子", "Model"
    elseif string.match(name, "^OilBucket_%d+$") then
        return "油管桶", "Model"
    elseif string.match(name, "^Crate_%d+$") then
        return "箱子", "Model"
    elseif string.match(name, "^Fridge_%d+$") then
        return "冰箱", "Model"
    end

    local num = tonumber(name)
    if num and num >= 0 and num <= 1000 and obj:IsA("Tool") then
        return "道具", "Tool"
    end

    for _, npcName in ipairs(TASK_NPC_NAMES) do
        if name == npcName then
            local chineseName = NPC_CHINESE_MAP[npcName] or npcName
            return "[人质] " .. chineseName, "TaskNPC"
        end
    end

    return nil, nil
end

local function isIgnored(obj)
    local parent = obj.Parent
    while parent do
        if parent.Name == IGNORE_FOLDER then
            return true
        end
        parent = parent.Parent
    end
    return false
end

local function isInMonstersFolder(obj)
    local parent = obj.Parent
    while parent do
        if parent.Name == "Monsters" then
            return true
        end
        parent = parent.Parent
    end
    return false
end

local function getBasePart(obj)
    if obj:IsA("Tool") then
        local part = obj:FindFirstChildWhichIsA("BasePart")
        if part then return part end
        if obj:IsA("BasePart") then return obj end
    elseif obj:IsA("Model") then
        local part = obj.PrimaryPart
        if part then return part end
        return obj:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

local function getColorsForType(category)
    local fill = getColorForCategory(category)
    return fill, fill
end

local function createTracking(obj)
    if isIgnored(obj) then return end
    if trackedObjects[obj] then return end
    local displayName, objType = getDisplayInfo(obj)
    if not displayName then return end

    local basePart = getBasePart(obj)
    if not basePart then return end

    local fillColor, outlineColor = getColorsForType(objType)

    local highlight = Instance.new("Highlight")
    highlight.Adornee = obj
    highlight.FillColor = fillColor
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = outlineColor
    highlight.OutlineTransparency = 0.3
    highlight.Enabled = false
    highlight.Parent = obj

    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = basePart
    billboard.Size = UDim2.new(0, 120, 0, 60)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true
    billboard.Enabled = false
    billboard.Parent = basePart

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.2
    label.Text = displayName
    label.Font = Enum.Font.SourceSansBold
    label.TextSize = 12
    label.TextScaled = false
    label.Parent = billboard

    local line = nil
    if objType == "Tool" then
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        line = Instance.new("LineHandleAdornment")
        line.Adornee = root
        line.Thickness = 2
        line.Color3 = Color3.fromRGB(0, 255, 255)
        line.Transparency = 0.5
        line.Visible = false
        line.Parent = basePart
        if root then
            line.Point = root.CFrame:PointToObjectSpace(basePart.Position)
        end
    end

    local data = {
        Highlight = highlight,
        Billboard = billboard,
        Label = label,
        BasePart = basePart,
        Line = line,
        DisplayName = displayName,
        Category = objType,
        Obj = obj,
        UpdateConn = nil,
        AncestryConn = nil,
    }
    trackedObjects[obj] = data

    local function updateDistance()
        if not basePart.Parent then
            if trackedObjects[obj] then
                highlight:Destroy()
                billboard:Destroy()
                if line then line:Destroy() end
                if data.UpdateConn then data.UpdateConn:Disconnect() end
                if data.AncestryConn then data.AncestryConn:Disconnect() end
                trackedObjects[obj] = nil
            end
            return
        end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then
            label.Text = displayName .. "\n-- 格"
            return
        end
        local dist = (root.Position - basePart.Position).Magnitude
        label.Text = string.format("%s\n%.1f 格", displayName, dist)

        if line then
            line.Point = root.CFrame:PointToObjectSpace(basePart.Position)
            if line.Adornee ~= root then
                line.Adornee = root
            end
        end
    end

    local conn = RunService.Heartbeat:Connect(updateDistance)
    data.UpdateConn = conn

    local ancestryConn = obj.AncestryChanged:Connect(function()
        if not obj.Parent then
            if trackedObjects[obj] then
                highlight:Destroy()
                billboard:Destroy()
                if line then line:Destroy() end
                if conn then conn:Disconnect() end
                if ancestryConn then ancestryConn:Disconnect() end
                trackedObjects[obj] = nil
            end
        end
    end)
    data.AncestryConn = ancestryConn

    updateDistance()
end

local function scanScene()
    for _, obj in pairs(Workspace:GetDescendants()) do
        if getDisplayInfo(obj) then
            createTracking(obj)
        end
    end
end

local function refreshTracking()
    for _, data in pairs(trackedObjects) do
        local visible = false
        local cat = data.Category
        if cat == "Model" and trackModels then
            visible = true
        elseif cat == "Tool" and trackTools then
            visible = true
        elseif cat == "Monster" and trackMonsters then
            visible = true
        elseif cat == "RoomDoor" and trackRoomDoor then
            visible = true
        elseif cat == "TaskNPC" and trackTaskNPC then
            visible = true
        end
        if visible then
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local dist = (root.Position - data.BasePart.Position).Magnitude
                if dist > maxRenderDistance then
                    visible = false
                end
            end
        end
        data.Highlight.Enabled = visible
        data.Billboard.Enabled = visible
        if data.Line then
            data.Line.Visible = visible
        end
    end
end

local function refreshAllHighlights()
    for _, data in pairs(trackedObjects) do
        local fillColor, outlineColor = getColorsForType(data.Category)
        data.Highlight.FillColor = fillColor
        data.Highlight.OutlineColor = outlineColor
    end
end

Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") or obj:IsA("Tool") then
        if getDisplayInfo(obj) then
            createTracking(obj)
            local data = trackedObjects[obj]
            if data then
                local visible = false
                local cat = data.Category
                if cat == "Model" and trackModels then
                    visible = true
                elseif cat == "Tool" and trackTools then
                    visible = true
                elseif cat == "Monster" and trackMonsters then
                    visible = true
                elseif cat == "RoomDoor" and trackRoomDoor then
                    visible = true
                elseif cat == "TaskNPC" and trackTaskNPC then
                    visible = true
                end
                if visible then
                    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        local dist = (root.Position - data.BasePart.Position).Magnitude
                        if dist > maxRenderDistance then
                            visible = false
                        end
                    end
                end
                data.Highlight.Enabled = visible
                data.Billboard.Enabled = visible
                if data.Line then
                    data.Line.Visible = visible
                end
            end
        end
    end
end)

player.CharacterAdded:Connect(function()
    for _, data in pairs(trackedObjects) do
        if data.Line then
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            data.Line.Adornee = root
        end
    end
end)

local function getRootPart(char) return char and char:FindFirstChild("HumanoidRootPart") end

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
    local clipFunc = setclipboard or toclipboard or set_clipboard
    if clipFunc then
        pcall(clipFunc, tostring(text))
        return true
    end
    warn("剪贴板不可用")
    return false
end

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
    local root = getRootPart(char)
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
        if plr.Character and getRootPart(plr.Character) and player.Character and getRootPart(player.Character) then
            local dist = math.floor((getRootPart(player.Character).Position - getRootPart(plr.Character).Position).magnitude)
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

local function startFlyPC()
    if flying then return end
    local char = player.Character; local humanoid = char and char:FindFirstChildOfClass("Humanoid"); local root = getRootPart(char)
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
        local char = player.Character; local root = getRootPart(char)
        if not root or not root.Parent then stopFly(); return end
        local bv = root:FindFirstChildOfClass("BodyVelocity"); local bg = root:FindFirstChildOfClass("BodyGyro")
        if not bv then stopFly(); return end
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
    local char = player.Character; local humanoid = char and char:FindFirstChildOfClass("Humanoid"); local root = getRootPart(char)
    if not humanoid or not root then return end
    local controlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
    local bg = Instance.new("BodyGyro"); bg.P=9e4; bg.MaxTorque=Vector3.new(9e9,9e9,9e9); bg.CFrame=workspace.CurrentCamera.CFrame; bg.Parent=root
    local bv = Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(9e9,9e9,9e9); bv.Velocity=Vector3.new(); bv.Parent=root
    humanoid.PlatformStand=true; flying=true
    flyConnection = RunService.RenderStepped:Connect(function()
        if not flying then return end
        local char=player.Character; local root=getRootPart(char)
        if not root or not root.Parent then stopFly(); return end
        local bv=root:FindFirstChildOfClass("BodyVelocity"); local bg=root:FindFirstChildOfClass("BodyGyro")
        if not bv then stopFly(); return end
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
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    if flyKeyDown then flyKeyDown:Disconnect(); flyKeyDown = nil end
    if flyKeyUp then flyKeyUp:Disconnect(); flyKeyUp = nil end
    if flying then
        local char = player.Character
        local root = getRootPart(char)
        if root then
            for _, obj in pairs(root:GetChildren()) do
                if obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") then obj:Destroy() end
            end
        end
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end
        flying = false
    end
    control = { W = 0, S = 0, A = 0, D = 0, Q = 0, E = 0 }
end

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

local EnhanceTab = Window:Tab({ Title = "角色增强", Icon = "solar:user-bold", IconColor = Color3.fromHex("#10C550"), IconShape = "Square", Border = true })
local CharSection = EnhanceTab:Section({ Title = "角色控制", Box = true, BoxBorder = true, Opened = true })
local AnchorToggle = CharSection:Toggle({ Title = "角色锚固", Desc = "固定位置（重生不保留）", Callback = function(s) setAnchoredFunc(s) end })
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
ESPSection:Dropdown({ Title = "显示模式", Values = {"ESP (全信息)", "Chams (高亮HitBox)", "Locate (损坏状态)"}, Value = "ESP (全信息)", Callback = function(v)
    if v == "ESP (全信息)" then espMode = "ESP"
    elseif v == "Chams (高亮HitBox)" then espMode = "Chams"
    else espMode = "Locate" end
    if espEnabled then refreshAllESP() end
end})
ESPSection:Space()
ESPSection:Slider({ Title = "HitBox透明调整", IsTooltip=true, IsTextbox=true, Step=0.05, Value={Min=0,Max=1,Default=espTransparency}, Callback=function(v) espTransparency=v; if espEnabled then refreshAllESP() end end })

local SceneTab = Window:Tab({ Title = "场景追踪", Icon = "solar:box-bold", IconColor = Color3.fromHex("#FFA500"), IconShape = "Square", Border = true })
local SceneSection = SceneTab:Section({ Title = "追踪控制", Box = true, BoxBorder = true, Opened = true })

local function addTrackToggle(title, desc, category)
    local toggle = SceneSection:Toggle({
        Title = title,
        Desc = desc,
        Callback = function(s)
            if category == "Model" then trackModels = s
            elseif category == "Tool" then trackTools = s
            elseif category == "Monster" then trackMonsters = s
            elseif category == "RoomDoor" then trackRoomDoor = s
            elseif category == "TaskNPC" then trackTaskNPC = s
            end
            refreshTracking()
            if s then WindUI:Notify({Title=title.." 追踪", Content="已启用", Icon="eye", Duration=1}) end
        end
    })
    local currentColorName = colorSettings[category] or "白色"
    SceneSection:Dropdown({
        Title = "颜色",
        Values = presetColorNames,
        Value = currentColorName,
        Callback = function(selectedName)
            colorSettings[category] = selectedName
            refreshAllHighlights()
            WindUI:Notify({Title="颜色已更新", Content=title.." 颜色已修改为 "..selectedName, Icon="check", Duration=1.5})
        end
    })
    SceneSection:Space()
end

addTrackToggle("柜子/油罐/箱子/冰箱/奖励洞口", "高亮模型组", "Model")
addTrackToggle("道具/金币", "高亮模型", "Tool")
addTrackToggle("通道门", "高亮门模型", "RoomDoor")
addTrackToggle("怪物", "高亮敌对生物", "Monster")
addTrackToggle("任务NPC（指定人质）", "高亮NPC人质", "TaskNPC")

SceneSection:Space()
SceneSection:Slider({
    Title = "渲染距离（格）",
    Desc = "建议拉大数值",
    IsTooltip = true,
    IsTextbox = true,
    Step = 10,
    Value = { Min = 10, Max = 500, Default = maxRenderDistance },
    Callback = function(value)
        maxRenderDistance = value
        refreshTracking()
        WindUI:Notify({Title="渲染距离已更新", Content=tostring(value).." 格", Icon="eye", Duration=0.5})
    end
})

local TeleportTab = Window:Tab({ Title = "传送", Icon = "solar:map-pin-bold", IconColor = Color3.fromHex("#30A0FF"), IconShape = "Square", Border = true })
local TeleportSection = TeleportTab:Section({ Title = "定点传送", Box = true, BoxBorder = true, Opened = true })

TeleportSection:Button({
    Title = "回到电梯",
    Desc = "回到电梯里",
    Icon = "map-pin",
    Color = Color3.fromHex("#30FF6A"),
    Justify = "Center",
    Callback = function()
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(-310.905365, 324.80072, 406.117249)
                WindUI:Notify({Title="传送", Content="已传送到位置", Icon="check", Duration=1.5})
            end
        end
    end
})

TeleportSection:Space()

local targetPosition = nil
local targetPositionSet = false

local function getCurrentPos()
    local char = player.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            return hrp.Position
        end
    end
    return nil
end

TeleportSection:Button({
    Title = "定位当前位置",
    Desc = "记录当前站立位置作为传送目标",
    Icon = "target",
    Color = Color3.fromHex("#305dff"),
    Justify = "Center",
    Callback = function()
        local pos = getCurrentPos()
        if pos then
            targetPosition = pos
            targetPositionSet = true
            WindUI:Notify({Title="定位成功", Content="目标位置已记录: "..tostring(pos), Icon="check", Duration=2})
        else
            WindUI:Notify({Title="定位失败", Content="无法获取当前位置", Icon="x", Duration=2})
        end
    end
})

TeleportSection:Space()

local autoTeleportEnabled = false
local autoTeleportConnection = nil
local countdownTriggered = false

local function checkCountdownAndTeleport()
    if not autoTeleportEnabled then return end
    if not targetPositionSet then
        WindUI:Notify({Title="自动传送错误", Content="请先定位目标位置", Icon="x", Duration=2})
        autoTeleportEnabled = false
        return
    end

    local found = false
    for _, obj in pairs(game:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Name == "Countdown" then
            local text = obj.Text:gsub("%s+", "")
            if text:match("%d+:%d+") and text == "00:29" and not countdownTriggered then
                found = true
                break
            end
        end
    end

    if found then
        countdownTriggered = true
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(targetPosition)
                WindUI:Notify({Title="AutoTp", Content="时间到传送回目标位置", Icon="map-pin", Duration=2})
            end
        end
    else
        countdownTriggered = false
    end
end

TeleportSection:Toggle({
    Title = "倒计时自动回指定位置",
    Desc = "倒计时变为 00:29 时，自动传送至定位位置",
    Callback = function(s)
        autoTeleportEnabled = s
        if autoTeleportConnection then
            autoTeleportConnection:Disconnect()
            autoTeleportConnection = nil
        end
        if s then
            if not targetPositionSet then
                WindUI:Notify({Title="自动传送启动失败", Content="请先定位目标位置", Icon="x", Duration=2})
                autoTeleportEnabled = false
                return
            end
            countdownTriggered = false
            autoTeleportConnection = RunService.Heartbeat:Connect(function()
                if tick() % 0.2 < 0.01 then
                    checkCountdownAndTeleport()
                end
            end)
            WindUI:Notify({Title="自动传送", Content="已启用，等待倒计时", Icon="toggle-on", Duration=1.5})
        else
            WindUI:Notify({Title="自动传送", Content="已禁用", Icon="toggle-off", Duration=1})
        end
    end
})

TeleportSection:Space()

local healthTargetPosition = nil
local healthTargetSet = false
local healthAutoTeleportEnabled = false
local healthCheckConn = nil
local healthCheckConnAdded = nil
local healthTriggered = false

TeleportSection:Button({
    Title = "记录血量传送坐标",
    Desc = "记录当前位置，用于血量低于45时自动传送",
    Icon = "heart",
    Color = Color3.fromHex("#FF6B35"),
    Justify = "Center",
    Callback = function()
        local pos = getCurrentPos()
        if pos then
            healthTargetPosition = pos
            healthTargetSet = true
            WindUI:Notify({Title="记录成功", Content="血量传送坐标已记录: "..tostring(pos), Icon="check", Duration=2})
        else
            WindUI:Notify({Title="记录失败", Content="无法获取当前位置", Icon="x", Duration=2})
        end
    end
})

TeleportSection:Space()

TeleportSection:Toggle({
    Title = "血量低于45自动传送",
    Desc = "当血量 ≤ 45 时，自动传送到记录的血量坐标",
    Callback = function(s)
        healthAutoTeleportEnabled = s
        if healthCheckConn then
            healthCheckConn:Disconnect()
            healthCheckConn = nil
        end
        if healthCheckConnAdded then
            healthCheckConnAdded:Disconnect()
            healthCheckConnAdded = nil
        end
        if s then
            if not healthTargetSet then
                WindUI:Notify({Title="启动失败", Content="请先记录血量传送坐标", Icon="x", Duration=2})
                healthAutoTeleportEnabled = false
                return
            end
            healthTriggered = false
            
            local function onHealthChanged()
                if not healthAutoTeleportEnabled then return end
                local char = player.Character
                if not char then return end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if not hum then return end
                local health = hum.Health
                if health <= 45 and not healthTriggered then
                    healthTriggered = true
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp and healthTargetPosition then
                        hrp.CFrame = CFrame.new(healthTargetPosition)
                        WindUI:Notify({Title="自动传送", Content="血量低于45，已传送至安全位置", Icon="heart", Duration=2})
                    end
                elseif health > 45 then
                    healthTriggered = false
                end
            end

            local function bindHealthEvent()
                local char = player.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        if healthCheckConn then healthCheckConn:Disconnect() end
                        healthCheckConn = hum.HealthChanged:Connect(onHealthChanged)
                        onHealthChanged() 
                    end
                end
            end
            
            bindHealthEvent()
            healthCheckConnAdded = player.CharacterAdded:Connect(function()
                task.wait(0.5)
                bindHealthEvent()
            end)
            WindUI:Notify({Title="血量自动传送", Content="已启用，当血量≤45时传送", Icon="toggle-on", Duration=1.5})
        else
            if healthCheckConn then
                healthCheckConn:Disconnect()
                healthCheckConn = nil
            end
            if healthCheckConnAdded then
                healthCheckConnAdded:Disconnect()
                healthCheckConnAdded = nil
            end
            WindUI:Notify({Title="血量自动传送", Content="已禁用", Icon="toggle-off", Duration=1})
        end
    end
})

local LightingTab = Window:Tab({ Title = "照明", Icon = "solar:sun-bold", IconColor = Color3.fromHex("#FDB813"), IconShape = "Square", Border = true })
local LightingSection = LightingTab:Section({ Title = "照明控制", Box = true, BoxBorder = true, Opened = true })

LightingSection:Button({
    Title = "除雾",
    Desc = "删除官方设置光影效果 [ 不可撤销 ] ",
    Icon = "trash",
    Color = Color3.fromHex("#FF4830"),
    Justify = "Center",
    Callback = function()
        for _, child in pairs(Lighting:GetChildren()) do
            child:Destroy()
        end
        WindUI:Notify({Title="照明清除", Content="所有照明对象已删除", Icon="check", Duration=1.5})
    end
})

LightingSection:Space()

LightingSection:Button({
    Title = "无阴影",
    Desc = "关闭全局阴影 [ 不可撤销 ] ",
    Icon = "sun",
    Color = Color3.fromHex("#FDB813"),
    Justify = "Center",
    Callback = function()
        Lighting.ClockTime = 12
        Lighting.GlobalShadows = false
        WindUI:Notify({Title="照明更新", Content="阴影已关闭", Icon="check", Duration=1.5})
    end
})

LightingSection:Space()

local pointLightEnabled = false
local pointLightConnection = nil
local currentLight = nil
local lightRange = 20
local lightBrightness = 5

local function updatePlayerLight()
    if not pointLightEnabled then
        if currentLight then
            currentLight:Destroy()
            currentLight = nil
        end
        return
    end
    local char = player.Character
    if not char then return end
    local root = getRootPart(char)
    if not root then return end

    if not currentLight or currentLight.Parent ~= root then
        if currentLight then currentLight:Destroy() end
        currentLight = Instance.new("PointLight")
        currentLight.Parent = root
    end
    currentLight.Range = lightRange
    currentLight.Brightness = lightBrightness
    currentLight.Color = Color3.new(1, 1, 1)
end

LightingSection:Toggle({
    Title = "玩家光源",
    Desc = "在玩家身上创建光明",
    Callback = function(s)
        pointLightEnabled = s
        if not s then
            if currentLight then
                currentLight:Destroy()
                currentLight = nil
            end
            if pointLightConnection then
                pointLightConnection:Disconnect()
                pointLightConnection = nil
            end
            WindUI:Notify({Title="玩家光源", Content="已关闭", Icon="toggle-off", Duration=1})
        else
            updatePlayerLight()
            if pointLightConnection then pointLightConnection:Disconnect() end
            pointLightConnection = player.CharacterAdded:Connect(function()
                task.wait(0.2)
                updatePlayerLight()
            end)
            WindUI:Notify({Title="玩家光源", Content="已启用", Icon="toggle-on", Duration=1})
        end
    end
})

LightingSection:Space()

LightingSection:Slider({
    Title = "光源距离",
    Desc = "1 ~ 50",
    IsTooltip = true,
    IsTextbox = true,
    Step = 1,
    Value = { Min = 1, Max = 50, Default = lightRange },
    Callback = function(v)
        lightRange = v
        if pointLightEnabled and currentLight then
            currentLight.Range = v
        end
    end
})

LightingSection:Space()

LightingSection:Slider({
    Title = "光源亮度",
    Desc = "0 ~ 10",
    IsTooltip = true,
    IsTextbox = true,
    Step = 0.1,
    Value = { Min = 0, Max = 10, Default = lightBrightness },
    Callback = function(v)
        lightBrightness = v
        if pointLightEnabled and currentLight then
            currentLight.Brightness = v
        end
    end
})

local FunctionTab = Window:Tab({ Title = "功能区", Icon = "solar:folder-2-bold", IconColor = Color3.fromHex("#ECA201"), IconShape = "Square", Border = true })
local FunctionSection = FunctionTab:Section({ Title = "交互功能", Box = true, BoxBorder = true, Opened = true })

local autoInteractEnabled = false
local autoInteractConnection = nil
local lastInteractTime = 0
local lastInteractTool = nil

local function triggerInteraction(target)
    local detector = target:FindFirstChildOfClass("ClickDetector")
    local prompt = target:FindFirstChildOfClass("ProximityPrompt")
    
    if detector then
        local ok, err = pcall(function()
            if fireclickdetector then
                fireclickdetector(detector)
                return true
            end
        end)
        if ok and fireclickdetector then return true end
    elseif prompt then
        local ok, err = pcall(function()
            if fireproximityprompt then
                fireproximityprompt(prompt)
                return true
            end
        end)
        if ok and fireproximityprompt then return true end
    end

    if VirtualInputManager and VirtualInputManager.SendMouseButtonEvent then
        local cam = workspace.CurrentCamera
        local screenPos, onScreen = cam:WorldToScreenPoint(target.Position)
        if onScreen then
            VirtualInputManager:SendMouseMovementEvent(screenPos.X, screenPos.Y, 0, false)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, true, Enum.UserInputType.MouseButton1, false)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, false, Enum.UserInputType.MouseButton1, false)
            return true
        end
    end

    if VirtualInputManager and VirtualInputManager.SendKeyEvent then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, nil)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, nil)
        return true
    end

    if keypress and keyrelease then
        local code = 69
        keypress(code)
        task.wait(0.05)
        keyrelease(code)
        return true
    end

    return false
end

local function autoInteractLoop()
    if not autoInteractEnabled then return end
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local radius = 5
    local closestDist = radius
    local closestTool = nil

    for _, data in pairs(trackedObjects) do
        if data.Category == "Tool" then
            local tool = data.Obj
            if tool and not isInMonstersFolder(tool) and data.Highlight.Enabled then
                local handle = tool:FindFirstChildWhichIsA("BasePart")
                if handle then
                    local dist = (root.Position - handle.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestTool = tool
                    end
                end
            end
        end
    end

    if closestTool then
        local now = tick()
        if closestTool ~= lastInteractTool or closestDist < 1.5 then
            if now - lastInteractTime > 0.5 then
                local handle = closestTool:FindFirstChildWhichIsA("BasePart")
                if handle then
                    lastInteractTool = closestTool
                    lastInteractTime = now
                    local success = triggerInteraction(handle)
                    if success then
                        WindUI:Notify({Title="自动交互", Content="已触发道具: "..closestTool.Name, Icon="mouse", Duration=1.5})
                    else
                        WindUI:Notify({Title="自动交互", Content="尝试触发道具失败 [ 也许你不应该打开 ] ", Icon="x", Duration=2})
                    end
                end
            end
        end
    else
        lastInteractTool = nil
    end
end

FunctionSection:Toggle({
    Title = "自动交互（损坏的）",
    Desc = "持续检测附近可以交互，自动触发交互",
    Callback = function(s)
        autoInteractEnabled = s
        if autoInteractConnection then
            autoInteractConnection:Disconnect()
            autoInteractConnection = nil
        end
        if s then
            autoInteractConnection = RunService.Heartbeat:Connect(autoInteractLoop)
            WindUI:Notify({Title="自动交互", Content="已启用", Icon="toggle-on", Duration=1})
        else
            WindUI:Notify({Title="自动交互", Content="已禁用", Icon="toggle-off", Duration=1})
        end
    end
})

FunctionSection:Space()

local countdownDisplayEnabled = false
local countdownDisplayConn = nil
local countdownDisplayGui = nil
local countdownDisplayLabel = nil

local function createCountdownDisplay()
    if countdownDisplayGui then
        countdownDisplayGui:Destroy()
        countdownDisplayGui = nil
        countdownDisplayLabel = nil
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "CountdownDisplay"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 50)
    frame.Position = UDim2.new(0, 10, 1, -60)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.SourceSansBold
    label.TextSize = 24
    label.Text = "等待倒计时..."
    label.Parent = frame

    countdownDisplayGui = gui
    countdownDisplayLabel = label
    return label
end

local function updateCountdownDisplay()
    if not countdownDisplayEnabled then return end
    if not countdownDisplayLabel then
        createCountdownDisplay()
    end
    local foundText = "无倒计时"
    for _, obj in pairs(game:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Name == "Countdown" then
            local raw = obj.Text:gsub("%s+", "")
            if raw:match("%d+:%d+") then
                foundText = raw
                break
            end
        end
    end
    if countdownDisplayLabel then
        countdownDisplayLabel.Text = foundText
    end
end

FunctionSection:Toggle({
    Title = "显示精确倒计时",
    Desc = "在屏幕左下角显示倒计时数字",
    Callback = function(s)
        countdownDisplayEnabled = s
        if countdownDisplayConn then
            countdownDisplayConn:Disconnect()
            countdownDisplayConn = nil
        end
        if s then
            createCountdownDisplay()
            updateCountdownDisplay()
            countdownDisplayConn = RunService.Heartbeat:Connect(function()
                if tick() % 0.1 < 0.01 then
                    updateCountdownDisplay()
                end
            end)
            WindUI:Notify({Title="倒计时显示", Content="已启用", Icon="eye", Duration=1})
        else
            if countdownDisplayGui then
                countdownDisplayGui:Destroy()
                countdownDisplayGui = nil
                countdownDisplayLabel = nil
            end
            WindUI:Notify({Title="倒计时显示", Content="已禁用", Icon="eye-off", Duration=1})
        end
    end
})

local InfoTab = Window:Tab({ Title = "信息", Icon = "solar:info-square-bold", IconColor = Color3.fromHex("#83889E"), IconShape = "Square", Border = true })

local infoButtons = {}

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

local function refreshAllInfo()
    local data = getServerInfo()
    local mappings = {
        ["地点"] = data.PlaceName,
        ["Place ID"] = data.PlaceId,
        ["Game ID"] = data.GameId,
        ["Job ID"] = data.JobId,
        ["游戏开发者"] = data.CreatorName .. " (ID: " .. data.CreatorId .. ")",
        ["你的加入累计时间"] = data.RunTimeFormatted,
        ["玩家"] = data.CurrentPlayers .. " / " .. data.MaxPlayers,
        ["本地玩家"] = data.PlayerName .. " (" .. data.PlayerDisplayName .. ")",
        [" 玩家 ID"] = data.PlayerId,
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

do
    local data = getServerInfo()
    infoButtons["地点"] = createInfoButton("地点", data.PlaceName)
    infoButtons["Place ID"] = createInfoButton("Place ID", data.PlaceId)
    infoButtons["Game ID"] = createInfoButton("Game ID", data.GameId)
    infoButtons["Job ID"] = createInfoButton("Job ID", data.JobId)
    infoButtons["游戏开发者"] = createInfoButton("游戏开发者", data.CreatorName .. " (ID: " .. data.CreatorId .. ")")
    infoButtons["你的加入累计时间"] = createInfoButton("你的加入累计时间", data.RunTimeFormatted)
    infoButtons["玩家"] = createInfoButton("玩家", data.CurrentPlayers .. " / " .. data.MaxPlayers)
    infoButtons["本地玩家"] = createInfoButton("本地玩家", data.PlayerName .. " (" .. data.PlayerDisplayName .. ")")
    infoButtons[" 玩家 ID"] = createInfoButton(" 玩家 ID", data.PlayerId)
    infoButtons["延迟"] = createInfoButton("延迟", data.Ping)
end

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

scanScene()
refreshTracking()
