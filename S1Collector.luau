-- ============================================================
-- S1Collector.lua  (Script — ServerScriptService)
-- 1 pohon = 4 log = 1 HTTP request batch ke GAS
-- Pakai attribute S1EventId di tiap log agar client bisa temukan
-- tanpa mengganggu nama/gameplay log
-- ============================================================

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PingService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PingService"))

local CONFIG = {
	ENDPOINT       =
		"https://script.google.com/macros/s/AKfycbxe5GqxoYDLbSw4kqNKzIxYajpk0hoAstRKTe9Cq7-zjGzXOUarcnqlRiTfbUYn7zdL/exec",
	SESSION_ID     = nil,
	SCENARIO_ID    = 1,
	MECHANISM_TYPE = "chop",
	CLIENT_TIMEOUT = 2,
}

local ok, SharedConfig = pcall(function()
	return require(ReplicatedStorage:WaitForChild("ScriptPenelitian"):WaitForChild("SharedConfig"))
end)
CONFIG.SESSION_ID = (ok and SharedConfig and SharedConfig.SESSION_ID)
	or HttpService:GenerateGUID(false)

if not (ok and SharedConfig) then
	warn("[S1Collector] SharedConfig tidak ditemukan, pakai session ID sendiri.")
end

local eventsFolder = ReplicatedStorage:WaitForChild("Events")

local function getOrCreate(name)
	local re = eventsFolder:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = eventsFolder
	end
	return re
end

local S1ServerBroadcast = getOrCreate("S1ServerBroadcast")
local S1ClientReport    = getOrCreate("S1ClientReport")

local S1TreeBroke = eventsFolder:FindFirstChild("S1TreeBroke")
if not S1TreeBroke then
	S1TreeBroke = Instance.new("BindableEvent")
	S1TreeBroke.Name = "S1TreeBroke"
	S1TreeBroke.Parent = eventsFolder
end

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
		warn("[S1Collector] Gagal kirim ke GAS: " .. tostring(err))
	end
end

local function makeObjectId(tree)
	local pos = tree.Position
	return string.format("%s_%.0f_%.0f_%.0f",
		tree.Name, math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z))
end

local pendingBatches = {}
local eventIdToBatch = {}

--[[local function finalizeBatch(batchId, batch)
	for i, row in ipairs(batch.rows) do
		local data = batch.clientData[i]
		if data then
			row.client_object_status        = data.status
			row.client_spawn_receive_time   = data.receiveTime
			row.client_receive_time         = data.receiveTime
		end
	end

	for eventId in pairs(batch.eventIdToIndex) do
		eventIdToBatch[eventId] = nil
	end

	pendingBatches[batchId] = nil
	sendPayload(batch.rows)
end]]

local function finalizeBatch(batchId, batch)
	for eventId in pairs(batch.eventIdToIndex) do
		eventIdToBatch[eventId] = nil
	end
	pendingBatches[batchId] = nil
	sendPayload(batch.clientRows)
end

local function checkBatchComplete(batchId)
	local batch = pendingBatches[batchId]
	if not batch then return end
	for i = 1, batch.totalLogs do
		if (batch.reportsReceived[i] or 0) < batch.playerCount then
			return
		end
	end
	finalizeBatch(batchId, batch)
end

-- ============================================================
-- LISTENER: pohon hancur dari tree_handler
-- ============================================================

