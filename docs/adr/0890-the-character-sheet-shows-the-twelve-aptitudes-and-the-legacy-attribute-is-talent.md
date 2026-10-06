# 0890 the character sheet shows the twelve aptitudes and the legacy attribute is Talent

- Status: Accepted
- Date: 2026-10-06

## Context

- DEF-0349: `aptitude_points()` and `Aptitude.*` appeared nowhere under `ui/`, so the
  port's foundation had no observable surface — a player could not see their build
  identity, and a breakthrough that moved it was invisible.
- `StatPresenter` printed the stored ATTRIBUTE under the label "Aptitude", colliding by
  name with the layer `ADR 0881` introduced. Two different quantities reading as one word
  is a vocabulary defect, not a layout one.

## Decision

- The character sheet gains an **Aptitudes** section: one `StatRow` per aptitude, in
  `Aptitude`'s append-only ordinal order, drawn through `StatRow`'s `stat` key so
  `StatPresenter` owns every label. The section is declared in `character_screen.tscn`
  (one row per structural aptitude, like the pool block) rather than grown in code.
- The section title carries the dominant posture — `AptitudeGrant.dominant_posture`'s
  read, where a tie resolves to none — so "what does my build lead with" is answerable at
  a glance. `summary()["aptitudes"]` reports `dominant` (id, `""` for none), `points`
  (all twelve, zero included, keyed by id) and `total`, all primitives.
- Every aptitude is reported even at zero: the roster is structural (three postures of
  four), so a missing key would read as an aptitude the game does not have.
- Aptitude points print EXACT (as held), not at the attribute's declared precision: a
  point can be fractional — a technique split divides by four — and `agility` is the one
  id the roster shares with a stored attribute, so the sheet passes the precision for the
  aptitude row explicitly rather than letting the shared id's attribute precision round a
  point.
- The stored attribute `Stat.APTITUDE` is renamed in display only (the id is unchanged):
  the label reads **"Talent"**. "Aptitude" now names the source layer alone.
- `_vitals_summary` keeps the first row per label, so the shared `agility` label reports
  the attribute's figure while both rows still draw.

## Consequences

- A breakthrough is now visible: the involved aptitude rows and the dominant posture
  change on the sheet (`test_the_aptitudes_are_reported_with_the_dominant_posture`,
  `test_the_sheet_draws_a_row_per_aptitude_and_names_the_posture`).
- DEF-0349 is `done`; the sheet is the layer's read surface until a dedicated screen is
  needed. No spend verb, preset or respec is introduced (ADR 0881's rule stands).
- The aptitude ids join `StatPresenter`'s table, which is already the sheet's label table
  for pools and combat-owned rates; the reconciliation tests (`test_the_aptitude_ids_are_declared`,
  `test_a_declared_stat_is_not_labelled_with_its_own_id`) keep the entries honest.
