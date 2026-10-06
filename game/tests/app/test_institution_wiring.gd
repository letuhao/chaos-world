extends TestCase

## ## The wiring, and what it makes pressable
##
## `core/institution_membership.gd` publishes the verbs and its own suite proves they work.
## Nothing proved they were REACHABLE, and the whole programme this slice belongs to exists
## because a shipped, tested, unwired feature is decoration (ADR 0074, ADR 0089, and the
## `EconomyBoot` class note's five-module list). So this suite is the wiring half:
##
##   - `InstitutionBoot.install()` has a PRODUCTION caller in the attach pipeline.
##   - `institution_screen.tscn` has a ROUTE, so the shell can open it at all.
##   - The route binder binds all THREE seams, so `join` and `leave` are pressable rather
##     than refusing `no_join_seam` by name forever.
##   - `_wire_content_roots` reaches `set_overlay_roots` for the `institutions` family, so a
##     mod's organization is visible rather than announced and skipped (DEF-0326).
##   - The screen's reader publishes `InstitutionMembership.summary`'s shape verbatim, so
##     the card renders a claim rather than an empty row.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over a route table, over an attach pipeline and
## over a fixed list of source paths, and none appends to the container it walks.

const SCREEN := "res://src/ui/screens/institution_screen.tscn"
const ROUTE := &"institution"
## The key this route binds, and the input action it therefore names.
const KEY := "i"
const ACTION := "nav_route_i"

const BODY_FILE := "res://src/app/item_workbench_body.gd"
const APP_FILE := "res://src/app/item_workbench_app.gd"
const BOOT_FILE := "res://src/app/institution_boot.gd"
const ROUTES_FILE := "res://src/app/screen_routes.gd"
const MEMBERSHIP_FILE := "res://src/core/institution_membership.gd"

## Every verb the screen can press, and where each one lives. A screen may not name
## `InstitutionMembership` for a verb, so the binder arms are the ONLY production call sites
## and this table is what says which.
const SEAM_CALL_SITES := [
	"InstitutionMembership.summary",
	"InstitutionMembership.join",
	"InstitutionMembership.leave",
]

## Everything this suite mints. Dropping the array IS the release: `Actor` and `Resource` both
## extend `RefCounted`, and `Object.free()` on one is a SCRIPT ERROR that aborts the rest of
## teardown (measured in `test_institution_foundation`).
var _born: Array = []


func setup() -> void:
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()


func teardown() -> void:
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	if InstitutionRegistry.shared != null:
		InstitutionRegistry.shared.clear()


# --- The screen is ROUTED --------------------------------------------------------


## ## The route is what makes the page reachable, asserted through the REAL table
##
## The screen shipped in `ui/screens/` with three Callables nothing bound. Unrouted it also
## cost exactly **2 red assertions** in `test_ui_conventions.gd`, because
## `SeamHarness.screen_scene_paths()` is a DIRECTORY scan — so a shipped screen with no
## route is invisible to the gate that claims to check reachability. This case is the route,
## its scene, its node name and its input action, all read off `ScreenRoutes` itself rather
## than restated, because a second copy of the table in a test is a second thing that can be
## wrong.
func test_the_institution_screen_has_a_route_a_player_can_open() -> void:
	assert_eq(ScreenRoutes.has(ROUTE), true, "the route table names the institutions page")
	assert_eq(ScreenRoutes.scene_of(ROUTE), SCREEN, "and it mounts the shipped screen")
	assert_eq(ResourceLoader.exists(SCREEN), true, "which exists")
	assert_eq(
		String(ScreenRoutes.id_for_scene(SCREEN)),
		String(ROUTE),
		"and the table agrees with itself about which route mounts it"
	)
	assert_ne(ScreenRoutes.node_of(ROUTE), "", "the mounted screen carries a node name")
	assert_eq(ScreenRoutes.key_of(ROUTE), KEY, "with the key this case asserts below")
	assert_eq(
		String(ScreenRoutes.action_of(ROUTE)),
		ACTION,
		"so a keyboard player can open it, not only the navigation bar"
	)
	# A route reachable only by a button is a route a keyboard player cannot reach.
	assert_eq(InputMap.has_action(ScreenRoutes.action_of(ROUTE)), true, "and the action is bound")
	# And no other route shares it, which is the failure two routes on one key produce.
	for other in ScreenRoutes.ids():
		if other == ROUTE:
			continue
		assert_ne(
			String(ScreenRoutes.action_of(other)),
			String(ScreenRoutes.action_of(ROUTE)),
			"no other route shares the '%s' action" % ACTION
		)


# --- The boot RUNS ---------------------------------------------------------------


