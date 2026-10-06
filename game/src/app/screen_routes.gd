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
		# The lineage page (ADR 0030 / 0062 / 0063 / 0064). `RaceApi`, `BloodlineApi`
		# and `ClanApi` each published a primitives-only `summary(actor)` and each
		# shipped a green suite, while NO route mounted a screen that read any of
		# them: a hero's body, the lineages it carries and the house it owes were
		# three reach models no player could open. `BloodlineProjection` keeps the
		# `bloodline:<id>` trait mirror on while a lineage is dormant, so a sleeping
		# ancestry was a LIVE trait on the actor with no visible cause anywhere.
		# This is the route that reads all three, and the dormant row is the reason
		# the page is worth opening at all.
		"id": &"lineage",
		"node": "LineageScreen",
		"label": "Lineage",
		"hint": "The body you were born into, the blood you carry, and your house.",
		"scene": "res://src/ui/screens/lineage_screen.tscn",
		"key": "g",
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
		# The clan page (ADR 0239 / DEF-0229 / DEF-0286). `ClanHeir.register` is the SOLE
		# writer of `household_heir_registered` and had zero production callers: `ui/`
		# shipped `sect_screen` and `nation_screen` and no clan screen at all, so a house
		# had no way to speak and four authored quests could never complete. This is the
		# route that gives `app/clan_registry.gd`'s unwired seam a caller.
		"id": &"clan",
		"node": "ClanScreen",
		"label": "Clan",
		"hint": "Your house, your standing in it, and the register it keeps.",
		"scene": "res://src/ui/screens/clan_screen.tscn",
		"key": "h",
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
	{
		# The combat readout (ADR 0174). `CombatOutcome.to_dict()` is the engine's own
		# primitives-only read model and no screen consumed it, so every stage of the
		# spine and every mechanism was computed and invisible. This is the surface
		# that renders one resolved blow to the last stage. The strike and its target
		# arrive as Callables from the composition root — the ADR 0143 seam — because
		# `ui/` may neither mint an `Actor` nor name a `TechniqueDef`.
		"id": &"combat_readout",
		"node": "CombatReadoutScreen",
		"label": "Blow",
		"hint": "Strike once and read every stage the damage spine ran.",
		"scene": "res://src/ui/screens/combat_readout.tscn",
		"key": "r",
		"root": false,
	},
	{
		# The fight (ADR 0197). The engine was complete, reachable and GREEN, and a
		# player still could not fight: the only surface combat happened on was
		# `combat_readout.tscn`, which fires one blow at a stationary drill body and
		# resolves no contest. This is the route that opens one — two sides, alternating
		# blows, a verdict, a record. Every verb arrives as a Callable because `ui/` may
		# neither name `FightLoop` (an `app/` type, a `PRIVATE_UNIT`) nor mint an
		# opponent; the root owns the loop and hands its verbs over.
		"id": &"fight",
		"node": "FightScreen",
		"label": "Fight",
		"hint": "Take a fight, exchange blows, and win or lose it.",
		"scene": "res://src/ui/screens/fight_screen.tscn",
		"key": "f",
		"root": false,
	},
	{
		# The gather surface (ADR 0097). `HoldingsApi.claim` had no production caller
		# repo-wide, so a node was never held and `ForageAction.workable` could never
		# answer true: the sixteen authored nodes, the yield table covering every one
		# of them, and the harvest verb behind them were reachable by nothing a player
		# can press. `tools data audit` nonetheless reported `gather` live, because
		# `app/forage_action.gd` is a call site a scan can see and a player cannot.
		# This is the route that opens it — claim, work, give up.
		"id": &"forage",
		"node": "ForageScreen",
		"label": "Gather",
		"hint": "Take a resource node, work it, and gather what it yields.",
		"scene": "res://src/ui/screens/forage_screen.tscn",
		"key": "y",
		"root": false,
	},
	{
		# The shop surface (ADR 0100 / DEF-0218). `ShopCounter` shipped the whole
		# priced read model — `summary(shop_id)`, `at_location(location_id, player)`,
		# a shelf priced by the one reader settlement uses, and a `can_buy` per
		# shop — and called itself "the door a caller actually walks through" while
		# nothing walked through it. `MarketApi.buy`/`sell` both take a `shop_actor:
		# Actor` and only `ShopCounter`, an `app/` type, can mint one, so the verbs
		# had no argument a screen could produce. This is the route that opens it.
		"id": &"market",
		"node": "MarketScreen",
		"label": "Market",
		"hint": "The stalls here, their priced shelves, and buying and selling.",
		"scene": "res://src/ui/screens/market_screen.tscn",
		"key": "m",
		"root": false,
	},
	{
		# The auction surface (ADR 0102). `MarketApi.list` / `bid` / `settle_lot`
		# shipped with the whole escrow discipline, and `AuctionReadModel`
		# published a primitives-only row for every lot in the world — and no
		# screen read any of it, so who was winning, what a bid had to be and what
		# a lot was frozen at were all computed and invisible.
		"id": &"auction",
		"node": "AuctionScreen",
		"label": "Auction",
		"hint": "Every lot, the high bidder, and what the next bid has to be.",
		"scene": "res://src/ui/screens/auction_screen.tscn",
		"key": "b",
		"root": false,
	},
	{
		# The floor (DEF-0309). `MarketApi.drop`, `take` and `settle` shipped a
		# bounded, decaying, per-location container of realized instances, and
		# `MarketApi.summary` publishes the whole ledger as `floor` — while
		# `market_screen.gd` said out loud that the floor was "deliberately NOT on
		# this surface". So a dropped item was a ledger row only a test could reach:
		# one player put goods down and nothing in the shipped program could pick
		# them up again. Every argument of all three verbs is the bound actor plus
		# plain ids, so `market` being a `UI_MODULES` grant is enough on its own and
		# this route's binding arm is the PLAIN default `setup(actor)`.
		"id": &"floor",
		"node": "FloorScreen",
		"label": "Floor",
		"hint": "What lies on the floor here, and what you may take or leave.",
		"scene": "res://src/ui/screens/floor_screen.tscn",
		"key": "n",
		"root": false,
	},
	{
		# The custody page (ADR 0104). `CustodyApi.capture`, `transfer`, `release`,
		# `settle_term` and `subject` shipped, passed 63 assertions, and had NO
		# production caller: the brief asked that captured actors and mobs be
		# reachable, ADR 0094 refused a captive as a tradeable thing, and ADR 0104
		# answered "a custody CLAIM" -- and then nothing a player can press opened,
		# moved or ended one. So a captive was a ledger row and no surface, which is
		# the UNWIRED shape the gather audit found on the other side of the program.
		# `custody` is in `rules.UI_MODULES` with no module reach, so the screen
		# calls `CustodyApi` by bare name and the composition root's binding arm is
		# the PLAIN default `setup(actor)`: every verb takes primitives plus an
		# actor the screen already holds, so custody is the one surface with no
		# injected seam, and this route is the proof that a granted facade reach is
		# enough on its own.
		"id": &"custody",
		"node": "CustodyScreen",
		"label": "Custody",
		"hint": "The claims you hold, and the terms they carry.",
		"scene": "res://src/ui/screens/custody_screen.tscn",
		"key": "v",
		"root": false,
	},
	{
		# Every organization of ANY kind (ADR 0271 / 0278). The institution family
		# shipped a registry, a catalog, a generic founding verb, a ledger and a
		# projection, and `core/` published NO actor-scoped surface at all — so
		# `institution_screen.tscn` sat in the UI program with three Callables nothing
		# bound and a `found` verb whose written ledger it published and dropped.
		# `InstitutionMembership` is that surface, and the composition root's route
		# binder binds it. Unrouted, the screen cost exactly 2 red assertions in
		# `test_ui_conventions.gd` because `SeamHarness.screen_scene_paths()` is a
		# directory scan; this row clears both and is what makes the verbs pressable.
		"id": &"institution",
		"node": "InstitutionScreen",
		"label": "Guilds",
		"hint": "Every kind of organization, the offices it publishes, and your place in one.",
		"scene": "res://src/ui/screens/institution_screen.tscn",
		"key": "i",
		"root": false,
	},
	{
		# The soul and hearth page (ADR 0127 / 0129 / 0146 / 0128). `soul`,
		# `difficulty`, `anchor` and `save` shipped their verbs, their content and
		# their suites, and nothing in the shipped program ever rendered any of
		# them: the soul was a number in an injected store, the difficulty a row
		# in a table, the hearth a set of headless verbs and the save's status a
		# `summary()` with no reader. This is the surface that reaches all four.
		# It is ONE page and not four because they are one player's condition, and
		# because the save half has no verb at all — ADR 0128 leaves it a status
		# line, so a route of its own could never justify itself.
		"id": &"soul_hearth",
		"node": "SoulHearthScreen",
		"label": "Soul",
		"hint": "The soul's condition, the difficulty, the anchors and the save.",
		"scene": "res://src/ui/screens/soul_hearth_screen.tscn",
		"key": "s",
		"root": false,
	},
	{
		# The main menu (boot slice). The shell used to decide silently: a
		# restored body went to the workbench, a fresh boot went to arrival,
		# and a player who wanted the other door had no door. This is the
		# door: Continue returns to the saved journey, New Game opens
		# arrival. Last in tab order, so every feature route keeps its key.
		"id": &"boot",
		"node": "BootScreen",
		"label": "Begin",
		"hint": "Continue the saved journey, or begin anew.",
		"scene": "res://src/ui/screens/boot_screen.tscn",
		"key": "o",
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
