class_name ScreenRoutes
extends RefCounted

## The route table: the one place that names every surface a player can reach.
##
## The shell builds its navigation bar from this table, mounts the root route at
## boot, and refuses to load any scene it does not name here. So "the screens the UI
## program ships" and "the screens a player can reach" cannot drift apart: a screen
## that is not listed is unreachable, and a listed route whose scene stops loading
## is a reported error rather than a silent hole.
##
## Order is the tab order and the digit order. Each route names its own `key`, and
## that key is bound to the input action `ACTION_PREFIX + key` in `project.godot`, so
## every route has a keyboard action as well as a button press.
##
## `root` marks the single route the shell mounts at boot and never pops: it is the
## home every other route is stacked over, so `ui_cancel` always lands somewhere.

const ACTION_PREFIX := "nav_route_"
const ROOT_ID := &"workbench"
## A route's `key` names its input action: `nav_route_<key>`, declared in
## `project.godot`. The key is per route, not per position, so a route past the tenth
## takes any unused printable character and a matching action — there is no second
## list of keys here to fall out of step with the table. `nav_probe` presses a key by
## unicode, so a letter works exactly as a digit does.

const ROUTES: Array[Dictionary] = [
	{
		"id": &"workbench",
		"node": "Workbench",
		"label": "Workbench",
		"hint": "Inventory, equipment, roll, save and load.",
		"scene": "res://src/ui/screens/item_workbench.tscn",
		"key": "1",
		"root": true,
	},
	{
		"id": &"loot_encounter",
		"node": "LootEncounterScreen",
		"label": "Hunt",
		"hint": "Enter a domain, strike the boss, take what it drops.",
		"scene": "res://src/ui/screens/loot_encounter.tscn",
		"key": "2",
		"root": false,
	},
	{
		"id": &"world_map",
		"node": "WorldMapScreen",
		"label": "World",
		"hint": "Locations by tier, faction and danger.",
		"scene": "res://src/ui/screens/world_map_screen.tscn",
		"key": "3",
		"root": false,
	},
	{
		"id": &"body_cultivation",
		"node": "BodyCultivationPanel",
		"label": "Body",
		"hint": "Body cultivation: temper, recover, break through.",
		"scene": "res://src/ui/screens/body_cultivation_panel.tscn",
		"key": "4",
		"root": false,
	},
	{
		"id": &"qi_cultivation",
		"node": "QiCultivationScreen",
		"label": "Qi",
		"hint": "Qi cultivation: dantian, meridians, break through.",
		"scene": "res://src/ui/screens/qi_cultivation_screen.tscn",
		"key": "5",
		"root": false,
	},
	{
		"id": &"mind_cultivation",
		"node": "MindCultivationScreen",
		"label": "Mind",
		"hint": "Mind cultivation: sea of consciousness and anchors.",
		"scene": "res://src/ui/screens/mind_cultivation_screen.tscn",
		"key": "6",
		"root": false,
	},
	{
		"id": &"crafting",
		"node": "CraftingScreen",
		"label": "Craft",
		"hint": "Every recipe whose inputs the hero already holds.",
		"scene": "res://src/ui/screens/crafting_screen.tscn",
		"key": "7",
		"root": false,
	},
	{
		"id": &"socket_forge",
		"node": "SocketForgeScreen",
		"label": "Sockets",
		"hint": "Open, impute, seat and enchant sockets on a host item.",
		"scene": "res://src/ui/screens/socket_forge.tscn",
		"key": "8",
		"root": false,
	},
	{
		"id": &"set_bonus",
		"node": "SetBonusScreen",
		"label": "Sets",
		"hint": "Every authored set, its thresholds and its uniques.",
		"scene": "res://src/ui/screens/set_bonus_screen.tscn",
		"key": "9",
		"root": false,
	},
	{
		"id": &"character",
		"node": "CharacterScreen",
		"label": "Hero",
		"hint": "Every derived stat, resource pool and enrolled path.",
		"scene": "res://src/ui/screens/character_screen.tscn",
		"key": "0",
		"root": false,
	},
	{
		"id": &"character_creation",
		"node": "CharacterCreation",
		"label": "Arrival",
		"hint": "The origin you arrive under, and the body it arrives in.",
		"scene": "res://src/ui/screens/character_creation.tscn",
		"key": "k",
		"root": false,
	},
	{
		"id": &"destiny",
		"node": "DestinyScreen",
		"label": "Fate",
		"hint": "Every fate earned, and the destinies still closed to you.",
		"scene": "res://src/ui/screens/destiny_screen.tscn",
		"key": "-",
		"root": false,
	},
	{
		"id": &"sect",
		"node": "SectScreen",
		"label": "Sect",
		"hint": "The institution you are sworn to, and what the office obliges.",
		"scene": "res://src/ui/screens/sect_screen.tscn",
		"key": "q",
		"root": false,
	},
	{
		"id": &"nation",
		"node": "NationScreen",
		"label": "Nation",
		"hint": "The board of offices, the claims, and every declared conflict.",
		"scene": "res://src/ui/screens/nation_screen.tscn",
		"key": "e",
		"root": false,
	},
	{
		"id": &"technique_codex",
		"node": "TechniqueCodexScreen",
		"label": "Arts",
		"hint": "Every technique you have learned, and what each one costs.",
		"scene": "res://src/ui/screens/technique_codex.tscn",
		"key": "c",
		"root": false,
	},
	{
		"id": &"technique_loadout",
		"node": "TechniqueLoadoutScreen",
		"label": "Arts Set",
		"hint": "Which techniques are equipped and ready to cast.",
		"scene": "res://src/ui/screens/technique_loadout.tscn",
		"key": "l",
		"root": false,
	},
	{
		"id": &"tribulation",
		"node": "TribulationScreen",
		"label": "Tribulation",
		"hint": "The tribulation a breakthrough must answer, and whether you can.",
		"scene": "res://src/ui/screens/tribulation_screen.tscn",
		"key": "t",
		"root": false,
	},
	{
		# The domain surface (BL-0220 / BL-0394). The `domain` module shipped ten
		# green suites with nothing in the shipped program ever reaching it, so the
		# Hunt route could write a loot dict and never produce a map. This is the route
		# that reaches it instead: the screen generates an authored template, enters
		# the run, and draws its floor plan from `DomainMinimap` — the same read model
		# the headless driver renders, so the two cannot disagree.
		"id": &"domain_explore",
		"node": "DomainExploreScreen",
		"label": "Explore",
		"hint": "Enter a domain and walk its rooms, traps, puzzles and hoards.",
		"scene": "res://src/ui/screens/domain_explore.tscn",
		"key": "d",
		"root": false,
	},
	{
		# The quest journal (BL-0663 / BL-0664). `QuestApi` shipped twelve verbs and
		# 476 green assertions with nothing in `src/` ever calling `accept`, so the
		# active set `QuestBeatHandler` reads was always empty and
		# `QuestGrants.pay -> DestinyApi.earn_fate(actor, id, "quest:<id>")` was dead
		# code. This is the route that makes a quest something a player can SEE and
		# ACCEPT; the commit itself goes through `QuestProgram`, the one caller.
		"id": &"quest",
		"node": "QuestScreen",
		"label": "Quests",
		"hint": "What the world is offering, and what you are carrying.",
		"scene": "res://src/ui/screens/quest_screen.tscn",
		"key": "j",
		"root": false,
	},
]


