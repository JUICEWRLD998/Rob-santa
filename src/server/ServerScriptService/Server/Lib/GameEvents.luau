--!strict
-- Server-only "something happened" signals (step 6.3), so a service can report an event without
-- requiring the services that care about it (that would make require loops). DailyService listens
-- to count quest progress (event names in Config.Quests.Pool[*].event); TutorialService (6.5) listens
-- to move a new player through the first 3 minutes.
--   GameEvents.fire("PresentGrabbed", player)      PresentService: a present picked up
--   GameEvents.fire("InspectionSurvived", player)  DisguiseService: an elf sniffed the box and left
--   GameEvents.fire("MinedOut", player)            JailService: freed by mining enough coal
--   GameEvents.fire("PresentUnwrapped", player)    UnwrapService: a present unwrapped
--   GameEvents.fire("ToySold", player, count)      ShelfService: toys sold for coins
--   GameEvents.fire("ToyShelved", player)          ShelfService: a toy put on a shelf (6.5 tutorial)
--   GameEvents.fire("ShopBought", player)          ShopService: a Gadget Shop purchase (6.5 tutorial)

export type Listener = (player: Player, amount: number) -> ()

local GameEvents = {}

local listeners: { [string]: { Listener } } = {}

function GameEvents.on(name: string, listener: Listener)
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, listener)
end

-- Each listener runs in its own thread, so a broken listener can't break the service that fired.
function GameEvents.fire(name: string, player: Player, amount: number?)
	local list = listeners[name]
	if not list then
		return
	end
	for _, listener in list do
		task.spawn(listener, player, amount or 1)
	end
end

return GameEvents
