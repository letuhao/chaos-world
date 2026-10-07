# 0921 Tier-3 elements: void, chaos and time form a closed cycle above the ladder

- Status: Accepted
- Date: 2026-10-08

## Context

ADR 0004 reserved tier 3 — void, chaos and time — for "a later ADR", gated by mastery. The mastery path has since shipped (practice, Awaken, the rank+realm door, the qi tier-rise gate, the elixir door, the domain and trial blessings), and the door's tier half already reads `ElementMastery.max_tier`, which caps at three: `MAX_ELEMENT_TIER` is 3 and the realm ladder's IMMORTAL tier is what opens it. What was missing was the elements themselves.

Two constraints shape them. The mastery tax (the per-tier divisor that keeps an advanced element from being a strictly better attack) applies one step further at tier 3. And the ten-element matchup table's balance is MEASURED — the tier-1 mean is exactly 0.950 (ADR 0069) — so a triad that reached down with new overcomes would move a figure other tests and balance notes rest on.

## Decision

- **Three elements, one closed cycle**: `void` overcomes `chaos`, `chaos` overcomes `time`, `time` overcomes `void` (`game/src/modules/elements/default_elements.gd:45`). Each is strong against exactly one sibling and weak to the other, so the counterplay is the pick and no tier-3 element is a strict best response; tiers 1 and 2 are NEUTRAL in both directions by omission, which leaves the measured ten-element table untouched.
- **A separate list, not a merged one**: `ElementStats.TIER_THREE_ELEMENTS` (`game/src/modules/elements/stats.gd:32`) sits beside `BASE_ELEMENTS` and `ADVANCED_ELEMENTS` because the status catalogue's ten-name vocabulary (`StatusDef.AUTHORED_ELEMENTS`) and the tools that read those two lists are about the ten the ladder has always shipped. A tier-3 element that ships no status must not be demanded one by a reader that assumes every element is in the status set.
- **`all_ids()` carries them**, so the provider's stat families (`element_power_<e>`, `element_defense_<e>`, `element_crit_<e>`/`element_crit_resist_<e>`) and the omni sums include them the moment they exist — the same "a new element joins by existing" rule the crit family documents.
- **The door is the existing one**: `ElementMastery.max_tier` caps at `MAX_ELEMENT_TIER = 3` and the realm half reads the ladder's tier, so a tier-3 element is usable exactly from the IMMORTAL realm with the elemental rank to match (`game/src/modules/elements/mastery.gd:19`). No new gate is invented for tier 3.
- **The elixir family follows the tier**: `ELIXIR_GAIN_BY_TIER` pays `600.0` for tier 3 (`game/src/modules/elements/training.gd:80`) — roughly the same 2.4x step as tier 1 to tier 2 — and three authored elixirs plus recipes ship for the triad, so the "every element ships its mastery elixir" contract holds at thirteen elements.

## Consequences

- Tier 3 is reachable and playable: awaken an affinity, practise or drink an elixir, and the element opens at the Immortal realm — the same loop every other element uses.
- The triad ships as elements, not as content: no tier-3 statuses, wards or techniques are authored here, and none is demanded (the status catalogue's `AUTHORED_ELEMENTS` list is deliberately untouched). Content for them is a normal later wave.
- The balance consequence is NOT ruled here. A tier-3 element pays the tier-3 mastery tax with a neutral matchup against everything below, which is a coherent niche rather than a measured optimum; the ADR 0133 census (the open scale question) is where that gets numbers.
- `ElementCatalog`'s authored `.tres` path (ADR 0184 §5) remains a mod-overlay surface: the shipped table is the code-defined `ElementDefaults`, and a base `.tres` copy of the triad would be a second source of truth, so none is authored.
