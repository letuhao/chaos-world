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
        "one plain horn, a tapering cone with a hollow open base",
        "a curved horn, a crescent tapering to a closed point",
        "one sliced horn segment, a short tube cut off square at both ends",
        "a horn with a band, a tapering cone bound near its base",
        "one horn cup, a short broad cone shaped like a small cup",
        "a paired horn set, two tapering cones lying crossed",
    ],
    "material/pearl": [
        "one pearl, a single round bead with a smooth reflective surface",
        "an opened pearl shell, a bivalve shell holding one round bead",
        "a pair of pearls on a cord, two round beads threaded together",
        "a pearl in a small dish, one round bead resting in a shallow cup",
        "one irregular pearl, a lumpy bead with a slightly uneven surface",
        "a strung row of pearls, five round beads on one taut cord",
    ],
    "material/gut": [
        "one gut strand, a single long flattened strip resting in a loose curve",
        "a gut loop, a length doubled back and tied at one point",
        "one wound gut, a strip wound into a flat spiral",
        "a gut strip folded, a long strip creased into a short stack",
        "one gut strand knotted, a strip tied in a single overhand knot",
        "a gut bundle, several short lengths gathered together",
    ],
    "material/amber": [
        "one amber lump, an irregular clear-gold blob with a rounded surface",
        "an amber bead, a smooth polished oval of clear material",
        "one amber in a rough matrix, a clear nodule still joined to dull stone",
        "an amber teardrop, a tapering clear drop with a rounded lower end",
        "a flat amber piece, a thin clear-gold plate with irregular edges",
        "one amber on a cord, a drilled clear bead threaded on a short loop",
    ],
    "material/slate": [
        "one slate shard, a thin flat fragment with a chipped edge",
        "a slate tile, a thin square plate with squared corners",
        "one slate billet, a small rectangular block thicker than a tile",
        "a slate plate with a bored hole, a thin square pierced at one corner",
        "a stack of slate slates, three thin plates laid one on another",
        "one slate standing on edge, a thin plate propped on its narrow side",
    ],
    "material/moss": [
        "one moss cushion, a rounded pad of dense growth",
        "a moss patch on bark, growth covering one flat slab of bark",
        "one moss tuft, a small upright clump with visible fine stalks",
        "moss on a stone, a low mat spreading over a rounded rock",
        "a moss-lined hollow, growth filling a shallow bowl-shaped hollow",
        "one moss strand, a single trailing sprig laid in a curve",
    ],
    "material/bristle": [
        "one bristle tuft, a short dense cluster of stiff hairs",
        "a bound bristle bunch, a tuft with its base tied",
        "one straight bristle, a single long stiff hair laid flat",
        "a fanned bristle spread, a tuft opened out into a fan",
        "a bristle pair, two stiff hairs crossed at one end",
        "a cut bristle bundle, a bunch with a trimmed even top edge",
    ],
    "material/fiber": [
        "one fiber tuft, a small loose bundle of fine strands",
        "a fiber bundle tied at one end, a handful gathered with a single tie",
        "one fiber strand, a single long thin strand laid flat",
        "a woven fiber strip, a narrow band of plaited strands",
        "a fiber wad, a loose rounded mass of matted strands",
        "one fiber coil, a single strand wound into a flat ring",
    ],
    "material/resin": [
        "one resin lump, an irregular translucent blob with a rounded top",
        "a resin nodule, a small stone-like bead of clear material",
        "one resin on a leaf, a blob resting on a broad leaf",
        "a resin shard, a hard angular fragment with flat broken faces",
        "one resin tear, a rounded drop hanging from a short stem of bark",
        "a resin pool, a flat wide puddle set into a piece of bark",
    ],
    "material/filament": [
        "one coiled filament, a single long thread wound into a loose spiral",
        "a filament bundle, several threads gathered and tied at the middle",
        "one filament spool, a thread wound around a small spindle",
        "a loose filament loop, one long thread resting in an open curve",
        "one filament on a card, a single thread stretched across a small card",
        "a filament tuft, a short brush-like end of fine threads",
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
        "one rough gemstone, an uncut crystal lump with flat facets",
        "one cut gemstone, a faceted stone set upright on its point",
        "a gemstone cluster, three small crystals joined at the base",
        "one polished cabochon, a smooth domed stone with no facets",
        "a gemstone in a wire setting, a stone held by a thin metal claw",
        "one tumbled gemstone, a rounded pebble-like stone with worn edges",
    ],
    "material/bone": [
        "one bone fragment, a thick hollow shard with two broken ends",
        "one whole small bone, a curved tapering shaft with knuckled ends",
    ],
    "material/core": [
        "one plain core, a short thick dowel of pale material with cut ends",
        "a core bundle, several lengths tied side by side at one end",
        "one carved core, a shaped block with one face worked smooth",
        "a stacked core, three cut lengths laid in a short pile",
        "one core standing upright, a thick billet resting on its end",
        "a core wrapped at the middle, a length bound with a single turn of cord",
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
        "one bark plate, a curved fragment of outer bark with a rough outer face",
        "a bark strip, a long narrow strip torn from a trunk",
        "one bark block, a thick squared-off chunk with bark on two faces",
        "a bark curl, a fragment peeled back into a shallow curve",
        "one bark slab, a wide flat piece with the inner face shaved pale",
        "a stacked bark bundle, several plates laid flat one on another",
    ],
    "currency/writ": [
        "one folded writ of office, heavy paper closed with a wax seal",
        "one rolled writ scroll, a paper cylinder bound with a cord",
    ],
    "currency/coin": [
        "one coin standing on edge, a thin disc propped upright",
        "a small stack of coins, three discs piled on one another",
        "one coin in a cloth pouch, a disc partly showing from a drawstring bag",
        "a strung coin, a disc threaded onto a short cord",
        "one coin in a wooden case, a disc fitted into a round slot",
        "a coin strung with two small discs, one large and two small on one cord",
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
        "one official seal, a square stone block with a carved handle on top",
        "a seal stamp, a short cylinder with a flat marked base",
        "one seal in a wooden box, a carved block fitted into a fitted case",
        "a hanging seal, a block threaded onto a short cord loop",
        "one seal with a cord and a cap, a block with a tied silk cover",
        "a seal resting on a stand, a carved block propped on a small rack",
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
        "one charm on a ring, a pierced token held in a plain metal hoop",
        "a knotted charm, a small tied bundle with a loop of cord",
        "one charm disc, a flat round token with a hole near the top",
        "a charm on a chain, a small pendant hanging from short links",
        "one charm plaque, a small shaped plate with a drilled hole",
        "a charm in a pouch, a drawstring bag holding one small object",
    ],
    "misc/token": [
        "one smooth oval token, a polished stone disc with an incised ring",
        "one square token, a thick flat tile with chipped corners",
    ],
    "misc/curio": [
        "one odd curio, a small unfamiliar trinket of mixed metal and shell",
        "one curio in a tiny glass dome, an object under a clear bell",
        "a curio on a plain stand, a strange object mounted on a short post",
        "one pocket curio, a small hinged case holding an odd keepsake",
        "a curio strung on a cord, a pierced object hanging from a loop",
        "one worn curio, an object rubbed smooth at the edges from handling",
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
        "one manual standing upright, a thick book resting on its fore edge",
        "one manual open flat, covers spread around a page block",
        "a manual with a thumb index, a closed book with tabs at one edge",
        "one manual rolled closed, a soft-bound volume tied with a cord",
        "a manual lying on its side, a thick closed book set flat and low",
        "one manual in a slipcase, a book slid partway out of a fitted sleeve",
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
        "a salve pot with a strap, a small pot with a leather carrying loop",
        "a salve block in a stone cup, a rounded lump sitting in a cup",
        "a salve jar on a saucer, a tall narrow pot beside its lid",
        "a salve horn, a curved container with a wide open mouth and a plug",
    ],
    "consumable/decree": [
        "one rolled decree scroll tied with a cord and a large wax seal",
        "one broad decree sheet, a wide rectangle of stiff paper with a torn edge",
        "a decree tablet standing upright, a thin slab of dark stone with a "
        "carved border and a cord hole",
        "a folded decree in an envelope, a wide packet of stiff paper with one "
        "string tie and a wax drop",
        "a hanging decree strip, a long narrow paper tag with a hole at the top "
        "and a cord through it",
        "a rolled decree bound as a set, three narrow paper rolls lashed together with one cord",
    ],
    "consumable/syrup": [
        "one stoppered syrup vial, a narrow-necked bottle with dark residue",
        "one squat syrup jar, a round-bellied vessel with a waxed cap",
        "a syrup flask with a long neck, a slim glass tube with a cork",
        "a syrup pot with a ladle, a wide jar with a small cup resting in it",
        "a syrup bottle in a wicker sleeve, a glass bottle wrapped in rushes",
        "a double syrup bottle, two small joined bulbs with one stopper",
    ],
    "consumable/ferment": [
        "one ferment jar, a wide-mouthed clay vessel under a tied cloth",
        "one sealed ferment crock, a bulbous pot with a wax seal",
        "a ferment keg on its side, a small barrel with two iron hoops",
        "a stoppered demijohn, a big-bellied glass vessel with a long neck",
        "a ferment in a gourd, a round bottle with a cork and a cord",
        "a lidded ferment pail, a tapered metal pail with a swing handle",
    ],
    "consumable/grease": [
        "one open grease pot, a shallow clay dish of smooth pale solid",
        "one stoppered grease jar, a ribbed glass jar with thick residue",
        "a grease cake on a leaf, a thick round puck resting on a broad leaf",
        "a grease pot with a wide lid, a squat jar with an overlapping cover",
        "a grease tin with a rim, a shallow metal dish with a rolled edge",
        "a grease block in a wooden box, a wrapped square packed in a crate",
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
        "one draught in a wide bowl, a shallow dish filled close to the rim",
        "a draught in a handled cup, a small mug with one side handle",
        "one draught in a stemmed glass, a shallow bowl on a short stem",
        "a draught in a lidded bowl, a dish with a sliding cover partway open",
        "one draught in a twin cup, two joined bowls sharing one base",
        "a draught in a pouring beaker, a tall straight-sided cup",
    ],
    "consumable/elixir": [
        "one slim elixir vial, a narrow tube with a rounded base",
        "one twin-necked elixir bottle, small and waisted with two necks",
    ],
    "consumable/tonic": [
        "one tonic bottle, a straight-sided glass bottle with a short cork",
        "one tonic jug, a small handled pitcher with a narrow lip",
        "a tonic in a gourd vessel, a round bottle with a corked neck",
        "one tonic flask, a flat oval bottle with a loop of cord at the neck",
        "a tonic jar with a spoon beside it, a pot with a small cup resting against it",
        "one tonic in a stoppered tube, a slim glass cylinder with a ground stopper",
    ],
    "consumable/pill": [
        "one round pill, smooth with a faint seam and a matte coating",
        "one small pill jar, round glass with a cork and one pill beside it",
    ],
    "consumable/powder": [
        "one powder tin, a shallow round metal box with a tight lid",
        "one open powder bowl, a small dish heaped with fine powder",
        "a powder in a paper twist, a small parcel folded at both ends",
        "one powder horn, a curved tapering container with a plugged tip",
        "a powder wrapped in a leaf, a measured parcel folded in a broad leaf",
        "one stoppered powder vial, a narrow bottle with powder packed at the base",
    ],
    "consumable/tincture": [
        "one tincture vial, a slim glass bottle with a narrow neck and cork",
        "one round tincture flask, a flat disc-shaped bottle with a short neck",
        "a tincture in a stoppered phial, a small bottle with a waxed seal",
        "one double-necked tincture bottle, two joined bulbs under one stopper",
        "a tincture ampoule, a plain sealed glass tube with rounded ends",
        "one tincture jar, a wide-mouthed pot with a tied cloth cover",
    ],
    "consumable/formula": [
        "one carved stone tablet with a deeply incised circular seal",
        "one bound formula folio, thin and upright with a plain clasp",
        "a formula written on a hanging slate tag, a narrow pierced stone strip",
        "a formula on a wax tablet, a thick round wax disc scored with one ring",
        "a rolled formula chart lashed with cord, a narrow paper cylinder",
        "a formula kept in a lacquer case, a small hinged box with one clasp",
    ],
    "consumable/draft": [
        "one open codex lying flat, covers spread around a blank page block",
        "one closed folio upright on its fore edge, square spine",
        "a draft open on a stand, a book propped upright on a small ledge",
        "a draft with loose leaves, a book with one page turned out flat",
        "a rolled draft tied open, a cylinder with one sheet hanging loose",
        "a slim pocket draft, a small book with a thumb notch and a thin spine",
    ],
    "consumable/treaty": [
        "one folded treaty sheet bound by cord and closed with a wax seal",
        "one treaty tablet, thin dark stone with an engraved border",
        "a treaty scroll in a tube, a rolled paper inside a plain cylinder",
        "two treaty sheets tied together, a pair of documents with one cord",
        "a treaty sheet weighted by a seal, a broad page with a stone on it",
        "a treaty hung as a banner, a long sheet from a thin wooden rod",
    ],
    "consumable/scroll": [
        "one rolled scroll standing upright, a paper cylinder tied with cord",
        "one partially unrolled scroll, a cylinder with a sheet hanging open",
        "a sealed scroll tube, a rolled paper inside a slim wooden case",
        "one flat folded scroll, a paper packet creased into quarters",
        "a scroll spread in a shallow spiral, a wide sheet coiled from the centre",
        "one scroll with a hanging tag, a roll with a small pierced slip tied on",
    ],
    "consumable/mantra": [
        "one mantra on a single leaf, a broad leaf carrying one marked band",
        "a mantra strip of paper, a long narrow strip loosely coiled",
        "one mantra cut into a bamboo strip, a flat slat with marks along it",
        "a mantra on a palm-sized card, a small card with a plain ruled frame",
        "one mantra wound on a spindle, a strip wound around a small stick",
        "a mantra strip threaded on a ring, a narrow band looped through a hoop",
    ],
    "consumable/rite": [
        "one rite card, a thick stiff card marked with a plain border",
        "a rite sheet folded twice, a large paper sheet creased into thirds",
        "one rite on a wooden tally, a flat notched stick",
        "a rite sheet weighted by a smooth stone, a marked page held down",
        "one rite bound as a booklet, several small sheets tied with one cord",
        "a rite posted on a board, a marked sheet pinned to a standing panel",
    ],
    "consumable/grimoire": [
        "one thick grimoire, a heavy closed book with a deep spine and metal corners",
        "one grimoire open on its spine, covers spread flat around a page block",
        "a chained grimoire, a closed book with a short chain wrapped around it",
        "one grimoire standing on its fore edge, a heavy square book upright",
        "a grimoire with a clasp, a closed book with one hinged metal catch",
        "one grimoire wrapped in a cloth half-slip, a bound book in a plain cover",
    ],
    "consumable/jade_slip": [
        "one jade slip, a narrow flat stone bar with squared ends",
        "a jade slip on a cord, a stone bar threaded through a drilled hole",
        "one carved jade slip, a thin stone plate carved on one face",
        "a jade slip in a sleeve, a bar inside a fitted slotted holder",
        "a stack of jade slips, three thin stone bars laid together",
        "one jade slip standing upright, a stone bar resting on its narrow end",
    ],
    "consumable/sigil": [
        "one sigil cut in a stone plaque, a small slab with a marked face",
        "a sigil branded on a metal tag, a flat tag with a marked surface",
        "one sigil scratched into a clay token, a small disc with a marked face",
        "a sigil drawn inside a plain ring, a marked circle inside an unbordered band",
        "one sigil pressed into wax, a soft round disc carrying a raised mark",
        "a sigil on a hanging bone charm, a marked plate drilled at the top",
    ],
    "equipment/greaves": [
        "one pair of greaves, two symmetrical plates strapped at the calf",
        "one greave, a shaped shin plate with a plain knee cup",
        "a greave with a high boot, a plated greave laced over a tall boot",
        "greaves laid side by side, two plates resting flat and parallel",
        "one greave strapped across, a plate with two crossing leather straps",
        "a greave with a feathered edge, a plate cut into a wing-like rim",
    ],
    "equipment/bandolier": [
        "one bandolier strap, a wide sash of hide with small sewn pockets",
        "one bandolier belt, plain and studded with a hanging strap",
        "a crossed bandolier, two straps crossing at the chest",
        "a bandolier with a single large pouch, one strap and one deep pocket",
        "a studded shoulder harness, one broad strap with rows of rivets",
        "a coiled bandolier, the strap wound into a flat spiral",
    ],
    "equipment/lens": [
        "one lens, a thick glass disc in a brass rim with a side mount",
        "one lens in a folding case, a disc seated in a hinged cover",
        "a lens on a swivel arm, a disc in a bracket that pivots at one side",
        "a stack of lenses, three discs of different sizes piled together",
        "a lens in a wooden frame, a round disc set in a plain square holder",
        "a handheld lens with a handle, a small disc on a short turned grip",
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
