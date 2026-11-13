"""Builds the first-person arm and the consumable props as glTF models.

Run from the project root:
    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_fp_assets.py

Inputs (written by `godot --path . -- --visual-tour=export`):
    assets/fp/source/hand_rig.json   skeleton of the hand in its straight rest pose
    assets/fp/source/*.png           label / wrap / skin textures
Outputs:
    assets/fp/arm.glb, bottle.glb, can.glb, cigarette.glb, lighter.glb, pack.glb, six_pack.glb

Everything is described in Godot coordinates (Y up, -Z forward) and converted
with `g2b`; the glTF exporter converts back, so node names, pivots and sizes
match what scripts/fx/fp_props.gd and fp_hand.gd expect.
"""
import bpy, bmesh, json, math, os
from mathutils import Vector, Matrix, Quaternion

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "fp", "source")
# FP_OUT overrides the output folder (test builds); names after "--" pick builders.
OUT = os.environ.get("FP_OUT") or os.path.join(ROOT, "assets", "fp")
TAU = math.pi * 2
IMAGES = {}


def g2b(v):
    return Vector((v[0], -v[2], v[1]))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    IMAGES.clear()


def collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


# --- materials ------------------------------------------------------------------

def image(name):
    if name not in IMAGES:
        IMAGES[name] = bpy.data.images.load(os.path.join(SRC, name + ".png"))
    return IMAGES[name]


def linear(color):
    def channel(c):
        return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4
    return (channel(color[0]), channel(color[1]), channel(color[2]), color[3])


