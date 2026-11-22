--!strict
-- Flavour NPCs that just stand there (step 5.3: the Black Market dealer). Any Model tagged IdleNpc
-- with a Humanoid gets Roblox's default R15 idle on a loop, so it breathes instead of T-posing.
-- The model's HumanoidRootPart is anchored in the place file, so it never walks or falls over.

local CollectionService = game:GetService("CollectionService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TAG = "IdleNpc"

local NpcService = {}

local function startIdle(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local humanoid = instance:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[NpcService] {instance:GetFullName()} is tagged {TAG} but has no Humanoid`)
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = Config.Animations.NpcIdle.id
	local track = (animator :: Animator):LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true
	track:Play()
end

function NpcService:Init() end

function NpcService:Start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(startIdle)
	for _, instance in CollectionService:GetTagged(TAG) do
		startIdle(instance)
	end
end

return NpcService
