--!strict
-- Sound effects and music (step 5.6, docs/04 section 6). Plays on this client only: nothing here
-- decides anything. It listens to what the server already tells this player:
--   CarryCount up        grab: paper rustle + a ding
--   ChasedBy 0 -> 1+     spotted: alarm sting, and the chase music fades in (out when it ends)
--   DisguiseUpdate       wrap: fwip + twinkle; inspected: heartbeat + sniffs; fooled: soft chime
--   Jailed               caught: whistle + a stamp thud
--   Unwrapping           drumroll; UnwrapReveal: a fanfare that gets bigger with rarity
--   Coins jump           coin clinks (not the passive income tick)
-- Music: the festive Town tune, the sneaky Explore tune inside a zone (ZoneArea boxes) and in the
-- jail, and the Chase tune while any elf chases you. The Sleigh Raid sound waits for Phase 6.
-- The Sound instances live in SoundService/Sfx and SoundService/Music (place file).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SOUND_WAIT_SECONDS = 15

type Track = { sound: Sound, volume: number, target: number }

local SoundController = {}

local player = Players.LocalPlayer
local sfx: Folder? = nil
local tracks: { [string]: Track } = {}
local currentTrack: string? = nil
local heartbeat: Sound? = nil
local sniffing = 0 -- bumps each inspection, so an old sniff loop stops
local drumroll: Sound? = nil
local lastCoins = 0
local lastCoinSound = 0
local chasedUntil = 0

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- Fades a one-shot copy out, then removes it. Stepped by Heartbeat, not TweenService: tweens
-- stall while Studio is in the background, which left sounds playing in tests (2026-11-22).
local function fadeOut(sound: Sound, seconds: number)
	task.spawn(function()
		local start = sound.Volume
		local elapsed = 0
		while elapsed < seconds and sound.Parent do
			elapsed += RunService.Heartbeat:Wait()
			sound.Volume = start * math.max(0, 1 - elapsed / seconds)
		end
		sound:Destroy()
	end)
end

-- Plays a copy of SoundService/Sfx/<name>. Copies, so the same sound can overlap itself.
local function play(name: string, volume: number?, speed: number?): Sound?
	local folder = sfx
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA("Sound") then
		return nil
	end
	local sound = template:Clone()
	sound.Volume = volume or template.Volume
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	return sound
end

----------------------------------------------------------------------------------------------------
-- Music

local function insideZone(position: Vector3): boolean
	for _, box in CollectionService:GetTagged("ZoneArea") do
		if box:IsA("BasePart") then
			local offset = box.CFrame:PointToObjectSpace(position)
			local half = box.Size / 2
			if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local function wantedTrack(): string
	if os.clock() < chasedUntil or numberAttribute("ChasedBy") > 0 then
		return "Chase"
	end
	if player:GetAttribute("Jailed") == true then
		return "Explore"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and insideZone(root.Position) then
		return "Explore"
	end
	return "Town"
end

local function updateMusic()
	local wanted = wantedTrack()
	if wanted == currentTrack then
		return
	end
	currentTrack = wanted
	for name, track in tracks do
		track.target = if name == wanted then track.volume else 0
		if track.target > 0 and not track.sound.IsPlaying then
			track.sound:Resume()
		end
	end
end

-- Each frame, every track's volume moves toward its target; a full fade takes MusicFadeSeconds.
-- A track that reaches 0 pauses, and picks up where it left off next time.
local function stepMusic(dt: number)
	for _, track in tracks do
		local sound = track.sound
		local volume = sound.Volume
		if volume ~= track.target then
			local stepSize = track.volume * dt / Config.Audio.MusicFadeSeconds
			if volume < track.target then
				sound.Volume = math.min(track.target, volume + stepSize)
			else
				sound.Volume = math.max(track.target, volume - stepSize)
			end
			if sound.Volume == 0 and track.target == 0 then
				sound:Pause()
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Moments

local function stopHeartbeat()
	sniffing += 1
	local sound = heartbeat
	heartbeat = nil
	if sound then
		fadeOut(sound, 0.4)
	end
end

