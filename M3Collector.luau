
-- M3Collector.lua
-- Script — ServerScriptService
--
-- SCENARIO 3: GLOBAL STATE CHANGE
--
-- Event Type:
--   GeneratorInsert = player menambahkan fuel
--   GeneratorDrain  = sistem mengurangi fuel
--
-- Timestamp:
--   server_event_time
--       = saat server mulai memproses perubahan
--
--   server_state_change_time
--       = setelah server selesai mengubah GeneratorValue
--
--   client_receive_time
--       = saat client menerima perubahan dari server

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local generator      = workspace:WaitForChild("Generator_listrik_Genset")
local GeneratorValue = generator:WaitForChild("GeneratorValue")

local PingService = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("PingService")
)

-- CONFIGURATION

local CONFIG = {
	ENDPOINT       = "https://script.google.com/macros/s/AKfycbxe5GqxoYDLbSw4kqNKzIxYajpk0hoAstRKTe9Cq7-zjGzXOUarcnqlRiTfbUYn7zdL/exec",

	SESSION_ID     = nil,

	MECHANISM_TYPE = "generator",

	GENERATOR_ID   = "Genset_01",

	-- Maksimum waktu menunggu laporan client
	CLIENT_TIMEOUT = 2,
	SERVER_TIMEOUT = 5,
}

-- SESSION ID

local ok, SharedConfig = pcall(function()
	return require(
		ReplicatedStorage
			:WaitForChild("ScriptPenelitian")
			:WaitForChild("SharedConfig")
	)
end)

if ok and SharedConfig and SharedConfig.SESSION_ID then

	CONFIG.SESSION_ID = SharedConfig.SESSION_ID

else

	CONFIG.SESSION_ID = HttpService:GenerateGUID(false)

	warn(
		"[M3Collector] SharedConfig tidak ditemukan. " ..
			"Memakai session ID sendiri."
	)

end

-- REMOTE EVENTS

local eventsFolder = ReplicatedStorage:WaitForChild("Events")

-- Client → Server
local M3ClientReport = eventsFolder:FindFirstChild("M3ClientReport")

if not M3ClientReport then

	M3ClientReport = Instance.new("RemoteEvent")

	M3ClientReport.Name = "M3ClientReport"

	M3ClientReport.Parent = eventsFolder

	print("[M3Collector] M3ClientReport dibuat.")

end

-- Server → Client
local M3ServerBroadcast = eventsFolder:FindFirstChild("M3ServerBroadcast")

if not M3ServerBroadcast then

	M3ServerBroadcast = Instance.new("RemoteEvent")

	M3ServerBroadcast.Name = "M3ServerBroadcast"

	M3ServerBroadcast.Parent = eventsFolder

	print("[M3Collector] M3ServerBroadcast dibuat.")

end

-- BINDABLE FUNCTION
--
-- Dipanggil oleh script generator utama.

local M3RecordEvent = eventsFolder:FindFirstChild("M3RecordEvent")

if not M3RecordEvent then

	M3RecordEvent = Instance.new("BindableFunction")

	M3RecordEvent.Name = "M3RecordEvent"

	M3RecordEvent.Parent = eventsFolder

	print("[M3Collector] M3RecordEvent dibuat.")

end

-- HELPER

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

		warn(
			"[M3Collector] Gagal mengirim data: "
				.. tostring(err)
		)

	end

end


local function buildEventId()

	return HttpService:GenerateGUID(false)

end

-- PENDING EVENTS
--
-- Menyimpan event sampai client memberikan laporan.

local pendingEvents = {}

-- FINALIZE EVENT

local function finalize(eventId, pending)
	if not pending then return end

	if #pending.clientRows > 0 then
		sendPayload(pending.clientRows)
	else
		sendPayload({pending.rowTemplate})
	end
	pendingEvents[eventId] = nil

end

-- CREATE GENERATOR EVENT

