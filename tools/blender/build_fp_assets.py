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
OUT = os.path.join(ROOT, "assets", "fp")
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


# --- arm -----------------------------------------------------------------------

def build_arm():
    reset()
    col = collection("Arm")
    rig = json.load(open(os.path.join(SRC, "hand_rig.json")))
    bones = {b["name"]: b for b in rig["bones"]}

    # Plain colours: the game swaps in its own skin/fabric shaders, and glTF drops
    # the colour factor when a texture is linked (white hands in the editor previews).
    skin = material("Skin", (0.79, 0.58, 0.44, 1), .55)
    nail = material("Nail", (0.9, 0.72, 0.64, 1), .25)
    sleeve = material("Sleeve", (0.23, 0.25, 0.34, 1), .88)
    cuff = material("Cuff", (0.17, 0.18, 0.25, 1), .9)

    # Metaball families fuse only with themselves, so every finger is its own
    # family (no webbing between fingers); the voxel remesh then welds them to the palm.
    pieces = []

    def family(name):
        mb = bpy.data.metaballs.new(name)
        mb.resolution = .0011
        mb.render_resolution = .0011
        mb.threshold = .6
        obj = bpy.data.objects.new(name, mb)
        col.objects.link(obj)
        pieces.append(obj)
        return mb

    surface = .672  # metaball radius -> surface radius at threshold .6, stiffness 2

    def capsule(mb, a_g, b_g, radius):
        a = g2b(a_g); b = g2b(b_g)
        el = mb.elements.new(type="CAPSULE")
        el.co = (a + b) / 2
        el.radius = radius / surface
        el.size_x = (b - a).length / 2
        el.rotation = Vector((1, 0, 0)).rotation_difference((b - a).normalized())
        el.stiffness = 2.0

    def blob(mb, center_g, semi_g, turn=None):
        el = mb.elements.new(type="ELLIPSOID")
        el.co = g2b(center_g)
        base = max(semi_g)
        el.radius = base / surface
        s = [semi_g[0] / base, semi_g[2] / base, semi_g[1] / base]  # Godot x,z,y -> Blender x,y,z sizes
        el.size_x, el.size_y, el.size_z = s
        if turn:
            el.rotation = turn
        el.stiffness = 2.0

    palm = family("SkinPalm")
    blob(palm, (.004, 0.0, -.047), (.0165, .036, .043))
    blob(palm, (.005, 0.0, -.074), (.014, .038, .016))
    blob(palm, (.002, -.010, -.020), (.017, .029, .026))
    blob(palm, (-.007, .021, -.032), (.013, .015, .023))   # thenar (thumb muscle)
    blob(palm, (-.004, -.024, -.045), (.011, .011, .03))   # hypothenar
    for finger in ("index", "middle", "ring", "pinky"):
        b = bones[finger + "_1"]
        head = Vector(b["head"]); tail = Vector(b["tail"])
        blob(palm, head + Vector((.008, 0, .006)), (.0088, .0086, .0095))
        # Skin web: the first third of each finger grows out of the palm smoothly.
        capsule(palm, head + Vector((0, 0, .008)), head + (tail - head) * .32, b["radius"] * 1.08)
    # Wrist: flattened oval tapering into the forearm (hidden by the cuff further back).
    for z, wy in ((.0, .029), (.035, .027), (.075, .026), (.11, .026)):
        blob(palm, (.004, -.004, z), (.0215, wy, .03))

    for finger in ("index", "middle", "ring", "pinky", "thumb"):
        mb = family("Skin" + finger.capitalize())
        for i in (1, 2, 3):
            b = bones["%s_%d" % (finger, i)]
            r = b["radius"] * (1.04 if finger != "thumb" else 1.0)
            head = Vector(b["head"]); tail = Vector(b["tail"])
            if i == 3:
                tail = head + (tail - head) * .82  # rounded tip ends where the old fingertip did
            capsule(mb, head, tail, r)

    bpy.context.view_layer.update()
    meshes = []
    for obj in pieces:
        if "." in obj.name:
            continue
        mesh = evaluated_mesh(obj, obj.name + "Mesh")
        holder = bpy.data.objects.new(obj.name + "Poly", mesh)
        col.objects.link(holder)
        meshes.append(holder)
    for obj in pieces:
        bpy.data.objects.remove(obj)
    fused = bpy.data.objects.new("ArmSkinRaw", join(meshes, "ArmSkinRaw"))
    col.objects.link(fused)
    for obj in meshes:
        bpy.data.objects.remove(obj)
    remesh = fused.modifiers.new("Remesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = .0009
    remesh.adaptivity = 0.0
    smooth = fused.modifiers.new("Smooth", "SMOOTH")
    smooth.factor = .7
    smooth.iterations = 12
    decimate = fused.modifiers.new("Decimate", "DECIMATE")
    decimate.ratio = .16
    bpy.context.view_layer.update()
    skin_mesh = evaluated_mesh(fused, "ArmSkin")
    bpy.data.objects.remove(fused)
    skin_mesh.materials.clear()
    skin_mesh.materials.append(skin)
    print("skin triangles", sum(len(p.vertices) - 2 for p in skin_mesh.polygons))

    # Box-projected UVs: the skin texture is soft noise, so seams do not show.
    bm = bmesh.new()
    bm.from_mesh(skin_mesh)
    uv = bm.loops.layers.uv.new()
    for face in bm.faces:
        n = face.normal
        axis = max(range(3), key=lambda k: abs(n[k]))
        for loop in face.loops:
            co = loop.vert.co
            pair = [(1, 2), (0, 2), (0, 1)][axis]
            loop[uv].uv = (co[pair[0]] * 9, co[pair[1]] * 9)
    bm.to_mesh(skin_mesh)
    bm.free()
    finish(skin_mesh, 180)

    # Nails: thin shells on the back (+X) of the fingertips.
    nails = []
    for finger in ("index", "middle", "ring", "pinky", "thumb"):
        b = bones[finger + "_3"]
        head = Vector(b["head"]); tail = Vector(b["tail"])
        z = (head - tail).normalized()
        y = Vector(b["up"]).normalized()
        x = y.cross(z).normalized()
        y = z.cross(x).normalized()
        length = (tail - head).length
        r = b["radius"] * 1.04
        center = head + x * (r * .66) - z * (length * .58)
        mesh = ellipsoid("Nail_" + finger, center, (r * .30, r * .72, length * .30), basis_g=(x, y, z))
        mesh.materials.append(nail)
        finish(mesh, 180)
        nails.append(bpy.data.objects.new("Nail_" + finger, mesh))
        col.objects.link(nails[-1])

    # Sleeve with soft folds and a ribbed cuff.
    def fold(a, h):
        return 1.0 + .035 * math.sin(3 * a + h * 40) + .02 * math.sin(7 * a - h * 25)
    sleeve_mesh = lathe("Sleeve", [(.0345, 0), (.0355, .12), (.037, .3), (.038, .44)], 32, radial=fold)
    sleeve_mesh.transform(Matrix.Translation(g2b((.002, -.002, .085))) @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Diagonal((1, .9, 1, 1)))
    # lathe axis is Blender +Z; rotate +90 deg about X so it runs along Blender -Y = Godot +Z.
    sleeve_mesh.materials.append(sleeve)
    finish(sleeve_mesh, 60, flip=False)
    cuff_profile = [(.0335, -.001), (.0385, 0), (.0395, .006), (.0392, .044), (.0382, .05), (.0335, .05)]
    def rib(a, h):
        return 1.0 + .012 * math.cos(a * 36)
    cuff_mesh = lathe("Cuff", cuff_profile, 72, radial=rib)
    cuff_mesh.transform(Matrix.Translation(g2b((.002, -.002, .05))) @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Diagonal((1, .9, 1, 1)))
    cuff_mesh.materials.append(cuff)
    finish(cuff_mesh, 50)

    skin_obj = bpy.data.objects.new("ArmSkin", join([bpy.data.objects.new("tmp", skin_mesh)] + nails, "ArmSkin"))
    col.objects.link(skin_obj)
    for obj in nails:
        bpy.data.objects.remove(obj)
    sleeve_obj = bpy.data.objects.new("Sleeve", join([bpy.data.objects.new("s", sleeve_mesh), bpy.data.objects.new("c", cuff_mesh)], "Sleeve"))
    col.objects.link(sleeve_obj)

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

    # Skin weights: inverse distance to each bone segment (palm box for the hand bone).
    segs = {b["name"]: (g2b(b["head"]), g2b(b["tail"])) for b in rig["bones"]}

    def seg_distance(p, a, b, behind_penalty):
        ab = b - a
        t = (p - a).dot(ab) / ab.length_squared
        closest = a + ab * min(max(t, 0.0), 1.0)
        d = (p - closest).length
        if t < 0:
            d += -t * ab.length * behind_penalty
        return d

    palm_lo = g2b((-.016, -.034, 0.0)); palm_hi = g2b((.022, .034, -.08))
    lo = Vector((min(palm_lo.x, palm_hi.x), min(palm_lo.y, palm_hi.y), min(palm_lo.z, palm_hi.z)))
    hi = Vector((max(palm_lo.x, palm_hi.x), max(palm_lo.y, palm_hi.y), max(palm_lo.z, palm_hi.z)))

    def box_distance(p):
        d = Vector((max(lo.x - p.x, 0, p.x - hi.x), max(lo.y - p.y, 0, p.y - hi.y), max(lo.z - p.z, 0, p.z - hi.z)))
        return d.length

    def weigh(obj, only=None):
        groups = {name: obj.vertex_groups.new(name=name) for name in segs}
        for v in obj.data.vertices:
            p = v.co
            scores = {}
            if only:
                scores[only(p)] = 1.0
            else:
                for name, (a, b) in segs.items():
                    if name == "hand":
                        d = box_distance(p) + .003
                    elif name == "forearm":
                        d = seg_distance(p, a, b, 4.0) + .002
                    else:
                        d = seg_distance(p, a, b, 2.5 if name.endswith("_1") else 1.2)
                    scores[name] = 1.0 / (d + .0025) ** 5
                best = sorted(scores.items(), key=lambda kv: -kv[1])[:3]
                total = sum(w for _, w in best)
                scores = {n: w / total for n, w in best if w / total > .02}
            for name, w in scores.items():
                groups[name].add([v.index], w, "REPLACE")

    weigh(skin_obj)
    # Nails ride rigidly on their fingertip bones.
    nail_index = [i for i, m in enumerate(skin_obj.data.materials) if m.name.startswith("Nail")]
    for v in skin_obj.data.vertices:
        pass
    for poly in skin_obj.data.polygons:
        if poly.material_index in nail_index:
            for vid in poly.vertices:
                p = skin_obj.data.vertices[vid].co
                name = min((n for n in segs if n.endswith("_3")), key=lambda n: seg_distance(p, *segs[n], 1.0))
                for g in skin_obj.vertex_groups:
                    g.remove([vid])
                skin_obj.vertex_groups[name].add([vid], 1.0, "REPLACE")
    weigh(sleeve_obj, only=lambda p: "forearm")

    for obj in (skin_obj, sleeve_obj):
        obj.parent = arm_obj
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_obj
    for obj in list(col.objects):
        if obj not in (arm_obj, skin_obj, sleeve_obj):
            bpy.data.objects.remove(obj)
    export(os.path.join(OUT, "arm.glb"), [arm_obj, skin_obj, sleeve_obj])


# --- props ---------------------------------------------------------------------

BOTTLE_PROFILE = [(.0, .0), (.026, .0), (.031, .003), (.0325, .010), (.0325, .128), (.031, .142), (.025, .160),
                  (.017, .176), (.0132, .190), (.0125, .226), (.0138, .229), (.0140, .236), (.0125, .239)]


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

    outer = refine(BOTTLE_PROFILE, 4)
    mesh = lathe("Glass", outer, 48, cap_bottom=False)
    mesh.materials.append(glass)
    new_object("Glass", finish(mesh, 50), col)
    # Punt (domed bottom) seen when the bottle is tipped up.
    punt = lathe("Punt", [(.026, .0), (.018, .004), (.008, .007), (0, .008)], 48)
    punt.materials.append(glass)
    new_object("Punt", finish(punt, 60), col)

    liquid_root = empty("Liquid", col, at=(0, .005, 0))
    inner = [(max(r - .0035, .002), h - .005) for r, h in outer if .004 < h < .205]
    liquid = lathe("LiquidMesh", inner, 40, cap_bottom=True, cap_top=True)
    liquid.materials.append(beer)
    new_object("LiquidMesh", finish(liquid, 50), col, liquid_root)
    foam_mesh = lathe("Foam", [(0, -.002), (.0118, -.002), (.0118, .002), (.009, .0026), (0, .0028)], 32)
    foam_mesh.materials.append(foam)
    new_object("Foam", finish(foam_mesh, 50), col, liquid_root, (0, .196, 0))

    label_mesh = lathe("Label", [(.0331, .030), (.0331, .102)], 64, v_range=(.030, .102))
    label_mesh.materials.append(label)
    new_object("Label", finish(label_mesh, 30), col)
    neck = lathe("NeckLabel", [(.01425, .192), (.0133, .205), (.0129, .218)], 40)
    neck.materials.append(foil)
    new_object("NeckLabel", finish(neck, 40), col)

    cap_root = empty("Cap", col, at=(0, .239, 0))
    def crimp(a, h):
        return 1.0 + (.05 * math.cos(a * 21) if h < .0015 else 0.0)
    cap = lathe("CapMesh", [(.0128, -.0045), (.0158, -.0045), (.0158, .0005), (.0150, .0022), (.0135, .0032), (0, .0034)], 84, radial=crimp)
    cap.materials.append(gold)
    new_object("CapMesh", finish(cap, 35), col, cap_root)

    beads = []
    for index in range(26):
        angle = index * 2.39996 + .4
        height = .02 + math.fmod(index * .0371, .10)
        size = .0011 + math.fmod(index * .00029, .0008)
        r = .0338
        center = (math.cos(angle) * r, height, math.sin(angle) * r)
        bead = ellipsoid("Bead", center, (size, size * 1.6, size), segments=8, rings=6)
        holder = bpy.data.objects.new("b", bead)
        beads.append(holder)
    bead_mesh = join(beads, "Beads")
    bead_mesh.materials.clear()
    bead_mesh.materials.append(wet)
    new_object("Beads", finish(bead_mesh, 180), col)
    export(os.path.join(OUT, "bottle.glb"), list(col.objects))


CAN_PROFILE = [(.0, .006), (.020, .006), (.026, .0), (.0305, .004), (.0325, .014), (.0325, .112), (.0300, .124),
               (.0265, .130), (.0268, .133)]


def build_can():
    reset()
    col = collection("Can")
    wrap = material("CanWrap", (1, 1, 1, 1), .28, .55, texture="can_wrap")
    alu = material("Aluminium", (.78, .8, .82, 1), .25, .9)
    dark = material("Opening", (.04, .05, .05, 1), .6)
    rivet = material("Rivet", (.23, .24, .26, 1), .4, .6)
    body = lathe("Body", refine(CAN_PROFILE, 3), 64, v_range=(0.0, .133))
    body.materials.append(wrap)
    new_object("Body", finish(body, 40), col)
    lid = lathe("Lid", [(.0262, .1305), (.0255, .1300), (.0215, .1296), (.0205, .1302), (.0, .1302)], 48)
    lid.materials.append(alu)
    new_object("Lid", finish(lid, 30), col)
    hole = ellipsoid("Hole", (0, .1309, -.012), (.0055, .0005, .0072), segments=20, rings=6)
    hole.materials.append(dark)
    new_object("Hole", finish(hole, 180), col)
    hinge = empty("Tab", col, at=(0, .1314, 0))
    # Pull tab: a rounded plate with a finger ring at the far end.
    bm = bmesh.new()
    outline = []
    for s in range(32):
        a = TAU * s / 32
        x = .0055 * math.cos(a)
        z = .006 + .0118 * math.sin(a) * (1 if math.sin(a) > 0 else .55)
        outline.append((x, z))
    ring = []
    for s in range(32):
        a = TAU * s / 32
        ring.append((.0032 * math.cos(a), .0105 + .0032 * math.sin(a)))
    top = [bm.verts.new(g2b((x, .0006, z))) for x, z in outline]
    bot = [bm.verts.new(g2b((x, -.0006, z))) for x, z in outline]
    itop = [bm.verts.new(g2b((x, .0006, z))) for x, z in ring]
    ibot = [bm.verts.new(g2b((x, -.0006, z))) for x, z in ring]
    for i in range(32):
        j = (i + 1) % 32
        bm.faces.new((top[i], top[j], itop[j], itop[i]))
        bm.faces.new((bot[j], bot[i], ibot[i], ibot[j]))
        bm.faces.new((top[j], top[i], bot[i], bot[j]))
        bm.faces.new((itop[i], itop[j], ibot[j], ibot[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tab = bpy.data.meshes.new("TabPlate")
    bm.to_mesh(tab)
    bm.free()
    tab.materials.append(alu)
    new_object("TabPlate", finish(tab, 45), col, hinge)
    rivet_mesh = ellipsoid("Rivet", (0, .0007, 0), (.0024, .0009, .0024), segments=12, rings=6)
    rivet_mesh.materials.append(rivet)
    new_object("Rivet", finish(rivet_mesh, 180), col, hinge)
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
    filt = tube_along("Filter", (0, 0, 0), (0, 0, -.022), .0042, 20)
    filt.materials.append(cork)
    new_object("Filter", finish(filt, 50), col)
    band = tube_along("Ring", (0, 0, -.021), (0, 0, -.0222), .00428, 20, caps=False)
    band.materials.append(ring)
    new_object("Ring", finish(band, 50), col)
    pivot = empty("Paper", col, at=(0, 0, -.022))
    tube = tube_along("PaperMesh", (0, 0, 0), (0, 0, -.062), .0041, 20, caps=False)
    tube.materials.append(paper)
    new_object("PaperMesh", finish(tube, 50), col, pivot)
    end = tube_along("Tobacco", (0, 0, -.0615), (0, 0, -.062), .0040, 20)
    end.materials.append(tobacco)
    new_object("Tobacco", finish(end, 50), col, pivot)
    ash_mesh = tube_along("Ash", (0, 0, .003), (0, 0, -.003), .0039, 12, end_radius=.0033)
    ash_mesh.materials.append(ash)
    new_object("Ash", finish(ash_mesh, 180), col, None, (0, 0, -.087))
    ember_mesh = tube_along("Ember", (0, 0, .0011), (0, 0, -.0011), .0040, 14, end_radius=.0034)
    ember_mesh.materials.append(ember)
    new_object("Ember", finish(ember_mesh, 180), col, None, (0, 0, -.0846))
    export(os.path.join(OUT, "cigarette.glb"), list(col.objects))


def build_lighter():
    reset()
    col = collection("Lighter")
    plastic = material("LighterPlastic", (.70, .15, .12, 1), .32)
    steel = material("Steel", (.73, .74, .75, 1), .28, .9)
    wheel_mat = material("WheelSteel", (.33, .35, .36, 1), .45, .8)
    black = material("Button", (.11, .11, .12, 1), .6)
    # Stadium-shaped body (rounded sides), bevelled.
    bm = bmesh.new()
    outline = []
    for s in range(24):
        a = math.pi * s / 23 - math.pi / 2
        outline.append((.012 + .006 * math.cos(a), .006 * math.sin(a)))
    for s in range(24):
        a = math.pi * s / 23 + math.pi / 2
        outline.append((-.012 + .006 * math.cos(a), .006 * math.sin(a)))
    levels = [(.0, .9), (.002, 1.0), (.060, 1.0), (.062, .96)]
    rings = []
    for h, k in levels:
        rings.append([bm.verts.new(g2b((x * k, h, z * k))) for x, z in outline])
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
    new_object("Body", finish(body, 40), col)
    hood = box("Hood", (.026, .015, .0132), (0, .069, 0), bevel=.0012)
    hood.materials.append(steel)
    new_object("Hood", finish(hood, 40), col)
    for i in range(4):
        slot = box("Slot", (.0035, .007, .0134), (-.008 + i * .0055, .070, 0))
        slot.materials.append(black)
        new_object("Slot%d" % i, finish(slot), col)
    # Knurled spark wheel, axis along its local Y (Godot), turned to X by the node rotation.
    def knurl(a, h):
        return 1.0 + .08 * (1 if math.cos(a * 24) > 0 else -1) * (1 if .0015 < h < .0075 else 0)
    wheel = lathe("Wheel", [(0, 0), (.0052, 0), (.0055, .0015), (.0055, .0075), (.0052, .009), (0, .009)], 48, radial=knurl)
    wheel.transform(Matrix.Translation((0, 0, -.0045)))
    wheel.materials.append(wheel_mat)
    w = new_object("Wheel", finish(wheel, 30), col, None, (.004, .078, 0))
    w.rotation_euler = (0, -math.pi / 2, 0)
    button = box("Button", (.012, .004, .011), (-.006, .075, 0), bevel=.0008)
    button.materials.append(black)
    new_object("Button", finish(button, 40), col)
    nozzle = tube_along("Nozzle", (-.004, .076, 0), (-.004, .081, 0), .0016, 10)
    nozzle.materials.append(steel)
    new_object("Nozzle", finish(nozzle, 40), col)
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
    build_arm()
    build_bottle()
    build_can()
    build_cigarette()
    build_lighter()
    build_pack()
    build_six_pack()
    print("FP_ASSETS done")
