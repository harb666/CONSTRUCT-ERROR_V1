class_name FrontEnd
extends Control
## The screens before a match, over the (paused) arena:
## 1. Title: "TAP TO START". The tap is a real touch, so the browser lets the
##    game's sound start right then (iPhones keep web audio off until the
##    first touch); the arena keeps loading / drawing behind it, so by the
##    time you're in, sounds play straight away.
## 2. Character select: the roster (CharacterRoster) with a turning 3D
##    preview of the picked character, and the co-op squad (up to 4 players:
##    you plus open slots until online play is added). DEPLOY starts.
## Drawn in the owner's cyan HUD style (HudStyle). Emits `deployed`, then
## fades out and frees itself.

signal started
signal deployed(character: CharacterDefinition)

enum Screen { TITLE, SELECT, OUT }

## Loading counts as done after this many smooth frames in a row (the
## phone has finished preparing the arena's graphics) or `max_loading_time`.
@export var smooth_frames_needed := 20
@export var max_loading_time := 10.0
@export var fade_time := 0.35

var screen := Screen.TITLE
var roster: CharacterRoster
var selected: CharacterDefinition
## Slowly circles the arena behind the menus (optional).
var orbit_camera: Camera3D
var orbit_center := Vector3.ZERO
var loaded := false

var _t := 0.0
var _load_t := 0.0
var _smooth := 0
var _fade := 1.0
var _screen_t := 0.0
var _press := ""
var _build := ""
var _preview_vp: SubViewport
var _preview_pivot: Node3D
var _preview_def: CharacterDefinition
var _buttons := {}  # id -> Rect2 (this frame's layout)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if roster == null:
		roster = CharacterRoster.load_default()
	if selected == null and roster and not roster.characters.is_empty():
		selected = roster.characters[0]
	if FileAccess.file_exists("res://build_info.txt"):
		_build = FileAccess.get_file_as_string("res://build_info.txt").strip_edges()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_t += delta
	_screen_t += delta
	if not loaded:
		_load_t += delta
		_smooth = _smooth + 1 if delta < 0.05 else 0
		if (_load_t > 0.5 and _smooth >= smooth_frames_needed) or _load_t > max_loading_time:
			loaded = true
	if orbit_camera and is_instance_valid(orbit_camera):
		var a := _t * 0.08
		orbit_camera.global_position = orbit_center + Vector3(sin(a) * 19.0, 8.5, cos(a) * 19.0)
		orbit_camera.look_at(orbit_center + Vector3(0, 1.0, 0))
	if _preview_pivot:
		_preview_pivot.rotation.y = _t * 0.5
	if screen == Screen.OUT:
		_fade = move_toward(_fade, 0.0, delta / fade_time)
		if _fade <= 0.0:
			queue_free()
			return
	queue_redraw()


# --- Input (own hit tests: touch, mouse, keys) ---

func _input(event: InputEvent) -> void:
	if screen == Screen.OUT:
		return
	var pos := Vector2.INF
	var pressed := false
	if event is InputEventScreenTouch and event.index == 0:
		pos = event.position
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		pos = event.position
		pressed = event.pressed
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_activate("start" if screen == Screen.TITLE else "deploy")
		get_viewport().set_input_as_handled()
		return
	else:
		return
	get_viewport().set_input_as_handled()
	var hit := _hit(pos)
	if pressed:
		_press = hit
	else:
		if hit != "" and hit == _press:
			_activate(hit)
		_press = ""


func _hit(pos: Vector2) -> String:
	if screen == Screen.TITLE:
		return "start"  # anywhere
	for id in _buttons:
		if (_buttons[id] as Rect2).grow(8.0).has_point(pos):
			return id
	return ""


## Presses a button by id ("start", "deploy", "char:<id>").
func _activate(id: String) -> void:
	if id == "start" and screen == Screen.TITLE:
		if not loaded:
			return
		screen = Screen.SELECT
		_screen_t = 0.0
		_make_preview()
		started.emit()
	elif id == "deploy" and screen == Screen.SELECT and selected:
		screen = Screen.OUT
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		deployed.emit(selected)
	elif id.begins_with("char:") and screen == Screen.SELECT:
		var def := roster.find(StringName(id.substr(5)))
		if def:
			selected = def
			_make_preview()


## Test / desktop helpers.
func press_start() -> void:
	_activate("start")


func press_deploy() -> void:
	_activate("deploy")


func press_character(id: StringName) -> void:
	_activate("char:" + String(id))


# --- 3D preview of the picked character ---

