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
    "M_Toolbox": (0.85, 0.6, 0.2), "M_Ceramic": (0.92, 0.92, 0.91), "M_Coping": (0.07, 0.08, 0.09),
    "M_Joint": (0.3, 0.3, 0.3), "M_Frame": (0.55, 0.57, 0.6), "M_LampHousing": (0.8, 0.8, 0.8), "M_Roof": (0.18, 0.19, 0.2), "M_Facade": (0.62, 0.64, 0.65),
    "M_Curtain": (0.62, 0.66, 0.70), "M_Chassis": (0.05, 0.06, 0.07), "M_TrailerRoof": (0.75, 0.77, 0.78),
    "M_Grille": (0.03, 0.035, 0.04), "M_Headlight": (0.9, 0.9, 0.85), "M_TailLight": (0.5, 0.04, 0.03),
    "M_Window": (0.55, 0.62, 0.68), "M_GlassClear": (0.8, 0.85, 0.88), "M_BoothFrame": (0.86, 0.86, 0.85),
    "M_Cabinet": (0.82, 0.83, 0.81), "M_PipeWater": (0.2, 0.36, 0.48),
    "M_Strap": (0.03, 0.035, 0.04),
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


def pipe_z(x, y, z0, z1, r, mat, seg=16):
    """Horizontal cylinder along scene z at (x, y)."""
    return cyl(x, z0, z1, y, r, mat, seg=seg, bevel=0, axis="z")


def pipe_x(y, z, x0, x1, r, mat, seg=16):
    """Horizontal cylinder along scene x at height y, depth z."""
    return cyl(y, x0, x1, z, r, mat, seg=seg, bevel=0, axis="x")


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


def text(body, x, z, size, mat, rot=0.0, y=0.012, stand=False):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("txt", cu)
    scene.collection.objects.link(ob)
    ob.location = S(x, y, z)
    ob.rotation_euler = (math.pi / 2 if stand else 0, 0, rot)   # standing: faces +z (or rot about the vertical)
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


# Models with their own module (forklift, workers): executed into this namespace.
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "atelier_models.py")).read(), globals())
if "--proto" in argv:                       # quick look-development scene (tmp/ scripts)
    exec(open(argv[argv.index("--proto") + 1]).read(), globals())
    raise SystemExit


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

# ----------------------------------------------------------------------------- neighbour hall
# Context only (not interactive): a finished production block north of the yard with a ribbed
# facade, a gravel roof behind a parapet, skylight strips and rooftop units — what the
# references read as «real plant».
rect(14.2, 40, -24, -8, 0.004, "M_Asphalt")
NX0, NX1, NZ0, NZ1, NH = 18.0, 38.0, -22.0, -10.0, 9.0
box(NX0, NX1, 0, 0.9, NZ0, NZ1, "M_Plinth", bevel=0.04)
box(NX0 + 0.02, NX1 - 0.02, 0.9, NH, NZ0 + 0.02, NZ1 - 0.02, "M_Facade", bevel=0.05)
for k in range(int((NX1 - NX0) / 1.2)):                                    # vertical facade ribs
    x = NX0 + 0.6 + k * 1.2
    box(x - 0.04, x + 0.04, 0.9, NH, NZ1 - 0.02, NZ1 + 0.03, "M_Facade", bevel=0.01, segments=1)
for k in range(int((NZ1 - NZ0) / 1.2)):
    z = NZ0 + 0.6 + k * 1.2
    box(NX0 - 0.03, NX0 + 0.02, 0.9, NH, z - 0.04, z + 0.04, "M_Facade", bevel=0.01, segments=1)
box(NX0 + 1.0, NX1 - 1.0, 6.0, 7.2, NZ1 - 0.04, NZ1 + 0.02, "M_Window", bevel=0)       # ribbon window
box(NX0 - 0.1, NX1 + 0.1, NH, NH + 0.6, NZ0 - 0.1, NZ1 + 0.1, "M_Coping", bevel=0.03)  # parapet
box(NX0 + 0.2, NX1 - 0.2, NH, NH + 0.45, NZ0 + 0.2, NZ1 - 0.2, "M_Roof", bevel=0.01)  # gravel roof
for k in range(4):                                                          # skylight strips
    x0 = NX0 + 2.5 + k * 4.2
    box(x0, x0 + 1.4, NH + 0.45, NH + 0.85, NZ0 + 2.0, NZ1 - 2.0, "M_Window", bevel=0.05)
    box(x0 - 0.06, x0 + 1.46, NH + 0.45, NH + 0.55, NZ0 + 1.95, NZ1 - 1.95, "M_Galv", bevel=0.01)
for x in (24.0, 30.0):
    box(x - 1.6, x + 1.6, 0.0, 4.2, NZ1 - 0.03, NZ1 + 0.06, "M_Steel", bevel=0.02)
    for y in range(14):
        box(x - 1.5, x + 1.5, 0.1 + y * 0.29, 0.36 + y * 0.29, NZ1 + 0.06, NZ1 + 0.09, "M_Galv", bevel=0.01, segments=1)
    box(x - 2.0, x + 2.0, 4.4, 4.55, NZ1, NZ1 + 1.4, "M_Coping", bevel=0.02)          # canopy
text("salini", (NX0 + NX1) / 2 + 3.0, NZ1 + 0.035, 1.7, "M_Coping", stand=True, y=6.6)   # facade lettering
anchor("anchor_neighbour_roof", (NX0 + NX1) / 2, NH + 0.45, (NZ0 + NZ1) / 2)

# ----------------------------------------------------------------------------- hall shell
box(0, 14.25, 0, FLOOR, 0, 20.25, "M_Slab", bevel=0.07)           # raised dock-height slab
rect(0.25, 13.75, 0.25, 19.75, FLOOR + 0.003, "M_Floor")
for x in (4.75, 9.25):                                                         # saw-cut joints
    rect(x - 0.008, x + 0.008, 0.25, 19.75, FLOOR + 0.0045, "M_Joint")
for z in (6.6, 13.2):
    rect(0.25, 13.75, z - 0.008, z + 0.008, FLOOR + 0.0045, "M_Joint")
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
box(-0.05, 14.05, TOP, TOP + 0.12, -0.05, 0.32, "M_Coping", bevel=0.025)   # coping
box(-0.05, 0.32, TOP, TOP + 0.12, -0.05, 20.05, "M_Galv", bevel=0.01)
# Near walls cut at CUT with a darker section cap; openings for two docks and a door.
def cut_wall_x(z0, z1):   # east wall, x 13.75..14.0
    box(13.72, 14.0, FLOOR, FLOOR + 1.0, z0, z1, "M_Plinth", bevel=0.04)
    box(13.75, 14.0, FLOOR + 1.0, CUT, z0, z1, "M_Panel", bevel=0.03)
    box(13.75, 14.0, CUT, CUT + 0.02, z0, z1, "M_Coping", bevel=0)
def cut_wall_z(x0, x1):   # south wall, z 19.75..20.0
    box(x0, x1, FLOOR, FLOOR + 1.0, 19.72, 20.0, "M_Plinth", bevel=0.04)
    box(x0, x1, FLOOR + 1.0, CUT, 19.75, 20.0, "M_Panel", bevel=0.03)
    box(x0, x1, CUT, CUT + 0.02, 19.75, 20.0, "M_Coping", bevel=0)
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
        box(13.7, 14.05, CUT, CUT + 0.02, zj - 0.1, zj + 0.1, "M_Coping", bevel=0)
    box(13.2, 14.25, FLOOR, FLOOR + 0.03, z0 + 0.1, z1 - 0.1, "M_Leveler", bevel=0.01)   # leveler
    for zz in (z0 - 0.45, z1 + 0.05):                                    # shelter pads, cut
        box(14.0, 14.6, FLOOR - 0.1, CUT, zz, zz + 0.4, "M_Rubber", bevel=0.05)
    for zz in (z0 + 0.25, z1 - 0.5):                                      # bumpers
        box(14.25, 14.38, 0.75, 1.15, zz, zz + 0.25, "M_Rubber", bevel=0.02)
    box(14.25, 14.3, 0.2, 1.15, z0 + 0.1, z1 - 0.1, "M_Galv", bevel=0.005)   # pit face plate
anchor("anchor_dock_1", 14.0, FLOOR, 6.5)
anchor("anchor_dock_2", 14.0, FLOOR, 13.5)
anchor("anchor_dock_2_left", 14.0, FLOOR, 12.0)
anchor("anchor_dock_2_right", 14.0, FLOOR, 15.0)
box(14.25, 14.6, FLOOR - 0.02, FLOOR + 0.015, 12.2, 14.8, "M_Leveler", bevel=0.008)   # leveler lip onto the deck
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
    """A stringer pallet entered from ±x: runners along x (the fork pockets between them),
    deck boards across, thin bottom boards at the two ends (below the fork blades)."""
    n = max(4, round(lx / 0.2))
    for i in range(n):                                                      # deck boards (across z)
        x = cx - lx / 2 + 0.06 + i * (lx - 0.12) / (n - 1)
        box(x - 0.055, x + 0.055, y0 + 0.11, y0 + 0.14, cz - lz / 2, cz + lz / 2, "M_Timber", group, bevel=0.004, segments=1)
    for sz in (-1, 0, 1):                                                   # runners (along x)
        z = cz + sz * (lz / 2 - 0.05)
        box(cx - lx / 2, cx + lx / 2, y0 + 0.022, y0 + 0.11, z - 0.05, z + 0.05, "M_Timber", group, bevel=0.004, segments=1)
    for sx in (-1, 1):                                                      # bottom boards
        x = cx + sx * (lx / 2 - 0.055)
        box(x - 0.05, x + 0.05, y0, y0 + 0.022, cz - lz / 2, cz + lz / 2, "M_Timber", group, bevel=0.003, segments=1)
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
            cyl(x + sx, FLOOR + 0.06, FLOOR + 0.9, z + sz, 0.016, "M_Frame", seg=8, bevel=0)
            cyl(x + sx, FLOOR, FLOOR + 0.06, z + sz, 0.04, "M_Rubber", seg=10, bevel=0)
    for y in (FLOOR + 0.2, FLOOR + 0.86):
        box(x - 0.33, x + 0.33, y, y + 0.03, z - 0.23, z + 0.23, "M_Frame", bevel=0.01)
    box(x - 0.24, x + 0.1, FLOOR + 0.89, FLOOR + 1.05, z - 0.14, z + 0.12, "M_Toolbox", bevel=0.02)
    box(x + 0.13, x + 0.3, FLOOR + 0.89, FLOOR + 0.9, z - 0.12, z + 0.12, "M_Screen", bevel=0.004)
    box(x - 0.2, x + 0.2, FLOOR + 0.23, FLOOR + 0.36, z - 0.16, z + 0.16, "M_Carton", bevel=0.01)


