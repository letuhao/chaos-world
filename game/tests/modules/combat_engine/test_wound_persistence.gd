extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0140: THE WOUND LEDGER SURVIVES A SAVE — schema v5 carries `body_wounds`.
##
## ## What was broken
##
## `BodyWounds` held per-meridian severity and a NECROSIS flag set, and neither half
## reached the payload: `Actor.to_dict` wrote no key for it, so every save/load pair
## quietly reset a body to un-hit. That is not a cosmetic loss. ADR 0070 makes necrosis
## IRREVERSIBLE by design — `decay` floors a necrotic channel at `necrosis_threshold`
## and no repair route un-necroses it — so a save was the one mechanism that undid it
## for free. The ledger already had `to_dict` / `load_from` and was simply never wired.
##
## ## The shape of the fix
##
## Core cannot import `combat_engine`, so the slot travels as RAW DATA, exactly as
## `mind_attempt` does (ADR 0037). `to_dict` reads the bound ledger off the component by
## `has_method`/`call`; `from_dict` stashes the raw payload in `module_data`; and
## `CombatEngineApi.attach_wounds` rebuilds the typed object from that stash. Core owns
## the key and the version gate, the module owns the meaning.
##
## ## Why a v4 save is "no wounds" and not "no ledger"
##
## An ABSENT slot stays absent rather than becoming an empty ledger, because "this body
## was never hit" and "this body was hit and every wound decayed" are different facts.
## See `test_a_v4_payload_loads_with_no_wounds_and_never_crashes`.

# --- the round trip ---------------------------------------------------------------


## The headline: severity PER MERIDIAN and the necrosis flags survive `to_dict` ->
## `from_dict` -> `attach_wounds`, on two different meridians, so a per-channel fact is
## proven to survive and not just a single aggregate number.
##
## Asserted on two channels with DIFFERENT severities on purpose. A serializer that wrote
## one channel's number under every key, or that summed them, would pass a single-channel
## test and fail this one — which is the only reason this test is worth its line count.
func test_wound_severity_and_necrosis_survive_the_actor_round_trip() -> void:
	var target := _defender(
		["lung", "spleen"], {"lung": MeridianState.OPEN, "spleen": MeridianState.OPEN}
	)
	# `lung` is driven past NECROSIS and `spleen` stops below the wound threshold, so the
	# payload carries one flagged channel, one wounded channel and one clean channel.
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	ledger.add(target, &"lung", _severity_for(target, _tuning.necrosis_threshold * 2.0), _tuning)
	ledger.add(target, &"spleen", _severity_for(target, _tuning.wound_threshold * 0.5), _tuning)
	assert_eq(ledger.is_necrotic(&"lung"), true, "the setup really did necrose lung")

	var payload := target.to_dict()
	assert_eq(
		int(payload["version"]),
		Actor.SCHEMA_VERSION,
		"the payload declares the CURRENT schema version"
	)
	assert_eq(payload.has("body_wounds"), true, "and it carries the wounds slot")

	var restored_actor := Actor.from_dict(payload)
	var restored := CombatEngineApi.attach_wounds(restored_actor, _tuning)
	assert_almost_eq(
		restored.severity_of(&"lung"),
		ledger.severity_of(&"lung"),
		"lung's severity survived the round trip"
	)
	assert_almost_eq(
		restored.severity_of(&"spleen"),
		ledger.severity_of(&"spleen"),
		"splen's severity survived it too, and independently"
	)
	assert_eq(restored.is_necrotic(&"lung"), true, "the NECROSIS flag survived")
	assert_eq(restored.is_necrotic(&"spleen"), false, "and an un-necrotic channel stayed so")
	assert_eq(restored.severity_of(&"heart"), 0.0, "an untouched meridian stays clean")

	# The load is not merely a faithful copy of the NUMBERS: the irreversible fact is
	# still irreversible afterwards. Decay is the one route that moves severity down, so
	# if the flag had been dropped on restore this would fall to 0.0.
	restored.decay(1.0e6, _tuning)
	assert_almost_eq(
		restored.severity_of(&"lung"),
		_tuning.necrosis_threshold,
		"a restored necrotic channel still floors at the necrosis threshold"
	)
	assert_eq(restored.is_necrotic(&"lung"), true, "so a save can no longer un-necrose")


