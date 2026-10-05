class_name SocialAlignmentTrack
extends RefCounted

## The player-aligned verdict for ONE pair, and the ONLY place alignment is allowed to
## touch a bond (ADR 0253).
##
## ## Why this class exists at all
##
## The owner ruled that one player's alignment is read identically by every NPC. The
## obvious way to honour that — pass the actor's axes into the bond — is exactly the
## DOS2 group-alignment leak: a global number read by every agent makes flipping it
## flip every relationship in the world, and an NPC in another part of the map finds
## itself in combat "for no intuitive reason".
##
## **So the score is identical for all NPCs, and the VERDICT is not.** This type is the
## split, made structural: it takes the actor's band plus one cause and one bond, and
## returns how much *this* pair moves *this time*. Two different NPCs given the same
## band and the same cause always get the same number — that is the identical reading,
## and it is testable. What it can never do is reach a third party, because it has no
## handle on one: `apply_swayed` writes exactly the bond passed in and returns.
##
## That is the whole DOS2 answer, and it is worth stating plainly: **the leak was never
## caused by the score being global, it was caused by the score being APPLIED globally.**
## DOS2 flips an alignment *entity* and every member of that entity reacts to every
## player. Here one number is read by everyone, but it is only ever *spent* on the pair
## that just did something — so being a hated person in one valley costs you nothing in
## the next, and the change is always explainable by an act the player just performed.

## The rate band comes from the player-aligned actor; nothing else is consulted.


## How much a cause's SIGNED standing is multiplied by, for one pair. Uses the CAUSE'S
## own sign, never the pair's current standing: a bond that is already a grudge does not
## get its hatred doubled *and* its goodwill halved into a third behaviour, which would
## be a rule with more cases than the genre has. The two matrix halves are `goodwill`
## (a cause that raises standing) and `hatred` (a cause that lowers it).
##
## **`trust` is never swayed** (`NEUTRAL_SWAY` in every band). A corrupt player can
## still keep a promise, and if trust followed the band then a single cruelty would
## demote every confidant bond in the world — the DOS2 shape, wearing a different hat.
static func sway_for(band: StringName, cause_standing: float) -> float:
	if cause_standing >= 0.0:
		return SocialAlignmentMatrix.goodwill_rate(band)
	return SocialAlignmentMatrix.hatred_rate(band)


## Apply one authored cause to one bond with the alignment sway folded in.
##
## `scale` is the CALLER's attenuation and multiplies the matrix contribution before
## the band is applied, so a partial win reads as a partial both in alignment and in
## standing — one attenuation, one meaning.
##
## Returns the signed standing the bond ACTUALLY moved by, so a caller can log or assert
## the effect without re-deriving it (and so a test can prove corruption changed it).
static func apply_swayed(
	bond: SocialBond, cause: SocialCauseDef, band: StringName, scale: float = 1.0
) -> float:
	if bond == null or cause == null:
		return 0.0
	var before := bond.standing
	bond.apply(cause, sway_for(band, cause.standing) * maxf(0.0, scale))
	return bond.standing - before


## The alignment verdict alone, for a gate or a panel that wants to ask "how does this
## act land on this pair" without writing anything. `{goodwill_rate, hatred_rate,
## band, corrupt}` — primitives only.
static func verdict(band: StringName) -> Dictionary:
	return {
		"band": String(band),
		"corrupt": band == SocialAlignmentMatrix.CORRUPT,
		"goodwill_rate": SocialAlignmentMatrix.goodwill_rate(band),
		"hatred_rate": SocialAlignmentMatrix.hatred_rate(band),
	}
