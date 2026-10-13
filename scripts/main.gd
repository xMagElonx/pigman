extends Node3D
## M0 / M1 / M2 的入口。
##
## 这个文件的职责只有一件事：组装。
## 环境 → 灰盒房间 → 玩家 → 武器 → 靶子 → 调参面板。
## 所有能调的东西都在被组装的脚本里，不在这里 —— 这样它永远不会变成一团泥。
##
## ── 为什么靶子排在这个顺序里（2026-10-12 修正）──────────────────
## 移动不是战斗的前置，移动是战斗的一部分。
## 在一个空房间里拖那几个滑条，你没有可失去的东西 —— 也就分不出
## 「这个身体听我的话」和「这个身体只是没被我用来做任何事」。
## 靶子放进来之后，同一个滑条第一次有了含义：
##   acceleration 不够 → 敌人已经贴脸了你还没起步
##   deceleration 太小 → 你冲过头，刀从它旁边划过去
##   steer_rate 太大  → 你没法在转身时把刀留在它身上
## 这三个信号，空房间里一个都测不出来。

@export_group("房间")
## 房间尺寸（米）。改这里，整个灰盒会按新尺寸重建。
@export var room_size := Vector3(14.0, 3.0, 9.0)
## 要不要天花板。默认关掉 —— 开着的话平行光进不来，灰盒会变得很平、很难读深度。
@export var with_ceiling := false
## 地面每 2 米一道刻度，用来看速度。
@export var floor_stripes := true
## 北墙门洞的宽与高（米）。M5 会在这里放一扇真的门。
@export var door_width := 2.2
@export var door_height := 2.2

@export_group("玩家")
## 出生点。y 稍微抬高一点，避免第一帧卡进地面。
@export var spawn_position := Vector3(0.0, 0.2, 3.0)

@export_group("靶子")
## 近靶：站一米外，只测挥砍本身。
@export var dummy_near := Vector3(-1.30, 0.0, -0.60)
## 远靶：站四米外，测「起步 → 冲刺 → 刹车 → 出刀」这一整串。
@export var dummy_far := Vector3(1.30, 0.0, -3.20)
## 靶子开关（0 = 隐藏，1 = 显示）。给面板用的，所以是 float。
## 需要单独验证移动手感时把它拖到 0。
@export var dummy_switch := 1.0
## 倒地后几秒自动站起来。0 = 不自动（只能按 R）。
## ⚠️ M3 的真敌人要设为 0 —— 敌人不该复活。
@export var dummy_auto_respawn := 2.5

var _player: PlayerController
var _weapon: MeleeWeapon
var _tuner: TunerPanel
var _dummies: Array[TargetDummy] = []
var _last_dummy_switch := 1.0
var _last_auto_respawn := 2.5


func _ready() -> void:
	InputActions.ensure()
	_build_environment()
	Graybox.build(self, room_size, with_ceiling, floor_stripes, door_width, door_height)
	_player = _build_player()
	_build_weapon()
	_build_dummies()
	_build_tuner()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[PIGMAN M0/M1/M2] WASD 移动 · Shift 冲刺 · 鼠标左键 挥砍 · R 复位靶子 · Tab 调参面板 · Esc 释放鼠标")


func _input(event: InputEvent) -> void:
	# 用 _input 而不是 _unhandled_input：Tab 必须在 GUI 之前被截住，
	# 否则它会被拿去当焦点切换键。
	if event.is_action_pressed("toggle_panel"):
		_tuner.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_dummies"):
		for d in _dummies:
			d.respawn()


