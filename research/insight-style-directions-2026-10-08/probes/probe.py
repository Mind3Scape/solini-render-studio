import bpy, bmesh, sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
ob = bpy.context.active_object
ob.name = "Wall_panel"
mod = ob.modifiers.new("bevel", "BEVEL"); mod.width = 0.05; mod.segments = 2; mod.limit_method = 'ANGLE'
bpy.ops.object.modifier_apply(modifier="bevel")
me = ob.data
me.uv_layers.new(name="UVMap")
me.uv_layers.new(name="Lightmap")
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
me.uv_layers.active = me.uv_layers["Lightmap"]
bpy.ops.uv.lightmap_pack()
bpy.ops.object.mode_set(mode='OBJECT')
mat = bpy.data.materials.new("Porcelain_panel"); mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]; bsdf.inputs["Base Color"].default_value = (0.86, 0.86, 0.85, 1); bsdf.inputs["Roughness"].default_value = 0.55
me.materials.append(mat)
out = sys.argv[-1]
bpy.ops.wm.usd_export(filepath=out, export_uvmaps=True, export_materials=True, generate_preview_surface=True)
print("EXPORTED", out, [l.name for l in me.uv_layers], len(me.polygons))
