"""One-off authoring helper for the ADR 0258 age-band statuses (throwaway).

Kept out of the repo on purpose: the CONTENT is the eight `.tres` files, and this script
is only the writer that produced them, so committing it would add a second place that can
describe the same eight rows.
"""

import os

HEADER = '''[gd_resource type="Resource" script_class="StatusDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/modules/status/status_def.gd" id="1_status"]

[resource]
script = ExtResource("1_status")
id = &"age_{band}_{half}"
# {rationale}
element = &""
# AMBIENT, and deliberately so: an age band is inflicted by BEING THIS AGE, not by a landed
# blow and not by standing in a hazard. `StatusDef.problems()` makes `element` mandatory
# because every status in `res://data/statuses` rides one; naming a fire element here would
# be a lie the shipped catalogue would act on, because `StatusApi.status_for_element` would
# answer with this for every fire blow in the game.
#
# `mitigation_tags` below is still mandatory and still published: a status nothing answers
# to is a flat tax (ADR 0090), and these are answered by `gear`/`pill`/`technique` exactly
# as any other is. `ambient = true` waives EXACTLY ONE rule - the element - and no other.
ambient = true
on_landed_blow = false
kind = &"stat_modifier"
scope = &"cultivation"
# PERMANENT and never expiring: an age band is a stage of a life, not an affliction with a
# timer. A hero does not recover from being fifty. `StatusDef.DURATION_FOREVER`.
stacking = &"refresh"
duration = -1.0
magnitude_unit = &"stat_modifier"
magnitude_cap = 1.0
tick_interval = 1.0
# {ops}
mitigation_tags = Array[StringName]([&"affinity", &"gear", &"technique", &"pill"])
payload = {{
"mechanic": &"{mechanic}",
"text": "{text}",
{axis_note}"modifiers": [
{mods}
]
}}
'''

RATE_REASON = (
    "`cultivation_rate` and `insight_gain` are RATE stats (`Stat.RATE_STATS`), so PERCENT is\n"
    "the only op that means anything on them - a FLAT of `+10` would be 1000%, which is why\n"
    "`StatusDef._modifier_problems` refuses it. `health_regen` and `stamina_regen` are NOT\n"
    "rate stats and carry a small non-zero baseline (`core/actor_stats.gd:149,151`), so a\n"
    "PERCENT on them is authored content and not the ADR 0022 no-op."
)

BASE_ATTR_REASON = (
    "`comprehension` is a BASE ATTRIBUTE, which a `StatModifier` can only RAISE - so this is\n"
    "a floor under a poor build rather than a reward a lucky one already had. `dao_heart`\n"
    "resolves from `will` (`core/actor_stats.gd:210`) and has no zero baseline for any actor\n"
    "this game builds, so a FLAT is the right op; PERCENT would be legal but is not what this\n"
    "says."
)

AXIS_NOTE = (
    "# ONE of ADR 0258 §3's four axes is deliberately not a `StatModifier`: 'social standing\n"
    "# and recognition accumulate'. `social_reputation` is PROVIDER-contributed\n"
    "# (`social/social_provider.gd:41`) and ADR 0026 makes a provider's contribution the\n"
    "# BASELINE a modifier then scales once - so a FLAT authored on it would be silently\n"
    "# overwritten by every bond the hero forms and would be a lie the tree acts on. The social\n"
    "# half is carried by the BAND ITSELF: the status id is the named fact a recognition rule\n"
    "# reads, and `StatusApi.summary` publishes it under `age`, so the axis is named rather than\n"
    "# faked.\n"
)

WEAR_OPS = RATE_REASON
CLARITY_OPS = BASE_ATTR_REASON


def _comment(block: str) -> str:
    """A block as `#`-prefixed lines, for the slots the format allows a comment in."""
    return "\n".join("# " + line for line in block.split("\n"))