STATIONS = [((2.9, 3.2), "Alda-160-70"), ((6.9, 3.2), "Mona-170"), ((2.9, 6.6), "Luce"), ((6.9, 6.6), "Noemi-170")]
for i, ((cx, cz), product) in enumerate(STATIONS):
    rect(cx - 1.6, cx + 1.6, cz - 1.25, cz + 1.25, FLOOR + 0.006, "M_Mat")
    for sx in (-1, 1):                                                      # trestles
        box(cx + sx * 0.7 - 0.05, cx + sx * 0.7 + 0.05, FLOOR, FLOOR + 0.55, cz - 0.4, cz + 0.4, "M_Frame", bevel=0.01)
    box(cx - 0.95, cx + 0.95, FLOOR + 0.55, FLOOR + 0.6, cz - 0.42, cz + 0.42, "M_Galv", bevel=0.01)
    for sx in (-1, 1):                                                      # inspection light frame
        for sz in (-1, 1):                                                  # 45 mm profile, base plate, bolts, corner node
            px, pz = cx + sx * 1.35, cz + sz * 1.05
            box(px - 0.0225, px + 0.0225, FLOOR + 0.012, FLOOR + 2.47, pz - 0.0225, pz + 0.0225, "M_Frame", bevel=0.004, segments=1)
            box(px - 0.08, px + 0.08, FLOOR, FLOOR + 0.012, pz - 0.08, pz + 0.08, "M_Galv", bevel=0.003, segments=1)
            for bx in (-0.055, 0.055):
                for bz in (-0.055, 0.055):
                    cyl(px + bx, FLOOR + 0.012, FLOOR + 0.028, pz + bz, 0.009, "M_Steel", seg=6, bevel=0)
            box(px - 0.04, px + 0.04, FLOOR + 2.45, FLOOR + 2.55, pz - 0.04, pz + 0.04, "M_Steel", bevel=0.006, segments=1)
    box(cx - 0.72, cx + 0.72, FLOOR + 0.17, FLOOR + 0.2, cz - 0.38, cz + 0.38, "M_Galv", bevel=0.006, segments=1)  # lower shelf
    box(cx - 0.62, cx - 0.2, FLOOR + 0.2, FLOOR + 0.33, cz - 0.3, cz + 0.02, "M_Toolbox", bevel=0.015)            # tool case
    box(cx - 0.6, cx - 0.22, FLOOR + 0.33, FLOOR + 0.345, cz - 0.2, cz - 0.08, "M_Rubber", bevel=0.004)          # handle
    box(cx + 0.05, cx + 0.55, FLOOR + 0.2, FLOOR + 0.36, cz - 0.32, cz + 0.3, "M_Cabinet", bevel=0.012)           # parts bin
    cyl(cx + 0.3, FLOOR + 0.36, FLOOR + 0.52, cz + 0.12, 0.04, "M_Frame", seg=12, bevel=0.004)                    # spray bottle
    box(cx - 1.35, cx + 1.35, FLOOR + 1.45, FLOOR + 1.49, cz - 1.05 - 0.02, cz - 1.05 + 0.02, "M_Frame", bevel=0.004, segments=1)  # tool rail
    for k, (dx, h, mat) in enumerate(((-0.9, 0.32, "M_Galv"), (-0.65, 0.22, "M_Toolbox"), (-0.4, 0.28, "M_Steel"), (0.55, 0.18, "M_Screen"), (0.8, 0.3, "M_Galv"))):
        box(cx + dx - 0.035, cx + dx + 0.035, FLOOR + 1.45 - h, FLOOR + 1.45, cz - 1.05 + 0.02, cz - 1.05 + 0.05, mat, bevel=0.005, segments=1)
    sign_z = cz + 1.05                                                       # post sign under the front beam
    for sx in (-0.22, 0.22):
        cyl(cx + sx, FLOOR + 2.3, FLOOR + 2.47, sign_z, 0.006, "M_Galv", seg=6, bevel=0)
    box(cx - 0.3, cx + 0.3, FLOOR + 2.08, FLOOR + 2.3, sign_z - 0.012, sign_z + 0.012, "M_Steel", bevel=0.006, segments=1)
    text(f"QC {i + 1:02d}", cx, sign_z + 0.014, 0.13, "M_LineWhite", stand=True, y=FLOOR + 2.19)
    text(f"QC {i + 1:02d}", cx - 1.05, cz + 0.95, 0.22, "M_LineWhite", y=FLOOR + 0.012)                    # stencil on the mat
    for sz in (-1, 1):
        box(cx - 1.4, cx + 1.4, FLOOR + 2.47, FLOOR + 2.53, cz + sz * 1.05 - 0.025, cz + sz * 1.05 + 0.025, "M_Frame", bevel=0.005)
    for sx in (-1, 1):
        box(cx + sx * 1.35 - 0.025, cx + sx * 1.35 + 0.025, FLOOR + 2.47, FLOOR + 2.53, cz - 1.1, cz + 1.1, "M_Frame", bevel=0.005)
    for sz in (-0.45, 0.45):
        box(cx - 1.1, cx + 1.1, FLOOR + 2.41, FLOOR + 2.47, cz + sz - 0.07, cz + sz + 0.07, "M_LampHousing", bevel=0.01)
        box(cx - 1.05, cx + 1.05, FLOOR + 2.40, FLOOR + 2.41, cz + sz - 0.055, cz + sz + 0.055, "M_Lamp", bevel=0)
    anchor(f"anchor_product_{product}", cx, FLOOR + 0.6, cz)
    anchor(f"anchor_light_qc_{i + 1}", cx, FLOOR + 2.3, cz)
    trolley(cx + (-0.85 if i % 2 == 0 else 0.85), cz + 0.78)
    for k in range(3):                                                     # inspection tools on the table
        box(cx - 0.75 + k * 0.12, cx - 0.7 + k * 0.12, FLOOR + 0.6, FLOOR + 0.62, cz + 0.3, cz + 0.4, "M_Toolbox" if k == 0 else "M_Frame", bevel=0)
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
for cz in (2.3, 4.5, 6.7):                                                 # staged for dock 1 (clear of the forklift route)
    batch(12.9, FLOOR, cz, layers=2 if cz != 6.7 else 1)

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
# Shrubs: real Poly Haven shrub_02/03/04 prototypes, instanced at these spots (see SHRUBS below).
SHRUB_SPOTS = []
for i in range(16):                                                          # planting along the hall
    x = -0.4 + i * 0.95
    if 1.9 < x < 4.7:
        continue
    SHRUB_SPOTS.append((("Shrub3", "Shrub4", "Shrub2")[i % 3], x, 23.05 + 0.18 * ((i * 7) % 3 - 1), i * 1.7, 0.85 + 0.1 * (i % 3)))
for i in range(11):                                                          # along the road
    SHRUB_SPOTS.append((("Shrub4", "Shrub2", "Shrub3")[i % 3], 13.2 + i * 1.45, 31.5, i * 2.3, 0.9 + 0.08 * (i % 2)))

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


person2(2.9, 4.5, -math.pi / 2, kind="inspect", reach=0.25)                 # inspector at the Alda
person2(6.0, 6.6, 0.0, kind="inspect", reach=0.3)                           # inspector at the Luce/Noemi row
person2(6.9, 2.45, -math.pi / 2, kind="inspect", reach=0.15)                # inspector at QC 02
person2(4.9, 10.25, math.pi / 2, kind="inspect", coat="M_Workwear", reach=0.35)  # packer at the packing table
person2(11.3, 1.8, -2.4, kind="stand")                                      # in the QC booth
person2(6.2, 16.2, math.pi / 2, kind="walk", coat="M_Workwear")             # walking along the racking
person2(16.4, 17.0, 2.2, kind="stand", coat="M_Workwear", vest=True, hat="M_Toolbox")   # yard marshal

# More planting south of the road (the site keeps going into the haze).
rect(-8, 36, 30.6, 38, 0.006, "M_Grass")
box(-8, 36, 0, 0.14, 30.6, 30.75, "M_Curb", bevel=0.035)

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


