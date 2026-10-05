# 0279 A System's persisted key names are declared by the contract, because the ledger normaliser drops anything it does not name

- Status: Accepted
- Date: 2026-10-06
- Extends: ADR 0267 (the `DoctrineRule` contract), ADR 0273 (the framework ships no System)

## Context

`DoctrineRule` tells a System where its state lives — `data_key()` returns
`doctrine/<id>`, and the System reaches it through `Actor.set_module_data`. It never said
what the dictionary inside is *keyed by*.

That gap was invisible until a template mod tried to persist a counter and found it
vanishing. `DoctrineLedger.normalize` (`modules/doctrine/doctrine_ledger.gd:57`) rebuilds
its dictionary from its own key list and
copies nothing else, so a counter stored under a System's own key name is **erased by the
next write** — no error, no refusal, just a counter that resets.

Three of the nine names (`points`, `points_max`, `owned`) happened to coincide with keys
the contract already published for *reads* (`PROGRESS_KEYS`, `PRICE_KEYS`). The other six —
`version`, `joined`, `balance`, `balances`, `earnings`, `redemptions` — were published
nowhere at all. So a System had to reach one module class past the contract to learn which
strings its own state used, and the three it could infer were inferring a coincidence
rather than reading a declaration.

A coincidence is not a contract, and nothing failed when one drifted.

## Decision

**`DoctrineRule` publishes the persistence vocabulary.** `PERSIST_KEYS` is the complete
list, and nine named constants (`POINTS_KEY`, `BALANCE_KEY`, …) exist so a System can name
one key without indexing a list.

**`SYSTEM_OWNED_PERSIST_KEYS` publishes the subset a System owns.** `DoctrineRule.earn`
returns a *proposal* and writes nothing, so the counter (`points`, `points_max`, `owned`)
belongs to the System, which advances it inside its own `redeem`. `balance`, `joined`,
`earnings` and `redemptions` belong to the framework and the next framework write
overwrites them.

**A System MUST use these names and MUST NOT add keys of its own.** That is not a
preference; it is the only way its state survives.

## Consequences

- The extension surface is now complete for a System that keeps state: `data_key()` says
  where, `PERSIST_KEYS` says under what.
- `game/tests/modules/doctrine/test_doctrine_persist_keys.gd` fails when the two lists
  disagree in **either** direction, and pins the behaviour that makes the declaration
  necessary — an undeclared key is *dropped*, not refused. That test is the reason the
  declaration cannot quietly become decorative.
- Two constants that looked like they said the same thing (`PERSIST_KEYS` and
  `SYSTEM_OWNED_PERSIST_KEYS`) are two questions — what may exist, and who may write it —
  and collapsing them would lose the ownership half, which is the half that stops a System
  overwriting the framework's balance.
- This is an **OCP change to `contracts/`**, so it carries its own ADR and its own contract
  tests. It adds surface; it changes no existing behaviour.
- The companion defect is **not** fixed here and is filed as DEF-0321: no channel at all
  can currently grant a *permanent base attribute* to an actor. The vocabulary above is
  about naming state, not about moving stats.