WEAR = {
    "first_ash": {
        "mechanic": "brace",
        "text": (
            "An unworn body. Nothing has been asked of it yet, so nothing about it has "
            "dulled either."
        ),
        "mods": [
            '{"stat": &"cultivation_rate", "op": &"percent", "value": 0.04}',
            '{"stat": &"health_regen", "op": &"percent", "value": 0.05}',
            '{"stat": &"stamina_regen", "op": &"percent", "value": 0.04}',
        ],
        "rationale": (
            "THE FIRST ASYMMETRY, and the reason the pair test asserts a DIRECTION per band\n"
            "# rather than one direction for all four: even the youngest band's cost axis reads\n"
            "# POSITIVE. A band whose debuff granted nothing would make `first_ash` a strictly\n"
            "# worse state than a hero who has not yet been told what they are, which is the\n"
            "# `RealmPowerTable` NEUTRAL argument with the sign flipped - `AgeBandTable` gives\n"
            "# `first_ash` a fraction of exactly `0.0`, so its band is real, and a real band\n"
            "# with an empty debuff would be an invisible tax rather than a cost."
        ),
    },
    "greenwood": {
        "mechanic": "brace",
        "text": (
            "The body still pays for everything it is asked to do. A little slower, a little "
            "stiffer, and much more certain of what it already knows."
        ),
        "mods": [
            '{"stat": &"cultivation_rate", "op": &"percent", "value": -0.12}',
            '{"stat": &"health_regen", "op": &"percent", "value": -0.10}',
            '{"stat": &"stamina_regen", "op": &"percent", "value": -0.08}',
        ],
        "rationale": (
            "DEBUFF HALF, row 2 of 4: the cultivation gain rate falls. This is the cost of a\n"
            "# long life and it is paid in the SPEED of the climb, never in its height -\n"
            "# ADR 0258 §4's rule, so nothing here touches a realm power table, a cultivation\n"
            "# rate curve or a pool maximum. The health/stamina pair is the second debuff axis\n"
            "# §3 names, and both are the pools `ActorPools` regenerates through\n"
            "# (`core/actor_pools.gd:89`), so a worn body pays to come back from a fight as\n"
            "# well as to study."
        ),
    },
    "gilded": {
        "mechanic": "brace",
        "text": (
            "The turn. The body takes longer to mend and longer to settle into a stance, and "
            "the years behind it have left a clarity the young never earn."
        ),
        "mods": [
            '{"stat": &"cultivation_rate", "op": &"percent", "value": -0.24}',
            '{"stat": &"health_regen", "op": &"percent", "value": -0.20}',
            '{"stat": &"stamina_regen", "op": &"percent", "value": -0.16}',
        ],
        "rationale": (
            "DEBUFF HALF, row 3 of 4: the same two axes as row 2 and roughly twice the bite.\n"
            "# `max_health`, `max_qi` and every other POOL MAXIMUM are deliberately absent -\n"
            "# age scales shares of what the player holds, never a magnitude, which is ADR\n"
            "# 0258 §4 and the whole reason an old hero is slower rather than smaller."
        ),
    },
    "lastlight": {
        "mechanic": "brace",
        "text": (
            "The last of it. Everything the body was quick at is now slow, and everything it "
            "has seen is suddenly worth something."
        ),
        "mods": [
            '{"stat": &"cultivation_rate", "op": &"percent", "value": -0.36}',
            '{"stat": &"health_regen", "op": &"percent", "value": -0.30}',
            '{"stat": &"stamina_regen", "op": &"percent", "value": -0.24}',
        ],
        "rationale": (
            "DEBUFF HALF, row 4 of 4: the cost of a whole lifespan, and the only row where the\n"
            "# cost nearly cancels the gain. That near-cancellation IS the design - a body at\n"
            "# three quarters of its life is close to being better at nothing - and the pair\n"
            "# test asserts the buff half still leaves a long-lived hero strictly better off\n"
            "# than removing the debuff half does."
        ),
    },
}