local function onDisguise(value: any)
	if type(value) ~= "table" then
		return
	end
	local state = value.state
	if state == "Wrapped" then
		play("Fwip")
		task.delay(0.12, play, "Chime", 0.3, 2) -- the ribbon twinkle: the chime, high and quiet
	elseif state == "Inspected" then
		stopHeartbeat()
		heartbeat = play("Heartbeat")
		local token = sniffing
		task.spawn(function()
			while sniffing == token do
				play("Sniff")
				task.wait(Config.Audio.SniffEverySeconds)
			end
		end)
	elseif state == "Fooled" then
		stopHeartbeat()
		play("Chime", 0.45, 1)
	else -- Gotcha (the jail sound follows) or Ended
		stopHeartbeat()
	end
end

local function onReveal(payload: any)
	if type(payload) ~= "table" or type(payload.rarity) ~= "string" then
		return
	end
	local roll = drumroll
	drumroll = nil
	if roll then
		fadeOut(roll, 0.15)
	end
	local settings = Config.Audio
	local tier = table.find(Config.RarityOrder, payload.rarity) or 1
	local fanfare = play(settings.FanfareByTier[tier] or "Chime", settings.FanfareVolumeByTier[tier])
	if fanfare and fanfare.TimeLength > settings.FanfareSeconds then
		task.delay(settings.FanfareSeconds, function()
			if fanfare.Parent then
				fadeOut(fanfare, 0.8)
			end
		end)
	end
	if payload.mutation ~= nil then
		task.delay(Config.Reveal.StampDelay, play, "Stamp", 0.6) -- the mutation stamp slam
	end
end

local function onCoins()
	local coins = numberAttribute("Coins")
	local gain = coins - lastCoins
	lastCoins = coins
	local quiet = numberAttribute("IncomePerSecond") * Config.Audio.CoinsMinIncomeSeconds
	if gain > 0 and gain > quiet and os.clock() - lastCoinSound >= Config.Audio.CoinsCooldownSeconds then
		lastCoinSound = os.clock()
		play("Coins")
	end
end

----------------------------------------------------------------------------------------------------

function SoundController:Init() end

function SoundController:Start()
	local foundSfx = SoundService:WaitForChild("Sfx", SOUND_WAIT_SECONDS)
	local foundMusic = SoundService:WaitForChild("Music", SOUND_WAIT_SECONDS)
	if not foundSfx or not foundSfx:IsA("Folder") or not foundMusic then
		warn("[SoundController] SoundService/Sfx or SoundService/Music is missing (place file); no sound")
		return
	end
	sfx = foundSfx
	for _, sound in foundMusic:GetChildren() do
		if sound:IsA("Sound") then
			tracks[sound.Name] = { sound = sound, volume = sound.Volume, target = 0 }
			sound.Volume = 0
			sound.Looped = true
		end
	end

	-- Grab.
	local lastCarry = numberAttribute("CarryCount")
	player:GetAttributeChangedSignal("CarryCount"):Connect(function()
		local carry = numberAttribute("CarryCount")
		if carry > lastCarry then
			play("Rustle")
			task.delay(0.15, play, "Chime", 0.35, 1.5)
		end
		lastCarry = carry
	end)

	-- Spotted and chased.
	local lastChased = numberAttribute("ChasedBy")
	player:GetAttributeChangedSignal("ChasedBy"):Connect(function()
		local chased = numberAttribute("ChasedBy")
		if chased > 0 and lastChased == 0 then
			play("AlarmSting")
		elseif chased == 0 then
			chasedUntil = os.clock() + Config.Audio.ChaseLingerSeconds
		end
		lastChased = chased
		updateMusic()
	end)

	-- Caught.
	player:GetAttributeChangedSignal("Jailed"):Connect(function()
		if player:GetAttribute("Jailed") == true then
			stopHeartbeat()
			play("Whistle")
			task.delay(0.45, play, "Stamp")
		end
		updateMusic()
	end)

	-- Unwrap.
	player:GetAttributeChangedSignal("Unwrapping"):Connect(function()
		if player:GetAttribute("Unwrapping") == true and not drumroll then
			drumroll = play("Drumroll")
		end
	end)
	Remotes.get("UnwrapReveal").OnClientEvent:Connect(onReveal)

	Remotes.get("DisguiseUpdate").OnClientEvent:Connect(onDisguise)

	lastCoins = numberAttribute("Coins")
	player:GetAttributeChangedSignal("Coins"):Connect(onCoins)

	RunService.Heartbeat:Connect(stepMusic)
	task.spawn(function()
		while true do
			updateMusic()
			task.wait(Config.Audio.MusicCheckSeconds)
		end
	end)
end

return SoundController
