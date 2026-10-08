"""Salini Insight · «Участок отгрузки» proof: reproducible Blender art kit.

Builds the static architecture of one shipping section (≈24 × 20 m: quality control, racking,
staging, two docks and the yard), the movable forklift / truck / batch, and named anchors that
drive the app's demo logic. Bakes ambient occlusion of the static scene (roof absent, movers
hidden) into a second UV set «Lightmap». In SceneKit the AO map multiplies only ambient/IBL
light, so the real-time sun, its shadows and specular highlights are never doubled.

Scene coordinates (as used by the app): metres, x east, y up, z south; the isometric camera
looks from +x +z. Blender is Z-up, so every point goes through S(x, y, z) = (x, -z, y) and the
USD export converts back to Y-up.

  blender -b --factory-startup --python ios/tools/insight_poc/build_atelier_kit.py -- \
      ios/Salini/InsightAssets [--no-bake] [--samples 192] [--size 2048]
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv and not argv[0].startswith("--") else "ios/Salini/InsightAssets")
BAKE = "--no-bake" not in argv
SAMPLES = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 192
SIZE = int(argv[argv.index("--size") + 1]) if "--size" in argv else 2048

SRC = os.path.abspath(argv[argv.index("--src") + 1]) if "--src" in argv else os.path.abspath("tmp/insight-poc-source")
USED_ASSETS = []
FLOOR = 1.2   # hall floor = dock height above the yard
CUT = 2.6     # section height of the near (south/east) walls and the trailer
TOP = 8.2     # far walls

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def S(x, y, z):
    return Vector((x, -z, y))


# ----------------------------------------------------------------------------- materials
# Blender colours are only a preview; the app assigns its own PBR by material name.
PALETTE = {
    "M_Panel": (0.84, 0.84, 0.82), "M_Plinth": (0.64, 0.63, 0.60), "M_Section": (0.25, 0.25, 0.24),
    "M_Floor": (0.70, 0.70, 0.68), "M_Slab": (0.58, 0.57, 0.53), "M_Asphalt": (0.10, 0.11, 0.12),
    "M_Paving": (0.60, 0.58, 0.53), "M_Curb": (0.72, 0.71, 0.68), "M_Grass": (0.14, 0.25, 0.10),
    "M_LineWhite": (0.85, 0.85, 0.83), "M_LineYellow": (0.80, 0.62, 0.15),
    "M_Steel": (0.11, 0.16, 0.21), "M_Galv": (0.62, 0.63, 0.64), "M_RackUpright": (0.05, 0.12, 0.22),
    "M_RackBeam": (0.82, 0.55, 0.16), "M_Timber": (0.58, 0.45, 0.30), "M_Carton": (0.62, 0.50, 0.36),
    "M_Wrap": (0.90, 0.90, 0.88), "M_Rubber": (0.06, 0.06, 0.06), "M_Bollard": (0.85, 0.66, 0.12),
    "M_Lamp": (0.95, 0.95, 0.92), "M_Desk": (0.75, 0.73, 0.70), "M_Screen": (0.05, 0.06, 0.08),
    "M_Foliage": (0.25, 0.42, 0.26), "M_Bark": (0.30, 0.24, 0.19), "M_Mat": (0.18, 0.19, 0.20),
    "M_Leveler": (0.40, 0.41, 0.42), "M_TruckCab": (0.88, 0.88, 0.86), "M_Trailer": (0.82, 0.83, 0.83),
    "M_Glass": (0.05, 0.07, 0.09), "M_Forklift": (0.80, 0.58, 0.16), "M_Beacon": (1.0, 0.6, 0.1),
    "M_Coat": (0.92, 0.92, 0.9), "M_Vest": (0.85, 0.6, 0.2), "M_Trousers": (0.2, 0.22, 0.26),
    "M_Skin": (0.75, 0.58, 0.48), "M_Hair": (0.15, 0.13, 0.12), "M_Workwear": (0.22, 0.32, 0.45),
    "M_Toolbox": (0.85, 0.6, 0.2), "M_Ceramic": (0.92, 0.92, 0.91),
    "M_Window": (0.55, 0.62, 0.68), "M_GlassClear": (0.8, 0.85, 0.88), "M_BoothFrame": (0.86, 0.86, 0.85),
}
MATS = {}
for name, rgb in PALETTE.items():
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    MATS[name] = m

# ----------------------------------------------------------------------------- geometry
GROUPS = {}   # group name -> list of objects to join


def _obj(name, bm, mat, group, bevel, segments=2, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MATS[mat])
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if bevel > 0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
        mod.harden_normals = True
        mod.miter_outer = "MITER_ARC"
    GROUPS.setdefault(group, []).append(ob)
    return ob


def box(x0, x1, y0, y1, z0, z1, mat, group="Static", bevel=0.015, segments=2, rot_y=0.0, pivot=None):
    """Axis-aligned box in scene coordinates (optional rotation about the vertical axis)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
    bmesh.ops.scale(bm, vec=Vector((sx, sz, sy)), verts=bm.verts)
    c = S((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    if rot_y:
        p = S(*pivot) if pivot else c
        bmesh.ops.translate(bm, vec=c - p, verts=bm.verts)
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(rot_y, 3, "Z"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=p, verts=bm.verts)
    else:
        bmesh.ops.translate(bm, vec=c, verts=bm.verts)
    return _obj("box", bm, mat, group, min(bevel, 0.45 * min(sx, sy, sz)), segments)


def cyl(x, y0, y1, z, r, mat, group="Static", seg=20, bevel=0.01, axis="y"):
    bm = bmesh.new()
    length = y1 - y0
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=length)
    if axis == "y":
        bmesh.ops.translate(bm, vec=S(x, (y0 + y1) / 2, z), verts=bm.verts)
    elif axis == "z":   # along scene z (Blender -Y)
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=S(x, z, (y0 + y1) / 2), verts=bm.verts)  # y=height, (y0,y1)=z range
    else:               # along scene x
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=S((y0 + y1) / 2, x, z), verts=bm.verts)  # x=height, (y0,y1)=x range
    return _obj("cyl", bm, mat, group, bevel, 2)


def flat(points, y, mat, group="Static"):
    """A flat polygon on the ground (paint, grass, asphalt) — no thickness, no bevel."""
    bm = bmesh.new()
    vs = [bm.verts.new(S(px, y, pz)) for px, pz in points]
    bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    return _obj("flat", bm, mat, group, 0, smooth=False)


def rect(x0, x1, z0, z1, y, mat, group="Static"):
    return flat([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], y, mat, group)


def stripe(xa, za, xb, zb, w, y, mat):
    dx, dz = xb - xa, zb - za
    n = math.hypot(dx, dz)
    ox, oz = -dz / n * w / 2, dx / n * w / 2
    return flat([(xa + ox, za + oz), (xb + ox, zb + oz), (xb - ox, zb - oz), (xa - ox, za - oz)], y, mat)


def text(body, x, z, size, mat, rot=0.0, y=0.012):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("txt", cu)
    scene.collection.objects.link(ob)
    ob.location = S(x, y, z)
    ob.rotation_euler = (0, 0, rot)
    bpy.context.view_layer.objects.active = ob
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.view_layer.objects.active
    ob.data.materials.clear()
    ob.data.materials.append(MATS[mat])
    GROUPS.setdefault("Static", []).append(ob)


def anchor(name, x, y, z, heading=0.0):
    e = bpy.data.objects.new(name, None)
    e.location = S(x, y, z)
    e.rotation_euler = (0, 0, heading)
    scene.collection.objects.link(e)
    GROUPS.setdefault("Anchors", []).append(e)
    return e


# ----------------------------------------------------------------------------- site & yard
rect(-8, 36, -8, 32, 0.0, "M_Paving")
rect(14.2, 36, -8, 23.0, 0.004, "M_Asphalt")                 # dock yard
rect(-8, 36, 24.6, 30.6, 0.004, "M_Asphalt")                 # access road
rect(-8, 14.2, 22.6, 24.4, 0.006, "M_Grass")                 # planting strip along the hall
rect(-8, -1.0, -8, 22.6, 0.006, "M_Grass")                   # west lawn
rect(-1.0, 14.2, -8, -1.2, 0.006, "M_Grass")                 # north lawn
for x0, x1, z0, z1 in [(-8, 14.2, 22.45, 22.6), (-8, 14.2, 24.4, 24.6), (14.2, 36, 23.0, 23.15),
                       (-1.15, -1.0, -8, 22.6), (-1.0, 14.2, -1.35, -1.2)]:
    box(x0, x1, 0, 0.14, z0, z1, "M_Curb", bevel=0.035)
for x in range(-6, 36, 4):                                    # road centre dashes
    rect(x, x + 2, 27.52, 27.68, 0.009, "M_LineWhite")
for x0 in (2.0, 2.6, 3.2, 3.8, 4.4):                          # zebra from the walkway to the road
    rect(x0, x0 + 0.35, 22.6, 24.6, 0.012, "M_LineWhite")
# Dock bays: lines, numbers, wheel stops, island with the lamp pole.
for z in (4.2, 8.8, 11.2, 15.8):
    rect(14.3, 31.0, z - 0.07, z + 0.07, 0.009, "M_LineWhite")
text("01", 29.0, 6.5, 1.3, "M_LineWhite", rot=math.pi / 2)
text("02", 29.0, 13.5, 1.3, "M_LineWhite", rot=math.pi / 2)
for i in range(7):                                            # hatch between the bays
    stripe(14.4 + i * 0.55, 8.95, 14.9 + i * 0.55, 11.05, 0.14, 0.01, "M_LineYellow")
box(14.3, 18.2, 0, 0.16, 9.35, 10.65, "M_Curb", bevel=0.03)   # dock island
for z in (4.55, 8.45, 11.55, 15.45):
    cyl(14.7, 0, 1.05, z, 0.11, "M_Bollard", seg=18)
    cyl(14.7, 1.05, 1.1, z, 0.08, "M_Bollard", seg=18)
# Lamp pole on the island and one at the walkway.
for px, pz, arm in ((17.6, 10.0, -1), (15.4, 21.8, -1)):
    cyl(px, 0.16, 8.0, pz, 0.09, "M_Galv", seg=16)
    box(px + arm * 1.4, px, 7.85, 7.95, pz - 0.05, pz + 0.05, "M_Galv", bevel=0.01)
    box(px + arm * 1.75, px + arm * 1.05, 7.7, 7.88, pz - 0.22, pz + 0.22, "M_Steel", bevel=0.03)
    box(px + arm * 1.7, px + arm * 1.1, 7.69, 7.7, pz - 0.18, pz + 0.18, "M_Lamp", bevel=0)
    anchor(f"anchor_light_pole_{'island' if pz < 15 else 'walk'}", px + arm * 1.4, 7.6, pz)
