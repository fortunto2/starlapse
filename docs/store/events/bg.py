import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from layout import CARD, DETAIL, EVENTS
R = sys.argv[1]; OUT = os.path.abspath(sys.argv[2]); PHOTO = os.path.abspath(sys.argv[3])
os.makedirs(OUT, exist_ok=True)
def load(path, cut):
    src = open(path).read(); src = src[: src.index(cut)]; g = {"__name__": "x"}
    sys.argv = [path, PHOTO]; exec(compile(src, path, "exec"), g); return g
moon = load(f"{R}/moonscape.py", '\nrender(1920')
met = load(f"{R}/meteors.py", 'base = sys.argv[1]')
for key, e in EVENTS.items():
    for L, s, n, tag in ((CARD, e["seed"][0], 0, "card"), (DETAIL, e["seed"][1], 1, "details")):
        out = f"{OUT}/{key}-{tag}.jpg"
        if e["kind"] == "meteor":
            met["render"](L["W"], L["H"], L["radiant"], s, out, e["n"][n])
        else:
            opts = dict(e.get("opts", {}))
            if e.get("mars"): opts["mars"] = L["mars"]
            moon["render"](L["W"], L["H"], L["moon"], L["D"], s, out, **opts)
        print(out)