## The ledger is written EXACTLY ONCE. It is excluded from the generic `module_data` loop
## and carried under its own key — the `mind_attempt` precedent — so a save that went the
## other way (both places at once) would restore a stale copy over a fresh one.
func test_the_wound_slot_is_written_once_and_never_duplicated_into_module_data() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	ledger.add(target, &"lung", _severity_for(target, _tuning.wound_threshold), _tuning)

	var payload := target.to_dict()
	var stashed: Dictionary = payload["module_data"]
	assert_eq(
		stashed.has(String(Actor.WOUNDS_MODULE_KEY)),
		false,
		"the versioned slot is NOT also written into generic module_data"
	)
	assert_eq(payload["body_wounds"].has("severity"), true, "and it IS written to its own key")

	# A stale stash must not resurrect: `attach_wounds` consumes the raw payload, so a
	# re-attach cannot restore an old copy over a ledger that has since been written to.
	var restored_actor := Actor.from_dict(payload)
	var restored := CombatEngineApi.attach_wounds(restored_actor, _tuning)
	restored.add(
		restored_actor, &"lung", _severity_for(restored_actor, _tuning.wound_threshold), _tuning
	)
	assert_almost_eq(
		restored.severity_of(&"lung"), ledger.severity_of(&"lung") * 2.0, "accumulated on top of it"
	)


## `attach_wounds` is IDEMPOTENT, and a re-attach must not erase wounds earned this
## session — the same contract `MechanismSlot.bind` has for the mechanism slot. A body
## that is re-attached on every path change would otherwise heal on every re-attach.
func test_attaching_twice_keeps_the_ledger_rather_than_replacing_it() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var first := CombatEngineApi.attach_wounds(target, _tuning)
	first.add(target, &"lung", _severity_for(target, _tuning.necrosis_threshold * 2.0), _tuning)
	var second := CombatEngineApi.attach_wounds(target, _tuning)
	assert_eq(second == first, true, "the SAME ledger came back")
	assert_eq(second.is_necrotic(&"lung"), true, "so the necrosis is still on it")


# --- migration --------------------------------------------------------------------


## A v4 payload has NO wounds slot, because the slot did not exist. It must load as "no
## wounds" and it must not crash: `Actor._restore_versioned` follows the file's existing
## pattern for a missing key — `data.get(SLOT, {})`, then a non-empty check before any
## write, so an absent slot writes nothing and stashes nothing.
##
## Built as a real round trip and then DOWNGRADED rather than hand-written, because a
## hand-built v4 payload is a payload nobody ever wrote: it is the v5 payload minus one
## key, and that is exactly what a save from before the bump is.
func test_a_v4_payload_loads_with_no_wounds_and_never_crashes() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	# Wound the body first, so the downgrade is a genuine loss rather than a no-op: this
	# asserts the loader IGNORES what is gone, not that there was nothing to lose.
	var ledger := CombatEngineApi.attach_wounds(target, _tuning)
	ledger.add(target, &"lung", _severity_for(target, _tuning.necrosis_threshold * 2.0), _tuning)

	var legacy: Dictionary = target.to_dict()
	legacy["version"] = 4
	legacy.erase("body_wounds")

	var actor := Actor.from_dict(legacy)
	assert_ne(actor, null, "a v4 payload loads")
	assert_eq(actor.id, target.id, "the actor is the same one")
	assert_eq(
		actor.get_module_data(Actor.WOUNDS_MODULE_KEY).is_empty(),
		true,
		"no wounds were INVENTED for the old save"
	)
	var restored := CombatEngineApi.attach_wounds(actor, _tuning)
	assert_almost_eq(restored.severity_of(&"lung"), 0.0, "and it loads as an unhit body")
	assert_eq(restored.is_necrotic(&"lung"), false, "with nothing necrotic")

	# The migrated actor must be able to carry wounds FORWARD: a save that loaded clean
	# is only correct if the next save from it works.
	restored.add(actor, &"lung", _severity_for(actor, _tuning.necrosis_threshold * 2.0), _tuning)
	var again := Actor.from_dict(actor.to_dict())
	var second := CombatEngineApi.attach_wounds(again, _tuning)
	assert_eq(second.is_necrotic(&"lung"), true, "and the migration is not a dead end")