# Transformer cabinet and a cable trench cover in the yard corner.
box(30.0, 32.4, 0, 2.3, -6.5, -4.9, "M_Galv", bevel=0.04)
for i in range(6):
    box(30.0 + 0.3 + i * 0.35, 30.0 + 0.5 + i * 0.35, 0.8, 1.9, -4.92, -4.88, "M_Steel", bevel=0.005)
box(26, 30, 0, 0.03, -5.9, -5.5, "M_Galv", bevel=0.005)

# ----------------------------------------------------------------------------- hall shell
box(0, 14.25, 0, FLOOR, 0, 20.25, "M_Slab", bevel=0.07)           # raised dock-height slab
rect(0.25, 13.75, 0.25, 19.75, FLOOR + 0.003, "M_Floor")
# Far walls: concrete plinth + horizontal sandwich panels with real joints.
box(0, 14.0, FLOOR, FLOOR + 1.0, 0, 0.28, "M_Plinth", bevel=0.04)
box(0, 0.28, FLOOR, FLOOR + 1.0, 0, 20.0, "M_Plinth", bevel=0.04)
WIN0, WIN1 = FLOOR + 4.8, FLOOR + 5.9   # ribbon glazing band in the far walls
for i in range(int(TOP - FLOOR - 1.0)):
    y0 = FLOOR + 1.0 + i + 0.006
    y1 = y0 + 0.988
    if y1 > WIN0 and y0 < WIN1:
        continue
    box(0, 14.0, y0, y1, 0, 0.25, "M_Panel", bevel=0.03)
    box(0, 0.25, y0, y1, 0.25, 20.0, "M_Panel", bevel=0.03)
gap_lo, gap_hi = FLOOR + 4.006, FLOOR + 5.994      # panels skipped around the band
box(0, 14.0, gap_lo, WIN0, 0, 0.25, "M_Panel", bevel=0.03)
box(0, 0.25, gap_lo, WIN0, 0.25, 20.0, "M_Panel", bevel=0.03)
box(0, 14.0, WIN1, gap_hi, 0, 0.25, "M_Panel", bevel=0.03)
box(0, 0.25, WIN1, gap_hi, 0.25, 20.0, "M_Panel", bevel=0.03)
box(0, 14.0, WIN0, WIN1, 0, 0.1, "M_Window", bevel=0)                      # glass, set back
box(0, 0.1, WIN0, WIN1, 0.1, 20.0, "M_Window", bevel=0)
for y in (WIN0, WIN1 - 0.06):                                               # sill and head
    box(0, 14.0, y, y + 0.06, 0.08, 0.2, "M_Galv", bevel=0.005, segments=1)
    box(0.08, 0.2, y, y + 0.06, 0.1, 20.0, "M_Galv", bevel=0.005, segments=1)
for k in range(1, 10):                                                      # mullions
    x = k * 1.4
    box(x - 0.03, x + 0.03, WIN0, WIN1, 0.08, 0.18, "M_Galv", bevel=0.004, segments=1)
for k in range(1, 14):
    z = k * 1.43
    box(0.08, 0.18, WIN0, WIN1, z - 0.03, z + 0.03, "M_Galv", bevel=0.004, segments=1)
box(0.3, 13.7, FLOOR + 3.4, FLOOR + 3.46, 0.3, 0.6, "M_Galv", bevel=0.004, segments=1)    # cable tray
box(0.3, 13.7, FLOOR + 3.46, FLOOR + 3.52, 0.3, 0.32, "M_Galv", bevel=0, segments=1)
box(0.3, 13.7, FLOOR + 3.46, FLOOR + 3.52, 0.58, 0.6, "M_Galv", bevel=0, segments=1)
box(-0.05, 14.05, TOP, TOP + 0.12, -0.05, 0.32, "M_Galv", bevel=0.025)     # coping
box(-0.05, 0.32, TOP, TOP + 0.12, -0.05, 20.05, "M_Galv", bevel=0.01)
# Near walls cut at CUT with a darker section cap; openings for two docks and a door.
def cut_wall_x(z0, z1):   # east wall, x 13.75..14.0
    box(13.72, 14.0, FLOOR, FLOOR + 1.0, z0, z1, "M_Plinth", bevel=0.04)
    box(13.75, 14.0, FLOOR + 1.0, CUT, z0, z1, "M_Panel", bevel=0.03)
    box(13.75, 14.0, CUT, CUT + 0.02, z0, z1, "M_Section", bevel=0)
def cut_wall_z(x0, x1):   # south wall, z 19.75..20.0
    box(x0, x1, FLOOR, FLOOR + 1.0, 19.72, 20.0, "M_Plinth", bevel=0.04)
    box(x0, x1, FLOOR + 1.0, CUT, 19.75, 20.0, "M_Panel", bevel=0.03)
    box(x0, x1, CUT, CUT + 0.02, 19.75, 20.0, "M_Section", bevel=0)
for z0, z1 in ((0.28, 5.0), (8.0, 12.0), (15.0, 20.0)):
    cut_wall_x(z0, z1)
for x0, x1 in ((0.28, 2.5), (3.5, 13.75)):
    cut_wall_z(x0, x1)
# Steel columns (HEA profiles) on the grid; near-wall columns are cut with the walls.
def column(x, z, top, along_x):
    w, d, t = 0.30, 0.29, 0.02
    if along_x:
        box(x - w / 2, x + w / 2, FLOOR, top, z - d / 2, z - d / 2 + t, "M_Steel", bevel=0.008, segments=1)
        box(x - w / 2, x + w / 2, FLOOR, top, z + d / 2 - t, z + d / 2, "M_Steel", bevel=0.008, segments=1)
        box(x - 0.006, x + 0.006, FLOOR, top, z - d / 2, z + d / 2, "M_Steel", bevel=0, segments=1)
    else:
        box(x - d / 2, x - d / 2 + t, FLOOR, top, z - w / 2, z + w / 2, "M_Steel", bevel=0.008, segments=1)
        box(x + d / 2 - t, x + d / 2, FLOOR, top, z - w / 2, z + w / 2, "M_Steel", bevel=0.008, segments=1)
        box(x - d / 2, x + d / 2, FLOOR, top, z - 0.006, z + 0.006, "M_Steel", bevel=0, segments=1)
for x in (0.42, 7.0, 13.58):
    column(x, 0.42, TOP - 0.05, True)
for z in (6.9, 13.4, 19.58):
    column(0.42, z, TOP - 0.05, False)
for z in (10.0, 19.58):
    column(13.58, z, CUT, False)
column(7.0, 19.58, CUT, True)
box(0.25, 13.8, TOP - 0.55, TOP - 0.25, 0.28, 0.5, "M_Steel", bevel=0.005, segments=1)  # eaves girt
box(0.28, 0.5, TOP - 0.55, TOP - 0.25, 0.25, 19.8, "M_Steel", bevel=0.005, segments=1)
# A light 4.4 m workshop gantry (the Poly Haven overhead crane at 0.35 scale) on its own four
# columns and runway beams over the staging area — a sanitaryware plant, not a shipyard.
CRANE_SCALE = 0.35
RAIL = FLOOR + 3.9
CRANE_X, CRANE_Z = 11.4, 6.0
for cx in (9.2, 13.6):
    for cz in (4.4, 7.6):
        column(cx, cz, RAIL - 0.28, True)
    box(cx - 0.1, cx + 0.1, RAIL - 0.28, RAIL, 4.1, 7.9, "M_Steel", bevel=0.01, segments=1)
    box(cx - 0.03, cx + 0.03, RAIL, RAIL + 0.05, 4.1, 7.9, "M_Galv", bevel=0, segments=1)
# Wall floodlights on the far walls (emissive face points into the hall).
for i, (x, z, heading) in enumerate(((3.5, 0.3, 0), (10.5, 0.3, 0), (0.3, 6.0, 1), (0.3, 15.0, 1))):
    if heading == 0:
        box(x - 0.35, x + 0.35, 7.3, 7.6, 0.3, 0.62, "M_Steel", bevel=0.02)
        box(x - 0.3, x + 0.3, 7.29, 7.3, 0.34, 0.58, "M_Lamp", bevel=0)
    else:
        box(0.3, 0.62, 7.3, 7.6, z - 0.35, z + 0.35, "M_Steel", bevel=0.02)
        box(0.34, 0.58, 7.29, 7.3, z - 0.3, z + 0.3, "M_Lamp", bevel=0)
    anchor(f"anchor_light_wall_{i}", x + (1.2 if heading else 0), 7.2, z + (0 if heading else 1.2))

# ----------------------------------------------------------------------------- docks
for zc in (6.5, 13.5):
    z0, z1 = zc - 1.5, zc + 1.5
    for zj in (z0 - 0.12, z1 + 0.12):                                   # steel jambs, cut
        box(13.7, 14.05, FLOOR, CUT, zj - 0.1, zj + 0.1, "M_Steel", bevel=0.01)
        box(13.7, 14.05, CUT, CUT + 0.02, zj - 0.1, zj + 0.1, "M_Section", bevel=0)
    box(13.2, 14.25, FLOOR, FLOOR + 0.03, z0 + 0.1, z1 - 0.1, "M_Leveler", bevel=0.01)   # leveler
    for zz in (z0 - 0.45, z1 + 0.05):                                    # shelter pads, cut
        box(14.0, 14.6, FLOOR - 0.1, CUT, zz, zz + 0.4, "M_Rubber", bevel=0.05)
    for zz in (z0 + 0.25, z1 - 0.5):                                      # bumpers
        box(14.25, 14.38, 0.75, 1.15, zz, zz + 0.25, "M_Rubber", bevel=0.02)
    box(14.25, 14.3, 0.2, 1.15, z0 + 0.1, z1 - 0.1, "M_Galv", bevel=0.005)   # pit face plate
anchor("anchor_dock_1", 14.0, FLOOR, 6.5)
anchor("anchor_dock_2", 14.0, FLOOR, 13.5)
# Personnel door with steel stair and handrail from the walkway.
for i in range(6):
    box(2.55, 3.45, 0, FLOOR - i * 0.2, 20.25 + i * 0.28, 20.53 + i * 0.28, "M_Galv", bevel=0.01)
for x in (2.5, 3.5):
    cyl(x, 0, 2.2, 21.9, 0.025, "M_Steel", seg=10)
    cyl(x, FLOOR, 2.2, 20.3, 0.025, "M_Steel", seg=10)