S1TreeBroke.Event:Connect(function(player, tree, logs)
	if not player or not tree or not logs then return end

	local allPlayers      = Players:GetPlayers()
	local playerCount     = #allPlayers
	local treeObjectId    = makeObjectId(tree)
	local serverSpawnTime = tick()
	local timestamp       = getTimestamp()
	local batchId         = HttpService:GenerateGUID(false)

	local rows           = {}
	local eventIdToIndex = {}

	for i, log in ipairs(logs) do
		local eventId = HttpService:GenerateGUID(false)
		eventIdToIndex[eventId] = i
		eventIdToBatch[eventId] = batchId

		-- Set attribute di log agar client bisa temukan via scan
		-- Tidak mengubah nama, tidak mengganggu gameplay
		log:SetAttribute("S1EventId", eventId)

		rows[i] = {
			timestamp                 = timestamp,
			session_id                = CONFIG.SESSION_ID,
			scenario_id               = CONFIG.SCENARIO_ID,
			mechanism_type            = CONFIG.MECHANISM_TYPE,
			player_id                 = tostring(player.UserId),
			player_count              = playerCount,
			event_type                = "LogSpawned",
			player_ping_ms            = PingService.getPing(player),
			server_event_time         = serverSpawnTime,
			client_receive_time       = "",
			object_id                 = treeObjectId,
			object_type               = "log",
			action_player_id          = tostring(player.UserId),
			server_object_status      = "spawned",
			client_object_status      = "",
			server_spawn_time         = serverSpawnTime,
			client_spawn_receive_time = "",
		}
	end

	if playerCount == 0 then
		sendPayload(rows)
		return
	end

	--[[pendingBatches[batchId] = {
		rows             = rows,
		eventIdToIndex   = eventIdToIndex,
		totalLogs        = #logs,
		playerCount      = playerCount,
		reportsReceived  = {},
		clientData       = {},
	}]]
	
	pendingBatches[batchId] = {
		rowTemplates     = rows,  -- ganti dari rows
		eventIdToIndex   = eventIdToIndex,
		totalLogs        = #logs,
		playerCount      = playerCount,
		reportsReceived  = {},
		clientRows       = {},    -- semua baris hasil per client
	}

	-- Broadcast ke client: kirim batchId + daftar eventId saja
	-- Client akan scan workspace.Items berdasarkan attribute S1EventId
	S1ServerBroadcast:FireAllClients(batchId, eventIdToIndex)

	task.delay(CONFIG.CLIENT_TIMEOUT, function()
		local batch = pendingBatches[batchId]
		if not batch then return end
		finalizeBatch(batchId, batch)
	end)
end)

-- ============================================================
-- LISTENER: laporan dari client
-- ============================================================

S1ClientReport.OnServerEvent:Connect(function(sender, eventId, clientReceiveTime, clientStatus)
	local batchId = eventIdToBatch[eventId]
	if not batchId then return end

	local batch = pendingBatches[batchId]
	if not batch then return end

	local rowIndex = batch.eventIdToIndex[eventId]
	if not rowIndex then return end

	local r = {}
	for k, v in pairs(batch.rowTemplates[rowIndex]) do r[k] = v end

	r.player_id                 = tostring(sender.UserId)
	r.client_receive_time       = clientReceiveTime
	r.client_spawn_receive_time = clientReceiveTime
	r.client_object_status      = clientStatus

	table.insert(batch.clientRows, r)
	batch.reportsReceived[rowIndex] = (batch.reportsReceived[rowIndex] or 0) + 1
	checkBatchComplete(batchId)
end)

--[[S1ClientReport.OnServerEvent:Connect(function(_, eventId, clientReceiveTime, clientStatus)
	local batchId = eventIdToBatch[eventId]
	if not batchId then return end

	local batch = pendingBatches[batchId]
	if not batch then return end

	local rowIndex = batch.eventIdToIndex[eventId]
	if not rowIndex then return end

	if not batch.clientData[rowIndex] then
		batch.clientData[rowIndex] = {
			status      = clientStatus,
			receiveTime = clientReceiveTime,
		}
	end

	batch.reportsReceived[rowIndex] = (batch.reportsReceived[rowIndex] or 0) + 1
	checkBatchComplete(batchId)
end)]]

print("[S1Collector] Siap. Session ID: " .. CONFIG.SESSION_ID)
print("[S1Collector] Batch mode: 4 log = 1 HTTP request")