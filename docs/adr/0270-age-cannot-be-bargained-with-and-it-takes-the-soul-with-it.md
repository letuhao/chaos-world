# 0270 Age cannot be bargained with, and it takes the soul with it

- Status: Accepted
- Date: 2026-10-05

## Context

ADR 0258 decided that age ends a **body** rather than a run, and that a guardian — the
consumable that spends an item and costs nothing else — would **prevent** an age death. The
argument was ADR 0130's own: a guardian buys one more body, and an aged body handed its
lifespan back is a younger body with a young soul, because age lives on the BODY and the body
was never swapped.

Both halves of that are now reversed by the owner, and the reversal is deliberate.

**A guardian must not be the answer to age.** The reasoning that made it right in the abstract
made it wrong in play: "the body was never swapped, so the soul is untouched" is exactly why it
does not read as a death at all. It costs an item and nothing else, which is a clean trade for a
wound. Applied to expiry it converts the end of a life into a consumable, and a player learns
that the correct response to ageing is to carry a certain item — which makes age a resource
check wearing the costume of a fate.

**And expiry must cost the soul.** If it only costs the body it is a tax with a counter, and the
programme's whole argument for the soul (ADR 0127) is that a body is not the thing being
preserved. More to the point, this is what makes the pair in ADR 0258 §3 land: age raises
comprehension and social standing, and a death that leaves those standing untouched would let a
hero bank a lifetime's worth of standing and then walk into the next body still holding it. An
age death that erases the soul is the only outcome under which an aged run is genuinely different
from a young one.

The cost is that the run is not endless. That is the intent.

## Decision

### 1. A guardian does NOT prevent an age death

The age check sits **above** the guardian branch, not below it. The order is:

```
age expired -> age death (guardian never consulted)
otherwise   -> guardian? spend it, cost nothing
           -> otherwise wound, damage the soul, re-body
```

A player holding a guardian when their body expires still loses the body. The item is a
lifeline against a **wound**, and expiry is not a wound.

### 2. The guardian's own lifespan extension is a DIFFERENT item

"There is an item that extends life" is a real and separate affordance, and it is kept — but it
is not the guardian. A lifespan-extending consumable raises the **authored lifespan** the body
was born with, which is a number in `RealmLifespan` / the race's body plan, not a one-shot
rescue. It is a different verb with a different cost, it is consumed once and has no effect on
a body already past its span, and it does not make expiry survivable — it moves the date.

This is the distinction that keeps both affordances honest: the guardian buys a re-body, the
elixir moves the deadline, and neither stops the clock.

### 3. An age death damages the soul to destruction, and the soul is ERASED

- The soul is damaged by the **authored expiry cost**, not by zero. `damage` keeps the one
  meaning it already has on this verdict (ADR 0190's full-key-set rule), and `0` would be a lie
  about a death.
- On expiry the soul is **erased**: incarnation, damage trail, fates, counters and the arrival
  history all go. The next body starts from nothing.
- **The loss is real and it is the point.** A hero who reaches the end of a long life arrives in
  the next vessel with none of the standing, comprehension or recognition that age granted, and
  none of the fates the previous life earned. That asymmetry — a long life is worth playing, and
  it is not bankable — is the reward half of ADR 0258 §3 doing its work.
- `SoulGate.can_rebody` is still consulted, and an exhausted soul refuses by name. Expiry does
  not grant a life the soul has not earned.

### 4. The guardian precedence test is inverted, and the reason is recorded

The test that proved "a guardian prevents an age death" was a **correct test of the wrong
decision**, and it is load-bearing in the wrong direction: it will fail until the decision is
reversed. That is intended, and the test's name should say which way it asserts. A guard that
stops failing because nobody re-read the ADR is how ADR 0188 happens.

## Consequences

- `SoulDeath.resolve` moves the age check above the guardian branch. The guardian branch keeps
  its own full key set (ADR 0190); the age branch publishes its own.
- `damage` on an age death is the authored expiry cost.
- The soul is erased on expiry: a new `FACT_ID` is **not** required, because the fact ledger
  records that the body ended and the erasure is the soul's own state, not a world fact. A quest
  asking how many deaths a soul has earned still hears about it; a quest asking how many times
  this hero fell in battle does not, which is why the two counts must be distinguishable.
- A lifespan-extending consumable is a NEW verb, not a re-skin of the guardian. It needs its own
  option, its own content and its own guard; see BL-0892's next step.
- `RealmLifespan` gains a way to raise an authored lifespan, keyed by NAME (ADR 0050) — never by
  row index, so a new tier shifts nothing.
- The age bands in `age_band_table` are unchanged: ageing is still a **pair** (ADR 0258 §3), and
  this ADR removes the escape hatch, not the trade-off.

## Rejected

- **Guardian prevents age-death.** It makes the end of a life a consumable, and the correct
  response to ageing becomes an inventory check.
- **Age erases only the body.** Then a lifetime's standing is bankable across vessels, and ADR
  0258's buff half has no cost, which makes the pair a debuff with a bonus rather than a trade.
- **Age deals zero damage but erases.** Two contradictory messages on one verdict: "nothing was
  lost" and "everything was lost". `damage` is the authored cost and the erasure is separate.
- **One item doing both.** A single consumable that both rescues an expiry and extends a lifespan
  collapses the distinction between buying a re-body and moving a deadline, and makes the
  guardian's own ADR 0130 semantics unreadable.
