# Dual-cultivation art is a relationship scene, never a daily-life scene, never explicit

Status: accepted

## Decision

A dual-cultivation render is a **`relationship_scene`** — two characters, one occasion — and it is
never a `daily_life` shot. `daily_life` carries ONE character in an ordinary private moment;
`relationship_scene` is the only slot that already means "two people together". Romance is a
relationship scene. `ilsa_daily_romance` is a MISNAMED file, not a second romance slot: the word
"daily" in a filename does not make the shot a daily-life scene, and honouring the filename would
give the vocabulary two spellings for one idea.

Rendered art is **non-graphic and mechanical**. Attraction, affection, tension and intimacy of
presence are in scope. Intercourse, genitalia, exposed nipples or breasts, erotic or pornographic
framing, sexualised minors, sexual violence, fetish/BDSM and scat are out of scope, permanently,
and a render that needs any of them to make sense is the wrong render. Cultivation-path fiction
already treats dual cultivation as a **clinical mechanic** — a qi-exchange with a cost and a
balance — so the honest depiction is two people and the mechanism between them, not the act.

## Why

**One slot, one meaning.** Two slots that both accept "two characters together" make
`daily_life` and `relationship_scene` interchangeable, and an author picks by filename. The
vocabulary has to answer "how many people, and for what" with one word each.

**No verbs, no art.** `modules/dual_cultivation` exposes no player-facing verb, so a dual
cultivation portrait has nothing to display behind. The art decision therefore cannot wait on the
module, and equally must not be authored as though the module already exists: the scene is authored
as reference art now, and the slot it publishes into is the one `relationship_scene` already owns,
which needs no schema change and no new `PROMPT_SLOTS` entry.

**Non-graphic is a design constraint, not a filter.** Deciding after the fact that a render is too
explicit means the render was commissioned wrong. Naming the frame up front — two characters, the
qi-exchange between them, nothing else — is the only way the constraint survives a generation run.

## Consequences

- `daily_life` gains a canon minimum counted on DISTINCT daypart text, per ADR 0178's closed
  dawn/day/dusk/night vocabulary. Four shots reading the same daypart fail, exactly as nine
  identical expressions fail today.
- A dual-cultivation shot is placeable with no catalog change: `relationship_scene` already exists
  in `SLOT_KIND`.
- Art review for any `relationship_scene` applies the explicit-content rule above. `art_fidelity`
  measures palette, transparency and subject count; it does **not** and cannot judge this, so the
  rule is enforced by review against `MANUAL_REVIEW`, not by the automated gate. A gate that cannot
  see the thing it forbids must not claim to.
- `ilsa_daily_romance.png` is a **rename candidate**, not a schema change. Nothing reads its
  filename; it is corrected when the render set is next regenerated.