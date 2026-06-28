-- ============================================================
-- S3CollectorClient.lua  (LocalScript — StarterPlayerScripts)
-- Mendengar broadcast dari server saat GeneratorValue berubah,
-- lalu melaporkan client_receive_time & client_fuel_value
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local generator         = workspace:WaitForChild("Generator_listrik_Genset")
local GeneratorValue    = generator:WaitForChild("GeneratorValue")
local eventsFolder      = ReplicatedStorage:WaitForChild("Events")

-- Tunggu kedua RemoteEvent dibuat oleh server
local S3ServerBroadcast = eventsFolder:WaitForChild("S3ServerBroadcast")
local S3ClientReport    = eventsFolder:WaitForChild("S3ClientReport")

-- ============================================================
-- LISTENER: terima sinyal dari server bahwa ada event baru
-- Server kirim eventId ? client baca nilai lokal + catat waktu
-- ============================================================

S3ServerBroadcast.OnClientEvent:Connect(function(eventId)
	local clientReceiveTime = tick()            -- waktu client menerima replikasi
	local clientFuelValue   = GeneratorValue.Value  -- nilai yang client lihat saat ini

	-- Kirim balik ke server
	S3ClientReport:FireServer(eventId, clientReceiveTime, clientFuelValue)
end)

print("[S3Client] Siap. Menunggu broadcast dari server...")