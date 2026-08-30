local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local VirtualUser        = game:GetService("VirtualUser")

local player = Players.LocalPlayer

--// ═══ KHAI BÁO TRƯỚC (tránh lỗi forward reference) ═══
local ghiLog
local capNhatTrangThai
local capNhatThongKe

--// ═══ THƯ VIỆN UI ═══
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Dương Api",
    LoadingTitle = "Đang tải Dương Api...",
    LoadingSubtitle = "Tự động hóa game..",
    Theme = "AmberGlow",
    ToggleUIKeybind = "K",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "SlimHub",
        FileName = "Config_v3"
    }
})

--// ═══ REMOTES ═══
local NukeRemotes = ReplicatedStorage:WaitForChild("NukeRemotes", 10)
if not NukeRemotes then
    warn("[SlimHub] Không tìm thấy NukeRemotes!")
    return
end

local Remote = {}
for _, ten in ipairs({
    "PickUp", "Drop", "MergeRequest", "PurchaseUpgrade",
    "HoldStarted", "HoldEnded", "StateUpdate"
}) do
    Remote[ten] = NukeRemotes:WaitForChild(ten, 5)
    if not Remote[ten] then
        warn("[SlimHub] Thiếu remote: " .. ten)
    end
end

--// ═══ CẤU HÌNH ═══
local CAU_HINH = {
    -- Quét
    THOIGIAN_QUET     = 0.15,    -- giây giữa mỗi lần quét
    BAN_KINH_QUET     = 120,     -- studs - phạm vi tìm nuke
    KHOANG_CACH_TP    = 5,       -- studs offset khi teleport

    -- Thời gian
    TRE_PICKUP        = 0.20,    -- chờ sau khi pickup
    TRE_MERGE         = 0.30,    -- chờ trước khi merge
    TRE_TP            = 0.12,    -- chờ sau khi teleport
    TIMEOUT_BUSY      = 6.0,     -- giây - reset nếu bị kẹt
    TIMEOUT_GIU       = 2.5,     -- giây - drop nếu giữ quá lâu
    TIMEOUT_PICKUP    = 2.0,     -- giây - chờ HoldStarted

    -- Nâng cấp
    THOIGIAN_NANGCAP  = 1.0,     -- giây giữa mỗi lần mua
    THU_TU_NANGCAP    = {"TIER", "LOCKBASE", "MAX"},

    -- Chống phát hiện
    ANTI_AFK          = true,
    TRE_NGAU_NHIEN    = true,    -- thêm thời gian ngẫu nhiên
    BIEN_DO_TRE       = 0.05,    -- ± giây ngẫu nhiên

    -- Giao diện
    SO_LOG_TOI_DA     = 30,
    CHE_DO_DEBUG      = false,
}

--// ═══ TRẠNG THÁI MÁY ═══
--[[
    Mô phỏng state machine từ bản gốc (100+ states).
    Đơn giản hóa thành các trạng thái thiết yếu:
]]
local TrangThai = {
    NGOI       = "NGOI",         -- Idle
    QUET       = "QUET",         -- Scanning
    TP_NUKE    = "TP_NUKE",      -- Teleport to nuke
    NHAT       = "NHAT",         -- Picking up
    CHO_GIU    = "CHO_GIU",      -- Waiting for hold
    TP_GOP     = "TP_GOP",       -- Teleport to merge target
    GOP        = "GOP",          -- Merging
    THA        = "THA",          -- Dropping
    NANGCAP    = "NANGCAP",      -- Upgrading
    LOI        = "LOI",          -- Error
}

local ctx = {
    trangThai      = TrangThai.NGOI,
    dangGiu        = false,
    nukeDangGiu    = nil,
    tierDangGiu    = nil,
    thoiDiemGiu    = 0,
    dangBan        = false,       -- busy
    thoiDiemBan    = 0,
    idSequence     = 0,

    -- Bộ đếm
    soLanQuet      = 0,
    soLanNhat      = 0,
    soLanGop       = 0,
    soLanTha       = 0,
    soLanNangCap   = 0,
    soLanLoi       = 0,

    -- Thời gian
    lanQuetCuoi    = 0,
    lanNangCapCuoi = 0,

    -- Bật/tắt
    tuDongSequence = false,
    tuDongNangCap  = false,
    tuDongTha      = true,
}

--// ═══ DỮ LIỆU NÂNG CẤP ═══
local duLieuNangCap = {
    tien     = 0,
    nangCaps = {},
}

--// ═══ HÀM TIỆN ÍCH ═══

local function treNgauNhien(coSo)
    if CAU_HINH.TRE_NGAU_NHIEN then
        return coSo + math.random() * CAU_HINH.BIEN_DO_TRE
    end
    return coSo
end

