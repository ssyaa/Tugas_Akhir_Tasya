-- ============================================================
-- S3Collector.lua  (Script — ServerScriptService)
-- Kirim data generator (scenario_id = 3) ke Google Apps Script
-- Menunggu konfirmasi client sebelum kirim ke GAS
-- ============================================================

local HttpService        = game:GetService("HttpService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local generator          = workspace:WaitForChild("Generator_listrik_Genset")
local GeneratorValue     = generator:WaitForChild("GeneratorValue")
local PingService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PingService"))

-- ============================================================
-- KONFIGURASI
-- ============================================================

local CONFIG = {
	ENDPOINT        = "https://script.google.com/macros/s/AKfycbxe5GqxoYDLbSw4kqNKzIxYajpk0hoAstRKTe9Cq7-zjGzXOUarcnqlRiTfbUYn7zdL/exec",
	SESSION_ID      = nil,
	SCENARIO_ID     = 3,
	MECHANISM_TYPE  = "generator",
	GENERATOR_ID    = "Genset_01",

	-- Berapa lama (detik) server tunggu laporan client sebelum kirim tanpa data client
	CLIENT_TIMEOUT  = 2,
}

local ok, SharedConfig = pcall(function()
	return require(ReplicatedStorage:WaitForChild("ScriptPenelitian"):WaitForChild("SharedConfig"))
end)

if ok and SharedConfig and SharedConfig.SESSION_ID then
	CONFIG.SESSION_ID = SharedConfig.SESSION_ID
else
	CONFIG.SESSION_ID = HttpService:GenerateGUID(false)
	warn("[S3Collector] SharedConfig tidak ditemukan, pakai session ID sendiri.")
end

-- ============================================================
-- REMOTE EVENTS — buat otomatis jika belum ada
-- ============================================================

local eventsFolder = ReplicatedStorage:WaitForChild("Events")

local S3ClientReport = eventsFolder:FindFirstChild("S3ClientReport")
if not S3ClientReport then
	S3ClientReport = Instance.new("RemoteEvent")
	S3ClientReport.Name = "S3ClientReport"
	S3ClientReport.Parent = eventsFolder
	print("[S3Collector] RemoteEvent S3ClientReport dibuat otomatis.")
end

local S3ServerBroadcast = eventsFolder:FindFirstChild("S3ServerBroadcast")
if not S3ServerBroadcast then
	S3ServerBroadcast = Instance.new("RemoteEvent")
	S3ServerBroadcast.Name = "S3ServerBroadcast"
	S3ServerBroadcast.Parent = eventsFolder
	print("[S3Collector] RemoteEvent S3ServerBroadcast dibuat otomatis.")
end

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
		warn("[S3Collector] Gagal kirim ke GAS: " .. tostring(err))
	end
end

-- ============================================================
-- PENDING EVENTS
-- Saat GeneratorValue berubah, server simpan dulu data servernya.
-- Client akan melaporkan nilai mereka, lalu server kirim ke GAS.
-- ============================================================

local pendingEvents = {}

local function buildEventId()
	return tostring(tick()):gsub("%.", "_")
end

--[[local function finalize(eventId, pending)
	local r = pending.row
	if #pending.clientReceiveTimes > 0 then
		local sumTime, sumFuel = 0, 0
		for _, v in ipairs(pending.clientReceiveTimes) do sumTime = sumTime + v end
		for _, v in ipairs(pending.clientFuelValues)   do sumFuel = sumFuel + v end
		r.client_receive_time = sumTime / #pending.clientReceiveTimes
		r.client_fuel_value   = sumFuel / #pending.clientFuelValues
	end
	pendingEvents[eventId] = nil
	sendPayload({ r })
end]]

--[[local function finalize(eventId, pending)
	for _, clientData in ipairs(pending.clientRows) do
		sendPayload({ clientData })
	end
	pendingEvents[eventId] = nil
end]]

local function finalize(eventId, pending)
	if #pending.clientRows > 0 then
		sendPayload(pending.clientRows)
	end
	pendingEvents[eventId] = nil
end

-- ============================================================
-- LISTENER: perubahan GeneratorValue di server
-- ============================================================

local lastValue = GeneratorValue.Value

GeneratorValue:GetPropertyChangedSignal("Value"):Connect(function()
	local newValue  = GeneratorValue.Value
	local oldValue  = lastValue
	lastValue       = newValue

	if math.abs(newValue - oldValue) < 0.001 then return end

	local allPlayers  = Players:GetPlayers()
	local playerCount = #allPlayers
	local eventId     = buildEventId()

	local row = {
		timestamp           = getTimestamp(),
		session_id          = CONFIG.SESSION_ID,
		scenario_id         = CONFIG.SCENARIO_ID,
		mechanism_type      = CONFIG.MECHANISM_TYPE,
		player_id           = "server",
		player_count        = playerCount,
		event_type          = "GeneratorFuelChange",
		player_ping_ms      = (function()
			local total, count = 0, 0
			for _, p in ipairs(allPlayers) do
				local ping = PingService.getPing(p)
				if ping >= 0 then
					total = total + ping
					count = count + 1
				end
			end
			return count > 0 and math.floor(total / count) or -1
		end)(),
		server_event_time   = tick(),
		client_receive_time = "",
		generator_id        = CONFIG.GENERATOR_ID,
		fuel_before         = oldValue,
		fuel_after          = newValue,
		server_fuel_value   = newValue,
		client_fuel_value   = "",
	}

	if playerCount == 0 then
		sendPayload({ row })
		return
	end

	--[[pendingEvents[eventId] = {
		row                 = row,
		clientCount         = playerCount,
		clientsReported     = 0,
		clientReceiveTimes  = {},
		clientFuelValues    = {},
	}]]
	
	pendingEvents[eventId] = {
		rowTemplate         = row,
		clientCount         = playerCount,
		clientsReported     = 0,
		clientRows          = {},   -- ? ganti dari clientReceiveTimes & clientFuelValues
	}

	-- Minta semua client lapor
	S3ServerBroadcast:FireAllClients(eventId)

	-- Timeout fallback
	task.delay(CONFIG.CLIENT_TIMEOUT, function()
		local pending = pendingEvents[eventId]
		if not pending then return end
		finalize(eventId, pending)
	end)
end)

-- ============================================================
-- LISTENER: laporan dari client
-- ============================================================

--[[S3ClientReport.OnServerEvent:Connect(function(_, eventId, clientReceiveTime, clientFuelValue)
	local pending = pendingEvents[eventId]
	if not pending then return end

	table.insert(pending.clientReceiveTimes, clientReceiveTime)
	table.insert(pending.clientFuelValues, clientFuelValue)
	pending.clientsReported = pending.clientsReported + 1

	if pending.clientsReported >= pending.clientCount then
		finalize(eventId, pending)
	end
end)]]

S3ClientReport.OnServerEvent:Connect(function(sender, eventId, clientReceiveTime, clientFuelValue)
	local pending = pendingEvents[eventId]
	if not pending then return end

	local r = {}
	for k, v in pairs(pending.rowTemplate) do r[k] = v end

	r.player_id           = tostring(sender.UserId)  -- ? pakai UserId client
	r.client_receive_time = clientReceiveTime
	r.client_fuel_value   = clientFuelValue

	table.insert(pending.clientRows, r)
	pending.clientsReported = pending.clientsReported + 1

	if pending.clientsReported >= pending.clientCount then
		finalize(eventId, pending)
	end
end)

-- ============================================================
-- INISIALISASI
-- ============================================================

print("[S3Collector] Siap. Generator ID: " .. CONFIG.GENERATOR_ID)
print("[S3Collector] Session ID: "          .. CONFIG.SESSION_ID)
print("[S3Collector] Timeout client: "      .. CONFIG.CLIENT_TIMEOUT .. " detik")
print("[S3Collector] Menunggu perubahan GeneratorValue...")