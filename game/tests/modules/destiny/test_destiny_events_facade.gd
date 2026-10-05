extends TestCase

## ## `DestinyApi.events()` is the legal way in, and it is the ONLY instance
##
## `tools arch` failed the whole repo on exactly this:
##
## [code]fail src/ui/screens/destiny_screen.gd:269: 'ui/' may reference 'destiny'
## only through modules/destiny/api.gd[/code]
##
## `ui/` is a pure consumer, so the codex screen reached past the facade to
## `DestinyProjection.events()`. The repo's standing rule for that is not to widen
## the boundary and not to relax the gate — it is to **add the missing verb to the
## facade**, so the screen calls `DestinyApi.events()` and the module keeps its
## internals.
##
## So this suite is the contract of the verb that closed the breach, and it asserts
## three separate things a rename or a copy would each break:
##
##   1. [method DestinyApi.events] is the same ONE bus the earns fire on — not a
##      parallel one. A second instance would leave every subscriber silent.
##   2. A consumer outside the module reaches it through the facade, and the screen
##      names no module internal.
##   3. The facade is still within its cap, so the verb was paid for honestly.
##
## The bus is a process-wide singleton, so nothing here is torn down: a subscriber
## made in one test is still connected in the next, and that is fine because the
## handler is a `Callable` over this suite's own object rather than a freed node.

const SCREEN_SOURCE := "res://src/ui/screens/destiny_screen.gd"
const FACADE_SOURCE := "res://src/modules/destiny/api.gd"

## The facade width cap is DELETED (ADR 0265), and with it the local copy that used to
## live here. The comment above it claimed the cap was "read from the rule rather than
## retyped" — it was retyped, because a GDScript suite cannot read a Python constant,
## so a cap change could never have propagated here. Coupling is fan-in now, measured
## Python-side by `tools arch`.

## A REAL authored fate — `earn_fate` refuses an id the catalog does not define, so
## a fabricated one would announce nothing and every assertion here would be green
## for the wrong reason.
const OATH_BREAKER := &"oath_breaker"

## The two earn announcements the codex subscribes to.
const EARN_SIGNALS := ["fate_earned", "destiny_earned"]

## The payload an earn announced, so an assertion reads WHAT was said rather than
## that some handler ran. Typed to the signal's own signature so a changed signal
## is a connect error instead of a silent no-op.
##
## A member rather than a local because `setup()` clears it once per test: the
## harness drives ONE instance through the whole suite, so a local would have been
## emptied by the time the first assertion read it.
var _seen: Array = []


func _hero(actor_id: StringName = &"listener") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


func setup() -> void:
	_seen.clear()
	# This suite is the SUBSCRIBER: it connects through the facade verb, which is
	# the whole surface under test. Connected here rather than inside each test,
	# so an assertion can never be green because nothing was listening.
	#
	# Guarded by `is_connected()` because the harness runs `setup()` once per test
	# against ONE instance, and the bus is process-wide: an unguarded second
	# connect is a duplicate-connection ERROR, and the screen this suite models
	# guards for exactly that reason.
	#
	# Plain `Callable` form, not a captured `Callable` var: the plain form walks
	# the connected-callables list, so it resolves against the live instance, while
	# a `Callable` bound at member-init time is empty until the object exists and
	# would connect to nothing.
	var bus := DestinyApi.events()
	if not bus.fate_earned.is_connected(_on_fate_earned):
		bus.fate_earned.connect(_on_fate_earned)
	if not bus.destiny_earned.is_connected(_on_destiny_earned):
		bus.destiny_earned.connect(_on_destiny_earned)


func _on_fate_earned(actor_id: String, fate_id: StringName, source: String) -> void:
	_seen.append([actor_id, fate_id, source])


func _on_destiny_earned(actor_id: String, destiny_id: StringName, source: String) -> void:
	_seen.append([actor_id, destiny_id, source])


# --- The verb reaches the one bus ---------------------------------------------


## The instance, not a copy. `DestinyApi.events()` and `DestinyProjection.events()`
## must be the SAME object: the module emits through the projection's bus and a
## consumer subscribes through the facade, so a second instance would leave the
## codex listening to a silence.
func test_the_facade_verb_hands_out_the_projection_bus_itself() -> void:
	assert_eq(
		DestinyApi.events(),
		DestinyProjection.events(),
		"the facade delegates rather than building a second bus"
	)
	assert_eq(DestinyApi.events(), DestinyApi.events(), "and it is stable across calls")