func _process(_delta: float) -> void:
	if _tuner == null or _player == null:
		return

	if not is_equal_approx(_last_dummy_switch, dummy_switch):
		_last_dummy_switch = dummy_switch
		_set_dummies_active(dummy_switch >= 0.5)

	if not is_equal_approx(_last_auto_respawn, dummy_auto_respawn):
		_last_auto_respawn = dummy_auto_respawn
		for d in _dummies:
			d.auto_respawn_delay = dummy_auto_respawn

	var weapon_txt := "武器未装配"
	if _weapon != null:
		weapon_txt = "%s   %s" % [_weapon.stats(), _weapon.phase_name()]

	# 「方向偏差」是 2026-10-13 加的：速度方向和朝向差多少度。
	# 0° = 身体听话；转身时会瞬间飚到 90°~180° 再回落 ——
	# 那个「莫名其妙的左右位移」第一次变成可读的数字。
	_tuner.set_readout(
		"%s\n速度 %.2f m/s   方向偏差 %.0f°   地面 %s   FPS %d\n靶子 %s"
		% [
			weapon_txt,
			_player.horizontal_speed(),
			_player.steer_offset_deg(),
			"是" if _player.is_on_floor() else "否",
			Engine.get_frames_per_second(),
			_dummy_hp_text(),
		]
	)


func _dummy_hp_text() -> String:
	var parts: PackedStringArray = []
	for d in _dummies:
		if d.down and d.auto_respawn_delay > 0.0:
			parts.append("%.1fs 后复位" % maxf(0.0, d.auto_respawn_delay - d.down_timer()))
		elif d.down:
			parts.append("已倒 · 按 R")
		else:
			parts.append("%d/%d" % [d.hp, d.max_hp])
	return " · ".join(parts)


func _set_dummies_active(v: bool) -> void:
	for d in _dummies:
		d.set_active(v)


# --- 环境 -------------------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.065, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.70)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)


# --- 玩家 -------------------------------------------------------------------

func _build_player() -> PlayerController:
	var p := PlayerController.new()
	p.name = "Player"
	p.position = spawn_position

	# 碰撞胶囊：高度含两端半球，所以位置要上抬半个身高，
	# 让胶囊底部正好落在节点原点（= 脚底）上。
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0.0, cap.height * 0.5, 0.0)
	p.add_child(col)

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, p.eye_height, 0.0)
	p.add_child(head)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 82.0
	cam.near = 0.05
	head.add_child(cam)

	add_child(p)
	return p


# --- 武器 -------------------------------------------------------------------

func _build_weapon() -> void:
	var head := _player.get_node_or_null("Head")
	if head == null:
		return

	_weapon = MeleeWeapon.new()
	_weapon.name = "Weapon"

	# Pivot 就是「手腕」：绕它转 y 轴 = 横斩。
	# 位置放在画面右下角，是因为第一人称里刀身从正中横过去会挡住你看敌人。
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0.30, -0.22, -0.12)
	_weapon.add_child(pivot)

	var handle := _mesh_box("Handle", Vector3(0.05, 0.05, 0.22), Vector3(0.0, 0.0, 0.07), Color(0.16, 0.15, 0.17))
	pivot.add_child(handle)

	var guard := _mesh_box("Guard", Vector3(0.24, 0.05, 0.05), Vector3(0.0, 0.0, -0.03), Color(0.36, 0.34, 0.37))
	pivot.add_child(guard)

	var blade := _mesh_box("Blade", Vector3(0.085, 0.028, 1.15), Vector3(0.0, 0.0, -0.66), Color(0.80, 0.82, 0.86))
	pivot.add_child(blade)

	# 刀身中点。扫掠检测以它为参照 —— 它比刀尖更代表「刀在哪」。
	var mid := Marker3D.new()
	mid.name = "BladeMid"
	mid.position = Vector3(0.0, 0.0, -0.66)
	pivot.add_child(mid)

	var sc := ShapeCast3D.new()
	sc.name = "ShapeCast3D"
	var sphere := SphereShape3D.new()
	sphere.radius = _weapon.hit_radius
	sc.shape = sphere
	sc.target_position = Vector3.ZERO
	pivot.add_child(sc)

	head.add_child(_weapon)