# ----------------------------------------------------------------------------- interior: QC
def crate(cx, y0, cz, along_z=True):
    """A packed bathtub crate: white film over the tub, timber slats and corner posts."""
    lx, lz = (0.82, 1.72) if along_z else (1.72, 0.82)
    h = 0.66
    box(cx - lx / 2 + 0.03, cx + lx / 2 - 0.03, y0, y0 + h - 0.03, cz - lz / 2 + 0.03, cz + lz / 2 - 0.03, "M_Wrap", bevel=0.05)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(cx + sx * lx / 2 - (0.07 if sx > 0 else 0), cx + sx * lx / 2 + (0 if sx > 0 else 0.07), y0, y0 + h,
                cz + sz * lz / 2 - (0.07 if sz > 0 else 0), cz + sz * lz / 2 + (0 if sz > 0 else 0.07), "M_Timber", bevel=0.008, segments=1)
    for yy in (y0 + 0.08, y0 + h - 0.12):
        if along_z:
            for sx in (-1, 1):
                box(cx + sx * lx / 2 - 0.02, cx + sx * lx / 2 + 0.02, yy, yy + 0.1, cz - lz / 2, cz + lz / 2, "M_Timber", bevel=0.008, segments=1)
        else:
            for sz in (-1, 1):
                box(cx - lx / 2, cx + lx / 2, yy, yy + 0.1, cz + sz * lz / 2 - 0.02, cz + sz * lz / 2 + 0.02, "M_Timber", bevel=0.008, segments=1)
    return y0 + h


def pallet(cx, y0, cz, lx=1.0, lz=1.8, group="Static"):
    for i in range(5):                                                      # deck boards
        z = cz - lz / 2 + 0.08 + i * (lz - 0.16) / 4
        box(cx - lx / 2, cx + lx / 2, y0 + 0.11, y0 + 0.14, z - 0.06, z + 0.06, "M_Timber", group, bevel=0.005, segments=1)
    for sx in (-1, 0, 1):                                                   # stringers
        x = cx + sx * (lx / 2 - 0.05)
        box(x - 0.05, x + 0.05, y0, y0 + 0.11, cz - lz / 2, cz + lz / 2, "M_Timber", group, bevel=0.005, segments=1)
    return y0 + 0.14


def batch(cx, y0, cz, group="Static", layers=2):
    y = pallet(cx, y0, cz, group=group)
    for _ in range(layers):
        if group == "Static":
            y = crate(cx, y, cz)
        else:
            y = crate_group(cx, y, cz, group)
    return y


def crate_group(cx, y0, cz, group):
    start = len(GROUPS.get("Static", []))
    top = crate(cx, y0, cz)
    moved = GROUPS["Static"][start:]
    del GROUPS["Static"][start:]
    GROUPS.setdefault(group, []).extend(moved)
    return top


def trolley(x, z):
    """Tool trolley: blue-grey frame, two trays, an amber toolbox and a tablet."""
    for sx in (-0.3, 0.3):
        for sz in (-0.2, 0.2):
            cyl(x + sx, FLOOR + 0.06, FLOOR + 0.9, z + sz, 0.016, "M_Steel", seg=8, bevel=0)
            cyl(x + sx, FLOOR, FLOOR + 0.06, z + sz, 0.04, "M_Rubber", seg=10, bevel=0)
    for y in (FLOOR + 0.2, FLOOR + 0.86):
        box(x - 0.33, x + 0.33, y, y + 0.03, z - 0.23, z + 0.23, "M_Steel", bevel=0.01)
    box(x - 0.24, x + 0.1, FLOOR + 0.89, FLOOR + 1.05, z - 0.14, z + 0.12, "M_Toolbox", bevel=0.02)
    box(x + 0.13, x + 0.3, FLOOR + 0.89, FLOOR + 0.9, z - 0.12, z + 0.12, "M_Screen", bevel=0.004)
    box(x - 0.2, x + 0.2, FLOOR + 0.23, FLOOR + 0.36, z - 0.16, z + 0.16, "M_Carton", bevel=0.01)


STATIONS = [((2.9, 3.2), "Alda-160-70"), ((6.9, 3.2), "Mona-170"), ((2.9, 6.6), "Luce"), ((6.9, 6.6), "Noemi-170")]
for i, ((cx, cz), product) in enumerate(STATIONS):
    rect(cx - 1.6, cx + 1.6, cz - 1.25, cz + 1.25, FLOOR + 0.006, "M_Mat")
    for sx in (-1, 1):                                                      # trestles
        box(cx + sx * 0.7 - 0.05, cx + sx * 0.7 + 0.05, FLOOR, FLOOR + 0.55, cz - 0.4, cz + 0.4, "M_Steel", bevel=0.01)
    box(cx - 0.95, cx + 0.95, FLOOR + 0.55, FLOOR + 0.6, cz - 0.42, cz + 0.42, "M_Galv", bevel=0.01)
    for sx in (-1, 1):                                                      # inspection light frame
        for sz in (-1, 1):
            cyl(cx + sx * 1.35, FLOOR, FLOOR + 2.5, cz + sz * 1.05, 0.035, "M_Steel", seg=12)
    for sz in (-1, 1):
        box(cx - 1.4, cx + 1.4, FLOOR + 2.45, FLOOR + 2.55, cz + sz * 1.05 - 0.04, cz + sz * 1.05 + 0.04, "M_Steel", bevel=0.005)
    for sx in (-1, 1):
        box(cx + sx * 1.35 - 0.04, cx + sx * 1.35 + 0.04, FLOOR + 2.45, FLOOR + 2.55, cz - 1.1, cz + 1.1, "M_Steel", bevel=0.005)
    for sz in (-0.45, 0.45):
        box(cx - 1.1, cx + 1.1, FLOOR + 2.38, FLOOR + 2.45, cz + sz - 0.09, cz + sz + 0.09, "M_Steel", bevel=0.005)
        box(cx - 1.05, cx + 1.05, FLOOR + 2.37, FLOOR + 2.38, cz + sz - 0.07, cz + sz + 0.07, "M_Lamp", bevel=0)
    anchor(f"anchor_product_{product}", cx, FLOOR + 0.6, cz)
    anchor(f"anchor_light_qc_{i + 1}", cx, FLOOR + 2.3, cz)
    trolley(cx + (-0.85 if i % 2 == 0 else 0.85), cz + 0.78)
    for k in range(3):                                                     # inspection tools on the table
        box(cx - 0.75 + k * 0.12, cx - 0.7 + k * 0.12, FLOOR + 0.6, FLOOR + 0.62, cz + 0.3, cz + 0.4, "M_Toolbox" if k == 0 else "M_Steel", bevel=0)
# Packing table with stretch film and tape: Sofia 150 being packed.
box(3.95, 5.85, FLOOR + 0.78, FLOOR + 0.82, 8.9, 9.85, "M_Desk", bevel=0.015)
for sx in (4.05, 5.75):
    for sz in (8.98, 9.77):
        box(sx - 0.03, sx + 0.03, FLOOR, FLOOR + 0.78, sz - 0.03, sz + 0.03, "M_Steel", bevel=0.005)
box(3.98, 5.82, FLOOR + 0.2, FLOOR + 0.23, 8.95, 9.8, "M_Steel", bevel=0.005)
for k in range(3):
    box(4.0, 5.8, FLOOR + 0.23 + k * 0.025, FLOOR + 0.248 + k * 0.025, 8.98, 9.77, "M_Carton", bevel=0.003)
cyl(5.95, FLOOR, FLOOR + 1.1, 9.4, 0.03, "M_Steel", seg=10, bevel=0)                 # film roll stand
cyl(5.95, FLOOR + 0.55, FLOOR + 1.05, 9.4, 0.06, "M_Wrap", seg=16, bevel=0.005)
anchor("anchor_product_Sofia-150-2015-Corona-fbx", 4.9, FLOOR + 0.82, 9.37)
# Inspector desk with a screen and a chair against the north wall.
box(4.9, 6.1, FLOOR + 0.72, FLOOR + 0.76, 0.6, 1.3, "M_Desk", bevel=0.01)
for sx in (4.95, 6.0):
    box(sx, sx + 0.05, FLOOR, FLOOR + 0.72, 0.65, 1.25, "M_Steel", bevel=0.005)
box(5.2, 5.8, FLOOR + 0.8, FLOOR + 1.15, 0.75, 0.79, "M_Screen", bevel=0.005)
box(5.47, 5.53, FLOOR + 0.76, FLOOR + 0.82, 0.78, 0.8, "M_Steel", bevel=0)
box(5.25, 5.75, FLOOR + 0.42, FLOOR + 0.48, 1.55, 2.05, "M_Rubber", bevel=0.02)
box(5.25, 5.75, FLOOR + 0.48, FLOOR + 0.95, 2.0, 2.06, "M_Rubber", bevel=0.02)
cyl(5.5, FLOOR, FLOOR + 0.42, 1.8, 0.03, "M_Steel", seg=10)
# Glazed quality-control booth: aluminium frame, clear glass, solid roof with a condenser.
BX0, BX1, BZ0, BZ1, BH = 10.0, 12.7, 0.5, 3.1, 2.7
box(BX0, BX1, FLOOR, FLOOR + 0.12, BZ0, BZ1, "M_BoothFrame", bevel=0.01)
box(BX0 - 0.05, BX1 + 0.05, FLOOR + BH, FLOOR + BH + 0.14, BZ0 - 0.05, BZ1 + 0.05, "M_BoothFrame", bevel=0.02)
for x in (BX0, BX0 + 0.9, BX0 + 1.8, BX1):
    for z in (BZ0, BZ1):
        box(x - 0.04, x + 0.04, FLOOR, FLOOR + BH, z - 0.04, z + 0.04, "M_BoothFrame", bevel=0.006, segments=1)
for z in (BZ0 + 1.3,):
    for x in (BX0, BX1):
        box(x - 0.04, x + 0.04, FLOOR, FLOOR + BH, z - 0.04, z + 0.04, "M_BoothFrame", bevel=0.006, segments=1)
for y in (FLOOR + 1.0,):
    box(BX0, BX1, y, y + 0.05, BZ1 - 0.03, BZ1 + 0.03, "M_BoothFrame", bevel=0.004, segments=1)
    box(BX0 - 0.03, BX0 + 0.03, y, y + 0.05, BZ0, BZ1, "M_BoothFrame", bevel=0.004, segments=1)
    box(BX1 - 0.03, BX1 + 0.03, y, y + 0.05, BZ0, BZ1, "M_BoothFrame", bevel=0.004, segments=1)
box(BX0, BX1, FLOOR + 0.12, FLOOR + BH, BZ1 - 0.012, BZ1 + 0.012, "M_GlassClear", bevel=0)
box(BX1 - 0.012, BX1 + 0.012, FLOOR + 0.12, FLOOR + BH, BZ0, BZ1, "M_GlassClear", bevel=0)
box(BX0 - 0.012, BX0 + 0.012, FLOOR + 0.12, FLOOR + BH, BZ0, BZ1, "M_GlassClear", bevel=0)
box(BX0 + 0.3, BX1 - 0.3, FLOOR + 0.72, FLOOR + 0.76, BZ0 + 0.1, BZ0 + 0.8, "M_Desk", bevel=0.01)
box(BX0 + 0.8, BX0 + 1.3, FLOOR + 0.8, FLOOR + 1.1, BZ0 + 0.2, BZ0 + 0.24, "M_Screen", bevel=0.004)
box(BX0 + 1.5, BX0 + 2.0, FLOOR + 0.8, FLOOR + 1.1, BZ0 + 0.2, BZ0 + 0.24, "M_Screen", bevel=0.004)
anchor("anchor_booth_roof", (BX0 + BX1) / 2, FLOOR + BH + 0.14, (BZ0 + BZ1) / 2)
# Pickup square where an approved batch waits for the forklift.
PICK = (7.4, 9.2)
for a, b in (((-0.85, -1.2), (0.85, -1.2)), ((-0.85, 1.2), (0.85, 1.2)), ((-0.85, -1.2), (-0.85, 1.2)), ((0.85, -1.2), (0.85, 1.2))):
    stripe(PICK[0] + a[0], PICK[1] + a[1], PICK[0] + b[0], PICK[1] + b[1], 0.08, FLOOR + 0.009, "M_LineYellow")