## ## `install()` has a production caller, and it is the attach pipeline
##
## It shipped with **zero** production callers. `tests` are not callers: a `.tres` a modder
## dropped into the family directory was discovered by a suite and by nothing a player runs.
## So this is asserted over `game/src/app` — the composition root and the only layer allowed
## to depend on anything — and NOT over the whole tree, because `core/` calling its own
## writer would be a cycle rather than wiring.
func test_the_institution_boot_is_installed_from_the_composition_root() -> void:
	var call_sites := 0
	for path in _files_under("res://src/app"):
		var body := FileAccess.get_file_as_string(path)
		if body.is_empty():
			continue
		if body.contains("InstitutionBoot.install("):
			call_sites += 1
			assert_eq(
				path,
				BODY_FILE,
				"and the ONE caller is the attach pipeline, beside EconomyBoot.install"
			)
	assert_eq(call_sites, 1, "install() has exactly one production call site")
	# And it is an ATTACH STEP rather than a stray call, so it runs on every boot and again
	# after a save load — the `EconomyBoot.install` shape, which is idempotent for that reason.
	var steps := _attach_step_names()
	assert_eq(
		steps.has("institutions"),
		true,
		"and it is a phase of the attach pipeline, so a restored body gets it too"
	)
	# The order matters: beside `economy`, which is the last thing installed, because a
	# failure there is the newest thing a reader sees.
	assert_eq(
		steps.find("institutions") >= 0 and steps.find("institutions") <= steps.find("economy"),
		true,
		"installed at or before the economy phase, which is the last"
	)


## ## The three seams are BOUND, which is the whole of this slice
##
## `InstitutionScreen.bind_institutions(reader, joiner, leaver)` refused `no_join_seam` and
## `no_leave_seam` by name forever, because nothing called it. The binder arm is the only
## place a screen may meet a gameplay type, so the arm's existence is the assertion — and the
## Callables it builds are the three public verbs, so a caller pressing the screen presses
## `core` and nothing in between.
func test_the_route_binder_binds_all_three_actor_scoped_seams() -> void:
	var body := FileAccess.get_file_as_string(APP_FILE)
	assert_ne(body, "", "the composition root is readable")
	assert_eq(body.contains("ROUTE_INSTITUTION"), true, "the route has a binder arm")
	assert_eq(body.contains('"bind_institutions"'), true, "and it calls the screen's seam binder")
	# All three verbs, and no fourth: a screen that could read, join and leave is a screen
	# whose surface a caller can complete, and the refusal vocabulary is then honest.
	for verb in SEAM_CALL_SITES:
		assert_eq(_calls(body, verb), 1, "the binder reaches %s exactly once" % verb)
	# The reader is the summary; the joiner takes an id; the leaver takes none, which is why
	# `leave`'s zero-argument form means "every organization this actor holds".
	assert_eq(
		_calls(body, "func _leave_institution()"), 1, "and the leaver takes no organization id"
	)
	# A lambda over another script's static function killed the process with an access
	# violation on the shell's first frame (`EconomyBoot.install` documents it), so the seams
	# are `Callable(self, ...)` METHODS and not closures.
	assert_eq(body.contains("func(): InstitutionMembership"), false, "no closure crosses the seam")


# --- The mod family reaches the catalog ------------------------------------------


## ## `_wire_content_roots` dispatches on `institutions` (DEF-0326)
##
## The `:` arm records the offender in `_unwired_families` and `push_warning`s it, so a mod
## shipping `content_roots: [{family: "institutions"}]` was announced, ignored and green —
## the silent skip ADR 0184's own acceptance criterion forbids. Asserted over the FILE's
## source rather than by calling it, because `_wire_content_roots` is private and the arm is
## what matters: a family that dispatches is a family a mod's content reaches.
func test_the_institutions_family_is_wired_to_the_catalog_overlay_seam() -> void:
	var body := FileAccess.get_file_as_string(BODY_FILE)
	assert_ne(body, "", "the boot body is readable")
	assert_eq(body.contains('&"institutions":'), true, "_wire_content_roots names the family")
	assert_eq(
		body.contains("InstitutionDefCatalog.set_overlay_roots"),
		true,
		"and dispatches it to the family's own overlay seam"
	)
	# The arm must come BEFORE the `:` fallback, or it is dead code the fallback shadows.
	assert_eq(
		body.find('&"institutions":') < body.find("\n\t\t\t_:"),
		true,
		"and it sits before the fallback that would otherwise record the family as unwired"
	)


## ## And the family row a mod declares is really the one declared
##
## Read from the ONE Python declaration `tools/arch/families.json` carries, so a rename on
## either side fails here rather than leaving the runtime seam naming a family no gate
## grades — which is the failure `tools/institution_family.py` exists to catch.
func test_the_institutions_family_is_declared_with_the_data_directory_the_catalog_scans() -> void:
	var catalog := InstitutionDefCatalog.instance()
	assert_eq(
		String(InstitutionDefCatalog.INSTITUTIONS_ROOT),
		"res://data/institutions",
		"the family's root is the directory the shipped organizations actually live in"
	)
	# And the shipped content is answerable through it, which is what a mod's root stacks
	# onto: three organizations, three kinds, none of them named in any source file.
	assert_eq(catalog.is_loaded(), true, "the family loaded")
	assert_eq(catalog.has(&"lantern_exchange"), true, "the trading guild")
	assert_eq(catalog.has(&"grey_horizon_hunt"), true, "the hunting guild")
	assert_eq(catalog.has(&"torrent_field_circle"), true, "the farmers' circle")
	assert_eq(String(catalog.owner_of(&"lantern_exchange")), "base", "owned by the base root")