func _make_preview() -> void:
	if selected == null or selected == _preview_def or selected.preview_model == null:
		return
	_preview_def = selected
	if _preview_vp == null:
		_preview_vp = SubViewport.new()
		_preview_vp.own_world_3d = true
		_preview_vp.transparent_bg = true
		_preview_vp.msaa_3d = Viewport.MSAA_2X
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_preview_vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.65, 0.78, 0.85)
		env.environment.ambient_light_energy = 0.9
		_preview_vp.add_child(env)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-30, 25, 0)
		key.light_energy = 1.25
		_preview_vp.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-12, 165, 0)
		rim.light_color = HudStyle.CYAN
		rim.light_energy = 1.4
		_preview_vp.add_child(rim)
		_preview_vp.add_child(_make_platform())
		var cam := Camera3D.new()
		cam.name = "Camera"
		cam.fov = 30.0
		_preview_vp.add_child(cam)
	if _preview_pivot:
		_preview_pivot.queue_free()
	_preview_pivot = Node3D.new()
	_preview_vp.add_child(_preview_pivot)
	var model: Node3D = selected.preview_model.instantiate()
	model.rotation_degrees.y = selected.preview_yaw_degrees
	_preview_pivot.add_child(model)
	if selected.preview_caps:
		selected.preview_caps.apply(model)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and selected.preview_animation != "" and ap.has_animation(selected.preview_animation):
		ap.get_animation(selected.preview_animation).loop_mode = Animation.LOOP_LINEAR
		ap.play(selected.preview_animation)
	# Frame the whole body.
	var cam := _preview_vp.get_node("Camera") as Camera3D
	var h := 1.8
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		var s := sk[0] as Skeleton3D
		var head := s.find_bone("mixamorig_Head")
		if head >= 0:
			h = (s.transform * s.get_bone_global_rest(head)).origin.y * model.scale.y + 0.5
	var dist := h * 0.7 / tan(deg_to_rad(cam.fov * 0.5))
	cam.position = Vector3(0, h * 0.62, dist)
	cam.look_at(Vector3(0, h * 0.5, 0))


## Glowing ring pad the character stands on.
func _make_platform() -> Node3D:
	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.8
	cyl.height = 0.06
	disc.mesh = cyl
	disc.position.y = -0.03
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.12, 0.14)
	m.roughness = 0.9
	disc.material_override = m
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.76
	tor.outer_radius = 0.785
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = HudStyle.CYAN
	ring.material_override = rm
	root.add_child(ring)
	return root


# --- Drawing ---

func _draw() -> void:
	_buttons.clear()
	var a := _fade
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(HudStyle.BG, (0.86 if screen == Screen.TITLE else 0.9) * a))
	HudStyle.grid(self, r, 48.0, Color(HudStyle.CYAN, 0.05 * a), Vector2(_t * 6.0, _t * 3.0))
	if screen == Screen.TITLE:
		_draw_title(a)
	else:
		_draw_select(a)


func _margin() -> float:
	return maxf(40.0, size.x * 0.03)