anchor("anchor_pickup", PICK[0], FLOOR, PICK[1])
# Aisle and staging lines.
stripe(8.9, 7.6, 8.9, 19.5, 0.1, FLOOR + 0.009, "M_LineYellow")
stripe(12.0, 0.6, 12.0, 11.6, 0.1, FLOOR + 0.009, "M_LineYellow")
for i in range(6):
    stripe(12.6 + i * 0.22, 12.0, 12.6 + i * 0.22 + 0.4, 15.0, 0.07, FLOOR + 0.01, "M_LineWhite")
for cz in (2.3, 4.5, 6.7, 8.9):                                            # staged for dock 1
    batch(12.9, FLOOR, cz, layers=2 if cz != 8.9 else 1)

# ----------------------------------------------------------------------------- interior: racking
def rack_run(x0, depth, z0, bays, levels, seed):
    bay = 2.7
    z1 = z0 + bays * bay
    for k in range(bays + 1):
        z = z0 + k * bay
        for x in (x0, x0 + depth):
            box(x - 0.045, x + 0.045, FLOOR, FLOOR + 5.2, z - 0.04, z + 0.04, "M_RackUpright", bevel=0.006, segments=1)
        for y in (FLOOR + 0.5, FLOOR + 2.0, FLOOR + 3.5, FLOOR + 5.0):
            box(x0, x0 + depth, y, y + 0.04, z - 0.025, z + 0.025, "M_RackUpright", bevel=0, segments=1)
    for lv in range(levels):
        y = FLOOR + 0.15 + lv * 1.5
        for x in (x0, x0 + depth):
            box(x - 0.05, x + 0.05, y, y + 0.12, z0, z1, "M_RackBeam", bevel=0.006, segments=1)
        for k in range(bays):
            for j in range(2):
                if (seed * 7 + lv * 3 + k * 5 + j) % 5 == 0:
                    continue
                cz = z0 + k * bay + 0.38 + j * 1.0 + 0.45
                yy = pallet(x0 + depth / 2, y + 0.12, cz, lx=depth - 0.05, lz=0.95)
                if (seed + lv + k + j) % 3 == 0:
                    crate_h = 0.66
                    box(x0 + 0.08, x0 + depth - 0.08, yy, yy + crate_h, cz - 0.42, cz + 0.42, "M_Wrap", bevel=0.04)
                else:
                    hh = 0.55 + 0.25 * ((seed + k + j + lv) % 3)
                    box(x0 + 0.06, x0 + depth - 0.06, yy, yy + hh, cz - 0.44, cz + 0.44, "M_Carton", bevel=0.02)
rack_run(0.6, 1.1, 8.4, 4, 4, 1)
rack_run(3.4, 1.1, 10.9, 3, 4, 2)
for i in range(6):                                                           # empty pallet stack
    pallet(7.0, FLOOR + i * 0.145, 17.8, lx=1.0, lz=1.2)

# ----------------------------------------------------------------------------- planting
def tree(x, z, s, seed):
    cyl(x, 0, 2.2 * s, z, 0.09 * s, "M_Bark", seg=10, bevel=0)
    rng = [(0, 3.2, 0, 1.25), (0.55, 2.7, 0.3, 0.9), (-0.5, 2.8, -0.35, 0.85), (0.1, 3.9, -0.2, 0.8), (-0.3, 2.5, 0.55, 0.75)]
    for i, (dx, dy, dz, r) in enumerate(rng):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r * s)
        bmesh.ops.translate(bm, vec=S(x + dx * s, dy * s, z + dz * s), verts=bm.verts)
        ob = _obj("leaf", bm, "M_Foliage", "Static", 0)
        tex = bpy.data.textures.new(f"n{seed}{i}", "CLOUDS")
        tex.noise_scale = 0.35 * s
        d = ob.modifiers.new("disp", "DISPLACE")
        d.texture = tex
        d.strength = 0.35 * s
        d.mid_level = 0.5
# Trees: the Poly Haven tree_small_02 prototype, instanced at these anchors (see TREES below).
TREE_SPOTS = [(5.6, 23.5, 0.3, 1.0), (10.6, 23.6, 2.1, 0.9), (20.5, 33.6, 4.0, 1.1), (29.0, 33.2, 1.2, 0.95),
              (-3.5, 23.5, 5.2, 1.05)]
for i in range(14):                                                          # clipped hedge
    x0 = -0.6 + i * 1.0
    if 1.9 < x0 < 4.6:
        continue
    box(x0, x0 + 0.95, 0, 0.75, 22.75, 23.35, "M_Foliage", bevel=0.18, segments=3)

# ----------------------------------------------------------------------------- people
def limb(p0, p1, r0, r1, mat, seg=10):
    """A tapered capsule-ish limb between two scene points."""
    a, b = S(*p0), S(*p1)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r0, radius2=r1, depth=d.length)
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=bm.verts)
    _obj("limb", bm, mat, "Static", 0)


