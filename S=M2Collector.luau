local HttpService =game:GetService("HttpService")
local Players =game:GetService("Players")
local ReplicatedStorage =game:GetService("ReplicatedStorage")

local PingService =require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PingService"))


-- CONFIG

local CONFIG = {
	ENDPOINT =
		"insert your endpoint apps script",
	SESSION_ID = nil,
	MECHANISM_TYPE = "drag",
	SAMPLING_INTERVAL = 1,
	CLIENT_TIMEOUT = 2,
	SERVER_TIMEOUT = 5,
	-- PATCH: pengaman kedua. Kalau satu dragId entah kenapa masih
	-- hidup lebih lama dari ini (detik), paksa hentikan loop
	-- sampling-nya. Ini jaring pengaman terakhir di luar fix utama.
	MAX_DRAG_DURATION = 120,

}


-- SESSION

local ok, SharedConfig =
	pcall(function()

		return require(
			ReplicatedStorage
			:WaitForChild("ScriptPenelitian")
			:WaitForChild("SharedConfig")
		)

	end)


CONFIG.SESSION_ID =
	(ok and SharedConfig and SharedConfig.SESSION_ID)
	or HttpService:GenerateGUID(false)


-- EVENTS

local Events =
	ReplicatedStorage:WaitForChild("Events")


local function getOrCreateRemote(name)

	local remote =
		Events:FindFirstChild(name)


	if not remote then

		remote =
			Instance.new("RemoteEvent")

		remote.Name =
			name

		remote.Parent =
			Events

	end


	return remote

end


local M2ServerBroadcast =
	getOrCreateRemote(
		"M2ServerBroadcast"
	)


local M2ClientReport =
	getOrCreateRemote(
		"M2ClientReport"
	)


local M2PositionUpdated =
	Events:WaitForChild(
		"M2PositionUpdated"
	)


local M2DragStarted =
	Events:WaitForChild(
		"M2DragStarted"
	)


local M2DragStopped =
	Events:WaitForChild(
		"M2DragStopped"
	)


-- UTIL

local function getTimestamp()

	return os.date(
		"!%Y-%m-%dT%H:%M:%SZ"
	)

end


local function getServerTime()

	return workspace:GetServerTimeNow()

end


local function round(value)

	return math.floor(
		value * 100
	) / 100

end


-- HTTP

local function sendPayload(payload)

	local success, err =
		pcall(function()

			HttpService:PostAsync(

				CONFIG.ENDPOINT,

				HttpService:JSONEncode(
					payload
				),

				Enum.HttpContentType.ApplicationJson,

				false

			)

		end)


	if not success then

		warn(
			"[M2Collector] Gagal kirim:",
			err
		)

	end

end


-- ACTIVE DRAGS

local activeDrags = {}
local sampleIdToDragId = {}


-- CREATE DRAG SESSION

local function createDragSession(

	player,

	item,

	serverEventTime,

	serverStateChangeTime,

	x,
	y,
	z

)

	local dragId =
		HttpService:GenerateGUID(false)


	activeDrags[dragId] = {

		dragId =
			dragId,

		player =
			player,

		item =
			item,

		startTime =
			getServerTime(),

		lastServerEventTime =
			serverEventTime,

		lastServerStateChangeTime =
			serverStateChangeTime,

		lastX =
			x,

		lastY =
			y,

		lastZ =
			z,

		sequence =
			0,

		isActive =
			true,

	}


	return dragId

end


-- UPDATE LATEST SERVER STATE

M2PositionUpdated.Event:Connect(function( player, item, serverEventTime, serverStateChangeTime,
	x, y, z )

		for _, data in pairs(activeDrags) do
			if
				data.player == player
				and data.item == item
				and data.isActive
			then
				data.lastServerEventTime = serverEventTime
				data.lastServerStateChangeTime = serverStateChangeTime
				data.lastX = x
				data.lastY = y
				data.lastZ = z
				return
			end
		end
	end
)


-- CREATE ROW TEMPLATE

local function createRow(

	data,

	samplingTime

)

	data.sequence += 1


	return {

		timestamp =
			getTimestamp(),

		session_id =
			CONFIG.SESSION_ID,

		mechanism_type =
			CONFIG.MECHANISM_TYPE,

		player_id =
			"",

		player_count =
			#Players:GetPlayers(),

		event_type =
			"DraggingObject",

		player_ping_ms =
			"",

		fps =
			"",

		sampling_time =
			samplingTime,

		server_event_time =
			data.lastServerEventTime,

		server_state_change_time =
			data.lastServerStateChangeTime,

		client_receive_time =
			"",

		object_id =	
			data.item.Name,

		action_player_id =
			tostring(
				data.player.UserId
			),

		server_pos_x =
			round(data.lastX),

		server_pos_y =
			round(data.lastY),

		server_pos_z =
			round(data.lastZ),

		client_pos_x =
			"",

		client_pos_y =
			"",

		client_pos_z =
			"",

	}

