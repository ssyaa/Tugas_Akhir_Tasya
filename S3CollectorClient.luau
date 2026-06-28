local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local generator         = workspace:WaitForChild("Generator_listrik_Genset")
local GeneratorValue    = generator:WaitForChild("GeneratorValue")
local eventsFolder      = ReplicatedStorage:WaitForChild("Events")

-- Tunggu kedua RemoteEvent dibuat oleh server
local S3ServerBroadcast = eventsFolder:WaitForChild("S3ServerBroadcast")
local S3ClientReport    = eventsFolder:WaitForChild("S3ClientReport")

S3ServerBroadcast.OnClientEvent:Connect(function(eventId)
	local clientReceiveTime = tick()            -- waktu client menerima replikasi
	local clientFuelValue   = GeneratorValue.Value  -- nilai yang client lihat saat ini

	-- Kirim balik ke server
	S3ClientReport:FireServer(eventId, clientReceiveTime, clientFuelValue)
end)

print("[S3Client] Siap. Menunggu broadcast dari server...")
