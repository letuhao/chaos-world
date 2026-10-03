"""The acquisition requirement graph, read from authored content only.

`ItemDef.sources` is an authoring claim that nothing in `game/src` reads, so the
only honest way to ask "can a player ever hold this item" is to walk the graph the
game ships: `sources` -> a recipe or a boss -> the domain that hosts that boss ->
an authored `LootEncounterDef` -> the loot table bound to that boss.

This module answers the narrowest useful question: for the body cultivation path,
which bosses must an authored encounter host before every realm's three
consumables can be crafted. It resolves ids through the authored graph, never
through an id convention, so renaming an item or a realm cannot silently break it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from ..common import REPO_ROOT, ToolError
from ..data import DATA_ROOT, _load  # noqa: PLC0415  one parser for the whole corpus
from ..item_migrate import realm_ladder
from . import design

ENCOUNTER_DIR = DATA_ROOT / "loot" / "encounters"
# The three consumable roles a realm seed declares, in the order a reader meets
# them. A realm missing any of them cannot offer the full loop, so the validator
# reports it rather than letting a chain walk an empty graph.
#
# The body path names its second role `strengthening_item` and the two qi/mind
# paths name theirs `training_item`. Declared per path rather than sniffed from
# the file, because a role that is *absent* and a role that is *renamed* produce
# the same empty read and only one of them is a content defect.
LADDER_PATHS: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("body", "body_cultivation", ("breakthrough_item", "strengthening_item", "recovery_item")),
    ("qi", "qi_cultivation", ("breakthrough_item", "training_item", "recovery_item")),
    ("mind", "mind_cultivation", ("breakthrough_item", "training_item", "recovery_item")),
)
WORLD_PATH = "world"
# A ladder trial's domain is named after the path and the realm, and the boss that
# carries a realm's catalyst carries that prefix. Both are read off the authored
# boss record rather than built from the convention: the convention finds the
# candidate, and the candidate's own `domain_id` is the answer, so a renamed trial
# domain resolves and a misnamed boss does not.
TRIAL_PREFIX = "{path}_{realm_id}_"
# `ItemSources.KINDS`, mirrored for the two kinds that name a *drop site* rather
# than a verb. `craft`/`gather`/`starter`/`quest` name no boss and no domain, so
# they are deliberately absent: a walk that needed them would be asking a different
# question. Spelling them here rather than inline keeps the reader honest about the
# fact that the `sources` vocabulary is owned by `game/src` and mirrored, not
# invented — `tools data audit` cross-checks the two.
ROUTE_BOSS = "boss"
ROUTE_DOMAIN = "domain"
# `LootContent.MAX_NESTING_DEPTH`, mirrored so a walk over authored tables bounds
# its own recursion rather than inheriting the resolver's guard from a distance.
MAX_TABLE_NESTING = 4


@dataclass(frozen=True)
class Reagent:
    """One recipe input: the item, and the bosses that author it as a drop."""

    item_id: str
    bosses: tuple[str, ...]


@dataclass(frozen=True)
class Consumable:
    """One realm seed role: the item, the recipe that makes it, its reagents."""

    role: str
    item_id: str
    recipe_id: str
    reagents: tuple[Reagent, ...]
    bosses: tuple[str, ...] = ()
    """The `boss:` sources the consumable itself declares.

    Kept beside the reagents because the reagent list answers a different
    question. A reagent is an *input*, so the recipe needs it and the boss that
    carries it is a catalyst by definition. A consumable is an *output*: it is
    judged as a catalyst only because its table is what a player opens, and a
    rolled one is a miss with no second run to retry it (rule E2).
    """


@dataclass(frozen=True)
class Trial:
    """One authored trial domain and what has to make it playable.

    Two shapes share this record because one generator serves both, and because
    the runtime does not care which it is — `LootApi.enter_domain` spawns a boss
    from an encounter either way:

    - a **ladder trial** (`body`/`qi`/`mind`) is one realm's own trial domain. It
      carries a canonical realm id and the realm's catalysts, so its bands have to
      guarantee them: a cleared band grants no second run (loot rule E2), so a
      catalyst left to a roll soft-locks the ladder permanently.
    - a **world trial** (`amulet_iron_sage_domain` and its 57 siblings) is a
      creature's home. It has no ladder position, no consumables and no catalysts,
      and its band realm is a derived label — see [method Graph.band_realm].
    """

    trial_id: str
    """`{path}_{realm_id}` for a ladder trial, the domain id for a world trial."""

    path: str
    ladder: bool
    realm_id: str
    index: int
    display_name: str
    domain_id: str
    boss_ids: tuple[str, ...]
    consumables: tuple[Consumable, ...]

    @property
    def catalysts(self) -> dict[str, tuple[str, ...]]:
        """boss id -> the item ids that boss must guarantee for this trial.

        Two sources, one answer, because both are things the next realm cannot do
        without. A **reagent** is named by a recipe input, so the boss that carries
        it is a catalyst by definition. A **consumable** is named by the realm's
        own seed and is what the band is actually opened for; reading only the
        reagents left 85 boss-dropped consumables unjudged, 15 of them on the qi
        ladder, and a rolled catalyst on a cleared band is the permanent soft-lock
        this property exists to prevent (rule E2: a cleared band grants no second
        run, so a miss is forever).
        """
        out: dict[str, list[str]] = {}
        for consumable in self.consumables:
            for reagent in consumable.reagents:
                for boss_id in reagent.bosses:
                    out.setdefault(boss_id, []).append(reagent.item_id)
            for boss_id in consumable.bosses:
                if boss_id and consumable.item_id:
                    out.setdefault(boss_id, []).append(consumable.item_id)
        return {boss_id: tuple(sorted(set(ids))) for boss_id, ids in sorted(out.items())}


@dataclass
class Encounter:
    """The authored bindings of one loot encounter, flattened for checking."""

    path: Path
    encounter_id: str
    domain_id: str
    boss_ids: tuple[str, ...]
    tiers: tuple[dict, ...] = field(default_factory=tuple)


# --- Field readers ----------------------------------------------------------

_ARRAY = r"Array\[[^\]]*\]\(\[(.*?)\]\)"


def scalar(text: str, name: str) -> str:
    """The authored value of `name`, or "" when the file does not declare it.

    Quoting is normalized away, because Godot writes a `StringName` as `&"x"` and
    a `String` as `"x"`, and both are the same id to a reader. A value left quoted
    would be re-quoted by the writer into `"\"x\""`, which only fails at run time.
    """
    match = re.search(rf"(?m)^{name}\s*=\s*(.+?)\s*$", text)
    if match is None:
        return ""
    value = match.group(1).strip()
    for quote in ('&"', '"'):
        if len(value) > 1 and value.startswith(quote) and value.endswith('"'):
            return value[len(quote) : -1]
    return value


def unquote(value: str) -> str:
    """`&"x"` or `"x"` -> `x`. Anything else is returned unchanged."""
    text = value.strip()
    for quote in ('&"', '"'):
        if len(text) > 1 and text.startswith(quote) and text.endswith('"'):
            return text[len(quote) : -1]
    return text


def resource_scalar(text: str, name: str) -> str:
    """A field of the `[resource]` block, ignoring every `sub_resource` field.

    A `.tres` repeats `id` once per sub-resource, so a whole-file scan answers
    with whichever entry was authored first. Only the main block carries the id a
    reader addresses the file by.
    """
    marker = text.rfind("[resource]")
    if marker < 0:
        return ""
    return scalar(text[marker:], name)


def string_array(text: str, field_name: str) -> tuple[str, ...]:
    """An authored `Array[StringName]` of bare strings."""
    match = re.search(rf"(?m)^{field_name}\s*=\s*{_ARRAY}", text, re.S)
    if match is None:
        return ()
    return tuple(re.findall(r'&"([^"]*)"', match.group(1)))


def bindings(text: str, field_name: str) -> tuple[dict, ...]:
    """An authored `Array[Dictionary]` of `{key: &"value"}` pairs."""
    match = re.search(rf"(?m)^{field_name}\s*=\s*Array\[Dictionary\]\(\[(.*?)\]\)", text, re.S)
    if match is None:
        return ()
    out: list[dict] = []
    for block in re.findall(r"(?s)\{(.*?)\}", match.group(1)):
        entry = dict(re.findall(r'"([a-z_0-9]+)"\s*:\s*&?"?([^",}]*)"?', block))
        if entry:
            out.append(entry)
    return tuple(out)


def sub_resources(text: str) -> list[str]:
    """Every `sub_resource` block of a `.tres`, in authored order.

    Split on the opening bracket rather than matched with a block pattern: the
    bodies have no fixed terminator, and a lookahead for the next block header
    silently swallows the last one.
    """
    return [
        chunk
        for chunk in re.split(r"(?m)^\[sub_resource", text)[1:]
        if chunk.split("\n", 1)[0].endswith("]")
    ]


# --- The graph --------------------------------------------------------------


def _omits_declared_bosses(encounter: Encounter, boss_ids: tuple[str, ...]) -> bool:
    """Whether `encounter` spawns every boss its domain declares."""
    return any(boss_id not in encounter.boss_ids for boss_id in boss_ids)


class Graph:
    """Authored acquisition content, parsed once and queried many times."""

    def __init__(self, root: Path = DATA_ROOT) -> None:
        self.root = root
        self.records, self.malformed = _load(root)
        self._authored_drops_cache: dict[str, set[str]] | None = None
        self.items = self.records.get("item", {})
        self.recipes = self.records.get("recipe", {})
        self.bosses = self.records.get("boss", {})
        self.domains = self.records.get("domain", {})
        self.loot_tables = self.records.get("loot_table", {})
        self.ladder = tuple(realm_ladder())
        # Encounters before trials: a ladder trial picks its domain by preferring
        # one that already carries an encounter, so it has to be able to read them.
        self.encounters = self._encounters()
        self.trials = self._ladder_trials()
        self.world_trials = self._world_trials()
        # Every domain a trial wants an encounter for, ladder trials first. A
        # world trial is only ever a domain no ladder trial claimed, so the two
        # collections cannot ask for the same encounter.
        self.all_trials = tuple(self.trials.values()) + self.world_trials

    # --- authored text

    def read(self, record: dict | None) -> str:
        """The authored text of a record, or "" when it cannot be read."""
        if not record:
            return ""
        path = self.root / record["path"]
        return path.read_text(encoding="utf-8") if path.is_file() else ""

    def field(self, record: dict | None, name: str) -> str:
        """A scalar the audit's schema does not carry, read off the file.

        The audit records only the fields its own rules need, so `display_name`
        and `tags` are not in any record. Reading them from the file keeps one
        parser for the corpus instead of a second one beside it.
        """
        return scalar(self.read(record), name)

    # --- items

    def item_sources(self, item_id: str) -> tuple[str, ...]:
        record = self.items.get(item_id)
        return tuple(record["arrays"].get("sources", ())) if record else ()

    def item_field(self, item_id: str, name: str) -> str:
        record = self.items.get(item_id)
        return str(record["scalars"].get(name, "")) if record else ""

    def item_tags(self, item_id: str) -> tuple[str, ...]:
        """Every `unique_route:` tag on an item.

        Route-limiting is the one acquisition claim a generated table must never
        contradict: a table bound to a different boss resolves such an item to a
        refused drop.
        """
        return tuple(
            tag
            for tag in string_array(self.read(self.items.get(item_id)), "tags")
            if tag.startswith("unique_route:")
        )

    # --- bosses and domains

    def boss_loot(self, boss_id: str) -> tuple[str, ...]:
        record = self.bosses.get(boss_id)
        return tuple(record["arrays"].get("loot", ())) if record else ()

    def boss_domain(self, boss_id: str) -> str:
        record = self.bosses.get(boss_id)
        return str(record["scalars"].get("domain_id", "")) if record else ""

    def boss_display_name(self, boss_id: str) -> str:
        return self.field(self.bosses.get(boss_id), "display_name")

    def domain_bosses(self, domain_id: str) -> tuple[str, ...]:
        record = self.domains.get(domain_id)
        return tuple(record["arrays"].get("boss_ids", ())) if record else ()

    def domain_display_name(self, domain_id: str) -> str:
        return self.field(self.domains.get(domain_id), "display_name")

    # --- the three ladders

    def _seed(self, path: str, realm_id: str) -> str:
        for prefix, directory, _roles in LADDER_PATHS:
            if prefix != path:
                continue
            seed = DATA_ROOT / directory / "realms" / f"{realm_id}.tres"
            return seed.read_text(encoding="utf-8") if seed.is_file() else ""
        return ""

    def _ladder_trials(self) -> dict[str, Trial]:
        """Every realm of every cultivation path that resolves to a trial domain.

        Keyed `{path}_{realm_id}`, because a realm id means the same rung on all
        three ladders and the three trials are three different encounters: keying
        on the realm id alone would let the qi trial overwrite the body one and the
        last path seeded would silently be the only one validated.
        """
        out: dict[str, Trial] = {}
        ladder = {realm_id: index for index, realm_id in enumerate(self.ladder)}
        for path, _directory, roles in LADDER_PATHS:
            for realm_id in sorted(self.ladder):
                seed = self._seed(path, realm_id)
                if not seed:
                    continue
                domain_id = self._boss_domain_for_realm(path, realm_id, roles)
                if domain_id not in self.domains:
                    continue
                out[f"{path}_{realm_id}"] = Trial(
                    trial_id=f"{path}_{realm_id}",
                    path=path,
                    ladder=True,
                    realm_id=realm_id,
                    index=ladder[realm_id],
                    display_name=self.domain_display_name(domain_id),
                    domain_id=domain_id,
                    boss_ids=self.domain_bosses(domain_id),
                    consumables=self._consumables(seed, roles),
                )
        return out

    def _boss_domain_for_realm(self, path: str, realm_id: str, roles: tuple[str, ...]) -> str:
        """The domain a realm's trial lives in.

        Read off the realm's own path boss, the one boss the generation contract
        names per realm on each ladder. A realm whose boss is missing resolves to
        no domain and is reported as a gap rather than guessed.

        The first match wins, and that is a content decision rather than an
        accident: `qi_qi_refining_guardian` and `qi_qi_refining_warden` both carry
        the prefix, and they live in different domains. The one already carrying an
        encounter is preferred, so a second, coarser grouping of the same ladder's
        bosses never displaces the trial the ladder walks.
        """
        seed = self._seed(path, realm_id)
        prefix = TRIAL_PREFIX.format(path=path, realm_id=realm_id)
        candidates: list[str] = []
        for item_id in (scalar(seed, role) for role in roles):
            for reagent_id in self._reagents(self._craft_recipe(item_id)):
                for boss_id in self._bosses_of(reagent_id):
                    if boss_id.startswith(prefix):
                        candidates.append(self.boss_domain(boss_id))
        for domain_id in candidates:
            if self.encounter_for_domain(domain_id) is not None:
                return domain_id
        return candidates[0] if candidates else ""

    def _craft_recipe(self, item_id: str) -> str:
        for source in self.item_sources(item_id):
            if source.startswith("craft:"):
                return source.split(":", 1)[1]
        return ""

    def _reagents(self, recipe_id: str) -> tuple[str, ...]:
        record = self.recipes.get(recipe_id)
        return tuple(record["arrays"].get("inputs", ())) if record else ()

    def _bosses_of(self, item_id: str) -> tuple[str, ...]:
        return tuple(
            source.split(":", 1)[1]
            for source in self.item_sources(item_id)
            if source.startswith(f"{ROUTE_BOSS}:")
        )

    def _refs(self, item_id: str, kind: str) -> tuple[str, ...]:
        """Every `<kind>:<ref>` source `item_id` declares, de-duplicated in order."""
        prefix = f"{kind}:"
        seen: dict[str, None] = {}
        for source in self.item_sources(item_id):
            if source.startswith(prefix):
                seen.setdefault(source[len(prefix) :], None)
        return tuple(seen)

    def domain_routes(self, item_id: str) -> tuple[str, ...]:
        """Every domain `item_id` declares as a `domain:` route.

        `ItemSources.KIND_DOMAIN`, and it is `shipped` — the reader resolves it, so
        a `domain:` ref is a delivery claim exactly like a `boss:` one. It was the
        larger of the two by count (6540 declarations over 160 domains, against 1501
        `boss:` ones) and nothing here read it, which is how a walk that only
        followed `boss:` could conclude that an item was unreachable while a domain
        was handing it out. That conflation cost DEF-0188, which reported 41 items
        unobtainable and was wrong about every one of them.
        """
        return self._refs(item_id, ROUTE_DOMAIN)

    def domain_delivery_bosses(self, domain_id: str) -> tuple[str, ...]:
        """The bosses a `domain:` route actually delivers through.

        A domain delivers through the bosses an authored encounter for it spawns,
        narrowed to those every band binds a table for. A boss the domain declares
        but the encounter omits cannot be spawned by `LootApi.enter_domain`, and a
        boss with no bound table has nothing to drop from, so neither counts as a
        delivery route — the same two facts `_content_problems` already reports, read
        here as "can this claim be paid" instead of "is this content broken".
        """
        encounter = self.encounter_for_domain(domain_id)
        if encounter is None or not encounter.tiers:
            return ()
        spawnable = set(encounter.boss_ids)
        return tuple(
            boss_id
            for boss_id in encounter.boss_ids
            if boss_id in spawnable
            and all(self.table_for(encounter, tier, boss_id) for tier in encounter.tiers)
        )

    def delivering_bosses(self, item_id: str) -> tuple[str, ...]:
        """Every boss that can hand out `item_id`, by either drop route kind.

        The honest answer to "can a player ever hold this", and the reason the
        earlier `boss:`-only walk was wrong: a `domain:` route reaches a boss the
        named-boss walk never visits. It reports *reachability*, never *guarantee* —
        which boss delivers an item and whether that delivery is unconditional are
        two different questions, and only [method Trial.catalysts] may raise the
        second.
        """
        found = list(self._bosses_of(item_id))
        for domain_id in self.domain_routes(item_id):
            for boss_id in self.domain_delivery_bosses(domain_id):
                if boss_id not in found:
                    found.append(boss_id)
        return tuple(sorted(found))

    def unpayable_domain_routes(self) -> tuple[tuple[str, str], ...]:
        """(item, domain) for every `domain:` claim nothing can deliver.

        The mirror of the `boss:` rule the module docstring states: a source naming
        something no encounter spawns is a claim nothing can pay, and it is reported
        at authoring time — the only moment the file that wrote it can still be
        found. Deliberately *not* a guarantee demand. A domain that pays an item by
        roll is reachable, and calling it broken here would demand 41 new content
        guarantees across a corpus whose `domain:` routes are authored as ordinary
        drops.
        """
        out: list[tuple[str, str]] = []
        for item_id in sorted(self.items):
            for domain_id in self.domain_routes(item_id):
                if domain_id not in self.domains:
                    out.append((item_id, domain_id))
                elif not self.domain_delivery_bosses(domain_id):
                    out.append((item_id, domain_id))
        return tuple(out)

    def unbound_delivery_bosses(self, domain_id: str) -> tuple[str, ...]:
        """Bosses an encounter for `domain_id` spawns that some band leaves unbound.

        The middle case [method unpayable_domain_routes] folds into "unpayable": a
        domain whose only boss has no table on some band cannot deliver through that
        band, and rule E2 means a band is never re-run, so what it cannot deliver is
        gone. Split out here so the report can name which boss and which band, which
        is the difference between "your route points nowhere" and "your route points
        at a boss one band forgot to bind".
        """
        encounter = self.encounter_for_domain(domain_id)
        if encounter is None:
            return ()
        return tuple(
            boss_id
            for boss_id in encounter.boss_ids
            if any(not self.table_for(encounter, tier, boss_id) for tier in encounter.tiers)
        )

    def _consumables(self, seed: str, roles: tuple[str, ...]) -> tuple[Consumable, ...]:
        out: list[Consumable] = []
        for role in roles:
            item_id = scalar(seed, role)
            recipe_id = self._craft_recipe(item_id)
            reagents = tuple(
                Reagent(reagent_id, self._bosses_of(reagent_id))
                for reagent_id in self._reagents(recipe_id)
            )
            out.append(
                Consumable(role, item_id, recipe_id, reagents, bosses=self._bosses_of(item_id))
            )
        return tuple(out)

    # --- the world domains

    def _world_trials(self) -> tuple[Trial, ...]:
        """Every non-ladder domain whose bosses carry drops and no encounter.

        A world domain is a creature's home, not a rung of a ladder: it has no
        realm seed, no consumables and no catalysts. It still needs an encounter,
        because `LootApi.enter_domain` resolves a boss through one and a boss in
        no encounter is a boss `enter_domain` cannot spawn — which is why its
        drops are unreachable, not why they are undeserved.
        """
        claimed = {trial.domain_id for trial in self.trials.values()}
        out: list[Trial] = []
        for domain_id in sorted(self.domains):
            if domain_id in claimed:
                continue
            existing = self.encounter_for_domain(domain_id)
            # Only a **foreign** encounter that is *complete* excludes a domain. One
            # this generator wrote under its own deterministic id is still this
            # generator's work and has to stay in the walk, or a rule change could
            # never be re-applied to it: the domain would drop out of
            # `world_trials`, its tables would stop being regenerated, and a boss
            # that gates a ladder would keep a rolled catalyst forever. An
            # incomplete one is included too, because its omitted boss is owed a
            # route whatever wrote the encounter.
            if (
                existing is not None
                and existing.encounter_id != design.encounter_id(domain_id)
                and not _omits_declared_bosses(existing, self.domain_bosses(domain_id))
            ):
                continue
            boss_ids = tuple(
                boss for boss in self.domain_bosses(domain_id) if self.declared_drops(boss)
            )
            if not boss_ids:
                continue
            realm_id = self.band_realm(domain_id, boss_ids)
            if not realm_id:
                continue
            out.append(
                Trial(
                    trial_id=domain_id,
                    path=WORLD_PATH,
                    ladder=False,
                    realm_id=realm_id,
                    index=self.ladder.index(realm_id),
                    display_name=self.domain_display_name(domain_id),
                    domain_id=domain_id,
                    boss_ids=boss_ids,
                    consumables=(),
                )
            )
        return tuple(out)

    def band_realm(self, domain_id: str, boss_ids: tuple[str, ...]) -> str:
        """The realm id a non-ladder domain's bands are labelled with.

        A `LootTier` declares exactly one realm and the loot validator rejects an
        empty one, so a world domain has to carry a label it does not own. The
        **lowest** realm any of the domain's authored drops belong to is chosen
        rather than the highest, because the label is a drop-context *fallback*
        and a wrong-high fallback hands out loot scaled above its authored
        magnitude. It is never actually consulted for a world domain: every drop
        on a generated boss table is an entry of a per-realm pool, and a pool's
        own realm overrides the band (`LootResolver` takes the innermost table's
        realm). So this is a derived, conservative, and pinned-by-the-validator
        default, not a claim about where the domain sits on the ladder.

        Empty when nothing the domain's bosses drop names a canonical realm, which
        is a content gap the caller reports rather than a label it invents.
        """
        found = {
            self.item_field(item, "realm")
            for boss_id in boss_ids
            for item in self.boss_drops(boss_id)
        }
        canonical = [realm_id for realm_id in self.ladder if realm_id in found]
        return canonical[0] if canonical else ""

    def boss_drops(self, boss_id: str) -> tuple[str, ...]:
        """Every item `boss_id` can hand out: its legacy list and its tables.

        Read together for the same reason the seeder reads them together: a
        migrated boss has an empty legacy array and a populated table, so reading
        either one alone answers "nothing" for half the corpus.
        """
        items = set(self.boss_loot(boss_id))
        authored = self._authored_drops().get(boss_id, set())
        items |= authored
        return tuple(sorted(items))

    def bound_table_ids(self, boss_id: str) -> tuple[str, ...]:
        """Every table an authored encounter band binds `boss_id` to.

        A boss does not always own a table named after it. Two of the body
        trials' elemental bosses carry a `loot_route_*` table carried over from a
        folded encounter, so a re-run that only looked for `loot_<boss_id>` found
        nothing for them and reported them as bosses with no drop to migrate.
        """
        out: list[str] = []
        for encounter in self.encounters.values():
            for tier in encounter.tiers:
                table_id = self.table_for(encounter, tier, boss_id)
                if table_id and table_id not in out:
                    out.append(table_id)
        return tuple(out)

    def declared_drops(self, boss_id: str) -> tuple[str, ...]:
        """Every item `boss_id` **declares** it can hand out, bound or not.

        [method boss_drops] answers *reachable* drops: it counts a table only once
        an encounter binds it. Trial membership cannot be gated on that, because the
        binding is precisely what the seeder has yet to write — so a boss whose only
        table nothing binds yet reads as drop-less, is filtered out of its own
        trial, and so is never given the binding that would make it reachable. The
        filter keeps its own output out of its input.

        `elemental_transcendent_guardian` is that shape: a `BossDef` its domain
        declares, a full authored table holding the five items that declare
        `boss:elemental_transcendent_guardian`, and no binding anywhere. Read as
        reachable it has nothing, so the world trial for its domain left it out,
        so the seeder never bound it, so it stayed unreadable.

        So the question a trial asks is "has this boss authored drop content?",
        which is a property of a file on disk and not of an encounter. The table
        named after the boss is that file; reading it by name is naming, not
        authorship, and it is the same rule [method seed._owns_table] already
        applies when it decides whether `--force` may rewrite a table.
        """
        items = set(self.boss_drops(boss_id))
        own = design.table_id(boss_id)
        if own in self.loot_tables:
            items |= self.reachable(own)
        return tuple(sorted(items))

    # --- authored encounters

    def reachable(self, table_id: str, depth: int = 0) -> set[str]:
        """Every item `table_id` can produce, nested tables included.

        Bounded by [constant MAX_TABLE_NESTING] so a cyclic table terminates
        instead of recursing past the resolver's own guard.
        """
        if depth > MAX_TABLE_NESTING:
            return set()
        table = self.loot_tables.get(table_id)
        if table is None:
            return set()
        found = set(table.get("entries", ()))
        for nested in table.get("nested", ()):
            found |= self.reachable(nested, depth + 1)
        return found

    def _authored_drops(self) -> dict[str, set[str]]:
        """boss id -> every item an authored loot table bound to it can produce.

        Cached because [method boss_drops] reads it once per boss and the world
        trial walk asks for every boss in the corpus.
        """
        if self._authored_drops_cache is None:
            out: dict[str, set[str]] = {}
            for encounter in self.encounters.values():
                for tier in encounter.tiers:
                    for boss_id in encounter.boss_ids:
                        table_id = self.table_for(encounter, tier, boss_id)
                        if table_id:
                            out.setdefault(boss_id, set()).update(self.reachable(table_id))
            self._authored_drops_cache = out
        return self._authored_drops_cache

    def _encounters(self) -> dict[str, Encounter]:
        out: dict[str, Encounter] = {}
        if not ENCOUNTER_DIR.is_dir():
            return out
        for path in sorted(ENCOUNTER_DIR.glob("*.tres")):
            text = path.read_text(encoding="utf-8")
            out[scalar(text, "id")] = Encounter(
                path=path,
                encounter_id=scalar(text, "id"),
                domain_id=scalar(text, "domain_id"),
                boss_ids=string_array(text, "boss_ids"),
                tiers=self._tiers(text),
            )
        return out

    @staticmethod
    def _tiers(text: str) -> tuple[dict, ...]:
        """Every `LootTier` sub-resource in one encounter file.

        Read from the `sub_resource` blocks rather than from the `tiers` array,
        because that array only holds `SubResource` references: the bands are
        declared above the `[resource]` block, and a parser that looked inside the
        array would find no bands at all.
        """
        return tuple(
            {
                "tier": scalar(chunk, "tier"),
                "realm": scalar(chunk, "realm"),
                "rarity": scalar(chunk, "rarity"),
                "vitality": scalar(chunk, "vitality"),
                "bindings": bindings(chunk, "boss_tables"),
            }
            for chunk in sub_resources(text)
            if "boss_tables" in chunk
        )

    def hosted_bosses(self) -> set[str]:
        """Bosses an authored encounter can spawn through `LootApi.enter_domain`."""
        return {boss for encounter in self.encounters.values() for boss in encounter.boss_ids}

    def catalysts_for(self, boss_id: str) -> tuple[str, ...]:
        """Every reagent id any trial requires `boss_id` to guarantee.

        Keyed on the boss rather than on one trial, because a boss does not belong
        to the trial that needs it: the qi ladder puts each realm's guardian in one
        of ten grouped `qi_*_domain`s that no realm seed names, so a guarantee
        derived from the hosting trial alone would be empty and the reagent that
        gates the whole ladder would be left to a roll. A reagent two trials share
        is listed once.
        """
        found: set[str] = set()
        for trial in self.all_trials:
            found.update(trial.catalysts.get(boss_id, ()))
        return tuple(sorted(found))

    def encounter_hosting(self, boss_id: str) -> Encounter | None:
        """The encounter that can spawn `boss_id`, or None.

        Not always the trial that needs it. A mind realm's qi-herb reagent drops
        from a boss living in the *qi* ladder's trial domain, so the catalyst
        guarantee has to be checked where the boss actually is or the walk would
        demand a table the runtime will never consult.
        """
        for encounter in self.encounters.values():
            if boss_id in encounter.boss_ids:
                return encounter
        return None

    def encounter_for_domain(self, domain_id: str) -> Encounter | None:
        """The encounter that hosts `domain_id`, or None.

        One domain may have at most one encounter: the loot validator rejects a
        second, so the first authored match is the whole answer.
        """
        for encounter in self.encounters.values():
            if encounter.domain_id == domain_id:
                return encounter
        return None

    def table_for(self, encounter: Encounter, tier: dict, boss_id: str) -> str:
        """The table `tier` binds `boss_id` to, or "" when it binds none."""
        for binding in tier["bindings"]:
            if unquote(str(binding.get("boss_id", ""))) == boss_id:
                return unquote(str(binding.get("table_id", "")))
        return ""

    def require(self) -> Graph:
        """The graph, or a loud failure naming the missing content.

        A silently empty graph would make every downstream assertion vacuously
        true, which is the failure mode this chain exists to prevent. Only the
        ladder collection is required: an empty `world_trials` is the *success*
        state — every world domain already carries an encounter — so requiring it
        to be non-empty would make the command fail the moment it had done its
        job. A missing world domain is reported by `acquisition validate`, which
        checks the content rather than the to-do list.
        """
        if not self.trials:
            raise ToolError(
                "no realm seed on any of the "
                f"{len(LADDER_PATHS)} ladders resolved to a domain; "
                "the generation contract wrote them, so the content is missing"
            )
        return self

    def relative(self, path: Path) -> str:
        return path.relative_to(REPO_ROOT).as_posix()