def wheel(x, y, z, r, width, group, outward, dual=False):
    """Tyre with a rounded shoulder, a pressed steel rim and a hub (outward = +1 / -1 along z)."""
    for k in range(2 if dual else 1):
        zz = z + outward * k * (width + 0.03)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=28, radius1=r, radius2=r, depth=width)
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=S(x, y, zz), verts=bm.verts)
        _obj("tyre", bm, "M_Rubber", group, 0.06, segments=3)
    zr = z + outward * (width / 2 + (width + 0.03 if dual else 0) + 0.005)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=r * 0.62, radius2=r * 0.58, depth=0.04)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=S(x, y, zr), verts=bm.verts)
    _obj("rim", bm, "M_Galv", group, 0.01)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=r * 0.2, radius2=r * 0.16, depth=0.08)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=S(x, y, zr + outward * 0.04), verts=bm.verts)
    _obj("hub", bm, "M_Steel", group, 0.01)
    for k in range(10):                                         # wheel nuts: a turning wheel reads
        a = 2 * math.pi * k / 10
        cyl(x + math.cos(a) * r * 0.32, min(zr, zr + outward * 0.04), max(zr, zr + outward * 0.04),
            y + math.sin(a) * r * 0.32, 0.018, "M_Galv", group, seg=6, bevel=0, axis="z")


TRAILER = dict(x0=14.4, x1=27.95, zc=13.5, w=1.275, deck=FLOOR, roof=3.9)
TRUCK_WHEELS = []      # radius per «Truck_Wheel_<i>» (the app spins them with the truck's travel)


def truck():
    """Curtain-side semi-trailer at dock 02: real roof (load height 2.7 m), the camera-side
    curtain drawn back to the cab, rear doors open — the forklift loads through a real opening.
    Tractor: cab with glazing, grille, lights, mirrors, steps and tank; tyres with rims."""
    g = "Truck_Body"
    T = TRAILER
    x0, x1, zc, w = T["x0"], T["x1"], T["zc"], T["w"]
    deck, roof = T["deck"], T["roof"]
    zf, zn = zc - w, zc + w                                                            # far / near side
    box(x0, x1, deck - 0.14, deck, zf, zn, "M_Leveler", g, bevel=0.015)                # deck
    for zz in (zc - 0.45, zc + 0.45):                                                   # main beams
        box(x0 + 0.3, x1 - 0.2, 0.78, deck - 0.14, zz - 0.07, zz + 0.07, "M_Chassis", g, bevel=0.01)
    box(x0, x1, deck - 0.3, deck - 0.12, zn - 0.06, zn, "M_Chassis", g, bevel=0.01)     # side rails
    box(x0, x1, deck - 0.3, deck - 0.12, zf, zf + 0.06, "M_Chassis", g, bevel=0.01)
    box(x0, x1, deck, roof, zf, zf + 0.05, "M_Trailer", g, bevel=0.01)                 # far wall
    for k in range(1, 12):                                                               # inner stanchions
        x = x0 + k * (x1 - x0) / 12
        box(x - 0.04, x + 0.04, deck, roof, zf + 0.05, zf + 0.1, "M_Galv", g, bevel=0.008, segments=1)
    for k in range(1, 12):                                                               # far wall panel seams
        x = x0 + k * (x1 - x0) / 12 + 0.55
        box(x - 0.006, x + 0.006, deck + 0.05, roof - 0.05, zf - 0.006, zf + 0.0, "M_Chassis", g, bevel=0, segments=1)
    for y in (deck + 0.9, deck + 1.8):                                                   # load rails inside
        box(x0 + 0.2, x1 - 0.2, y, y + 0.06, zf + 0.05, zf + 0.08, "M_Galv", g, bevel=0.005, segments=1)
    box(x1 - 0.06, x1, deck, roof, zf, zn, "M_Trailer", g, bevel=0.02)                 # front wall
    box(x0 - 0.02, x1 + 0.02, roof, roof + 0.07, zf - 0.02, zn + 0.02, "M_TrailerRoof", g, bevel=0.025)
    for k in range(1, 9):                                                                # roof sheet seams
        x = x0 + k * (x1 - x0) / 9
        box(x - 0.01, x + 0.01, roof + 0.07, roof + 0.075, zf, zn, "M_Galv", g, bevel=0, segments=1)
    for zz in (zf + 0.04, zn - 0.04):                                                   # roof rails
        box(x0, x1, roof - 0.16, roof, zz - 0.04, zz + 0.04, "M_Galv", g, bevel=0.01, segments=1)
    for k in range(1, 18):                                                               # roof bows
        x = x0 + k * (x1 - x0) / 18
        box(x - 0.02, x + 0.02, roof - 0.06, roof, zf, zn, "M_Galv", g, bevel=0, segments=1)
    box(x0, x1, deck - 0.02, deck + 0.06, zn - 0.05, zn, "M_Galv", g, bevel=0.005)      # rave rail
    for k in range(9):                                                                   # curtain drawn back
        x = x1 - 0.12 - k * 0.15
        dz = 0.06 if k % 2 else 0.0
        box(x - 0.09, x + 0.09, deck + 0.05, roof - 0.17, zn - 0.08 + dz, zn + 0.02 + dz, "M_Curtain", g, bevel=0.035, segments=2)
        for y in (deck + 0.25, deck + 1.3):                                             # buckle straps
            box(x - 0.1, x + 0.1, y, y + 0.05, zn - 0.09 + dz, zn + 0.03 + dz, "M_Strap", g, bevel=0.005, segments=1)
    for zz in (zf, zn - 0.075):                                                         # rear posts + header
        box(x0, x0 + 0.08, deck - 0.3, roof, zz, zz + 0.075, "M_Chassis", g, bevel=0.01)
    box(x0, x0 + 0.08, roof - 0.22, roof, zf, zn, "M_Chassis", g, bevel=0.01)
    box(x0 + 0.08, x0 + 1.3, deck, roof - 0.05, zf - 0.07, zf - 0.02, "M_Trailer", g, bevel=0.01)   # far door, open
    box(x0 - 0.02, x0 + 0.04, 0.42, 0.58, zf + 0.1, zn - 0.1, "M_Chassis", g, bevel=0.01)          # underrun bar
    for zz in (zf + 0.15, zn - 0.35):                                                   # rear lights
        box(x0 - 0.03, x0, 0.66, 0.8, zz, zz + 0.2, "M_TailLight", g, bevel=0.01)
    for ax in (16.2, 17.5, 18.8):
        for side in (-1, 1):
            wheel(ax, 0.5, zc + side * 0.92, 0.5, 0.38, f"Truck_Wheel_{len(TRUCK_WHEELS)}", side)
            TRUCK_WHEELS.append(0.5)
        box(ax - 0.06, ax + 0.06, 0.45, 0.8, zc - 0.85, zc + 0.85, "M_Chassis", g, bevel=0.01)
    for side in (-1, 1):                                                                 # mudflaps, legs
        box(19.3, 19.33, 0.12, 0.95, zc + side * 0.95 - 0.25, zc + side * 0.95 + 0.25, "M_Rubber", g, bevel=0.005)
        box(24.5, 24.62, 0.06, deck - 0.3, zc + side * 0.85 - 0.06, zc + side * 0.85 + 0.06, "M_Chassis", g, bevel=0.01)
        box(24.4, 24.72, 0.0, 0.06, zc + side * 0.85 - 0.12, zc + side * 0.85 + 0.12, "M_Chassis", g, bevel=0.01)
    box(19.5, 23.8, 0.55, 0.75, zn - 0.06, zn - 0.02, "M_Galv", g, bevel=0.005)         # side guard
    # Tractor.
    box(26.6, 32.0, 0.62, 0.92, zc - 0.48, zc + 0.48, "M_Chassis", g, bevel=0.02)
    box(27.2, 28.2, 0.92, 1.06, zc - 0.55, zc + 0.55, "M_Chassis", g, bevel=0.03)        # fifth wheel
    for ax, dual in ((28.6, True), (31.1, False)):
        for side in (-1, 1):
            wheel(ax, 0.52, zc + side * (0.78 if dual else 0.98), 0.52, 0.32, f"Truck_Wheel_{len(TRUCK_WHEELS)}", side, dual=dual)
            TRUCK_WHEELS.append(0.52)
    tractor_cab(zc, g)
    bm = bmesh.new()                                                                     # fuel tank
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.28, radius2=0.28, depth=1.3)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=S(29.3, 0.78, zc + 1.0), verts=bm.verts)
    _obj("tank", bm, "M_Galv", g, 0.04)
    anchor("anchor_truck", 21.2, FLOOR, zc)
    anchor("anchor_trailer_min", x0, deck, zf + 0.05)
    anchor("anchor_trailer_max", x1 - 0.06, roof - 0.02, zn)
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
    # Compact warehouse forklift (0.85): collapsed mast ≈ 2.45 m clears the trailer roof.
    place_m = Matrix.Scale(0.85, 4) @ Matrix.Translation(Vector((-0.37, 0, 0))) @ Matrix.Rotation(math.pi / 2, 4, "Z")
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


forklift2()
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
# Separately moving parts: the forklift's mast and wheels, the truck's wheels.
PARTS = {g: realize(g, g) for g in sorted(GROUPS)
         if (g.startswith("Forklift_") and g not in ("Forklift_Body", "Forklift_Carriage")) or g.startswith("Truck_Wheel_")}
