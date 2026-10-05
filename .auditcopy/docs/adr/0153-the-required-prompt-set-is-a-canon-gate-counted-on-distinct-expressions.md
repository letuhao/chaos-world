# 0153 The required prompt set is a canon gate counted on distinct expressions

- Status: Accepted
- Date: 2026-10-04

## Context

ADR 0138 gave `unique_characters` a `kind` per shot: the routing key a renderer
dispatches on, with three kinds and shots free-form within one. It made no claim
about WHICH prompts a character must have.

A character can therefore pass every existing check with nine `portrait` shots
and no exploration token. `report` prints a kind histogram, and a histogram with
one bucket full is the shape a healthy catalog looks like. Nothing states that the
nine required prompt types exist, so nothing can report one missing.

The natural fix is a required slot per shot plus a minimum count per slot. That
fix has a specific failure mode worth recording, because it is the reading
everyone reaches for first.

## Decision

Two vocabularies, not one.

- `kind` answers HOW to render: `map_sprite`, `concept`, `portrait`, `dialogue`,
  `scene`. Five kinds cover the nine required prompts because an expression sheet
  and a dialogue portrait are the same graph at different framings. The split is
  by render graph, never by prompt count.
- `slot` answers WHY the shot exists: the nine required prompts. Only `slot` has
  a required minimum.

`SLOT_KIND` pins each single-shot slot to its kind, as a failure. A `map_sprite`
slot holding a waist-up portrait is a mislabelled prompt, and the alternative is a
catalog that validates and is still missing the exploration representation.

Coverage is enforced at the `canon` promotion gate, not by a separate command.
`canon` is the claim that a character is fully specified; a canon character with
no map token is one the exploration map cannot place. A gate that only reported
at render time is later than the moment it is cheap to fix.

`expression_set` and `pose_set` are SETS, and a set is counted on the **distinct
text that makes two of its members different** — `SET_SLOT_MEMBER_FIELD`, which
is `expression` for the expression set and `pose` for the pose set.

Not the number of shots. Nine expression shots that all read "composed" is a
prompt set by cardinality and a single picture by content — the exact shape an
agent produces when it satisfies a count instead of writing nine emotions.

The two sets are counted on different fields on purpose. Counting `pose_set` on
`expression` — the obvious way to write one loop over both — demands nine
distinct emotions from a character being asked for nine stances, which no author
can satisfy except by restating the stance in the emotion field. A prompt set
that passes while saying the same thing twice is worse than one that fails,
because it looks complete. Shot ids are not the identity either: members are
free-form slugs, so `expr-anger` and `expr-anger-bitter` are one emotion
described twice.

The minimums are 9 and 6 because the art brief enumerates nine emotions and six
poses, not because those are round. Raising one is a spec change.

`art.style` stays outside this. No slot carries it, and the brief's SUBJECT block
is what keeps identity stable across a character's prompts: it is derived from one
record, so a portrait and a concept sheet cannot disagree about who they are.

## Consequences

- `unique_characters add` still writes a valid draft with an empty shot list. The
  nine-prompt minimum is a promotion condition, so drafting stays one command.
- `unique_characters report` prints per-character prompt gaps, because a gate that
  only speaks at promotion time reports the answer after the authoring is done.
- A shot without a `slot` is refused at any status. A shot that cannot be
  attributed to a required prompt cannot be counted toward one, so accepting it
  would make the canon gate count shots it cannot place.
- The minimum is a PROMPT count. Rendering stays optional per shot and is
  `unique_characters next`, so the gate raises the cost of authoring text and not
  the cost of generating images.
- `tools/selftest_cases.py` asserts the gate goes RED, including the duplicated
  expression fixture and the pose-counted-on-pose fixture. Those cases are the
  only things distinguishing a set guard from a count guard, and a pose guard from
  an expression guard (INC-0016).