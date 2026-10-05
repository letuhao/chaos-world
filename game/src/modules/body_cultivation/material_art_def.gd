class_name MaterialArtDef
extends Resource

## One KIND of material art: matter turned into body.
##
## ## The four answers, and they are not interchangeable
##
## `transforms_into` names WHICH body part the art can rebuild, so two arts over
## different materials are different arts even when they train the same limb. A
## metal art that grows bone and a wood art that grows bone are two answers to
## the same question and both must be authored to exist — otherwise "multiple
## kinds of material" is one kind wearing five hats.
##
## ## Every art carries its own liability
##
## `price_drain` is the integrity the reshaping costs, and `draws_demand` is the
## body demand the drawn matter places on the limb it was built into. Yin-yang
## (AGENTS.md): the thing that grows a part is the thing that makes the part
## harder to keep whole. `test_material_arts_carry_their_counterpart` asserts both
## are authored on every shipped art, so a "pure upside" art cannot be added.

@export var id: StringName = &""
@export var display_name: String = ""
## The material this art is practiced on, as a tag the item content already
## speaks: metal, wood, bone, mineral, blood.
@export var material: StringName = &"metal"
## One line naming what the matter is good at doing. Content, not a formula.
@export_multiline var best_against: String = ""
## The part this art can grow where the body has none. This is the "destroy and
## recreate" payoff: the limb does not exist until the art makes it.
@export var transforms_into: StringName = &"forearm"
## Body demand the reshaping places on the new part. The liability half.
@export var draws_demand: StringName = &"brace"
## Base-attribute points this art pays into the base stat every resculpt.
@export var base_gain: float = 2.0
## Integrity drained per resculpt, from the body's own reservoir. Paid only on a
## successful reshape; a refusal costs nothing (same all-or-nothing rule as
## `BodyTraining.recover`).
@export var price_drain: float = 8.0
## Material units one resculpt consumes from the actor's material bag.
@export var material_cost: int = 2
@export var material_item: StringName = &"body_refined_titanium"
## Ladder index the art may first be practised at.
@export var min_realm_index: int = 0
