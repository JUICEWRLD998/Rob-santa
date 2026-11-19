--!strict
-- Server entry point. The ONLY server Script; everything else is a ModuleScript in Services/.
-- Boot order: create remotes, require every service, call Init on all of them (in name order,
-- must not yield), then Start on all of them (each in its own thread, may yield).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

-- Show a failure as a red error in Output without stopping the other services from booting.
local function report(stage: string, name: string, err: any)
	task.spawn(error, `[Server] {name}:{stage} failed: {err}`, 0)
end

-- Calls module:Init()/Start() and returns (ok, errorWithTraceback).
local function run(fn: (any) -> (), self: any): (boolean, any)
	return xpcall(function(): any
		fn(self)
		return nil
	end, debug.traceback)
end

Remotes.createAll()

local servicesFolder = script.Parent:WaitForChild("Services")
local moduleScripts: { ModuleScript } = {}
for _, child in servicesFolder:GetChildren() do
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

print(`[Server] booted {#loaded} service(s)`)