func _mesh_box(node_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	m.metallic = 0.35
	mesh.material_override = m
	mesh.position = pos
	return mesh


# --- 靶子 -------------------------------------------------------------------

func _build_dummies() -> void:
	for pos in [dummy_near, dummy_far]:
		var d := TargetDummy.new()
		d.name = "Dummy"
		d.position = pos
		d.auto_respawn_delay = dummy_auto_respawn
		add_child(d)
		_dummies.append(d)


# --- 调参面板 ---------------------------------------------------------------

func _build_tuner() -> void:
	_tuner = TunerPanel.new()
	_tuner.name = "TunerPanel"
	add_child(_tuner)

	# 这一串就是你的「滑条」。新增参数时只加一行。
	# 标签刻意压短 —— 面板是单行布局，太长会被裁掉。
	var entries: Array = [
		{"label": "walk_speed  慢走", "target": _player, "prop": "walk_speed", "min": 1.0, "max": 12.0, "step": 0.1},
		{"label": "sprint_speed  冲刺", "target": _player, "prop": "sprint_speed", "min": 1.0, "max": 22.0, "step": 0.1},
		{"label": "acceleration  加速", "target": _player, "prop": "acceleration", "min": 2.0, "max": 150.0, "step": 1.0},
		{"label": "deceleration  减速（惯性）", "target": _player, "prop": "deceleration", "min": 2.0, "max": 150.0, "step": 1.0},
		{"label": "steer_rate_deg  转向 °/s", "target": _player, "prop": "steer_rate_deg", "min": 60.0, "max": 4000.0, "step": 10.0},
		{"label": "turn_speed_keep  转身掉速", "target": _player, "prop": "turn_speed_keep", "min": 0.0, "max": 1.0, "step": 0.01},
		{"label": "mouse_sensitivity  鼠标", "target": _player, "prop": "mouse_sensitivity", "min": 0.0005, "max": 0.008, "step": 0.0001},
		{"label": "pitch_limit_deg  俯仰上限", "target": _player, "prop": "pitch_limit_deg", "min": 30.0, "max": 89.0, "step": 1.0},
		{"label": "eye_height  眼高", "target": _player, "prop": "eye_height", "min": 1.0, "max": 2.2, "step": 0.01},
		{"label": "gravity  重力", "target": _player, "prop": "gravity", "min": 0.0, "max": 60.0, "step": 0.5},
		{"label": "jump_velocity  跳跃(0=不跳)", "target": _player, "prop": "jump_velocity", "min": 0.0, "max": 12.0, "step": 0.1},
	]

	if _weapon != null:
		entries.append_array([
			{"label": "│ 前摇 windup s", "target": _weapon, "prop": "windup", "min": 0.0, "max": 0.5, "step": 0.01},
			{"label": "│ 命中窗口 active s", "target": _weapon, "prop": "active", "min": 0.02, "max": 0.40, "step": 0.01},
			{"label": "│ 后摇 recovery s", "target": _weapon, "prop": "recovery", "min": 0.05, "max": 0.80, "step": 0.01},
			{"label": "│ 扫掠角 °", "target": _weapon, "prop": "swing_angle_deg", "min": 30.0, "max": 200.0, "step": 5.0},
			{"label": "│ 顿帧 hitstop s", "target": _weapon, "prop": "hitstop", "min": 0.0, "max": 0.20, "step": 0.005},
			{"label": "│ 屏震 shake m", "target": _weapon, "prop": "shake_strength", "min": 0.0, "max": 0.15, "step": 0.005},
		])

	entries.append_array([
		{"label": "│ 靶子开关 0/1", "target": self, "prop": "dummy_switch", "min": 0.0, "max": 1.0, "step": 1.0},
		{"label": "│ 靶子自动复位 sec", "target": self, "prop": "dummy_auto_respawn", "min": 0.0, "max": 10.0, "step": 0.5},
	])

	_tuner.setup(entries, "挥击 0 · 命中 0   待机")