# --- The reader the screen is bound to --------------------------------------------


## ## The screen renders the membership the surface publishes, with no division of its own
##
## The screen's reader returns `{"institutions": {id: {exists, position, standing,
## standing_cap, normalized, obligations, roster}}}`, and `InstitutionCard` renders every
## number from it. So this drives the REAL screen with the REAL reader and asserts the three
## states arrive as three different rows — which is the contract the UI slice measured and
## this surface has to satisfy, not one this suite would prefer.
func test_the_bound_reader_publishes_a_claim_the_card_renders() -> void:
	var registry := InstitutionRegistry.new()
	InstitutionBoot.install(registry)
	var actor := _actor(&"reader")
	var screen := _screen()
	screen.setup(actor)
	# BEFORE anything: every organization is VACANT, because the reader answered and the
	# claim says `exists: false`. That is ADR 0083's middle state, and it is not the same as
	# a row carrying nothing at all.
	screen.bind_institutions(
		func(): return InstitutionMembership.summary(actor), Callable(), Callable()
	)
	assert_eq(bool(screen.claims_bound()), true, "the reader is bound")
	var before: Array = screen.summary()["organizations"]
	assert_eq(before.size() > 0, true, "the catalog offered organizations")
	for row in before:
		var view: Dictionary = row
		assert_eq(bool(view["vacant"]), true, "every organization is vacant to a non-member")

	# AFTER a founding: the claim exists, the ratio is published, and the office the founder
	# holds is NOT vacant. The screen never divided `standing / standing_cap` — it read
	# `normalized`, so a card cannot disagree with the claim it renders.
	InstitutionMembership.found(
		registry, actor, InstitutionDefCatalog.instance().definition(&"lantern_exchange"), "reader"
	)
	screen.refresh()
	var after: Dictionary = {}
	for row in screen.summary()["organizations"]:
		var view: Dictionary = row
		if String(view.get("id", "")) == "lantern_exchange":
			after = view
	assert_eq(bool(after["is_member"]), true, "the founder is a member")
	assert_eq(bool(after["vacant"]), false, "and no longer a vacancy")
	assert_eq(int(after["standing"]), 40, "on the authored founder standing")
	assert_almost_eq(
		float(after["standing_ratio"]),
		InstitutionClaim.from_dict(after["claim"]).normalized(),
		"with the ratio the claim computed, never one the screen divided"
	)
	assert_eq(String(after["position"]), "first_ledger", "seated in the authored seat")
	registry.clear()


# --- Helpers ----------------------------------------------------------------------


func _screen() -> InstitutionScreen:
	var scene := load(SCREEN) as PackedScene
	assert_ne(scene, null, "the institution screen loads")
	return scene.instantiate() as InstitutionScreen


## An actor with a funded founding pool and every base attribute, so a founding is refused
## for a CONTENT reason and never for want of money.
func _actor(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id, {})
	actor.add_resource(ResourcePool.new(InstitutionFounding.DEFAULT_FUNDING_POOL, 9000.0))
	_born.append(actor)
	var realms := RealmDefaults.ladder().realms()
	assert_ne(realms.size(), 0, "the ladder has realms")
	var power := maxf(1.0, (realms[0] as RealmDef).power)
	for attribute in Stat.BASE_ATTRIBUTES:
		actor.stats.set_base(attribute, 10.0 * power)
	return actor


## Every phase name the boot body's attach pipeline declares, read from its SOURCE rather
## than by running it — the list is data the pipeline consumes, and a phase whose name is
## spelled here but absent there is a phase that never runs.
func _attach_step_names() -> Array[StringName]:
	var out: Array[StringName] = []
	var body := FileAccess.get_file_as_string(BODY_FILE)
	for line in body.split("\n"):
		var code := line.strip_edges()
		if not code.begins_with('{"name": &"'):
			continue
		var start := code.find('&"') + 2
		var stop := code.find('"', start)
		if stop > start:
			out.append(StringName(code.substr(start, stop - start)))
	return out


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it — the
## binder arms name the verbs they call inside their own comments, so a raw `contains` would
## count the documentation as the call site.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## Every `.gd` under `root`, sorted. A `for` over `ContentScan`'s own sorted snapshot, so the
## order never depends on `DirAccess` iteration and the bound is the tree's own file count.
func _files_under(root: String) -> Array[String]:
	return ContentScan.files_under(root, ".gd")
