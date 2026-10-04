"""Subject templates, palettes and prompt assembly for the group sweeper.

Subjects are kept short and concrete on purpose. The model reads a long prose
brief as more words to weight, and the earlier hand-written batches (which ran
~90-120 characters) produced cleaner, more readable objects than these do not.

Two subjects per subcategory, alternated by position within the run, so a block
of groups from one subcategory does not read as a single repeated object.

Every subject is phrased so the object can be shown with no ground plane: either
"from DIRECTLY ABOVE" or "straight on" is appended by the caller, because the
Krea2 graph zeroes negative conditioning and "no shadow" is simply ignored.
"""

from __future__ import annotations

# cat/sub -> two concrete object descriptions.
SUBJECTS: dict[str, list[str]] = {
    "material/horn": [
        "one curled horn, a tapering spiral tusk segment with a hollow open end",
        "one straight horn shard, a narrow tapering spike with a banded grain",
    ],
    "material/pearl": [
        "one open oyster shell holding a single round pearl",
        "one whole pearl alone, a round bead with an iridescent sheen",
    ],
    "material/gut": [
        "one coiled length of dried gut, a looped sinew strand",
        "one cut strip of gut, flat with a wet sheen and a pale inner face",
    ],
    "material/amber": [
        "one lump of raw amber, an irregular nodule of translucent resin",
        "one shard of amber, an angular chip with one internal bubble",
    ],
    "material/slate": [
        "one flat shard of slate, a thin plate with layered cleavage edges",
        "one block of slate, a squat rectangle with a stratified surface",
    ],
    "material/moss": [
        "one dense tuft of dried moss, a compact cushion of fine strands",
        "one flat mat of moss, short growth clinging to a thin bark base",
    ],
    "material/bristle": [
        "one coarse bristle tuft, stiff hairs splayed and bound at one end",
        "one curled bristle, a long stiff hair looped into a loose spiral",
    ],
    "material/fiber": [
        "one hank of spun fiber, a loose skein of twisted thread",
        "one woven fiber band, a short strip of coarse plaited cord",
    ],
    "material/resin": [
        "one lump of raw resin, a teardrop of translucent gum",
        "one pooled resin disc, a flat cake of hardened gum",
    ],
    "material/filament": [
        "one wisp of filament, a fine thread curling with a faint sheen",
        "one bundle of filaments, a small sheaf tied at one end",
    ],
    "material/hide": [
        "one folded hide, a broad piece of tanned skin folded once",
        "one rolled hide, a thick cylinder of leather tied with one cord",
    ],
    "material/ingot": [
        "one metal ingot, a low trapezoid bar with a cast top",
        "two stacked ingots, trapezoid bars resting one on the other",
    ],
    "material/gemstone": [
        "one rough gemstone, an irregular crystal with one polished window",
        "one cut gemstone standing face up on its point",
    ],
    "material/bone": [
        "one bone fragment, a thick hollow shard with two broken ends",
        "one whole small bone, a curved tapering shaft with knuckled ends",
    ],
    "material/core": [
        "one beast core, a rough stone nodule with one glowing seam",
        "one split core, a stone husk cracked around a bright inner body",
    ],
    "material/fragment": [
        "one stone fragment, an angular shard with a flat conchoidal face",
        "one metal fragment, a short bent offcut with a bright torn edge",
    ],
    "material/scroll": [
        "one sheet of blank paper with a torn deckle edge",
        "one bundle of paper reeds, a tied sheaf of pale rolls",
    ],
    "material/tablet": [
        "one clay tablet, a flat slab with impressed wedge marks",
        "one stone tablet, a thick upright slab with a carved border",
    ],
    "material/bark": [
        "one strip of bark, a curled piece showing rough outer and pale inner",
        "one bark disc, a round cut section showing growth rings",
    ],
    "currency/writ": [
        "one folded writ of office, heavy paper closed with a wax seal",
        "one rolled writ scroll, a paper cylinder bound with a cord",
    ],
    "currency/coin": [
        "one round coin with a square hole and a worn raised rim",
        "a stack of three coins, flat discs slightly offset",
    ],
    "currency/bond": [
        "one debt bond, a notched strip of stiff paper with a wax seal",
        "one bound bond booklet, a small stiff cover closed with a cord",
    ],
    "currency/token": [
        "one round token, a flat disc with a square hole and stamped rim",
        "one chipped token, an irregular metal nugget worn smooth",
    ],
    "currency/seal": [
        "one official seal, a stone cylinder with a carved top face",
        "one wax seal stamp, a round matrix with a turned handle",
    ],
    "key/ledger": [
        "one closed ledger, a thick book with a plain board cover",
        "one ledger lying open, a heavy book spread flat",
    ],
    "key/key": [
        "one old iron key, a long shank with a round bow and two teeth",
        "one bone key, a short thick key with a carved loop bow",
    ],
    "key/seal": [
        "one official seal, a stone cylinder with a cord through its handle",
        "one wax seal stamp, a round matrix with a raised device",
    ],
    "key/talisman": [
        "one key token, a thick disc pierced by a square hole",
        "one key plaque, a small stone tablet with a bored hole",
    ],
    "key/sigil": [
        "one key sigil, a flat disc cut deeply into four quarters",
        "one key sigil ring, an open metal ring with a heavy top boss",
    ],
    "misc/charm": [
        "one knotted charm, a cord loop threaded with a carved bead",
        "one hanging charm, a pierced metal disc on a short ring",
    ],
    "misc/token": [
        "one smooth oval token, a polished stone disc with an incised ring",
        "one square token, a thick flat tile with chipped corners",
    ],
    "misc/curio": [
        "one curio on a plain stand: a bone claw, a clay bead, one coin",
        "one curio box, a shallow open case holding a small odd object",
    ],
    "misc/medal": [
        "one struck medal, a thick disc with a raised rim and worn relief",
        "one hanging medal, a flat disc on a short ring",
    ],
    "quest/bounty": [
        "one posted bounty sheet, a broad notice pinned at one corner",
        "one rolled bounty writ, a paper cylinder tied with a red cord",
    ],
    "quest/text": [
        "one sheet of quest text, ruled writing and a torn lower edge",
        "one folded quest letter, heavy paper sealed with a wax drop",
    ],
    "quest/relic": [
        "one quest relic, a small carved beast figure on a plain base",
        "one relic fragment, a broken ceramic shard showing painted scrollwork",
    ],
    "quest/instrument": [
        "one long-necked stringed instrument with a pear-shaped body",
        "one hand drum, a shallow round frame with a taut pale skin",
    ],
    "quest/sachet": [
        "one drawstring sachet, a small cloth bag gathered and tied",
        "one flat sachet pouch, a thin packet sealed on three edges",
    ],
    "consumable/manual": [
        "one bound manual standing closed, a plain board cover and spine band",
        "one bound manual standing open, covers spread on a blank page block",
    ],
    "consumable/talisman": [
        "one folded paper talisman, a narrow strip printed with dense strokes",
        "one hanging talisman tag on a short red cord",
    ],
    "consumable/food": [
        "one round flatbread loaf, thick with a blistered top",
        "one skewer of grilled meat, three plain cubes on a bare stick",
    ],
    "consumable/salve": [
        "one wide salve jar, a squat clay pot with a wedged cork",
        "one shallow salve tin, a round metal box with a pressed lid",
    ],
    "consumable/decree": [
        "one rolled decree scroll tied with a cord and a large wax seal",
        "one broad decree sheet with dense ruling and a torn lower edge",
    ],
    "consumable/syrup": [
        "one stoppered syrup vial, a narrow-necked bottle with dark residue",
        "one squat syrup jar, a round-bellied vessel with a waxed cap",
    ],
    "consumable/ferment": [
        "one ferment jar, a wide-mouthed clay vessel under a tied cloth",
        "one sealed ferment crock, a bulbous pot with a wax seal",
    ],
    "consumable/grease": [
        "one open grease pot, a shallow clay dish of smooth pale solid",
        "one stoppered grease jar, a ribbed glass jar with thick residue",
    ],
    "consumable/broth": [
        "one broth flask, a round-bellied glass vessel with a tied cork",
        "one lidded broth bowl, a deep clay bowl under a plain domed lid",
        "one stoppered broth bottle, tall and narrow with a wax seal",
        "one ceramic broth pot, a wide stoneware jar with a rope handle",
        "one double broth gourd, two joined bulbs with one small stopper",
        "one broth horn, a curved drinking vessel with a narrow spout",
        "one shallow broth dish, a wide low bowl with a rolled rim",
        "one broth tankard, a heavy lidded cup with one arched handle",
    ],
    "consumable/draught": [
        "one corked draught bottle, tall and straight-sided",
        "one round draught phial, a bulbous vial with a narrow stopper",
    ],
    "consumable/elixir": [
        "one slim elixir vial, a narrow tube with a rounded base",
        "one twin-necked elixir bottle, small and waisted with two necks",
    ],
    "consumable/tonic": [
        "one tonic flask, a broad flat bottle with a waxed neck",
        "one ceramic tonic jar, a rounded stoneware pot with a plain lid",
    ],
    "consumable/pill": [
        "one round pill, smooth with a faint seam and a matte coating",
        "one small pill jar, round glass with a cork and one pill beside it",
    ],
    "consumable/powder": [
        "one folded paper packet of powder, pinched shut at one corner",
        "one open powder dish, a shallow saucer holding a fine pale heap",
    ],
    "consumable/tincture": [
        "one tincture dropper, a slim tube with a bulb at one end",
        "one tincture bottle, square-shouldered glass with a stopper",
    ],
    "consumable/formula": [
        "one carved stone tablet with a deeply incised circular seal",
        "one bound formula folio, thin and upright with a plain clasp",
    ],
    "consumable/draft": [
        "one open codex lying flat, covers spread around a blank page block",
        "one closed folio upright on its fore edge, square spine",
    ],
    "consumable/treaty": [
        "one folded treaty sheet bound by cord and closed with a wax seal",
        "one treaty tablet, thin dark stone with an engraved border",
    ],
    "consumable/scroll": [
        "one wide scroll partly unrolled, a broad sheet from a roller",
        "one narrow scroll standing rolled, bound by a plain cord",
    ],
    "consumable/mantra": [
        "one narrow mantra strip rolled tight and tied with a cord",
        "one folded mantra leaf, a small square pierced by one hole",
    ],
    "consumable/rite": [
        "one shallow rite bowl on a short foot with an incised band",
        "one rite token, a flat plate shaped as one pair of upswept wings",
    ],
    "consumable/grimoire": [
        "one thick bound grimoire closed upright with a broad clasp",
        "one thick grimoire upright and open on a blank page block",
    ],
    "consumable/jade_slip": [
        "one flat stone slip with rounded corners and a carved channel",
        "one flat banded stone slip drilled with a row of small holes",
    ],
    "consumable/sigil": [
        "one carved sigil disc, a round stone split by a vertical cleft",
        "one carved sigil ring, an open circle with a spiral channel",
    ],
    "equipment/greaves": [
        "one pair of greaves, two symmetrical plates strapped at the calf",
        "one greave, a shaped shin plate with a plain knee cup",
    ],
    "equipment/bandolier": [
        "one bandolier strap, a wide sash of hide with small sewn pockets",
        "one bandolier belt, plain and studded with a hanging strap",
    ],
    "equipment/lens": [
        "one lens, a thick glass disc in a brass rim with a side mount",
        "one lens in a folding case, a disc seated in a hinged cover",
    ],
    "equipment/accessory": [
        "one pendant on a plain cord, a small shaped hanging charm",
        "one signet ring, a plain band with a flat oval face",
    ],
    "equipment/artifact": [
        "one artifact, a small carved figure on a plain stepped base",
        "one artifact disc, a flat ring of dark etched metal",
    ],
    "equipment/armor": [
        "one cuirass seen from the front, a shaped breastplate with straps",
        "one shoulder plate, a curved pauldron with a rolled lip",
    ],
    "equipment/weapon": [
        "one straight blade with a narrow crossguard and wrapped grip",
        "one broad axe head on a short bound haft",
    ],
    "equipment/orb": [
        "one glass orb in an open bronze cradle, clouded and faintly lit",
        "one polished stone sphere resting in a ring of dull iron",
    ],
}