local function goiRemoteAnToan(remote, ...)
    if not remote then return false end
    local args = {...}
    local ok, err = pcall(function()
        remote:FireServer(unpack(args))
    end)
    if not ok then
        ctx.soLanLoi = ctx.soLanLoi + 1
        ghiLog("Lỗi FireServer: " .. tostring(err))
    end
    return ok
end

local function doiTrangThai(moi)
    local cu = ctx.trangThai
    ctx.trangThai = moi
    if CAU_HINH.CHE_DO_DEBUG then
        print(string.format("[TRẠNG THÁI] %s → %s", cu, moi))
    end
end

local function layNhanVat()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function khoangCach2D(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function teleportTo(viTri)
    local root = layNhanVat()
    if not root then return false end
    root.CFrame = CFrame.new(viTri + Vector3.new(0, CAU_HINH.KHOANG_CACH_TP, 0))
    task.wait(treNgauNhien(CAU_HINH.TRE_TP))
    return true
end

--// ═══ HÀM XỬ LÝ NUKE ═══

local folderCache = nil

local function timFolderNukeCuaToi()
    if folderCache and folderCache.Parent then
        return folderCache
    end
    folderCache = nil

    local Bases = Workspace:FindFirstChild("Bases")
    if not Bases then return nil end

    for _, base in ipairs(Bases:GetChildren()) do
        local Nukes = base:FindFirstChild("Nukes")
        if Nukes then
            for _, nuke in ipairs(Nukes:GetChildren()) do
                local ok, chuSo = pcall(function()
                    return nuke:GetAttribute("OwnerUserId")
                end)
                if ok and chuSo == player.UserId then
                    folderCache = Nukes
                    return Nukes
                end
            end
        end
    end
    return nil
end

local function laySoNuke(nuke)
    local ok, ketQua = pcall(function()
        local oh = nuke:FindFirstChild("OverheadNuke")
        if oh then
            local tl = oh:FindFirstChild("TextLabel")
            if tl then return tl.Text end
        end
        return nil
    end)
    return ok and ketQua or nil
end

local function layTierNuke(nuke)
    local ok, tier = pcall(function()
        return nuke:GetAttribute("Tier")
    end)
    return ok and tier or nil
end

local function layTrangThaiNuke(nuke)
    local ok, val = pcall(function()
        return nuke:GetAttribute("State")
    end)
    return ok and val or nil
end

local function coTheNhat(nuke)
    local tt = layTrangThaiNuke(nuke)
    return tt == "floor" or tt == "based"
end

--// ═══ THU THẬP NUKE ═══
--[[
    Logic từ MAN.lua:
    - table.create, table.insert patterns
    - Nhóm theo số nuke (string keys)
    - Sắp xếp theo khoảng cách
]]

local function thuThapNukes()
    local root = layNhanVat()
    if not root then return {} end

    local folder = timFolderNukeCuaToi()
    if not folder then return {} end

    local nhom = {}  -- { [soNuke] = { {instance, khoangCach}, ... } }

    for _, nuke in ipairs(folder:GetChildren()) do
        if nuke:IsA("BasePart") and coTheNhat(nuke) then
            local kc = khoangCach2D(nuke.Position, root.Position)
            if kc <= CAU_HINH.BAN_KINH_QUET then
                local so = laySoNuke(nuke)
                if so then
                    if not nhom[so] then
                        nhom[so] = {}
                    end
                    table.insert(nhom[so], {
                        inst = nuke,
                        kc   = kc,
                        tier = layTierNuke(nuke),
                    })
                end
            end
        end
    end

    -- Sắp xếp mỗi nhóm theo khoảng cách tăng dần
    for _, nhomCon in pairs(nhom) do
        table.sort(nhomCon, function(a, b) return a.kc < b.kc end)
    end

    return nhom
end

--// ═══ CÁC HÀNH ĐỘNG ═══

local function hanhDongTha(lyDo)
    doiTrangThai(TrangThai.THA)
    local root = layNhanVat()
    if root then
        goiRemoteAnToan(Remote.Drop, root.CFrame)
    end
    ctx.soLanTha = ctx.soLanTha + 1
    ctx.dangGiu = false
    ctx.nukeDangGiu = nil
    ctx.tierDangGiu = nil
    ghiLog(string.format("THẢ #%d: %s", ctx.soLanTha, lyDo))
    task.wait(treNgauNhien(CAU_HINH.TRE_PICKUP))
    doiTrangThai(TrangThai.NGOI)
end

local function hanhDongNhat(nukeInst, soNuke)
    -- Bước 1: Teleport đến nuke
    doiTrangThai(TrangThai.TP_NUKE)
    if not teleportTo(nukeInst.Position) then
        doiTrangThai(TrangThai.LOI)
        ghiLog("LỖI: Không teleport được")
        return false
    end

    -- Bước 2: Gửi lệnh PickUp
    doiTrangThai(TrangThai.NHAT)
    goiRemoteAnToan(Remote.PickUp, nukeInst)
    ctx.soLanNhat = ctx.soLanNhat + 1
    ghiLog(string.format("NHẶT #%d: Nuke số %s", ctx.soLanNhat, soNuke))

    -- Bước 3: Chờ sự kiện HoldStarted
    doiTrangThai(TrangThai.CHO_GIU)
    local hanCuong = os.clock() + CAU_HINH.TIMEOUT_PICKUP
    while not ctx.dangGiu and os.clock() < hanCuong do
        task.wait(0.05)
    end

    if not ctx.dangGiu then
        ghiLog("LỖI: Không nhận được HoldStarted (timeout)")
        doiTrangThai(TrangThai.NGOI)
        return false
    end

    return true
end

local function hanhDongGop(mucTiep, soNuke)
    -- Kiểm tra mục tiêu còn tồn tại
    if not mucTiep or not mucTiep.Parent then
        ghiLog("LỖI: Mục tiêu merge đã biến mất")
        doiTrangThai(TrangThai.NGOI)
        return false
    end

    -- Bước 4: Teleport đến nuke mục tiêu
    doiTrangThai(TrangThai.TP_GOP)
    if not teleportTo(mucTiep.Position) then
        doiTrangThai(TrangThai.LOI)
        ghiLog("LỖI: Không teleport đến mục tiêu merge")
        return false
    end

    -- Bước 5: Chờ rồi gửi lệnh Merge
    doiTrangThai(TrangThai.GOP)
    task.wait(treNgauNhien(CAU_HINH.TRE_MERGE))

    goiRemoteAnToan(Remote.MergeRequest, mucTiep)
    ctx.soLanGop = ctx.soLanGop + 1
    ghiLog(string.format("GHÉP #%d: Nuke số %s", ctx.soLanGop, soNuke))

    task.wait(treNgauNhien(CAU_HINH.TRE_PICKUP))
    doiTrangThai(TrangThai.NGOI)
    return true
end

--// ═══ LOGIC CHÍNH - VÒNG LẶP TỰ ĐỘNG ═══
--[[
    Mô phỏng lại từ VM bytecode:
    - State machine với điều kiện phân nhánh
    - Coroutine-based async (coroutine.create/resume/yield)
    - Arithmetic cho so sánh khoảng cách
    - Table operations cho nhóm nuke

    Flow đầy đủ:
    ┌──────────────────────────────────────────────────────┐
    │  ĐANG GIỮ NUKE?                                     │
    │  ├─ CÓ + có nuke trùng số → TP đến nuke đó → GHÉP  │
    │  ├─ CÓ + không trùng số  → THẢ nuke                │
    │  └─ KHÔNG                                           │
    │      ├─ Có 2+ nuke trùng số → NHẶT cái 1 → GHÉP   │
    │      └─ Không có cặp → NGồi chờ                     │
    └──────────────────────────────────────────────────────┘
]]

local function chaySequence()
    -- Kiểm tra busy + timeout an toàn
    if ctx.dangBan then
        if os.clock() - ctx.thoiDiemBan > CAU_HINH.TIMEOUT_BUSY then
            ghiLog("CẢNH BÁO: Busy timeout - tự động reset")
            ctx.dangBan = false
            ctx.dangGiu = false
            doiTrangThai(TrangThai.NGOI)
        else
            return
        end
    end

    ctx.dangBan = true
    ctx.thoiDiemBan = os.clock()
    ctx.idSequence = ctx.idSequence + 1
    local idHienTai = ctx.idSequence

    doiTrangThai(TrangThai.QUET)
    local nhom = thuThapNukes()

    -- ═══ TRƯỜNG HỢP 1: Đang giữ nuke ═══
    if ctx.dangGiu then
        local soDangGiu = ctx.nukeDangGiu and laySoNuke(ctx.nukeDangGiu)
        local timThayCap = false
        local mucTiepCap = nil

        if soDangGiu and nhom[soDangGiu] then
            for _, duLieu in ipairs(nhom[soDangGiu]) do
                -- Phải khác nuke đang giữ VÀ còn tồn tại
                if duLieu.inst ~= ctx.nukeDangGiu and duLieu.inst.Parent then
                    timThayCap = true
                    mucTiepCap = duLieu.inst
                    break
                end
            end
        end

        if timThayCap and mucTiepCap then
            -- Có nuke trùng số → Ghép
            hanhDongGop(mucTiepCap, soDangGiu or "?")
        else
            -- Không có nuke trùng số → Thả
            hanhDongTha("không có cặp cho số " .. tostring(soDangGiu))
        end

        ctx.dangBan = false
        ctx.thoiDiemBan = 0
        return
    end

    -- ═══ TRƯỜNG HỢP 2: Không giữ nuke → tìm cặp ═══
    for so, nhomCon in pairs(nhom) do
        if #nhomCon >= 2 then
            local nukeDau  = nhomCon[1].inst
            local nukeThu2 = nhomCon[2].inst

            -- Kiểm tra cả 2 còn tồn tại
            if not nukeDau.Parent or not nukeThu2.Parent then
                continue
            end

            -- Bước 1: Nhặt nuke đầu tiên
            local daNhat = hanhDongNhat(nukeDau, so)

            -- Kiểm tra sequence còn hợp lệ không (tránh conflict)
            if ctx.idSequence ~= idHienTai then
                ctx.dangBan = false
                ctx.thoiDiemBan = 0
                return
            end

            -- Bước 2: Nếu nhặt thành công → Ghép với nuke thứ 2
            if daNhat and ctx.dangGiu then
                hanhDongGop(nukeThu2, so)
            end

            ctx.dangBan = false
            ctx.thoiDiemBan = 0
            return  -- Chỉ chạy 1 sequence mỗi lần quét
        end
    end

    -- Không tìm thấy cặp nào
    doiTrangThai(TrangThai.NGOI)
    ctx.dangBan = false
    ctx.thoiDiemBan = 0
end

--// ═══ LOGIC NÂNG CẤP ═══

local function muaNangCap(loai)
    goiRemoteAnToan(Remote.PurchaseUpgrade, loai)
    ctx.soLanNangCap = ctx.soLanNangCap + 1
    ghiLog(string.format("MUA NÂNG CẤP: %s", loai))
end

local function chayNangCap()
    for _, loai in ipairs(CAU_HINH.THU_TU_NANGCAP) do
        local cap = duLieuNangCap.nangCaps[loai]
        if cap and not cap.maxed then
            muaNangCap(loai)
            return
        end
    end
end

--// ═══ XỬ LÝ SỰ KIỆN REMOTE ═══

if Remote.HoldStarted then
    Remote.HoldStarted.OnClientEvent:Connect(function(nukeInst)
        ctx.dangGiu = true
        ctx.nukeDangGiu = nukeInst
        ctx.thoiDiemGiu = os.clock()

        if type(nukeInst) == "userdata" then
            ctx.tierDangGiu = layTierNuke(nukeInst)
        end

        ghiLog("BẮT ĐẦU GIỮ: " .. tostring(laySoNuke(nukeInst)))
    end)
end

if Remote.HoldEnded then
    Remote.HoldEnded.OnClientEvent:Connect(function()
        ctx.dangGiu = false
        ctx.nukeDangGiu = nil
        ctx.tierDangGiu = nil
        ghiLog("KẾT THÚC GIỮ")
    end)
end

if Remote.StateUpdate then
    Remote.StateUpdate.OnClientEvent:Connect(function(data)
        if data then
            if data.cash then
                duLieuNangCap.tien = data.cash
            end
            if data.upgrades then
                duLieuNangCap.nangCaps = data.upgrades
            end
        end
    end)
end

--// ═══ ANTI-AFK ═══

if CAU_HINH.ANTI_AFK then
    player.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        if CAU_HINH.CHE_DO_DEBUG then
            ghiLog("Anti-AFK đã kích hoạt")
        end
    end)
