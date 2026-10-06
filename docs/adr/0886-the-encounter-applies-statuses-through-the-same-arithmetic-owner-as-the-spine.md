# 0886 the encounter applies statuses through the same arithmetic owner as the spine

- Status: Accepted
- Date: 2026-10-06

## Context

- The completeness audit found the port's second phase missing from the main PvE loop:
  `CombatExchange._status_on_landing` and `_boss_affliction_numbers` ran only the gate
  (`apply_chance`) and their own copies of selection, seeding, rolling and potency
  lookup, so ADR 0885's potency split and immunity never reached a domain encounter.
- The two exchange sites rolled their own substreams and re-derived `potency_of`; the
  producer's request path (`combat_boot`) and the spine's S12 stage had the full
  arithmetic. Three copies of "how a status resolves", one of them stale.
- The WRITE styles genuinely differ by architecture: `combat_engine` has no `status`
  edge, so the spine writes through `Actor.add_status`; `loot` has a `status` edge and
  writes through `StatusApi.apply` (runtimes, modifiers, bursts). Unifying the WRITER is
  an edge change this ADR does not take.

## Decision

- S12's arithmetic gets ONE owner: `StatusApply.resolve_roll(attacker, target, tuning,
  request, rng, technique, hit_index) -> Dictionary`. It validates the id and gate,
  reads the immunity tags, computes both potency net factors and the intensity floor,
  resolves the chance and makes the ONE seeded roll. It writes nothing and takes no
  `CombatOutcome`, and it returns primitives only (`ready, refused, detail, status_id,
  chance, resist, potency, intensity_net, duration_net, open`) — `potency` is the fully
  factored magnitude a writer applies.
- `StatusApply.apply` keeps its clean-hit gate, the closed-gate and already-held
  refusals, then delegates to `resolve_roll` and `_written`; `_written` now only builds
  and hands the effect over.
- BOTH `CombatExchange` sites call `resolve_roll` with the request the producer already
  shapes (`id, element, kind, immunity_tags, chance, scope`). The player's-blow site
  writes through `StatusApi.apply` with the factored potency and the net-scaled duration;
  the boss-affliction site hands `chance`/`potency`/`gate_open` down to `LootApi.strike`
  exactly as before, so `loot`'s own writer stays its own.
- Selection alignment is a NON-issue, recorded so nobody re-opens it: `status_for_element`
  reads `chance` only as a closed-gate check and the catalogue guarantees one claim per
  element, so selecting with the gate and selecting with the computed chance return the
  same id. The gate is used in both sites because it is the authored value.
- The encounter's roll is unchanged: same `status_seed(rng.seed, actor, actor, active,
  salt)` inputs, same saturated/closed short-circuits, so every seed-pinned suite
  (`test_loot_boss_affliction`, `test_combat_exchange_status`) measures the same verdicts.
- The stale claims found by the audit are corrected in the same change: `exchange.gd`'s
  "no production caller" comments about `ElementsApi.attach` (false since
  `actor_factory.gd` attaches it), and the exchange suite's fixture that pinned the
  RETIRED `Stat.STATUS_RESISTANCE` id, which made its "resisted" arm decorative (DEF-0350).

## Consequences

- The split and immunity now run on BOTH production paths; `test_combat_exchange_status`
  proves it end to end by asserting one net-factor scale of intensity doubles the
  encounter's reported potency (DEF-0345's acceptance).
- One arithmetic owner means a future change to the gate, the split or immunity cannot
  again reach only one path; the writers remain two by architecture, which is a fact
  about module edges rather than a rule with two copies.
- The end-to-end immunity assertion on the encounter path still needs an authored status
  with `immunity_tags`; it lands with the first tagged content (DEF-0346).