func _draw_title(a: float) -> void:
	var tf := HudStyle.title_font()
	var lf := HudStyle.label_font()
	var nf := HudStyle.num_font()
	var cx := size.x * 0.5
	# Title with a soft glow.
	var title := "CONSTRUCT-ERROR"
	var ts := HudStyle.fit(tf, title, size.x - 2.0 * _margin() - 40.0, 72)
	var ty := size.y * 0.3
	for k in 3:
		var o := (3 - k) * 2.0
		HudStyle.text(self, tf, Vector2(cx, ty) + Vector2(0, o * 0.3), title, ts, Color(HudStyle.CYAN, 0.12 * a), 0.5, int(o * 2.0))
	HudStyle.text(self, tf, Vector2(cx, ty), title, ts, Color(HudStyle.TEXT, a), 0.5)
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
	draw_line(Vector2(cx - tw * 0.5, ty + 16), Vector2(cx + tw * 0.5, ty + 16), Color(HudStyle.CYAN, 0.7 * a), 2.0)
	HudStyle.stripes(self, Vector2(cx + tw * 0.5 - 46, ty + 28), 7, Color(HudStyle.CYAN, 0.8 * a))
	HudStyle.text(self, lf, Vector2(cx - tw * 0.5, ty + 40), "CO-OP ARENA  //  1-4 PLAYERS", 22, Color(HudStyle.CYAN, 0.9 * a))
	# Emblem + button.
	var ec := Vector2(cx, size.y * 0.6)
	var er := minf(size.y * 0.13, 96.0)
	HudStyle.emblem(self, ec, er, _t, HudStyle.CYAN, a)
	var btn := Rect2(Vector2(cx - 170, ec.y + er + 26), Vector2(340, 58))
	if not loaded:
		# Loading gauge (reference sheet's percentage rings).
		var k := clampf(float(_smooth) / smooth_frames_needed, 0.0, 1.0)
		draw_arc(ec, er * 0.55, -PI * 0.5, -PI * 0.5 + TAU * maxf(k, 0.04), 48, Color(HudStyle.CYAN, a), 5.0, true)
		HudStyle.text(self, nf, ec + Vector2(0, 8), "%d%%" % roundi(k * 100.0), 22, Color(HudStyle.TEXT, a), 0.5)
		HudStyle.panel(self, btn, HudStyle.CYAN_DIM, HudStyle.FILL_DARK, 14.0, a)
		var stripes_x := fposmod(_t * 60.0, 24.0)
		for i in 14:
			var x := btn.position.x + 14 + i * 24 + stripes_x - 24
			if x > btn.position.x + 8 and x < btn.end.x - 22:
				draw_line(Vector2(x, btn.end.y - 10), Vector2(x + 8, btn.end.y - 18), Color(HudStyle.CYAN, 0.5 * a), 3.0)
		HudStyle.text(self, lf, btn.get_center() + Vector2(0, -2), "LOADING", 24, Color(HudStyle.TEXT, 0.7 * a), 0.5)
	else:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		HudStyle.text(self, nf, ec + Vector2(0, 8), "READY", 20, Color(HudStyle.TEXT, a), 0.5)
		HudStyle.panel(self, btn, HudStyle.CYAN, HudStyle.FILL.lerp(Color(HudStyle.CYAN, 0.45), pulse * 0.5), 14.0, a)
		HudStyle.brackets(self, btn, Color(HudStyle.CYAN, (0.5 + 0.5 * pulse) * a), 16.0, 6.0 + pulse * 4.0)
		HudStyle.text(self, nf, btn.get_center() + Vector2(0, 10), "TAP TO START", 26, Color(HudStyle.TEXT, a), 0.5, 3)
	_buttons["start"] = btn
	if _build != "":
		HudStyle.text(self, lf, Vector2(size.x - _margin(), size.y - 14), "build " + _build, 15, Color(HudStyle.TEXT, 0.45 * a), 1.0)