MOVERS = (body, carriage, truck_body, batch_ob) + tuple(PARTS.values())
for ob in (static,) + MOVERS:
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
        if "leaves" in m["name"] or asset.startswith("shrub"):
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
        for slot in o.material_slots:
            m = slot.material
            if not (m and m.use_nodes):
                continue
            # Rewire to the resized textures in OUT/textures: the USD then references
            # «textures/…» relatively (RealityKit reads them; SceneKit rebinds by name anyway).
            nt = m.node_tree
            for n in [n for n in nt.nodes if n.type in ("TEX_IMAGE", "NORMAL_MAP", "SEPRGB", "SEPARATE_COLOR")]:
                nt.nodes.remove(n)
            b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            e = MATERIAL_MAP.get(m.name, {})
            if b is None:
                continue
            if e.get("base"):
                t = nt.nodes.new("ShaderNodeTexImage")
                t.image = bpy.data.images.load(os.path.join(OUT, e["base"]), check_existing=True)
                nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
            if e.get("normal"):
                t = nt.nodes.new("ShaderNodeTexImage")
                t.image = bpy.data.images.load(os.path.join(OUT, e["normal"]), check_existing=True)
                t.image.colorspace_settings.name = "Non-Color"
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(t.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
            b.inputs["Roughness"].default_value = 0.6
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
    DUCT_HALF = (hi.x - lo.x) / 2
    for k in range(9):                     # cantilever brackets from the west wall under each joint
        z = 6.2 - 0.9 + k * 1.8
        box(0.25, 0.3, 6.95, 7.25, z - 0.04, z + 0.04, "M_Galv", bevel=0.004, segments=1)             # wall plate
        box(0.3, 1.05 + DUCT_HALF + 0.08, 7.17, 7.25, z - 0.025, z + 0.025, "M_Galv", bevel=0.004, segments=1)  # arm
        box(1.05 + DUCT_HALF + 0.04, 1.05 + DUCT_HALF + 0.08, 7.25, 7.4, z - 0.025, z + 0.025, "M_Galv", bevel=0.004, segments=1)
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
    for k in range(4):                                                      # rooftop units next door
        place(air, NX0 + 3.0 + k * 4.2, NH + 0.45, NZ1 - 1.2, 0.0, centred)
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
    for k2 in range(3):
        place([sink], 1.7 + k2 * 0.8, FLOOR + 0.86, 1.15, 0.0)
    # QC bench kit: perforated lower shelf with cases, a pegboard with the gauges on the lamp posts.
    box(1.27, 3.73, FLOOR + 0.18, FLOOR + 0.21, 0.82, 1.48, "M_Galv", bevel=0.005, segments=1)
    box(1.4, 1.9, FLOOR + 0.21, FLOOR + 0.35, 0.9, 1.3, "M_Toolbox", bevel=0.015)
    box(2.05, 2.75, FLOOR + 0.21, FLOOR + 0.42, 0.88, 1.4, "M_Carton", bevel=0.01)
    box(2.95, 3.6, FLOOR + 0.21, FLOOR + 0.31, 0.9, 1.38, "M_Cabinet", bevel=0.01)
    box(1.27, 3.73, FLOOR + 1.05, FLOOR + 1.7, 0.825, 0.835, "M_Galv", bevel=0.003, segments=1)
    for sx in (1.27, 3.71):
        box(sx, sx + 0.02, FLOOR + 1.0, FLOOR + 1.75, 0.8, 0.84, "M_Steel", bevel=0.003, segments=1)
    for dx, y0, y1, w, mat in ((1.45, 1.2, 1.6, 0.05, "M_Toolbox"), (1.75, 1.35, 1.6, 0.12, "M_Screen"),
                               (2.1, 1.15, 1.62, 0.03, "M_Galv"), (2.45, 1.4, 1.62, 0.18, "M_Steel"),
                               (2.9, 1.25, 1.6, 0.04, "M_Frame"), (3.3, 1.3, 1.62, 0.14, "M_Toolbox")):
        box(dx - w / 2, dx + w / 2, FLOOR + y0, FLOOR + y1, 0.835, 0.865, mat, bevel=0.006, segments=1)

# ----------------------------------------------------------------------------- engineering
# The services that make a real hall read as one (concept 01): distribution cabinets, cable
# ladder and trays, water and compressed-air lines, post signs. Every run is carried: wall
# struts with clamps, tray brackets, risers out of the slab, end flanges.
WX = 0.25                                       # inner face of the west wall (x)
NZ = 0.25                                       # inner face of the north wall (z)
# Distribution cabinets (3 × 800 mm) on the west wall behind quality control.
for k in range(3):
    z0 = 0.72 + k * 0.8                         # clear of the corner risers
    box(WX + 0.02, WX + 0.4, FLOOR, FLOOR + 0.1, z0 + 0.02, z0 + 0.78, "M_Steel", bevel=0.006, segments=1)   # plinth
    box(WX + 0.01, WX + 0.4, FLOOR + 0.1, FLOOR + 2.1, z0 + 0.005, z0 + 0.795, "M_Cabinet", bevel=0.012)    # carcass
    box(WX + 0.4, WX + 0.42, FLOOR + 0.13, FLOOR + 2.07, z0 + 0.03, z0 + 0.77, "M_Cabinet", bevel=0.006)    # door
    box(WX + 0.42, WX + 0.44, FLOOR + 1.0, FLOOR + 1.22, z0 + 0.69, z0 + 0.72, "M_Rubber", bevel=0.006)    # handle
    for j in range(4):                                                                                      # vent louvres
        y = FLOOR + 0.25 + j * 0.05
        box(WX + 0.42, WX + 0.425, y, y + 0.02, z0 + 0.2, z0 + 0.6, "M_Steel", bevel=0, segments=1)
    box(WX + 0.42, WX + 0.423, FLOOR + 1.7, FLOOR + 1.84, z0 + 0.12, z0 + 0.4, "M_LineWhite", bevel=0, segments=1)   # label
    box(WX + 0.42, WX + 0.424, FLOOR + 1.72, FLOOR + 1.82, z0 + 0.5, z0 + 0.6, "M_LineYellow", bevel=0, segments=1)  # hazard
    text(f"ЩР-{k + 1}", WX + 0.424, z0 + 0.26, 0.07, "M_Steel", rot=HALF, stand=True, y=FLOOR + 1.77)
# Vertical cable ladder from the cabinets to the wall tray.
for zz in (1.75, 2.09):
    box(WX + 0.06, WX + 0.11, FLOOR + 2.1, FLOOR + 3.46, zz - 0.02, zz + 0.02, "M_Galv", bevel=0.003, segments=1)
for j in range(6):
    y = FLOOR + 2.2 + j * 0.22
    box(WX + 0.06, WX + 0.1, y, y + 0.025, 1.75, 2.09, "M_Galv", bevel=0, segments=1)
for zz in (1.81, 1.87, 1.93, 1.99):
    cyl(WX + 0.13, FLOOR + 2.1, FLOOR + 3.42, zz, 0.014, "M_Rubber", seg=8, bevel=0)


def tray(a0, a1, along_z, y=FLOOR + 3.4):
    """A galvanised cable tray with cables, carried by wall brackets every ~1.2 m."""
    n = int((a1 - a0) / 1.2) + 1
    if along_z:
        box(WX + 0.05, WX + 0.35, y, y + 0.02, a0, a1, "M_Galv", bevel=0.003, segments=1)
        for xx in (WX + 0.05, WX + 0.33):
            box(xx, xx + 0.02, y, y + 0.1, a0, a1, "M_Galv", bevel=0.003, segments=1)
        for j, xx in enumerate((WX + 0.12, WX + 0.17, WX + 0.22, WX + 0.27)):
            pipe_z(xx, y + 0.04, a0 + 0.05, a1 - 0.05, 0.016 if j % 2 else 0.022, "M_Rubber", seg=8)
        for k in range(n):
            zz = a0 + 0.15 + k * (a1 - a0 - 0.3) / max(1, n - 1)
            box(WX, WX + 0.02, y - 0.25, y + 0.05, zz - 0.03, zz + 0.03, "M_Galv", bevel=0.003, segments=1)
            box(WX + 0.02, WX + 0.37, y - 0.05, y, zz - 0.02, zz + 0.02, "M_Galv", bevel=0.003, segments=1)
    else:                                       # brackets only: the north tray exists (hall shell)
        for k in range(n):
            xx = a0 + 0.15 + k * (a1 - a0 - 0.3) / max(1, n - 1)
            box(xx - 0.03, xx + 0.03, y - 0.25, y + 0.05, NZ, NZ + 0.02, "M_Galv", bevel=0.003, segments=1)
            box(xx - 0.02, xx + 0.02, y - 0.05, y, NZ + 0.02, NZ + 0.37, "M_Galv", bevel=0.003, segments=1)


tray(0.55, 8.1, True)
tray(0.6, 13.6, False)
# Water (blue) and compressed air (galvanised) lines: risers out of the slab in the north-west
# corner, along the west wall to quality control, the air line also along the north wall.
PIPES = (("M_PipeWater", 0.045, FLOOR + 2.7, 0.2), ("M_Galv", 0.032, FLOOR + 3.0, 0.32))   # clear of the booth roof
for mat, r, y, off in PIPES:
    px, pz = WX + off, NZ + off
    cyl(px, FLOOR, y, pz, r, mat, seg=16, bevel=0)                                                   # riser
    box(px - r - 0.015, px + r + 0.015, FLOOR, FLOOR + 0.02, pz - r - 0.015, pz + r + 0.015, "M_Steel", bevel=0.003, segments=1)
    cyl(px, FLOOR + 0.9, FLOOR + 0.93, pz, r + 0.028, "M_Steel", seg=16, bevel=0)                    # flange
    box(px - r - 0.02, px + r + 0.02, y - r - 0.02, y + r + 0.02, pz - r - 0.02, pz + r + 0.02, mat, bevel=r * 0.9)  # elbow
    pipe_z(px, y, pz, 8.05, r, mat)                                                                   # west run
    for zz in (3.0, 5.6, 8.05):                                                                       # flanges, end cap
        pipe_z(px, y, zz, zz + 0.025, r + 0.025, "M_Steel")
    if mat == "M_Galv":
        pipe_x(y, pz, px, 13.4, r, mat)                                                               # north run
        for xx in (4.5, 9.0, 13.4):
            pipe_x(y, pz, xx, xx + 0.025, r + 0.025, "M_Steel")
# Wall struts (galvanised channel) with clamps: every 1.35 m on the west run, 1.45 m on the north.
for k in range(6):
    z = 1.3 + k * 1.35
    box(WX, WX + 0.04, FLOOR + 2.58, FLOOR + 3.1, z - 0.02, z + 0.02, "M_Galv", bevel=0.003, segments=1)
    for mat, r, y, off in PIPES:
        box(WX + 0.04, WX + off, y - 0.012, y + 0.012, z - 0.015, z + 0.015, "M_Galv", bevel=0.002, segments=1)
        pipe_z(WX + off, y, z - 0.018, z + 0.018, r + 0.01, "M_Steel", seg=14)
for k in range(9):
    x = 1.4 + k * 1.45
    if 9.85 < x < 12.85:                       # no strut through the booth; the span stays < 3 m
        continue
    y, r, off = FLOOR + 3.0, 0.032, 0.32
    box(x - 0.02, x + 0.02, FLOOR + 2.88, FLOOR + 3.12, NZ, NZ + 0.04, "M_Galv", bevel=0.003, segments=1)
    box(x - 0.015, x + 0.015, y - 0.012, y + 0.012, NZ + 0.04, NZ + off, "M_Galv", bevel=0.002, segments=1)
    pipe_x(y, NZ + off, x - 0.018, x + 0.018, r + 0.01, "M_Steel", seg=14)
# Service points for the stations: a water drop with a valve into a wall box, a post sign above.
for k, zc in enumerate((3.6, 6.6)):
    px = WX + 0.2
    cyl(px, FLOOR + 1.45, FLOOR + 2.7, zc, 0.022, "M_PipeWater", seg=12, bevel=0)
    box(px - 0.05, px + 0.05, FLOOR + 2.65, FLOOR + 2.75, zc - 0.05, zc + 0.05, "M_PipeWater", bevel=0.02)  # tee
    box(px - 0.035, px + 0.035, FLOOR + 1.7, FLOOR + 1.78, zc - 0.035, zc + 0.035, "M_Steel", bevel=0.01)  # valve
    box(px + 0.03, px + 0.17, FLOOR + 1.76, FLOOR + 1.78, zc - 0.012, zc + 0.012, "M_TailLight", bevel=0.004)  # lever
    box(px - 0.03, px + 0.03, FLOOR + 1.42, FLOOR + 1.47, zc - 0.03, zc + 0.03, "M_Steel", bevel=0.008)  # gland into the box
    box(WX, WX + 0.2, FLOOR + 0.95, FLOOR + 1.45, zc - 0.28, zc + 0.28, "M_Cabinet", bevel=0.01)          # service box
    box(WX + 0.2, WX + 0.205, FLOOR + 1.0, FLOOR + 1.4, zc - 0.24, zc + 0.24, "M_Cabinet", bevel=0.003, segments=1)
    for j, zz in enumerate((-0.12, 0.0, 0.12)):                                                         # sockets, coupling
        box(WX + 0.205, WX + 0.24, FLOOR + 1.08, FLOOR + 1.16, zc + zz - 0.035, zc + zz + 0.035, "M_LineYellow" if j == 2 else "M_Rubber", bevel=0.008)
    box(WX + 0.01, WX + 0.03, FLOOR + 2.0, FLOOR + 2.3, zc + 0.08, zc + 0.8, "M_Steel", bevel=0.006, segments=1)  # post sign
    text(f"QC {2 * k + 1:02d}·{2 * k + 2:02d}", WX + 0.032, zc + 0.44, 0.12, "M_LineWhite", rot=HALF, stand=True, y=FLOOR + 2.15)

# Geometry added after the static mesh was realised (basin table, services) is joined into it
# with the same world-scale UV0 (before this, those boxes stayed loose objects in the USD).
def _alive(o):
    try:
        return o.name in bpy.data.objects and o != static
    except ReferenceError:                     # joined into «Static» earlier
        return False


late = [o for o in GROUPS.get("Static", []) if _alive(o)]
if late:
    for o in scene.objects:
        o.select_set(o in late)
    bpy.context.view_layer.objects.active = late[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    lj = bpy.context.view_layer.objects.active
    if not lj.data.uv_layers:
        lj.data.uv_layers.new(name="UVMap")
    lj.data.uv_layers[0].name = "UVMap"
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=2.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    GROUPS.setdefault("Props", []).append(lj)
    print("LATE static objects", len(late))

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

# ----------------------------------------------------------------------------- shrubs
# Poly Haven shrub_02 / 03 / 04 (CC0): natural shrubs, one prototype each, instanced by the app at
# anchor_inst_<Proto>_<k> (shared geometry). shrub_04 is decimated to half.
PROTOS = {}
if tree_proto:
    PROTOS["Tree"] = tree_proto
for asset, proto, ratio in (("shrub_02", "Shrub2", None), ("shrub_03", "Shrub3", None), ("shrub_04", "Shrub4", 0.5)):
    parts = load_asset(asset, ratio=ratio, size=512)
    if not parts:
        continue
    for o in parts:
        scene.collection.objects.link(o)
    for o in scene.objects:
        o.select_set(o in parts)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = proto
    while len(ob.data.uv_layers) > 1:
        ob.data.uv_layers.remove(ob.data.uv_layers[-1])
    for poly in ob.data.polygons:
        poly.use_smooth = True
    PROTOS[proto] = ob
    print("PART", proto, sum(len(p.vertices) - 2 for p in ob.data.polygons))
INSTANCES = [("Tree", x, z, rot, sc) for (x, z, rot, sc) in TREE_SPOTS] + list(SHRUB_SPOTS)
for k, (proto, x, z, rot, sc) in enumerate(INSTANCES):
    if proto in PROTOS:
        e = anchor(f"anchor_inst_{proto}_{k}", x, 0.0, z, heading=rot)
        e.scale = (sc, sc, sc)

# Tiled ground materials (app maps them in world metres on UV0).
for mat, folder, tile in (("M_Asphalt", "clean_asphalt", 2.0),):
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

def set_origin(ob, p):
    """Moves an object's origin (its pivot in the app) to scene point p, geometry unchanged."""
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    keep = scene.cursor.location.copy()
    scene.cursor.location = p
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    scene.cursor.location = keep


root = bpy.data.objects.new("Forklift", None)
scene.collection.objects.link(root)
body.parent = root
carriage.parent = root
truck_root = bpy.data.objects.new("Truck", None)
scene.collection.objects.link(truck_root)
truck_body.parent = truck_root
for name, ob in PARTS.items():
    if "Wheel" in name:                                       # spin (and steer) about the wheel centre
        lo = Vector(map(min, *[ob.matrix_world @ v.co for v in ob.data.vertices]))
        hi = Vector(map(max, *[ob.matrix_world @ v.co for v in ob.data.vertices]))
        c = (lo + hi) / 2
        if name.startswith("Forklift_"):                      # the hub sticks out: centre on the tyre
            r = FRONT_R if "WheelF" in name else REAR_R
            c.z = r
        set_origin(ob, c)
    elif name == "Forklift_Mast":
        set_origin(ob, S(*MAST_PIVOT))
    ob.parent = root if name.startswith("Forklift_") else truck_root

# Lightmap UV + AO bake for the static scene only. Only architecture and ground get atlas space;
# props, people and foliage still occlude (they are in the bake scene) but their own lightmap UVs
# point at a white corner of the atlas, so thousands of tiny islands never starve the floor.
NO_ATLAS = {"M_Foliage", "M_Bark", "M_Coat", "M_Vest", "M_Trousers", "M_Skin", "M_Hair", "M_Lamp",
            "M_Screen", "M_GlassClear", "M_Toolbox", "M_Workwear", "M_Rubber", "M_Ceramic"} | {k for k in MATERIAL_MAP if not k.startswith("M_")}
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

def place_instances():
    """Linked copies of the prototypes at their instance spots (they occlude in bakes and shots);
    the prototypes themselves sit at the origin and are hidden."""
    out = []
    for ob in PROTOS.values():
        ob.hide_render = True
    for proto, x, z, rot, sc in INSTANCES:
        if proto not in PROTOS:
            continue
        c = PROTOS[proto].copy()
        c.hide_render = False
        c.matrix_world = Matrix.Translation(S(x, 0, z)) @ Matrix.Rotation(rot, 4, "Z") @ Matrix.Scale(sc, 4)
        scene.collection.objects.link(c)
        out.append(c)
    return out


def apply_app_palette():
    """The app's PBR values (ShippingAtelierScene.swift specs) written into the Blender materials,
    so the USD preview surfaces carry them: RealityKit reads the same kit without a name map,
    and Cycles shots use the same values as SceneKit."""
    import re
    swift = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Salini",
                              "ShippingAtelierScene.swift")).read()
    to_lin = lambda c: (c / 255) / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4
    for name, hexc, rough, metal in re.findall(r'"(M_\w+)": Spec\(color: 0x([0-9A-Fa-f]{6}), rough: ([\d.]+)(?:, metal: ([\d.]+))?', swift):
        if name not in MATS:
            continue
        v = int(hexc, 16)
        b = MATS[name].node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (to_lin(v >> 16 & 255), to_lin(v >> 8 & 255), to_lin(v & 255), 1)
        b.inputs["Roughness"].default_value = float(rough)
        b.inputs["Metallic"].default_value = float(metal or 0)
    lamp = MATS["M_Lamp"].node_tree.nodes["Principled BSDF"]
    lamp.inputs["Emission Color"].default_value = (1.0, 0.95, 0.85, 1)
    lamp.inputs["Emission Strength"].default_value = 0.0
    surface_textures(swift)