end

--// ═══ ESP (HIỂN THỊ NUKE TRÊN MÀN HÌNH) ═══

local doiTuongESP = {}

local function xoaESP()
    for _, obj in pairs(doiTuongESP) do
        if obj and obj.Parent then
            obj:Destroy()
        end
    end
    doiTuongESP = {}
end

local function capNhatESP()
    xoaESP()

    local root = layNhanVat()
    if not root then return end

    local folder = timFolderNukeCuaToi()
    if not folder then return end

    for _, nuke in ipairs(folder:GetChildren()) do
        if nuke:IsA("BasePart") and coTheNhat(nuke) then
            local kc = khoangCach2D(nuke.Position, root.Position)
            if kc <= CAU_HINH.BAN_KINH_QUET then
                local so = laySoNuke(nuke) or "?"

                local bb = Instance.new("BillboardGui")
                bb.Name = "SlimESP"
                bb.Adornee = nuke
                bb.Size = UDim2.new(0, 90, 0, 32)
                bb.StudsOffset = Vector3.new(0, 3.5, 0)
                bb.AlwaysOnTop = true

                local tl = Instance.new("TextLabel")
                tl.Parent = bb
                tl.Size = UDim2.new(1, 0, 1, 0)
                tl.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                tl.BackgroundTransparency = 0.4
                tl.TextColor3 = Color3.fromRGB(255, 200, 0)
                tl.Text = string.format(" #%s (%.0fm)", so, kc)
                tl.TextScaled = true
                tl.Font = Enum.Font.GothamBold
                tl.BorderSizePixel = 0

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
                corner.Parent = tl

                bb.Parent = nuke
                table.insert(doiTuongESP, bb)
            end
        end
    end
