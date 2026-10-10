class_name DomainFixtureGates
extends RefCounted

## Which fixture verb this screen OFFERS, and what it says when it refuses (ADR 0211).
##
## ## Why this is extracted, and why it is not a Node
##
## `domain_explore.gd` was over its thousand-line `max-file-lines` ceiling, and the gates
## were the block that could leave without moving a single door: they are PURE decisions
## over three inputs (is a run live, is the seam wired, what kind is the selected
## fixture) and they touch no widget. A `RefCounted` is therefore the whole contract —
## `ui/panels/` is where a shared piece of this program lives, and this one shares with
## nothing but the screen because it is the screen's own policy made nameable.
##
## ## Why a trap is INSPECTED and never ARMED
##
## [constant FIXTURE_VERB] maps the MODULE's three kinds onto the BRIDGE's three actions.
## A trap's verb is `inspect_fixture` — FREE, non-mutating, and carrying no `delta`, so
## the verb structurally cannot express "fire it". Presence inside the authored footprint
## is the only trigger (ADR 0211), which is why nothing here can reach `arm` or
## `presence`: they are not in this table, and a kind with no entry is refused.
##
## ## Two vocabularies, so two tables
##
## The values are the SEAM's action ids (`inspect_fixture` / `attempt_fixture` /
## `claim_fixture`), not the shorter button ids the `ActionSet` row publishes, because the
## only reader is [method can_act] and it is handed a bridge action. Holding the button
## ids instead made all three comparisons unequal, so every fixture verb was gated off
## permanently: a trap could never be read, the armed/spent ledger was unreachable, and a
## refusal reported a reason the player never caused (`authors_no_status_id`,
## `unknown_node`, `missing_key` — each a gate that does not exist).
##
## ## Why a treasure whose key you lack stays PRESSABLE
##
## [method can_act] asks whether the room holds a fixture OF THE KIND this verb acts on
## and whether the seam can answer — never whether the module will ACCEPT. Whether it will
## accept is its business: refusing here would make the refusal itself unreachable, and the
## refusal is the thing that teaches a player why the hoard is sealed.
##
## Contract: `reason_for()` answers the module's OWN reason id, never one invented here
## (`DomainBridge.REASON_TEXT` words it; the id is what a driver and a test match on).

## The MODULE's three kinds paired with the BRIDGE action that acts on each. Read from
## [DomainFixtures] through the seam, never named as a domain type (`domain` is not in
## `rules.UI_MODULES`).
const FIXTURE_VERB := {
	"trap": &"inspect_fixture",
	"puzzle": &"attempt_fixture",
	"treasure": &"claim_fixture",
	# BL-0951 / ADR 0939, S9 + S15: a one-time mending SITE, acted on by `DomainSecretRealm`
	# through the bridge's `reforge_site` (the fourth kind `DomainFixtures.KINDS` closes over).
	"secret_realm": &"reforge_site",
}

## The three fixture verbs, in the order a player meets them on the row.
const ACTIONS: Array[StringName] = [&"inspect_fixture", &"attempt_fixture", &"claim_fixture"]

## The button id each verb is published under. The `ActionSet` row speaks this vocabulary,
## which is why it is a SEPARATE table from [constant FIXTURE_VERB] rather than a rename.
const ACTION_LABEL := {
	&"inspect_fixture": &"inspect",
	&"attempt_fixture": &"attempt",
	&"claim_fixture": &"claim",
}

## The authored reason each verb falls back to when the SCREEN refuses rather than the
## module — the gate a player is most likely to be standing at, named in the module's own
## vocabulary (`DomainFixtures`' reason ids).
const AUTHORED_FALLBACK := {
	&"inspect_fixture": "unknown_fixture",
	&"attempt_fixture": "unknown_node",
	&"claim_fixture": "missing_key",
	&"reforge_site": "unknown_site",
}

## What the screen must know about itself for a gate to answer. Passed in rather than
## reached for, so this object never holds the screen and never makes a widget a
## precondition of a decision.
var _live: bool = false
var _wired: Callable = Callable()
var _fixture_kind: String = ""
var _fixture_id: StringName = &""
var _puzzle_nodes: Array[StringName] = []


## Re-point every gate at the state it is being asked about. One door, so the five
## verdicts below cannot be taken against two different moments.
##
## `wired` is a `Callable(StringName) -> bool` answering whether the seam reaches an
## action — a `Callable` rather than the bridge itself so `ui/` keeps its facade-only
## boundary and this object never names a domain type.
func evaluate(
	p_live: bool,
	p_wired: Callable,
	p_fixture_kind: String,
	p_fixture_id: StringName,
	p_puzzle_nodes: Array[StringName]
) -> void:
	_live = p_live
	_wired = p_wired
	_fixture_kind = p_fixture_kind
	_fixture_id = p_fixture_id
	_puzzle_nodes = p_puzzle_nodes


## Whether `action` may be offered at all: a live run, a seam that reaches the verb, a
## selected fixture, and that fixture being OF THE KIND this verb acts on.
func can_act(action: StringName) -> bool:
	if not _live or not _wired.is_valid() or not bool(_wired.call(action)):
		return false
	if _fixture_id.is_empty():
		return false
	return FIXTURE_VERB.get(_fixture_kind, &"") == action


## `can_act`, plus the one gate that is about the CONTENT rather than the seam: a formation
## with no authored nodes has nothing to strike, so `attempt` is not offered rather than
## offered-and-refused.
func can_attempt() -> bool:
	return can_act(&"attempt_fixture") and not _puzzle_nodes.is_empty()


## Why `action` was refused BY THE SCREEN rather than by the module.
##
## `no_map` and `no_inventory_bridge` are the two facts this screen can establish alone;
## everything else is the authored content's own gate, so it is handed back as the
## module's id and worded by [member DomainBridge.REASON_TEXT].
func reason_for(action: StringName) -> String:
	if not _live:
		return "no_map"
	if not _wired.is_valid() or not bool(_wired.call(action)):
		return "no_inventory_bridge"
	return String(AUTHORED_FALLBACK.get(action, "unknown_fixture"))
