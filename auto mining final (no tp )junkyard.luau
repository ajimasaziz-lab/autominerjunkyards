-- Auto Miner (F-only + deteksi tombol Mine / Stop Mining) + JALAN KAKI DENGAN KALKULASI RUTE
-- Perubahan versi ini:
--  * BARU: rute ke target (ore & drop) sekarang juga menghindari monster Kettle Beetle & Critter Goblin.
--      - Rute yang lewat dalam jarak ROUTE_MONSTER_CLEARANCE (50 stud) dari monster DITOLAK.
--      - Bot mencoba rute memutar lewat titik di sekeliling monster.
--      - Kalau semua rute terhalang monster: tunggu sebentar, hitung ulang.
--      - Saat berjalan, monster dipantau terus: kalau mendekati rute di depan -> berhenti & hitung ulang rute.
--      - Centang di menu "MONSTER DIHINDARI" tetap berlaku (tidak dicentang = tidak dihindari di rute).
--  * BARU: kalau muncul teks "Inventory Full", waktu tunggu ambil drop dipersingkat jadi setengahnya.
--  * FIX: lompat-lompat di tempat sebelum sampai target (selesai begitu sudah dalam jangkauan, lompat tidak beruntun/di udara,
--    titik rute dilewati kalau titik berikutnya sudah dekat, geser sedikit saat nyangkut sebelum hitung ulang rute).
--  * FIX: tidak mau turun dari tebing -> kalau tidak ada rute, karakter mencari tepi yang aman lalu melangkah turun
--    (maks MAX_FALL stud, hanya ke titik yang punya rute ke target).
--  * BARU: tombol RESET HITUNGAN (ketuk 2x) untuk mengosongkan hitungan Gold Veined Quartz (+ Ore & Drop).
--  * SEMUA teleport / noclip / anchor / jalan bawah tanah / meluncur menembus objek DIHAPUS.
--  * Menuju target mining (dan drop) dengan:
--      1. Cari beberapa titik pijakan di sekitar target (di tanah, dalam jarak "Jarak ke ore").
--      2. Hitung rute dengan PathfindingService (dinding tidak bisa dilewati -> otomatis cari jalan lain,
--         gundukan kecil <= WALL_HEIGHT tetap boleh dilompati, air dihindari).
--      3. Rute DIVERIFIKASI ulang dengan raycast (dinding / lubang dalam / monster).
--      4. Rute terbaik ditandai GARIS HIJAU, baru karakter berjalan mengikuti garis itu
--         dengan menekan tombol WASD (relatif kamera) + Space untuk lompat, seperti main biasa.
--      5. Nyangkut -> lompat (Space) -> hitung ulang rute (maks MAX_REPATH kali).
--      6. Kalau tidak ada rute yang bisa dicapai -> ore itu di-skip, lanjut ke target berikutnya.
--  * Auto respawn: kalau mati, tunggu tombol Respawn aktif -> klik -> lanjut mining lagi.
--  * Bertahan saat disconnect: pengaturan disimpan ke file, auto START lagi, auto rejoin + muat ulang script.
-- Tombol UI atau 0 = start/stop | X = mark + skip SP ini | End = matikan script

local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer

-- ==========================================================
-- PENGATURAN
-- ==========================================================
local HOLD_TIME = 0.05          -- lama tombol F ditahan
local CLICK_GAP = 0.15          -- jeda antar tekan F di satu ore
local EMPTY_WAIT = 2            -- jeda scan ulang saat tidak ada ore
local SKIP_TIME = 30            -- ore yang tidak habis dilewati selama ini (detik)
local PLAYER_RADIUS = 200       -- ore dilewati jika ada pemain lain sejauh ini (stud). 0 = matikan
local SHOW_RADIUS = true        -- bola radius di sekitar karaktermu (hanya terlihat olehmu)
local SHOW_PLAYERS = true       -- tandai pemain lain dalam radius
local SHOW_TARGET = true        -- tandai ore yang sedang ditambang
local CAMERA_MAX_ZOOM = 150     -- batas zoom out kamera (stud). nil = ikut aturan game

-- Perjalanan (jalan kaki + kalkulasi rute)
local SHOW_PATH = true                          -- tampilkan garis hijau rute
local PATH_COLOR = Color3.fromRGB(0, 255, 70)   -- warna garis rute
local AGENT_RADIUS = 2.5        -- lebar karakter untuk perhitungan rute (stud)
local AGENT_HEIGHT = 5          -- tinggi karakter untuk perhitungan rute (stud)
local WAYPOINT_SPACING = 4      -- jarak antar titik rute (stud)
local WALL_HEIGHT = 5           -- penghalang setinggi ini atau lebih = dinding. Lebih pendek = gundukan, boleh dilompati
local MAX_DROP = 10             -- lubang/jurang lebih dalam dari ini (stud) = tidak boleh dilewati
local DROP_DOWN_ENABLED = true  -- kalau tidak ada rute turun (mis. di atas tebing): turun dengan melangkah dari tepi tebing
local MAX_FALL = 30             -- tinggi maksimal yang boleh dilompati turun (stud). Kecilkan kalau game ada damage jatuh
local MAX_DROPDOWN_TRIES = 3    -- maks percobaan turun per perjalanan
local MAX_CANDIDATES = 6        -- maks titik pijakan di dekat target yang dicoba hitung rutenya
local MAX_REPATH = 3            -- maks hitung ulang rute kalau nyangkut
local STUCK_TIME = 2            -- diam sekian detik = dianggap nyangkut
local WAYPOINT_TIMEOUT = 7      -- batas waktu menuju satu titik rute (dtk)
local WALK_TIMEOUT = 120        -- batas total waktu jalan ke satu target (dtk)
local UNREACHABLE_SKIP = 90     -- ore yang tidak bisa dicapai di-skip selama ini (dtk)
local ARRIVE_TOLERANCE = 3      -- toleransi jarak dianggap sudah sampai (stud, di atas "Jarak ke ore")
local ORE_ARRIVE_TOLERANCE = 1  -- toleransi khusus saat menuju ore (lebih ketat supaya benar-benar dekat)
local FINAL_ARRIVE_RADIUS = 1.8 -- titik rute TERAKHIR dianggap sampai kalau sudah sedekat ini (stud)
local PROMPT_MARGIN = 2.5       -- berdiri minimal sedekat (jarak aktif tombol Mine - ini) dari ore
local MIN_REACH = 2             -- jarak terdekat yang dicoba saat mendekat lagi (stud)
local MAX_CLOSER = 3            -- maks berapa kali mendekat lagi kalau tombol Mine belum muncul
local GROUND_SCAN = 150         -- jarak raycast ke bawah untuk cari tanah (stud)
local KEY_FALLBACK_AFTER = 0.8  -- WASD tidak menggerakkan karakter selama ini (dtk) -> pakai MoveTo sebagai cadangan
local KEY_RESEND = 0.4           -- kirim ulang tombol yang sedang ditahan tiap sekian detik (jaga-jaga event hilang)
local CAMERA_FOLLOW = true      -- saat berjalan, kamera diputar halus ke arah tujuan
local CAMERA_TURN_SPEED = 4     -- kehalusan putar kamera (makin besar = makin cepat menyusul)
local CAMERA_MAX_TURN = 160     -- batas kecepatan putar kamera (derajat/detik)

-- Hindari monster di sepanjang rute
local ROUTE_AVOID_MONSTERS = { "Kettle Beetle", "Critter Goblin" } -- monster yang dihindari di rute
local ROUTE_MONSTER_CLEARANCE = 50   -- rute harus menjauh minimal segini dari monster (stud)
local ROUTE_DETOUR_EXTRA = 10        -- tambahan jarak titik belok saat memutar menghindari monster (stud)
local MAX_DETOURS = 4                -- maks titik belok yang dicoba per target
local MONSTER_LOOKAHEAD = 50         -- saat berjalan, cek monster pada rute sejauh ini ke depan (stud)
local MONSTER_CHECK_INTERVAL = 0.4   -- seberapa sering cek monster saat berjalan (dtk)
local MAX_MONSTER_REPATH = 8         -- maks hitung ulang rute karena monster mendekat
local MONSTER_WAIT_TRIES = 3         -- kalau semua rute terhalang monster: tunggu & coba lagi sekian kali
local MONSTER_WAIT_TIME = 2          -- lama tiap tunggu (dtk)
local routeAvoidSet = {}
for _, n in ipairs(ROUTE_AVOID_MONSTERS) do
    routeAvoidSet[n] = true
end

-- Auto respawn
local AUTO_RESPAWN = true       -- true = kalau mati, tunggu tombol Respawn aktif, klik, lalu lanjut mining
local RESPAWN_RETRY = 1.5       -- jeda antar klik Respawn kalau belum hidup (dtk)
local RESPAWN_MAX_WAIT = 90     -- kalau tombol tetap dianggap belum siap selama ini, tetap coba klik (dtk)
local RESPAWN_SETTLE = 1.5      -- jeda setelah hidup lagi sebelum lanjut mining (dtk)
local RESPAWN_PRESS_Q = true   -- tekan Q satu kali setelah respawn
local RESPAWN_Q_DELAY = 3       -- Q ditekan sekian detik setelah karakter hidup lagi (dtk)

-- Bertahan saat disconnect / rejoin
local AUTO_REJOIN = true        -- kalau terputus (disconnect/kick) saat miner ON: rejoin otomatis
local REJOIN_DELAY = 3          -- jeda sebelum mencoba rejoin (dtk)
local REJOIN_RETRY = 15         -- jeda antar percobaan rejoin kalau gagal (dtk)
local REJOIN_MAX_TRIES = 20     -- maks percobaan rejoin
local AUTO_RESUME = true        -- setelah script jalan lagi, otomatis START kalau sebelumnya masih ON
local RESUME_DELAY = 5          -- jeda setelah map & karakter siap sebelum START otomatis (dtk)
local SAVE_FILE = "AutoMinerState.json"  -- file penyimpan pengaturan (di folder workspace executor)
-- Cara script dimuat ulang setelah pindah server. Pilih salah satu:
--   a) simpan script ini sebagai SCRIPT_FILE di folder workspace executor (butuh readfile), atau
--   b) isi SCRIPT_URL dengan link raw script ini (dijalankan lewat loadstring(game:HttpGet(url)))
local SCRIPT_FILE = "auto_miner.lua"
local SCRIPT_URL = nil

-- Ambil drop
local PICKUP_ENABLED = true             -- true = ambil drop setelah ore hilang
local PICKUP_USE_REMOTE = true          -- true = lewat RequestPickupItem, false = klik item di layar
local PICKUP_RETRY = 1                  -- kirim ulang permintaan pickup tiap sekian detik
local PICKUP_MAX_TRY = 5                -- percobaan remote per item dalam satu ronde
local PICKUP_RADIUS = 25                -- cari drop sejauh ini dari posisi ore (stud)
local PICKUP_PART_NAME = nil            -- nama PrimaryPart item, mis. "Mat_StoneMesh". nil = SEMUA item (disarankan)
local PICKUP_CLICKS = 2                 -- klik cadangan per item
local PICKUP_DISTANCE = 4               -- jarak berdiri dari item saat mengambil (stud)
local DROP_GRACE = 1.5                  -- drop harus kosong selama ini (dtk) sebelum dianggap selesai
local DROP_MAX_WAIT = 20                -- batas total menunggu semua drop terambil (dtk), lalu lanjut

-- Inventory penuh: kalau muncul teks "Inventory Full", waktu tunggu ambil drop dipersingkat
local INVENTORY_FULL_TEXT = "Inventory Full"  -- teks yang dicari di layar (huruf besar/kecil & spasi diabaikan)
local INVENTORY_FULL_FACTOR = 0.5       -- pengali waktu tunggu drop saat inventory penuh (0.5 = setengahnya)
local INVENTORY_FULL_HOLD = 6           -- mode singkat bertahan sekian detik sejak teks terakhir terlihat (dtk)

-- Retry mining kalau ore tidak hilang setelah tekan F
local RETRY_AFTER = 4                   -- (cadangan, kalau tombol tidak terdeteksi) ore masih ada sekian detik: jalan ulang + tekan F lagi
local MAX_RETRY = 4                     -- maksimal percobaan cadangan per ore sebelum dilewati

-- Deteksi tombol Mine / Stop Mining
local MINE_CONFIRM_TIME = 8             -- maks detik mencoba sampai tombol berubah jadi "Stop Mining"
local MINE_CHECK_DELAY = 0.6            -- jeda setelah tekan F sebelum cek tombol lagi

