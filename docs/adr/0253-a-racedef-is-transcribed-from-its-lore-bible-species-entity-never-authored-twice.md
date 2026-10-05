# A RaceDef is transcribed from its Lore Bible species entity, never authored twice

Status: accepted

## Decision

Every `RaceDef` under `res://data/races/` is **transcribed** from the matching `races.<id>` entity
in the Lore Bible by `tools race_from_lore`. The Bible is the single authoring surface for a species;
the `.tres` is a projection of it, regenerated rather than edited.

Fields map one to one, with no interpretation:

| `RaceDef` | Lore entity |
|---|---|
| `id` | the entity id with `races.` stripped |
| `display_name` | `name` |
| `description` | `summary` |
| `dominance`, `manifestation_threshold`, `gestation_days`, `base_fertility`, `base_potency`, `offspring_variance`, `realm_ceiling`, `lifespan` | the same key under `attributes` |
| `closed_paths` | the same key under `attributes` |
| `base_attributes` | `base_attributes`, **seeded** at the plain-mortal `1.0` for all of `Stat.BASE_ATTRIBUTES` and overlaid with the Bible's values |
| `percent_modifiers`, `affinities` | the same key under `attributes` |
| `tags` | `tags`, kebab-case converted to `snake_case` |

`realm_ceiling_mechanism` and `cultivation_paths` have no `RaceDef` field and are **not**
transcribed; that prose stays in the Bible, which is where a reader looks for why a ceiling exists.

## Two refusals, and neither is negotiable

**An omitted balance scalar is a refusal, not a default.** `RaceDef`'s declared default is the
CLASS's idea of an ordinary body, not this species's, so filling one silently authors a balance
decision nobody made. Five species (`emberborn`, `hearthborn`, `tideborn`, `tideculled`, `voidborn`)
omit all eight scalars, so every number in their files would be invented.

**A body that cannot strike is a refusal.** `tidecaller.tres` states the mechanism: "an omitted
grant is a grant of 0.0 — `_grant` only ever ADDS ... Omitting it does not make this body
even-framed, it makes it unable to hit anything." The real `wake` entity authors
`attack_physical: -1.0` and reaches the same state through the other route.

Together these mean a refused species has **no `RaceDef`**, so no character naming it can be
selected. The tool invents nothing to avoid that.

## Why

346 of 400 canon characters name a species with no `RaceDef` at all — the cast uses ~29 lore species
against a game race table of 5. Those portraits load, validate, and can never be selected, because
`for_race` resolves by race id and no race of that name exists. Nothing rejected the mismatch, so
the gap passed every gate the repo owns.

Hand-authoring 25 races would author the same numbers twice. The Bible already carries every field a
`RaceDef` declares: `longwinter` has `dominance`, `base_attributes`, `percent_modifiers`,
`affinities`, `closed_paths`, `realm_ceiling` and a prose `realm_ceiling_mechanism` explaining why
its ceiling is 17. That is the authored balance decision; a `.tres` copy is a second place to retune
it, which is the drift `AGENTS.md` names when six independently-chosen caps diverge.

**The mapping is verified, not assumed.** All 7 stat names the Bible uses are declared in
`contracts/stat.gd`, and every `percent_modifiers` key across all species is one of the declared stat
keys — zero undeclared. Had any key been free text, transcription would have produced resources
that silently do nothing, which is exactly the defect the free-text `race:` tags in
`character-index.jsonl` already are.

## Consequences

- **Today this ships nothing, and that is the honest state.** Of 33 lore species: 4 are already
  authored on disk and keep their values, 6 are refused above (5 missing balance, `wake` for a zero
  attack), and the remaining **23 transcribe cleanly and every one of them fails the race suite** —
  none has a written body plan, and 10 additionally lack a structural liability under ADR 0062, a
  gestation, a fertility/potency fraction, or any dominance at all. See the deferral for the
  per-species list. The blocker is content, not transcription, so no `.tres` was committed.
- **The Bible becomes load-bearing for the race table.** A Bible that fails to load leaves existing
  `.tres` untouched rather than truncating them.
- **A stat the Bible names that `contracts/stat.gd` does not declare is a hard failure**, reported
  even for a species this decision refuses — the author is about to go edit that entity anyway.
- **Kebab-case tags become `snake_case`.** The Bible writes `cold-adapted`; the game writes
  `&"cold_adapted"`. A hyphen in a `StringName` would not match a `has_trait` gate.
- **The five hand-authored races keep their values.** Re-running never overwrites an existing `.tres`
  without `--force`, and an already-authored race is never reported as a refusal — its completion
  lives in its own file.