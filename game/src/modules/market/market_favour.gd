class_name MarketFavour
extends RefCounted

## The ONE buyer-dependent price modifier (ADR 0250). A price stops being the same number
## for everybody: a counter may treat a buyer it likes better than one it does not, **inside
## a clamp that cannot print money**.
##
## ## The authority is the reader, never a second formula
##
## `EconomyValuation.unit_price` (ADR 0094) is untouched and stays the only price path. This
## file does not price anything: it turns ONE injected number into ONE bounded multiplier,
## and [method MarketTransfer.quote] folds that multiplier into the coin quantity **once**,
## at the single place the market already turns a base price into coins.
##
## ## The boundary is a Callable, because `market` may not name `social`
##
## `registry.json` gives `market` `["contracts", "core", "economy", "items"]` and no
## `social`, so this module reads reputation through an injected
## `Callable(buyer: Actor) -> float` — the `CustodyApi.set_resolver` seam verbatim — and the
## composition root binds `SocialApi.reputation` **itself**, as a bare static-function
## reference and not through an adapter, because that is already this signature. A direct
## `SocialApi` reference would be an undeclared dependency the boundary checker fails on, and
## a second copy of the axis would be ADR 0066's duplication in a new place.
##
## ## The clamp, and why these two numbers
##
## The modifier is `1 + reputation * FAVOUR_RATE`, then hard-clamped to
## `[FAVOUR_FLOOR, FAVOUR_CAP]`.
##
## - `FAVOUR_RATE = 0.15` — a maximally-regarded buyer (`reputation` is authored in
##   `[-1, 1]` by `SocialStats.REPUTATION`) pays 15% less, and a maximally-disliked one
##   pays 15% more. Bounded by construction, because the input is a bounded axis.
## - `FAVOUR_CAP = 1.25` / `FAVOUR_FLOOR = 0.85` — the **clamp on the OUTPUT**, which is the
##   half that cannot be argued with. A reader is a `Callable`: a bug, a hostile test double
##   or a future axis authored at 100 could otherwise reach 10x on one row and re-price the
##   whole economy. The cap is *tighter* than `MarketSpread`'s own 1.5 sell rate on purpose:
##   fame is a discount, never a reason to beat the price the shop itself charges a stranger,
##   so a well-regarded buyer never sees a better rate than the shop's own margin allows and
##   a well-reputed player cannot become the cheapest buyer in the world.
##
## ## One axis, two signs — and that IS the counterpart
##
## AGENTS.md's yin-yang rule asks for a counter-force, and here the counter-force is the
## direction itself rather than a second mechanic. Buying, the axis is a **discount** on the
## charge; selling, the same axis is a **premium** on the payout. A well-regarded customer
## pays under the shelf price to buy and is paid over it to sell; a disliked one does
## exactly the reverse. One number, two signs, and applying the same sign to both would
## have been a strict best response — the defect the rule names.
##
## ## The default is exactly neutral
##
## No reader bound, a dead reader, a null counter, or a reader answering a non-finite value
## all answer `1.0` — **byte-identical to today's price**. That is what makes the ~290
## existing market assertions the regression guard for this file rather than something they
## have to be taught about.

## The biggest multiplier any reader may reach, whatever it answers.
const FAVOUR_CAP := 1.25
## The smallest. Symmetrical with the cap, so fame is a discount and infamy a surcharge of
## the same size rather than an unbounded penalty.
const FAVOUR_FLOOR := 0.85
## How much of a fully-regarded buyer's standing reaches the price. The ONLY rate here; the
## clamp above is what makes a mis-scaled reader harmless rather than merely unlikely.
const FAVOUR_RATE := 0.15

## The injected reader: `Callable(buyer: Actor) -> float`. A `static var`, because the seam
## is process-wide exactly as `MarketApi.set_store`'s is — and `static var` is excluded from
## the app-state heuristics by construction, the shape `ShopCounter._counters` uses.
static var _reader: Callable = Callable()