end


-- SAMPLING

local function performSampling( data, samplingTime, isFinal )

	if not data or not data.isActive then
		return
	end

	local expectedClients = Players:GetPlayers()

	local pending = {
		rows = {},
		reported = 0,
		expected = #expectedClients,
		createdAt = os.clock(),
	}

	local row = createRow( data, samplingTime )
	local sampleId = HttpService:GenerateGUID(false)
	
	M2ServerBroadcast:FireAllClients( sampleId, data.item )
	
	data.pendingSamples = data.pendingSamples or {}

	data.pendingSamples[sampleId] = {
		sampleId = sampleId,
		row = row,
		pending = pending,
		isFinal = isFinal,
	}

	sampleIdToDragId[sampleId] = data.dragId
	
	task.delay(CONFIG.SERVER_TIMEOUT, function()

		local sample = data.pendingSamples and data.pendingSamples[sampleId]

		if sample then

			local rows = sample.pending.rows

			if #rows > 0 then
				sendPayload(rows)
			end

			data.pendingSamples[sampleId] = nil
			sampleIdToDragId[sampleId] = nil

		end

	end)

end


-- DRAG START

M2DragStarted.Event:Connect(
	function( player, item, serverEventTime, serverStateChangeTime, x, y, z)

		local dragId =
			createDragSession( player, item, serverEventTime, serverStateChangeTime, x, y, z )

		local data = activeDrags[dragId]

		performSampling(data,0,false)
		
		task.spawn(function()
			local nextSample = CONFIG.SAMPLING_INTERVAL
			while
				data.isActive
			do
				local elapsed = getServerTime() - data.startTime

				if elapsed > CONFIG.MAX_DRAG_DURATION then
					warn(
						"[M2Collector] Drag session melebihi batas wajar, dipaksa berhenti:",
						data.dragId
					)
					data.isActive =
						false
					break
				end


				if elapsed >= nextSample then
					performSampling(data,round(elapsed),false)

					nextSample += CONFIG.SAMPLING_INTERVAL
				end
				task.wait(0.05)
			end
		end)
	end)


-- ===================================================	=========
-- DRAG STOP

M2DragStopped.Event:Connect(function( player, item, serverEventTime, serverStateChangeTime,
		x, y, z )
		
		for dragId, data in pairs(activeDrags) do
			if
				data.player == player
				and data.item == item
				and data.isActive
			then data.lastServerEventTime = serverEventTime
				data.lastServerStateChangeTime = serverStateChangeTime
				data.lastX = x
				data.lastY = y
				data.lastZ = z

				local elapsed = getServerTime() - data.startTime
				performSampling( data, round(elapsed), true )
				data.isActive = false

				task.delay( CONFIG.CLIENT_TIMEOUT + 0.5, function()
						activeDrags[dragId] = nil
					end
				)
			end
		end
	end)


-- CLIENT REPORT

M2ClientReport.OnServerEvent:Connect(function( sender, sampleId, clientReceiveTime, clientFPS,
	clientX, clientY, clientZ)

	local dragId = sampleIdToDragId[sampleId]
	local data = dragId and activeDrags[dragId]
	if not data then return end

	local sample = data.pendingSamples and data.pendingSamples[sampleId]
	if not sample then return end

	local row = {}
	for key, value in pairs(sample.row) do
		row[key] = value
	end

	row.player_id       = tostring(sender.UserId)
	row.player_ping_ms  = PingService.getPing(sender)
	row.fps             = clientFPS
	row.client_receive_time = clientReceiveTime
	row.client_pos_x    = clientX
	row.client_pos_y    = clientY
	row.client_pos_z    = clientZ

	table.insert(sample.pending.rows, row)

	sample.pending.reported += 1

	if sample.pending.reported >= sample.pending.expected then
		sendPayload(sample.pending.rows)
		data.pendingSamples[sampleId] = nil
		sampleIdToDragId[sampleId] = nil
	end
end)


print(
	"[M2Collector] ============================="
)

print(
	"[M2Collector] Scenario 2 READY"
)

print(
	"[M2Collector] Sampling: 0s + every 1s + final"
)

print(
	"[M2Collector] Event: DraggingObject"
)

print(
	"[M2Collector] Metrics: A → B → C"
)

print(
	"[M2Collector] FPS: Client"
)

print(
	"[M2Collector] PATCH: stop ALL matching dragIds + max duration safety cap"
)

print(
	"[M2Collector] ============================="
)
