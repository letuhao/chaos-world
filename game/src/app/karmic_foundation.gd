class_name KarmicFoundation
extends RefCounted

## Grants a re-embodied soul a small STARTING FOUNDATION from the deaths it has already
## died (BL-0951 / ADR 0939, S14).
##
## ## The half that was missing
##
## The karmic-memory FATES already ship and are already granted: each death's arrival
## authors `soul_marked_once` / `soul_marked_twice` / `soul_marked_thrice` as its `marks`,
## and `SoulArrivalMarks.grant` earns them on the new body (ADR 0190). So the fates exist,
## are held, and were read by NOTHING that changed the next body. This is the read: the
## held marks raise the new body's starting foundation through `FoundationApi.seed_karmic`.
##
## ## Why this is in `app/`, not in `foundation` or `soul`
##
## The floor's SOURCE is `destiny`'s fates and its SINK is `foundation`'s record.
## `foundation` may not read `destiny` — that would be a cycle, because `destiny` already
## depends on `foundation` (S12) — and `soul` may not read `destiny` at all (ADR 0181 guard
## 5). `app/` is the one layer that may depend on anything, exactly as `SoulArrivalMarks` is
## and for the same reason. This is a plain `RefCounted` a headless test can drive with no
## scene tree.
##
## ## Bounded and priced
##
## The floor is `marks * KARMIC_PER_MARK`, and the BOUND is the authored mark set itself: the
## soul can hold at most the three shipped marks, so the floor tops out at `0.15` — SLIGHT
## by construction, never near the mended ceiling. The price is the deaths themselves: a soul
## earns this only by dying, and nothing can buy it.

## The authored karmic-memory fates: the arrival marks each death grants. Named here in the
## flat fate namespace, so a content rename is a one-line edit and no other module learns
## the set.
const KARMIC_MARKS: Array[StringName] = [
	&"soul_marked_once", &"soul_marked_twice", &"soul_marked_thrice"
]

## The authored step (goal decision 4: authored defaults, tunable at content time). Small on
## purpose: the floor nudges a fresh body's start, it never substitutes for training.
const KARMIC_PER_MARK := 0.05

## The named refusal for a first life, which has nothing to remember.
const R_NO_KARMIC := "no_karmic_memory"
const R_NO_BODY := "no_body"


## How many karmic-memory fates `body` holds.
static func marks_held(body: Actor) -> int:
	if body == null:
		return 0
	var held := DestinyApi.fates(body)
	var count := 0
	for mark_id in KARMIC_MARKS:
		if held.has(mark_id):
			count += 1
	return count


## Seed `body`'s starting foundation from the karmic-memory fates it holds. Returns the
## `FoundationApi.seed_karmic` answer, or a NAMED refusal when the soul holds none (a first
## life, which has nothing to remember) or no body was handed over.
static func apply(body: Actor) -> Dictionary:
	if body == null:
		return {"ok": false, "reason": R_NO_BODY}
	var value := float(marks_held(body)) * KARMIC_PER_MARK
	if value <= 0.0:
		return {"ok": false, "reason": R_NO_KARMIC}
	return FoundationApi.seed_karmic(body, value)
