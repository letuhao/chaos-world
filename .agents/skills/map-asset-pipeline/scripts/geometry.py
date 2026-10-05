"""Shared pixel measurements; loops are bounded by image sizes or path ancestors."""

from pathlib import Path

from PIL import Image

CELL_PX = 128
SUB_PX = 32
ALPHA_THRESHOLD = 128


def find_repo_root(source: str | Path) -> Path:
    for parent in Path(source).resolve().parents:
        if (parent / "game/project.godot").is_file() or (parent / "pyproject.toml").is_file():
            return parent
    raise ValueError(f"no repository marker above {source}")


def read_alpha(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return image.convert("RGBA").getchannel("A")


def art_bbox(alpha: Image.Image) -> tuple[int, int, int, int] | None:
    # Fit and measurement must agree on alpha; faint fringe must not move the measured window.
    return alpha.point(lambda value: 255 if value >= ALPHA_THRESHOLD else 0).getbbox()


def contact_run(path: Path, band: int = 16) -> tuple[int, int] | None:
    """Widest solid run in the art's bottom band, in half-open canvas coordinates."""
    if type(band) is not int or band < 1:
        raise ValueError("contact band must be a positive integer")
    alpha = read_alpha(path)
    bbox = art_bbox(alpha)
    if bbox is None:
        return None
    left, top, right, bottom = bbox
    pixels = alpha.load()
    best = None
    best_width = 0
    for y in range(max(top, bottom - band), bottom):
        start = left
        for x in range(left, right + 1):
            if x < right and pixels[x, y] >= ALPHA_THRESHOLD:
                continue
            if x - start > best_width:
                best, best_width = (start, x), x - start
            start = x + 1
    return best