def material(name, color=(1, 1, 1, 1), rough=.5, metal=0.0, texture=None, alpha=None, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    # Colours below are written as in Godot (sRGB); Blender/glTF factors are linear.
    color = linear(color)
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if texture:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image(texture)
        mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
        mat.surface_render_method = "BLENDED"
    if emission:
        bsdf.inputs["Emission Color"].default_value = linear(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


# --- mesh helpers ---------------------------------------------------------------

def new_object(name, mesh, col, parent=None, at=(0, 0, 0)):
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    obj.parent = parent
    obj.location = g2b(at)
    return obj


def empty(name, col, parent=None, at=(0, 0, 0)):
    return new_object(name, None, col, parent, at)


def finish(mesh, smooth_angle=None, flip=False):
    if flip:
        for poly in mesh.polygons:
            poly.flip()
    if smooth_angle is None:
        mesh.shade_flat()
    else:
        mesh.shade_smooth()
        mesh.set_sharp_from_angle(angle=math.radians(smooth_angle))
    mesh.update()
    return mesh


def refine(profile, steps=3):
    """Catmull-Rom upsampling of a (radius, height) profile, keeping its corners."""
    if steps <= 1:
        return list(profile)
    out = []
    n = len(profile)
    for i in range(n - 1):
        p0 = Vector(profile[max(i - 1, 0)]); p1 = Vector(profile[i])
        p2 = Vector(profile[i + 1]); p3 = Vector(profile[min(i + 2, n - 1)])
        for s in range(steps):
            t = s / steps
            point = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
            out.append((max(point.x, 0.0), point.y))
    out.append(tuple(profile[-1]))
    return out


def lathe(name, profile, segments=48, cap_bottom=False, cap_top=False, radial=None, v_range=None):
    """Surface of revolution around the vertical axis. profile: (radius, height) bottom->top.
    UV: u runs counter-clockwise seen from above (text reads correctly from outside),
    v follows height (or `v_range` = (bottom, top) heights mapped to 0..1)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    lengths = [0.0]
    for i in range(1, len(profile)):
        lengths.append(lengths[-1] + (Vector(profile[i]) - Vector(profile[i - 1])).length)
    total = max(lengths[-1], 1e-6)
    rings = []
    for i, (r, h) in enumerate(profile):
        ring = []
        for s in range(segments):
            a = TAU * s / segments
            rr = r * (radial(a, h) if radial else 1.0)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), h)))
        rings.append(ring)

    def v_of(i):
        if v_range:
            return (profile[i][1] - v_range[0]) / (v_range[1] - v_range[0])
        return lengths[i] / total

    for i in range(len(profile) - 1):
        for s in range(segments):
            n = (s + 1) % segments
            face = bm.faces.new((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]))
            us = (s / segments, (s + 1) / segments)
            coords = [(us[0], v_of(i)), (us[1], v_of(i)), (us[1], v_of(i + 1)), (us[0], v_of(i + 1))]
            for loop, c in zip(face.loops, coords):
                loop[uv].uv = c
    for flag, index, up in ((cap_bottom, 0, False), (cap_top, len(profile) - 1, True)):
        if not flag or profile[index][0] <= 1e-5:
            continue
        ring = rings[index]
        face = bm.faces.new(ring if up else list(reversed(ring)))
        for loop in face.loops:
            co = loop.vert.co
            loop[uv].uv = (.5 + co.x * 6, .5 + co.y * 6)
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def tube_along(name, start_g, end_g, radius, segments=24, end_radius=None, caps=True):
    """Cylinder between two Godot-space points."""
    a = g2b(start_g); b = g2b(end_g)
    axis = (b - a)
    length = axis.length
    r1 = end_radius if end_radius is not None else radius
    mesh = lathe(name, [(0, 0), (radius, 0), (r1, length), (0, length)] if caps else [(radius, 0), (r1, length)], segments)
    rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    mesh.transform(Matrix.Translation(a) @ rot)
    return mesh


def box(name, size_g, center_g=(0, 0, 0), bevel=0.0, segments=3):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    s = g2b(size_g)
    bmesh.ops.scale(bm, vec=Vector((abs(s.x), abs(s.y), abs(s.z))), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, profile=.5, affect="EDGES")
    bmesh.ops.translate(bm, vec=g2b(center_g), verts=bm.verts)
    uv = bm.loops.layers.uv.new()
    for face in bm.faces:
        n = face.normal
        for loop in face.loops:
            co = loop.vert.co
            if abs(n.z) > .5:
                loop[uv].uv = (co.x * 10, co.y * 10)
            elif abs(n.x) > .5:
                loop[uv].uv = (co.y * 10, co.z * 10)
            else:
                loop[uv].uv = (co.x * 10, co.z * 10)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def ellipsoid(name, center_g, semi_g, basis_g=None, segments=16, rings=10):
    """Ellipsoid with semi-axes along the columns of a Godot-space basis."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    m = Matrix.Identity(3)
    if basis_g is not None:
        m = Matrix(basis_g).transposed()  # rows given as axes -> columns
    scale = Matrix.Diagonal(Vector(semi_g))
    conv = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender
    full = conv @ m @ scale
    for v in bm.verts:
        v.co = full @ v.co + g2b(center_g)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def join(objects, name):
    """Joins mesh objects into the first one (data-level, no operators)."""
    bm = bmesh.new()
    materials = []
    for obj in objects:
        mesh = obj.data.copy()
        mesh.transform(obj.matrix_world)
        offset = len(materials)
        for mat in mesh.materials:
            materials.append(mat)
        for poly in mesh.polygons:
            poly.material_index += offset
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    for mat in materials:
        out.materials.append(mat)
    return out


def evaluated_mesh(obj, name):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    return bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True,
        export_skins=True, export_animations=False, export_apply=False,
        export_materials="EXPORT", export_image_format="AUTO", export_extras=False,
    )
    print("exported", path)


def all_children(obj):
    out = [obj]
    for child in obj.children:
        out += all_children(child)
    return out


# --- low-poly building blocks ------------------------------------------------------
# Everything below is deliberately faceted (flat shaded, few sides): the hands and
# consumables share a stylised low-poly look with crisp silhouettes.

class Skinned:
    """bmesh under construction whose vertices carry bone weights and faces materials."""

    def __init__(self, groups):
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.groups = {name: i for i, name in enumerate(groups)}

    def vert(self, co_g, weights):
        v = self.bm.verts.new(g2b(co_g))
        total = sum(weights.values())
        for name, w in weights.items():
            if w > 0:
                v[self.deform][self.groups[name]] = w / total
        return v

    def face(self, verts, material=0):
        f = self.bm.faces.new(verts)
        f.material_index = material
        return f

    def tube(self, rings, material=0, tip=None, closed_start=False):
        """Rings: lists of verts with the same count; quads between them, optional tip fan."""
        n = len(rings[0])
        for a, b in zip(rings, rings[1:]):
            for s in range(n):
                t = (s + 1) % n
                self.face((a[s], a[t], b[t], b[s]), material)
        if tip is not None:
            last = rings[-1]
            for s in range(n):
                self.face((last[s], last[(s + 1) % n], tip), material)
        if closed_start:
            self.face(list(reversed(rings[0])), material)

    def mesh(self, name, materials):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mat in materials:
            mesh.materials.append(mat)
        return mesh


def frame_of(head, tail, up):
    """Godot-space bone frame: z points back toward the head, x is the back of the finger."""
    z = (Vector(head) - Vector(tail)).normalized()
    y = Vector(up).normalized()
    x = y.cross(z).normalized()
    y = z.cross(x).normalized()
    return x, y, z


def polygon_ring(center, x, y, rx, ry, sides, turn=0.0, squash=None):
    """Points of a flat-sided ring. With turn = pi/sides a flat face looks along +x."""
    out = []
    for s in range(sides):
        a = turn + TAU * s / sides
        k = squash(a) if squash else 1.0
        out.append(center + x * (math.cos(a) * rx * k) + y * (math.sin(a) * ry * k))
    return out


def box_uv(mesh, scale=9.0):
    """Box-projected UVs; the skin and fabric textures are soft noise, so seams never show."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        axis = max(range(3), key=lambda k: abs(n[k]))
        pair = [(1, 2), (0, 2), (0, 1)][axis]
        for loop in face.loops:
            co = loop.vert.co
            loop[uv].uv = (co[pair[0]] * scale, co[pair[1]] * scale)
    bm.to_mesh(mesh)
    bm.free()


# --- arm -----------------------------------------------------------------------

BONE_ORDER = ["hand", "forearm"] + ["%s_%d" % (f, i) for f in ("index", "middle", "ring", "pinky", "thumb") for i in (1, 2, 3)]


def build_arm():
    reset()
    col = collection("Arm")
    rig = json.load(open(os.path.join(SRC, "hand_rig.json")))
    bones = {b["name"]: b for b in rig["bones"]}
    names = [b["name"] for b in rig["bones"]]

    # Plain colours: the game swaps in its own skin/fabric shaders by material name.
    skin = material("Skin", (0.79, 0.58, 0.44, 1), .55)
    nail = material("Nail", (0.9, 0.72, 0.64, 1), .25)
    sleeve = material("Sleeve", (0.23, 0.25, 0.34, 1), .88)
    cuff = material("Cuff", (0.17, 0.18, 0.25, 1), .9)

    body = Skinned(names)
    SKIN, NAIL = 0, 1

    # Fingers: one hexagonal tube per finger with a flat back and a flat pad,
    # a ring at every knuckle shared by the two bones so bends fold cleanly.
    for finger in ("index", "middle", "ring", "pinky", "thumb"):
        b1, b2, b3 = (bones["%s_%d" % (finger, i)] for i in (1, 2, 3))
        x, y, z = frame_of(b1["head"], b1["tail"], b1["up"])
        fwd = -z
        h1, h2, h3 = Vector(b1["head"]), Vector(b2["head"]), Vector(b3["head"])
        end = Vector(b3["tail"])
        r1, r2, r3 = b1["radius"], b2["radius"], b3["radius"]
        n1, n2, n3 = b1["name"], b2["name"], b3["name"]
        thumb = finger == "thumb"
        root_w = {"hand": .65, n1: .35} if not thumb else {"hand": .45, n1: .55}
        flat = .86  # fingers are a little flatter than they are wide
        sides = 6
        turn = math.pi / sides

        def ring(center, r, weights, knuckle=0.0, pad=0.0):
            def squash(a):
                c = math.cos(a)
                # +x (back) gets the knuckle bump, -x (palm side) the pad.
                return 1.0 + (knuckle * max(c, 0.0)) + (pad * max(-c, 0.0))
            pts = polygon_ring(center, x, y, r * flat * 1.08, r * 1.08, sides, turn, squash)
            return [body.vert(p, weights) for p in pts]

        stations = [
            ring(h1 - fwd * (.014 if not thumb else .016), r1 * 1.12, root_w),
            ring(h1 + fwd * .002, r1 * 1.08, {"hand": .25, n1: .75}, knuckle=.12),
            ring(h1 + (h2 - h1) * .55, r1 * .98, {n1: 1}),
            ring(h2, r2 * 1.06, {n1: .5, n2: .5}, knuckle=.1),
            ring(h2 + (h3 - h2) * .5, r2 * .96, {n2: 1}, pad=.06),
            ring(h3, r3 * 1.04, {n2: .5, n3: .5}, knuckle=.06),
            ring(h3 + (end - h3) * .5, r3 * 1.0, {n3: 1}, pad=.1),
            ring(h3 + (end - h3) * .8, r3 * .8, {n3: 1}, pad=.05),
        ]
        tip = body.vert(h3 + (end - h3) * .93 - x * (r3 * .15), {n3: 1})
        body.tube(stations, SKIN, tip=tip)

        # Nail: a thin faceted plate on the back of the last segment.
        length = (end - h3).length
        lift = r3 * flat * 1.08 * math.cos(turn) + .0004
        base = h3 + fwd * (length * .32) + x * lift
        front = h3 + fwd * (length * .86) + x * (lift - r3 * .12)
        w = r3 * (.72 if not thumb else .8)
        outline = [base - y * w * .85, base + y * w * .85, base + (front - base) * .55 + y * w,
                   front + y * w * .55, front - y * w * .55, base + (front - base) * .55 - y * w]
        top = [body.vert(p + x * .0007, {n3: 1}) for p in outline]
        low = [body.vert(p - x * .0004, {n3: 1}) for p in outline]
        body.face(top, NAIL)
        body.face(list(reversed(low)), NAIL)
        for s in range(len(outline)):
            t = (s + 1) % len(outline)
            body.face((top[t], top[s], low[s], low[t]), NAIL)

    # Palm: a convex hull of hand-placed landmarks (knuckles, heel, thumb mound),
    # then nearly coplanar triangles are merged into larger flat facets.
    palm_pts = []
    for finger, back, front in (("index", (.0085, .002, .004), (-.0105, .002, .006)),
                                ("middle", (.0095, 0, .004), (-.0105, 0, .006)),
                                ("ring", (.009, 0, .004), (-.0105, 0, .006)),
                                ("pinky", (.0075, -.002, .004), (-.0095, -.002, .006))):
        head = Vector(bones[finger + "_1"]["head"])
        palm_pts.append(head + Vector(back))
        palm_pts.append(head + Vector(front))
    palm_pts += [Vector(p) for p in (
        (.002, .037, -.066), (-.004, .035, -.074),          # index edge
        (.001, -.035, -.058), (-.006, -.032, -.064),         # pinky edge
        (.0195, .022, -.038), (.0205, -.018, -.040),         # back of the hand
        (-.0145, -.026, -.030), (-.0135, -.006, -.050),      # heel / hypothenar
        (-.021, .026, -.030), (-.018, .036, -.042), (-.006, .042, -.036),  # thumb mound
        (-.016, .015, -.012),
    )]
    for p in polygon_ring(Vector((.003, -.002, -.004)), Vector((1, 0, 0)), Vector((0, 1, 0)), .0135, .022, 8, math.pi / 8):
        palm_pts.append(p)
    thumb_root = Vector(bones["thumb_1"]["head"])
    palm_bm = bmesh.new()
    for p in palm_pts:
        palm_bm.verts.new(p)
    hull = bmesh.ops.convex_hull(palm_bm, input=list(palm_bm.verts))
    bmesh.ops.delete(palm_bm, geom=list({v for v in hull["geom_interior"] + hull["geom_unused"] if isinstance(v, bmesh.types.BMVert)}), context="VERTS")
    bmesh.ops.dissolve_limit(palm_bm, angle_limit=math.radians(7), verts=list(palm_bm.verts), edges=list(palm_bm.edges))
    bmesh.ops.triangulate(palm_bm, faces=[f for f in palm_bm.faces if len(f.verts) > 4])
    palm_map = {}
    for v in palm_bm.verts:
        p = Vector(v.co)
        weights = {"hand": 1.0}
        if p.z > -.012:
            weights["forearm"] = min(max((p.z + .012) / .03, 0), 1) * .6
        d = (p - thumb_root).length
        if d < .018:
            weights["thumb_1"] = .4 * (1 - d / .018)
        palm_map[v] = body.vert(p, weights)
    for f in palm_bm.faces:
        body.face([palm_map[v] for v in f.verts], SKIN)
    palm_bm.free()

    # Wrist and forearm: an octagonal tube tapering into the sleeve.
    wrist = []
    for zpos, rx, ry, w in ((-.016, .0148, .0235, {"hand": .9, "forearm": .1}),
                            (.018, .0168, .0255, {"hand": .4, "forearm": .6}),
                            (.06, .0185, .027, {"forearm": 1}),
                            (.16, .021, .029, {"forearm": 1})):
        pts = polygon_ring(Vector((.003, -.002, zpos)), Vector((1, 0, 0)), Vector((0, 1, 0)), rx, ry, 8, math.pi / 8)
        wrist.append([body.vert(p, w) for p in pts])
    body.tube(wrist, SKIN)

    skin_mesh = body.mesh("ArmSkin", [skin, nail])
    box_uv(skin_mesh)
    finish(skin_mesh)
    print("skin triangles", sum(len(p.vertices) - 2 for p in skin_mesh.polygons))
    skin_obj = bpy.data.objects.new("ArmSkin", skin_mesh)
    col.objects.link(skin_obj)

    # Sleeve: chunky octagon with a few hard folds and a thick cuff.
    def fold(a, h):
        return 1.0 + .05 * math.sin(3 * a + h * 30) + .03 * math.cos(5 * a - h * 18)
    sleeve_mesh = lathe("Sleeve", [(.0335, 0), (.0345, .1), (.036, .22), (.0375, .34), (.0385, .44)], 9, radial=fold)
    sleeve_mesh.transform(Matrix.Translation(g2b((.003, -.002, .085))) @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Diagonal((1, .9, 1, 1)))
    sleeve_mesh.materials.append(sleeve)
    cuff_mesh = lathe("Cuff", [(.031, -.002), (.0385, -.001), (.0405, .007), (.040, .042), (.0385, .05), (.0325, .051)], 9)
    cuff_mesh.transform(Matrix.Translation(g2b((.003, -.002, .047))) @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Diagonal((1, .9, 1, 1)))
    cuff_mesh.materials.append(cuff)
    sleeve_obj = bpy.data.objects.new("Sleeve", join([bpy.data.objects.new("s", sleeve_mesh), bpy.data.objects.new("c", cuff_mesh)], "Sleeve"))
    col.objects.link(sleeve_obj)
    box_uv(sleeve_obj.data, 6.0)
    finish(sleeve_obj.data)
    group = sleeve_obj.vertex_groups.new(name="forearm")
    group.add(list(range(len(sleeve_obj.data.vertices))), 1.0, "REPLACE")

    # Vertex groups of the skin in skeleton order (the deform layer stored indices).
    for name in names:
        skin_obj.vertex_groups.new(name=name)

    # Armature built from the exported rest skeleton.
    arm_data = bpy.data.armatures.new("ArmRig")
    arm_obj = bpy.data.objects.new("ArmRig", arm_data)
    col.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    for b in rig["bones"]:
        eb = arm_data.edit_bones.new(b["name"])
        eb.head = g2b(b["head"])
        eb.tail = g2b(b["tail"])
        eb.align_roll(g2b(b["up"]))
    for b in rig["bones"]:
        if b["parent"]:
            arm_data.edit_bones[b["name"]].parent = arm_data.edit_bones[b["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")

    for obj in (skin_obj, sleeve_obj):
        obj.parent = arm_obj
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_obj
    for obj in list(col.objects):
        if obj not in (arm_obj, skin_obj, sleeve_obj):
            bpy.data.objects.remove(obj)
    export(os.path.join(OUT, "arm.glb"), [arm_obj, skin_obj, sleeve_obj])


# --- props ---------------------------------------------------------------------

def low(name, profile, segments, mat, col, parent=None, at=(0, 0, 0), **kw):
    """Faceted surface of revolution as a ready object."""
    mesh = lathe(name, profile, segments, **kw)
    mesh.materials.append(mat)
    return new_object(name, finish(mesh), col, parent, at)


def gem(name, center_g, size_g, sides=4):
    """Tiny faceted droplet (condensation beads, sparks of foam)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=sides, v_segments=3, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size_g[0], v.co.y * size_g[2], v.co.z * size_g[1])) + g2b(center_g)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


