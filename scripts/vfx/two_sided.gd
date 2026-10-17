class_name TwoSided
extends RefCounted
## Draws a character's opaque body materials on both sides (owner asked:
## "fix any open meshes on every character"). The models are built from
## single-sided pieces - coat tails, armour plates, joint sleeves - and from
## below or at a joint you could look past an edge at a piece's back, which
## wasn't drawn, so it showed as a hole. With both sides drawn the back of
## a piece shows its own texture (lit from the side you see), so nothing
## reads as see-through. Transparent and shader materials are left alone.
## The materials are shared, so each is changed once.


static func apply(root: Node) -> int:
	var changed := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si)
			if m == null:
				m = mi.mesh.surface_get_material(si)
			var bm := m as BaseMaterial3D
			if bm == null or bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.cull_mode != BaseMaterial3D.CULL_BACK:
				continue
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			changed += 1
	return changed
