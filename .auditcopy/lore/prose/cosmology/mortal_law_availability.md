# Mortal-Tier Law Availability

## Three slots, six groups

`mortal_world` holds three imprints. Six groups exist and all six are authored as
available in the tier (`tier_ids` lists all four tiers on every `WorldLawDef`), so nothing
is forbidden here — three are simply not written.

## Which three, and why those

The choice is not free. A three-slot world must spend every slot on the groups without
which its content cannot exist, and the authored content pins all three:

- `mortal_plains` yields `iron_ore` and `herb_common`. Ore has hardness and weight, so it
  needs `physical_law`. A herb is alive, so it needs `life_law`.
- `mortal_plains` houses `beast` inhabitants, and `ironhide_bear` carries
  `combat_power_min` 5.0. A beast that hits for five and not for zero is a body running
  on stored qi, so it needs `qi_law`.

Those three are spent. `elemental_law`, `spatial_law` and `temporal_law` are not.

**Elemental is the first casualty, and permanently.** Nothing in that list needs an
element: no element is a hardness, a metabolism or a stored charge.

## What the three absences are physically

**Elemental absent.** No material in the world carries an element, so the seasons drift
rather than turn — `elemental_law` governs seasonal cycles, and unwritten it leaves the
year as weather, not law. Ore stays ore: `iron_ore` has no affinity, so no elemental
treasure can form. And no elemental can be alive, because an elemental is a life form and
nothing is licensing one. The authored data agrees: `storm_elemental` lists
`immortal_world` and `transcendent_world` only.

**Temporal absent.** A mortal world's clock is not governed from inside. That is why its
`time_flow` band (0.5 – 2.0) is the tightest in the setting — a world without a temporal
imprint has no anchor, so its rate drifts toward whatever the smallest content it holds
determines.

**Spatial absent — with one consequence that matters.** If spatial law is unspent, the size
band 10 – 100 units is a ceiling and not a range. Nothing presses the world open. It is
born at a size and it stays there, which is the physical reason a mortal world cannot grow
into a spirit world rather than a bureaucratic one.

## Qi is not absent; it is on the floor

`qi_law` is imprinted, and imprinted at the bottom of its 0.1 – 100 range. Enough that a
seed germinates, a body draws breath and an ironhide bear reaches combat power 5. Not
enough for a dantian to fill.

This is the difference the setting turns on. A **void** has no dial. A **strained** law has
a dial wired to the floor: it runs, and nothing can be done to it. A mortal world is
limited, not empty.

## The consequence nobody authors a workaround for

`mortal_world` licenses `plant` and `beast`. No humanoid. Every authored humanoid
inhabitant — `azure_disciple` — begins at `spirit_world`.

So **a mortal world cannot produce a humanoid practitioner.** Body Dao's home tier is
`mortal_world`. Body Dao's own people are not native to Body Dao's own tier, and must
arrive from above, which is what turns the authored `home_tier` ladder into a migration
story.