-- Penghitung item
local COUNT_ITEM_NAME = "Gold Veined Quartz"  -- nama item yang dihitung
local DEBUG_ITEMS = false               -- true = cetak info tiap drop ke console
local RESET_ALSO_ORE_DROP = true        -- true = tombol reset juga mengosongkan hitungan Ore & Drop (false = hanya item di atas)

-- Jenis ore prioritas rendah: ditambang hanya kalau tidak ada jenis lain
local LOW_PRIORITY_TYPES = { "Stone" }

-- Timeout khusus per jenis ore (detik)
local TYPE_TIMEOUTS = {
    Aurorite = 25,
}

-- Monster yang dihindari
local MONSTER_RADIUS = 60               -- jarak (stud) dari ore untuk mendeteksi monster. 0 = matikan fitur
local MONSTER_NAMES = { "Kettle Beetle", "Critter Goblin", "Patch Hound", "Scarecrow Goblin" }
local avoidMonster = {}
for _, monsterName in ipairs(MONSTER_NAMES) do
    avoidMonster[monsterName] = true
end

-- Matikan versi lama jika script dijalankan ulang
if _G.StopAutoMiner then
    _G.StopAutoMiner(true) -- true = jangan timpa file simpanan
end

local isActive = false
local isAlive = true
local connections = {}
local skipped = {}
local currentTarget = nil
local inCooldown = false
local respawning = false
local saveState = function() end -- diisi di bagian PERSISTENSI
local settings = {}
local isTouchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local radiusBall = nil -- diisi di bagian VISUAL RADIUS (dideklarasikan di sini agar bisa dipakai raycast)

-- ==========================================================
-- UI
-- ==========================================================
local THEME = {
    bg = Color3.fromRGB(28, 29, 35),
    header = Color3.fromRGB(38, 40, 48),
    field = Color3.fromRGB(44, 46, 56),
    text = Color3.fromRGB(235, 235, 240),
    muted = Color3.fromRGB(150, 153, 165),
    green = Color3.fromRGB(46, 160, 90),
    red = Color3.fromRGB(190, 60, 60),
    orange = Color3.fromRGB(210, 140, 40),
    blue = Color3.fromRGB(70, 120, 210),
    grey = Color3.fromRGB(90, 93, 105),
}

local function getGuiParent()
    local ok, hidden = pcall(function()
        return gethui and gethui()
    end)
    if ok and hidden then
        return hidden
    end
    return CoreGui
end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoMinerUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = getGuiParent()

local frame = Instance.new("Frame")
frame.Name = "Window"
frame.Size = UDim2.fromOffset(190, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.Position = UDim2.fromOffset(30, 100)
frame.BackgroundColor3 = THEME.bg
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(60, 62, 74)
frameStroke.Thickness = 1
frameStroke.Parent = frame

local frameLayout = Instance.new("UIListLayout")
frameLayout.SortOrder = Enum.SortOrder.LayoutOrder
frameLayout.Parent = frame

-- Header (bisa di-drag)
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 26)
header.BackgroundColor3 = THEME.header
header.BorderSizePixel = 0
header.LayoutOrder = 1
header.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -104, 1, 0)
title.Position = UDim2.fromOffset(8, 0)
title.BackgroundTransparency = 1
title.Text = "AUTO MINER"
title.TextColor3 = THEME.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function createHeaderButton(offsetFromRight, text, color, width)
    width = width or 18
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(width, 18)
    button.Position = UDim2.new(1, -offsetFromRight, 0.5, -9)
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Text = text
    button.TextColor3 = THEME.text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.Parent = header
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    return button
end

local exitButton = createHeaderButton(24, "X", THEME.red)
local minimizeButton = createHeaderButton(46, "-", THEME.grey)
-- Tombol START/STOP di header: tetap terlihat saat window di-minimize
local headerToggle = createHeaderButton(96, "START", THEME.green, 46)

-- Isi window
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 0, 0)
content.AutomaticSize = Enum.AutomaticSize.Y
content.BackgroundTransparency = 1
content.LayoutOrder = 3
content.Parent = frame

local contentPadding = Instance.new("UIPadding")
contentPadding.PaddingTop = UDim.new(0, 5)
contentPadding.PaddingBottom = UDim.new(0, 6)
contentPadding.PaddingLeft = UDim.new(0, 6)
contentPadding.PaddingRight = UDim.new(0, 6)
contentPadding.Parent = content

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 4)
contentLayout.Parent = content

local nextOrder = 0
local function order()
    nextOrder += 1
    return nextOrder
end

local function styleBox(box)
    box.BackgroundColor3 = THEME.field
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.TextColor3 = THEME.text
    box.PlaceholderColor3 = THEME.muted
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
end

local function createRow(labelText, defaultText)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order()
    row.Parent = content

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, -6, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = THEME.muted
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.4, 0, 1, 0)
    box.Position = UDim2.fromScale(0.6, 0)
    box.Text = defaultText
    box.Parent = row
    styleBox(box)
    return box
end

local function createButton(text, color, height)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, height or 24)
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = THEME.text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.LayoutOrder = order()
    button.Parent = content
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    return button
end

local inputClicks = createRow("Tekan F (cadangan)", "1")
local inputWait = createRow("Timeout ore (dtk)", "20")
local inputReach = createRow("Jarak ke ore (stud)", "5")

local ignoreCaption = Instance.new("TextLabel")
ignoreCaption.Size = UDim2.new(1, 0, 0, 12)
ignoreCaption.BackgroundTransparency = 1
ignoreCaption.Text = "SP di-skip (pisah koma)"
ignoreCaption.TextColor3 = THEME.muted
ignoreCaption.Font = Enum.Font.Gotham
ignoreCaption.TextSize = 11
ignoreCaption.TextXAlignment = Enum.TextXAlignment.Left
ignoreCaption.LayoutOrder = order()
ignoreCaption.Parent = content

local inputIgnore = Instance.new("TextBox")
inputIgnore.Size = UDim2.new(1, 0, 0, 22)
inputIgnore.Text = "SP47"
inputIgnore.PlaceholderText = "SP3, SP12"
inputIgnore.TextTruncate = Enum.TextTruncate.AtEnd
inputIgnore.TextXAlignment = Enum.TextXAlignment.Left
inputIgnore.LayoutOrder = order()
inputIgnore.Parent = content
styleBox(inputIgnore)
inputIgnore.TextColor3 = Color3.fromRGB(255, 175, 120)
Instance.new("UIPadding", inputIgnore).PaddingLeft = UDim.new(0, 8)

local toggleButton = createButton("START", THEME.green, 26)
local markButton = createButton("MARK + SKIP (X)", THEME.orange, 22)
local monsterButton = createButton("MONSTER DIHINDARI >", THEME.blue, 22)
local RESET_TEXT = "RESET HITUNGAN"
local resetButton = createButton(RESET_TEXT, THEME.grey, 22)

-- Popup menu centang monster
local POPUP_WIDTH = 170
local monsterRefresh = {}
local monsterPopup = Instance.new("Frame")
monsterPopup.Name = "MonsterPopup"
monsterPopup.Size = UDim2.fromOffset(POPUP_WIDTH, 0)
monsterPopup.AutomaticSize = Enum.AutomaticSize.Y
monsterPopup.BackgroundColor3 = THEME.bg
monsterPopup.BorderSizePixel = 0
monsterPopup.Visible = false
monsterPopup.Parent = gui
Instance.new("UICorner", monsterPopup).CornerRadius = UDim.new(0, 8)

local popupStroke = Instance.new("UIStroke")
popupStroke.Color = Color3.fromRGB(60, 62, 74)
popupStroke.Thickness = 1
popupStroke.Parent = monsterPopup

local popupPadding = Instance.new("UIPadding")
popupPadding.PaddingTop = UDim.new(0, 6)
popupPadding.PaddingBottom = UDim.new(0, 6)
popupPadding.PaddingLeft = UDim.new(0, 6)
popupPadding.PaddingRight = UDim.new(0, 6)
popupPadding.Parent = monsterPopup

local popupLayout = Instance.new("UIListLayout")
popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
popupLayout.Padding = UDim.new(0, 4)
popupLayout.Parent = monsterPopup

local popupTitle = Instance.new("TextLabel")
popupTitle.Size = UDim2.new(1, 0, 0, 28)
popupTitle.BackgroundTransparency = 1
popupTitle.Text = "Hindari ore jika ada monster ini di dekatnya"
popupTitle.TextColor3 = THEME.muted
popupTitle.Font = Enum.Font.Gotham
popupTitle.TextSize = 11
popupTitle.TextWrapped = true
popupTitle.TextXAlignment = Enum.TextXAlignment.Left
popupTitle.TextYAlignment = Enum.TextYAlignment.Top
popupTitle.LayoutOrder = 0
popupTitle.Parent = monsterPopup

for index, monsterName in ipairs(MONSTER_NAMES) do
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BackgroundColor3 = THEME.field
    row.BorderSizePixel = 0
    row.AutoButtonColor = true
    row.Text = ""
    row.LayoutOrder = index
    row.Parent = monsterPopup
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local checkBox = Instance.new("Frame")
    checkBox.Size = UDim2.fromOffset(14, 14)
    checkBox.Position = UDim2.new(0, 6, 0.5, -7)
    checkBox.BorderSizePixel = 0
    checkBox.Parent = row
    Instance.new("UICorner", checkBox).CornerRadius = UDim.new(0, 4)

    local rowLabel = Instance.new("TextLabel")
    rowLabel.Size = UDim2.new(1, -30, 1, 0)
    rowLabel.Position = UDim2.fromOffset(26, 0)
    rowLabel.BackgroundTransparency = 1
    rowLabel.Text = monsterName
    rowLabel.TextColor3 = THEME.text
    rowLabel.Font = Enum.Font.Gotham
    rowLabel.TextSize = 11
    rowLabel.TextXAlignment = Enum.TextXAlignment.Left
    rowLabel.Parent = row

    local function refresh()
        checkBox.BackgroundColor3 = avoidMonster[monsterName] and THEME.green or THEME.grey
    end
    refresh()
    monsterRefresh[monsterName] = refresh

    table.insert(connections, row.Activated:Connect(function()
        avoidMonster[monsterName] = not avoidMonster[monsterName]
        refresh()
    end))
end

table.insert(connections, monsterButton.Activated:Connect(function()
    monsterPopup.Visible = not monsterPopup.Visible
    monsterButton.Text = monsterPopup.Visible and "MONSTER DIHINDARI <" or "MONSTER DIHINDARI >"
end))

table.insert(connections, RunService.Heartbeat:Connect(function()
    if not monsterPopup.Visible then
        return
    end
    local position = frame.AbsolutePosition
    local x = position.X + frame.AbsoluteSize.X + 6
    if x + POPUP_WIDTH > gui.AbsoluteSize.X then
        x = math.max(position.X - POPUP_WIDTH - 6, 0)
    end
    monsterPopup.Position = UDim2.fromOffset(x, position.Y)
end))

-- Penghitung
local counterLabel = Instance.new("TextLabel")
counterLabel.Size = UDim2.new(1, 0, 0, 0)
counterLabel.AutomaticSize = Enum.AutomaticSize.Y
counterLabel.BackgroundColor3 = THEME.header
counterLabel.BorderSizePixel = 0
counterLabel.Text = ""
counterLabel.TextColor3 = Color3.fromRGB(255, 214, 110)
counterLabel.Font = Enum.Font.GothamBold
counterLabel.TextSize = 11
counterLabel.TextWrapped = true
counterLabel.TextXAlignment = Enum.TextXAlignment.Left
counterLabel.LayoutOrder = 2
counterLabel.Parent = frame
Instance.new("UICorner", counterLabel).CornerRadius = UDim.new(0, 6)
local counterPadding = Instance.new("UIPadding")
counterPadding.PaddingTop = UDim.new(0, 4)
counterPadding.PaddingBottom = UDim.new(0, 4)
counterPadding.PaddingLeft = UDim.new(0, 6)
counterPadding.PaddingRight = UDim.new(0, 6)
counterPadding.Parent = counterLabel