def ball(c, r, mat, squash=1.0, sub=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    bmesh.ops.scale(bm, vec=Vector((1, 1, squash)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=S(*c), verts=bm.verts)
    _obj("ball", bm, mat, "Static", 0)


def person(x, z, heading, coat="M_Coat", reach=0.0, cap="M_Hair"):
    """A worker of 1.75 m with human proportions (legs 0.86, torso 0.6, head 0.23)."""
    f = FLOOR if 0 <= x <= 14 and 0 <= z <= 20 else 0.0
    fx, fz = math.cos(heading), -math.sin(heading)          # forward
    sx, sz = -fz, fx                                         # side
    P = lambda fwd, up, side: (x + fx * fwd + sx * side, f + up, z + fz * fwd + sz * side)
    for side in (-0.1, 0.1):
        limb(P(0, 0.04, side), P(0.0, 0.48, side), 0.055, 0.065, "M_Trousers")
        limb(P(0, 0.48, side), P(0.0, 0.9, side * 0.9), 0.065, 0.085, "M_Trousers")
        box(*[v for v in (x + fx * 0.04 + sx * side - 0.06, x + fx * 0.04 + sx * side + 0.06)], f, f + 0.07,
            z + fz * 0.04 + sz * side - 0.06, z + fz * 0.04 + sz * side + 0.06, "M_Rubber", bevel=0.02)
    limb(P(0, 0.88, 0), P(0, 1.18, 0), 0.15, 0.17, coat, seg=12)              # waist → chest
    limb(P(0, 1.18, 0), P(0, 1.42, 0), 0.17, 0.12, coat, seg=12)              # chest → shoulders
    for side in (-0.21, 0.21):
        ball(P(0, 1.38, side), 0.06, coat)
        limb(P(0, 1.38, side), P(0.12 + reach * 0.5, 1.12, side * 1.05), 0.05, 0.045, coat)
        limb(P(0.12 + reach * 0.5, 1.12, side * 1.05), P(0.3 + reach, 1.02 + reach * 0.2, side * 0.8), 0.04, 0.035, coat)
        ball(P(0.32 + reach, 1.02 + reach * 0.2, side * 0.78), 0.04, "M_Skin")
    limb(P(0, 1.42, 0), P(0, 1.5, 0), 0.045, 0.045, "M_Skin")                # neck
    ball(P(0.01, 1.62, 0), 0.105, "M_Skin", squash=1.15)                     # head
    ball(P(-0.01, 1.68, 0), 0.11, cap, squash=0.6)                           # hair / cap


person(2.9, 4.5, -math.pi / 2, reach=0.25)                     # inspector at the Alda
person(6.0, 6.6, 0.0, reach=0.3)                               # inspector at the Luce/Noemi row
person(4.9, 10.25, math.pi / 2, coat="M_Workwear", reach=0.35)  # packer at the packing table
person(11.3, 1.8, -2.4, coat="M_Coat")                         # in the QC booth
person(16.4, 17.0, 2.2, coat="M_Vest", cap="M_Toolbox")         # yard marshal with a hard hat

# More planting south of the road (the site keeps going into the haze).
rect(-8, 36, 30.6, 38, 0.006, "M_Grass")
box(-8, 36, 0, 0.14, 30.6, 30.75, "M_Curb", bevel=0.035)
for i in range(9):                                                           # low hedge along the road
    x0 = 13.0 + i * 1.5
    box(x0, x0 + 1.35, 0, 0.6, 31.2, 31.75, "M_Foliage", bevel=0.2, segments=3)

# ----------------------------------------------------------------------------- movers
def forklift():
    """Fork heel at the origin, facing +x. Body / carriage are separate movable meshes."""
    g = "Forklift_Body"
    box(-2.25, -0.25, 0.18, 0.95, -0.55, 0.55, "M_Forklift", g, bevel=0.06)          # chassis
    box(-2.35, -1.6, 0.18, 1.25, -0.56, 0.56, "M_Steel", g, bevel=0.1)              # counterweight
    box(-1.55, -0.95, 0.95, 1.25, -0.25, 0.25, "M_Rubber", g, bevel=0.06)           # seat
    box(-1.55, -1.48, 1.25, 1.75, -0.25, 0.25, "M_Rubber", g, bevel=0.04)
    for sx in (-2.0, -0.5):                                                          # overhead guard posts
        for sz in (-0.5, 0.5):
            box(sx - 0.04, sx + 0.04, 0.95, 2.15, sz - 0.04, sz + 0.04, "M_Steel", g, bevel=0.01)
    box(-2.05, -0.45, 2.12, 2.2, -0.55, 0.55, "M_Steel", g, bevel=0.015)
    for k in range(4):
        box(-1.95 + k * 0.45, -1.9 + k * 0.45, 2.15, 2.18, -0.5, 0.5, "M_Steel", g, bevel=0)
    cyl(-0.7, 0.95, 1.35, 0.0, 0.025, "M_Steel", g, seg=8)                           # steering column
    cyl(-1.25, 2.2, 2.32, 0.0, 0.07, "M_Beacon", g, seg=12)                           # beacon
    for x, r in ((-0.55, 0.33), (-1.95, 0.27)):                                      # tyres
        for sz in (-1, 1):
            cyl(sz * (0.5 if r > 0.3 else 0.47), x - 0.18, x + 0.18, r, r, "M_Rubber", g, seg=24, axis="z") if False else None
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=r, radius2=r, depth=0.24)
            bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
            bmesh.ops.translate(bm, vec=S(x, r, sz * 0.5), verts=bm.verts)
            _obj("tyre", bm, "M_Rubber", g, 0.03)
    for sz in (-0.38, 0.38):                                                          # mast channels
        box(-0.2, -0.08, 0.12, 2.35, sz - 0.07, sz + 0.07, "M_Steel", g, bevel=0.01)
    box(-0.2, -0.08, 2.25, 2.35, -0.45, 0.45, "M_Steel", g, bevel=0.01)
    c = "Forklift_Carriage"
    box(-0.08, 0.0, 0.08, 0.95, -0.45, 0.45, "M_Steel", c, bevel=0.01)
    for k in range(3):
        box(-0.07, 0.0, 0.95 + k * 0.0, 1.25, -0.45 + k * 0.42, -0.41 + k * 0.42, "M_Steel", c, bevel=0)
    for sz in (-0.3, 0.3):
        box(0.0, 1.15, 0.05, 0.1, sz - 0.06, sz + 0.06, "M_Galv", c, bevel=0.01)
        box(-0.02, 0.06, 0.05, 0.75, sz - 0.06, sz + 0.06, "M_Galv", c, bevel=0.01)


def truck():
    """Parked at dock 2: trailer rear at the dock, cut at the section height like the walls."""
    g = "Truck_Body"
    zc, x0, x1 = 13.5, 14.4, 28.0
    w = 1.275
    box(x0, x1, FLOOR - 0.06, FLOOR, zc - w, zc + w, "M_Leveler", g, bevel=0.01)          # deck
    for sz in (-1, 1):
        box(x0, x1, FLOOR, CUT, zc + sz * w - (0.04 if sz > 0 else 0), zc + sz * w + (0 if sz > 0 else 0.04), "M_Trailer", g, bevel=0.01)
        for k in range(23):                                                              # side ribs
            x = x0 + 0.3 + k * 0.6
            box(x - 0.03, x + 0.03, FLOOR, CUT, zc + sz * (w + 0.03) - 0.015, zc + sz * (w + 0.03) + 0.015, "M_Trailer", g, bevel=0.004, segments=1)
        box(x0, x1, CUT, CUT + 0.02, zc + sz * w - 0.05, zc + sz * w + 0.05, "M_Section", g, bevel=0)
        box(x0, x1, FLOOR - 0.35, FLOOR - 0.06, zc + sz * (w - 0.1) - 0.05, zc + sz * (w - 0.1) + 0.05, "M_Steel", g, bevel=0.01)
        box(x0 - 0.02, x0 + 0.05, FLOOR - 0.1, CUT, zc + sz * w - 0.06, zc + sz * w + 0.06, "M_Steel", g, bevel=0.005)
        # Rear door swung open against the side.
        box(x0 + 0.05, x0 + 1.3, FLOOR, CUT, zc + sz * (w + 0.09) - 0.025, zc + sz * (w + 0.09) + 0.025, "M_Trailer", g, bevel=0.01)
    box(x1 - 0.06, x1, FLOOR, CUT, zc - w, zc + w, "M_Trailer", g, bevel=0.01)          # front wall
    box(x1 - 0.06, x1, CUT, CUT + 0.02, zc - w, zc + w, "M_Section", g, bevel=0)
    for ax in (16.2, 17.5, 18.8, 28.9, 30.9):                                           # axles + tyres
        for sz in (-1, 1):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.5, radius2=0.5, depth=0.55)
            bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
            bmesh.ops.translate(bm, vec=S(ax, 0.5, zc + sz * 0.95), verts=bm.verts)
            _obj("tyre", bm, "M_Rubber", g, 0.04)
    box(24.5, 24.6, 0, FLOOR - 0.3, zc - 0.9, zc - 0.8, "M_Steel", g, bevel=0)           # landing legs
    box(24.5, 24.6, 0, FLOOR - 0.3, zc + 0.8, zc + 0.9, "M_Steel", g, bevel=0)
    box(26.5, 31.6, 0.75, 1.05, zc - 0.5, zc + 0.5, "M_Steel", g, bevel=0.02)            # tractor frame
    for sz in (-1, 1):                                                                   # mudguards
        box(28.5, 31.3, 1.0, 1.1, zc + sz * 1.0 - 0.3, zc + sz * 1.0 + 0.3, "M_Steel", g, bevel=0.03)
    box(30.0, 32.35, 0.9, 3.75, zc - 1.25, zc + 1.25, "M_TruckCab", g, bevel=0.12)        # cab
    box(32.33, 32.37, 2.2, 3.35, zc - 1.12, zc + 1.12, "M_Glass", g, bevel=0)             # windscreen
    for sz in (-1, 1):
        box(30.9, 32.1, 2.25, 3.3, zc + sz * 1.25 - 0.02, zc + sz * 1.25 + 0.02, "M_Glass", g, bevel=0)
    box(30.0, 32.35, 3.75, 3.95, zc - 1.2, zc + 1.2, "M_TruckCab", g, bevel=0.08)         # roof fairing
    box(32.3, 32.45, 0.9, 1.25, zc - 1.25, zc + 1.25, "M_Steel", g, bevel=0.03)           # bumper
    anchor("anchor_truck", 21.2, FLOOR, zc)
    for k in range(4):
        anchor(f"anchor_slot_{k}", 26.7 - k * 1.3, FLOOR, zc)


def forklift_asset():
    """3dassets.dev CC0 counterbalance forklift (separate forks and wheels) + seated driver.
    Rotated to face +x with the fork heel at the origin; bevelled; materials mapped to the kit."""
    import glob
    fl = glob.glob(os.path.join(SRC, "parcel-depot", "*528c9054*.glb"))
    dr = glob.glob(os.path.join(SRC, "forklift-candidates", "*seated-forklift-driver*.glb"))
    if not fl:
        return False
    place_m = Matrix.Translation(Vector((-0.37, 0, 0))) @ Matrix.Rotation(math.pi / 2, 4, "Z")
    def bring(path, mapping, extra=Matrix.Identity(4)):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        out = []
        for o in new:
            if o.type != "MESH":
                continue
            in_forks = any(p.name == "forks" for p in [o.parent, o.parent.parent if o.parent else None] if p)
            mw = place_m @ extra @ o.matrix_world
            o.parent = None
            o.matrix_world = mw
            for o2 in scene.objects:
                o2.select_set(o2 == o)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            for slot in o.material_slots:
                if slot.material:
                    slot.material = MATS[mapping.get(slot.material.name.split(".")[0], "M_Steel")]
            for poly in o.data.polygons:
                poly.use_smooth = True
            mod = o.modifiers.new("bevel", "BEVEL")
            mod.width = 0.012
            mod.segments = 2
            mod.limit_method = "ANGLE"
            mod.angle_limit = math.radians(35)
            mod.harden_normals = True
            GROUPS.setdefault("Forklift_Carriage" if in_forks else "Forklift_Body", []).append(o)
            out.append(o)
        for o in new:
            if o not in out:
                bpy.data.objects.remove(o, do_unlink=True)
        USED_ASSETS.append(os.path.basename(path).rsplit(".", 1)[0])
    bring(fl[0], {"yellow": "M_Forklift", "charcoal": "M_Steel", "paint": "M_Galv", "steel": "M_Galv",
                  "red": "M_Beacon", "rubber": "M_Rubber"})
    if dr:
        bring(dr[0], {"dark": "M_Trousers", "blue": "M_Workwear", "yellow": "M_Vest", "skin": "M_Skin",
                      "steel": "M_Galv"}, Matrix.Translation(Vector((0, 0.55, 0.62))))
    return True


if not forklift_asset():
    forklift()
truck()
# The demo batch: pallet + two packed crates (Swift moves and clones it).
batch(0, 0, 0, group="Batch", layers=2)

anchor("anchor_forklift_home", 10.6, FLOOR, 9.2, heading=math.pi)
anchor("anchor_view", 14.0, FLOOR, 11.0)

# ----------------------------------------------------------------------------- finalize
def realize(group, name):
    objs = GROUPS[group]
    for o in scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.object.material_slot_remove_unused()
    ob.data.uv_layers.new(name="UVMap") if not ob.data.uv_layers else None
    return ob


static = realize("Static", "Static")
body = realize("Forklift_Body", "Forklift_Body")
carriage = realize("Forklift_Carriage", "Forklift_Carriage")
truck_body = realize("Truck_Body", "Truck_Body")
batch_ob = realize("Batch", "Batch")
for ob in (static, body, carriage, truck_body, batch_ob):
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=2.0)          # world-scale UV0 for tiled micro textures
    bpy.ops.object.mode_set(mode="OBJECT")

# ----------------------------------------------------------------------------- Poly Haven props
# Real downloaded CC0 assets (tmp/insight-poc-source, manifests there) placed into the visible
# scene, decimated, joined into the static mesh so they receive the same AO bake. Their
# materials keep their names; textures are resized into InsightAssets/textures and bound by name
# in the app (atelier_materials.json), so the USD carries no absolute texture paths.
TEX = os.path.join(OUT, "textures")
os.makedirs(TEX, exist_ok=True)
MATERIAL_MAP = {}


def save_texture(path, size, linear):
    name = os.path.basename(path).replace("_1k", "").rsplit(".", 1)[0] + ".jpg"
    dst = os.path.join(TEX, name)
    if not os.path.exists(dst):
        img = bpy.data.images.load(path)
        if linear:
            img.colorspace_settings.name = "Non-Color"
        if img.size[0] > size:
            img.scale(size, size)
        # Always 8-bit RGB: single-channel textures become R8Unorm_sRGB in SceneKit, which the
        # iOS simulator's Metal rejects.
        settings = scene.render.image_settings
        settings.file_format = "JPEG"
        settings.color_mode = "RGB"
        settings.color_depth = "8"
        settings.quality = 86
        img.save_render(dst, scene=scene)
        bpy.data.images.remove(img)
    return "textures/" + name


