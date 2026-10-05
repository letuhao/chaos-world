# 0217 A gate is a bargain, and a gate that fails either test is an authoring error the audit refuses

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0840, BL-0848

## Context

Five authored treasure/puzzle gates exist. Measured against the two things a gate must be:

| Fixture | `key_item_id` | key resolvable | `requires_realm` | bare actor passes? |
|---|---|---|---|---|
| `ash_camp_offering` | `""` | n/a | `""` | **yes — no gate** |
| `tide_vault_hoard` | `""` | n/a | `""` | **yes — no gate** |
| `ash_arena_formation` (puzzle) | `""` | n/a | `""` | **yes — no gate** |
| `ash_furnace_hoard` | `ash_furnace_key` | **now yes** | `core_formation` | no |
| `ash_heart_hoard` | `""` | n/a | `core_formation` | no |

(`game/src/data/domains/rooms/{ash_camp,tide_vault,ash_arena,ash_furnace,ash_heart}.tres`
lines 18 / 29 / 18 / 29 / 29.)

BL-0840 said `ash_furnace_key` was not an `ItemDef`. That is **no longer true** —
`game/data/items/key/ash_furnace_key.tres:17-19` ships `key_reach: 3` and
`ash_furnace.tres:29` reads `requires_realm: core_formation` too. BL-0840 is stale on its
fact and still right on its rule.

The three remaining shapes fail differently. `ash_camp_offering` and `tide_vault_hoard`
are tagged `treasure_unkeyed`, which is honest: an offering in a settlement and a shell
pile in a drowned vault are **supplies, not prizes**, and the cost of reaching them is the
walk. But `ash_camp_offering` sits in a `social` room reachable by anyone who enters the
domain, so its gate is not weak — it is **absent**, and the fixture should be authored as
an open container rather than a locked one that opens for everyone.

## Decision

**Every gate must pass BOTH tests, and a gate that fails either is an authoring error the
content audit hard-fails — never a runtime refusal a player discovers.**

- **SATISFIABLE.** A legal prior state exists in which the gate opens. Tested by
  construction: the key must be an `ItemDef` that `Crafting.resolve` finds under an
  `ITEM_ROOT`, **and** it must carry at least one shipped acquisition source (`sources`,
  a table entry, or a quest grant). A key with no route is BL-0840 exactly.
- **NON-TRIVIAL.** A bare actor — empty inventory, at the domain's own entry realm — must
  NOT already pass. If it does, the gate is theatre and the fixture is mislabelled, not
  over-protected.

**What to do with a gate that fails a test — and the answer differs by which test:**

- Fails SATISFIABLE → **delete the gate**. Do not author a key to satisfy it. A key
  authored purely to make a gate pass is a content wave spent on a door nobody chose.
- Fails NON-TRIVIAL → **delete the `treasure_keyed` tag** and keep the fixture open. A
  container anyone may open, holding something worth opening, is a good container. What
  makes it a gate must be the room it sits in, not a flag on it.
- Both pass → keep it, and publish its requirement through `DomainFixtures.telegraph` so
  a screen can render "sealed — needs a furnace key" before the player spends the walk.

**The room is a gate.** This is the load-bearing part, and it is what makes an ungated
fixture legitimate rather than lazy. A fixture's cost is not only `key_item_id`: it is
the room's `roster_band`, the hazards inside it (ADR 0075), the trap that fires on the
approach (`DomainFixtures.arm`), and the fact that all of it is one-shot per run. A camp
offering three rooms and two traps from the entry is gated by the walk. That is a real
gate with a real price, and it costs no authored numbers.

## Consequences

- **The audit gains two hard rules** over `res://src/data/domains/rooms/**`: a
  `treasure_keyed` fixture with an empty or unresolvable `key_item_id` fails, and so does
  a `treasure_keyed` fixture whose key resolves but carries no shipped source. Same shape
  as ADR 0075's empty-`mitigation_tags` rule — a rule that hard-fails.
- **BL-0840 closes as stale-but-upheld**: the gate is now satisfiable, and the rule it
  asked for is this ADR's SATISFIABLE test, made permanent by the audit rather than by
  the one content file that happens to be correct today.
- **BL-0848 closes** for the three ungated fixtures: two keep their reward and lose the
  mislabelled tag; the puzzle keeps its reward and is gated by its own wrong-node cost
  (`domain_fixtures.gd:204-239`) plus the arena it sits in.
- The two remaining gates pass both axes and stay untouched.

## Rejected

- **A warning instead of a failure.** Rejected: a warning about a gate no legal state
  satisfies is the same silent failure one layer down. ADR 0073 already ruled that a kit
  gap is "a hard authoring error, not a fallback".
- **Authoring the missing keys to preserve the gates.** Rejected: it converts a gate the
  designer wrote into one the audit invented, and the room's own danger was already the
  real price.
- **A `difficulty` scalar on the fixture to harden a weak gate.** Rejected: a
  power-shaped number on a container. AGENTS.md reserves those for an ADR — this one, and
  it declines to author the number.