BOTTLE_SIDES = 10
BOTTLE_PROFILE = [(.0, .0), (.027, .0), (.0325, .006), (.0325, .128), (.029, .146), (.019, .172),
                  (.0135, .190), (.0128, .226), (.0142, .229), (.0142, .236), (.0125, .239)]


def build_bottle():
    reset()
    col = collection("Bottle")
    glass = material("Glass", (.36, .16, .03, 1), .05, alpha=.84)
    beer = material("Beer", (.48, .26, .03, 1), .15, emission=(.23, .09, 0, 1), strength=.25)
    foam = material("Foam", (.95, .89, .75, 1), .9)
    label = material("Label", (1, 1, 1, 1), .72, texture="beer_label")
    foil = material("NeckFoil", (.54, .16, .12, 1), .5, .2)
    gold = material("CapMetal", (.79, .64, .29, 1), .32, .85)
    wet = material("Condensation", (1, .96, .9, 1), .02, alpha=.45)
    n = BOTTLE_SIDES

    low("Glass", BOTTLE_PROFILE, n, glass, col)
    low("Punt", [(.027, .0), (.017, .004), (0, .009)], n, glass, col)

    liquid_root = empty("Liquid", col, at=(0, .005, 0))
    inner = [(max(r - .0035, .002), h - .005) for r, h in BOTTLE_PROFILE if .004 < h < .205]
    low("LiquidMesh", inner, n, beer, col, liquid_root, cap_bottom=True, cap_top=True)
    low("Foam", [(0, -.002), (.0105, -.002), (.0108, .0015), (.007, .0035), (0, .004)], n, foam, col, liquid_root, (0, .196, 0))

    # Label and neck foil share the bottle's facets, standing just proud of the glass.
    low("Label", [(.0338, .030), (.0338, .102)], n, label, col, v_range=(.030, .102))
    low("NeckLabel", [(.0146, .189), (.0137, .205), (.0134, .218)], n, foil, col)

    cap_root = empty("Cap", col, at=(0, .239, 0))
    def crimp(a, h):
        return 1.0 + (.075 * (1 if math.cos(a * n) > 0 else -1) if h < .0005 else 0.0)
    low("CapMesh", [(.0128, -.0045), (.0158, -.0045), (.0158, .0004), (.0142, .0026), (0, .0034)], n * 2, gold, col, cap_root, radial=crimp)

    beads = []
    for index in range(18):
        angle = index * 2.39996 + .4
        height = .022 + math.fmod(index * .0371, .10)
        size = .0012 + math.fmod(index * .00029, .0008)
        r = .0332
        beads.append(bpy.data.objects.new("b", gem("Bead", (math.cos(angle) * r, height, math.sin(angle) * r), (size, size * 1.7, size))))
    bead_mesh = join(beads, "Beads")
    bead_mesh.materials.clear()
    bead_mesh.materials.append(wet)
    new_object("Beads", finish(bead_mesh), col)
    export(os.path.join(OUT, "bottle.glb"), list(col.objects))