end

--// ═══ GIAO DIỆN: TAB CHÍNH ═══

local TabChinh = Window:CreateTab("Chính", "home")

local nhanTrangThai = TabChinh:CreateLabel(
    "ĐANG CHỜ...", "circle", Color3.fromRGB(255, 255, 0), false
)

local nhanThongKe = TabChinh:CreateLabel(
    "Quét: 0 | Nhặt: 0 | Ghép: 0 | Thả: 0",
    "info", Color3.fromRGB(200, 200, 200), false
)

local noiDungLog = "Đang chờ hành động..."
local doanLog = TabChinh:CreateParagraph({
    Title = "Nhật ký hoạt động",
    Content = noiDungLog
})

-- Ghi đè hàm ghiLog để cập nhật UI
ghiLog = function(msg)
    if CAU_HINH.CHE_DO_DEBUG then
        print("[LOG] " .. msg)
    end
    pcall(function()
        local cacDong = {}
        for dong in noiDungLog:gmatch("[^\r\n]+") do
            table.insert(cacDong, dong)
        end
        if #cacDong >= CAU_HINH.SO_LOG_TOI_DA then
            table.remove(cacDong, 1)
        end
        table.insert(cacDong, "[" .. os.date("%H:%M:%S") .. "] " .. msg)
        noiDungLog = table.concat(cacDong, "\n")
        doanLog:Set({
            Title = "Nhật ký hoạt động",
            Content = noiDungLog
        })
    end)