-- Status
local stateLabel = Instance.new("TextLabel")
stateLabel.Size = UDim2.new(1, 0, 0, 20)
stateLabel.BackgroundColor3 = THEME.grey
stateLabel.BorderSizePixel = 0
stateLabel.Text = "STOP"
stateLabel.TextColor3 = THEME.text
stateLabel.Font = Enum.Font.GothamBold
stateLabel.TextSize = 11
stateLabel.LayoutOrder = order()
stateLabel.Parent = content
Instance.new("UICorner", stateLabel).CornerRadius = UDim.new(0, 6)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 0)
statusLabel.AutomaticSize = Enum.AutomaticSize.Y
statusLabel.BackgroundColor3 = THEME.header
statusLabel.BorderSizePixel = 0
statusLabel.Text = "Siap"
statusLabel.TextColor3 = THEME.muted
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.LayoutOrder = order()
statusLabel.Parent = content
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 6)
local statusPadding = Instance.new("UIPadding")
statusPadding.PaddingTop = UDim.new(0, 4)
statusPadding.PaddingBottom = UDim.new(0, 4)
statusPadding.PaddingLeft = UDim.new(0, 6)
statusPadding.PaddingRight = UDim.new(0, 6)
statusPadding.Parent = statusLabel
local statusMin = Instance.new("UISizeConstraint")
statusMin.MinSize = Vector2.new(0, 30)
statusMin.Parent = statusLabel

local function setStatus(text)
    statusLabel.Text = text
end

local function setState(text, color)
    stateLabel.Text = text
    stateLabel.BackgroundColor3 = color
end

local mined, picked, gvqCount = 0, 0, 0
local function updateStats()
    if content.Visible then
        counterLabel.Text = string.format("%s: %d\nOre: %d | Drop: %d", COUNT_ITEM_NAME, gvqCount, mined, picked)
    else
        counterLabel.Text = string.format("%s: %d", COUNT_ITEM_NAME, gvqCount)
    end
end
updateStats()

-- Tombol reset hitungan (ketuk 2x dalam 3 detik supaya tidak kepencet)
do
    local armedAt = 0
    local function disarm()
        armedAt = 0
        resetButton.Text = RESET_TEXT
        resetButton.BackgroundColor3 = THEME.grey
    end

    table.insert(connections, resetButton.Activated:Connect(function()
        local now = os.clock()
        if armedAt > 0 and now - armedAt <= 3 then
            gvqCount = 0
            if RESET_ALSO_ORE_DROP then
                mined, picked = 0, 0
            end
            updateStats()
            saveState()
            disarm()
            setStatus(COUNT_ITEM_NAME .. " di-reset ke 0")
        else
            armedAt = now
            resetButton.Text = "KETUK LAGI UNTUK RESET"
            resetButton.BackgroundColor3 = THEME.red
            task.delay(3, function()
                if armedAt == now then
                    disarm()
                end
            end)
        end
    end))
end

-- Drag window lewat header (mouse & touch)
do
    local dragging, dragStart, startPos = false, nil, nil

    table.insert(connections, header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end))

    table.insert(connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    table.insert(connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

table.insert(connections, minimizeButton.Activated:Connect(function()
    content.Visible = not content.Visible
    minimizeButton.Text = content.Visible and "-" or "+"
    if not content.Visible then
        monsterPopup.Visible = false
        monsterButton.Text = "MONSTER DIHINDARI >"
    end
    updateStats()
end))

-- ==========================================================
-- OVERLAY: ORE YANG DITAMBANG
-- ==========================================================
local targetHighlight = Instance.new("Highlight")
targetHighlight.FillColor = Color3.fromRGB(255, 210, 80)
targetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
targetHighlight.FillTransparency = 0.5
targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
targetHighlight.Enabled = false
targetHighlight.Parent = gui

local targetBillboard = Instance.new("BillboardGui")
targetBillboard.Size = UDim2.new(0, 200, 0, 40)
targetBillboard.StudsOffset = Vector3.new(0, 4, 0)
targetBillboard.AlwaysOnTop = true
targetBillboard.Enabled = false
targetBillboard.Parent = gui

local targetNameLabel = Instance.new("TextLabel")
targetNameLabel.Size = UDim2.new(1, 0, 1, 0)
targetNameLabel.BackgroundTransparency = 1
targetNameLabel.TextColor3 = Color3.fromRGB(255, 220, 110)
targetNameLabel.TextStrokeTransparency = 0.2
targetNameLabel.Font = Enum.Font.GothamBold
targetNameLabel.TextSize = 14
targetNameLabel.Parent = targetBillboard

local function markTarget(entry)
    if not SHOW_TARGET then
        return
    end
    local ore = entry and entry.ore
    targetHighlight.Adornee = ore
    targetHighlight.Enabled = ore ~= nil

    if ore then
        targetBillboard.Adornee = ore:IsA("BasePart") and ore
            or (ore:IsA("Model") and ore.PrimaryPart)
            or ore:FindFirstChildWhichIsA("BasePart", true)
        targetNameLabel.Text = string.format("%s\nOre_%s", entry.name, entry.oreType or "?")
        targetBillboard.Enabled = true
    else
        targetBillboard.Adornee = nil
        targetBillboard.Enabled = false
    end
end

-- ==========================================================
-- SCAN ORE
-- ==========================================================
local function getOreCFrame(ore)
    if ore:IsA("BasePart") then
        return ore.CFrame
    end
    if ore:IsA("Model") then
        if ore.PrimaryPart then
            return ore.PrimaryPart.CFrame
        end
        return (ore:GetBoundingBox())
    end
    return nil
end

local function scanOres()
    local spawnFolder = workspace:FindFirstChild("Maps")
        and workspace.Maps:FindFirstChild("World")
        and workspace.Maps.World:FindFirstChild("Spawn_Ore")

    if not spawnFolder then
        return nil
    end

    local results = {}
    for _, spawnPoint in ipairs(spawnFolder:GetChildren()) do
        for _, oreType in ipairs(spawnPoint:GetChildren()) do
            if oreType.Name:sub(1, 4) == "Ore_" then
                local ore = oreType:FindFirstChild("Ore")
                local cframe = ore and getOreCFrame(ore)
                if cframe then
                    table.insert(results, {
                        name = spawnPoint.Name,
                        oreType = oreType.Name:sub(5),
                        ore = ore,
                        position = cframe.Position,
                    })
                end
            end
        end
    end
    return results
end

local function getNearbyPlayer(position)
    if PLAYER_RADIUS <= 0 then
        return nil
    end
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local otherCharacter = other.Character
            local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
            if otherRoot and (otherRoot.Position - position).Magnitude <= PLAYER_RADIUS then
                return other
            end
        end
    end
    return nil
end

-- Pelacak monster
local monsterKeys = {}
for _, monsterName in ipairs(MONSTER_NAMES) do
    monsterKeys[monsterName] = (monsterName:gsub("[^%w]", "")):lower()
end

local monsterModels = {} -- [model] = nama monster

local function matchMonster(instance)
    if not instance:IsA("Model") or Players:GetPlayerFromCharacter(instance) then
        return nil
    end
    local key = (instance.Name:gsub("[^%w]", "")):lower()
    for _, monsterName in ipairs(MONSTER_NAMES) do
        if key:find(monsterKeys[monsterName], 1, true) then
            return monsterName
        end
    end
    return nil
end

local function trackMonster(instance)
    local monsterName = matchMonster(instance)
    if monsterName then
        monsterModels[instance] = monsterName
    end
end

table.insert(connections, workspace.DescendantAdded:Connect(trackMonster))
table.insert(connections, workspace.DescendantRemoving:Connect(function(instance)
    monsterModels[instance] = nil
end))

task.spawn(function()
    local count = 0
    for _, instance in ipairs(workspace:GetDescendants()) do
        if not isAlive then
            return
        end
        trackMonster(instance)
        count += 1
        if count % 2000 == 0 then
            task.wait()
        end
    end
end)

local function getNearbyMonster(position)
    if MONSTER_RADIUS <= 0 then
        return nil
    end
    for model, monsterName in pairs(monsterModels) do
        if avoidMonster[monsterName] and model.Parent then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if not (humanoid and humanoid.Health <= 0) then
                local ok, pivot = pcall(model.GetPivot, model)
                if ok and (pivot.Position - position).Magnitude <= MONSTER_RADIUS then
                    return monsterName
                end
            end
        end
    end
    return nil
end

local function readIgnoreList()
    local list = {}
    for name in string.gmatch(inputIgnore.Text, "[^,%s]+") do
        if not table.find(list, name) then
            table.insert(list, name)
        end
    end
    return list
end

local function pickNearestOre(results, fromPosition)
    local now = os.clock()
    local ignoreList = readIgnoreList()
    local best, bestDistance = nil, math.huge
    local backup, backupDistance = nil, math.huge
    local stats = { marked = 0, cooldown = 0, player = 0, monster = 0 }

    for _, entry in ipairs(results) do
        local skipUntil = skipped[entry.ore]
        if table.find(ignoreList, entry.name) then
            stats.marked += 1
        elseif skipUntil and now < skipUntil then
            stats.cooldown += 1
        elseif getNearbyPlayer(entry.position) then
            stats.player += 1
        elseif getNearbyMonster(entry.position) then
            stats.monster += 1
        else
            local distance = (entry.position - fromPosition).Magnitude
            if table.find(LOW_PRIORITY_TYPES, entry.oreType) then
                if distance < backupDistance then
                    backup, backupDistance = entry, distance
                end
            elseif distance < bestDistance then
                best, bestDistance = entry, distance
            end
        end
    end
    return best or backup, stats
end

-- ==========================================================
-- FUNGSI DASAR
-- ==========================================================
local function waitFor(seconds)
    local elapsed = 0
    while elapsed < seconds do
        if not isActive or not isAlive then
            return false
        end
        elapsed += task.wait()
    end
    return isActive and isAlive
end

local function clickOnce(x, y)
    if isTouchDevice then
        return pcall(function()
            VirtualInputManager:SendTouchEvent(0, 0, x, y)
            task.wait(HOLD_TIME)
            VirtualInputManager:SendTouchEvent(0, 2, x, y)
        end)
    end
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(HOLD_TIME)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    return true
end

local function pressF()
    return pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(HOLD_TIME)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
end

-- ==========================================================
-- PERJALANAN: KALKULASI RUTE -> GARIS HIJAU -> JALAN KAKI
-- (tanpa teleport, tanpa noclip, tanpa menembus objek)
-- ==========================================================
local travelling = false

local pathFolder = Instance.new("Folder")
pathFolder.Name = "AutoMinerPath"
pathFolder.Parent = workspace

local PATH_PARAMS = {
    AgentRadius = AGENT_RADIUS,
    AgentHeight = AGENT_HEIGHT,
    AgentCanJump = true,
    AgentCanClimb = false,
    WaypointSpacing = WAYPOINT_SPACING,
    Costs = { Water = math.huge }, -- hindari air
}

local function getChar()
    local c = player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if h and r and h.Health > 0 then
        return c, h, r
    end
    return nil
end

local function flatDist(a, b)
    return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function clearPath()
    pathFolder:ClearAllChildren()
end

-- Kontrol gerak lewat tombol WASD (disimulasikan) + Space untuk lompat.
-- Arah W/A/S/D dihitung relatif terhadap kamera, sama seperti kalau kamu menekan tombolnya sendiri.
-- (Di perangkat sentuh tidak ada keyboard, jadi otomatis memakai Humanoid:MoveTo.)
local KEY_CODES = {
    W = Enum.KeyCode.W,
    A = Enum.KeyCode.A,
    S = Enum.KeyCode.S,
    D = Enum.KeyCode.D,
}
local heldKeys = { W = false, A = false, S = false, D = false }
local KEY_THRESHOLD = 0.35

-- Arah tujuan (mendatar) yang sedang diikuti kamera. nil = kamera tidak disentuh.
local camTargetDir = nil
local moveFallback = false -- true = WASD tidak efektif, pakai Humanoid:MoveTo
local lastKeyResend = 0

-- Putar kamera sedikit demi sedikit ke arah tujuan (hanya yaw, jarak & sudut atas-bawah dibiarkan)
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
    local dir = camTargetDir
    if not dir or not CAMERA_FOLLOW or not isActive then
        return
    end
    local camera = workspace.CurrentCamera
    local _, _, root = getChar()
    if not camera or not root then
        return
    end

    local look = camera.CFrame.LookVector
    local currentYaw = math.atan2(-look.X, -look.Z)
    local targetYaw = math.atan2(-dir.X, -dir.Z)
    local diff = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
    if math.abs(diff) < 0.004 then
        return
    end

    local step = diff * math.min(1, dt * CAMERA_TURN_SPEED)
    local maxStep = math.rad(CAMERA_MAX_TURN) * dt
    step = math.clamp(step, -maxStep, maxStep)

    local focus = root.Position
    camera.CFrame = CFrame.new(focus) * CFrame.Angles(0, step, 0) * CFrame.new(-focus) * camera.CFrame
end))

