# 0897 a status's authored potency base replaces the shared reuse

- Status: Accepted
- Date: 2026-10-07

## Context

- ADR 0885 recorded an incompleteness on purpose: "the BASE magnitude still reads
  `element_power_<e>` (ADR 0088's reuse) and the request's authored `potency` ... retiring
  the reuse means deciding what a status's authored base IS, and no status carries one
  yet." DEF-0344 (family 6) tracks it.
- `potency_of` is `maxf(status_potency_floor, element_power_<e> * status_potency_scale)`,
  and `resolve_roll` took `maxf(request.potency, that)` — so a request potency could only
  RAISE the reuse, never replace it. No shipped writer set the key at all; every request
  read it implicitly as `0.0`.
- The tension is real and is why this is a decision rather than a patch: `status_def.gd`
  refuses a per-status NUMERIC magnitude because "a second magnitude vocabulary a rebalance
  has to edit twenty times" is worse than the reuse. The potency path is the one place
  ADR 0885 said an authored base belongs.

## Decision

- `StatusDef` gains `potency_base: float = 0.0`. `0.0` means NOT AUTHORED and the shared
  reuse decides — which is every shipped def, so the default is byte-identical and no
  catalogue behaviour moves.
- An authored base (`> 0`) REPLACES the reuse rather than `maxf`-ing against it. Retiring
  the reuse is what authoring a base means, and a floor no def can go under is the reuse
  refusing to retire.
- The three writers hand it over in the request's existing `potency` slot
  (`combat/exchange.gd` on both exchange sites, `app/combat_boot.gd` on the spine path);
  `StatusApply.resolve_roll` stays the single arithmetic owner and the only reader.
- `magnitude_unit` still governs how a status RESOLVES its effect. This is not a second
  magnitude vocabulary — it is the one number the potency path was missing, authored only
  where the shared reuse is the wrong shape for a status.

## Consequences

- Family 6 of DEF-0344 is structurally moveable: the base is authorable today, and the
  content wave (authoring a value per status) is tracked rather than guessed here.
- Pinned by
  `test_status_potency_channels.gd::test_an_authored_base_replaces_the_shared_reuse_and_zero_keeps_it`:
  an authored `0.05` beats the `0.1` the shared curve reads, and `0.0` keeps the shared
  reading.
- The balance report's family-6 line now says the base is authorable; a def that authors
  one shows up in the potency it lands.
