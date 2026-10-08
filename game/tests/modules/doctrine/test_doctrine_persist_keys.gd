extends TestCase

## The persistence vocabulary is DECLARED, not coincided.
##
## `DoctrineRule` publishes the names a System persists its counter under, because the
## framework's ledger normaliser rebuilds its dictionary from its own key list and copies
## nothing else. A counter stored under a System's own key name is therefore erased by
## the next write — silently, with no refusal.
##
## Before this was published, a mod had to reach one module class past the contract to
## learn which strings its own state was keyed by, and three of those strings
## (`points`, `points_max`, `owned`) matched the contract's READ keys by coincidence
## while the other six were published nowhere at all. A coincidence is not a contract:
## nothing failed when one drifted.
##
## These tests are what make it one. They fail when the two lists disagree in EITHER
## direction, and they pin the behaviour that motivates the whole thing — that an
## undeclared key is dropped — so the declaration cannot quietly become decorative.

const LEDGER := preload("res://src/modules/doctrine/doctrine_ledger.gd")


## Every `KEY_*` constant the ledger declares, as a name -> value map.
func _ledger_keys() -> Dictionary:
	var script: Script = load("res://src/modules/doctrine/doctrine_ledger.gd")
	var out := {}
	for name in script.get_script_constant_map():
		if String(name).begins_with("KEY_"):
			out[String(name)] = script.get_script_constant_map()[name]
	return out


func test_the_contract_publishes_every_key_the_ledger_normalises() -> void:
	var published: Array[StringName] = []
	for id in DoctrineRule.PERSIST_KEYS:
		published.append(StringName(id))
	for name in _ledger_keys():
		var value := StringName(_ledger_keys()[name])
		assert_eq(
			published.has(value),
			true,
			(
				"the ledger normalises '%s' but the contract does not publish it, so a System cannot name it"
				% value
			)
		)


func test_the_contract_publishes_nothing_the_ledger_does_not_normalise() -> void:
	# The opposite direction from the test above, and the one that catches a typo in the
	# published list: a name the contract advertises but the ledger never reads is a name
	# a mod will write to and watch vanish.
	var normalised: Array[StringName] = []
	for name in _ledger_keys():
		normalised.append(StringName(_ledger_keys()[name]))
	for id in DoctrineRule.PERSIST_KEYS:
		assert_eq(
			normalised.has(StringName(id)),
			true,
			(
				"the contract publishes '%s' but the ledger never normalises it, so writing it is a silent loss"
				% id
			)
		)


func test_the_named_constants_agree_with_the_persisted_list() -> void:
	# The individual constants exist so a mod can name ONE key without indexing a list,
	# which is the ergonomic reason the list is not enough on its own.
	for pair in [
		[DoctrineRule.VERSION_KEY, &"version"],
		[DoctrineRule.JOINED_KEY, &"joined"],
		[DoctrineRule.POINTS_KEY, &"points"],
		[DoctrineRule.POINTS_MAX_KEY, &"points_max"],
		[DoctrineRule.BALANCE_KEY, &"balance"],
		[DoctrineRule.BALANCES_KEY, &"balances"],
		[DoctrineRule.OWNED_KEY, &"owned"],
		[DoctrineRule.EARNINGS_KEY, &"earnings"],
		[DoctrineRule.REDEMPTIONS_KEY, &"redemptions"],
	]:
		assert_eq(
			StringName(pair[0]), pair[1], "'%s' must name the same string the ledger uses" % pair[1]
		)


func test_the_system_owned_half_is_the_counter_and_nothing_else() -> void:
	# `DoctrineRule.earn` returns a proposal and writes nothing, so the counter is the
	# System's to advance; `balance`, `joined`, `earnings` and `redemptions` are the
	# framework's to move. A System writing one of those is writing a field the next
	# framework write overwrites.
	var owned: Array[StringName] = []
	for id in DoctrineRule.SYSTEM_OWNED_PERSIST_KEYS:
		owned.append(StringName(id))
	for id in [DoctrineRule.POINTS_KEY, DoctrineRule.POINTS_MAX_KEY, DoctrineRule.OWNED_KEY]:
		assert_eq(owned.has(id), true, "'%s' is the System's own to write" % id)
	for id in [
		DoctrineRule.BALANCE_KEY,
		DoctrineRule.JOINED_KEY,
		DoctrineRule.EARNINGS_KEY,
		DoctrineRule.REDEMPTIONS_KEY,
	]:
		assert_eq(
			owned.has(id),
			false,
			(
				"'%s' is the framework's to move, so a System writing it is writing a field it does not own"
				% id
			)
		)


func test_an_undeclared_key_is_dropped_rather_than_refused() -> void:
	# The behaviour that makes the declaration necessary. Note it is a DROP, not a
	# refusal: nothing errors, the value simply does not survive. That is why the names
	# have to be published rather than left to be discovered — a mod cannot detect this
	# except by losing its counter.
	var normalized := DoctrineLedger.normalize({"a_system_chose_its_own_key": 41})
	assert_eq(
		bool(normalized.get(DoctrineRule.JOINED_KEY, false)),
		false,
		"an undeclared key must not survive normalisation, or the declaration is decorative"
	)
	assert_eq(
		bool(normalized.has("a_system_chose_its_own_key")),
		false,
		"a key the contract does not publish is dropped silently - this is the hazard the published list exists to prevent"
	)