end

capNhatTrangThai = function(text, icon, mau)
    pcall(function()
        nhanTrangThai:Set(text, icon or "circle", mau or Color3.fromRGB(255, 255, 0), false)
    end)
end

capNhatThongKe = function()
    pcall(function()
        nhanThongKe:Set(
            string.format("Quét: %d | Nhặt: %d | Ghép: %d | Thả: %d | Nâng cấp: %d | Lỗi: %d",
                ctx.soLanQuet, ctx.soLanNhat, ctx.soLanGop,
                ctx.soLanTha, ctx.soLanNangCap, ctx.soLanLoi),
            "info",
            Color3.fromRGB(200, 200, 200),
            false
        )
    end)
end

TabChinh:CreateParagraph({
    Title = "SLIM HUB v3.0 - Hướng dẫn",
    Content = [[Tự động ghép nuke hoàn toàn tự động.

VÒNG LẶP TỰ ĐỘNG:
1. Đang giữ nuke + có nuke trùng số → GHÉP
2. Đang giữ nuke + không trùng số → THẢ
3. Không giữ + có 2+ nuke trùng → NHẶT → GHÉP
4. Lặp lại liên tục

PHÍM TẮT:
• K: Bật/tắt giao diện
• V: Quét thủ công]]
})

TabChinh:CreateKeybind({
    Name = "Quét thủ công",
    CurrentKeybind = "V",
    HoldToInteract = false,
    Flag = "PhimQuet",
    Callback = function()
        if ctx.dangBan then
            Rayfield:Notify({
                Title = "Đang bận",
                Content = "Đang chờ sequence hoàn thành...",
                Duration = 2
            })
            return
        end
        chaySequence()
        Rayfield:Notify({
            Title = "Quét thủ công",
            Content = "Đã thực hiện!",
            Duration = 2
        })
    end,
})

--// ═══ GIAO DIỆN: TAB CẤU HÌNH ═══
local TabCauHinh = Window:CreateTab("Cấu hình", "settings")

local mucChinh = TabCauHinh:CreateSection("Cài đặt chính")

TabCauHinh:CreateToggle({
    Name = "Tự động ghép nuke (Quét → Nhặt → Ghép)",
    CurrentValue = false,
    Flag = "TuDongSequence",
    Callback = function(giaTri)
        ctx.tuDongSequence = giaTri
        ctx.dangBan = false
        ctx.thoiDiemBan = 0
        if giaTri then
            capNhatTrangThai("TỰ ĐỘNG BẬT", "check-circle", Color3.fromRGB(0, 255, 0))
            ghiLog("▶ TỰ ĐỘNG GHÉP NUKED BẬT")
        else
            capNhatTrangThai("TẠM DỪNG", "pause-circle", Color3.fromRGB(255, 255, 0))
            ghiLog("⏸ TỰ ĐỘNG GHÉP NUKED TẠM DỪNG")
        end
    end,
})

TabCauHinh:CreateSlider({
    Name = "Tốc độ quét",
    Range = {0.05, 2.0},
    Increment = 0.05,
    Suffix = " giây",
    CurrentValue = CAU_HINH.THOIGIAN_QUET,
    Flag = "TocDoQuet",
    Callback = function(v) CAU_HINH.THOIGIAN_QUET = v end,
})

