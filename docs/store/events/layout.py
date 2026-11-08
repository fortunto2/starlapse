"""The template's one rule: the subject sits where App Store text never goes.
Card 16:9 — upper right third. Details 9:16 — upper 45%. Everything else follows from it."""
CARD = dict(W=1920, H=1080, moon=(1350, 420), D=400, radiant=(1380, 330), aim=(880, 400), mars=(1690, 290))
DETAIL = dict(W=1080, H=1920, moon=(540, 700), D=500, radiant=(600, 520), aim=(330, 860), mars=(850, 420))
EVENTS = {
    "geminids":  dict(kind="meteor", seed=(7, 11), n=(14, 13)),
    "quad":      dict(kind="meteor", seed=(57, 59), n=(13, 12)),
    "christmas": dict(kind="moon", seed=(3, 5), opts=dict(snow=True)),
    "beaver":    dict(kind="moon", seed=(21, 23), opts={}),
    "wolf":      dict(kind="moon", seed=(31, 33), opts=dict(snow=True, trees=False, warm=(240, 238, 235))),
    "lantern":   dict(kind="moon", seed=(41, 43), opts=dict(trees=False, lanterns=24), mars=True),
}
