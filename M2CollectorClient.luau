
-- M2CollectorClient.client.lua
--
-- Scenario 2
--
-- Client menerima marker dari server pada setiap sampling.
--
-- C = client_receive_time
-- FPS = FPS client ketika menerima marker

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")


local Events =
	ReplicatedStorage:WaitForChild(
		"Events"
	)


local M2ServerBroadcast =
	Events:WaitForChild(
		"M2ServerBroadcast"
	)


local M2ClientReport =
	Events:WaitForChild(
		"M2ClientReport"
	)


-- FPS SAMPLING

local frameCount = 0
local elapsedTime = 0

local clientFPS = 60


RunService.RenderStepped:Connect(
	function(dt)

		if dt <= 0 then
			return
		end


		frameCount += 1

		elapsedTime += dt


		if elapsedTime >= 1 then

			clientFPS =
				frameCount
				/ elapsedTime


			frameCount = 0

			elapsedTime = 0

		end

	end
)


-- UTIL

local function getServerTime()

	return workspace:GetServerTimeNow()

end


local function round(value)

	return math.floor(
		value * 100
	) / 100

end


-- RECEIVE SAMPLE

M2ServerBroadcast.OnClientEvent:Connect(function(sampleId,item)
	
	local clientReceiveTime = getServerTime()

		local currentFPS = math.floor(clientFPS * 100) / 100

		local x = 0
		local y = 0
		local z = 0

		if item and item:IsA("BasePart") then
			local position = item.Position
			x = round( position.X )
			y = round( position.Y )
			z = round( position.Z )
		end
		
		M2ClientReport:FireServer( sampleId, clientReceiveTime, currentFPS, x, y, z )
	end
)


print(
	"[M2CollectorClient] READY"
)

print(
	"[M2CollectorClient] Client FPS tracking: ON"
)
