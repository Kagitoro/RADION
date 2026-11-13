"""Renders quick turntable previews of the built glb files (workbench, studio light).
    Blender -b --python tools/blender/preview_fp_assets.py -- <out_dir> [names...]"""
import bpy, sys, os, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
out = argv[0] if argv else "/tmp"
names = argv[1:] or ["arm","bottle","can","cigarette","lighter","pack","six_pack"]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
for name in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,"assets","fp",name+".glb"))
    objs = [o for o in bpy.context.scene.objects if o.type=="MESH"]
    lo = Vector((1e9,)*3); hi = Vector((-1e9,)*3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min,lo,w)); hi = Vector(map(max,hi,w))
    center = (lo+hi)/2; size = (hi-lo).length
    if name == "arm":  # frame the hand, not the whole sleeve
        center = Vector((0,.05,0)); size = .16
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 640; scene.render.resolution_y = 480
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam); scene.camera = cam
    cam.data.lens = 50
    cam.data.clip_start = .005
    for i, angle in enumerate((30, 120, 210, 300)):
        a = math.radians(angle)
        cam.location = center + Vector((math.cos(a), math.sin(a), .55)).normalized()*size*1.5
        cam.rotation_euler = (center-cam.location).to_track_quat("-Z","Y").to_euler()
        scene.render.filepath = os.path.join(out, "%s_%d.png" % (name,i))
        bpy.ops.render.render(write_still=True)
