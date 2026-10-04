---
name: create-unique-character
description: >
  Create one named Chaos World character that emerges from the Lore Bible instead of from random
  trait draws, and register it with a validated nine-prompt visual asset set. Use when asked to
  create, design, or generate a unique/named character, NPC, sect member, playable character, or
  antagonist; to write a character's background, family, relationships, or story hooks; or to
  produce CLIP text-encode prompts for a character's portraits, expressions, poses, concept art, or
  combat and scene art. Resolves the lore context chain first, grades every background dependency
  REUSE/EXPAND/GAP, and refuses to invent lore it did not search for.
---

# Create Unique Character

A character is a set of consequences, not a set of traits. The Lore Bible decides what a character
*can* be; the resolver says which of it is missing; the catalog refuses to call a character canon
until both its background chain and its nine-prompt visual set are complete.

Two commands carry the discipline. `lore context` names the domains that contributed nothing.
`unique_characters check` refuses to promote a character with holes. Neither can be satisfied by
confident prose.

## Non-negotiables

- **Search before creating.** Grade every background dependency REUSE / EXPAND / GAP. Inventing a
  sect because you did not run `lore search sect` is a defect, not a decision.
- **One agent per character.** Never batch two characters in one context window. Cross-contamination
  is the main source of cosmetic duplicates, and it is invisible in the output.
- **Bounded loops.** Every loop gets a named terminating bound (INC-0002). A loop that grows a
  container it tests never terminates — snapshot the bound *before* the loop.
- **Commit before the next character.** Uncommitted work is unrecoverable; there is no reflog entry
  for a file that was never staged. Stage only your own paths (`git add <path>`, never `git add -A`),
  and never revert a path you do not own.
- **Non-sexual by rule.** Attraction, courtship, marriage, jealousy, dual cultivation and family
  formation are supported and are written clinically and mechanically. Never sexual, explicit, or
  suggestive prose, names, or assets — the repo rule, and `BRIEF_CONSTRAINTS` already refuses it
  downstream. All characters are adults, fully clothed.

## The pipeline

Ten steps, in order. Each step's output is the next step's input. Running a later step on missing
context produces a character that has to be thrown away, and the throwaway is what gets committed.

### 1. Search, then anchor

```bash
uv run python -m tools lore search "<query>" --limit 20
uv run python -m tools lore context <anchor-id> --draft "<Character Name>" --path <qi|body|mind>
```

Anchor on a **race** by default: race biology fixes lifespan, which fixes what a family is, which
fixes culture and social expectation. It is the deepest hub in the graph and the chain that follows
from it is the longest. Anchor on a world or a faction only when the character exists to serve one.

`--draft` prints a `unique_characters`-shaped record pre-filled from resolved lore. Keep
`reference_stats` exactly as printed — it is prose on purpose (ADR 0138), and any number you add
there is refused by the guard.

### 2. Read the MISSING block, and treat it as the task

`lore context` prints `INHERITED` (what the walk reached) and `MISSING` (what it did not), each
missing domain labelled with its purpose:

```
  [load-bearing] history        what already happened
  [supporting  ] families       who you owe
  [supporting  ] organizations   what you have sworn to
```

`load-bearing` first. A missing `history` means the character has no cause, and a character
without a cause is exactly the randomly-generated person this skill exists to prevent. The exit
code is non-zero while any domain is missing, which is the readiness signal, not an error to retry.

### 3. Brainstorm against measured diversity

```bash
uv run python -m tools lore coverage          # per-domain depth and diversity, worst first
uv run python -m tools unique_characters report  # tag axes, kind histogram, prompt gaps
```

Draft three to five candidate identities, then pick on **structure**, never on cosmetics. Compare
candidates on: origin, worldview, what they owe, what they want versus what they are for, the
contradiction they carry, and the pressure that produced them. `report` prints the tag axes already
in use with counts — a fourth `role:assassin` with a new name is not a distinct direction.

Reject a candidate whose distinctness survives only if you rename it.

### 4. Grade every dependency REUSE / EXPAND / GAP

For each hop in the chain, classify before writing a word of the character:

```bash
uv run python -m tools lore show <id>            # one entity with its incident relationships
uv run python -m tools lore traverse <id> --depth 2
uv run python -m tools lore chain <id> --depth 4  # walk backwards: why does this exist
uv run python -m tools lore gaps                 # what is missing, and why
uv run python -m tools lore queue --domain <d> --limit 25
```

- **REUSE** — the lore already answers it. Use it; cite the id.
- **EXPAND** — the entity exists and is thin. Enrich the existing record; never add a second one.
- **GAP** — nothing exists. Only now may you create, and the new lore must pass `lore validate`
  and be reusable by the next character.

New background goes through the authoring path, not into the character record:

```bash
uv run python -m tools lore brief <domain> --batch <unique-batch-id> --focus "<what is missing>"
```

One agent owns one bible file. Edges are append-only per batch. Never let two agents write one
shard — that is how a wave loses work.

### 5. Register the shell

```bash
uv run python -m tools unique_characters add \
  --character-id unique-0001 --name "<Name>" \
  --role <pc|npc|boss> --path <qi|body|mind|unaffiliated> --style <lowercase-slug>
```

This writes a `draft` with empty shots — valid, deliberately unfinished. Fill it, then promote.

### 6. Design the character into the real schema

The catalog schema is fixed; map your content onto it rather than inventing keys.

| Content | Field |
|---|---|
| identity, occupation | `identity.role`, `canon.role_in_story` |
| faction / sect / oath | `identity.faction` → `organizations` entity id |
| cultivation path, realm | `identity.path` (`qi`/`body`/`mind`/`unaffiliated`), `identity.realm` |
| race / species | `appearance.race` → `races` entity id |
| age / lifecycle | `appearance.age` |
| face, hair, eyes, build, complexion, marks, attire, bearing, palette | the other ten `appearance.*` keys |
| origin, homeland | `identity.home` → `geography` entity id |
| culture, language | `canon.lore` |
| formative experiences | `canon.history`, **earliest first** |
| beliefs, values, taboos | `canon.personality.taboos`, `motivations` |
| personality, voice, habits | `canon.personality.*` (7 keys) |
| desires, fears, flaws, secrets | `canon.personality.motivations`, `flaws` |
| social class, reputation | `tags` (`axis:value`), `canon.role_in_story` |
| education, abilities, fighting identity | `reference_stats.combat_read` |
| allies, enemies, mentors, rivals, obligations, romance | `canon.relationships[]` |
| goals, future trajectory | the last `canon.history` beat, plus `motivations` |

**Story hooks, not stories.** Write pressure, not plot. "Owes a debt to a sect that no longer
exists" is a hook; "will be killed by her master in chapter nine" is a story, and it forecloses
every other use of the character.

`tags` are `axis:value`, both sides lowercase slugs. The axis vocabulary is deliberately open —
`scar:oath-burned` is legitimate. A count of 1 in `report` may be a typo.

### 7. Link relationships to real entities

Every `canon.relationships[]` entry is `{to, kind, note}`:

- `to` — a Lore Bible id. **Verify it**: `uv run python -m tools lore show <to>`. `check` does not
  resolve relationship targets, so an unverified `to` is a promise nothing keeps.
- `kind` — free-form prose (`ally`, `rival`, `mentor`, `debtor`, `sworn_to`, `blood_feud`).
- `note` — what the relationship *does* to this character, not what it is.

Aim for relationships that cross domains. A character whose entire relationship list points at one
organization has an affiliation, not a life.

### 8. Build the nine-prompt visual set

`kind` answers how to render; `slot` answers why the shot exists. Only `slot` has a required
minimum. A shot needs `id`, `kind`, `slot`, `pose`, `framing`, `expression`, `scene`, `status`,
`canvas`.

| Slot | Kind | Min | Notes |
|---|---|---|---|
| `map_sprite` | `map_sprite` | 1 | small-scale exploration token |
| `dialogue_portrait` | `dialogue` | 1 | waist-up, neutral default |
| `character_portrait` | `portrait` | 1 | polished primary |
| `concept_art` | `concept` | 1 | full body, clothing and equipment readable |
| `environmental_concept` | `concept` | 1 | `scene` must name a lore-correct location |
| `combat_concept` | `concept` | 1 | weapon, abilities, fighting identity |
| `relationship_scene` | `scene` | 1 | `scene` required; interpersonal or dramatic |
| `expression_set` | `portrait` | 9 | distinct **expression** text |
| `pose_set` | `portrait` | 6 | distinct **pose** text |

