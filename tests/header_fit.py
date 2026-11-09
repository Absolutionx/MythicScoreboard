#!/usr/bin/env python3
# usage: python3 header_fit.py ADDON_DIR
# Every Stats page column header fits its column, in English and each
# Latin-script translation, measured with the addon's own font (Barlow Semi
# Condensed Medium, 13) plus a margin: the game draws text a little wider than
# the font's own metrics. (Russian, Korean and Chinese use the game's fonts,
# which aren't here to measure.)
import re, sys
from fontTools.ttLib import TTFont

ADDON = sys.argv[1]
SIZE, MARGIN, PAD = 13, 1.15, 6          # header: Text(band, "medium", 13), width c.w - 6
font = TTFont(ADDON + "/Media/Fonts/BarlowSemiCondensed-Medium.ttf")
cmap, hmtx, upm = font.getBestCmap(), font["hmtx"], font["head"].unitsPerEm

def width(s):
    return sum(hmtx[cmap.get(ord(c), cmap[ord("?")])][0] for c in s) * SIZE / upm

src = open(ADDON + "/Core/UI_Stats.lua", encoding="utf8").read() + open(ADDON + "/Core/UI_StatsKeys.lua", encoding="utf8").read()
cols = []
for table in ("DCOLS", "RCOLS", "LCOLS", "KCOLS"):
    body = re.search(r"local %s = \{(.*?)\n\}" % table, src, re.S).group(1)
    for label, w in re.findall(r'label = LK\("([^"]+)"\),\s*w = (\d+)', body):
        cols.append((table, label, int(w)))
# Forever swaps "Your DPS" for "XP a run" at the same width.
for t, label, w in list(cols):
    if label == "Your DPS":
        cols.append((t, "XP a run", w))

fails = passes = 0
for loc in ("enUS", "deDE", "frFR", "esES", "ptBR", "itIT"):
    T = {}
    if loc != "enUS":
        T = dict(re.findall(r'^T\["(.*?)"\] = "(.*)"$', open("%s/Locales/%s.lua" % (ADDON, loc), encoding="utf8").read(), re.M))
    for table, label, w in cols:
        text = T.get(label) or label.split("#")[0]
        need, room = width(text) * MARGIN, w - PAD
        if need <= room:
            passes += 1
        else:
            fails += 1
            print("FAIL %s %s %r: needs %.0fpx, column gives %dpx" % (loc, table, text, need, room))
# The dungeon names under the Dungeon column (semibold 15, width w - 8) fit,
# at full size or stepped down at most two sizes (UI.FitText does that).
sb = TTFont(ADDON + "/Media/Fonts/BarlowSemiCondensed-SemiBold.ttf")
scmap, shmtx, supm = sb.getBestCmap(), sb["hmtx"], sb["head"].unitsPerEm
namew = next(w for t, label, w in cols if t == "DCOLS" and label == "Dungeon") - 8
forever = open(ADDON + "/Core/Forever.lua", encoding="utf8").read()
for name in re.findall(r'^    \["([^"]+)"\] = \{', forever, re.M):
    need = sum(shmtx[scmap.get(ord(c), scmap[ord("?")])][0] for c in name) * 13 / supm
    if need <= namew: passes += 1
    else:
        fails += 1
        print("FAIL dungeon name %r: needs %.0fpx, column gives %dpx" % (name, need, namew))

# Run times in the Best and Typical columns (medium 15, width w - 8):
# "1:24:33", with the same margin.
med15 = lambda s: sum(hmtx[cmap[ord(c)]][0] for c in s) * 15 / upm * MARGIN
for t, label, w in cols:
    if t == "DCOLS" and label in ("Best", "Typical"):
        need = med15("9:59:59")
        if need <= w - 8: passes += 1
        else:
            fails += 1
            print("FAIL %s column: a run time needs %.0fpx, column gives %dpx" % (label, need, w - 8))

print("header_fit: %d passed, %d failed" % (passes, fails))
sys.exit(1 if fails else 0)
