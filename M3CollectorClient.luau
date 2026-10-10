local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local generator = workspace:WaitForChild(
	"Generator_listrik_Genset"
)

local GeneratorValue = generator:WaitForChild(
	"GeneratorValue"
)

local eventsFolder = ReplicatedStorage:WaitForChild(
	"Events"
)

-- Server → Client
local M3ServerBroadcast = eventsFolder:WaitForChild(
	"M3ServerBroadcast"
)

-- Client → Server
local M3ClientReport = eventsFolder:WaitForChild(
	"M3ClientReport"
)

-- FPS COUNTER

local frameCount = 0
local elapsedTime = 0
local currentFPS = 0

RunService.RenderStepped:Connect(function(deltaTime)

	frameCount += 1
	elapsedTime += deltaTime

	if elapsedTime >= 1 then

		currentFPS = math.floor(
			frameCount / elapsedTime
		)

		frameCount = 0
		elapsedTime = 0

	end

end)

-- SERVER BROADCAST

M3ServerBroadcast.OnClientEvent:Connect(function(eventId)

	local clientReceiveTime = workspace:GetServerTimeNow()
	local clientFuelValue = GeneratorValue.Value
	local fps =  currentFPS

	M3ClientReport:FireServer( eventId, clientReceiveTime, clientFuelValue, fps )
end)

print("[M3CollectorClient] Ready.")