# ----------------------------------------------------------------------------- surface textures
# Fine, realistic surface variation instead of constant fills: albedo (the app's colour ×
# subtle variation), roughness (the app's value ± variation) and normal maps per surface kind.
# Tileable over one UV0 unit = 2 m (cube projection). Same files for SceneKit and RealityKit.
# Scanned CC0 sets (ambientCG photogrammetry, tmp/insight-poc-source/<id>, manifests there):
# material → (scan id, tiles per 2 m UV unit, albedo variation, roughness variation, keep hue).
# Albedo = the scan normalised to the app's colour (its relative variation kept, scaled);
# roughness = the scan's variation around the app's value; normal = the scan's (OpenGL).
SCANS = {
    "M_Floor": ("Concrete016", 1, 0.6, 0.35, False),
    "M_Plinth": ("Concrete034", 2, 0.8, 0.4, False), "M_Slab": ("Concrete034", 2, 0.8, 0.4, False),
    "M_Section": ("Concrete034", 2, 0.8, 0.4, False), "M_Curb": ("Concrete034", 2, 0.7, 0.4, False),
    "M_Paving": ("Concrete016", 1, 0.8, 0.4, False),
    "M_Steel": ("Metal027", 4, 0.25, 0.5, False), "M_Coping": ("Metal027", 4, 0.25, 0.5, False),
    "M_Forklift": ("Metal027", 4, 0.2, 0.5, False), "M_TruckCab": ("Metal027", 4, 0.15, 0.4, False),
    "M_RackUpright": ("Metal027", 4, 0.25, 0.5, False), "M_RackBeam": ("Metal027", 4, 0.25, 0.5, False),
    "M_Bollard": ("Metal027", 4, 0.3, 0.5, False), "M_BoothFrame": ("Metal027", 4, 0.2, 0.4, False),
    "M_Chassis": ("Metal027", 4, 0.3, 0.5, False), "M_Cabinet": ("Metal027", 4, 0.2, 0.5, False),
    "M_PipeWater": ("Metal027", 4, 0.2, 0.5, False), "M_TrailerRoof": ("Metal027", 4, 0.2, 0.4, False),
    "M_Galv": ("Metal040", 4, 0.8, 0.8, False), "M_Leveler": ("Metal040", 4, 0.8, 0.8, False),
    "M_Frame": ("Metal011", 4, 0.6, 0.6, False), "M_Desk": ("Metal011", 4, 0.3, 0.5, False),
    "M_Rubber": ("Rubber004", 3, 0.8, 0.6, False), "M_Mat": ("Rubber004", 3, 0.8, 0.6, False),
    "M_Timber": ("Wood061", 2, 1.0, 0.6, True), "M_Carton": ("Cardboard002", 4, 1.0, 0.6, True),
}
SURFACE_KIND = {
    "M_Floor": "concrete_polished", "M_Plinth": "concrete", "M_Slab": "concrete", "M_Paving": "concrete",
    "M_Curb": "concrete", "M_Section": "concrete", "M_Panel": "panel_ribs", "M_Facade": "sheet_ribs_v",
    "M_Trailer": "sheet_ribs_v", "M_Steel": "paint", "M_Coping": "paint", "M_Forklift": "paint",
    "M_TruckCab": "paint", "M_RackUpright": "paint", "M_RackBeam": "paint", "M_Bollard": "paint",
    "M_BoothFrame": "paint", "M_Chassis": "paint", "M_Desk": "paint", "M_TrailerRoof": "paint",
    "M_Leveler": "brushed", "M_Frame": "brushed", "M_Galv": "brushed", "M_Rubber": "rubber", "M_Mat": "rubber",
    "M_Curtain": "fabric", "M_Roof": "gravel", "M_Timber": "timber", "M_Carton": "fibre", "M_Grass": "grass",
    "M_LineWhite": "paint", "M_LineYellow": "paint", "M_Cabinet": "paint", "M_PipeWater": "paint",
}


