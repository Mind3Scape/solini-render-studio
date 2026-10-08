#!/usr/bin/env python3
"""Draw a composition's regions (tools/regions.json) on a frame of the visible card crop, to check
them before measuring.  regions_overlay.py take.mp4 ninfea out.png [--frame N]"""
import argparse, io, json, os, subprocess
from PIL import Image, ImageDraw

p = argparse.ArgumentParser()
p.add_argument("take"); p.add_argument("composition"); p.add_argument("out")
p.add_argument("--frame", type=int, default=0); p.add_argument("--card-aspect", type=float, default=1.30)
a = p.parse_args()
regions = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "regions.json")))[a.composition]
raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", a.take, "-vf",
    f"select='eq(n\\,{a.frame})',crop=iw:min(ih\\,iw*{a.card_aspect}),scale=540:-2", "-vsync", "0",
    "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"])
im = Image.open(io.BytesIO(raw)).convert("RGB")
d = ImageDraw.Draw(im)
w, h = im.size
for spec in regions:
    name, rest = spec.split("=", 1)
    coords, _, kind = rest.partition(":")
    x0, y0, x1, y1 = (float(v) for v in coords.split(","))
    colour = (230, 60, 60) if kind == "rigid" else (60, 200, 90)
    d.rectangle([x0 * w, y0 * h, x1 * w - 1, y1 * h - 1], outline=colour, width=2)
    d.text((x0 * w + 4, y0 * h + 3), name, fill=colour)
im.save(a.out)
