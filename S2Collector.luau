-- ============================================================
-- S2Collector.lua  (Script — ServerScriptService)
-- Kirim data posisi drag item (scenario_id = 2) ke GAS
-- Dicatat saat: StartDrag/MobileStart dan StopDrag/MobileStop
-- ============================================================

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PingService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PingService"))

-- ============================================================
-- KONFIGURASI
-- ============================================================

local CONFIG = {
	ENDPOINT       = "https://script.google.com/macros/s/AKfycbxe5GqxoYDLbSw4kqNKzIxYajpk0hoAstRKTe9Cq7-zjGzXOUarcnqlRiTfbUYn7zdL/exec",
	SESSION_ID     = nil,
	SCENARIO_ID    = 2,
	MECHANISM_TYPE = "drag",
	CLIENT_TIMEOUT = 2,  -- detik tunggu laporan client sebelum kirim tanpa data client
}

local ok, SharedConfig = pcall(function()
	return require(ReplicatedStorage:WaitForChild("ScriptPenelitian"):WaitForChild("SharedConfig"))
end)
CONFIG.SESSION_ID = (ok and SharedConfig and SharedConfig.SESSION_ID)
	or HttpService:GenerateGUID(false)

if not (ok and SharedConfig) then
	warn("[S2Collector] SharedConfig tidak ditemukan, pakai session ID sendiri.")
end

-- ============================================================
-- REMOTE EVENTS — buat otomatis jika belum ada
-- ============================================================

local eventsFolder = ReplicatedStorage:WaitForChild("Events")

local function getOrCreate(name)
	local re = eventsFolder:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = eventsFolder
		print("[S2Collector] RemoteEvent " .. name .. " dibuat otomatis.")
	end
	return re
end

-- Server broadcast ke client saat ada event drag
local S2ServerBroadcast = getOrCreate("S2ServerBroadcast")
-- Client lapor posisi mereka ke server
local S2ClientReport    = getOrCreate("S2ClientReport")

-- ============================================================
-- FUNGSI BANTU
-- ============================================================

local function getTimestamp()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function sendPayload(payload)
	local success, err = pcall(function()
		HttpService:PostAsync(
			CONFIG.ENDPOINT,
			HttpService:JSONEncode(payload),
			Enum.HttpContentType.ApplicationJson,
			false
		)
	end)
	if not success then
		warn("[S2Collector] Gagal kirim ke GAS: " .. tostring(err))
	end
end

local function buildEventId()
	return tostring(tick()):gsub("%.", "_")
end

-- ============================================================
-- PENDING EVENTS
-- ============================================================

local pendingEvents = {}

--[[local function finalize(eventId, pending)
	local r = pending.row
	if #pending.clientPosData > 0 then
		local sx, sy, sz = 0, 0, 0
		for _, p in ipairs(pending.clientPosData) do
			sx = sx + p.x
			sy = sy + p.y
			sz = sz + p.z
		end
		local n = #pending.clientPosData
		r.client_pos_x = sx / n
		r.client_pos_y = sy / n
		r.client_pos_z = sz / n
		r.client_receive_time = pending.clientReceiveTimes[1] or ""
	end
	pendingEvents[eventId] = nil
	sendPayload({ r })
end]]

local function finalize(eventId, pending)
	if #pending.clientRows > 0 then
		sendPayload(pending.clientRows)
	end
	pendingEvents[eventId] = nil
end

-- ============================================================
-- FUNGSI CATAT EVENT DRAG
-- eventType = "DragStart" | "DragStop"
-- item      = BasePart yang di-drag
-- player    = pemain yang melakukan drag
-- ============================================================

local function isItemInWorld(item)
	if not item then return false end

	-- Cek item langsung
	if CollectionService:HasTag(item, "Item") then
		return true
	end

	-- Cek parent (Handle di dalam Tool)
	local parent = item.Parent
	if parent and CollectionService:HasTag(parent, "Item") then
		return true
	end

	return false
end