CAN_SIDES = 12
CAN_PROFILE = [(.0, .006), (.020, .006), (.026, .0), (.0315, .005), (.0325, .014), (.0325, .112),
               (.0298, .124), (.0265, .130), (.0268, .133)]


def build_can():
    reset()
    col = collection("Can")
    wrap = material("CanWrap", (1, 1, 1, 1), .28, .55, texture="can_wrap")
    alu = material("Aluminium", (.78, .8, .82, 1), .25, .9)
    dark = material("Opening", (.04, .05, .05, 1), .6)
    rivet = material("Rivet", (.23, .24, .26, 1), .4, .6)
    n = CAN_SIDES
    # The wall gets extra rings so the crush shape key has something to fold.
    profile = CAN_PROFILE[:5] + [(.0325, .014 + (.112 - .014) * k / 6) for k in range(1, 6)] + CAN_PROFILE[5:]
    body = new_object("Body", finish(lathe("Body", profile, n, v_range=(0.0, .133))), col)
    body.data.materials.append(wrap)

    # "Crushed": the middle of the can buckles in, with an off-centre dent and a twist.
    body.shape_key_add(name="Basis", from_mix=False)
    crushed = body.shape_key_add(name="Crushed", from_mix=False)
    crushed.value = 0.0
    for i, v in enumerate(body.data.vertices):
        co = v.co.copy()
        h = co.z
        if .012 < h < .116:
            t = (h - .012) / .104
            pinch = math.sin(math.pi * t)
            a = math.atan2(co.y, co.x)
            dent = .5 + .5 * math.cos(a - .8)
            squeeze = 1 - pinch * (.20 + .32 * dent) - .06 * pinch * (1 if (i // 1) % 2 else 0)
            twist = .45 * pinch
            r = math.hypot(co.x, co.y) * squeeze
            a += twist
            co.x, co.y = r * math.cos(a), r * math.sin(a)
            co.z = h - .006 * pinch
        crushed.data[i].co = co

    low("Lid", [(.0262, .1305), (.0255, .1300), (.0215, .1296), (.0205, .1302), (.0, .1302)], n, alu, col)
    hole = gem("Hole", (0, .1309, -.012), (.0055, .0005, .0072), sides=8)
    hole.materials.append(dark)
    new_object("Hole", finish(hole), col)

    hinge = empty("Tab", col, at=(0, .1314, 0))
    bm = bmesh.new()
    k = 10
    outline = [(.0055 * math.cos(TAU * s / k), .006 + .0118 * math.sin(TAU * s / k) * (1 if math.sin(TAU * s / k) > 0 else .55)) for s in range(k)]
    ring = [(.0032 * math.cos(TAU * s / k), .0105 + .0032 * math.sin(TAU * s / k)) for s in range(k)]
    top = [bm.verts.new(g2b((x, .0006, z))) for x, z in outline]
    bot = [bm.verts.new(g2b((x, -.0006, z))) for x, z in outline]
    itop = [bm.verts.new(g2b((x, .0006, z))) for x, z in ring]
    ibot = [bm.verts.new(g2b((x, -.0006, z))) for x, z in ring]
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((top[i], top[j], itop[j], itop[i]))
        bm.faces.new((bot[j], bot[i], ibot[i], ibot[j]))
        bm.faces.new((top[j], top[i], bot[i], bot[j]))
        bm.faces.new((itop[i], itop[j], ibot[j], ibot[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tab = bpy.data.meshes.new("TabPlate")
    bm.to_mesh(tab)
    bm.free()
    tab.materials.append(alu)
    new_object("TabPlate", finish(tab), col, hinge)
    rivet_mesh = gem("Rivet", (0, .0007, 0), (.0024, .0009, .0024), sides=6)
    rivet_mesh.materials.append(rivet)
    new_object("Rivet", finish(rivet_mesh), col, hinge)
    export(os.path.join(OUT, "can.glb"), list(col.objects))


def build_cigarette():
    reset()
    col = collection("Cigarette")
    cork = material("Cork", (1, 1, 1, 1), .85, texture="cork")
    ring = material("GoldRing", (.78, .64, .31, 1), .35, .7)
    paper = material("Paper", (.95, .94, .9, 1), .92, texture="paper")
    ash = material("Ash", (.55, .53, .51, 1), .98, texture="ash")
    ember = material("Ember", (.23, .09, .04, 1), .9, emission=(1, .35, .1, 1), strength=0.0)
    tobacco = material("Tobacco", (.36, .22, .11, 1), .95)
    n = 8
    filt = tube_along("Filter", (0, 0, 0), (0, 0, -.022), .0042, n)
    filt.materials.append(cork)
    new_object("Filter", finish(filt), col)
    band = tube_along("Ring", (0, 0, -.0208), (0, 0, -.0224), .00435, n, caps=False)
    band.materials.append(ring)
    new_object("Ring", finish(band), col)
    pivot = empty("Paper", col, at=(0, 0, -.022))
    tube = tube_along("PaperMesh", (0, 0, 0), (0, 0, -.062), .0041, n, caps=False)
    tube.materials.append(paper)
    new_object("PaperMesh", finish(tube), col, pivot)
    end = tube_along("Tobacco", (0, 0, -.0615), (0, 0, -.062), .0040, n)
    end.materials.append(tobacco)
    new_object("Tobacco", finish(end), col, pivot)
    def flaky(a, h):
        return 1.0 + .08 * math.sin(a * 3 + h * 900)
    ash_mesh = lathe("Ash", [(0, -.003), (.0039, -.003), (.0037, .0), (.0034, .003), (0, .0032)], 7, radial=flaky)
    ash_mesh.transform(Matrix.Rotation(-math.pi / 2, 4, "X"))
    ash_mesh.materials.append(ash)
    new_object("Ash", finish(ash_mesh), col, None, (0, 0, -.087))
    ember_mesh = tube_along("Ember", (0, 0, .0011), (0, 0, -.0011), .0040, n, end_radius=.0033)
    ember_mesh.materials.append(ember)
    new_object("Ember", finish(ember_mesh), col, None, (0, 0, -.0846))
    export(os.path.join(OUT, "cigarette.glb"), list(col.objects))


def build_lighter():
    reset()
    col = collection("Lighter")
    plastic = material("LighterPlastic", (.70, .15, .12, 1), .32)
    steel = material("Steel", (.73, .74, .75, 1), .28, .9)
    wheel_mat = material("WheelSteel", (.33, .35, .36, 1), .45, .8)
    black = material("Button", (.11, .11, .12, 1), .6)
    # Faceted stadium body: three flats round each side.
    bm = bmesh.new()
    outline = []
    for s in range(4):
        a = math.pi * s / 3 - math.pi / 2
        outline.append((.012 + .006 * math.cos(a), .006 * math.sin(a)))
    for s in range(4):
        a = math.pi * s / 3 + math.pi / 2
        outline.append((-.012 + .006 * math.cos(a), .006 * math.sin(a)))
    levels = [(.0, .88), (.003, 1.0), (.059, 1.0), (.062, .95)]
    rings = [[bm.verts.new(g2b((x * k, h, z * k))) for x, z in outline] for h, k in levels]
    n = len(outline)
    for i in range(len(rings) - 1):
        for s in range(n):
            t = (s + 1) % n
            bm.faces.new((rings[i][s], rings[i][t], rings[i + 1][t], rings[i + 1][s]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    body = bpy.data.meshes.new("Body")
    bm.to_mesh(body)
    bm.free()
    body.materials.append(plastic)
    new_object("Body", finish(body), col)
    hood = box("Hood", (.026, .015, .0132), (0, .069, 0))
    hood.materials.append(steel)
    new_object("Hood", finish(hood), col)
    for i in range(4):
        slot = box("Slot", (.0035, .007, .0134), (-.008 + i * .0055, .070, 0))
        slot.materials.append(black)
        new_object("Slot%d" % i, finish(slot), col)
    def knurl(a, h):
        return 1.0 + .1 * (1 if math.cos(a * 6) > 0 else -1) * (1 if .0015 < h < .0075 else 0)
    wheel = lathe("Wheel", [(0, 0), (.0052, 0), (.0055, .0015), (.0055, .0075), (.0052, .009), (0, .009)], 12, radial=knurl)
    wheel.transform(Matrix.Translation((0, 0, -.0045)))
    wheel.materials.append(wheel_mat)
    w = new_object("Wheel", finish(wheel), col, None, (.004, .078, 0))
    w.rotation_euler = (0, -math.pi / 2, 0)
    button = box("Button", (.012, .004, .011), (-.006, .075, 0))
    button.materials.append(black)
    new_object("Button", finish(button), col)
    nozzle = tube_along("Nozzle", (-.004, .076, 0), (-.004, .081, 0), .0016, 6)
    nozzle.materials.append(steel)
    new_object("Nozzle", finish(nozzle), col)
    export(os.path.join(OUT, "lighter.glb"), list(col.objects))


def build_pack():
    reset()
    col = collection("Pack")
    red = material("PackRed", (.69, .14, .11, 1), .55)
    print_mat = material("PackPrint", (1, 1, 1, 1), .5, texture="pack")
    white = material("PackInside", (.95, .93, .89, 1), .5)
    cork = material("Cork", (1, 1, 1, 1), .85, texture="cork")
    body = box("Body", (.056, .07, .022), (0, .035, 0), bevel=.0012)
    body.materials.append(red)
    new_object("Body", finish(body, 40), col)
    for side in (1, -1):
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new()
        z = side * .0112
        corners = [(-.028, .0), (.028, .0), (.028, .086), (-.028, .086)]
        verts = [bm.verts.new(g2b((x, y, z))) for x, y in (corners if side > 0 else list(reversed(corners)))]
        face = bm.faces.new(verts)
        for loop in face.loops:
            co = loop.vert.co
            u = (co.x + .028) / .056
            loop[uv].uv = (u if side > 0 else 1 - u, co.z / .086)
        mesh = bpy.data.meshes.new("Face")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(print_mat)
        new_object("Face%d" % (side > 0), finish(mesh), col)
    lid_root = empty("Lid", col, at=(0, .07, -.011))
    lid = box("LidBox", (.056, .016, .022), (0, .008, .011), bevel=.001)
    lid.materials.append(white)
    lo = new_object("LidBox", finish(lid, 40), col, lid_root)
    lid_root.rotation_euler = (math.radians(110), 0, 0)
    for index in range(4):
        tip = tube_along("Filter", (-.018 + index * .012, .062, .003), (-.018 + index * .012, .086 + (index % 2) * .006, .003), .0042, 14)
        tip.materials.append(cork)
        new_object("Filter%d" % index, finish(tip, 50), col)
    export(os.path.join(OUT, "pack.glb"), list(col.objects))


def build_six_pack():
    reset()
    col = collection("SixPack")
    card = material("Card", (1, 1, 1, 1), .9, texture="card")
    label = material("CarrierLabel", (1, 1, 1, 1), .7, texture="beer_label")
    base = box("Base", (.215, .09, .15), (0, .045, 0), bevel=.002)
    base.materials.append(card)
    new_object("Base", finish(base, 40), col)
    divider = box("Divider", (.215, .16, .006), (0, .15, 0), bevel=.001)
    divider.materials.append(card)
    new_object("Divider", finish(divider, 40), col)
    grip = box("Handle", (.07, .022, .008), (0, .205, 0))
    grip.materials.append(card)
    new_object("Handle", finish(grip, 40), col)
    for side in (1, -1):
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new()
        z = side * .0755
        corners = [(-.1, .008), (.1, .008), (.1, .083), (-.1, .083)]
        verts = [bm.verts.new(g2b((x, y, z))) for x, y in (corners if side > 0 else list(reversed(corners)))]
        face = bm.faces.new(verts)
        for loop in face.loops:
            co = loop.vert.co
            u = (co.x + .1) / .2
            loop[uv].uv = ((u if side > 0 else 1 - u) * .5, (co.z - .008) / .075)
        mesh = bpy.data.meshes.new("Sign")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(label)
        new_object("Sign%d" % (side > 0), finish(mesh), col)
    export(os.path.join(OUT, "six_pack.glb"), list(col.objects))


if __name__ == "__main__":
    import sys
    picked = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in ("arm", "bottle", "can", "cigarette", "lighter", "pack", "six_pack"):
        if not picked or name in picked:
            globals()["build_" + name]()
    print("FP_ASSETS done")
