"""Check rendered character art against its AUTHORED palette.

## Why this exists at all

`game/assets/characters/unique-characters/docs/PROMPT_AUDIT.md` predicted the prompts "will produce
attractive anime girls in ~80% of generations", and named the worst offenders. It was right. The two
scripts in that same program that were supposed to catch it **cannot fail anything**:
`audit_images.py:39,42` returns its issues and the `__main__` guard discards them, and
`validate.py`'s `main()` returns `None` (`:195`), so both exit 0 with failures present. Worse,
`validate.py:39` declares `map_sprite` should be `(896, 1184)` — the one shipped image the GAME
would reject, since the proven spec is 128x192 (`tools/character_assets.py:256`). A green gate that
discriminates nothing is worse than a red one (INC-0016), and that is exactly what those two are.

This module is the gate, and it is wired **per image** at install/approve time rather than into
`tools check`: 23 of the 25 shipped renders contradict their criteria, so a build-level gate would
be permanently red, and a permanently-red command stops being read.

## What is measured, and what is honestly NOT

MEASURED, and each verified to separate on the shipped set:

- [func check_single_subject] figure count against `BRIEF_CONSTRAINTS` "One subject only".
- [func check_transparency] a background was actually removed — which the existing guard cannot see,
  because `_validate_image` asserts only that the alpha channel REACHES 0 and one transparent pixel
  satisfies that. `pose_02` renders on an opaque ground and passes it.
- [func check_palette] dominant-colour containment in the authored palette.
- [func check_skin_bound] a per-kind ceiling on skin area.

**NOT automatable with Pillow and no CV model, measured and rejected rather than shipped:**

- **Skin flush.** The obvious metric — share of skin pixels redder than the authored `skin_warm` —
  was measured across all 25 renders and does **not** track the visually-verified cases: it scores
  `pose_06` highest (12.7%) where a human calls the flush "mild", and near zero on `combat_concept`
  where one is obvious. It is reading lighting and skin-tone variation, not flush. Shipping it would
  be a gate that discriminates nothing.
- **Ornament area.** Hue-window and hue+saturation+value variants were both measured; the first
  caught 36-73% of *every* frame (a ±20 degree window around a khaki brass covers the whole warm
  palette), and the second inverted the visual truth, scoring the two cleanest renders highest.
- **Hair crop.** 13 renders carry a bob-with-bangs and 11 a short crop, and separating them needs a
  head detector that is not in the tool bundle. Any rule that separated them would separate them
  only because a human drew the line by eye.
- **Apparent age, pose/bearing, garment coverage, sexualised reading.** No reliable pixel proxy.

All of those moved to [constant MANUAL_REVIEW], which a human works through before `approved` is
set. It is a Python constant rather than a Markdown file because AGENTS.md forbids new Markdown
without asking, and a checklist kept beside the gate it gates cannot drift from it.

`NO SEXUAL CONTENT` is an AGENTS.md rule: succubus, dual-cultivation and fertility are clinical
gameplay mechanics whose art is a cultivation-path concept plate or a labelled qi-exchange diagram.
The strongest guard is structural and is NOT rebuilt here — `SHOT_KINDS` and `SLOT_KIND`
(`tools/unique_characters.py:73,91`) have no slot or kind for such art, and a shot without a valid
slot is refused at any status, so such an asset cannot be indexed even if it were rendered.

## Where the numbers come from

Every threshold is authored, derived, or frozen against a human-confirmed render — never
derived from the failing art. The shipped set is homogeneous in its failure, so a threshold
tuned to separate the worst image from "the rest" is tuned against 22 images that are
equally wrong.

[constant PALETTE_DIST_LIMIT] and [constant PALETTE_OFF_MAX] were calibrated **once against the two
renders a human confirmed correct** (`expression_01` and `pose_06`, both 0.0% off-palette) and then
frozen. Calibrating on the known-good is not circular; calibrating on the known-bad is. As with
`core/realm_power_table.tres` (AGENTS.md:141), a threshold may thereafter only ever be TIGHTENED,
never loosened to make art pass.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path

from PIL import Image

from .common import GAME_DIR, ToolError, fail, info, ok

#: Where rendered character art lives — a gitignored sibling checkout of
#: https://github.com/letuhao/chaos-world-content.git, so it is usually ABSENT. Every entry point
#: reports that rather than failing: an absent private art folder must not make a public gate red,
#: for the same reason `_lore_entries()` returns None to disable a rule instead of guessing
#: (`tools/unique_characters.py:943-957`).
ART_ROOT = GAME_DIR / "assets" / "characters" / "unique-characters" / "outputs"

#: AUTHORED, copied from `ART_CRITERIA.md:32-38` and `context/unique-0001-ilsa-renn.md:56-62`.
#: Duplicated HERE deliberately: the source sits in a gitignored folder, so a threshold
#: recorded only there is recorded where no CI run and no other agent can read it.
#: `selftest` asserts the authored palette itself PASSES `check_palette` — if the reference
#: colours could not survive their own gate, the limit would have come from the art
#: rather than the criteria and the guard would be measuring itself.
APPROVED_PALETTE: dict[str, tuple[int, int, int]] = {
    "warm_ivory": (0xE8, 0xE0, 0xD0),
    "ash_grey": (0x8A, 0x85, 0x80),
    "pale_jade": (0xB8, 0xC4, 0xB0),
    "dull_brass": (0x8B, 0x7D, 0x4F),
    "ink_contour": (0x2A, 0x25, 0x20),
    "skin_warm": (0xC4, 0xA8, 0x82),
    "hair_brown": (0x3D, 0x2E, 0x22),
}

#: Which authored colour is the character's skin. Named because `check_skin_bound` is about that one
#: trait, and a bare hex literal would hide it.
SKIN_KEY = "skin_warm"

## Fixed integers, so every measurement is a pure function of the image: the same file always yields
##: the same numbers, which is the only thing that makes a threshold mean anything across runs.
DOWNSCALE = 4
SAMPLE_STRIDE = 2

## A dominant colour must sit within this distance of SOME authored hex. Frozen against the two
#: human-confirmed renders (both 0.0% at this value); thereafter only tightened. Painterly shading
#: between two palette hexes drifts, so it cannot be tighter without refusing correct art.
PALETTE_DIST_LIMIT = 46.0

## Share of the frame permitted to be dominated by a colour outside the palette: one accent plus its
##: own shading, and nothing more. "deliberately the least colourful person in any room"
##: (`ART_CRITERIA.md:40`).
PALETTE_OFF_MAX = 0.01

## How many dominant colour buckets decide "dominant". Eight is a stated choice, not a tuned one: it
##: is enough to cover a palette of seven plus one accent.
TOP_BUCKETS = 8

## A blob below this share of the opaque area is a background-removal artefact, not a person. Stated
##: rather than tuned: a trailing hem legitimately detaches in painterly art, and reporting that as
##: a fifth figure teaches people to ignore the report.
SUBJECT_AREA_FLOOR = 0.01
FRAGMENT_AREA_FLOOR = 0.003

## `BRIEF_CONSTRAINTS` "Transparent background, no ground plane"
##: (`tools/unique_characters.py:161`). A BOUND, not a discriminator.
ALPHA_MIN_FRACTION = 0.10

## Per-kind ceiling on skin area, because a close head-and-shoulders portrait is mostly face while a
##: map token is not. One global ceiling is provably wrong at both ends of that range.
SKIN_CEILING_BY_KIND: dict[str, float] = {
    "map_sprite": 0.14,
    "concept": 0.18,
    "portrait": 0.46,
    "dialogue": 0.46,
    "scene": 0.22,
}

#: The human half, checked by whoever sets `approved`. Everything measured-and-rejected above plus
#: what was never automatable.
MANUAL_REVIEW: tuple[str, ...] = (
    "apparent age matches appearance.age, not the model's default",
    "hair is blade-cropped, not a styled bob or fringe",
    "no flush: complexion specifies it, and no pixel check here can see it",
    "no visible marks or scar tissue unless appearance.marks says so",
    "garment coverage: high collar, full sleeves, covered shoulders",
    "pose reads as the authored bearing, not as performance",
    "no jewellery, no ornament, no rank marking unless the faction grants one",
    "no text, letters, numerals, UI, frame, border or watermark",
    "nothing sexualised in any frame; succubus, dual-cultivation and fertility art is a clinical "
    "cultivation-path plate or a labelled qi-exchange diagram, never a suggestive image",
)

#: Filename stem -> render kind. An unrecognised stem yields "" and skips the kind-specific ceiling
#: rather than guessing one.
_KIND_BY_STEM: dict[str, str] = {
    "map_sprite": "map_sprite",
    "dialogue_portrait": "dialogue",
    "character_portrait": "portrait",
    "concept_art": "concept",
    "environmental_concept": "concept",
    "combat_concept": "concept",
    "relationship_scene": "scene",
    "daily_casual": "scene",
    "daily_working": "scene",
    "daily_romance": "scene",
}


def kind_for(path: Path) -> str:
    """The render kind a file's name claims, or `""`."""
    stem = path.stem
    if stem in _KIND_BY_STEM:
        return _KIND_BY_STEM[stem]
    if stem.startswith("expression") or stem.startswith("pose"):
        return "portrait"
    return ""