def load_asset(asset, keep=None, ratio=None, size=512, unit=1.0):
    """Import one Poly Haven glTF; returns prototype meshes (unlinked) with world transforms applied."""
    import json
    gltf = os.path.join(SRC, asset, f"{asset}_1k.gltf")
    if not os.path.exists(gltf):
        print("MISSING", gltf)
        return []
    USED_ASSETS.append(asset)
    g = json.load(open(gltf))
    for m in g.get("materials", []):
        if m["name"] in MATERIAL_MAP:
            continue
        p = m.get("pbrMetallicRoughness", {})
        uri = lambda t: g["images"][g["textures"][t["index"]]["source"]]["uri"] if t else None
        base, arm, nor = uri(p.get("baseColorTexture")), uri(p.get("metallicRoughnessTexture")), uri(m.get("normalTexture"))
        entry = {"asset": asset}
        if base and "opacity" not in base:
            entry["base"] = save_texture(os.path.join(SRC, asset, base), size, False)
        if arm:
            entry["arm"] = save_texture(os.path.join(SRC, asset, arm), size, True)
        if nor:
            entry["normal"] = save_texture(os.path.join(SRC, asset, nor), size, True)
        if "leaves" in m["name"]:
            entry["foliage"] = True
        elif m.get("alphaMode") == "BLEND":
            entry["grille"] = True
        MATERIAL_MAP[m["name"]] = entry
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=gltf)
    new = [o for o in bpy.data.objects if o not in before]
    protos = []
    for o in new:
        if o.type != "MESH" or (keep and o.name not in keep):
            continue
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = Matrix.Scale(unit, 4) @ mw
        for o2 in scene.objects:
            o2.select_set(o2 == o)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if ratio and ratio < 1:
            d = o.modifiers.new("dec", "DECIMATE")
            d.ratio = ratio
            bpy.ops.object.modifier_apply(modifier="dec")
        protos.append(o)
    for o in new:
        if o not in protos:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in protos:
        scene.collection.objects.unlink(o)
        for slot in o.material_slots:              # plain material, name kept for the app
            if slot.material and slot.material.use_nodes:
                nt = slot.material.node_tree
                for n in [n for n in nt.nodes if n.type == "TEX_IMAGE"]:
                    nt.nodes.remove(n)
    return protos


def place(protos, x, y, z, heading=0.0, offset=(0, 0, 0), scale=1.0):
    """Copy prototypes to scene position (x, y, z) rotated about the vertical axis."""
    out = []
    m = (Matrix.Translation(S(x, y, z)) @ Matrix.Rotation(heading, 4, "Z") @ Matrix.Scale(scale, 4)
         @ Matrix.Translation(Vector(offset)))
    for p in protos:
        c = p.copy()
        c.data = p.data.copy()
        c.matrix_world = m @ p.matrix_world
        scene.collection.objects.link(c)
        out.append(c)
    GROUPS.setdefault("Props", []).extend(out)
    return out


def bounds(protos):
    pts = [p.matrix_world @ Vector(c) for p in protos for c in p.bound_box]
    return Vector(map(min, *pts)), Vector(map(max, *pts))


HALF = math.pi / 2
# Overhead crane on the new runways above quality control (rails stubs replaced by our beams).
crane = load_asset("overhead_crane", keep={"overhead_crane", "overhead_crane_winch"}, ratio=0.3, size=512)
if crane:
    place(crane, CRANE_X, RAIL + 0.05 + 0.04 * CRANE_SCALE, CRANE_Z, scale=CRANE_SCALE)
# Rectangular ducts: straight 1.8 m sections along both far walls under the eaves.
duct = load_asset("modular_airduct_rectangular_01", keep={"modular_airduct_rectangular_01_tripple_01"}, ratio=0.45)
if duct:
    lo, hi = bounds(duct)
    ctr = (lo + hi) / 2
    centred = (-ctr.x, -ctr.y, -lo.z)
    for k in range(8):                     # clear of the crane bridge
        place(duct, 1.05, 7.25, 6.2 + k * 1.8, 0.0, centred)
# Pipe manifold on the west wall beside quality control.
pipes = load_asset("modular_industrial_pipes_01", ratio=0.6)
if pipes:
    lo, hi = bounds(pipes)
    place(pipes, 0.45, FLOOR + 2.6, 3.0, -HALF, (-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
# Security cameras: dock island pole and the north-east corner coping.
cam = load_asset("security_camera_01", keep={"security_camera_01"}, ratio=0.3)
if cam:
    place(cam, 17.6, 5.6, 10.1, -HALF)
    place(cam, 13.8, 7.95, 0.45, -HALF * 0.5)
# Electrical cabinet on the hall's north wall next to the inspector desk.
power = load_asset("power_box_01", ratio=0.15)
if power:
    lo, hi = bounds(power)
    place(power, 6.8, FLOOR + 1.2, 0.25 - lo.y, 0.0, (-(lo.x + hi.x) / 2, 0, -lo.z))
# Condensing units: on the booth roof and on a pad in the yard corner.
air = load_asset("exterior_aircon_unit", keep={"exterior_aircon_unit"}, ratio=0.35)
if air:
    lo, hi = bounds(air)
    centred = (-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)
    place(air, (BX0 + BX1) / 2, FLOOR + BH + 0.14, (BZ0 + BZ1) / 2, 0.0, centred)
    box(25.6, 30.0, 0, 0.18, -6.6, -5.2, "M_Curb", bevel=0.03)
    for k in range(2):
        place(air, 26.7 + k * 2.1, 0.18, -5.9, 0.0, centred)
# Concrete barriers protecting the yard edge along the road.
barrier = load_asset("concrete_road_barrier", ratio=0.06)
if barrier:
    for k in range(6):
        place(barrier, 19.0 + k * 2.0, 0.0, 23.9, 0.0)
# Steel shelving with plastic crates next to the booth, wooden crates at the stations.
shelves = load_asset("steel_frame_shelves_01", ratio=0.6, unit=0.1)
crate_p = load_asset("plastic_crate_01", ratio=0.06)
if shelves:
    lo, hi = bounds(shelves)
    for k, x in enumerate((8.0, 9.15)):
        place(shelves, x, FLOOR, 0.25 - lo.y + 0.05, 0.0, (-(lo.x + hi.x) / 2, 0, -lo.z))
        if crate_p:
            clo, chi = bounds(crate_p)
            levels = [FLOOR + 0.05 + h for h in (0.02, 0.72, 1.42)]
            for li, yy in enumerate(levels):
                for j in range(3):
                    if (k + li + j) % 4 == 3:
                        continue
                    place(crate_p, x - 0.36 + j * 0.36, yy, 0.55, 0.0, (-(clo.x + chi.x) / 2, -(clo.y + chi.y) / 2, -clo.z))
wood = load_asset("wooden_crate_01", ratio=0.5)
if wood:
    lo, hi = bounds(wood)
    c0 = (-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)
    h = hi.z - lo.z
    place(wood, 2.6, FLOOR, 8.9, HALF + 0.1, c0)
    place(wood, 2.6, FLOOR + h, 8.9, HALF - 0.08, c0)
    place(wood, 2.65, FLOOR, 9.8, HALF, c0)
truck_hand = load_asset("hand_truck", ratio=0.25)
if truck_hand:
    place(truck_hand, 13.1, FLOOR, 17.6, 2.4)

# Salini Ninfea 02 countertop basins (official 540 × 447 × 120 mm; Salini asset, rights retained,
# not CC0 — see ASSETS.json): four on a dedicated basin inspection table by the north wall.
sink_obj = os.path.join(SRC, "salini-ninfea-02", "Ninfea-02-2015-obj.obj")
if os.path.exists(sink_obj):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=sink_obj)
    parts = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in scene.objects:
        o.select_set(o in parts)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    sink = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = sink.data
    lo = Vector(map(min, *[v.co for v in me.vertices]))
    hi = Vector(map(max, *[v.co for v in me.vertices]))
    size = hi - lo
    thin = min(range(3), key=lambda i: size[i])          # the 120 mm axis must be vertical (Blender Z)
    if thin != 2:
        sink.rotation_euler = (math.pi / 2, 0, 0) if thin == 1 else (0, math.pi / 2, 0)
        bpy.ops.object.transform_apply(rotation=True)
        lo = Vector(map(min, *[v.co for v in me.vertices]))
        hi = Vector(map(max, *[v.co for v in me.vertices]))
        size = hi - lo
    k = 0.54 / max(size.x, size.y)
    if size.y > size.x:                                  # 540 mm along the table (scene x)
        sink.rotation_euler = (0, 0, math.pi / 2)
        bpy.ops.object.transform_apply(rotation=True)
        lo = Vector(map(min, *[v.co for v in me.vertices]))
        hi = Vector(map(max, *[v.co for v in me.vertices]))
    for v in me.vertices:
        v.co = (v.co - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))) * k
    me.materials.clear()
    me.materials.append(MATS["M_Ceramic"])
    for poly in me.polygons:
        poly.use_smooth = True
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > 12000:
        d = sink.modifiers.new("dec", "DECIMATE")
        d.ratio = 12000 / tris
        bpy.ops.object.modifier_apply(modifier="dec")
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    print("SINK size m", tuple(round(v * k, 3) for v in size), "tris", sum(len(p.vertices) - 2 for p in me.polygons))
    scene.collection.objects.unlink(sink)
    USED_ASSETS.append("salini-ninfea-02")
    # Basin inspection table with a lamp bar.
    box(1.2, 3.8, FLOOR + 0.82, FLOOR + 0.86, 0.75, 1.55, "M_Desk", bevel=0.015)
    for sx in (1.3, 3.7):
        for sz in (0.82, 1.48):
            box(sx - 0.03, sx + 0.03, FLOOR, FLOOR + 0.82, sz - 0.03, sz + 0.03, "M_Steel", bevel=0.005)
    for sx in (1.25, 3.75):
        cyl(sx, FLOOR + 0.86, FLOOR + 2.2, 0.8, 0.02, "M_Steel", seg=8, bevel=0)
    box(1.2, 3.8, FLOOR + 2.2, FLOOR + 2.26, 0.72, 0.9, "M_Steel", bevel=0.005)
    box(1.3, 3.7, FLOOR + 2.19, FLOOR + 2.2, 0.75, 0.87, "M_Lamp", bevel=0)
    anchor("anchor_light_qc_5", 2.5, FLOOR + 2.1, 1.0)
    for k2 in range(4):
        place([sink], 1.57 + k2 * 0.62, FLOOR + 0.86, 1.15, 0.0)

# Join the props into the static mesh (UV0 = their own texture UVs).
props = GROUPS.get("Props", [])
print("PART kit-static", sum(len(p.vertices) - 2 for p in static.data.polygons))
from collections import Counter
_c = Counter()
for o in props:
    _c[o.data.materials[0].name if o.data.materials else "?"] += sum(len(p.vertices) - 2 for p in o.data.polygons)
print("PART props", sum(_c.values()), dict(_c))
if props:
    for o in scene.objects:
        o.select_set(o in props or o == static)
    bpy.context.view_layer.objects.active = static
    for o in props:
        if o.data.uv_layers and o.data.uv_layers[0].name != "UVMap":
            o.data.uv_layers[0].name = "UVMap"
    bpy.ops.object.join()
    static = bpy.context.view_layer.objects.active
    static.name = static.data.name = "Static"

