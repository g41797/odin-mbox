"""
Generate ring_mbox.png: a ring of 4 pixel-art gold mailboxes with flying cards between them,
plus a broken/fallen mailbox outside the ring with a card pile beside it.
"""

import math
import random
from PIL import Image, ImageDraw, ImageEnhance

SRC = "gold_mbox.png"
OUT = "ring_mbox.png"

CANVAS = 512
MBOX_SIZE = 110          # each mailbox scaled to this size
RING_R = 160             # radius of the ring (center of mailbox to canvas center)
N = 4                    # number of mailboxes
CARD_W, CARD_H = 22, 30  # pixel-art card size

SUITS = ['diamond', 'heart', 'spade', 'club']

# ── colours ──────────────────────────────────────────────────────────────────
CARD_BODY   = (255, 252, 220, 255)   # cream
CARD_BORDER = (180, 160,  60, 255)   # gold border
RED_SUIT    = (200,  30,  30, 255)   # red suit pip
BLACK_SUIT  = ( 40,  40,  40, 255)   # dark suit pip
GLOW        = (255, 220,  80, 80)    # translucent gold glow


def _draw_suit(d: ImageDraw.Draw, mx: int, my: int, suit: str) -> None:
    """Draw a ~5×5 pixel-art suit glyph centred at (mx, my) on draw context d."""
    if suit == 'cross':
        color = (10, 10, 10, 255)   # near-black
        # vertical bar
        for dy in range(-2, 3):
            d.point((mx, my+dy), fill=color)
        # horizontal bar
        for dx in range(-2, 3):
            d.point((mx+dx, my), fill=color)
    elif suit == 'diamond':
        color = RED_SUIT
        d.rectangle([mx - 2, my - 1, mx + 2, my + 1], fill=color)
        d.rectangle([mx - 1, my - 2, mx + 1, my + 2], fill=color)
    elif suit == 'heart':
        color = RED_SUIT
        # two bumps at top
        for px, py in [(mx-2, my-2), (mx-1, my-2), (mx+1, my-2), (mx+2, my-2)]:
            d.point((px, py), fill=color)
        # two full rows
        for dx in range(-2, 3):
            d.point((mx+dx, my-1), fill=color)
            d.point((mx+dx, my),   fill=color)
        # narrowing row
        for dx in range(-1, 2):
            d.point((mx+dx, my+1), fill=color)
        # pointed tip
        d.point((mx, my+2), fill=color)
    elif suit == 'spade':
        color = BLACK_SUIT
        # pointed tip
        d.point((mx, my-2), fill=color)
        # full row
        for dx in range(-2, 3):
            d.point((mx+dx, my-1), fill=color)
        # middle row
        for dx in range(-1, 2):
            d.point((mx+dx, my), fill=color)
        # stem
        d.point((mx, my+1), fill=color)
        # base bar
        for dx in range(-1, 2):
            d.point((mx+dx, my+2), fill=color)
    elif suit == 'club':
        color = BLACK_SUIT
        # top two bumps
        d.point((mx-1, my-2), fill=color)
        d.point((mx+1, my-2), fill=color)
        # full row
        for dx in range(-2, 3):
            d.point((mx+dx, my-1), fill=color)
        # middle row
        for dx in range(-1, 2):
            d.point((mx+dx, my), fill=color)
        # stem
        d.point((mx, my+1), fill=color)
        # base bar
        for dx in range(-1, 2):
            d.point((mx+dx, my+2), fill=color)


def draw_pixel_card(img: Image.Image, cx: int, cy: int, angle_deg: float,
                    suit: str = 'diamond') -> None:
    """Draw a small pixel-art playing card centred at (cx, cy), rotated by angle_deg."""
    card = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)

    # body
    d.rectangle([0, 0, CARD_W - 1, CARD_H - 1], fill=CARD_BODY, outline=CARD_BORDER)
    # inner border line
    d.rectangle([2, 2, CARD_W - 3, CARD_H - 3], outline=CARD_BORDER)
    # suit pip in centre
    mx, my = CARD_W // 2, CARD_H // 2
    _draw_suit(d, mx, my, suit)

    # glow halo (slightly larger, very transparent)
    glow = Image.new("RGBA", (CARD_W + 8, CARD_H + 8), (0, 0, 0, 0))
    dg = ImageDraw.Draw(glow)
    dg.rectangle([0, 0, CARD_W + 7, CARD_H + 7], fill=GLOW, outline=GLOW)

    rotated_glow = glow.rotate(-angle_deg, expand=True, resample=Image.NEAREST)
    rotated_card = card.rotate(-angle_deg, expand=True, resample=Image.NEAREST)

    gx = cx - rotated_glow.width  // 2
    gy = cy - rotated_glow.height // 2
    img.paste(rotated_glow, (gx, gy), rotated_glow)

    rx = cx - rotated_card.width  // 2
    ry = cy - rotated_card.height // 2
    img.paste(rotated_card, (rx, ry), rotated_card)


