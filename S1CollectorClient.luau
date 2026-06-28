local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder      = ReplicatedStorage:WaitForChild("Events")
local S1ServerBroadcast = eventsFolder:WaitForChild("S1ServerBroadcast")
local S1ClientReport    = eventsFolder:WaitForChild("S1ClientReport")

local REPLICATION_WAIT  = 0.5  -- detik tunggu replikasi

S1ServerBroadcast.OnClientEvent:Connect(function(batchId, eventIdToIndex)
	local clientReceiveTime = tick()

	-- Tunggu replikasi
	task.wait(REPLICATION_WAIT)

	local itemsFolder = workspace:FindFirstChild("Items")

	-- Untuk setiap eventId di batch, cari log yang punya attribute itu
	for eventId, _ in pairs(eventIdToIndex) do
		local clientStatus = "not_replicated"

		if itemsFolder then
			for _, obj in ipairs(itemsFolder:GetChildren()) do
				if obj:GetAttribute("S1EventId") == eventId then
					-- Log ditemukan dari sisi client
					if obj.Transparency < 1 then
						clientStatus = "visible"
					else
						clientStatus = "invisible"
					end
					break
				end
			end
		end

		-- Lapor ke server per eventId
		S1ClientReport:FireServer(eventId, clientReceiveTime, clientStatus)
	end
end)

print("[S1Client] Siap. Replication wait: " .. REPLICATION_WAIT .. "s")
