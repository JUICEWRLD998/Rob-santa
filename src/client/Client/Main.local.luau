--!strict
-- Client entry point. The ONLY LocalScript; everything else is a ModuleScript in Controllers/.
-- Same boot order as the server: require all, Init all (no yielding), then Start all.
-- The client never decides anything that matters; it shows things and sends intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local function report(stage: string, name: string, err: any)
	task.spawn(error, `[Client] {name}:{stage} failed: {err}`, 0)
end

-- Calls module:Init()/Start() and returns (ok, errorWithTraceback).
local function run(fn: (any) -> (), self: any): (boolean, any)
	return xpcall(function(): any
		fn(self)
		return nil
	end, debug.traceback)
end

local controllersFolder =script.Parent:WaitForChild("Controllers")
local moduleScripts: { ModuleScript } = {}
for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(moduleScripts, child)
	end
end
table.sort(moduleScripts, function(a, b)
	return a.Name < b.Name
end)

type Loaded = { name: string, module: Types.Module }
local loaded: { Loaded } = {}
for _, moduleScript in moduleScripts do
	local ok, result = pcall((require :: any), moduleScript)
	if ok then
		table.insert(loaded, { name = moduleScript.Name, module = result })
	else
		report("require", moduleScript.Name, result)
	end
end

for _, entry in loaded do
	local init = entry.module.Init
	if init then
		local ok, err = run(init, entry.module)
		if not ok then
			report("Init", entry.name, err)
		end
	end
end

for _, entry in loaded do
	local start = entry.module.Start
	if start then
		task.spawn(function()
			local ok, err = run(start, entry.module)
			if not ok then
				report("Start", entry.name, err)
			end
		end)
	end
end

print(`[Client] booted {#loaded} controller(s)`)
