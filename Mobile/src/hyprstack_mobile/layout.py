"""Logical-pixel layout policy, independent of compositor scale and GTK."""
from dataclasses import dataclass

TEST_SIZES = ('360x800', '540x1200', '393x873', '412x915', '320x640', '800x360')

@dataclass(frozen=True)
class Layout:
    mode: str
    margin: int
    columns: int
    card_columns: int
    short: bool


def choose(width, height, font_scale=1.0):
    scale = max(1.0, font_scale)
    margin = 8 if width < 380 or height < 480 else 16 if width >= 600 else 12
    available = max(1, width - 2 * margin)
    columns = max(1, min(8, int((available + 8) // (80 * scale + 8))))
    cards = max(1, min(4, int((available + 8) // (160 * scale + 8))))
    mode = 'compact' if width < 380 else 'standard' if width < 480 else 'expanded' if width < 720 else 'tablet'
    return Layout(mode, margin, columns, cards, height < 480)