## Every route, in tab order. Duplicated so a caller cannot edit the table.
static func all() -> Array[Dictionary]:
	return ROUTES.duplicate(true)


## Every route id, in tab order.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for route in ROUTES:
		out.append(StringName(route.get("id", "")))
	return out


static func has(route_id: StringName) -> bool:
	return index_of(route_id) >= 0


## The route with this id, or `{}` when the table does not name it.
static func entry(route_id: StringName) -> Dictionary:
	var index := index_of(route_id)
	return {} if index < 0 else ROUTES[index]


## Where a route sits in the table, or -1.
static func index_of(route_id: StringName) -> int:
	for index in ROUTES.size():
		if StringName(ROUTES[index].get("id", "")) == route_id:
			return index
	return -1


## The route that ships this scene, or `""`. The shell loads screens through this,
## so a path the table does not name cannot be reached even by a direct call.
static func id_for_scene(scene_path: String) -> StringName:
	for route in ROUTES:
		if String(route.get("scene", "")) == scene_path:
			return StringName(route.get("id", ""))
	return &""


## The scene a route names. Loading is the shell's job; this only answers the path.
static func scene_of(route_id: StringName) -> String:
	return String(entry(route_id).get("scene", ""))


## The node name a mounted route carries. The shell renames each screen to it, so the
## live screen says which route it is in the node tree and not only in the shell.
static func node_of(route_id: StringName) -> String:
	return String(entry(route_id).get("node", ""))


## The digit a route opens on, or "" when the id is not in the table.
static func key_of(route_id: StringName) -> String:
	return String(entry(route_id).get("key", ""))


## The input action a route opens on, e.g. `nav_route_3`. Declared in
## `project.godot`; the navigation bar and the shell both read it from here, so a key
## is never bound in one place and advertised in another.
static func action_of(route_id: StringName) -> StringName:
	return StringName(ACTION_PREFIX + key_of(route_id))


## The route this input action opens, or `""`.
static func route_for_action(action: StringName) -> StringName:
	for route in ROUTES:
		if action_of(StringName(route.get("id", ""))) == action:
			return StringName(route.get("id", ""))
	return &""


## The table as primitives, for a probe or a test to assert against.
static func summary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for route in ROUTES:
		(
			out
			. append(
				{
					"id": String(route.get("id", "")),
					"node": String(route.get("node", "")),
					"label": String(route.get("label", "")),
					"hint": String(route.get("hint", "")),
					"scene": String(route.get("scene", "")),
					"key": String(route.get("key", "")),
					"action": String(action_of(StringName(route.get("id", "")))),
					"root": bool(route.get("root", false)),
				}
			)
		)
	return out