local function recordDragEvent(eventType, item, player)
	if not isItemInWorld(item) then return end
	if not item or not (item:IsA("BasePart") or item:IsA("Model") or item:IsA("Tool")) then return end

	local allPlayers  = Players:GetPlayers()
	local playerCount = #allPlayers
	local serverPos   = item.Position
	local eventId     = buildEventId()

	local row = {
		-- common
		timestamp           = getTimestamp(),
		session_id          = CONFIG.SESSION_ID,
		scenario_id         = CONFIG.SCENARIO_ID,
		mechanism_type      = CONFIG.MECHANISM_TYPE,
		player_id           = tostring(player.UserId),
		player_count        = playerCount,
		event_type          = eventType,
		player_ping_ms      = PingService.getPing(player),
		server_event_time   = tick(),
		client_receive_time = "",

		-- specific scenario 2
		object_id           = item.Name,
		action_player_id    = tostring(player.UserId),
		server_pos_x        = math.floor(serverPos.X * 100) / 100,
		server_pos_y        = math.floor(serverPos.Y * 100) / 100,
		server_pos_z        = math.floor(serverPos.Z * 100) / 100,
		client_pos_x        = "",
		client_pos_y        = "",
		client_pos_z        = "",
	}

	if playerCount == 0 then
		sendPayload({ row })
		return
	end

	--[[pendingEvents[eventId] = {
		row                = row,
		clientCount        = playerCount,
		clientsReported    = 0,
		clientPosData      = {},
		clientReceiveTimes = {},
	}]]
	
	pendingEvents[eventId] = {
		rowTemplate        = row,
		clientCount        = playerCount,
		clientsReported    = 0,
		clientRows         = {},
	}

	-- Broadcast ke semua client: ada event drag, laporkan posisi item
	-- Kirim juga nama item agar client bisa baca posisinya sendiri
	S2ServerBroadcast:FireAllClients(eventId, item)

	-- Timeout fallback
	task.delay(CONFIG.CLIENT_TIMEOUT, function()
		local pending = pendingEvents[eventId]
		if not pending then return end
		finalize(eventId, pending)
	end)
end

-- ============================================================
-- HOOK KE DragEvent YANG SUDAH ADA
-- Dengarkan DragEvent yang sama, filter hanya Start & Stop
-- Tidak mengganggu handler drag yang sudah ada di script lain
-- ============================================================

local DragEvent = eventsFolder:WaitForChild("drag_event")

DragEvent.OnServerEvent:Connect(function(player, action, item)
	if action == "StartDrag" or action == "MobileStart" then
		recordDragEvent("DragStart", item, player)
	elseif action == "StopDrag" or action == "MobileStop" then
		recordDragEvent("DragStop", item, player)
	end
	-- UpdateDrag diabaikan (tidak dicatat)
end)

-- ============================================================
-- LISTENER: laporan posisi dari client
-- ============================================================

--[[S2ClientReport.OnServerEvent:Connect(function(_, eventId, clientReceiveTime, cx, cy, cz)
	local pending = pendingEvents[eventId]
	if not pending then return end

	table.insert(pending.clientPosData, { x = cx, y = cy, z = cz })
	table.insert(pending.clientReceiveTimes, clientReceiveTime)
	pending.clientsReported = pending.clientsReported + 1

	if pending.clientsReported >= pending.clientCount then
		finalize(eventId, pending)
	end
end)]]

S2ClientReport.OnServerEvent:Connect(function(sender, eventId, clientReceiveTime, cx, cy, cz)
	local pending = pendingEvents[eventId]
	if not pending then return end

	local r = {}
	for k, v in pairs(pending.rowTemplate) do r[k] = v end

	r.player_id           = tostring(sender.UserId)
	r.client_receive_time = clientReceiveTime
	r.client_pos_x        = cx
	r.client_pos_y        = cy
	r.client_pos_z        = cz

	table.insert(pending.clientRows, r)
	pending.clientsReported = pending.clientsReported + 1

	if pending.clientsReported >= pending.clientCount then
		finalize(eventId, pending)
	end
end)

-- ============================================================
-- INISIALISASI
-- ============================================================

print("[S2Collector] Siap. Scenario ID: " .. CONFIG.SCENARIO_ID)
print("[S2Collector] Session ID: "         .. CONFIG.SESSION_ID)
print("[S2Collector] Mencatat DragStart dan DragStop saja.")