local function setKey(name, down)
    if heldKeys[name] == down then
        return
    end
    heldKeys[name] = down
    pcall(function()
        VirtualInputManager:SendKeyEvent(down, KEY_CODES[name], false, game)
    end)
end

local function releaseMoveKeys()
    for name in pairs(heldKeys) do
        setKey(name, false)
    end
end

local function releaseKeys()
    camTargetDir = nil
    releaseMoveKeys()
end

local lastJumpAt = 0
local function tapJump()
    local now = os.clock()
    if now - lastJumpAt < 0.7 then
        return false -- jangan lompat beruntun
    end
    local c = player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if h and h.FloorMaterial == Enum.Material.Air then
        return false -- masih di udara
    end
    lastJumpAt = now
    if isTouchDevice then
        if h then
            h.Jump = true
        end
        return true
    end
    task.spawn(function()
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.wait(0.08)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
    end)
    return true
end

-- Tekan kombinasi WASD supaya karakter bergerak menuju targetPos
local function steerTo(targetPos, hum, root)
    local camera = workspace.CurrentCamera
    local dir = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
    if not camera or dir.Magnitude < 0.1 then
        releaseKeys()
        return
    end
    dir = dir.Unit
    camTargetDir = dir -- kamera ikut menghadap ke arah tujuan

    if isTouchDevice or moveFallback then
        if moveFallback then
            releaseMoveKeys()
        end
        hum:MoveTo(targetPos)
        return
    end

    -- kirim ulang tombol yang sedang ditahan (kalau event tekan sebelumnya hilang)
    local nowTime = os.clock()
    if nowTime - lastKeyResend > KEY_RESEND then
        lastKeyResend = nowTime
        for name, down in pairs(heldKeys) do
            if down then
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, KEY_CODES[name], false, game)
                end)
            end
        end
    end

    local look = camera.CFrame.LookVector
    local forward = Vector3.new(look.X, 0, look.Z)
    if forward.Magnitude < 0.1 then
        local up = camera.CFrame.UpVector
        forward = Vector3.new(up.X, 0, up.Z)
    end
    forward = forward.Unit
    local right = forward:Cross(Vector3.yAxis)

    local f = dir:Dot(forward)
    local r = dir:Dot(right)

    -- Natural: tidak pernah jalan mundur (tanpa S). Kamera sudah berputar ke arah tujuan,
    -- jadi biasanya cukup W. Kalau tujuan ada di samping/belakang, karakter berbelok dulu
    -- dengan A/D sambil kamera menyusul, lalu maju lagi.
    local wantW = f > KEY_THRESHOLD
    local wantD = r > KEY_THRESHOLD
    local wantA = r < -KEY_THRESHOLD

    if f <= 0 and not wantA and not wantD then
        -- tujuan tepat di belakang: pilih salah satu sisi untuk berbalik
        wantD = true
    end
    if f > 0.9 then
        -- sudah hampir lurus: cukup W saja (tidak zig-zag)
        wantA, wantD = false, false
    end

    setKey("W", wantW)
    setKey("S", false)
    setKey("D", wantD)
    setKey("A", wantA)
end

-- Gambar rute sebagai garis hijau
local function drawPath(waypoints)
    pathFolder:ClearAllChildren()
    if not SHOW_PATH then
        return
    end

    local lift = Vector3.new(0, 0.6, 0)
    for i = 1, #waypoints - 1 do
        local a = waypoints[i].Position + lift
        local b = waypoints[i + 1].Position + lift
        local length = (b - a).Magnitude
        if length > 0.05 then
            local segment = Instance.new("Part")
            segment.Name = "PathSegment"
            segment.Anchored = true
            segment.CanCollide = false
            segment.CanQuery = false
            segment.CanTouch = false
            segment.CastShadow = false
            segment.Material = Enum.Material.Neon
            segment.Color = PATH_COLOR
            segment.Size = Vector3.new(0.35, 0.35, length)
            segment.CFrame = CFrame.lookAt((a + b) / 2, b)
            segment.Parent = pathFolder
        end
    end

    local last = waypoints[#waypoints]
    if last then
        local marker = Instance.new("Part")
        marker.Name = "PathEnd"
        marker.Shape = Enum.PartType.Ball
        marker.Anchored = true
        marker.CanCollide = false
        marker.CanQuery = false
        marker.CanTouch = false
        marker.CastShadow = false
        marker.Material = Enum.Material.Neon
        marker.Color = PATH_COLOR
        marker.Size = Vector3.new(1.8, 1.8, 1.8)
        marker.Position = last.Position + lift
        marker.Parent = pathFolder
    end
end

-- Parameter raycast: abaikan karakter, monster, item drop, garis rute, dan objek target
local function buildRayParams(ignoreInstance)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    params.RespectCanCollide = true

    local list = { pathFolder }
    if radiusBall then
        table.insert(list, radiusBall)
    end
    local items = workspace:FindFirstChild("WorldItems")
    if items then
        table.insert(list, items)
    end
    for _, other in ipairs(Players:GetPlayers()) do
        if other.Character then
            table.insert(list, other.Character)
        end
    end
    for model in pairs(monsterModels) do
        if model.Parent then
            table.insert(list, model)
        end
    end
    if ignoreInstance then
        table.insert(list, ignoreInstance)
    end
    params.FilterDescendantsInstances = list
    return params
end

-- Titik pijakan (di tanah) di sekitar target
local function buildCandidates(targetPos, reach, fromPos, params, slack)
    local list = {}
    local radii = { 0, reach * 0.4, reach * 0.8 }

    for _, radius in ipairs(radii) do
        local count = radius == 0 and 1 or 8
        for i = 1, count do
            local angle = (i - 1) * (math.pi * 2 / count)
            local x = targetPos.X + math.cos(angle) * radius
            local z = targetPos.Z + math.sin(angle) * radius
            local hit = workspace:Raycast(Vector3.new(x, targetPos.Y + 4, z), Vector3.new(0, -GROUND_SCAN, 0), params)
            if hit then
                local ground = hit.Position
                local distToTarget = ((ground + Vector3.new(0, 3, 0)) - targetPos).Magnitude
                if distToTarget <= reach + slack then
                    table.insert(list, {
                        pos = ground,
                        score = distToTarget + flatDist(ground, fromPos) * 0.05,
                    })
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.score < b.score
    end)
    return list
end

-- Verifikasi rute: tolak kalau ada dinding menghalang atau lubang yang terlalu dalam
local function validateRoute(waypoints, params)
    for i = 1, #waypoints - 1 do
        local a, b = waypoints[i].Position, waypoints[i + 1].Position

        -- 1) Dinding: raycast mendatar setinggi WALL_HEIGHT di atas titik tertinggi segmen.
        --    Gundukan lebih pendek dari ini lolos (bisa dilompati).
        -- Hanya setinggi badan (bukan atap gua / kanopi pohon yang jauh di atas kepala).
        local base = math.max(a.Y, b.Y)
        for _, h in ipairs({ WALL_HEIGHT * 0.6, WALL_HEIGHT * 0.9 }) do
            local from = Vector3.new(a.X, base + h, a.Z)
            local to = Vector3.new(b.X, base + h, b.Z)
            if (to - from).Magnitude > 0.05 and workspace:Raycast(from, to - from, params) then
                return false, "dinding"
            end
        end

        -- 2) Lubang: sampel sepanjang segmen, harus ada tanah dalam MAX_DROP di bawahnya
        local steps = math.max(1, math.ceil((b - a).Magnitude / 2))
        for s = 0, steps do
            local p = a:Lerp(b, s / steps)
            local origin = p + Vector3.new(0, 2, 0)
            if not workspace:Raycast(origin, Vector3.new(0, -(2 + MAX_DROP), 0), params) then
                return false, "lubang dalam"
            end
        end
    end
    return true
end

local function routeLength(waypoints)
    local total = 0
    for i = 1, #waypoints - 1 do
        total += (waypoints[i + 1].Position - waypoints[i].Position).Magnitude
    end
    return total
end

-- ===== Deteksi monster di rute =====
local function getRouteMonsters()
    local list = {}
    for model, monsterName in pairs(monsterModels) do
        if routeAvoidSet[monsterName] and avoidMonster[monsterName] and model.Parent then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if not (humanoid and humanoid.Health <= 0) then
                local ok, pivot = pcall(model.GetPivot, model)
                if ok then
                    table.insert(list, { name = monsterName, pos = pivot.Position })
                end
            end
        end
    end
    return list
end

local function wpPositions(waypoints)
    local pts = {}
    for _, w in ipairs(waypoints) do
        table.insert(pts, w.Position)
    end
    return pts
end

-- Jarak mendatar titik p ke segmen a-b (+ tinggi segmen di titik terdekat)
local function segDistFlat(p, a, b)
    local dx, dz = b.X - a.X, b.Z - a.Z
    local len2 = dx * dx + dz * dz
    local t = 0
    if len2 > 0.0001 then
        t = math.clamp(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / len2, 0, 1)
    end
    local cx, cz = a.X + dx * t, a.Z + dz * t
    local dist = math.sqrt((p.X - cx) ^ 2 + (p.Z - cz) ^ 2)
    return dist, a.Y + (b.Y - a.Y) * t
end

-- Kembalikan monster pertama yang terlalu dekat dengan rute (nil = rute aman)
local function routeMonsterConflict(points, monsters)
    if #points == 0 or #monsters == 0 then
        return nil
    end
    local start = points[1]
    for _, m in ipairs(monsters) do
        local clear = ROUTE_MONSTER_CLEARANCE
        local startDist = flatDist(start, m.pos)
        if startDist < clear then
            -- monster sudah dekat dari awal: rute tidak boleh makin mendekat
            clear = math.max(startDist * 0.8, 3)
        end
        for i = 1, #points do
            local a = points[i]
            local b = points[i + 1] or a
            local d, cy = segDistFlat(m.pos, a, b)
            if d < clear and math.abs(m.pos.Y - cy) < 15 then
                return m
            end
        end
    end
    return nil
end

local function computePath(pathParams, a, b)
    local ok, waypoints = pcall(function()
        local path = PathfindingService:CreatePath(pathParams)
        path:ComputeAsync(a, b)
        if path.Status ~= Enum.PathStatus.Success then
            return nil
        end
        return path:GetWaypoints()
    end)
    if ok and waypoints and #waypoints >= 1 then
        return waypoints
    end
    return nil
end

