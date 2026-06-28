-- ============================================================
-- S2CollectorClient.lua  (LocalScript — StarterPlayerScripts)
-- Mendengar broadcast dari S2Collector server,
-- lalu melaporkan posisi item yang client lihat
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder      = ReplicatedStorage:WaitForChild("Events")
local S2ServerBroadcast = eventsFolder:WaitForChild("S2ServerBroadcast")
local S2ClientReport    = eventsFolder:WaitForChild("S2ClientReport")

-- ============================================================
-- LISTENER: server bilang ada drag event baru
-- Server kirim: eventId, item (BasePart)
-- Client baca posisi item dari sisinya sendiri, lalu lapor
-- ============================================================

S2ServerBroadcast.OnClientEvent:Connect(function(eventId, item)
	local clientReceiveTime = tick()

	-- Baca posisi item dari sisi client
	-- (bisa berbeda dari server karena replication lag)
	local pos = Vector3.new(0, 0, 0)
	if item and item:IsA("BasePart") then
		pos = item.Position
	end

	S2ClientReport:FireServer(
		eventId,
		clientReceiveTime,
		math.floor(pos.X * 100) / 100,
		math.floor(pos.Y * 100) / 100,
		math.floor(pos.Z * 100) / 100
	)
end)

print("[S2Client] Siap. Menunggu broadcast drag event dari server...")