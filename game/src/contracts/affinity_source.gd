class_name AffinitySource
extends RefCounted

## One registered way to open an element's root: an awakening treasure, an awakening
## elixir, a root-refining art — or anything a future feature ships (ADR 0924's
## seam, BL-0926). The elements module resolves the GRANT (the tier gate, the cap,
## the affinity write); the SOURCE owns only its own requirement and its own
## consumption, as two Callables, so a source can live in any module without this
## contract knowing that module.
##
## - `check(actor) -> bool`: is the requirement met right now (an item held, an art
##   learned)? Called once per candidate and never with a null actor.
## - `consume(actor) -> bool`: spend it. An item source consumes the item; a learned
##   art's one-time grant consumes nothing and answers true.
##
## `once` marks a source whose grant happens at most one time per actor — the
## learned art's opening — and the module records it as spent in the actor's own
## `module_data`, so it survives a save.
##
## Registration goes through the facade (`ElementsApi.register_affinity_source`),
## never by reaching into the elements module.

var id: StringName = &""
var element: StringName = &""
var amount: float = 0.0
var tier: int = 1
var label: String = ""
var once: bool = false
var check: Callable = Callable()
var consume: Callable = Callable()


static func make(
	p_id: StringName,
	p_element: StringName,
	p_amount: float,
	p_tier: int,
	p_label: String,
	p_once: bool,
	p_check: Callable,
	p_consume: Callable
) -> AffinitySource:
	var source := AffinitySource.new()
	source.id = p_id
	source.element = p_element
	source.amount = p_amount
	source.tier = p_tier
	source.label = p_label
	source.once = p_once
	source.check = p_check
	source.consume = p_consume
	return source