-- Rute memutar: lewat titik di sekeliling monster yang menghalangi
local function tryDetour(pathParams, params, fromPos, candPos, monsters, blocker)
    local radius = ROUTE_MONSTER_CLEARANCE + ROUTE_DETOUR_EXTRA
    local vias = {}
    for i = 0, 7 do
        local ang = i * math.pi / 4
        local x = blocker.pos.X + math.cos(ang) * radius
        local z = blocker.pos.Z + math.sin(ang) * radius
        local hit = workspace:Raycast(Vector3.new(x, blocker.pos.Y + 6, z), Vector3.new(0, -GROUND_SCAN, 0), params)
        if hit then
            local g = hit.Position
            local safe = true
            for _, m in ipairs(monsters) do
                if flatDist(g, m.pos) < ROUTE_MONSTER_CLEARANCE * 0.8 then
                    safe = false
                    break
                end
            end
            if safe then
                table.insert(vias, { pos = g, score = (g - fromPos).Magnitude + (g - candPos).Magnitude })
            end
        end
    end
    table.sort(vias, function(a, b)
        return a.score < b.score
    end)

    for i = 1, math.min(#vias, MAX_DETOURS) do
        local w1 = computePath(pathParams, fromPos, vias[i].pos)
        local w2 = w1 and computePath(pathParams, vias[i].pos, candPos)
        if w1 and w2 then
            local joined = {}
            for _, w in ipairs(w1) do
                table.insert(joined, w)
            end
            for j = 2, #w2 do
                table.insert(joined, w2[j])
            end
            if validateRoute(joined, params) and not routeMonsterConflict(wpPositions(joined), monsters) then
                return joined
            end
        end
    end
    return nil
end

-- Hitung rute terbaik ke salah satu titik pijakan dekat target.
-- Hasil: rute | nil, alasan, terhalangMonster
local function computeRoute(fromPos, targetPos, reach, ignoreInstance, slack, extraRadius)
    slack = slack or 2
    local pathParams = table.clone(PATH_PARAMS)
    pathParams.AgentRadius = AGENT_RADIUS + (extraRadius or 0)
    local params = buildRayParams(ignoreInstance)
    local monsters = getRouteMonsters()
    local candidates = buildCandidates(targetPos, reach, fromPos, params, slack)
    if #candidates == 0 then
        -- tidak ada pijakan sedekat itu: longgarkan sedikit, ambil yang terdekat
        candidates = buildCandidates(targetPos, reach, fromPos, params, slack + 4)
    end
    if #candidates == 0 then
        return nil, "tidak ada pijakan di dekat target"
    end

    local best, bestLength = nil, math.huge
    local rawBest, rawBestLength = nil, math.huge
    local validCount = 0
    local detourTries = 0
    local monsterBlocked = nil
    local lastReason = "tidak ada jalan"

    local function accept(route)
        local length = routeLength(route)
        if length < bestLength then
            best, bestLength = route, length
        end
        validCount += 1
    end

    for i = 1, math.min(#candidates, MAX_CANDIDATES) do
        local waypoints = computePath(pathParams, fromPos, candidates[i].pos)
        if waypoints then
            local valid, reason = validateRoute(waypoints, params)
            if valid then
                local blocker = routeMonsterConflict(wpPositions(waypoints), monsters)
                if not blocker then
                    accept(waypoints)
                else
                    monsterBlocked = blocker.name
                    lastReason = "monster " .. blocker.name .. " di rute"
                    if detourTries < 2 then
                        detourTries += 1
                        local detour = tryDetour(pathParams, params, fromPos, candidates[i].pos, monsters, blocker)
                        if detour then
                            accept(detour)
                        end
                    end
                end
                if validCount >= 2 then
                    break
                end
            else
                lastReason = "rute ditolak: " .. tostring(reason)
                -- ditolak karena dinding tapi navmesh bilang bisa: simpan sebagai cadangan
                -- (hanya kalau tidak melewati monster)
                if reason == "dinding" then
                    local length = routeLength(waypoints)
                    if length < rawBestLength and not routeMonsterConflict(wpPositions(waypoints), monsters) then
                        rawBest, rawBestLength = waypoints, length
                    end
                end
            end
        end
    end

    if not best and rawBest then
        best = rawBest
    end
    if not best then
        if monsterBlocked then
            return nil, "monster " .. monsterBlocked .. " menghalangi rute", true
        end
        return nil, lastReason
    end
    return best
end

-- Ikuti rute dengan berjalan biasa. Hasil: "done" | "stuck" | "abort" | "timeout" | "monster"
local function followPathInner(waypoints, myChar, hum, root, deadline, goal, goalNear)
    local lastIndex = #waypoints
    local index = 2
    local sideSign = 1
    local lastMonsterCheck = 0

    while index <= lastIndex do
        local waypoint = waypoints[index]
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            tapJump()
        end

        local startedAt = os.clock()
        local lastPos = root.Position
        local lastMoveAt = os.clock()
        local stallStage = 0
        local sideUntil = 0

        while true do
            if not isActive or not isAlive then
                return "abort"
            end
            if player.Character ~= myChar or not root.Parent or hum.Health <= 0 then
                return "abort"
            end
            local now = os.clock()
            if now > deadline then
                return "timeout"
            end

            local pos = root.Position

            -- Sudah cukup dekat dengan tujuan: selesai, tidak perlu menginjak titik rute terakhir persis
            -- (mencegah lompat-lompat di tempat padahal sudah dalam jangkauan)
            if goal and goalNear and (pos - goal).Magnitude <= goalNear then
                return "done"
            end

            -- Makin lama macet, makin longgar syarat "sampai di titik rute"
            local looseness = math.min((now - lastMoveAt) * 1.5, 3)
            local arriveRadius = ((index == lastIndex) and FINAL_ARRIVE_RADIUS or 3.2) + looseness
            if flatDist(pos, waypoint.Position) < arriveRadius and math.abs(pos.Y - waypoint.Position.Y) < 7 then
                break
            end

            -- Titik berikutnya sudah lebih dekat & terjangkau: lewati titik ini
            if index < lastIndex then
                local nextWp = waypoints[index + 1]
                local dNext = flatDist(pos, nextWp.Position)
                if nextWp.Action ~= Enum.PathWaypointAction.Jump
                    and dNext < 3.2
                    and dNext < flatDist(pos, waypoint.Position)
                    and math.abs(pos.Y - nextWp.Position.Y) < 7 then
                    index += 1
                    break
                end
            end

            -- Monster mendekat ke rute di depan: berhenti & hitung ulang rute
            if now - lastMonsterCheck >= MONSTER_CHECK_INTERVAL then
                lastMonsterCheck = now
                local monsters = getRouteMonsters()
                if #monsters > 0 then
                    local pts = { pos }
                    local travelled, prev = 0, pos
                    for k = index, lastIndex do
                        local p = waypoints[k].Position
                        travelled += (p - prev).Magnitude
                        table.insert(pts, p)
                        prev = p
                        if travelled >= MONSTER_LOOKAHEAD then
                            break
                        end
                    end
                    local conflict = routeMonsterConflict(pts, monsters)
                    if conflict then
                        return "monster", conflict.name
                    end
                end
            end

            -- Kemajuan diukur MENDATAR saja: lompat di tempat (naik-turun) tidak dihitung maju,
            -- jadi kalau karakter cuma loncat-loncat di depan batu, itu terdeteksi sebagai nyangkut.
            if flatDist(pos, lastPos) > 1 then
                lastPos = pos
                lastMoveAt = now
                stallStage = 0
                sideUntil = 0
            end
            local stalled = now - lastMoveAt

            -- WASD tidak menggerakkan karakter sama sekali: pindah ke MoveTo (cadangan)
            if not moveFallback and not isTouchDevice and stalled > KEY_FALLBACK_AFTER then
                moveFallback = true
                lastMoveAt = now
                stalled = 0
                stallStage = 0
                setStatus("WASD tidak bergerak, pakai MoveTo (cadangan)")
            end

            -- Anti nyangkut bertahap (sambil tetap menahan maju):
            --   1) lompat sambil maju  2) lompat + geser serong ke samping  3) hitung ulang rute
            if stallStage == 0 and stalled > 0.6 then
                stallStage = 1
                tapJump()
            elseif stallStage == 1 and stalled > 1.3 then
                stallStage = 2
                tapJump()
                sideSign = -sideSign
                sideUntil = now + 0.9
            end
            if stalled > STUCK_TIME or now - startedAt > WAYPOINT_TIMEOUT then
                -- tersangkut tepat di ujung rute (mis. terhalang ore itu sendiri) = sudah sedekat mungkin
                -- atau sudah hampir dalam jangkauan tujuan = anggap sampai
                if index == lastIndex or (goal and goalNear and (pos - goal).Magnitude <= goalNear + 3) then
                    return "done"
                end
                return "stuck"
            end

            local aim = waypoint.Position
            if now < sideUntil then
                local d = Vector3.new(aim.X - pos.X, 0, aim.Z - pos.Z)
                if d.Magnitude > 0.1 then
                    local perp = Vector3.new(-d.Z, 0, d.X).Unit * sideSign
                    aim = pos + d.Unit * 2 + perp * 6 -- serong: maju sedikit + ke samping
                end
            end
            steerTo(aim, hum, root)
            task.wait(0.05)
        end
        index += 1
    end
    return "done"
end

-- Pembungkus: pastikan semua tombol WASD dilepas begitu selesai / gagal / dihentikan
local function followPath(waypoints, myChar, hum, root, deadline, goal, goalNear)
    local result, extra = followPathInner(waypoints, myChar, hum, root, deadline, goal, goalNear)
    releaseKeys()
    return result, extra
end

