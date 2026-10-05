class_name ProphecyDef
extends Resource

## One authored prophecy: an item that hints at a fate.
##
## Prophecies are earned through encounters, never purchased. Each prophecy
## hints at exactly one fate — the uniqueness gate (no two prophecies hint at
## the same fate) is enforced by ProphecyCatalog.validate() and a test.
##
## A prophecy's hint is deliberately vague: it guides the player toward a fate
## without spoiling its effects. The yin-yang balance: a prophecy is valuable
## (it points toward a fate) but limited (it doesn't grant the fate, only hints).

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## The fate this prophecy hints at. Exactly one fate per prophecy (uniqueness gate).
@export var hint_fate_id: StringName = &""
## The hint text shown to the player. Vague enough to not spoil, specific enough to guide.
@export var hint_text: String = ""


func is_visible() -> bool:
	return id != &"" and hint_fate_id != &""