TabCauHinh:CreateSlider({
    Name = "Phạm vi nhặt nuke",
    Range = {10, 300},
    Increment = 10,
    Suffix = " studs",
    CurrentValue = CAU_HINH.BAN_KINH_QUET,
    Flag = "PhamViQuet",
    Callback = function(v) CAU_HINH.BAN_KINH_QUET = v end,
})

TabCauHinh:CreateSlider({
    Name = "Thời gian giữ tối đa",
    Range = {0.5, 10.0},
    Increment = 0.5,
    Suffix = " giây",
    CurrentValue = CAU_HINH.TIMEOUT_GIU,
    Flag = "TimeoutGiu",
    Callback = function(v) CAU_HINH.TIMEOUT_GIU = v end,
})

TabCauHinh:CreateDivider()

local mucTuyChon = TabCauHinh:CreateSection("Tùy chọn bổ sung")

TabCauHinh:CreateToggle({
    Name = "Chống AFK tự động",
    CurrentValue = CAU_HINH.ANTI_AFK,
    Flag = "AntiAFK",
    Callback = function(v)
        CAU_HINH.ANTI_AFK = v
        ghiLog(v and "🛡️ Chống AFK BẬT" or "🛡️ Chống AFK TẮT")
    end,
})

TabCauHinh:CreateToggle({
    Name = "Hiện nuke trên màn hình (ESP)",
    CurrentValue = false,
    Flag = "HienESP",
    Callback = function(v)
        CAU_HINH.HIEN_ESP = v
        if not v then xoaESP() end
        ghiLog(v and "👁️ ESP BẬT" or "👁️ ESP TẮT")
    end,
})

TabCauHinh:CreateToggle({
    Name = "Thời gian ngẫu nhiên (chống phát hiện)",
    CurrentValue = CAU_HINH.TRE_NGAU_NHIEN,
    Flag = "TreNgauNhien",
    Callback = function(v)
        CAU_HINH.TRE_NGAU_NHIEN = v
        ghiLog(v and "🎲 Trễ ngẫu nhiên BẬT" or "🎲 Trễ ngẫu nhiên TẮT")
    end,
})

TabCauHinh:CreateToggle({
    Name = "Chế độ debug (hiện log chi tiết)",
    CurrentValue = false,
    Flag = "DebugMode",
    Callback = function(v)
        CAU_HINH.CHE_DO_DEBUG = v
        ghiLog(v and "🐛 Debug BẬT" or "🐛 Debug TẮT")
    end,
})

TabCauHinh:CreateDivider()

local mucHanhDong = TabCauHinh:CreateSection("Hành động nhanh")

TabCauHinh:CreateButton({
    Name = "⚡ Quét ngay",
    Callback = function()
        if ctx.dangBan then
            Rayfield:Notify({
                Title = "Đang bận",
                Content = "Đang chờ sequence...",
                Duration = 2
            })
            return
        end
        chaySequence()
        Rayfield:Notify({
            Title = "Quét",
            Content = "Đã thực hiện!",
            Duration = 2
        })
    end,
})

TabCauHinh:CreateButton({
    Name = "🔄 Đặt lại thống kê",
    Callback = function()
        ctx.soLanQuet = 0
        ctx.soLanNhat = 0
        ctx.soLanGop = 0
        ctx.soLanTha = 0
        ctx.soLanNangCap = 0
        ctx.soLanLoi = 0
        capNhatThongKe()
        ghiLog("📊 Đã đặt lại thống kê")
    end,
})

TabCauHinh:CreateButton({
    Name = "🛑 DỪNG KHẨN CẤP",
    Callback = function()
        ctx.tuDongSequence = false
        ctx.tuDongNangCap = false
        ctx.dangBan = false
        ctx.thoiDiemBan = 0
        ctx.dangGiu = false
        ctx.nukeDangGiu = nil
        ctx.tierDangGiu = nil
        doiTrangThai(TrangThai.NGOI)
        capNhatTrangThai("ĐÃ DỪNG", "alert-circle", Color3.fromRGB(255, 0, 0))
        ghiLog("🛑 DỪNG KHẨN CẤP - mọi thứ đã tắt")
        Rayfield:Notify({
            Title = "DỪNG KHẨN CẤP",
            Content = "Đã dừng toàn bộ!",
            Duration = 3
        })
    end,
})

--// ═══ GIAO DIỆN: TAB NÂNG CẤP ═══
local TabNangCap = Window:CreateTab("Nâng cấp", "trending-up")

local mucMua = TabNangCap:CreateSection("Tự động mua nâng cấp")