# ----------------------------------------------------------------------------- tree
# Poly Haven tree_small_02 (CC0): 1.94 M triangles of real leaves. Whole twigs are kept at random
# (~6 %), each grown in place so the crown stays full, then lightly decimated; branches and trunk
# decimated. One prototype «Tree»; the app instances it at anchor_tree_* (shared geometry).
TREE_KEEP = float(argv[argv.index("--tree-keep") + 1]) if "--tree-keep" in argv else 0.0006
tree_proto = None
tree_parts = load_asset("tree_small_02", size=512)
if tree_parts:
    t = tree_parts[0]
    scene.collection.objects.link(t)
    for o in scene.objects:
        o.select_set(o == t)
    bpy.context.view_layer.objects.active = t
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in scene.objects if o.type == "MESH" and o.name.startswith(t.name.split(".")[0])]
    for part in parts:
        for o in scene.objects:
            o.select_set(o == part)
        bpy.context.view_layer.objects.active = part
        name = part.active_material.name
        if "leaves" in name:
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_mode(type="FACE")
            bpy.ops.mesh.select_all(action="DESELECT")
            bpy.ops.mesh.select_random(ratio=TREE_KEEP, seed=7, action="SELECT")
            bpy.ops.mesh.select_linked(delimit=set())
            bpy.ops.mesh.select_all(action="INVERT")
            bpy.ops.mesh.delete(type="FACE")
            bpy.ops.object.mode_set(mode="OBJECT")
            bm = bmesh.new()
            bm.from_mesh(part.data)
            seen = set()
            for f0 in bm.faces:                       # grow every kept twig about its own centre
                if f0.index in seen:
                    continue
                stack, island = [f0], []
                seen.add(f0.index)
                while stack:
                    f = stack.pop()
                    island.append(f)
                    for e in f.edges:
                        for g in e.link_faces:
                            if g.index not in seen:
                                seen.add(g.index)
                                stack.append(g)
                verts = {v for f in island for v in f.verts}
                c = sum((v.co for v in verts), Vector()) / len(verts)
                for v in verts:
                    v.co = c + (v.co - c) * 1.6
            bm.to_mesh(part.data)
            bm.free()
            ratio = 0.6
        else:
            ratio = 0.12 if "branch" in name else 0.35
        d = part.modifiers.new("dec", "DECIMATE")
        d.ratio = ratio
        bpy.ops.object.modifier_apply(modifier="dec")
        for poly in part.data.polygons:
            poly.use_smooth = True
    for o in scene.objects:
        o.select_set(o in parts)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    tree_proto = bpy.context.view_layer.objects.active
    tree_proto.name = tree_proto.data.name = "Tree"
    while len(tree_proto.data.uv_layers) > 1:
        tree_proto.data.uv_layers.remove(tree_proto.data.uv_layers[-1])
    print("PART Tree", sum(len(p.vertices) - 2 for p in tree_proto.data.polygons))
    for k, (x, z, rot, sc) in enumerate(TREE_SPOTS):
        e = anchor(f"anchor_tree_{k}", x, 0.0, z, heading=rot)
        e.scale = (sc, sc, sc)

# Tiled ground materials (app maps them in world metres on UV0).
for mat, folder, tile in (("M_Floor", "smooth_concrete_floor", 2.0), ("M_Asphalt", "clean_asphalt", 2.0)):
    base = os.path.join(SRC, folder, f"{folder}_diff_1k.jpg")
    if os.path.exists(base):
        USED_ASSETS.append(folder)
        MATERIAL_MAP[mat] = {
            "asset": folder, "tile": tile,
            "base": save_texture(base, 1024, False),
            "rough": save_texture(os.path.join(SRC, folder, f"{folder}_rough_1k.jpg"), 512, True),
            "normal": save_texture(os.path.join(SRC, folder, f"{folder}_nor_gl_1k.jpg"), 512, True),
        }
hdr = os.path.join(SRC, "factory_yard", "factory_yard_1k.hdr")
if os.path.exists(hdr):
    import shutil
    shutil.copyfile(hdr, os.path.join(OUT, "factory_yard_1k.hdr"))
    USED_ASSETS.append("factory_yard")

root = bpy.data.objects.new("Forklift", None)
scene.collection.objects.link(root)
body.parent = root
carriage.parent = root
truck_root = bpy.data.objects.new("Truck", None)
scene.collection.objects.link(truck_root)
truck_body.parent = truck_root

# Lightmap UV + AO bake for the static scene only. Only architecture and ground get atlas space;
# props, people and foliage still occlude (they are in the bake scene) but their own lightmap UVs
# point at a white corner of the atlas, so thousands of tiny islands never starve the floor.
NO_ATLAS = {"M_Foliage", "M_Bark", "M_Coat", "M_Vest", "M_Trousers", "M_Skin", "M_Hair", "M_Lamp",
            "M_Screen", "M_GlassClear", "M_Toolbox", "M_Workwear", "M_Rubber", "M_Ceramic"} | set(MATERIAL_MAP) - {"M_Floor", "M_Asphalt"}
me = static.data
me.uv_layers.new(name="Lightmap")
me.uv_layers.active = me.uv_layers["Lightmap"]
atlas_index = {i for i, slot in enumerate(static.material_slots) if slot.material and slot.material.name not in NO_ATLAS}
for poly in me.polygons:
    poly.select = poly.material_index in atlas_index
for o in scene.objects:
    o.select_set(o == static)
bpy.context.view_layer.objects.active = static
bpy.ops.object.mode_set(mode="EDIT")
bpy.context.tool_settings.mesh_select_mode = (False, False, True)
PACK = argv[argv.index("--pack") + 1] if "--pack" in argv else "concave"
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003, area_weight=1.0, scale_to_bounds=False)
bpy.ops.mesh.select_all(action="DESELECT")
bpy.ops.object.mode_set(mode="OBJECT")
for poly in me.polygons:
    poly.select = poly.material_index in atlas_index
bpy.ops.object.mode_set(mode="EDIT")
bpy.context.scene.tool_settings.use_uv_select_sync = True
bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, scale=True, margin_method="FRACTION",
                        margin=0.002, shape_method=PACK.upper(), merge_overlap=False)
bpy.context.scene.tool_settings.use_uv_select_sync = False
bpy.ops.object.mode_set(mode="OBJECT")
uv = me.uv_layers["Lightmap"].data
for poly in me.polygons:
    if poly.material_index not in atlas_index:
        for li in poly.loop_indices:
            uv[li].uv = (0.9995, 0.9995)
me.uv_layers.active = me.uv_layers["UVMap"]
me.uv_layers["UVMap"].active_render = True
_u = [uv[li].uv for p in me.polygons if p.material_index in atlas_index for li in p.loop_indices]
_area = sum(abs(sum((uv[p.loop_indices[i]].uv.x * uv[p.loop_indices[(i + 1) % len(p.loop_indices)]].uv.y
                     - uv[p.loop_indices[(i + 1) % len(p.loop_indices)]].uv.x * uv[p.loop_indices[i]].uv.y)
                    for i in range(len(p.loop_indices))) / 2) for p in me.polygons if p.material_index in atlas_index)
print("ATLAS uv bounds", min(v.x for v in _u), min(v.y for v in _u), max(v.x for v in _u), max(v.y for v in _u), "coverage", round(_area, 3))
print("ATLAS faces", sum(1 for p in me.polygons if p.material_index in atlas_index), "of", len(me.polygons))

os.makedirs(OUT, exist_ok=True)
LIGHTMAPPED = sorted(static.material_slots[i].material.name for i in atlas_index)
GI_SAMPLES = int(argv[argv.index("--gi-samples") + 1]) if "--gi-samples" in argv else 1024
GI_RANGE = 4.0                                   # encoded irradiance range (see the app's decoder)
SUN_TO = S(0.6, 0.78, -0.4).normalized()        # same sun as the app (ShippingAtelierScene.setupLights)
SUN_STRENGTH = 2.3 * math.pi                     # app sun 2300 ≈ 2.3 × the normalised sky
NIGHT_SKY = (0.035 * 0.62, 0.035 * 0.74, 0.035 * 1.0)


