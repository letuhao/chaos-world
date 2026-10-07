# 0912 Four-range streaming, prediction, transition hook (slice 5)

- Status: Accepted
- Date: 2026-10-07

## Context

Two radii could not answer "what simulates" versus "what shows", every step
generated underfoot, and a cut between worlds had no representation — any
arrival blinked across, seamless or not.

## Decision

- Four ranges, clamped in `configure`: render <= scene <= data, sim <= data.
  A hidden holder costs nodes but no pixels; simulated membership (cached
  ids in sim range of the focus) is the liveness answer for markers.
- `preload_toward(dx, dy, steps)` generates (never instantiates) ahead from
  the cursor, capped at 8 steps, answering known-vs-generated. Every step
  predicts two ahead.
- A node config with `seamless: false` yields to an app-installed transition
  hook naming both sides; refusal (or no hook: `no_transition_seam`) holds
  the player. Demo nodes stay seamless; the first cutscene-worthy arrival
  wires the hook to the LoadingScreen route.

## Consequences

- Summaries carry ranges + simulated ids (primitives only) for the slice-6 overlay.
- What this ADR does NOT do: drive the LoadingScreen (mechanism only), or
  simulate markers (liveness membership only — consumers read it).