## The v3-and-older shape, asserted because the gate is on the SLOT rather than the
## number: a payload with no `version` at all reads as the CURRENT schema, and one that
## declares 3 carries no slot either. Neither may crash.
func test_older_payloads_without_the_slot_all_load_clean() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	for legacy_version in [1, 2, 3, 4]:
		var legacy: Dictionary = target.to_dict()
		legacy["version"] = legacy_version
		legacy.erase("body_wounds")
		var actor := Actor.from_dict(legacy)
		var restored := CombatEngineApi.attach_wounds(actor, _tuning)
		assert_almost_eq(
			restored.severity_of(&"lung"), 0.0, "v%d loads as an unhit body" % legacy_version
		)


# --- untrusted input ---------------------------------------------------------------


## A save is UNTRUSTED input, and `Actor.get_module_data` already documents the contract
## that anything under a module's key that is not a dictionary reads as absent. The
## wounds slot must honour it, because the alternative is a load that throws on a
## hand-edited file instead of degrading to "this body is fine".
func test_a_corrupt_wounds_payload_degrades_instead_of_throwing() -> void:
	# Each shape is one way a hand-edited or foreign save can park something unusable
	# under the key. The bar for all of them is the SAME: the load finishes, and what it
	# produces is a ledger whose numbers are finite and non-negative.
	var corrupt_shapes: Array = [
		"not a dictionary",
		42,
		[1, 2, 3],
		{"severity": "not a dictionary"},
		{"severity": {"lung": "not a number"}},
		{"severity": {"lung": -5.0}},
		{"necrotic": "not a dictionary"},
		{"necrotic": {"lung": "not a bool"}},
		{"severity": {"lung": INF}, "necrotic": {"lung": true}},
		{},
	]
	for shape in corrupt_shapes:
		var target := _defender(["lung"], {"lung": MeridianState.OPEN})
		var payload := target.to_dict()
		payload["body_wounds"] = shape
		var actor := Actor.from_dict(payload)
		var restored := CombatEngineApi.attach_wounds(actor, _tuning)
		assert_eq(
			is_finite(restored.severity_of(&"lung")),
			true,
			"%s degraded to a finite severity" % str(shape)
		)
		assert_eq(restored.severity_of(&"lung") >= 0.0, true, "and never a negative wound")
		# A NECROSIS flag is honoured only when it is a REAL bool; anything else reads as
		# absent, the same answer a missing key gets. `get` throughout, because
		# `Dictionary[key]` on a missing key is an error in GDScript — and a test
		# asserting on corrupt input must not be the thing that crashes on it.
		var flags: Variant = (
			(shape as Dictionary).get("necrotic", null) if shape is Dictionary else null
		)
		var written: Variant = flags.get("lung", null) if flags is Dictionary else null
		assert_eq(
			restored.is_necrotic(&"lung"),
			written is bool and written,
			"and the flag is exactly the bool that was written"
		)


## The degradation above is only honest if the loader is the thing that decides. A
## NON-numeric severity must not reach the ledger as a silently coerced 0.0 alongside a
## NECROSIS flag that still says true — the two halves of the payload are separate facts
## and each is validated on its own.
func test_a_numeric_field_that_is_not_numeric_is_dropped_and_the_flags_survive() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var payload := target.to_dict()
	payload["body_wounds"] = {"severity": {"lung": "gash"}, "necrotic": {"lung": true}}
	var actor := Actor.from_dict(payload)
	var restored := CombatEngineApi.attach_wounds(actor, _tuning)
	assert_almost_eq(restored.severity_of(&"lung"), 0.0, "an unusable severity is not a wound")
	assert_eq(restored.is_necrotic(&"lung"), true, "but a usable flag is still honoured")
	# And such a ledger is still a working ledger, not a brick.
	restored.add(actor, &"lung", _severity_for(actor, _tuning.necrosis_threshold * 2.0), _tuning)
	assert_eq(restored.is_necrotic(&"lung"), true, "and it accepts new wounds")


## An actor with NO ledger bound at all serializes an EMPTY slot rather than failing:
## `Actor._wounds_dict` calls `to_dict` through `has_method`, so a core-only actor, a
## training dummy or a qi-only fighter is a supported state, not a crash.
func test_an_actor_with_no_ledger_serializes_an_empty_slot() -> void:
	var plain := Actor.new(&"qi_only")
	var payload := plain.to_dict()
	assert_eq(payload["body_wounds"], {}, "no ledger is an empty slot")
	assert_eq(Actor.from_dict(payload) != null, true, "and it still loads")
	assert_eq(CombatEngineApi.wounds_of(null), null, "and a null actor has no ledger")