CLARITY = {
    "first_ash": {
        "mechanic": "regrowth",
        "text": (
            "Nothing has been learned that cannot be unlearned. The mind is quick, and nobody "
            "has told it yet what it is for."
        ),
        "mods": [
            '{"stat": &"insight_gain", "op": &"percent", "value": 0.06}',
            '{"stat": &"dao_heart", "op": &"flat", "value": 0.5}',
        ],
        "rationale": (
            "BUFF HALF, row 1 of 4: the reading is FASTER than every band above it and the\n"
            "# floor is the barest positive. An old hero has to be BETTER at reading the dao\n"
            "# than a young one, or there is no reward for the pair to pay - which is what the\n"
            "# pair test measures when it removes this half."
        ),
    },
    "greenwood": {
        "mechanic": "regrowth",
        "text": (
            "Comprehension with a shape to it. What was learned holds, and what is learned now "
            "arrives in a form that survives the next decade."
        ),
        "mods": [
            '{"stat": &"insight_gain", "op": &"percent", "value": 0.10}',
            '{"stat": &"dao_heart", "op": &"flat", "value": 2.0}',
            '{"stat": &"comprehension", "op": &"flat", "value": 2.0}',
        ],
        "rationale": (
            "BUFF HALF, row 2 of 4. `insight_gain` is the RATE every training path prices its\n"
            "# work through (`qi_cultivation/training.gd:177`, `body_cultivation/training.gd:40`,\n"
            "# `mind_cultivation/training.gd:156`) and `dao_heart` is the FLOOR a tribulation\n"
            "# charges against, so the two are the same axis read as a rate and a magnitude -\n"
            "# a rate that falls has a rate that rises, and a stat that decays has a stat that\n"
            "# accrues."
        ),
    },
    "gilded": {
        "mechanic": "regrowth",
        "text": "The years have settled into a floor of understanding that no setback can argue below.",
        "mods": [
            '{"stat": &"insight_gain", "op": &"percent", "value": 0.14}',
            '{"stat": &"dao_heart", "op": &"flat", "value": 4.0}',
            '{"stat": &"comprehension", "op": &"flat", "value": 4.0}',
        ],
        "rationale": (
            "BUFF HALF, row 3 of 4: the comprehension / dao-heart floor ADR 0258 §3 names in one\n"
            "# row. `comprehension` is a BASE ATTRIBUTE, which a `StatModifier` can only RAISE,\n"
            "# so this is a floor a poor build cannot be argued below - not a reward a lucky one\n"
            "# already had."
        ),
    },
    "lastlight": {
        "mechanic": "regrowth",
        "text": (
            "Almost everything has been seen already. The dao is the part of a person that "
            "does not fade, and this body has been keeping it warm for a very long time."
        ),
        "mods": [
            '{"stat": &"insight_gain", "op": &"percent", "value": 0.18}',
            '{"stat": &"dao_heart", "op": &"flat", "value": 6.0}',
            '{"stat": &"comprehension", "op": &"flat", "value": 6.0}',
        ],
        "rationale": (
            "BUFF HALF, row 4 of 4, and the largest grant in the whole tree. That is the\n"
            "# mechanical answer to 'what did a long life buy': an old body is measurably worse\n"
            "# at everything physical and measurably better at everything it has already had\n"
            "# time to understand."
        ),
    },
}


def main() -> None:
    # The repo root, from this script's own directory: it lives at the root, so ONE `..`
    # would leave the repo and the two it walks up wrote a phantom tree beside the drive.
    root = os.path.normpath(
        os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "game",
            "src",
            "data",
            "statuses",
            "age",
        )
    )
    os.makedirs(root, exist_ok=True)
    written = 0
    for band in ("first_ash", "greenwood", "gilded", "lastlight"):
        for half, table, ops in (("wear", WEAR, WEAR_OPS), ("clarity", CLARITY, CLARITY_OPS)):
            row = table[band]
            mods = ",\n".join(row["mods"])
            body = HEADER.format(
                band=band,
                half=half,
                rationale=_comment(row["rationale"]),
                ops=_comment(ops),
                mechanic=row["mechanic"],
                text=row["text"],
                axis_note=AXIS_NOTE,
                mods=mods,
            )
            path = os.path.join(root, "age_%s_%s.tres" % (band, half))
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(body)
            written += 1
    print("wrote", written, "files into", root)


if __name__ == "__main__":
    main()