Nine and six are the counts the art brief enumerates. The two sets are counted on different fields
on purpose (ADR 0153): a pose set is six different stances, so putting the stance in `expression`
as well satisfies the count while writing the same thing twice.

Identity is stable across all nine by construction — the brief derives `SUBJECT` from the record's
`appearance`, so a portrait and a concept sheet cannot disagree about who they are. Only pose,
expression, framing and scene vary. Never hand-write a prompt per shot; the tool builds it:

```bash
uv run python -m tools unique_characters plan --character-id unique-0001 --shot-id <shot-id>
```

Rendering is separate and optional per shot:

```bash
uv run python -m tools unique_characters next --count 12
uv run python -m tools unique_characters install --character-id unique-0001 --shot-id <id> \
  --source <model> --prompt <text> --source-name <name> --license <license> [--seed N]
uv run python -m tools unique_characters preview --kind concept --limit 32
```

An installed shot must carry `source`, `prompt`, `generated_on` and `license`, and the PNG must be
transparent and exactly the declared canvas.

### 9. Validate

```bash
uv run python -m tools unique_characters check
uv run python -m tools lore validate
uv run python -m tools lore challenge --only cross-batch-tensions
```

`check` fails on: an invalid or duplicate id, a missing name, a malformed field shape, an empty
face, a shot with no `slot`, a `slot` routed to the wrong `kind`, a missing shot canvas or
provenance, and — at `canon` only — any of the nine prompts missing or under-filled.

It does **not** resolve relationship targets, and `lore validate` does not know the character
catalog exists. Verifying `to` in step 7 is the agent's job; nothing enforces it for you.

`lore validate` fails on the bible's own problems: dangling references, `slot`-independent schema
faults, and self-reference. `lore challenge` never fails; its findings are questions the bible
cannot answer about itself. Read it, and answer in the record.

### 10. Promote and register

Set `status` to `canon` **only** after step 9 is clean, then re-run `check`. `canon` is the claim
that this character is fully specified and that its art set is complete — it is not a quality
rating.

A character that fails validation returns to you for enrichment. It does not count toward
completion, and it is not committed as canon.

## Dispatching one agent per character

Give each agent exactly this, with the anchor resolved for it:

> Create ONE character. Do not create, modify, or delete any other character record, and do not
> touch `game/assets/**` or any `lore/` file — report gaps as text instead.
> 1. `uv run python -m tools lore context <anchor-id> --draft "<Name>" --path <p>`
> 2. Read the MISSING block; treat `load-bearing` domains as required work.
> 3. Grade every dependency REUSE / EXPAND / GAP with `lore show` / `traverse` / `chain` / `gaps`.
> 4. `unique_characters report` for diversity; pick a structurally distinct direction.
> 5. `unique_characters add`, then fill the record per the schema map above.
> 6. Author all nine prompt slots. Sets vary on `expression` and `pose` respectively.
> 7. `unique_characters check` clean, then set `status: canon`.
> 8. Commit only your own paths with an explicit pathspec.
> Every loop you write gets a named terminating bound; state which guard makes it terminate.

## Failure modes worth naming

- **Cosmetic distinctness.** A new name on an existing archetype. `report`'s tag histogram is the
  cheapest way to see it.
- **Race equals culture.** A species implies no personality, nation, or ideology. If every Emberblood
  is hot-tempered and loyal, the race is a costume.
- **Backfilled history.** `canon.history` written as a consequence of the character rather than a
  cause of them. If the history could be swapped with another character's unchanged, it is not
  history.
- **Satisfying counts.** Nine expression shots reading the same thing passes a shot count and fails
  the guard. The guard exists because this is the natural failure.
- **Resolving nothing.** A character with no `load-bearing` history filled is random with extra
  steps.