--[[local function createGeneratorEvent(
	eventType,
	triggerPlayerId,
	oldValue,
	newValue,
	serverEventTime,
	serverStateChangeTime
)

	local allPlayers = Players:GetPlayers()

	local playerCount = #allPlayers

	-- ========================================================
	-- Hitung rata-rata ping player
	-- ========================================================

	local pingTotal = 0
	local pingCount = 0

	for _, player in ipairs(allPlayers) do

		local ping = PingService.getPing(player)

		if ping >= 0 then

			pingTotal += ping
			pingCount += 1

		end

	end

	local averagePing = -1

	if pingCount > 0 then

		averagePing = math.floor(
			pingTotal / pingCount
		)

	end

	-- ========================================================
	-- Event ID
	-- ========================================================

	local eventId = buildEventId()

	-- ========================================================
	-- Data server
	-- ========================================================

	local row = {

		timestamp = getTimestamp(),
		session_id = CONFIG.SESSION_ID,
		scenario_id = CONFIG.SCENARIO_ID,
		mechanism_type = CONFIG.MECHANISM_TYPE,

		-- PEMILIK DATA
		-- Akan diganti menjadi UserId client saat client report
		player_id = "server",

		player_count = playerCount,

		event_type = eventType,

		-- Player yang melakukan / menyebabkan aksi
		action_player_id = tostring(triggerPlayerId),

		server_avg_ping_ms = averagePing,
		
		player_ping_ms = -1,

		server_event_time = serverEventTime,

		server_state_change_time = serverStateChangeTime,

		client_receive_time = "",

		generator_id = CONFIG.GENERATOR_ID,

		fuel_before = oldValue,

		fuel_after = newValue,

		server_fuel_value = newValue,

		client_fuel_value = "",
	}

	-- ========================================================
	-- Jika tidak ada player
	-- ========================================================

	if playerCount == 0 then

		sendPayload({
			row
		})

		return

	end

	-- ========================================================
	-- Simpan pending event
	-- ========================================================

	pendingEvents[eventId] = {

		rowTemplate = row,

		clientCount = playerCount,

		clientsReported = 0,

		clientRows = {},
	}

	-- ========================================================
	-- Broadcast perubahan kepada semua client
	-- ========================================================

	M3ServerBroadcast:FireAllClients(eventId)

	-- ========================================================
	-- Timeout fallback
	-- ========================================================

	task.delay(CONFIG.CLIENT_TIMEOUT, function()

		local pending = pendingEvents[eventId]

		if not pending then
			return
		end

		finalize(
			eventId,
			pending
		)

	end)

end]]

-- RECEIVE EVENT FROM GENERATOR SYSTEM

M3RecordEvent.OnInvoke = function( eventType, actionPlayerId, oldValue, newValue,
	serverEventTime, serverStateChangeTime)

	local allPlayers = Players:GetPlayers()
	local playerCount = #allPlayers

	local pingTotal = 0
	local pingCount = 0

	for _, player in ipairs(allPlayers) do

		local ping = PingService.getPing(player)

		if ping >= 0 then
			pingTotal += ping
			pingCount += 1
		end

	end

	local averagePing = -1

	if pingCount > 0 then
		averagePing = math.floor(
			pingTotal / pingCount
		)
	end

	-- ========================================================
	-- Buat Event ID
	-- ========================================================

	local eventId = buildEventId()
	local row = {
		timestamp = getTimestamp(),
		session_id = CONFIG.SESSION_ID,
		mechanism_type = CONFIG.MECHANISM_TYPE,
		player_id = "server",
		player_count = playerCount,
		event_type = eventType,
		action_player_id = tostring(actionPlayerId),
		player_ping_ms = averagePing,
		fps = "",
		server_event_time = serverEventTime,
		server_state_change_time = serverStateChangeTime,
		client_receive_time = "",
		generator_id = CONFIG.GENERATOR_ID,
		fuel_before = oldValue,
		fuel_after = newValue,
		server_fuel_value = newValue,
		client_fuel_value = "",
	}

	-- ========================================================
	-- Kalau tidak ada player
	-- ========================================================

	if playerCount == 0 then sendPayload ({row})return true end

	pendingEvents[eventId] = { rowTemplate = row, clientCount = playerCount,
		clientsReported = 0, clientRows = {},}

	M3ServerBroadcast:FireAllClients(eventId)

	task.delay(CONFIG.SERVER_TIMEOUT, function()

		local pending = pendingEvents[eventId]
		if not pending then return end
		finalize( eventId, pending)
	end)
	return true
end

-- RECEIVE EVENT FROM GENERATOR SYSTEMS

M3ClientReport.OnServerEvent:Connect(function(sender, eventId, clientReceiveTime,
	clientFuelValue, fps)

	local pending = pendingEvents[eventId]
	if not pending then return end

	for _, existingRow in ipairs(pending.clientRows) do
		if existingRow.player_id == tostring(sender.UserId) then
			return
		end

	end

	local row = {}
	for key, value in pairs(pending.rowTemplate) do
		row[key] = value
	end

	row.player_id = tostring(sender.UserId)
	row.client_receive_time = clientReceiveTime
	row.client_fuel_value = clientFuelValue
	row.fps = fps
	row.player_ping_ms = PingService.getPing(sender)

	table.insert(
		pending.clientRows,
		row
	)

	pending.clientsReported += 1

	if pending.clientsReported >= pending.clientCount then
		finalize(
			eventId,
			pending
		)
	end
end)

-- INITIALIZATION

print("[M3Collector] ===============================")
print("[M3Collector] Scenario 3 Collector Ready")
print("[M3Collector] Generator ID : " .. CONFIG.GENERATOR_ID)
print("[M3Collector] Session ID   : " .. CONFIG.SESSION_ID)
print("[M3Collector] Timeout      : " .. CONFIG.CLIENT_TIMEOUT)
print("[M3Collector] ===============================")
