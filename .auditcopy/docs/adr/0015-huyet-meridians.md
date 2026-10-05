# 0015 Huyệt and body meridian system (Huyệt + Mạch)

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0012 established Body Cultivation as the physical refinement path with `body_integrity` as its resource pool. ADR 0014 defines the shared meridian (Mạch) system used by all three cultivation paths. This ADR defines the body-specific storage layer — Huyệt (acupoints) — and how body cultivation interacts with the shared meridians. No `core/` or `contracts/` changes; this extends `modules/body_cultivation/`.

## Decision

- **Acupoint tiers** (aligned to mortal + spirit tiers, realms 1-18):
  - **Minor Acupoints** (小穴) — realms 1-9 (Mortal): 36 points, store basic body essence.
  - **Major Acupoints** (大穴) — realms 10-18 (Spirit): 12 points, store refined body essence, unlock at Spirit tier.
  - **Celestial Acupoints** (天穴) — reserved for Immortal/Transcendent; discussed in a future ADR.
- **Capacity**: Each acupoint has a `body_essence` pool (`ResourcePool`) whose maximum scales with realm via `RealmDef` multipliers (ADR 0001). Body techniques consume from acupoints, not from `body_integrity` (which remains the durability pool from ADR 0012).
- **Quality**: Each acupoint has a `quality` float (0.0–1.0) that scales body technique effectiveness. Improved by qi cultivation cross-pollination, pills, and successful breakthroughs. Emitted as a derived stat `acupoint_quality` (average across open points).
- **Damage**: Failed breakthroughs block acupoints (set `blocked = true`), reducing effective capacity to zero until cleared by pills or meridian repair. Blocked acupoints cannot store or release essence.
- **Meridian interaction** (shared system from ADR 0014):
  - Body essence flows through meridians → strengthens the physical body (feeds `physique` base attribute).
  - **Meridian expansion** → increases acupoint capacity (multiplier on pool maximum).
  - **Meridian strengthening** → increases body technique power (feeds `body_cultivation_power` derived stat).
  - **Body cultivation repairs damaged meridians** — unique to this path; qi/mind cultivation risk meridian damage on failure, body cultivation can restore it.
- **Cultivation speed**: `base * (1 + meridian_expansion_bonus) * realm_multiplier`. Meridian preparation is a prerequisite for efficient body cultivation.
- **Breakthrough requirements** (mortal + spirit tiers):
  1. All acupoints full (`body_essence.current == maximum` for every open point).
  2. Required meridians expanded to the tier's threshold.
  3. `physique` threshold met.
  4. Body Tempering Pill consumed.
- **Breakthrough challenge**: If meridians are not fully prepared, body deviation risk increases. Failure causes acupoint blockage + meridian damage (temporary `physique` penalty via modifier stack, ADR 0001).
- **Training opportunity**: Body cultivators can intentionally repair damaged meridians; each repair cycle grants a permanent small `physique` bonus (capped), turning failure into long-term gain.

## Consequences

- Acupoints are a new `ResourcePool` array owned by `modules/body_cultivation/`; no `core/` or `contracts/` changes.
- The meridian system (ADR 0014) gains a body-specific consumer; its expansion/strengthening APIs must be callable from the body module via the shared facade.
- Breakthrough logic in `BodyProvider` must query meridian state before attempting advancement; the meridian facade exposes `expansion_level` and `damage` per channel.
- Acupoint blockage is a new status-like condition; the UI must display blocked points and repair options.
- The repair-to-strengthen loop gives body cultivators a distinct risk/reward identity: slower early growth, higher late-game ceiling.
- Celestial Acupoints are out of scope for mortal + spirit tiers; the data model reserves the field but gates it behind Immortal tier.
