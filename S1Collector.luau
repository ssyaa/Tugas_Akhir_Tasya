local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PingService = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("PingService")
)

local CONFIG = {
	ENDPOINT =
		-

	SESSION_ID     = nil,
	MECHANISM_TYPE = "chop",

	CLIENT_TIMEOUT = 2,
	SERVER_TIMEOUT = 5,
}

local ok, SharedConfig = pcall(function()
	return require(
		ReplicatedStorage
			:WaitForChild("ScriptPenelitian")
			:WaitForChild("SharedConfig")
	)
end)

CONFIG.SESSION_ID =
	(ok and SharedConfig and SharedConfig.SESSION_ID)
	or HttpService:GenerateGUID(false)

if not (ok and SharedConfig) then
	warn("[M1Collector] SharedConfig tidak ditemukan, pakai session ID sendiri.")
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

local M1ServerBroadcast = getOrCreate("M1ServerBroadcast")
local M1ClientReport    = getOrCreate("M1ClientReport")

local M1TreeBroke = eventsFolder:FindFirstChild("M1TreeBroke")

if not M1TreeBroke then
	M1TreeBroke = Instance.new("BindableEvent")
	M1TreeBroke.Name = "M1TreeBroke"
	M1TreeBroke.Parent = eventsFolder
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
		warn("[M1Collector] Gagal kirim ke GAS: " .. tostring(err))
	end
end

local function makeObjectId(tree)
	local pos = tree.Position

	return string.format(
		"%s_%.0f_%.0f_%.0f",
		tree.Name,
		math.floor(pos.X),
		math.floor(pos.Y),
		math.floor(pos.Z)
	)
end

-- PENDING BATCH

local pendingBatches = {}
local eventIdToBatch = {}

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

-- TREE BROKE

M1TreeBroke.Event:Connect(function(
	player,
	tree,
	logs,
	serverProcessStart,
	serverStateChangeTime
)

	if not player or not tree or not logs then
		return
	end

	local allPlayers = Players:GetPlayers()
	local playerCount = #allPlayers
	local treeObjectId = makeObjectId(tree)
	local timestamp = getTimestamp()
	local batchId = HttpService:GenerateGUID(false)
	local rows = {}
	local eventIdToIndex = {}

	-- BUAT IDENTITAS UNTUK SETIAP LOG

	for i, log in ipairs(logs) do
		local eventId = HttpService:GenerateGUID(false)
		eventIdToIndex[eventId] = i
		eventIdToBatch[eventId] = batchId
		log:SetAttribute("M1EventId", eventId)
		rows[i] = {
			timestamp = timestamp,
			session_id = CONFIG.SESSION_ID,
			mechanism_type = CONFIG.MECHANISM_TYPE,
			player_id = tostring(player.UserId),
			player_count = playerCount,
			event_type = "LogSpawned",
			player_ping_ms = PingService.getPing(player),
			server_event_time = serverProcessStart,
			server_state_change_time = serverStateChangeTime,
			client_receive_time = "",
			fps = "",
			object_id = treeObjectId,
			object_type = "log",
			action_player_id = tostring(player.UserId),
			server_object_status = "spawned",
			client_object_status = "",
		}
	end

	if playerCount == 0 then
		sendPayload(rows)
		return
	end

	-- SIMPAN PENDING

	pendingBatches[batchId] = {
		rowTemplates = rows,
		eventIdToIndex = eventIdToIndex,
		totalLogs = #logs,
		playerCount = playerCount,
		reportsReceived = {},
		clientRows = {},
	}

	M1ServerBroadcast:FireAllClients(batchId, eventIdToIndex, CONFIG.CLIENT_TIMEOUT)

	task.delay(CONFIG.SERVER_TIMEOUT, function()
		local batch = pendingBatches[batchId]
		if not batch then return end
		finalizeBatch(batchId, batch)
	end)
end)

-- CLIENT REPORT

M1ClientReport.OnServerEvent:Connect(function(
	sender,
	eventId,
	clientReceiveTime,
	clientStatus,
	fps
)
	local batchId = eventIdToBatch[eventId]
	if not batchId then return end
	
	local batch = pendingBatches[batchId]
	if not batch then return end

	local rowIndex = batch.eventIdToIndex[eventId]
	if not rowIndex then return end

	local r = {}
	for k, v in pairs(batch.rowTemplates[rowIndex]) do
		r[k] = v
	end

	r.player_id = tostring(sender.UserId)
	r.client_receive_time = clientReceiveTime
	r.client_object_status = clientStatus
	r.fps = fps
	r.player_ping_ms = PingService.getPing(sender)
	table.insert(batch.clientRows, r)

	batch.reportsReceived[rowIndex] =
		(batch.reportsReceived[rowIndex] or 0) + 1

	checkBatchComplete(batchId)
end)

print("[M1Collector] Siap.")
print("[M1Collector] Session ID: " .. CONFIG.SESSION_ID)
