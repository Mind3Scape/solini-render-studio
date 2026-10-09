# Salini Insight · models for the shipping section: the counterbalance forklift (separate mast,
# carriage and wheels for the app's kinematics) and workers. Executed inside build_atelier_kit.py
# (uses its S / MATS / GROUPS / box / cyl / _obj helpers). Scene coordinates: metres, x east,
# y up, z south; vehicle-local models face +x with the fork heel at the origin.
import math

import bmesh
import bpy
from mathutils import Matrix, Vector


def rod(p0, p1, r, mat, group="Static", seg=12, r1=None, bevel=0.0):
    """A cylinder (or cone) between two scene points."""
    a, b = S(*p0), S(*p1)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r1 is None else r1,
                          depth=d.length)
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=bm.verts)
    return _obj("rod", bm, mat, group, bevel, 1)


def ring(c, axis, major, minor, mat, group="Static", seg=32, seg2=8):
    """A torus (steering wheel, hose) centred at scene point c around a scene axis."""
    bm = bmesh.new()
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for j in range(seg2):
            b = 2 * math.pi * j / seg2
            rr = major + minor * math.cos(b)
            bm.verts.new((rr * math.cos(a), rr * math.sin(a), minor * math.sin(b)))
    bm.verts.ensure_lookup_table()
    for i in range(seg):
        for j in range(seg2):
            v = [bm.verts[((i + di) % seg) * seg2 + (j + dj) % seg2] for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1))]
            bm.faces.new(v)
    ax = S(*axis) - S(0, 0, 0)
    rot = ax.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(S(*c)) @ rot, verts=bm.verts)
    return _obj("ring", bm, mat, group, 0)


