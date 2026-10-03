class_name SocialCauseDef
extends Resource

## One named reason a relationship moves (ADR 0076). Authored, not coded: a cause is
## the only writer of a bond, so "why do these two dislike each other" is answerable
## from data instead of inferred from a delta.
##
## **A cause writes axes; it never writes the class.** The class is a pure function of
## the axes (see `SocialBondClass.classify`), so no authored number can hand an actor a
## sworn bond, and gift-spamming a merchant cannot buy a friend.

## The authored cause id. The one writer of a bond's axes.
@export var id: StringName = &""

## Whether the standing this cause earns survives decay. A debt honoured is permanent;
## a gift is not.
@export var persistent: bool = false

## Tags an author can gate content on, e.g. `&"combat"`, `&"gift"`, `&"oath"`.
@export var tags: Array[StringName] = []

## Axis deltas. A cause that moved both standing and respect is authored deliberately —
## it is how a nemesis you admire stays possible.
@export var standing: float = 0.0
@export var trust: float = 0.0
@export var respect: float = 0.0

## The class this cause can promote to, or `&""`. Promotion additionally requires the
## class's own thresholds, so naming a class sets the ceiling, never the outcome.
@export var promotes_to: StringName = &""
