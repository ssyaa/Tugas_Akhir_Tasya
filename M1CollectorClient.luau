local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local eventsFolder = ReplicatedStorage:WaitForChild("Events")

local M1ServerBroadcast =
	eventsFolder:WaitForChild("M1ServerBroadcast")

local M1ClientReport =
	eventsFolder:WaitForChild("M1ClientReport")


-- FPS COUNTER

local frameCount = 0
local fps = 0
local fpsTimer = 0

RunService.RenderStepped:Connect(function(deltaTime)

	frameCount += 1
	fpsTimer += deltaTime

	if fpsTimer >= 1 then

		fps = frameCount / fpsTimer

		frameCount = 0
		fpsTimer = 0

	end

end)


-- FIND OBJECT

local function waitForObject(eventId, timeout)

	local startTime = os.clock()

	local itemsFolder =
		workspace:FindFirstChild("Items")

	if not itemsFolder then
		return nil
	end

	while os.clock() - startTime < timeout do

		for _, obj in ipairs(itemsFolder:GetChildren()) do

			if obj:GetAttribute("M1EventId") == eventId then
				return obj
			end

		end

		RunService.Heartbeat:Wait()

	end

	return nil
end


-- SERVER BROADCAST

M1ServerBroadcast.OnClientEvent:Connect(function(batchId, eventIdToIndex, clientTimeout)
	for eventId, _ in pairs(eventIdToIndex) do
		local obj = waitForObject(eventId, clientTimeout)

		local clientReceiveTime = ""
		local clientStatus = "not_replicated"

		if obj then
			clientReceiveTime = workspace:GetServerTimeNow()
			if obj.Transparency < 1 then
				clientStatus = "visible"
			else
				clientStatus = "invisible"
			end
		end

		M1ClientReport:FireServer(
			eventId,
			clientReceiveTime,
			clientStatus,
			math.floor(fps * 100) / 100
		)
	end
end)

print("[M1Client] Siap.")