## Install the reader that answers how well-regarded `buyer` is, in `[-1, 1]`.
## Anything that is not a live `Callable` is stored as none, so a dead binding degrades to
## the neutral default rather than raising at the first price.
static func set_reputation_reader(reader: Callable) -> void:
	_reader = reader if reader.is_valid() else Callable()


## Whether a reader is installed, so a caller can tell "no reputation" from "neutral
## reputation" — different sentences, and only one of them is a fact about a person.
static func has_reputation_reader() -> bool:
	return _reader.is_valid()


## The modifier for `counter`'s regard of the buyer, clamped into
## `[FAVOUR_FLOOR, FAVOUR_CAP]`. `buyer_pays` is the WHOLE of the direction question.
##
## ## The SIGN is the direction, and getting it wrong is a money printer
##
##   buyer_pays  = true  -> a liked buyer is CHARGED less      (the shop is selling)
##   buyer_pays  = false -> a liked buyer is PAID more         (the shop is buying)
##
## **One sign applied to both directions would be worse than no modifier at all**: a
## well-regarded buyer would both pay MORE at the counter and be paid MORE for the same
## good, which is a strict best response with no counterpart — the exact yin-yang defect
## AGENTS.md names. A test caught it: with a single sign, a reader answering `1.0`
## charged *more* than neutral.
##
## ## Every path out of here is `1.0` except one
##
## No reader, a null counter, or an answer that is not a finite NUMBER all read as "nobody
## in particular". The type gate is `TYPE_INT`/`TYPE_FLOAT` rather than a cast, because the
## reader is a `Callable` and may answer anything at all: `float(null)` and `float(true)`
## are runtime errors rather than a value, and a `String` would silently read as a price of
## zero. `is_finite` then guards the two numbers that ARE the right type and still mean
## nothing — `inf` and `NAN` — for `actor_save.gd`'s reason: they truncate to an int that
## looks like a real price, so an unguarded `NAN` would reach `MarketSpread`'s `roundi` and
## produce a coin figure nobody authored.
static func factor(counter: Actor, buyer_pays: bool) -> float:
	if not _reader.is_valid() or counter == null:
		return 1.0
	var answered: Variant = _reader.call(counter)
	if typeof(answered) != TYPE_INT and typeof(answered) != TYPE_FLOAT:
		return 1.0
	var raw := float(answered)
	if not is_finite(raw):
		return 1.0
	# `buyer_pays == false` is the case that PAYS OUT, so it takes the positive sign; the
	# inversion is the counterpart, not a second number.
	var swing := -raw * FAVOUR_RATE if buyer_pays else raw * FAVOUR_RATE
	return clampf(1.0 + swing, FAVOUR_FLOOR, FAVOUR_CAP)


## `coins` for a total at `factor`, rounded once and floored at 1.
##
## **This is the whole mechanism.** The modifier is applied to the COIN COUNT and nowhere
## else, and there is no "base price" and "final price" pair anywhere in the market: the base
## is `EconomyValuation`'s, the coins are `MarketSpread`'s, and this is the one bounded factor
## between them. `maxi(1, …)` is `MarketSpread`'s own floor carried through, so a buyer a
## merchant loves still pays at least one coin — a discount that reached zero would be a
## counter giving goods away, which is the free-money half of ADR 0100's rule.
static func coins(spread_coins: int, factor: float) -> int:
	if factor == 1.0:
		return maxi(0, spread_coins)
	return maxi(1, roundi(float(maxi(0, spread_coins)) * factor))


## The clamp and the rate as primitives, so `MarketApi.summary` and a test read the
## invariant from one place instead of restating three numbers.
static func view() -> Dictionary:
	return {
		"reader_installed": has_reputation_reader(),
		"favour_rate": FAVOUR_RATE,
		"favour_cap": FAVOUR_CAP,
		"favour_floor": FAVOUR_FLOOR,
	}