func _draw_select(a: float) -> void:
	var tf := HudStyle.title_font()
	var lf := HudStyle.label_font()
	var nf := HudStyle.num_font()
	var m := _margin()
	var slide := 1.0 - pow(1.0 - clampf(_screen_t / 0.3, 0.0, 1.0), 3.0)
	var off := Vector2(0, (1.0 - slide) * 24.0)
	a *= slide
	# Header.
	var head := Rect2(Vector2(m, 16) - off, Vector2(size.x - 2.0 * m, 52))
	HudStyle.panel(self, head, HudStyle.CYAN, HudStyle.FILL, 14.0, a)
	HudStyle.text(self, tf, head.position + Vector2(20, 36), "CHARACTER SELECT", HudStyle.fit(tf, "CHARACTER SELECT", head.size.x * 0.5, 28), Color(HudStyle.TEXT, a))
	var players := 1
	HudStyle.text(self, lf, Vector2(head.end.x - 20, head.position.y + 34), "CO-OP SQUAD  %d / %d" % [players, CharacterRoster.MAX_PLAYERS], 22, Color(HudStyle.CYAN, a), 1.0)
	# 3D preview.
	var top := head.end.y + 22.0
	var bottom := size.y - 24.0
	var pw := clampf(size.x * 0.36, 300.0, 560.0)
	var pr := Rect2(Vector2(m, top) + off, Vector2(pw, bottom - top))
	HudStyle.panel(self, pr, HudStyle.CYAN, HudStyle.FILL_DARK, 18.0, a)
	HudStyle.brackets(self, pr, Color(HudStyle.CYAN, a), 22.0, 6.0, 3.0)
	if _preview_vp:
		var scale := clampf(get_viewport().get_final_transform().get_scale().x, 1.0, 2.0)
		var inner := pr.grow(-10.0)
		inner.size.y -= 50.0
		var want := Vector2i(maxi(int(inner.size.x * scale), 2), maxi(int(inner.size.y * scale), 2))
		if _preview_vp.size != want:
			_preview_vp.size = want
		draw_texture_rect(_preview_vp.get_texture(), inner, false, Color(1, 1, 1, a))
	var plate := Rect2(Vector2(pr.position.x + 16, pr.end.y - 54), Vector2(pr.size.x - 32, 40))
	HudStyle.panel(self, plate, HudStyle.CYAN, HudStyle.FILL, 10.0, a)
	var nm := selected.display_name if selected else "-"
	HudStyle.text(self, tf, plate.get_center() + Vector2(0, 11), nm, 28, Color(HudStyle.TEXT, a), 0.5)
	# Roster.
	var rx := pr.end.x + 26.0
	var rw := size.x - m - rx
	HudStyle.text(self, lf, Vector2(rx, top + 16), "CHARACTERS", 20, Color(HudStyle.CYAN, a))
	var card := Vector2(118, 132)
	var cx := rx
	for def in roster.characters:
		var cr := Rect2(Vector2(cx, top + 26) + off, card)
		var sel := def == selected
		HudStyle.panel(self, cr, HudStyle.CYAN, HudStyle.FILL if sel else HudStyle.FILL_DARK, 12.0, a)
		if sel:
			HudStyle.brackets(self, cr, Color(def.accent_color, a), 14.0, 4.0 + 2.0 * sin(_t * 5.0), 3.0)
		if def.portrait:
			draw_texture_rect(def.portrait, Rect2(cr.position + Vector2(9, 8), Vector2(card.x - 18, card.x - 18)), false, Color(1, 1, 1, a))
		HudStyle.text(self, lf, Vector2(cr.get_center().x, cr.end.y - 8), def.display_name, HudStyle.fit(lf, def.display_name, card.x - 12, 20), Color(HudStyle.TEXT, a), 0.5)
		_buttons["char:" + String(def.id)] = cr
		cx += card.x + 14.0
	# Squad: you + open slots for online co-op.
	var sy := top + 26 + card.y + 34.0
	HudStyle.text(self, lf, Vector2(rx, sy - 8), "SQUAD  //  ONLINE CO-OP", 20, Color(HudStyle.CYAN, a))
	var deploy := Rect2(Vector2(size.x - m - 280, bottom - 62) + off, Vector2(280, 62))
	var row_h := clampf((deploy.position.y - 16.0 - sy) / CharacterRoster.MAX_PLAYERS - 8.0, 30.0, 52.0)
	for i in CharacterRoster.MAX_PLAYERS:
		var rr := Rect2(Vector2(rx, sy + i * (row_h + 8.0)) + off, Vector2(rw, row_h))
		var you := i == 0
		HudStyle.panel(self, rr, HudStyle.CYAN if you else HudStyle.CYAN_DIM, HudStyle.FILL if you else Color(HudStyle.FILL_DARK, 0.5), 8.0, a)
		var chip := Rect2(rr.position + Vector2(10, (row_h - 22) * 0.5), Vector2(36, 22))
		draw_colored_polygon(HudStyle.chamfer(chip, [6.0, 0.0, 6.0, 0.0]), Color(HudStyle.CYAN, (1.0 if you else 0.35) * a))
		HudStyle.text(self, nf, Vector2(chip.get_center().x, chip.end.y - 5), "P%d" % (i + 1), 13, Color(HudStyle.BG, a), 0.5)
		var ty := rr.get_center().y + 7
		if you:
			if selected and selected.portrait:
				var ps := row_h - 8.0
				draw_texture_rect(selected.portrait, Rect2(Vector2(chip.end.x + 10, rr.position.y + 4), Vector2(ps, ps)), false, Color(1, 1, 1, a))
			HudStyle.text(self, lf, Vector2(chip.end.x + row_h + 14, ty), "YOU  -  " + nm, 21, Color(HudStyle.TEXT, a))
			HudStyle.text(self, lf, Vector2(rr.end.x - 16, ty), "READY", 19, Color(HudStyle.HEALTH, a), 1.0)
		else:
			HudStyle.text(self, lf, Vector2(chip.end.x + 14, ty), "OPEN SLOT", 20, Color(HudStyle.TEXT, 0.4 * a))
	# Deploy.
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	HudStyle.panel(self, deploy, HudStyle.CYAN, HudStyle.FILL.lerp(Color(HudStyle.CYAN, 0.5), 0.3 + pulse * 0.3), 16.0, a)
	HudStyle.brackets(self, deploy, Color(HudStyle.CYAN, a), 16.0, 5.0 + pulse * 3.0)
	HudStyle.text(self, tf, deploy.get_center() + Vector2(0, 12), "DEPLOY", 32, Color(HudStyle.TEXT, a), 0.5, 3)
	_buttons["deploy"] = deploy