def draw_card_pile(img: Image.Image, base_x: int, base_y: int) -> None:
    """Draw 4 slightly fanned cards stacked at (base_x, base_y) — a fallen deck.
    The top card (drawn last) shows a black cross — out of the game."""
    pile_suits = ['diamond', 'heart', 'spade', 'cross']   # cross ends up on top
    for i, suit in enumerate(pile_suits):
        draw_pixel_card(img,
                        base_x + i * 4,
                        base_y + i * 3,
                        angle_deg=random.uniform(-20, 20),
                        suit=suit)


def draw_motion_trail(draw: ImageDraw.Draw, x1, y1, x2, y2) -> None:
    """Draw a faint gold dotted trail between two points (pixel art dashes)."""
    steps = 8
    for i in range(1, steps):
        t = i / steps
        tx = int(x1 + (x2 - x1) * t)
        ty = int(y1 + (y2 - y1) * t)
        alpha = int(160 * math.sin(t * math.pi))
        if i % 2 == 0:  # pixel-art dashes
            draw.rectangle([tx - 1, ty - 1, tx + 1, ty + 1],
                           fill=(220, 180, 60, alpha))


def main() -> None:
    random.seed(42)

    # ── load & prepare source mailbox ────────────────────────────────────────
    src = Image.open(SRC).convert("RGBA")

    # make white background transparent (the source has white BG)
    data = src.load()
    w, h = src.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = data[x, y]
            # pixels that are near-white and not part of the mailbox itself
            if r > 230 and g > 230 and b > 230:
                data[x, y] = (r, g, b, 0)

    mbox = src.resize((MBOX_SIZE, MBOX_SIZE), Image.NEAREST)

    # ── canvas ───────────────────────────────────────────────────────────────
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw   = ImageDraw.Draw(canvas)

    cx, cy = CANVAS // 2, CANVAS // 2

    # ── place mailboxes in a ring ─────────────────────────────────────────────
    mbox_centers = []
    for i in range(N):
        angle_rad = 2 * math.pi * i / N - math.pi / 2   # start at top
        mx = int(cx + RING_R * math.cos(angle_rad))
        my = int(cy + RING_R * math.sin(angle_rad))
        mbox_centers.append((mx, my))

        # rotate each mailbox to face the centre (tangent direction)
        face_angle = math.degrees(angle_rad) + 90
        rotated = mbox.rotate(-face_angle, expand=False, resample=Image.NEAREST)

        px = mx - rotated.width  // 2
        py = my - rotated.height // 2
        canvas.paste(rotated, (px, py), rotated)

    # ── flying cards between mailboxes (clockwise) ───────────────────────────
    suits_order = SUITS[:]        # one of each suit, shuffled
    random.shuffle(suits_order)

    for i in range(N):
        ax, ay = mbox_centers[i]
        bx, by = mbox_centers[(i + 1) % N]

        # midpoint along the arc (interpolated at 50%)
        mid_x = int(ax + (bx - ax) * 0.5)
        mid_y = int(ay + (by - ay) * 0.5)

        # slight outward push so the card is clearly between the boxes
        push_x = int((mid_x - cx) * 0.15)
        push_y = int((mid_y - cy) * 0.15)
        mid_x += push_x
        mid_y += push_y

        # small random position jitter — no two gaps look identical
        mid_x += random.randint(-8, 8)
        mid_y += random.randint(-8, 8)

        # card flight angle = direction of travel + slight random rotation
        flight_angle = math.degrees(math.atan2(by - ay, bx - ax))
        flight_angle += random.uniform(-15, 15)

        draw_motion_trail(draw, ax, ay, bx, by)
        draw_pixel_card(canvas, mid_x, mid_y, flight_angle, suits_order[i])

    # ── broken / fallen mailbox outside the ring ─────────────────────────────
    broken_x = cx + RING_R + 60
    broken_y = cy + RING_R + 20

    # Step 1: desaturate + darken (dead/damaged look)
    # Enhance RGB only — preserving the original alpha (transparent background)
    broken_mbox = mbox.copy()
    alpha = broken_mbox.split()[3]
    rgb = broken_mbox.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(0.25)      # mostly grey, hint of original
    rgb = ImageEnhance.Brightness(rgb).enhance(0.60) # noticeably darker
    broken_mbox = rgb.convert("RGBA")
    broken_mbox.putalpha(alpha)

    # Step 2: tilt it over (fallen on side)
    broken_mbox = broken_mbox.rotate(82, expand=True, resample=Image.NEAREST)

    # Step 3: place it (adjust for expanded size after rotation)
    bx_pos = broken_x - broken_mbox.width  // 2
    by_pos = broken_y - broken_mbox.height // 2
    canvas.paste(broken_mbox, (bx_pos, by_pos), broken_mbox)

    # Card pile beside the broken mailbox (to its left and slightly below)
    draw_card_pile(canvas, broken_x - 30, broken_y + 30)

    canvas.save(OUT, "PNG")
    print(f"Saved {OUT}")


if __name__ == "__main__":
    main()
