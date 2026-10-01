"""Chaos World workflow tools. Entrypoint: `uv run python -m tools <task>`."""

__all__ = ["main"]


def main(argv: list[str] | None = None) -> int:
    from .__main__ import main as _main

    return _main(argv)