def surface_textures(swift):
    import re
    import numpy as np
    N = 512
    rng = np.random.default_rng(7)
    fy, fx = np.meshgrid(np.fft.fftfreq(N), np.fft.fftfreq(N), indexing="ij")
    f = np.sqrt(fx * fx + fy * fy) + 1e-6

    def fbm(beta, lo=0.0, hi=1.0, aniso=(1.0, 1.0)):
        """Seamless 1/f^beta noise in [-1, 1] (periodic by construction); aniso stretches it."""
        ff = np.sqrt((fx * aniso[0]) ** 2 + (fy * aniso[1]) ** 2) + 1e-6
        spec = np.fft.fft2(rng.standard_normal((N, N))) / ff ** beta
        spec[(ff < lo) | (ff > hi)] = 0
        n = np.real(np.fft.ifft2(spec))
        n -= n.mean()
        return n / (np.abs(n).max() + 1e-9)

    def normal_from_height(h, strength):
        gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
        n = np.stack([-gx, gy, np.ones_like(h)], 2)
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        return n * 0.5 + 0.5

    def scan(name):
        def load(kind):
            img = bpy.data.images.load(os.path.join(SRC, "smooth_concrete_floor", f"smooth_concrete_floor_{kind}_1k.jpg"))
            img.scale(N, N)
            a = np.empty(N * N * 4, dtype=np.float32)
            img.pixels.foreach_get(a)
            bpy.data.images.remove(img)
            return a.reshape(N, N, 4)[::-1, :, :3]
        return load(name)

    concrete_diff = scan("diff").mean(2)
    concrete_diff = (concrete_diff - concrete_diff.mean()) / (np.abs(concrete_diff - concrete_diff.mean()).max() + 1e-6)
    concrete_rough = scan("rough").mean(2)
    concrete_rough = (concrete_rough - concrete_rough.mean()) / (np.abs(concrete_rough - concrete_rough.mean()).max() + 1e-6)
    concrete_nor = scan("nor_gl")
    yy = np.arange(N)[:, None] / N
    xx = np.arange(N)[None, :] / N

    def ribs(coord, period_px):
        u = (coord * N) % period_px / period_px
        return np.clip(np.minimum(u, 1 - u) * 6, 0, 1)                                     # trapezoid

    specs = {n: (int(c, 16), float(r)) for n, c, r in
             re.findall(r'"(M_\w+)": Spec\(color: 0x([0-9A-Fa-f]{6}), rough: ([\d.]+)', swift)}
    scan_cache = {}
    used_concrete_scan = False

    def scan_set(sid, tiles):
        """A scanned set at N × N, tiled `tiles` times (seamless sets; non-square ones are
        repeated to square first), as float arrays top-down: albedo (linear), roughness, normal."""
        key = (sid, tiles)
        if key in scan_cache:
            return scan_cache[key]
        out = {}
        for kind, suffix in (("albedo", "Color"), ("rough", "Roughness"), ("nor", "NormalGL")):
            img = bpy.data.images.load(os.path.join(SRC, sid, f"{sid}_1K-JPG_{suffix}.jpg"))
            if kind != "albedo":
                img.colorspace_settings.name = "Non-Color"
            w, h = img.size
            a = np.empty(w * h * 4, dtype=np.float32)
            img.pixels.foreach_get(a)          # linear for the sRGB colour map
            bpy.data.images.remove(img)
            a = a.reshape(h, w, 4)[::-1, :, :3]
            if h != w:                          # e.g. 1.10 × 0.55 m → stack to a square tile
                rep = w // h if w > h else h // w
                a = np.concatenate([a] * rep, axis=0 if w > h else 1)
            a = np.tile(a, (tiles, tiles, 1))
            step = a.shape[0] / N
            idx = (np.arange(N) * step).astype(int)
            out[kind] = a[idx][:, idx]
        scan_cache[key] = out
        USED_ASSETS.append(sid)
        return out

    for name, kind in SURFACE_KIND.items():
        if name not in MATS or name not in specs:
            continue
        hexc, rough = specs[name]
        base = np.array([(hexc >> 16 & 255), (hexc >> 8 & 255), (hexc & 255)], np.float32) / 255
        av, rv, h, ns = np.zeros((N, N)), np.zeros((N, N)), np.zeros((N, N)), 0.0
        scanned = None
        if name in SCANS and os.path.exists(os.path.join(SRC, SCANS[name][0])):
            sid, tiles, ka, kr, hue = SCANS[name]
            sc = scan_set(sid, tiles)
            lin = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
            target = np.array([lin(c) for c in base], np.float32)
            alb = sc["albedo"]
            if hue:                               # wood, cardboard: the scan's hue variation, app mean
                rel = alb / np.maximum(alb.reshape(-1, 3).mean(0), 1e-4)
            else:                                 # neutral relative luminance variation
                L = alb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
                rel = np.repeat((L / max(float(L.mean()), 1e-4))[:, :, None], 3, 2)
            rel = 1 + (rel - 1) * ka
            alb_lin = np.clip(target[None, None, :] * rel, 0, 1)
            enc = lambda x: np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(np.maximum(x, 0), 1 / 2.4) - 0.055)
            scanned = (enc(alb_lin), np.clip(rough + (sc["rough"].mean(2) - sc["rough"].mean()) * kr, 0.04, 1.0), sc["nor"], sid)
        if kind.startswith("concrete") and scanned is None:
            used_concrete_scan = True
            av, rv = 0.07 * concrete_diff + 0.03 * fbm(1.4, 0.002, 0.05), 0.10 * concrete_rough
            nrm = concrete_nor
        else:
            nrm = None
            if kind == "paint":
                av, rv, h, ns = 0.025 * fbm(1.6, 0.002, 0.08), 0.06 * fbm(1.5, 0.002, 0.06), fbm(0.8, 0.08, 0.5), 0.35
            elif kind == "panel_ribs":
                av, rv, h, ns = 0.02 * fbm(1.6, 0.002, 0.08), 0.05 * fbm(1.5, 0.002, 0.06), ribs(yy, 25.6) + 0.15 * fbm(0.8, 0.08, 0.5), 1.6
            elif kind == "sheet_ribs_v":
                av, rv, h, ns = 0.03 * fbm(1.6, 0.002, 0.08), 0.06 * fbm(1.5, 0.002, 0.06), ribs(xx, 32.0) + 0.1 * fbm(0.8, 0.08, 0.5), 2.2
            elif kind == "brushed":
                av, rv, h, ns = 0.03 * fbm(1.2, 0.002, 0.5, (0.04, 1.0)), 0.08 * fbm(1.0, 0.002, 0.5, (0.04, 1.0)), fbm(1.0, 0.05, 0.5, (0.04, 1.0)), 0.25
            elif kind in ("rubber", "fabric"):
                av, rv, h, ns = 0.05 * fbm(1.0, 0.01, 0.5), 0.05 * fbm(1.2, 0.002, 0.1), fbm(0.6, 0.1, 0.5), 0.6 if kind == "rubber" else 0.9
            elif kind == "gravel":
                av, rv, h, ns = 0.18 * fbm(0.4, 0.05, 0.5), 0.03 * fbm(1.0, 0.002, 0.1), fbm(0.5, 0.05, 0.5), 2.5
            elif kind in ("timber", "fibre"):
                st = (1.0, 0.03) if kind == "timber" else (1.0, 1.0)
                av, rv, h, ns = 0.10 * fbm(1.1, 0.002, 0.5, st), 0.05 * fbm(1.2, 0.002, 0.1), fbm(0.9, 0.02, 0.5, st), 0.5
            elif kind == "grass":
                av, rv, h, ns = 0.22 * fbm(1.2, 0.004, 0.4), 0.02 * fbm(1.0, 0.002, 0.1), fbm(0.6, 0.05, 0.5), 1.0
            nrm = normal_from_height(h, ns)
        albedo = np.clip(base[None, None, :] * (1 + av[:, :, None]), 0, 1)
        rmap = np.clip(rough + rv, 0.04, 1.0)
        entry = {"asset": "generated", "kind": kind}
        if scanned is not None:
            albedo, rmap, nrm, sid = scanned
            entry = {"asset": sid, "kind": "scan", "tiles_per_2m": SCANS[name][1]}
        for suffix, data in (("albedo", albedo), ("rough", np.repeat(rmap[:, :, None], 3, 2)), ("nor", nrm)):
            fname = f"gen_{name[2:].lower()}_{suffix}.jpg"
            img = bpy.data.images.new(fname, N, N, float_buffer=False, is_data=True)
            rgba = np.concatenate([data[::-1].astype(np.float32), np.ones((N, N, 1), np.float32)], 2)
            img.pixels.foreach_set(rgba.ravel())
            img.filepath_raw = os.path.join(TEX, fname)
            img.file_format = "JPEG"
            img.save()
            bpy.data.images.remove(img)
            entry[{"albedo": "base", "rough": "rough", "nor": "normal"}[suffix]] = "textures/" + fname
        MATERIAL_MAP[name] = entry
        # The Blender material references the same files (USD → RealityKit, Cycles bakes).
        nt = MATS[name].node_tree
        b = nt.nodes["Principled BSDF"]
        for n in [n for n in nt.nodes if n.type in ("TEX_IMAGE", "NORMAL_MAP")]:
            nt.nodes.remove(n)
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(OUT, entry["base"]), check_existing=True)
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(OUT, entry["rough"]), check_existing=True)
        t.image.colorspace_settings.name = "Non-Color"
        nt.links.new(t.outputs["Color"], b.inputs["Roughness"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(OUT, entry["normal"]), check_existing=True)
        t.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    if used_concrete_scan:
        USED_ASSETS.append("smooth_concrete_floor")
    print("SURFACES", len([k for k in MATERIAL_MAP if k.startswith("M_")]))


apply_app_palette()
os.makedirs(OUT, exist_ok=True)
LIGHTMAPPED = sorted(static.material_slots[i].material.name for i in atlas_index)
GI_SAMPLES = int(argv[argv.index("--gi-samples") + 1]) if "--gi-samples" in argv else 1024
GI_RANGE = 4.0                                   # encoded irradiance range (see the app's decoder)
SUN_TO = S(0.6, 0.78, -0.4).normalized()        # same sun as the app (ShippingAtelierScene.setupLights)
# Soft architectural daylight (diagnostic C): neutral sky ≈ sun, 3° sun disc. Must match the app
# (ShippingAtelierScene: sky 1.25, sun 1250, PCF penumbra).
SKY_STRENGTH = 1.25
SKY_DESAT = 0.85
SUN_STRENGTH = 1.25 * math.pi
SUN_ANGLE = 3.0
NIGHT_SKY = tuple(v / SKY_STRENGTH for v in (0.035 * 0.62, 0.035 * 0.74, 0.035 * 1.0))


def night_spots():
    """The fixtures' light cones (the same in the night bake and the night probe panoramas)."""
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
    return spots


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
    l2 = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    px[:, :3] = px[:, :3] * (1 - SKY_DESAT) + l2[:, None] * SKY_DESAT      # neutral sky, no colour cast
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
    sun.data.angle = math.radians(SUN_ANGLE)
    sun.rotation_euler = (-SUN_TO).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    spots = night_spots()

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
            for n in [n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image and n.image.name.split(".")[0] in ("atelier_ao", "gi")]:
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
    world(SKY_STRENGTH)
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
    for o in MOVERS:
        o.hide_render = True
    bake_only = place_instances()
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
        for n in [n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image and n.image.name.split(".")[0] in ("atelier_ao", "gi")]:
            nt.nodes.remove(n)
    bake_gi()
    for o in bake_only:
        bpy.data.objects.remove(o, do_unlink=True)
    for ob in PROTOS.values():
        ob.hide_render = False
    for o in MOVERS:
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

# Inside / outside split (same lightmap atlas, same materials): RealityKit lights the hall with
# a local environment probe and only the outside with the sky; a sky receiver on one mesh that
# spans both would suppress the hall probe (measured).
HALL_MIN, HALL_MAX = Vector((-0.2, -20.6, FLOOR - 0.05)), Vector((14.45, 0.2, 99.0))   # Blender coords


def split_outside(ob, outside_name):
    import bmesh as _bm
    me = ob.data
    bm = _bm.new()
    bm.from_mesh(me)
    for f in bm.faces:
        c = f.calc_center_median()
        inside = HALL_MIN.x <= c.x <= HALL_MAX.x and HALL_MIN.y <= c.y <= HALL_MAX.y and c.z >= HALL_MIN.z
        f.select = not inside
    bm.to_mesh(me)
    bm.free()
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    out = next((o for o in bpy.context.selected_objects if o != ob), None)
    if out:
        out.name = out.data.name = outside_name
        for o in (ob, out):
            for o2 in scene.objects:
                o2.select_set(o2 == o)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.material_slot_remove_unused()
    return out


split_outside(static, "StaticOutside")
split_outside(props_ob, "StaticPropsOutside")

usd = os.path.join(OUT, "atelier_kit.usdc")
bpy.ops.wm.usd_export(
    filepath=usd, selected_objects_only=False, export_uvmaps=True, rename_uvmaps=True,
    export_materials=True, generate_preview_surface=True, export_normals=True,
    convert_orientation=True, export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y",
    export_textures_mode="KEEP", relative_paths=True,
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
            "use": "three basins on the basin inspection table, normalised to 540 mm, joined into atelier_kit.usdc",
        })
        continue
    if m.get("page_url"):                    # ambientCG scans (manifest written at download)
        shipped.append({
            "asset": asset, "source": m["page_url"], "license": m.get("license"), "license_url": m.get("license_url"),
            "authors": m.get("authors", []), "dimensions_note": m.get("dimensions_note"),
            "source_files": [{"url": f.get("url"), "file": f.get("zip_member"), "sha256": f.get("sha256")} for f in m.get("files", [])],
            "use": "scanned CC0 PBR set: albedo normalised to the app's colour, roughness re-centred, normal as scanned, "
                   "tiled to its real size into textures/gen_*",
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
tris = sum(len(p.vertices) - 2 for o in (static, props_ob) + MOVERS for p in o.data.polygons)
for o in (static, props_ob) + MOVERS:
    print("PART", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons))
print("KIT", usd, "triangles", tris, "static materials", [s.material.name for s in static.material_slots])


# ----------------------------------------------------------------------------- diagnostic shots
def shot(out_dir):
    """Path-traced reference of the SAME kit, camera and pose as the app harness (t = 20 s):
      B — the app's light (clamped HDRI, sun 2.3 × sky, 0.6° disc) and the app's PBR values;
      C — proposed light (neutral sky, soft 3° sun, sun ≈ 1.25 × sky).
    Material values are parsed from ShippingAtelierScene.swift so both renderers share them."""
    import numpy as np
    os.makedirs(out_dir, exist_ok=True)
    apply_app_palette()
    # Downloaded props: their resized base colour / ARM maps as in the app.
    for m in bpy.data.materials:
        e = MATERIAL_MAP.get(m.name)
        if not e or not m.use_nodes or m.name.startswith("M_"):
            continue
        nt = m.node_tree
        b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not b:
            continue
        if e.get("base"):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(os.path.join(OUT, e["base"]), check_existing=True)
            nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
        if e.get("arm"):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(os.path.join(OUT, e["arm"]), check_existing=True)
            t.image.colorspace_settings.name = "Non-Color"
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(t.outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
    # Pose at t = 20 s (between keys 19 and 21 of AtelierTimeline).
    hx, hz, heading, fork = 10.75, 13.3, -math.pi / 4, 0.32
    root.location = S(hx, FLOOR, hz)
    root.rotation_euler = (0, 0, heading)
    carriage.location = (0, 0, fork)
    fwd = Vector((math.cos(heading), 0, -math.sin(heading)))
    bx, bz = hx + fwd.x * 0.55, hz + fwd.z * 0.55
    batch_ob.location = S(bx, FLOOR + max(0, fork - 0.05), bz)
    batch_ob.rotation_euler = (0, 0, heading - math.pi)
    place_instances()
    # Catalogue products at their anchors, scaled to their catalogue length.
    lengths = {"Alda-160-70": 1.615, "Mona-170": 1.70, "Luce": 1.70, "Noemi-170": 1.705, "Sofia-150-2015-Corona-fbx": 1.50}
    models = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Salini", "CatalogMedia", "models")
    for e in GROUPS.get("Anchors", []):
        if not e.name.startswith("anchor_product_"):
            continue
        file = e.name[len("anchor_product_"):]
        before = set(bpy.data.objects)
        bpy.ops.wm.usd_import(filepath=os.path.join(models, file + ".usdz"))
        new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        if not new:
            continue
        pts = [o.matrix_world @ Vector(c) for o in new for c in o.bound_box]
        lo, hi = Vector(map(min, *pts)), Vector(map(max, *pts))
        k = lengths.get(file, 1.7) / max(hi.x - lo.x, hi.y - lo.y)
        rot = Matrix.Rotation(math.pi / 2, 4, "Z") if (hi.y - lo.y) > (hi.x - lo.x) else Matrix.Identity(4)
        m = Matrix.Translation(e.location) @ rot @ Matrix.Scale(k, 4) @ Matrix.Translation(-Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)))
        white = bpy.data.materials.new("gelcoat")
        white.use_nodes = True
        wb = white.node_tree.nodes["Principled BSDF"]
        wb.inputs["Base Color"].default_value = (0.9, 0.89, 0.86, 1)
        wb.inputs["Roughness"].default_value = 0.22
        for o in new:
            o.matrix_world = m @ o.matrix_world
            o.data.materials.clear()
            o.data.materials.append(white)
    # Camera: true isometric orthographic, as AtelierCamera (focus, scale 15.5 = half height).
    focus = S(12.5, FLOOR, 11.0)
    d = S(1, 1, 1).normalized()
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.ortho_scale = 31.0
    cam.data.clip_end = 400
    cam.location = focus + d * 140
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    W, H = (int(v) for v in (argv[argv.index("--shot-size") + 1].split("x") if "--shot-size" in argv else ("390", "844")))
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for dv in prefs.devices:
            dv.use = True
        scene.cycles.device = "GPU"
    except Exception:
        pass
    scene.cycles.samples = int(argv[argv.index("--shot-samples") + 1]) if "--shot-samples" in argv else 64
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    for vt in ("Khronos PBR Neutral", "PBR Neutral", "Standard"):
        try:
            scene.view_settings.view_transform = vt
            break
        except TypeError:
            continue
    # Sky image (clamped sun disc, normalised to mean 1), optionally desaturated.
    src = bpy.data.images.load(os.path.join(SRC, "factory_yard", "factory_yard_1k.hdr"))
    w, h = src.size
    px = np.empty(w * h * 4, dtype=np.float32)
    src.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    lum = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    mean = float(lum.mean())
    px[:, :3] *= (np.minimum(1.0, 6 * mean / np.maximum(lum, 1e-6)) / mean)[:, None]

    def sky(desat):
        q = px.copy()
        l2 = q[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
        q[:, :3] = q[:, :3] * (1 - desat) + l2[:, None] * desat
        img = bpy.data.images.new(f"sky{desat}", w, h, float_buffer=True, is_data=True)
        img.pixels.foreach_set(q.ravel())
        img.pack()
        return img

    def world(img, strength):
        wd = bpy.data.worlds.new("shot")
        wd.use_nodes = True
        nt = wd.node_tree
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = img
        nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
        nt.nodes["Background"].inputs["Strength"].default_value = strength
        scene.world = wd

    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (-SUN_TO).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    variants = {
        "B-cycles-app-light": dict(desat=0.0, sky=1.0, sun=2.3, angle=0.6, exposure=-0.85, color=(1.0, 0.95, 0.87)),
        "C-cycles-proposed": dict(desat=SKY_DESAT, sky=SKY_STRENGTH, sun=SUN_STRENGTH / math.pi, angle=SUN_ANGLE,
                                  exposure=-0.55, color=(1.0, 0.98, 0.95)),
    }
    only = argv[argv.index("--shot-only") + 1] if "--shot-only" in argv else ""
    for name, v in variants.items():
        if only and only not in name:
            continue
        world(sky(v["desat"]), v["sky"])
        sun.data.energy = v["sun"] * math.pi
        sun.data.angle = math.radians(v["angle"])
        sun.data.color = v["color"]
        scene.view_settings.exposure = v["exposure"]
        scene.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("SHOT", name, scene.view_settings.view_transform)


if "--shot" in argv:
    shot(os.path.abspath(argv[argv.index("--shot") + 1]))


def probe_panoramas(out_dir):
    """Equirectangular Cycles panoramas of the baked-lit day scene from the hall and dock probe
    centres: local environment probes (RealityKit VirtualEnvironmentProbeComponent, parallax box).
    Movers are hidden (they are dynamic); trees/shrubs and props are in. Radiance .hdr, linear."""
    import numpy as np
    place_instances()
    for o in MOVERS:
        o.hide_render = True
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for dv in prefs.devices:
            dv.use = True
        scene.cycles.device = "GPU"
    except Exception:
        pass
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = 0
    src = bpy.data.images.load(os.path.join(SRC, "factory_yard", "factory_yard_1k.hdr"))
    w, h = src.size
    px = np.empty(w * h * 4, dtype=np.float32)
    src.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    lum = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    mean = float(lum.mean())
    px[:, :3] *= (np.minimum(1.0, 6 * mean / np.maximum(lum, 1e-6)) / mean)[:, None]
    l2 = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    px[:, :3] = px[:, :3] * (1 - SKY_DESAT) + l2[:, None] * SKY_DESAT
    sky = bpy.data.images.new("probe_sky", w, h, float_buffer=True, is_data=True)
    sky.pixels.foreach_set(px.ravel())
    sky.pack()
    wd = bpy.data.worlds.new("probe")
    wd.use_nodes = True
    env = wd.node_tree.nodes.new("ShaderNodeTexEnvironment")
    env.image = sky
    wd.node_tree.links.new(env.outputs["Color"], wd.node_tree.nodes["Background"].inputs["Color"])
    wd.node_tree.nodes["Background"].inputs["Strength"].default_value = SKY_STRENGTH
    scene.world = wd
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = SUN_STRENGTH
    sun.data.angle = math.radians(SUN_ANGLE)
    sun.rotation_euler = (-SUN_TO).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("pano", bpy.data.cameras.new("pano"))
    cam.data.type = "PANO"
    cam.data.panorama_type = "EQUIRECTANGULAR"
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 1024, 512
    scene.render.image_settings.file_format = "HDR"
    scene.render.image_settings.color_depth = "32"
    def render(suffix):
        for name, (x, y, z) in (("probe_hall", (7.0, FLOOR + 1.6, 10.0)), ("probe_dock", (21.0, 2.0, 13.5))):
            cam.location = S(x, y, z)
            cam.rotation_euler = (math.pi / 2, 0, -math.pi / 2)    # +X centre, Z up (equirect convention)
            scene.render.filepath = os.path.join(out_dir, name + suffix + ".hdr")
            bpy.ops.render.render(write_still=True)
            print("PROBE", name + suffix)

    render("")
    # Night: the same light as the night bake — dim tinted sky, lit fixtures and their spots, no
    # sun (the app's dim moon is live). RealityKit swaps these in with the night lightmap.
    sun.hide_render = True
    tint = wd.node_tree.nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 1.0
    tint.inputs[7].default_value = (*[v * SKY_STRENGTH for v in NIGHT_SKY], 1)
    wd.node_tree.links.new(env.outputs["Color"], tint.inputs[6])
    wd.node_tree.links.new(tint.outputs[2], wd.node_tree.nodes["Background"].inputs["Color"])
    wd.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    lamp = MATS["M_Lamp"].node_tree.nodes["Principled BSDF"]
    lamp.inputs["Emission Color"].default_value = (1.0, 0.92, 0.8, 1)
    lamp.inputs["Emission Strength"].default_value = 25.0
    night_spots()
    render("_night")
    lamp.inputs["Emission Strength"].default_value = 0.0


if "--probes" in argv:
    probe_panoramas(OUT)