def tapered_blade(x0, x1, y0, y1, z0, z1, tip, mat, group):
    """A fork blade: full thickness at the heel, thinned to `tip` at the point, rounded edges."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((x1 - x0, z1 - z0, y1 - y0)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=S((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), verts=bm.verts)
    for v in bm.verts:
        if v.co.x > (x0 + x1) / 2 and v.co.z > (y0 + y1) / 2:   # top of the tip comes down
            v.co.z = y0 + tip
    return _obj("blade", bm, mat, group, 0.008, 2)


# ----------------------------------------------------------------------------- people
def mannequin(joints, bones, radius, group="Static", root="pelvis", waist=None, lower=None, upper=None, limbs=(),
              bands=()):
    """A smooth figure from a joint graph (Skin + Subdivision), each face coloured by its
    nearest bone. joints: name → scene point; bones: (a, b, material); radius: name → r."""
    names = list(joints)
    idx = {n: i for i, n in enumerate(names)}
    me = bpy.data.meshes.new("person")
    me.from_pydata([S(*joints[n]) for n in names], [(idx[a], idx[b]) for a, b, _ in bones], [])
    ob = bpy.data.objects.new("person", me)
    scene.collection.objects.link(ob)
    skin = ob.modifiers.new("skin", "SKIN")
    skin.use_smooth_shade = True
    for i, n in enumerate(names):
        r = radius.get(n, 0.04)
        me.skin_vertices[0].data[i].radius = (r, r) if not isinstance(r, tuple) else r
    me.skin_vertices[0].data[idx[root]].use_root = True
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="skin")
    bpy.ops.object.modifier_apply(modifier="sub")
    mats = []
    for _, _, m in bones:
        if m not in mats:
            mats.append(m)
    for _, _, m in bands:
        if m not in mats:
            mats.append(m)
    for m in mats:
        ob.data.materials.append(MATS[m])
    if waist is not None:                                     # a clean hem: cut the mesh at the waist
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        for y in [waist] + [y for b in bands for y in b[:2]]:
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=S(0, y, 0), plane_no=Vector((0, 0, 1)))
        bm.to_mesh(ob.data)
        bm.free()
    segs = [(S(*joints[a]), S(*joints[b]), mats.index(m), (a, b) in limbs) for a, b, m in bones]

    def near(p):
        best, bi, limb = 1e9, 0, False
        for a, b, mi, is_limb in segs:
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (a + ab * t - p).length
            if d < best:
                best, bi, limb = d, mi, is_limb
        return bi, limb
    for poly in ob.data.polygons:
        mi, limb = near(poly.center)
        if waist is not None and not limb:                    # torso / legs: by the hem
            mi = mats.index(lower if poly.center.z < S(0, waist, 0).z else upper)
            for y0, y1, m in bands:
                if S(0, y0, 0).z < poly.center.z < S(0, y1, 0).z:
                    mi = mats.index(m)
        poly.material_index = mi
        poly.use_smooth = True
    GROUPS.setdefault(group, []).append(ob)
    return ob


def person2(x, z, heading, kind="stand", coat="M_Coat", trousers="M_Trousers", reach=0.0, hat=None, vest=False,
            group="Static", floor=None, local=None):
    """A worker of 1.75 m: stand / inspect (reaching forwards by `reach`) / walk / seated.
    `local` (a 4×4 scene matrix) places a vehicle-local figure (the driver)."""
    f = (FLOOR if 0 <= x <= 14 and 0 <= z <= 20 else 0.0) if floor is None else floor
    fx, fz = math.cos(heading), -math.sin(heading)
    sx, sz = -fz, fx

    def P(fwd, up, side):
        p = (x + fx * fwd + sx * side, f + up, z + fz * fwd + sz * side)
        if local is not None:
            v = local @ Vector((p[0], p[1], p[2], 1))
            return (v.x, v.y, v.z)
        return p
    J = {}
    lean = {"inspect": 0.07 + 0.08 * reach, "walk": 0.02}.get(kind, 0.0)
    if kind == "seated":
        hip_y, knee, ankle = 0.0, (0.36, 0.06), (0.38, -0.36)
        J["pelvis"] = (0.0, hip_y + 0.08, 0)
        J["spine"] = (-0.02, hip_y + 0.3, 0)
        J["chest"] = (-0.02, hip_y + 0.48, 0)
        J["neck"] = (0.0, hip_y + 0.64, 0)
        for s, sd in (("l", -1), ("r", 1)):
            J[f"hip_{s}"] = (0.02, hip_y + 0.06, sd * 0.1)
            J[f"knee_{s}"] = (knee[0], hip_y + knee[1] + 0.04, sd * 0.11)
            J[f"ankle_{s}"] = (ankle[0], hip_y + ankle[1], sd * 0.11)
            J[f"shoulder_{s}"] = (-0.01, hip_y + 0.58, sd * 0.19)
            J[f"elbow_{s}"] = (0.16, hip_y + 0.36, sd * 0.22)
            J[f"wrist_{s}"] = (0.36, hip_y + 0.27, sd * 0.16)
            J[f"hand_{s}"] = (0.42, hip_y + 0.26, sd * 0.14)
        head_y = hip_y + 0.78
    else:
        J["pelvis"] = (0.0, 0.95, 0)
        J["spine"] = (lean * 0.4, 1.15, 0)
        J["chest"] = (lean * 0.8, 1.33, 0)
        J["neck"] = (lean * 1.2, 1.5, 0)
        for s, sd in (("l", -1), ("r", 1)):
            stride = {"walk": 0.18 * sd}.get(kind, 0.0)
            J[f"hip_{s}"] = (0.0, 0.92, sd * 0.1)
            J[f"knee_{s}"] = (0.03 + stride * 0.5, 0.5, sd * 0.1)
            J[f"ankle_{s}"] = (stride, 0.09, sd * 0.1)
            J[f"shoulder_{s}"] = (lean, 1.43, sd * 0.19)
            if kind == "inspect":
                J[f"elbow_{s}"] = (lean + 0.14 + 0.25 * reach, 1.18, sd * 0.23)
                J[f"wrist_{s}"] = (lean + 0.34 + 0.45 * reach, 1.04 + 0.1 * reach, sd * 0.17)
                J[f"hand_{s}"] = (lean + 0.42 + 0.48 * reach, 1.02 + 0.1 * reach, sd * 0.15)
            else:
                swing = {"walk": -0.16 * sd}.get(kind, 0.0)
                J[f"elbow_{s}"] = (0.02 + swing * 0.5, 1.16, sd * 0.24)
                J[f"wrist_{s}"] = (0.05 + swing, 0.9, sd * 0.235)
                J[f"hand_{s}"] = (0.06 + swing, 0.81, sd * 0.23)
        head_y = 1.64
    pts = {n: P(*v) for n, v in J.items()}
    top = vest and "M_Vest" or coat
    bones = [("pelvis", "spine", top), ("spine", "chest", top), ("chest", "neck", top)]
    for s in ("l", "r"):
        bones += [("pelvis", f"hip_{s}", trousers), (f"hip_{s}", f"knee_{s}", trousers), (f"knee_{s}", f"ankle_{s}", trousers),
                  ("chest", f"shoulder_{s}", top), (f"shoulder_{s}", f"elbow_{s}", coat), (f"elbow_{s}", f"wrist_{s}", coat),
                  (f"wrist_{s}", f"hand_{s}", "M_Skin")]
    radius = {"pelvis": 0.13, "spine": 0.125, "chest": 0.15, "neck": 0.055}
    for s in ("l", "r"):
        radius.update({f"hip_{s}": 0.085, f"knee_{s}": 0.06, f"ankle_{s}": 0.045, f"shoulder_{s}": 0.06,
                       f"elbow_{s}": 0.045, f"wrist_{s}": 0.034, f"hand_{s}": 0.04})
    arms = tuple((a, b) for a, b, _ in bones if "shoulder" in b or "elbow" in a or "wrist" in a or "shoulder" in a)
    waist_y = pts["pelvis"][1] + (0.12 if kind == "seated" else 0.07)
    base = pts["pelvis"][1] - (0.08 if kind == "seated" else 0.95)
    bands = [(base + y, base + y + 0.035, "M_LineWhite") for y in ((1.1, 1.25) if kind != "seated" else (0.32, 0.46))] if vest else []
    mannequin(pts, bones, radius, group, waist=waist_y, lower=trousers, upper=top, limbs=arms, bands=bands)
    # Head (slightly egg-shaped), hair or hat, shoes.
    hx = lean * 1.3 if kind != "seated" else 0.0
    head = P(hx + 0.01, head_y, 0)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=0.1)
    bmesh.ops.scale(bm, vec=Vector((0.95, 0.88, 1.15)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=S(*head), verts=bm.verts)
    o = _obj("head", bm, "M_Skin", group, 0)
    for poly in o.data.polygons:
        poly.use_smooth = True
    capc = P(hx - 0.005, head_y + 0.045, 0)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=0.108 if hat else 0.104)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
    bmesh.ops.scale(bm, vec=Vector((1.0, 0.96, 0.95)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=S(*capc), verts=bm.verts)
    o = _obj("hair", bm, hat or "M_Hair", group, 0)
    for poly in o.data.polygons:
        poly.use_smooth = True
    if hat:                                                     # hard-hat brim
        c = P(hx + 0.03, head_y + 0.05, 0)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.135, radius2=0.13, depth=0.012)
        bmesh.ops.scale(bm, vec=Vector((1.15, 1.0, 1.0)), verts=bm.verts)
        bmesh.ops.translate(bm, vec=S(*c), verts=bm.verts)
        _obj("brim", bm, hat, group, 0.004)
    for s in ("l", "r"):
        a = J[f"ankle_{s}"]
        fwd_dir = (fx, fz)
        heel = P(a[0] - 0.04, a[1] - 0.06 if kind != "seated" else a[1] - 0.06, a[2])
        toe = P(a[0] + 0.17, a[1] - 0.06 if kind != "seated" else a[1] - 0.06, a[2])
        rod((heel[0], heel[1] + 0.035, heel[2]), (toe[0], toe[1] + 0.03, toe[2]), 0.045, "M_Rubber", group, seg=10,
            r1=0.04, bevel=0.015)


# ----------------------------------------------------------------------------- forklift
FRONT_AXLE, WHEELBASE = -0.45, 1.25          # = AtelierTimeline.frontAxle / wheelbase
FRONT_R, REAR_R = 0.27, 0.2
MAST_PIVOT = (-0.17, 0.30, 0.0)


def fork_wheel(name, x, y, z, r, width, outward):
    """A solid tyre with rounded shoulders, a painted rim, hub and wheel nuts (so a turning
    wheel reads). Its own group; the origin is set to the wheel centre after realisation."""
    g = name
    cyl(x, z - width / 2, z + width / 2, y, r, "M_Rubber", g, seg=32, bevel=0.05, axis="z")
    zo = z + outward * width / 2
    cyl(x, zo - outward * 0.02 - 0.012, zo - outward * 0.02 + 0.012, y, r * 0.66, "M_Chassis", g, seg=28, bevel=0.01, axis="z")
    cyl(x, min(zo, zo + outward * 0.02), max(zo, zo + outward * 0.02), y, r * 0.3, "M_Galv", g, seg=20, bevel=0.006, axis="z")
    for k in range(5):
        a = 2 * math.pi * k / 5
        cyl(x + math.cos(a) * r * 0.42, min(zo, zo + outward * 0.03), max(zo, zo + outward * 0.03), y + math.sin(a) * r * 0.42,
            0.014, "M_Galv", g, seg=8, bevel=0, axis="z")
    return g


def forklift2():
    """A compact 1.5 t electric counterbalance forklift, fork heel at the origin facing +x:
    Forklift_Body (chassis, counterweight, guard, seat, driver), Forklift_Mast (tilts about
    MAST_PIVOT), Forklift_Carriage (lifts; forks hooked on it), four wheels."""
    g = "Forklift_Body"
    Y = "M_Forklift"
    # Chassis between the axles, narrow nose between the front wheels.
    box(-1.52, -0.72, 0.16, 0.72, -0.52, 0.52, Y, g, bevel=0.035, segments=3)
    box(-0.74, -0.3, 0.16, 0.6, -0.3, 0.3, Y, g, bevel=0.04, segments=2)
    for sz in (-1, 1):                                                        # front fenders
        box(-0.8, -0.12, 0.56, 0.6, sz * 0.3 if sz > 0 else -0.54, 0.54 if sz > 0 else -0.3, Y, g, bevel=0.02, segments=2)
        box(-0.8, -0.76, 0.3, 0.6, sz * 0.3 if sz > 0 else -0.54, 0.54 if sz > 0 else -0.3, Y, g, bevel=0.015, segments=1)
    # Counterweight: rounded block over the rear (steer) wheels, open underneath for them.
    box(-2.0, -1.44, 0.42, 1.02, -0.54, 0.54, "M_Coping", g, bevel=0.1, segments=5)
    box(-1.98, -1.44, 0.12, 0.44, -0.24, 0.24, "M_Coping", g, bevel=0.05, segments=2)
    for sz in (-1, 1):                                                        # rear lights
        box(-2.004, -1.97, 0.82, 0.92, sz * 0.36 - 0.06, sz * 0.36 + 0.06, "M_TailLight", g, bevel=0.01)
    box(-2.0, -1.96, 0.24, 0.32, -0.08, 0.08, "M_Chassis", g, bevel=0.01)      # tow pin
    # Battery hood with the seat, cowl and dash.
    box(-1.48, -0.72, 0.72, 0.9, -0.48, 0.48, Y, g, bevel=0.03, segments=3)
    box(-0.72, -0.3, 0.56, 0.62, -0.46, 0.46, "M_Rubber", g, bevel=0.01)                   # floor plate
    box(-0.5, -0.3, 0.6, 1.0, -0.36, 0.36, Y, g, bevel=0.06, segments=3)                    # cowl
    box(-0.48, -0.38, 0.98, 1.02, -0.2, 0.2, "M_Screen", g, bevel=0.01)
    box(-1.32, -0.86, 0.9, 1.0, -0.24, 0.24, "M_Rubber", g, bevel=0.04, segments=3)        # seat cushion
    box(-1.42, -1.3, 0.96, 1.42, -0.24, 0.24, "M_Rubber", g, bevel=0.05, segments=3)       # backrest
    box(-1.36, -1.0, 1.0, 1.04, 0.24, 0.3, "M_Rubber", g, bevel=0.015)                      # armrest
    rod((-0.44, 0.98, 0.0), (-0.62, 1.2, 0.0), 0.028, "M_Chassis", g)                      # steering column
    ring((-0.64, 1.22, 0.0), (0.55, 0.85, 0.0), 0.16, 0.017, "M_Rubber", g)                # steering wheel
    rod((-0.64, 1.22, 0.0), (-0.56, 1.27, 0.12), 0.012, "M_Rubber", g, seg=8)
    for k, dz in enumerate((0.18, 0.24, 0.3)):                                             # hydraulic levers
        rod((-0.46, 1.0, dz), (-0.52, 1.18, dz), 0.008, "M_Chassis", g, seg=6)
        rod((-0.52, 1.18, dz), (-0.525, 1.21, dz), 0.016, "M_Chassis" if k else "M_Beacon", g, seg=8)
    box(-0.98, -0.7, 0.28, 0.31, 0.5, 0.58, "M_Galv", g, bevel=0.006)                      # step
    # Overhead guard: inclined front posts, rear posts, frame and roof slats.
    for sz in (-0.46, 0.46):
        rod((-0.62, 0.6, sz), (-0.82, 2.1, sz), 0.035, "M_Chassis", g)
        rod((-1.52, 0.9, sz), (-1.58, 2.1, sz), 0.035, "M_Chassis", g)
        box(-1.64, -0.76, 2.08, 2.14, sz - 0.03, sz + 0.03, "M_Chassis", g, bevel=0.01)
    for x in (-1.6, -0.8):
        box(x - 0.03, x + 0.03, 2.08, 2.14, -0.49, 0.49, "M_Chassis", g, bevel=0.01)
    for k in range(6):
        x = -1.5 + k * 0.13
        box(x - 0.02, x + 0.02, 2.1, 2.15, -0.44, 0.44, "M_Chassis", g, bevel=0.004, segments=1)
    for sz in (-0.5, 0.5):                                                    # work lights
        box(-0.86, -0.76, 1.98, 2.08, sz - 0.05, sz + 0.05, "M_Chassis", g, bevel=0.012)
        box(-0.761, -0.755, 2.0, 2.06, sz - 0.04, sz + 0.04, "M_Headlight", g, bevel=0)
    cyl(-1.5, 2.15, 2.18, 0.32, 0.055, "M_Chassis", g, seg=16)              # beacon
    cyl(-1.5, 2.18, 2.27, 0.32, 0.045, "M_Beacon", g, seg=16, bevel=0.02)
    # Tilt cylinders between the cowl and the mast.
    for sz in (-0.33, 0.33):
        rod((-0.6, 0.72, sz), (-0.3, 0.98, sz), 0.04, "M_Chassis", g)
        rod((-0.42, 0.82, sz), (-0.26, 1.0, sz), 0.018, "M_Galv", g, seg=10)
    # The driver.
    person2(-1.06, 0.0, 0.0, kind="seated", coat="M_Workwear", vest=True, hat="M_Toolbox", group=g, floor=0.97)
    # Mast (tilts about MAST_PIVOT): outer and inner uprights, ties, lift cylinder, chains.
    m = "Forklift_Mast"
    for sz in (-1, 1):
        box(-0.26, -0.1, 0.1, 2.2, sz * 0.3 if sz > 0 else -0.4, 0.4 if sz > 0 else -0.3, "M_Chassis", m, bevel=0.012)
        box(-0.2, -0.11, 0.14, 2.14, sz * 0.24 if sz > 0 else -0.3, 0.3 if sz > 0 else -0.24, "M_Steel", m, bevel=0.01)
        box(-0.14, -0.105, 0.42, 2.04, sz * 0.12 - 0.018, sz * 0.12 + 0.018, "M_Rubber", m, bevel=0.004, segments=1)  # chain
        cyl(-0.12, sz * 0.12 - 0.03, sz * 0.12 + 0.03, 2.06, 0.06, "M_Galv", m, seg=16, axis="z")
    box(-0.26, -0.14, 2.1, 2.2, -0.4, 0.4, "M_Chassis", m, bevel=0.012)
    box(-0.26, -0.16, 0.1, 0.22, -0.4, 0.4, "M_Chassis", m, bevel=0.012)
    box(-0.26, -0.18, 1.2, 1.3, -0.3, 0.3, "M_Chassis", m, bevel=0.01)
    cyl(-0.3, 0.14, 1.75, 0.0, 0.05, "M_Chassis", m, seg=16, bevel=0.01)
    cyl(-0.3, 1.75, 2.06, 0.0, 0.03, "M_Galv", m, seg=12, bevel=0.005)
    # Carriage at fork height 0 (blade underside on the floor): bars, backrest, forks.
    c = "Forklift_Carriage"
    for y0, y1 in ((0.1, 0.2), (0.36, 0.46)):
        box(-0.09, -0.045, y0, y1, -0.47, 0.47, "M_Chassis", c, bevel=0.01)
    for sz in (-1, 1):
        box(-0.09, -0.05, 0.1, 0.46, sz * 0.43 if sz > 0 else -0.47, 0.47 if sz > 0 else -0.43, "M_Chassis", c, bevel=0.008)
    for k in range(6):
        zz = -0.45 + k * 0.18
        box(-0.075, -0.055, 0.46, 1.22, zz - 0.012, zz + 0.012, "M_Chassis", c, bevel=0.004, segments=1)
    box(-0.08, -0.05, 1.19, 1.24, -0.47, 0.47, "M_Chassis", c, bevel=0.008)
    box(-0.08, -0.05, 0.84, 0.87, -0.47, 0.47, "M_Chassis", c, bevel=0.006)
    for sz in (-0.3, 0.3):                                                    # forks
        box(-0.045, 0.0, 0.0, 0.5, sz - 0.06, sz + 0.06, "M_Chassis", c, bevel=0.008)
        box(-0.095, -0.04, 0.4, 0.48, sz - 0.06, sz + 0.06, "M_Chassis", c, bevel=0.008)
        tapered_blade(-0.02, AtelierFork.LENGTH, 0.0, AtelierFork.THICK, sz - 0.06, sz + 0.06, 0.02, "M_Chassis", c)
    # Wheels: front (drive) and rear (steer).
    for name, x, y, z, r, w, out in (("Forklift_WheelFL", FRONT_AXLE, FRONT_R, -0.41, FRONT_R, 0.2, -1),
                                     ("Forklift_WheelFR", FRONT_AXLE, FRONT_R, 0.41, FRONT_R, 0.2, 1),
                                     ("Forklift_WheelRL", FRONT_AXLE - WHEELBASE, REAR_R, -0.36, REAR_R, 0.16, -1),
                                     ("Forklift_WheelRR", FRONT_AXLE - WHEELBASE, REAR_R, 0.36, REAR_R, 0.16, 1)):
        fork_wheel(name, x, y, z, r, w, out)
    return True


class AtelierFork:
    LENGTH = 0.98     # = AtelierTimeline.forkLength
    THICK = 0.06      # blade top at the pallet deck underside when the forks are at emptyFork


# ----------------------------------------------------------------------------- truck cab
def prism(profile, z0, z1, mat, group="Static", bevel=0.0, segments=2):
    """A profile in the (x, y) plane (scene metres, counter-clockwise) extruded from z0 to z1."""
    bm = bmesh.new()
    a = [bm.verts.new(S(x, y, z0)) for x, y in profile]
    b = [bm.verts.new(S(x, y, z1)) for x, y in profile]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj("prism", bm, mat, group, bevel, segments, smooth=bevel > 0)


def arch(xc, yc, r, thick, z0, z1, mat, group, a0=0.0, a1=math.pi, seg=16):
    """A wheel arch (part of a ring) in the (x, y) plane."""
    outer = [(xc + (r + thick) * math.cos(a0 + (a1 - a0) * k / seg), yc + (r + thick) * math.sin(a0 + (a1 - a0) * k / seg)) for k in range(seg + 1)]
    inner = [(xc + r * math.cos(a1 - (a1 - a0) * k / seg), yc + r * math.sin(a1 - (a1 - a0) * k / seg)) for k in range(seg + 1)]
    return prism(outer + inner, z0, z1, mat, group, 0.01, 1)


def tractor_cab(zc, g):
    """A cab-over tractor: raked windscreen, aero roof fairing, doors with shut lines, handles
    and steps, fenders over the steer axle, bumper with integrated lamps (x forwards = +x)."""
    W = 1.24
    cab = [(29.9, 0.98), (32.38, 0.98), (32.42, 2.12), (32.14, 3.52), (31.86, 3.74), (29.9, 3.74)]
    prism(cab, zc - W, zc + W, "M_TruckCab", g, 0.07, 3)
    prism([(29.95, 3.7), (31.7, 3.7), (31.25, 4.02), (30.4, 4.14), (29.95, 4.14)], zc - 1.16, zc + 1.16, "M_TruckCab", g, 0.06, 3)
    # Windscreen (along the rake), sun visor, wipers.
    prism([(32.425, 2.2), (32.445, 2.2), (32.175, 3.46), (32.155, 3.46)], zc - 1.08, zc + 1.08, "M_Glass", g)
    prism([(32.12, 3.5), (32.3, 3.5), (32.28, 3.56), (32.1, 3.58)], zc - 1.15, zc + 1.15, "M_Chassis", g, 0.01, 1)
    for dz in (-0.45, 0.35):
        rod((32.44, 2.24, zc + dz - 0.3), (32.4, 2.4, zc + dz + 0.25), 0.012, "M_Chassis", g, seg=6)
    for side in (-1, 1):
        zs = zc + side * (W + 0.004)
        z0, z1 = (zs - 0.01, zs + 0.012) if side > 0 else (zs - 0.012, zs + 0.01)
        # Side window following the door's front edge, door shut lines, handle, steps.
        prism([(30.95, 2.32), (32.18, 2.32), (31.98, 3.36), (30.95, 3.36)], z0, z1, "M_Glass", g)
        for x in (30.85, 32.25):
            box(x - 0.006, x + 0.006, 1.05, 3.4, z0, z1, "M_Chassis", g, bevel=0)
        box(30.85, 32.25, 1.04, 1.052, z0, z1, "M_Chassis", g, bevel=0)
        box(31.0, 31.2, 2.05, 2.09, z0 - side * 0.01, z1 + side * 0.01, "M_Galv", g, bevel=0.01)
        for k, y in enumerate((0.42, 0.72)):
            box(31.2, 31.75, y, y + 0.05, zc + side * (W - 0.05) - 0.2, zc + side * (W - 0.05) + 0.2, "M_Galv", g, bevel=0.01)
        rod((32.3, 1.2, zc + side * (W + 0.04)), (32.25, 2.0, zc + side * (W + 0.04)), 0.015, "M_Galv", g, seg=8)   # grab rail
        # Fender over the steer axle and the corner deflector.
        arch(31.1, 0.52, 0.6, 0.05, zc + side * 1.0 - 0.18, zc + side * 1.0 + 0.18, "M_Chassis", g, 0.15, math.pi - 0.15)
        # Mirror arm and head.
        zm = zc + side * 1.5
        rod((32.2, 3.1, zc + side * W), (32.24, 3.1, zm), 0.02, "M_Chassis", g, seg=8)
        box(32.16, 32.3, 2.45, 3.12, zm - 0.07, zm + 0.07, "M_Chassis", g, bevel=0.03, segments=2)
    # Grille, bumper with lamps, roof marker lights.
    box(32.4, 32.46, 1.25, 2.05, zc - 0.85, zc + 0.85, "M_Grille", g, bevel=0.015)
    for k in range(5):
        y = 1.32 + k * 0.15
        box(32.45, 32.49, y, y + 0.035, zc - 0.82, zc + 0.82, "M_Galv", g, bevel=0)
    prism([(32.2, 0.62), (32.55, 0.62), (32.6, 0.85), (32.52, 1.14), (32.2, 1.14)], zc - 1.25, zc + 1.25, "M_Chassis", g, 0.04, 2)
    for side in (-1, 1):
        box(32.56, 32.6, 0.92, 1.06, zc + side * 0.9 - 0.2, zc + side * 0.9 + 0.2, "M_Headlight", g, bevel=0.015)
        box(32.5, 32.56, 0.7, 0.78, zc + side * 0.6 - 0.12, zc + side * 0.6 + 0.12, "M_Headlight", g, bevel=0.01)
    for dz in (-0.5, 0.0, 0.5):
        box(31.7, 31.8, 4.13, 4.18, zc + dz - 0.06, zc + dz + 0.06, "M_Beacon", g, bevel=0.01)
