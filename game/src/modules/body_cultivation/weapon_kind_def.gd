class_name WeaponKindDef
extends Resource

## One KIND of weapon: a body demand, its counterweight, and the matchup it wins.
##
## ## A kind is a demand, never a damage number
##
## Everything here is about the BODY, and nothing here is about how hard the
## weapon hits. `demand` is what the weapon asks of the body, `counter_demands`
## is the body ability the same style walks on, and `counters` names the defence
## the kind answers. Two kinds with the same damage and different demands are
## different weapons; two kinds with different damage and the same demand are a
## reskin, which `test_weapon_kinds_demand_different_bodies` refuses.
##
## ## The demand is the stat id, and the stat id is the rule
##
## `demand` names a stat from `WeaponDemand`: mass, leverage, speed, balance,
## brace, precision. Nothing in the module ever compares two demands numerically
## to decide what is "strong" — the demand decides WHICH base attribute pays,
## and the attribute decides how much. So adding a seventh demand is one entry in
## `WeaponDemand` and no arithmetic anywhere else.

@export var id: StringName = &""
@export var display_name: String = ""
## One line naming the body ability this kind is good against. Content, not a
## formula: a screen prints it and a test asserts it is non-empty.
@export_multiline var best_against: String = ""
@export var demand: StringName = &"mass"
## The body ability this style leans on. NOT the demand: a two-handed maul needs
## mass AND balance, and the two are what makes the pair legible.
@export var lean: StringName = &"balance"
## What the same training costs this body. Yin-yang (AGENTS.md): no weapon ships
## an advantage without its counterpart, and the counterpart is authored here.
@export var counter_demands: Array[StringName] = []
## Defence id this kind answers — the pairing that stops any one weapon being a
## strict best response. Read through `WeaponCounter.of(id)`, so a defence and the
## weapon it answers are one declared fact.
@export var counters: StringName = &"guard"
## Work units one landed strike is worth to this kind's own practice. A rate
## constant of the practice, NOT a magnitude of the weapon.
@export var practice_gain: float = 1.0
## Base-attribute points ONE LANDED STRIKE pays into the demand's own attribute.
##
## ## Why this is authored and not defaulted, and why it is per-use
##
## The brief says a kind masters by BEING USED, and use is the only thing that moves
## a body: mastery is the record, the body work is the effect. A kind that trained
## nothing off its own `demand` would leave every swing with a counter and no body
## behind it, which is the `demand_paid` reskin this module refuses.
##
## It is scaled DOWN from `practice_gain` on purpose, and that factor is what
## separates two kinds sharing an attribute. `greatsword` and `spear` both pay
## PHYSIQUE, so an equal per-use gain would make one swing of each leave the same
## body — the "two sizes of the same weapon" `test_two_kinds_leave_a_different_body_
## behind` fails. Paired with the demand's own `practice_gain` the two arrive at
## deliberately different totals.
@export var demand_delta: float = 0.5
## Ladder index the kind may first be wielded at, keyed off the shared realm
## ladder. A gate, never a rate: it says when a body may hold the thing.
@export var min_realm_index: int = 0