# Twelve hue-spread palettes; exactly one is green, to stay under the
# art-direction ceiling of two jade icons per eight.
PALETTES: list[tuple[str, str]] = [
    ("charcoal, black and cold silver", "a very dark object"),
    ("deep indigo, violet and cold white", "a mid-dark object"),
    ("sienna, burnt orange and ochre", "a warm mid object"),
    ("onyx black, charcoal and thin white banding", "a very dark object"),
    ("copper, rust orange and dull tan", "a warm mid object"),
    ("slate blue, black and cold grey", "a very dark object"),
    ("antique gold, ivory and pale brass", "a warm mid object"),
    ("oxblood, deep crimson and bone white", "a very dark object"),
    ("chalk white, pale grey and cold silver", "a pale luminous object"),
    ("umber, oxblood and faded tan", "a mid-dark object"),
    ("pale rose white, ivory and faint silver", "a pale luminous object"),
    ("deep bottle green, black and cold jade", "a mid-dark object"),
]

VALUE_WORDS: dict[str, str] = {
    "a very dark object": (
        "The whole object sits in the dark half of the value range and only the "
        "raised edges catch a thin highlight."
    ),
    "a mid-dark object": (
        "The object stays below the light half of the value range; only the top "
        "edge and one facet catch a thin highlight."
    ),
    "a pale luminous object": (
        "The object is the brightest thing in frame, glowing softly from within."
    ),
    "a warm mid object": (
        "The object stays in the middle of the value range with one clear lit "
        "top plane and a darker underside."
    ),
}