local nhanNangCap = TabNangCap:CreateLabel(
    "Nâng cấp tự động: TẮT",
    "circle", Color3.fromRGB(255, 100, 100), false
)

TabNangCap:CreateToggle({
    Name = "Tự động mua TẤT CẢ nâng cấp",
    CurrentValue = false,
    Flag = "TuDongNangCap_TatCa",
    Callback = function(giaTri)
        ctx.tuDongNangCap = giaTri
        if giaTri then
            nhanNangCap:Set("Nâng cấp tự động: BẬT", "check-circle", Color3.fromRGB(0, 255, 0), false)
            chayNangCap()
        else
            nhanNangCap:Set("Nâng cấp tự động: TẮT", "circle", Color3.fromRGB(255, 100, 100), false)
        end
        ghiLog(giaTri and "🛒 Tự động nâng cấp BẬT" or "⏸ Tự động nâng cấp TẮT")
    end,
})

TabNangCap:CreateDivider()
local mucLoai = TabNangCap:CreateSection("Nâng cấp riêng lẻ")

local tenHienThi = {
    TIER     = "Cấp bậc (Tier)",
    LOCKBASE = "Khóa căn cứ",
    MAX      = "Tối đa (Max)",
}

for _, loai in ipairs(CAU_HINH.THU_TU_NANGCAP) do
    local ten = tenHienThi[loai] or loai

    TabNangCap:CreateToggle({
        Name = "Tự động mua: " .. ten,
        CurrentValue = false,
        Flag = "TuDongNangCap_" .. loai,
        Callback = function(giaTri)
            if giaTri then
                muaNangCap(loai)
                ghiLog("🛒 Tự động " .. ten .. " BẬT + mua ngay")
            else
                ghiLog("⏸ Tự động " .. ten .. " TẮT")
            end
        end,
    })
end

TabNangCap:CreateDivider()
local mucMuaThuCong = TabNangCap:CreateSection("Mua thủ công")

for _, loai in ipairs(CAU_HINH.THU_TU_NANGCAP) do
    local ten = tenHienThi[loai] or loai

    TabNangCap:CreateButton({
        Name = "🛒 Mua " .. ten,
        Callback = function() muaNangCap(loai) end,
    })
end

--// ═══ GIAO DIỆN: TAB THỐNG KÊ ═══
local TabThongKe = Window:CreateTab("Thống kê", "bar-chart")

local doanThongKe = TabThongKe:CreateParagraph({
    Title = "Thống kê chi tiết",
    Content = "Đang tải..."
})

TabThongKe:CreateButton({
    Name = "🔄 Đặt lại thống kê",
    Callback = function()
        ctx.soLanQuet = 0
        ctx.soLanNhat = 0
        ctx.soLanGop = 0
        ctx.soLanTha = 0
        ctx.soLanNangCap = 0
        ctx.soLanLoi = 0
        ghiLog("📊 Đã đặt lại thống kê")
    end,
})

--// ═══ GIAO DIỆN: TAB NHẬT KÝ ═══
local TabNhatKy = Window:CreateTab("Nhật ký", "file-text")

local mucNhatKy = TabNhatKy:CreateSection("Lịch sử hoạt động")

local doanNhatKy = TabNhatKy:CreateParagraph({
    Title = "Nhật ký",
    Content = "Đang chờ hành động..."
})

TabNhatKy:CreateButton({
    Name = "🗑️ Xóa nhật ký",
    Callback = function()
        noiDungLog = "Đã xóa nhật ký."
        pcall(function()
            doanLog:Set({
                Title = "Nhật ký hoạt động",
                Content = noiDungLog
            })
        end)
    end,
})

--// ═══ VÒNG LẶP CHÍNH (Heartbeat) ═══

local boDemCapNhatESP = 0