def bake_gi():
    """Irradiance lightmaps for SceneKit's selfIllumination (it replaces only the diffuse IBL;
    specular IBL and the real-time sun stay live — measured, no double count).
      day   = sky (direct + indirect) + sun (indirect only; its direct light and shadows are live)
      night = dim tinted sky + static lamps (direct + indirect); live spots light only the movers
    Colour is excluded (light only); the app multiplies by albedo. Radiance .hdr, linear."""
    import numpy as np
    hdr_path = os.path.join(SRC, "factory_yard", "factory_yard_1k.hdr")
    src = bpy.data.images.load(hdr_path)
    w, h = src.size
    px = np.empty(w * h * 4, dtype=np.float32)
    src.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    lum = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    mean = float(lum.mean())
    clamp = 6.0 * mean                                   # the HDRI sun disc is replaced by our sun
    scale = np.minimum(1.0, clamp / np.maximum(lum, 1e-6))
    px[:, :3] *= scale[:, None] / mean
    sky = bpy.data.images.new("sky_clamped", w, h, float_buffer=True, is_data=True)
    sky.pixels.foreach_set(px.ravel())
    sky.pack()

    def world(strength):
        wd = bpy.data.worlds.new("gi")
        wd.use_nodes = True
        nt = wd.node_tree
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = sky
        bg = nt.nodes["Background"]
        nt.links.new(env.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = strength
        scene.world = wd

    # Glass lets light through in the bake; lamps emit only for the night pass.
    for name in ("M_GlassClear", "M_Window"):
        b = MATS[name].node_tree.nodes["Principled BSDF"]
        b.inputs["Transmission Weight"].default_value = 1.0
        b.inputs["Roughness"].default_value = 0.05
    lamp = MATS["M_Lamp"].node_tree.nodes["Principled BSDF"]
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = SUN_STRENGTH
    sun.data.angle = math.radians(0.6)
    sun.rotation_euler = (-SUN_TO).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    spots = []
    for e in GROUPS.get("Anchors", []):
        if not e.name.startswith("anchor_light_"):
            continue
        kind = e.name.split("_")[2]
        power = {"qc": 120, "wall": 600, "pole": 900}.get(kind, 300)
        sp = bpy.data.objects.new("bake_" + e.name, bpy.data.lights.new("bake_" + e.name, "SPOT"))
        sp.data.energy = power
        sp.data.spot_size = math.radians(110 if kind != "qc" else 120)
        sp.data.spot_blend = 0.7
        sp.data.color = (1.0, 0.86, 0.68)
        sp.data.shadow_soft_size = 0.15
        sp.location = e.location
        aim = Vector((0, 0, -1)) if kind != "wall" else (S(7, FLOOR, 10) - e.location).normalized()
        sp.rotation_euler = aim.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(sp)
        spots.append(sp)

    def bake(passes):
        img = bpy.data.images.new("gi", SIZE, SIZE, float_buffer=True, is_data=True)
        img.generated_color = (0, 0, 0, 0)          # baked texels (and margins) get alpha 1
        for slot in static.material_slots:
            nt = slot.material.node_tree
            n = nt.nodes.new("ShaderNodeTexImage")
            n.image = img
            nt.nodes.active = n
        for o in scene.objects:
            o.select_set(o == static)
        bpy.context.view_layer.objects.active = static
        bpy.ops.object.bake(type="DIFFUSE", pass_filter=passes, uv_layer="Lightmap", margin=8,
                            use_clear=True, target="IMAGE_TEXTURES")
        out = np.empty(SIZE * SIZE * 4, dtype=np.float32)
        img.pixels.foreach_get(out)
        for slot in static.material_slots:
            nt = slot.material.node_tree
            for n in [n for n in nt.nodes if n.type == "TEX_IMAGE"]:
                nt.nodes.remove(n)
        bpy.data.images.remove(img)
        return out.reshape(SIZE, SIZE, 4)

    scene.cycles.samples = GI_SAMPLES
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 4
    lamp.inputs["Emission Strength"].default_value = 0.0
    for sp in spots:
        sp.hide_render = True
    sun.hide_render = True
    world(1.0)
    sky_light = bake({"DIRECT", "INDIRECT"})
    sun.hide_render = False
    world(0.0)
    sun_bounce = bake({"INDIRECT"})
    sun.hide_render = True
    lamp.inputs["Emission Color"].default_value = (1.0, 0.92, 0.8, 1)
    lamp.inputs["Emission Strength"].default_value = 25.0
    for sp in spots:
        sp.hide_render = False
    lamps = bake({"DIRECT", "INDIRECT"})
    for sp in spots:
        sp.hide_render = True
    lamp.inputs["Emission Strength"].default_value = 0.0

    mask = (sky_light[:, :, 3] > 0.5).astype(np.float32)

    def denoise(rgb, sigma=1.3):
        """Normalised Gaussian blur inside the baked islands (no bleed into empty atlas space):
        removes the residual path-tracing grain of the low-frequency irradiance."""
        r = int(3 * sigma)
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2).astype(np.float32)
        k /= k.sum()
        def blur(a):
            out = np.zeros_like(a)
            for i, w in enumerate(k):
                out += w * np.roll(a, i - r, axis=0)
            a2 = np.zeros_like(out)
            for i, w in enumerate(k):
                a2 += w * np.roll(out, i - r, axis=1)
            return a2
        m = blur(mask)
        out = np.stack([blur(rgb[:, :, c] * mask) for c in range(3)], axis=2) / np.maximum(m, 1e-4)[:, :, None]
        return np.where(mask[:, :, None] > 0, out, rgb[:, :, :3])

    day = denoise(sky_light + sun_bounce)
    night = denoise(sky_light * np.array([*NIGHT_SKY, 1.0], dtype=np.float32) + lamps)
    # 8-bit PNG, gamma 2.2 over the range 0…GI_RANGE: smooth irradiance compresses ~3× better
    # than Radiance RLE, with finer steps in the darks (the app decodes it back to linear).
    for name, data in (("atelier_gi_day.png", day), ("atelier_gi_night.png", night)):
        enc = np.clip(data / GI_RANGE, 0, 1) ** (1 / 2.2)
        rgba = np.concatenate([enc, np.ones((SIZE, SIZE, 1), np.float32)], axis=2)
        img = bpy.data.images.new(name, SIZE, SIZE, float_buffer=False, is_data=True)
        img.pixels.foreach_set(np.ascontiguousarray(rgba).ravel())
        img.filepath_raw = os.path.join(OUT, name)
        img.file_format = "PNG"
        img.save()
        print("GI", name, "mean", float(data.mean()), "p99", float(np.percentile(data, 99)),
              "clipped", float((data > GI_RANGE).mean()))
    for name in ("M_GlassClear", "M_Window"):
        MATS[name].node_tree.nodes["Principled BSDF"].inputs["Transmission Weight"].default_value = 0.0
    bpy.data.objects.remove(sun, do_unlink=True)
    for sp in spots:
        bpy.data.objects.remove(sp, do_unlink=True)


if BAKE:
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception as e:  # CPU fallback
        print("GPU unavailable:", e)
    scene.cycles.samples = SAMPLES
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.light_settings.distance = 2.5
    for o in (body, carriage, truck_body, batch_ob):
        o.hide_render = True
    bake_only = []
    if tree_proto:                      # the trees occlude in the bake at their real places
        tree_proto.hide_render = True
        for (x, z, rot, sc) in TREE_SPOTS:
            c = tree_proto.copy()
            c.hide_render = False
            c.matrix_world = Matrix.Translation(S(x, 0, z)) @ Matrix.Rotation(rot, 4, "Z") @ Matrix.Scale(sc, 4)
            scene.collection.objects.link(c)
            bake_only.append(c)
    img = bpy.data.images.new("atelier_ao", SIZE, SIZE, float_buffer=False, is_data=True)
    img.generated_color = (1, 1, 1, 1)          # unbaked texels (and the props' corner) = no occlusion
    for slot in static.material_slots:
        nt = slot.material.node_tree
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        nt.nodes.active = n
    for o in scene.objects:
        o.select_set(o == static)
    bpy.context.view_layer.objects.active = static
    bpy.ops.object.bake(type="AO", uv_layer="Lightmap", margin=6, use_clear=False, target="IMAGE_TEXTURES")
    settings = scene.render.image_settings
    settings.file_format = "PNG"
    settings.color_mode = "RGB"          # RGB 8-bit for Metal (no single-channel textures)
    settings.color_depth = "8"
    settings.compression = 90
    img.save_render(os.path.join(OUT, "atelier_ao.png"), scene=scene)
    for slot in static.material_slots:
        nt = slot.material.node_tree
        for n in [n for n in nt.nodes if n.type == "TEX_IMAGE"]:
            nt.nodes.remove(n)
    bake_gi()
    for o in bake_only:
        bpy.data.objects.remove(o, do_unlink=True)
    if tree_proto:
        tree_proto.hide_render = False
    for o in (body, carriage, truck_body, batch_ob):
        o.hide_render = False

# Geometry without lightmap texels (props, people, basins, lamps, glass) becomes «StaticProps»:
# it has no baked light, so the app lets the live night spots light it (static light ownership:
# baked for «Static», live for «StaticProps» — never both).
for o in scene.objects:
    o.select_set(o == static)
bpy.context.view_layer.objects.active = static
for poly in static.data.polygons:
    poly.select = poly.material_index not in atlas_index
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.separate(type="SELECTED")
bpy.ops.object.mode_set(mode="OBJECT")
props_ob = next(o for o in bpy.context.selected_objects if o != static)
props_ob.name = props_ob.data.name = "StaticProps"
for o in (static, props_ob):
    for o2 in scene.objects:
        o2.select_set(o2 == o)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.material_slot_remove_unused()

usd = os.path.join(OUT, "atelier_kit.usdc")
bpy.ops.wm.usd_export(
    filepath=usd, selected_objects_only=False, export_uvmaps=True, rename_uvmaps=True,
    export_materials=True, generate_preview_surface=True, export_normals=True,
    convert_orientation=True, export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y",
    export_lights=False, export_cameras=False, triangulate_meshes=False)
import json
json.dump({"materials": MATERIAL_MAP, "sources": sorted(set(USED_ASSETS)), "lightmapped": LIGHTMAPPED,
           "gi": {"day": "atelier_gi_day.png", "night": "atelier_gi_night.png", "range": GI_RANGE, "gamma": 2.2},
           "license": "Poly Haven CC0 1.0 (polyhaven.com/license); manifests in tmp/insight-poc-source"},
          open(os.path.join(OUT, "atelier_materials.json"), "w"), indent=1, sort_keys=True)
# Bundled manifest of the subset actually shipped (the full download catalogue stays in research).
shipped = []
for asset in sorted(set(USED_ASSETS)):
    mf = os.path.join(SRC, f"{asset}-manifest.json")
    m = json.load(open(mf)) if os.path.exists(mf) else {}
    meta = m.get("metadata", {})
    if not m:   # 3dassets.dev GLB (forklift, driver): look it up in the pack manifests
        for pack in ("parcel-manifest.json", "forklift-candidates-manifest.json"):
            pf = os.path.join(SRC, pack)
            if not os.path.exists(pf):
                continue
            entries = json.load(open(pf))
            entries = entries["assets"] if isinstance(entries, dict) else entries
            hit = next((e for e in entries if e.get("slug") and e["slug"] in asset), None)
            if hit:
                lic = hit.get("license", {})
                shipped.append({
                    "asset": asset, "title": hit.get("title"), "source": hit.get("url"),
                    "license": "CC0-1.0" if lic.get("slug") == "cc0-1.0" else lic.get("name"),
                    "license_url": lic.get("url"), "authors": [hit.get("contributor", {}).get("name")],
                    "ai_generated": hit.get("aiGenerated"),
                    "source_files": [{"url": hit.get("cdnUrl"), "sha256": hit.get("sha256")}],
                    "use": "bevelled and recoloured into the forklift (Forklift_Body / Forklift_Carriage)",
                })
                break
        continue
    if asset.startswith("salini-"):
        shipped.append({
            "asset": asset, "source": m.get("source"), "public_model": m.get("public_model"),
            "license": m.get("license"), "rights": "Salini — rights retained (not CC0); product visualisation",
            "dimensions_mm": m.get("dimensions_mm"),
            "source_files": [{"url": f.get("source_path"), "sha256": f.get("sha256")} for f in m.get("files", [])],
            "use": "four basins on the basin inspection table, normalised to 540 mm, joined into atelier_kit.usdc",
        })
        continue
    shipped.append({
        "asset": asset, "source": m.get("source"), "license": m.get("license"),
        "license_url": m.get("license_url"), "authors": sorted(meta.get("authors", {}).keys()),
        "source_files": [{"url": f.get("url"), "sha256": f.get("sha256")} for f in m.get("files", [])],
        "use": "decimated geometry joined into atelier_kit.usdc; textures resized into textures/"
               if asset not in ("factory_yard", "smooth_concrete_floor", "clean_asphalt")
               else "environment light" if asset == "factory_yard" else "tiled ground material",
    })
json.dump({"generated_by": "ios/tools/insight_poc/build_atelier_kit.py", "assets": shipped,
           "own_work": "architecture, racking, yard, forklift, truck and batch are procedural (this script)",
           "products": "Alda 160×70, Mona 170, Luce 170, Noemi 170, Sofia 150 — Salini catalogue USDZ "
                       "(CatalogMedia/models), loaded at runtime; Ninfea 02 basin in the kit"},
          open(os.path.join(OUT, "ASSETS.json"), "w"), indent=1, ensure_ascii=False)
tris = sum(len(p.vertices) - 2 for o in (static, props_ob, body, carriage, truck_body, batch_ob) for p in o.data.polygons)
for o in (static, props_ob, body, carriage, truck_body, batch_ob):
    print("PART", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons))
print("KIT", usd, "triangles", tris, "static materials", [s.material.name for s in static.material_slots])