## The consequence of the above, asserted the only way that really counts: a
## subscriber that connected through the FACADE is called by an earn. A copy would
## pass the identity check above and fail here, which is why both exist.
func test_a_subscriber_on_the_facade_bus_is_called_by_an_earn() -> void:
	var actor := _hero()
	var before := _seen.size()

	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")

	assert_eq(_seen.size(), before + 1, "the facade subscriber heard the earn once")
	assert_eq(String(_seen[before][0]), String(actor.id), "and it was told WHICH actor earned it")
	assert_eq(
		String(_seen[before][1]), String(OATH_BREAKER), "and the fate is the REAL authored one"
	)
	assert_eq(String(_seen[before][2]), "combat", "along with the source that earned it")


## Both announcements the codex binds, on one bus, reachable through the facade.
func test_both_earn_announcements_travel_on_the_one_facade_bus() -> void:
	var bus := DestinyApi.events()
	for signal_name in EARN_SIGNALS:
		assert_eq(
			bus.has_signal(signal_name),
			true,
			"the facade bus publishes %s: the codex binds it by name" % signal_name
		)
	assert_eq(
		DestinyApi.events(),
		DestinyApi.events(),
		"one bus every time, so a listener cannot be split across two"
	)


# --- The consumer goes through the facade -------------------------------------


## The shape of the fix itself, read off the shipped source rather than inferred.
## Comments are stripped because these files DOCSTRING the internals they must not
## call — the prose that explains this very rule would otherwise satisfy a scan
## looking for the thing the rule forbids.
func test_the_codex_reaches_the_bus_through_the_facade_and_names_no_internal() -> void:
	var code := _code_only(SCREEN_SOURCE)
	assert_eq(code.is_empty(), false, "the codex has readable source")

	assert_eq(code.contains("DestinyApi.events()"), true, "the codex subscribes through the facade")
	assert_eq(
		code.contains("DestinyProjection"),
		false,
		"'ui/' may reach 'destiny' only through api.gd — no module internal in the code"
	)

	# The counterpart on the facade: it delegates, it does not re-declare the bus.
	# A facade that kept its own `_events` would be the same split this forbids.
	var facade := _code_only(FACADE_SOURCE)
	assert_eq(
		facade.contains("DestinyProjection.events()"),
		true,
		"the facade's verb delegates to the projection that owns the bus"
	)
	assert_eq(facade.contains("DestinyEvents.new()"), false, "and never constructs a second one")


# --- The verb was paid for ----------------------------------------------------


## The cap is why this verb exists, so the cap is asserted in the same place the
## reason is written down. `tools arch` fails the repo at thirteen; this fails if
## the count ever drifts off twelve.
func test_the_facade_is_still_within_its_twelve_method_cap() -> void:
	var text := FileAccess.get_file_as_string(FACADE_SOURCE)
	var public: Array[String] = []
	# Line-anchored over `static func ` lines — the same test `tools arch` applies
	# (`FUNC_RE` in `tools/arch/enforce.py`), so this is the same number the gate
	# enforces rather than a second, looser definition.
	#
	# A `RegEx` needs `MULTILINE` for `^` to mean "start of line": without it the
	# anchor is the start of the whole file, nothing matches, and the count reads
	# a confident zero.
	for line in text.split("\n"):
		if not line.begins_with("static func "):
			continue
		var name := line.substr("static func ".length())
		name = name.substr(0, name.find("(")).strip_edges()
		if not name.begins_with("_"):
			public.append(name)

	assert_ne(public.is_empty(), true, "the facade exposes something; %s" % str(public))
	# The exact verb count is NOT pinned. `assert_eq(public.size(), 12, ...)` was a
	# de facto width cap: ADR 0265 removed `MAX_FACADE_PUBLIC_METHODS` precisely so a
	# module can publish what it needs, and an exact-count assertion fails the first
	# time anyone does. What this suite is for is the verb's EXISTENCE.
	assert_eq(public.has("events"), true, "the verb this breach needed is one of them")


# --- Helpers ------------------------------------------------------------------


## The CODE of a GDScript file, with every comment line removed. Same helper shape
## as `test_destiny_hub_earned_feedback.gd`: a convention guard that reads prose
## fails a file for explaining itself.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash := line.find("#")
		if hash >= 0:
			line = line.substr(0, hash)
		out.append(line)
	return "\n".join(out)