RunService.Heartbeat:Connect(function()
    local bayGio = os.clock()

    -- ═══ TIMEOUT GIỮ NUKE → THẢ ═══
    if ctx.dangGiu then
        if bayGio - ctx.thoiDiemGiu >= CAU_HINH.TIMEOUT_GIU then
            hanhDongTha("giữ quá lâu " .. CAU_HINH.TIMEOUT_GIU .. " giây")
        end
    end

    -- ═══ AN TOÀN BUSY: Reset nếu bị kẹt ═══
    if ctx.dangBan and ctx.thoiDiemBan > 0 then
        if bayGio - ctx.thoiDiemBan > CAU_HINH.TIMEOUT_BUSY then
            ghiLog("⚠️ Reset an toàn busy (" .. CAU_HINH.TIMEOUT_BUSY .. "s)")
            ctx.dangBan = false
            ctx.thoiDiemBan = 0
            ctx.dangGiu = false
            doiTrangThai(TrangThai.NGOI)
        end
    end

    -- ═══ TỰ ĐỘNG GHÉP NUKE ═══
    if ctx.tuDongSequence then
        if bayGio - ctx.lanQuetCuoi >= CAU_HINH.THOIGIAN_QUET then
            ctx.lanQuetCuoi = bayGio
            ctx.soLanQuet = ctx.soLanQuet + 1
            chaySequence()

            -- Cập nhật thống kê mỗi 20 lần quét
            if ctx.soLanQuet % 20 == 0 then
                capNhatThongKe()
            end
        end
    end

    -- ═══ TỰ ĐỘNG NÂNG CẤP ═══
    if ctx.tuDongNangCap then
        if bayGio - ctx.lanNangCapCuoi >= CAU_HINH.THOIGIAN_NANGCAP then
            ctx.lanNangCapCuoi = bayGio
            chayNangCap()
        end
    end

    -- ═══ CẬP NHẬT ESP ═══
    if CAU_HINH.HIEN_ESP then
        boDemCapNhatESP = boDemCapNhatESP + 1
        if boDemCapNhatESP >= 10 then
            boDemCapNhatESP = 0
            capNhatESP()
        end
    end

    -- ═══ CẬP NHẬT THỐNG KÊ CHI TIẾT (mỗi ~3 giây) ═══
    if ctx.soLanQuet % 20 == 0 then
        pcall(function()
            doanThongKe:Set({
                Title = "Thống kê chi tiết",
                Content = string.format(
                    "Lần quét: %d\n" ..
                    "Lần nhặt: %d\n" ..
                    "Lần ghép: %d\n" ..
                    "Lần thả: %d\n" ..
                    "Lần nâng cấp: %d\n" ..
                    "Lỗi: %d\n" ..
                    "─────────────\n" ..
                    "Trạng thái: %s\n" ..
                    "Đang giữ: %s\n" ..
                    "Đang bận: %s\n" ..
                    "Nuke đang giữ: %s\n" ..
                    "Tier: %s",
                    ctx.soLanQuet, ctx.soLanNhat, ctx.soLanGop,
                    ctx.soLanTha, ctx.soLanNangCap, ctx.soLanLoi,
                    ctx.trangThai,
                    ctx.dangGiu and "CÓ" or "KHÔNG",
                    ctx.dangBan and "CÓ" or "KHÔNG",
                    ctx.nukeDangGiu and tostring(laySoNuke(ctx.nukeDangGiu)) or "—",
                    ctx.tierDangGiu and tostring(ctx.tierDangGiu) or "—"
                )
            })
        end)
    end
end)

--// ═══ KHỞI ĐỘNG ═══

pcall(function() Rayfield:LoadConfiguration() end)

-- Đồng bộ cờ từ Rayfield → biến cục bộ
local function dongBoCo()
    local flags = Rayfield.Flags
    if not flags then return end

    local seqVal = flags["TuDongSequence"]
    if type(seqVal) == "boolean" then
        ctx.tuDongSequence = seqVal
    elseif type(seqVal) == "table" and seqVal.Value ~= nil then
        ctx.tuDongSequence = seqVal.Value
    end

    local upgVal = flags["TuDongNangCap_TatCa"]
    if type(upgVal) == "boolean" then
        ctx.tuDongNangCap = upgVal
    elseif type(upgVal) == "table" and upgVal.Value ~= nil then
        ctx.tuDongNangCap = upgVal.Value
    end

    if ctx.tuDongSequence then
        capNhatTrangThai("TỰ ĐỘNG BẬT", "check-circle", Color3.fromRGB(0, 255, 0))
    end
    if ctx.tuDongNangCap then
        nhanNangCap:Set("Nâng cấp tự động: BẬT", "check-circle", Color3.fromRGB(0, 255, 0), false)
    end
end

dongBoCo()

-- Nhật ký khởi động
ghiLog("═══════════════════════════")
ghiLog("SLIM HUB v3.0 - Nuke Merge")
ghiLog("═══════════════════════════")
ghiLog("Vòng lặp: Quét → Nhặt → Ghép")
ghiLog("Không có cặp → Thả → Tiếp tục")
ghiLog("An toàn busy: " .. CAU_HINH.TIMEOUT_BUSY .. "s tự reset")
ghiLog("Chống AFK: " .. (CAU_HINH.ANTI_AFK and "BẬT" or "TẮT"))
ghiLog("Trễ ngẫu nhiên: " .. (CAU_HINH.TRE_NGAU_NHIEN and "BẬT" or "TẮT"))
ghiLog("Nhấn K (giao diện) / V (quét)")

Rayfield:Notify({
    Title = "SLIM HUB v3.0 đã tải!",
    Content = "Tích hợp logic nâng cao | ESP, Anti-AFK, Chống phát hiện",
    Duration = 6
})

print("[SlimHub v3.0] Đã sẵn sàng ✅")
