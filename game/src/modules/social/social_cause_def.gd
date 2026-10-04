class_name SocialCauseDef
extends Resource

## One named reason a relationship moves (ADR 0076). Authored, not coded: a cause is
## the only writer of a bond, so "why do these two dislike each other" is answerable
## from data instead of inferred from a delta.
##
## **A cause writes axes; it never writes the class on its own.** The class is a pure
## function of the axes (see `SocialBondClass.classify`), so gift-spamming a merchant
## cannot buy a friend. A cause MAY additionally name the top of the ladder it is
## entitled to (`promotes_to`), but that is a ceiling the axes still have to reach — which
## is what stops an act from granting the very rank it promises.

## The authored cause id. The one writer of a bond's axes.
@export var id: StringName = &""

## Whether the standing this cause earns survives decay. A debt honoured is permanent;
## a gift is not.
@export var persistent: bool = false

## Tags an author can gate content on, e.g. `&"combat"`, `&"gift"`, `&"oath"`.
##
## `kind` is the one the anti-farm rule reads: two causes of the SAME kind — two gifts, two
## fights — are one kind of act repeated, and a friendship has to survive at least two
## DIFFERENT kinds. See `SocialBondClass.FRIEND_DISTINCT_KINDS`.
@export var kind: StringName = &""
@export var tags: Array[StringName] = []

## Axis deltas. A cause that moved both standing and respect is authored deliberately —
## it is how a nemesis you admire stays possible.
@export var standing: float = 0.0
@export var trust: float = 0.0
@export var respect: float = 0.0

## Whether this cause is one an INSTITUTION moved rather than a person: an oath to
## a sect, a seat held in a nation, ground defended. **It is a flag rather than a
## tag lookup because it has to survive a save.** `SocialState.regard` is built
## from the bonds that carry this flag, and the projection must give the same
## answer after a reload as it did before — so the fact is stored on the bond
## rather than re-derived from a catalog that a test may have replaced, an author
## may have edited, or a save may have outlived.
##
## It is deliberately NOT the same thing as having `&"institution"` in `tags`:
## `held_office` is institutional while a seat in a nation's board is tagged
## `&"office"`, and conflating the two would make the kind of the act decide
## whether the actor is regarded by an institution at all.
@export var institutional: bool = false

## The class this cause can promote to, or `&""`. Promotion additionally requires the
## class's own thresholds, so naming a class sets the ceiling, never the outcome:
## `SocialBond.apply` records it on the bond and `SocialBondClass.classify` returns it only
## when the axes have already earned `SocialBondClass.PROMOTION_MIN_CLASS`.
@export var promotes_to: StringName = &""