-- Turun dari tebing/ketinggian: cari tepi yang aman, lalu melangkah turun ke tanah di bawah
-- (tanpa teleport). Dipakai kalau PathfindingService tidak punya rute turun.
-- Hasil true = karakter sudah turun.
local function tryDropDown(targetPos, myChar, hum, root, ignoreInstance, extraRadius)
    local params = buildRayParams(ignoreInstance)
    local pathParams = table.clone(PATH_PARAMS)
    pathParams.AgentRadius = AGENT_RADIUS + (extraRadius or 0)
    local monsters = getRouteMonsters()

    local pos = root.Position
    local feetY = pos.Y - (root.Size.Y / 2 + hum.HipHeight)

    -- tanah di dekat target (titik tujuan perhitungan rute dari bawah)
    local goal = targetPos
    local goalHit = workspace:Raycast(Vector3.new(targetPos.X, targetPos.Y + 4, targetPos.Z),
        Vector3.new(0, -GROUND_SCAN, 0), params)
    if goalHit then
        goal = goalHit.Position
    end

    -- kumpulkan titik pendaratan: arah mengelilingi, ada tanah yang lebih rendah (3..MAX_FALL stud)
    local options = {}
    for i = 0, 15 do
        local ang = i * math.pi / 8
        local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
        local wall = workspace:Raycast(pos, dir * 14, params) -- jalan menuju tepi harus bebas dinding
        local maxDist = wall and math.max(wall.Distance - 2, 0) or 14
        for _, dist in ipairs({ 4, 7, 10, 13 }) do
            if dist <= maxDist then
                local p = pos + dir * dist
                local hit = workspace:Raycast(Vector3.new(p.X, pos.Y + 2, p.Z), Vector3.new(0, -GROUND_SCAN, 0), params)
                if hit then
                    local drop = feetY - hit.Position.Y
                    if drop >= 3 and drop <= MAX_FALL then
                        local safe = true
                        for _, m in ipairs(monsters) do
                            if flatDist(hit.Position, m.pos) < ROUTE_MONSTER_CLEARANCE * 0.8 then
                                safe = false
                                break
                            end
                        end
                        if safe then
                            table.insert(options, {
                                pos = hit.Position,
                                drop = drop,
                                score = flatDist(hit.Position, goal) + drop * 0.5,
                            })
                        end
                    end
                end
            end
        end
    end
    if #options == 0 then
        return false
    end
    table.sort(options, function(a, b)
        return a.score < b.score
    end)

    -- pilih pendaratan yang dari sana ADA rute ke target
    local best, bestScore = nil, math.huge
    for i = 1, math.min(#options, 6) do
        local waypoints = computePath(pathParams, options[i].pos, goal)
        if waypoints then
            local score = routeLength(waypoints) + options[i].drop * 2
            if score < bestScore then
                best, bestScore = options[i], score
            end
        end
    end
    if not best then
        return false
    end

    -- melangkah dari tepi menuju titik pendaratan
    setStatus(string.format("Tidak ada rute turun, melangkah turun (%.0f stud)", best.drop))
    local startedAt = os.clock()
    local startY = root.Position.Y
    local landed = false
    while os.clock() - startedAt < 5 do
        if not isActive or not isAlive or player.Character ~= myChar or hum.Health <= 0 then
            break
        end
        if root.Position.Y < startY - math.max(2.5, best.drop * 0.6) and hum.FloorMaterial ~= Enum.Material.Air then
            landed = true
            break
        end
        steerTo(best.pos, hum, root)
        task.wait(0.05)
    end
    releaseKeys()
    if landed then
        task.wait(0.3)
    end
    return landed
end

-- Berjalan ke dekat targetPos (dalam jarak reach). Menunggu (yield) sampai selesai.
-- Hasil true = sampai. false = tidak bisa dicapai / dihentikan.
local function walkTo(targetPos, reach, ignoreInstance, tolerance)
    if travelling then
        return false
    end
    local myChar, hum, root = getChar()
    if not root then
        return false
    end

    local tol = tolerance or ARRIVE_TOLERANCE
    local near = reach + tol
    if (root.Position - targetPos).Magnitude <= near then
        return true
    end

    travelling = true
    moveFallback = false
    local ok, result = pcall(function()
        local deadline = os.clock() + WALK_TIMEOUT
        local repaths = 0
        local monsterRepaths = 0
        local monsterWaits = 0
        local dropAttempts = 0

        while true do
            local c2, h2, r2 = getChar()
            if not r2 or c2 ~= myChar then
                return false
            end
            if not isActive or not isAlive then
                return false
            end
            if (r2.Position - targetPos).Magnitude <= near then
                return true
            end
            if os.clock() > deadline then
                setStatus("Waktu jalan habis")
                return false
            end

            setStatus("Menghitung rute...")
            local feet = r2.Position - Vector3.new(0, r2.Size.Y / 2 + h2.HipHeight, 0)
            local route, reason, monsterBlock = computeRoute(feet, targetPos, reach, ignoreInstance, tol - 1, repaths * 1.0)
            if not route then
                if monsterBlock and monsterWaits < MONSTER_WAIT_TRIES then
                    monsterWaits += 1
                    setStatus(string.format("%s, tunggu monster pergi (%d/%d)",
                        tostring(reason), monsterWaits, MONSTER_WAIT_TRIES))
                    if not waitFor(MONSTER_WAIT_TIME) then
                        return false
                    end
                    continue
                end
                -- tidak ada rute (mis. sedang di atas tebing): coba turun dengan melangkah dari tepi
                if DROP_DOWN_ENABLED and not monsterBlock and dropAttempts < MAX_DROPDOWN_TRIES then
                    dropAttempts += 1
                    setStatus(string.format("Tidak ada rute (%s), coba turun (%d/%d)",
                        tostring(reason), dropAttempts, MAX_DROPDOWN_TRIES))
                    if tryDropDown(targetPos, myChar, h2, r2, ignoreInstance, repaths * 1.0) then
                        continue
                    end
                end
                setStatus("Tidak bisa dicapai: " .. tostring(reason))
                return false
            end

            drawPath(route)
            setStatus(string.format("Jalan sesuai garis hijau (%d titik)", #route))

            local outcome, extra = followPath(route, myChar, h2, r2, deadline, targetPos, near)
            if outcome == "abort" then
                return false
            elseif outcome == "timeout" then
                setStatus("Waktu jalan habis")
                return false
            elseif outcome == "monster" then
                monsterRepaths += 1
                if monsterRepaths > MAX_MONSTER_REPATH then
                    setStatus("Monster terus menghalangi rute, target dilewati")
                    return false
                end
                setStatus(string.format("%s mendekati rute, hitung ulang (%d/%d)",
                    tostring(extra), monsterRepaths, MAX_MONSTER_REPATH))
                task.wait(0.2)
            elseif outcome == "stuck" then
                repaths += 1
                if repaths > MAX_REPATH then
                    setStatus("Nyangkut terus, target dilewati")
                    return false
                end
                setStatus(string.format("Nyangkut, hitung ulang rute (%d/%d)", repaths, MAX_REPATH))
                -- geser sedikit ke belakang/samping supaya tidak mengulang titik macet yang sama
                local look = r2.CFrame.LookVector
                local flatLook = Vector3.new(look.X, 0, look.Z)
                if flatLook.Magnitude > 0.1 then
                    flatLook = flatLook.Unit
                    local side = Vector3.new(-flatLook.Z, 0, flatLook.X) * ((repaths % 2 == 0) and 1 or -1)
                    h2:MoveTo(r2.Position - flatLook * 3 + side * 3)
                    if not waitFor(0.5) then
                        return false
                    end
                end
                task.wait(0.2)
            else -- "done": sudah berdiri di ujung rute (titik terdekat yang bisa dicapai)
                return true
            end
        end
    end)

    clearPath()
    releaseKeys()
    pcall(function()
        local _, h, r = getChar()
        if h and r then
            h:MoveTo(r.Position)
        end
    end)
    travelling = false
    return ok and result == true
end

-- Cari ProximityPrompt (tombol Mine) milik ore: posisi & jarak aktifnya
local function getPromptInfo(target)
    if not target.promptChecked then
        target.promptChecked = true
        local root = target.ore.Parent or target.ore
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local parent = d.Parent
                local pos = nil
                if parent and parent:IsA("BasePart") then
                    pos = parent.Position
                elseif parent and parent:IsA("Attachment") then
                    pos = parent.WorldPosition
                elseif parent and parent:IsA("Model") then
                    pos = parent:GetPivot().Position
                end
                target.prompt = d
                target.promptPos = pos
                target.promptMax = d.MaxActivationDistance
                break
            end
        end
    end
    return target.prompt, target.promptPos, target.promptMax
end

-- Titik yang diukur untuk jarak: posisi tombol Mine kalau ada, kalau tidak posisi ore
local function aimPosition(target)
    local _, pos = getPromptInfo(target)
    return pos or target.position
end

-- Jarak berdiri yang dipakai: tidak boleh melebihi jarak aktif tombol Mine (dikurangi margin)
local function effectiveReach(target)
    local reach = settings.reach
    local _, _, maxDist = getPromptInfo(target)
    if maxDist and maxDist > 0 then
        reach = math.min(reach, maxDist - PROMPT_MARGIN)
    end
    if target.closeReach then
        reach = math.min(reach, target.closeReach)
    end
    return math.max(reach, MIN_REACH)
end

local function oreTooFar(target, rootPart)
    return (rootPart.Position - aimPosition(target)).Magnitude > effectiveReach(target) + ORE_ARRIVE_TOLERANCE + 0.5
end

local function walkToOre(target)
    return walkTo(aimPosition(target), effectiveReach(target), target.ore.Parent or target.ore, ORE_ARRIVE_TOLERANCE)
end

local function markUnreachable(target)
    if isActive and isAlive and getChar() then
        skipped[target.ore] = os.clock() + UNREACHABLE_SKIP
        setStatus(string.format("%s tidak bisa dicapai, lanjut ke target lain", target.name))
    end
end

-- ==========================================================
-- START / STOP
-- ==========================================================
local function loadSettings()
    local clicks = tonumber(inputClicks.Text)
    local waitTime = tonumber(inputWait.Text)
    local reach = tonumber(inputReach.Text)

    if not clicks or clicks < 1 or not waitTime or not reach or reach <= 0 then
        return false
    end

    settings.clicks = math.clamp(math.floor(clicks), 1, 1000)
    settings.waitTime = math.max(waitTime, 0)
    settings.reach = math.clamp(reach, 3, 40)
    return true
end

local function setToggleVisual(running)
    local text = running and "STOP" or "START"
    local color = running and THEME.red or THEME.green
    toggleButton.Text = text
    toggleButton.BackgroundColor3 = color
    headerToggle.Text = text
    headerToggle.BackgroundColor3 = color
end

local function setRunningUI()
    setToggleVisual(true)
    setState("ON", THEME.green)
end

local function stopMiner(reason)
    isActive = false
    inCooldown = false
    markTarget(nil)
    clearPath()
    setToggleVisual(false)
    setState("STOP", THEME.grey)
    if reason then
        setStatus(reason)
    end
end

local function startMiner()
    if not loadSettings() then
        setState("INPUT TIDAK VALID", THEME.orange)
        setStatus("Cek kolom: semua harus berupa angka")
        return
    end
    skipped = {}
    isActive = true
    setRunningUI()
end

local function toggleMiner()
    if isActive then
        stopMiner("Dihentikan")
    else
        startMiner()
    end
end

for _, box in ipairs({ inputClicks, inputWait, inputReach, inputIgnore }) do
    table.insert(connections, box.Focused:Connect(function()
        if isActive and not inCooldown then
            stopMiner("Dihentikan untuk edit")
        end
    end))
end

-- ==========================================================
-- AMBIL DROP (workspace.WorldItems)
-- ==========================================================
local givenUpDrops = {}

local function getItemPart(item)
    if item:IsA("BasePart") then
        return item
    end
    if item:IsA("Model") then
        return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function normalizeName(text)
    local clean = tostring(text):gsub("[^%w]", "")
    return clean:lower()
end

local COUNT_KEY = normalizeName(COUNT_ITEM_NAME)
local AMOUNT_ATTRIBUTES = { "Amount", "amount", "Quantity", "quantity", "Count", "count", "Stack", "stack" }
local dropInfo = {}
local debugPrinted = 0

local function collectTexts(instance, texts)
    for _, value in pairs(instance:GetAttributes()) do
        if type(value) == "string" then
            table.insert(texts, value)
        end
    end
end

local function classifyDrop(item)
    local info = dropInfo[item]
    if info and (info.match or info.checks >= 3) then
        return info
    end

    local texts = { item.Name }
    collectTexts(item, texts)
    for _, descendant in ipairs(item:GetDescendants()) do
        table.insert(texts, descendant.Name)
        if descendant:IsA("StringValue") then
            table.insert(texts, descendant.Value)
        elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            table.insert(texts, descendant.Text)
        end
        collectTexts(descendant, texts)
    end

    local match = false
    for _, text in ipairs(texts) do
        if normalizeName(text):find(COUNT_KEY, 1, true) then
            match = true
            break
        end
    end

    local amount = 1
    for _, attributeName in ipairs(AMOUNT_ATTRIBUTES) do
        local value = item:GetAttribute(attributeName)
        if type(value) == "number" and value >= 1 then
            amount = math.floor(value)
            break
        end
    end

    if DEBUG_ITEMS and not info and debugPrinted < 20 then
        debugPrinted += 1
        print("[DROP] " .. table.concat(texts, " | "))
    end

    info = { match = match, amount = amount, checks = (info and info.checks or 0) + 1 }
    dropInfo[item] = info
    return info
end

local function findDrops(center)
    local folder = workspace:FindFirstChild("WorldItems")
    if not folder then
        return {}
    end

    local found = {}
    for _, item in ipairs(folder:GetChildren()) do
        local part = getItemPart(item)
        if part and not givenUpDrops[item] and (not PICKUP_PART_NAME or part.Name == PICKUP_PART_NAME) then
            local distance = (part.Position - center).Magnitude
            if distance <= PICKUP_RADIUS then
                classifyDrop(item)
                table.insert(found, { item = item, part = part, distance = distance })
            end
        end
    end
    table.sort(found, function(a, b)
        return a.distance < b.distance
    end)
    return found
end

-- Mendekati drop dengan berjalan (rute dihitung + garis hijau)
local function approachDrop(part)
    return walkTo(part.Position, PICKUP_DISTANCE + 2, part)
end

local function getPickupId(item)
    if item.Name:sub(1, 7) == "pickup_" then
        return item.Name
    end
    local attribute = item:GetAttribute("pickupId")
    if type(attribute) == "string" then
        return attribute
    end
    return nil
end

local pickupRemote = nil
local function getPickupRemote()
    if pickupRemote and pickupRemote.Parent then
        return pickupRemote
    end
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local inventory = remotes and remotes:FindFirstChild("Inventory")
    pickupRemote = inventory and inventory:FindFirstChild("RequestPickupItem")
    return pickupRemote
end

local function requestPickup(item)
    local pickupId = getPickupId(item)
    local remote = getPickupRemote()
    if not pickupId or not remote then
        return false
    end
    return pcall(function()
        remote:FireServer({ pickupId = pickupId })
    end)
end

local function clickDrop(part)
    local camera = workspace.CurrentCamera
    local screenPoint, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen then
        return false
    end
    return clickOnce(math.floor(screenPoint.X), math.floor(screenPoint.Y))
end

-- ----- Deteksi teks "Inventory Full" -----
local INVENTORY_FULL_KEY = normalizeName(INVENTORY_FULL_TEXT)
local inventoryFullUntil = 0
local lastInvScan = 0

local function isInvFullText(text)
    return type(text) == "string" and #text > 0 and #text < 80
        and normalizeName(text):find(INVENTORY_FULL_KEY, 1, true) ~= nil
end

local function invLabelVisible(label)
    if label.TextTransparency >= 1 then
        return false
    end
    local current = label
    while current and current ~= game do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("ScreenGui") then
            return current.Enabled
        end
        current = current.Parent
    end
    return true
end

local function scanInventoryFull()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then
        return false
    end
    for _, d in ipairs(pg:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton"))
            and isInvFullText(d.Text)
            and not d:IsDescendantOf(gui)
            and invLabelVisible(d) then
            return true
        end
    end
    return false
end

-- true selama teks "Inventory Full" terlihat (dan INVENTORY_FULL_HOLD detik sesudahnya)
local function inventoryFull()
    local now = os.clock()
    if now - lastInvScan >= 0.25 then
        lastInvScan = now
        if scanInventoryFull() then
            inventoryFullUntil = now + INVENTORY_FULL_HOLD
        end
    end
    return now < inventoryFullUntil
end

-- Pengali waktu tunggu drop: 1 normal, INVENTORY_FULL_FACTOR saat inventory penuh
local function dropWaitFactor()
    return inventoryFull() and INVENTORY_FULL_FACTOR or 1
end

-- Pantau terus supaya notifikasi yang muncul sebentar tetap tertangkap
task.spawn(function()
    while isAlive do
        if isActive then
            pcall(inventoryFull)
        end
        task.wait(0.3)
    end
end)

local function collectRound(drops)
    for index, drop in ipairs(drops) do
        if not drop.item.Parent then
            continue
        end

        setStatus(string.format("Ambil drop %d/%d\n%s", index, #drops, drop.item.Name))
        if not approachDrop(drop.part) then
            if not (isActive and isAlive) or not getChar() then
                return false
            end
            -- drop tidak bisa dicapai: lewati saja
            givenUpDrops[drop.item] = true
            continue
        end
        if not waitFor(0.25 * dropWaitFactor()) then return false end

        if PICKUP_USE_REMOTE and getPickupId(drop.item) then
            local tries = 0
            while drop.item.Parent and tries < PICKUP_MAX_TRY do
                tries += 1
                if not requestPickup(drop.item) then
                    break
                end
                if not waitFor(PICKUP_RETRY * dropWaitFactor()) then return false end
            end
        end

        for _ = 1, PICKUP_CLICKS do
            if not drop.item.Parent then
                break
            end
            if not clickDrop(drop.part) then
                break
            end
            if not waitFor(0.2 * dropWaitFactor()) then return false end
        end

        if not drop.item.Parent then
            picked += 1
            local info = dropInfo[drop.item]
            if info and info.match then
                gvqCount += info.amount
            end
            updateStats()
        end
    end
    return true
end

local function waitAllDrops(center)
    local startedAt = os.clock()
    local emptySince = nil

    while true do
        local drops = findDrops(center)

        if #drops > 0 then
            emptySince = nil

            if os.clock() - startedAt >= DROP_MAX_WAIT * dropWaitFactor() then
                for _, drop in ipairs(drops) do
                    givenUpDrops[drop.item] = true
                end
                setStatus(string.format("%d drop tidak bisa diambil, lanjut", #drops))
                return true
            end

            setState(string.format("OFF | ambil %d drop%s", #drops,
                inventoryFull() and " (inv penuh, waktu x" .. INVENTORY_FULL_FACTOR .. ")" or ""), THEME.orange)
            if PICKUP_ENABLED then
                if not collectRound(drops) then return false end
            else
                if not waitFor(0.2) then return false end
            end
        else
            emptySince = emptySince or os.clock()
            if os.clock() - emptySince >= DROP_GRACE * dropWaitFactor() then
                return true
            end
            setState("OFF | cek drop", THEME.orange)
            if not waitFor(0.2) then return false end
        end
    end
end

-- ==========================================================
-- DETEKSI TOMBOL MINE / STOP MINING
-- ==========================================================
local function stateFromText(text)
    local s = tostring(text):lower()
    if s:find("stop") then
        return "stop"
    end
    if s:match("^%s*mine%s*$") then
        return "mine"
    end
    return nil
end

local function getMineState(target)
    local root = target.ore.Parent or target.ore
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local st = stateFromText(d.ActionText)
            if st then
                return st
            end
        end
    end

    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible and #d.Text > 0 and #d.Text < 20 then
                local sg = d:FindFirstAncestorWhichIsA("ScreenGui")
                if sg and sg.Enabled then
                    local st = stateFromText(d.Text)
                    if st then
                        return st
                    end
                end
            end
        end
    end
    return nil
end

-- ==========================================================
-- SATU PUTARAN MINING
-- ==========================================================
-- Hasil false = miner dihentikan / ore tidak bisa dicapai.
local function attemptMine(target, forceWalk)
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return waitFor(0.5)
    end

    -- percobaan ulang = berdiri lebih dekat lagi dari sebelumnya
    if forceWalk then
        target.closeReach = math.max(MIN_REACH, effectiveReach(target) * 0.6)
    end

    if forceWalk or oreTooFar(target, rootPart) then
        if not walkToOre(target) then
            markUnreachable(target)
            return false
        end
        if not waitFor(0.4) then return false end
    end

    local deadline = os.clock() + MINE_CONFIRM_TIME
    local presses = 0
    local closerTries = 0
    local walkAttempts = 0

    while target.ore.Parent and os.clock() < deadline do
        local state = getMineState(target)
        if state == "stop" then
            return true
        end

        character = player.Character
        rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if rootPart and oreTooFar(target, rootPart) and walkAttempts < 3 then
            walkAttempts += 1
            if not walkToOre(target) then
                markUnreachable(target)
                return false
            end
            if not waitFor(0.4) then return false end
        end

        -- Tombol Mine tidak muncul / F ditekan berkali-kali tapi tidak mulai menambang:
        -- kemungkinan masih kurang dekat, jadi mendekat lagi (makin dekat tiap percobaan)
        local hasPrompt = getPromptInfo(target) ~= nil
        local notWorking = (state == nil and hasPrompt) or (state == "mine" and presses >= 3 and presses % 3 == 0)
        if notWorking and closerTries < MAX_CLOSER then
            closerTries += 1
            target.closeReach = math.max(MIN_REACH, effectiveReach(target) * 0.6)
            setStatus(string.format("Tombol Mine belum aktif, mendekat lagi (%d/%d)", closerTries, MAX_CLOSER))
            if not walkToOre(target) then
                markUnreachable(target)
                return false
            end
            if not waitFor(0.4) then return false end
        end

        presses += 1
        setStatus(string.format("Mining %s (%s)\nTombol: %s | tekan F ke-%d | total %d",
            target.name, target.oreType, state == "mine" and "Mine" or "?", presses, mined))

        if not pressF() then
            stopMiner("SendKeyEvent tidak didukung executor ini")
            return false
        end
        if not waitFor(MINE_CHECK_DELAY) then return false end

        if state == nil and presses >= settings.clicks and (not hasPrompt or closerTries >= MAX_CLOSER) then
            return true
        end
    end
    return true
end

local function mineOnce()
    if respawning or not getChar() then
        setStatus("Menunggu respawn...")
        waitFor(0.3)
        return
    end

    local results = scanOres()
    if not results then
        stopMiner("Folder Spawn_Ore tidak ditemukan")
        return
    end

    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        setStatus("Menunggu karakter...")
        waitFor(1)
        return
    end

    local target, skipStats = pickNearestOre(results, rootPart.Position)
    if not target then
        setStatus(string.format(
            "Tidak ada ore bisa dituju (%d total)\nDi-mark: %d | Pemain: %d | Monster: %d | Cooldown: %d",
            #results, skipStats.marked, skipStats.player, skipStats.monster, skipStats.cooldown))
        waitFor(EMPTY_WAIT)
        return
    end

    local blocker = getNearbyPlayer(target.position)
    if blocker then
        setStatus(target.name .. " ada " .. blocker.Name .. ", cari SP lain")
        waitFor(0.2)
        return
    end

    -- Hitung rute -> garis hijau -> jalan ke ore
    markTarget(target)
    currentTarget = target
    setStatus("Menuju " .. target.name .. " (" .. target.oreType .. ")")
    if not walkToOre(target) then
        if isActive and isAlive then
            -- tidak ada rute / nyangkut terus / mati: skip, lanjut ke target mining berikutnya
            markUnreachable(target)
            waitFor(0.5)
        end
        return
    end
    if not waitFor(0.3) then return end

    -- Tekan F sampai tombol jadi "Stop Mining"
    if not attemptMine(target, false) then return end

    -- Tunggu ore hilang
    inCooldown = true
    local oreTimeout = TYPE_TIMEOUTS[target.oreType] or settings.waitTime
    local oreDeadline = os.clock() + oreTimeout
    local attempts, nextRetry = 1, os.clock() + RETRY_AFTER
    while target.ore.Parent do
        if respawning or not getChar() then
            inCooldown = false
            return
        end
        local left = oreDeadline - os.clock()
        local state = getMineState(target)

        if left > 0 and state == "mine" then
            if not attemptMine(target, false) then
                inCooldown = false
                return
            end
            nextRetry = os.clock() + RETRY_AFTER
        elseif left > 0 and state ~= "stop" and attempts < MAX_RETRY and os.clock() >= nextRetry then
            attempts += 1
            if not attemptMine(target, true) then
                inCooldown = false
                return
            end
            nextRetry = os.clock() + RETRY_AFTER
        end

        if left <= 0 then
            skipped[target.ore] = os.clock() + SKIP_TIME
            setStatus(string.format("%s tidak hilang dalam %.0f dtk, lanjut", target.name, oreTimeout))
            inCooldown = false
            if not loadSettings() then
                stopMiner("Input tidak valid, cek kolom")
                return
            end
            setRunningUI()
            return
        end
        setState(string.format("OFF | tunggu ore hilang (%d)", math.ceil(left)), THEME.orange)
        setStatus(string.format("%s (%s)\nTombol: %s | percobaan %d/%d | total %d",
            target.name, target.oreType,
            state == "stop" and "Stop Mining" or (state == "mine" and "Mine" or "?"),
            attempts, MAX_RETRY, mined))
        if not waitFor(0.2) then
            inCooldown = false
            return
        end
    end
    mined += 1
    updateStats()

    -- Tunggu SEMUA drop terambil dulu, baru pindah tempat
    if not waitAllDrops(target.position) then
        inCooldown = false
        return
    end
    inCooldown = false
    setStatus(string.format("%s selesai | ore %d | drop %d", target.name, mined, picked))

    if not loadSettings() then
        stopMiner("Input tidak valid, cek kolom")
        return
    end
    setRunningUI()
end

-- ==========================================================
-- AUTO RESPAWN
-- ==========================================================
local function isGuiShown(obj)
    local current = obj
    while current and current ~= game do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("ScreenGui") then
            return current.Enabled
        end
        current = current.Parent
    end
    return true
end

-- Cari tombol yang tulisannya mengandung "respawn".
-- Hasil: tombol, siap diklik (true/false), teks yang terbaca
local function findRespawnButton()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then
        return nil
    end

    local fallback = nil
    for _, d in ipairs(pg:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("TextLabel")) and not d:IsDescendantOf(gui) then
            local text = d.Text
            if #text > 0 and #text < 60 and text:lower():find("respawn", 1, true) and isGuiShown(d) then
                local button = d:IsA("TextButton") and d or d:FindFirstAncestorWhichIsA("GuiButton")
                if button then
                    -- ada angka (mis. "Respawn in 5") = masih hitung mundur
                    local counting = text:find("%d") ~= nil
                    local usable = button.Interactable ~= false and button.Active ~= false
                    local info = { button = button, ready = (not counting) and usable, text = text }
                    if info.ready then
                        return info.button, true, text
                    end
                    fallback = fallback or info
                end
            end
        end
    end

    if fallback then
        return fallback.button, false, fallback.text
    end
    return nil
end

-- Klik tombol GUI. Percobaan ganjil = klik mouse/sentuh sungguhan di tengah tombol,
-- percobaan genap = picu langsung event tombol (butuh getconnections dari executor).
local function pressGuiButton(button, attempt)
    if attempt % 2 == 0 and getconnections then
        for _, signal in ipairs({ button.MouseButton1Click, button.Activated, button.MouseButton1Down, button.MouseButton1Up }) do
            local ok, list = pcall(getconnections, signal)
            if ok and list then
                for _, connection in ipairs(list) do
                    pcall(function()
                        connection:Fire()
                    end)
                end
            end
        end
        return
    end

    local center = button.AbsolutePosition + button.AbsoluteSize / 2
    local screenGui = button:FindFirstAncestorWhichIsA("ScreenGui")
    local inset = Vector2.zero
    if screenGui and not screenGui.IgnoreGuiInset then
        inset = GuiService:GetGuiInset()
    end
    clickOnce(math.floor(center.X + inset.X), math.floor(center.Y + inset.Y))
end

local function pressQ()
    return pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
        task.wait(HOLD_TIME)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
    end)
end

local function respawnFlow()
    respawning = true
    inCooldown = false
    markTarget(nil)
    clearPath()
    releaseKeys()
    setState("MATI | tunggu respawn", THEME.orange)

    local startedAt = os.clock()
    local lastClick = 0
    local attempts = 0

    while isAlive and isActive and not getChar() do
        local button, ready, text = findRespawnButton()
        if button then
            local waited = os.clock() - startedAt
            if ready or waited > RESPAWN_MAX_WAIT then
                if os.clock() - lastClick >= RESPAWN_RETRY then
                    attempts += 1
                    lastClick = os.clock()
                    setStatus(string.format("Mati. Klik Respawn (percobaan %d)", attempts))
                    pressGuiButton(button, attempts)
                end
            else
                setStatus("Mati. Menunggu respawn: " .. tostring(text))
            end
        else
            setStatus("Mati. Menunggu tombol Respawn / karakter baru...")
        end
        task.wait(0.25)
    end

    -- hidup lagi: beri jeda sebentar supaya karakter & map selesai dimuat
    if isAlive and isActive and getChar() then
        local aliveAt = os.clock()
        setStatus("Respawn berhasil, bersiap lanjut mining...")
        waitFor(RESPAWN_SETTLE)

        -- Tekan Q satu kali, RESPAWN_Q_DELAY detik setelah respawn
        if RESPAWN_PRESS_Q and isAlive and isActive then
            local remaining = RESPAWN_Q_DELAY - (os.clock() - aliveAt)
            if remaining > 0 then
                setStatus(string.format("Tekan Q dalam %.1f dtk...", remaining))
                waitFor(remaining)
            end
            if isAlive and isActive and getChar() then
                pressQ()
                setStatus("Q ditekan")
                waitFor(0.3)
            end
        end
    end

    respawning = false
    if isAlive and isActive then
        setRunningUI()
        setStatus("Kembali mining")
    end
end

task.spawn(function()
    while isAlive do
        if AUTO_RESPAWN and isActive and not respawning and not getChar() then
            -- konfirmasi dulu supaya jeda sesaat (karakter sedang dimuat) tidak dianggap mati
            task.wait(0.5)
            if isAlive and isActive and not getChar() then
                local ok, err = pcall(respawnFlow)
                if not ok then
                    warn("Auto Respawn error: " .. tostring(err))
                end
                respawning = false
            end
        end
        task.wait(0.3)
    end
end)

-- ==========================================================
-- VISUAL RADIUS
-- ==========================================================
if SHOW_RADIUS and PLAYER_RADIUS > 0 then
    radiusBall = Instance.new("Part")
    radiusBall.Name = "AutoMinerRadius"
    radiusBall.Shape = Enum.PartType.Ball
    radiusBall.Size = Vector3.new(PLAYER_RADIUS * 2, PLAYER_RADIUS * 2, PLAYER_RADIUS * 2)
    radiusBall.Material = Enum.Material.ForceField
    radiusBall.Color = Color3.fromRGB(80, 170, 255)
    radiusBall.Transparency = 0.3
    radiusBall.Anchored = true
    radiusBall.CanCollide = false
    radiusBall.CanQuery = false
    radiusBall.CanTouch = false
    radiusBall.CastShadow = false
    radiusBall.Parent = workspace

    table.insert(connections, RunService.RenderStepped:Connect(function()
        local character = player.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            radiusBall.CFrame = CFrame.new(rootPart.Position)
        end
    end))
end

-- ==========================================================
-- OVERLAY: PEMAIN LAIN
-- ==========================================================
local playerMarks = {}

local function removeMark(other)
    local mark = playerMarks[other]
    if mark then
        mark.highlight:Destroy()
        mark.billboard:Destroy()
        playerMarks[other] = nil
    end
end

local function getMark(other, character)
    local mark = playerMarks[other]
    if mark and mark.character == character then
        return mark
    end
    removeMark(other)

    local highlight = Instance.new("Highlight")
    highlight.FillColor = Color3.fromRGB(255, 60, 60)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.6
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = character
    highlight.Parent = gui

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 160, 0, 36)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    billboard.Parent = gui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 120, 120)
    label.TextStrokeTransparency = 0.3
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.Parent = billboard

    mark = { character = character, highlight = highlight, billboard = billboard, label = label }
    playerMarks[other] = mark
    return mark
end

local function updatePlayerMarks()
    local myCharacter = player.Character
    local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")

    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local character = other.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local distance = (myRoot and root) and (root.Position - myRoot.Position).Magnitude or math.huge

            if SHOW_PLAYERS and root and distance <= PLAYER_RADIUS then
                local mark = getMark(other, character)
                mark.label.Text = string.format("%s\n%.0f stud", other.Name, distance)
            else
                removeMark(other)
            end
        end
    end

    for other in pairs(playerMarks) do
        if other.Parent ~= Players then
            removeMark(other)
        end
    end
end

task.spawn(function()
    while isAlive do
        pcall(updatePlayerMarks)
        task.wait(0.3)
    end
end)

-- ==========================================================
-- KAMERA
-- ==========================================================
local originalMaxZoom = player.CameraMaxZoomDistance

if CAMERA_MAX_ZOOM then
    task.spawn(function()
        while isAlive do
            if player.CameraMaxZoomDistance < CAMERA_MAX_ZOOM then
                player.CameraMaxZoomDistance = CAMERA_MAX_ZOOM
            end
            task.wait(0.5)
        end
    end)
end

-- ==========================================================
-- MEMATIKAN SCRIPT
-- ==========================================================
local function stopScript(skipSave)
    isActive = false
    if skipSave ~= true then
        saveState() -- dimatikan manual: jangan auto-START lagi nanti
    end
    isAlive = false
    for other in pairs(playerMarks) do
        removeMark(other)
    end
    pcall(function()
        player.CameraMaxZoomDistance = originalMaxZoom
    end)
    if radiusBall then
        radiusBall:Destroy()
    end
    releaseKeys()
    pathFolder:Destroy()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    gui:Destroy()
    _G.StopAutoMiner = nil
end

_G.StopAutoMiner = stopScript

-- ==========================================================
-- TOMBOL DAN SHORTCUT
-- ==========================================================
table.insert(connections, toggleButton.Activated:Connect(toggleMiner))
table.insert(connections, headerToggle.Activated:Connect(toggleMiner))
table.insert(connections, exitButton.Activated:Connect(stopScript))

local function markCurrent()
    if not currentTarget then
        setStatus("Belum ada target untuk di-mark")
        return
    end

    local name = currentTarget.name
    local list = readIgnoreList()
    if not table.find(list, name) then
        table.insert(list, name)
        local position = currentTarget.position
        print(string.format("[MARK] %s = %s, %s, %s", name,
            tostring(position.X), tostring(position.Y), tostring(position.Z)))
    end
    inputIgnore.Text = table.concat(list, ", ")

    local copyFunction = setclipboard or toclipboard
    if copyFunction and pcall(copyFunction, inputIgnore.Text) then
        setStatus(name .. " di-skip, daftar tersalin")
    else
        setStatus(name .. " di-skip (lihat console)")
    end
end

table.insert(connections, markButton.Activated:Connect(markCurrent))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or UserInputService:GetFocusedTextBox() then
        return
    end

    if input.KeyCode == Enum.KeyCode.Zero then
        toggleMiner()
    elseif input.KeyCode == Enum.KeyCode.X then
        markCurrent()
    elseif input.KeyCode == Enum.KeyCode.End then
        stopScript()
    end
end))

-- ==========================================================
-- PERSISTENSI: SIMPAN PENGATURAN, AUTO RESUME, AUTO REJOIN
-- ==========================================================
local queueTeleportFn = queue_on_teleport or queueonteleport
    or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

local function readState()
    if not (isfile and readfile and SAVE_FILE) then
        return nil
    end
    local ok, data = pcall(function()
        if not isfile(SAVE_FILE) then
            return nil
        end
        return HttpService:JSONDecode(readfile(SAVE_FILE))
    end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local lastSaved = nil
saveState = function()
    if not (writefile and SAVE_FILE) then
        return
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({
            clicks = inputClicks.Text,
            wait = inputWait.Text,
            reach = inputReach.Text,
            ignore = inputIgnore.Text,
            active = isActive,
            mined = mined,
            picked = picked,
            gvq = gvqCount,
            avoid = avoidMonster,
        })
    end)
    if not ok or encoded == lastSaved then
        return
    end
    if pcall(writefile, SAVE_FILE, encoded) then
        lastSaved = encoded
    end
end

-- Muat pengaturan terakhir
local resumeWanted = false
do
    local data = readState()
    if data then
        if type(data.clicks) == "string" then inputClicks.Text = data.clicks end
        if type(data.wait) == "string" then inputWait.Text = data.wait end
        if type(data.reach) == "string" then inputReach.Text = data.reach end
        if type(data.ignore) == "string" then inputIgnore.Text = data.ignore end
        if type(data.mined) == "number" then mined = data.mined end
        if type(data.picked) == "number" then picked = data.picked end
        if type(data.gvq) == "number" then gvqCount = data.gvq end
        if type(data.avoid) == "table" then
            for monsterName in pairs(avoidMonster) do
                if type(data.avoid[monsterName]) == "boolean" then
                    avoidMonster[monsterName] = data.avoid[monsterName]
                    if monsterRefresh[monsterName] then
                        monsterRefresh[monsterName]()
                    end
                end
            end
        end
        updateStats()
        resumeWanted = AUTO_RESUME and data.active == true
    end
end

-- Simpan berkala (hanya menulis kalau ada perubahan)
task.spawn(function()
    while isAlive do
        saveState()
        task.wait(2)
    end
end)

-- Auto resume: tunggu game, map, dan karakter siap, lalu START otomatis
if resumeWanted then
    task.spawn(function()
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        local waited = 0
        while isAlive and waited < 90 do
            local _, _, root = getChar()
            local maps = workspace:FindFirstChild("Maps")
            local world = maps and maps:FindFirstChild("World")
            if root and world and world:FindFirstChild("Spawn_Ore") then
                break
            end
            setStatus(string.format("Menunggu map & karakter siap (%d dtk)", waited))
            task.wait(1)
            waited += 1
        end
        if not isAlive or isActive then
            return
        end
        setStatus("Lanjut otomatis setelah masuk lagi...")
        task.wait(RESUME_DELAY)
        if isAlive and not isActive then
            startMiner()
        end
    end)
end

-- Muat ulang script otomatis setelah pindah server / rejoin (butuh queue_on_teleport + file/URL)
local reloadQueued = false
local function queueReload()
    if reloadQueued or not queueTeleportFn then
        return reloadQueued
    end
    local loader = nil
    if SCRIPT_URL then
        loader = string.format('loadstring(game:HttpGet("%s"))()', SCRIPT_URL)
    elseif SCRIPT_FILE and isfile and readfile and isfile(SCRIPT_FILE) then
        loader = string.format('loadstring(readfile("%s"))()', SCRIPT_FILE)
    end
    if loader and pcall(queueTeleportFn, loader) then
        reloadQueued = true
    end
    return reloadQueued
end

if AUTO_REJOIN then
    queueReload()
end

-- Auto rejoin saat terputus
local rejoining = false
local function onDisconnected()
    if rejoining or not isAlive or not AUTO_REJOIN or not isActive then
        return
    end
    rejoining = true
    saveState() -- active = true tersimpan, jadi nanti lanjut otomatis

    task.spawn(function()
        queueReload()
        for attempt = 1, REJOIN_MAX_TRIES do
            if not isAlive then
                return
            end
            setStatus(string.format("Terputus. Rejoin dalam %d dtk (percobaan %d/%d)",
                attempt == 1 and REJOIN_DELAY or REJOIN_RETRY, attempt, REJOIN_MAX_TRIES))
            task.wait(attempt == 1 and REJOIN_DELAY or REJOIN_RETRY)
            pcall(function()
                TeleportService:Teleport(game.PlaceId, player)
            end)
        end
        setStatus("Rejoin gagal, coba masuk manual")
        rejoining = false
    end)
end

table.insert(connections, GuiService.ErrorMessageChanged:Connect(function(message)
    if message and message ~= "" then
        onDisconnected()
    end
end))

task.spawn(function()
    local ok = pcall(function()
        local promptGui = CoreGui:WaitForChild("RobloxPromptGui", 15)
        local overlay = promptGui and promptGui:WaitForChild("promptOverlay", 15)
        if overlay then
            table.insert(connections, overlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" then
                    onDisconnected()
                end
            end))
        end
    end)
    if not ok then
        warn("Auto Miner: tidak bisa memantau prompt disconnect")
    end
end)

-- ==========================================================
-- LOOP UTAMA
-- ==========================================================
task.spawn(function()
    while isAlive do
        if isActive then
            local success, err = pcall(mineOnce)
            if not success then
                warn("Auto Miner error: " .. tostring(err))
                waitFor(1)
            end
        else
            task.wait(0.1)
        end
    end
end)
