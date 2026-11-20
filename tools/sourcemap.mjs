// Builds sourcemap.json (Rojo sourcemap format) from the Script Sync layout in src/,
// so luau-lsp can resolve require() paths without a Rojo project.
// Mapping comes from the table in CLAUDE.md. Run: node tools/sourcemap.mjs
import { readdirSync, statSync, writeFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

// [disk folder, DataModel path above it, folder name in Studio]
const MOUNTS = [
	["src/server/ServerScriptService/Server", ["ServerScriptService:ServerScriptService"], "Server"],
	["src/client/Client/Client", ["StarterPlayer:StarterPlayer", "StarterPlayerScripts:StarterPlayerScripts"], "Client"],
	["src/shared/ReplicatedStorage/Shared", ["ReplicatedStorage:ReplicatedStorage"], "Shared"],
];

function classFor(file) {
	if (/\.(server|legacy)\.luau$/.test(file)) return ["Script", file.replace(/\.(server|legacy)\.luau$/, "")];
	if (/\.(local|client)\.luau$/.test(file)) return ["LocalScript", file.replace(/\.(local|client)\.luau$/, "")];
	if (/\.luau$/.test(file)) return ["ModuleScript", file.replace(/\.luau$/, "")];
	return null;
}

let count = 0;
function walk(dir, name) {
	const node = { name, className: "Folder", children: [] };
	for (const entry of readdirSync(dir).sort()) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) {
			node.children.push(walk(full, entry));
			continue;
		}
		const c = classFor(entry);
		if (c) {
			node.children.push({ name: c[1], className: c[0], filePaths: [relative(root, full).replaceAll("\\", "/")] });
			count++;
		}
	}
	return node;
}

const game = { name: "Game", className: "DataModel", children: [] };
function child(parent, name, className) {
	let n = parent.children.find((c) => c.name === name);
	if (!n) {
		n = { name, className, children: [] };
		parent.children.push(n);
	}
	return n;
}

for (const [disk, path, folderName] of MOUNTS) {
	let parent = game;
	for (const seg of path) {
		const [name, cls] = seg.split(":");
		parent = child(parent, name, cls);
	}
	const full = join(root, disk);
	let exists = false;
	try { exists = statSync(full).isDirectory(); } catch {}
	parent.children.push(exists ? walk(full, folderName) : { name: folderName, className: "Folder", children: [] });
}

writeFileSync(join(root, "sourcemap.json"), JSON.stringify(game, null, "\t"));
console.log(`sourcemap.json written: ${count} script file(s)`);