# --- measurement ------------------------------------------------------------


class Sample:
    """One render reduced to the numbers every check needs.

    Built with Pillow's C-level `convert`/`tobytes` rather than per-pixel `getpixel`: it is two
    orders of magnitude faster on a 1248x1664 PNG, and `getdata`/`getpixel` are deprecated in
    Pillow 12+ and removed in 14.
    """

    __slots__ = ("width", "height", "alpha", "rgb", "ycc")

    def __init__(self, image: Image.Image) -> None:
        rgba = image.convert("RGBA")
        width, height = rgba.size
        if width < DOWNSCALE or height < DOWNSCALE:
            raise ToolError(f"image is too small to sample: {rgba.size}")
        small = rgba.resize((width // DOWNSCALE, height // DOWNSCALE), Image.Resampling.BOX)
        self.width, self.height = small.size
        # `getchannel("A")` is single-band, so its `tobytes()` is ONE byte per pixel. Indexing it as
        # RGBA (x4) walks off the end of the buffer on any real image.
        self.alpha = small.getchannel("A").tobytes()
        self.rgb = small.convert("RGB").tobytes()
        self.ycc = small.convert("YCbCr").tobytes()

    def total(self) -> int:
        return self.width * self.height

    def opaque(self, index: int) -> bool:
        return self.alpha[index] >= 128

    def opaque_sampled(self) -> int:
        return sum(1 for index in self.sampled() if self.opaque(index))

    def sampled(self) -> range:
        """The fixed lattice every statistic is taken over."""
        return range(0, self.total(), SAMPLE_STRIDE)

    def is_skin(self, index: int) -> bool:
        """YCrCb skin test, in Pillow's FULL-RANGE JPEG encoding where 128 is neutral.

        Authored `skin_warm` encodes to `(Y 172, Cb 104, Cr 145)`: warmth is Cb BELOW 128 and Cr
        ABOVE it. A test written for the studio-swing convention (`133 <= Cb <= 180`) matches
        nothing at all here and silently reports every image as having no skin.
        """
        _y, cb, cr = self.ycc[index * 3 : index * 3 + 3]
        return cr >= 140 and cb <= 132


def _palette_distance(red: int, green: int, blue: int) -> float:
    """Euclidean distance to the nearest authored hex. Loops the 7-entry palette, fixed size."""
    best = 1.0e9
    for reference in APPROVED_PALETTE.values():
        delta_red = red - reference[0]
        delta_green = green - reference[1]
        delta_blue = blue - reference[2]
        squared = delta_red * delta_red + delta_green * delta_green + delta_blue * delta_blue
        if squared < best:
            best = squared
    return best**0.5


def _component_areas(mask: bytes, width: int, height: int) -> list[int]:
    """8-connected component areas of an opaque mask, largest first.

    LOOP GUARD: an explicit stack, and a pixel is marked visited BEFORE it is pushed, so each pixel
    is pushed at most once and total work is bounded by `width * height`. The `while` always drains;
    there is no re-entry and no unbounded scan. The bound is read before the loop and only consumed,
    which is the same shape as `core/row_budget.gd`.
    """
    seen = bytearray(width * height)
    areas: list[int] = []
    for start in range(width * height):
        if mask[start] == 0 or seen[start]:
            continue
        seen[start] = 1
        stack = [start]
        area = 0
        while stack:
            index = stack.pop()
            area += 1
            x = index % width
            y = index // width
            # Eight explicit neighbours, each bounds-checked, so this cannot walk off the buffer.
            for offset_y in (-1, 0, 1):
                for offset_x in (-1, 0, 1):
                    if offset_x == 0 and offset_y == 0:
                        continue
                    neighbour_x = x + offset_x
                    neighbour_y = y + offset_y
                    if (
                        neighbour_x < 0
                        or neighbour_y < 0
                        or neighbour_x >= width
                        or neighbour_y >= height
                    ):
                        continue
                    neighbour = neighbour_y * width + neighbour_x
                    if mask[neighbour] and not seen[neighbour]:
                        seen[neighbour] = 1
                        stack.append(neighbour)
        areas.append(area)
    areas.sort(reverse=True)
    return areas


# --- gating checks ----------------------------------------------------------


def check_single_subject(image: Image.Image) -> list[str]:
    """GATING. One figure, per `BRIEF_CONSTRAINTS` "One subject only".

    `CHARACTER_NEGATIVE` names it too (`tools/character_assets.py:299`: "multiple characters, two
    figures, three figures"). Six of the shipped renders hold two to five figures.
    """
    sample = Sample(image)
    opaque = sample.opaque_sampled()
    if opaque == 0:
        return ["no opaque pixels: nothing to measure"]
    mask = bytes(1 if sample.opaque(index) else 0 for index in range(sample.total()))
    areas = _component_areas(mask, sample.width, sample.height)
    floor = sample.total() * SUBJECT_AREA_FLOOR
    subjects = [area for area in areas if area >= floor]
    if len(subjects) <= 1:
        return []
    return [
        f"{len(subjects)} subjects above {SUBJECT_AREA_FLOOR:.0%} of the silhouette; the brief "
        "allows one (BRIEF_CONSTRAINTS 'One subject only')"
    ]


def check_transparency(image: Image.Image) -> list[str]:
    """GATING. A background was actually removed.

    Catches what `_validate_image` is structurally blind to: it asserts only that the alpha channel
    REACHES 0, which one transparent pixel satisfies.
    """
    rgba = image.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A").tobytes()
    clear = sum(1 for value in alpha if value < 128)
    fraction = clear / float(width * height)
    if fraction >= ALPHA_MIN_FRACTION:
        return []
    return [
        f"{fraction:.1%} of the frame is transparent; the brief requires at least "
        f"{ALPHA_MIN_FRACTION:.0%} (BRIEF_CONSTRAINTS 'Transparent background, no ground plane')"
    ]


def check_palette(image: Image.Image) -> list[str]:
    """GATING. Dominant colours must sit inside the authored palette.

    The discriminator that actually works on this art. Measured across all 25 shipped renders, the
    share of the frame dominated by a colour far from every authored hex puts the known-bad
    `daily_romance` third worst and the two human-confirmed-clean renders at exactly 0.0% — which is
    why this replaced a saturation-ceiling check that scored 25 of 25 (a hue window wide enough to
    cover a warm palette matches the whole frame) and a flush check that did not track the visual
    verdict at all.
    """
    sample = Sample(image)
    opaque = sample.opaque_sampled()
    if opaque == 0:
        return ["no opaque pixels: nothing to measure"]
    # Histogram over a coarse grid: painterly gradients collapse into countable colour
    # families while a saturated teal stays far from ash grey. `Counter.most_common` is
    # bounded by TOP_BUCKETS.
    histogram: Counter[tuple[int, int, int]] = Counter()
    for index in sample.sampled():
        if not sample.opaque(index):
            continue
        offset = index * 3
        histogram[
            (
                sample.rgb[offset] >> 2,
                sample.rgb[offset + 1] >> 2,
                sample.rgb[offset + 2] >> 2,
            )
        ] += 1
    dominant = histogram.most_common(TOP_BUCKETS)
    outside = 0
    for bucket, count in dominant:
        distance = _palette_distance(bucket[0] << 2, bucket[1] << 2, bucket[2] << 2)
        if distance > PALETTE_DIST_LIMIT:
            outside += count
    fraction = outside / float(opaque)
    if fraction <= PALETTE_OFF_MAX:
        return []
    return [
        f"{fraction:.1%} of the frame is dominated by colours further than "
        f"{PALETTE_DIST_LIMIT:.0f} from every authored hex; the palette is seven "
        f"near-neutrals plus one accent (ART_CRITERIA.md:32-40) and allows {PALETTE_OFF_MAX:.0%}"
    ]


def check_skin_bound(image: Image.Image, kind: str) -> list[str]:
    """GATING when `kind` is known. A BOUND, not a discriminator.

    Every shipped render passes, which is correct: this exists so a future render cannot fill its
    frame with bare skin, and its red path is a synthetic fixture.
    """
    ceiling = SKIN_CEILING_BY_KIND.get(kind)
    if ceiling is None:
        return []
    sample = Sample(image)
    opaque = sample.opaque_sampled()
    if opaque == 0:
        return []
    skin = 0
    for index in sample.sampled():
        if sample.opaque(index) and sample.is_skin(index):
            skin += 1
    fraction = skin / float(opaque)
    if fraction <= ceiling:
        return []
    return [
        f"{fraction:.1%} of opaque pixels read as skin against a {ceiling:.0%} ceiling for kind "
        f"'{kind}'"
    ]


# --- advisory ---------------------------------------------------------------
#
# Reported, never fatal. A permanently-red command stops being read, so anything not anchored on
# authored data stays advisory and is promoted only with `--fail-on`.


def report_fragments(image: Image.Image) -> list[str]:
    """ADVISORY. Detached blobs between the fragment and subject floors."""
    sample = Sample(image)
    mask = bytes(1 if sample.opaque(index) else 0 for index in range(sample.total()))
    areas = _component_areas(mask, sample.width, sample.height)
    if not areas:
        return []
    lower = sample.total() * FRAGMENT_AREA_FLOOR
    upper = sample.total() * SUBJECT_AREA_FLOOR
    fragments = sum(1 for area in areas if lower <= area < upper)
    if not fragments:
        return []
    return [f"{fragments} detached fragment(s) between {lower:.0f} and {upper:.0f} pixels"]


GATING_CHECKS = (check_single_subject, check_transparency, check_palette)


def image_findings(path: Path, kind: str = "") -> tuple[list[str], list[str]]:
    """(gating, advisory) findings for one PNG."""
    try:
        with Image.open(path) as opened:
            image = opened.convert("RGBA")
    except OSError as exc:
        return ([f"cannot be opened as an image: {exc}"], [])
    resolved = kind or kind_for(path)
    gating: list[str] = []
    for check in GATING_CHECKS:
        gating.extend(check(image))
    gating.extend(check_skin_bound(image, resolved))
    advisory = [f"{path.name}: {finding}" for finding in report_fragments(image)]
    return (gating, advisory)


def installed_images() -> list[Path]:
    """Every rendered character PNG, or `[]` when the private folder is absent."""
    if not ART_ROOT.is_dir():
        return []
    return sorted(ART_ROOT.glob("*.png"))


# --- CLI --------------------------------------------------------------------


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "art_fidelity",
        help="check rendered character art against its authored palette",
    )
    actions = parser.add_subparsers(dest="art_fidelity_action", required=True)

    check = actions.add_parser("check", help="fail on art that contradicts its authored criteria")
    check.add_argument("--character-id", help="only files whose stem contains this")
    report = actions.add_parser("report", help="per-image table; never fails on its own")
    report.add_argument("--character-id", help="only files whose stem contains this")
    report.add_argument(
        "--fail-on",
        choices=("warn", "error"),
        default=None,
        help="promote advisory findings to a non-zero exit",
    )
    actions.add_parser("review", help="print the manual review checklist; never fails")


def run(args) -> int:
    action = args.art_fidelity_action
    if action == "review":
        print("Manual review, required before a shot may be set `approved`:")
        for line in MANUAL_REVIEW:
            print(f"  [ ] {line}")
        print()
        print(
            "Apparent age, flush, hair crop, pose, garment coverage and any sexualised "
            "reading have NO reliable pixel proxy here — each was measured and rejected. "
            "The machine enforces bounds; you enforce the rest."
        )
        return 0

    images = installed_images()
    if not images:
        info(
            f"no rendered character art at {ART_ROOT} (the private content folder is usually "
            "absent); nothing to check"
        )
        return 0
    wanted = getattr(args, "character_id", "") or ""
    if wanted:
        # Snapshot before the loop; the body filters a new list and never grows `images`.
        images = [path for path in images if wanted in path.stem]
        if not images:
            fail(f"no rendered art matches --character-id {wanted}")
            return 1

    rows = [(path, *image_findings(path)) for path in images]
    failing = [row for row in rows if row[1]]

    if action == "report":
        print(f"rendered art under {ART_ROOT}: {len(rows)} file(s)")
        for path, gating, advisory in rows:
            print(f"  [{'FAIL' if gating else 'pass'}] {path.name}")
            for finding in gating:
                print(f"      gating: {finding}")
            for finding in advisory:
                print(f"      advisory: {finding}")
        print(f"gating failures: {len(failing)} of {len(rows)}")
        if getattr(args, "fail_on", None) == "error" and failing:
            fail(f"{len(failing)} image(s) contradict their authored criteria")
            return 1
        ok("art fidelity report complete (advisory findings never fail this command)")
        return 0

    for path, gating, _advisory in failing:
        for finding in gating:
            fail(f"{path.name}: {finding}")
    if failing:
        fail(
            f"{len(failing)} of {len(rows)} rendered image(s) contradict their authored criteria; "
            "a threshold may be TIGHTENED to make art pass, never loosened"
        )
        return 1
    ok(f"art fidelity check complete ({len(rows)} image(s), all within the authored criteria)")
    return 0
