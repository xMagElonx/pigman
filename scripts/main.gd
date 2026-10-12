extends Node3D
## M0 / M1 的入口。
##
## 这个文件的职责只有一件事：组装。
## 环境 → 灰盒房间 → 玩家 → 调参面板。
## 所有能调的东西都在被组装的脚本里，不在这里 —— 这样它永远不会变成一团泥。

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

var _player: PlayerController
var _tuner: TunerPanel


func _ready() -> void:
	InputActions.ensure()
	_build_environment()
	Graybox.build(self, room_size, with_ceiling, floor_stripes, door_width, door_height)
	_player = _build_player()
	_build_tuner()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[PIGMAN M0/M1] WASD 移动 · Shift 冲刺 · Tab 调参面板 · Esc 释放鼠标")


func _input(event: InputEvent) -> void:
	# 用 _input 而不是 _unhandled_input：Tab 必须在 GUI 之前被截住，
	# 否则它会被拿去当焦点切换键。
	if event.is_action_pressed("toggle_panel"):
		_tuner.toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _tuner == null or _player == null:
		return
	_tuner.set_readout(
		"水平速度 %.2f m/s    地面 %s    FPS %d"
		% [
			_player.horizontal_speed(),
			"是" if _player.is_on_floor() else "否",
			Engine.get_frames_per_second(),
		]
	)


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


func _build_tuner() -> void:
	_tuner = TunerPanel.new()
	_tuner.name = "TunerPanel"
	add_child(_tuner)

	# 这一串就是你的「8 个滑条」。新增参数时只加一行。
	var entries: Array = [
		{"label": "walk_speed   慢走速度", "target": _player, "prop": "walk_speed", "min": 1.0, "max": 12.0, "step": 0.1},
		{"label": "sprint_speed   冲刺速度", "target": _player, "prop": "sprint_speed", "min": 1.0, "max": 22.0, "step": 0.1},
		{"label": "acceleration   加速度", "target": _player, "prop": "acceleration", "min": 2.0, "max": 150.0, "step": 1.0},
		{"label": "deceleration   减速度", "target": _player, "prop": "deceleration", "min": 2.0, "max": 150.0, "step": 1.0},
		{"label": "steer_rate_deg   转身速率 °/秒", "target": _player, "prop": "steer_rate_deg", "min": 60.0, "max": 2000.0, "step": 10.0},
		{"label": "mouse_sensitivity   鼠标灵敏度", "target": _player, "prop": "mouse_sensitivity", "min": 0.0005, "max": 0.008, "step": 0.0001},
		{"label": "pitch_limit_deg   抬头 / 低头上限", "target": _player, "prop": "pitch_limit_deg", "min": 30.0, "max": 89.0, "step": 1.0},
		{"label": "eye_height   眼睛高度", "target": _player, "prop": "eye_height", "min": 1.0, "max": 2.2, "step": 0.01},
		{"label": "gravity   重力", "target": _player, "prop": "gravity", "min": 0.0, "max": 60.0, "step": 0.5},
		{"label": "jump_velocity   跳跃初速（0 = 不跳）", "target": _player, "prop": "jump_velocity", "min": 0.0, "max": 12.0, "step": 0.1},
	]
	_tuner.setup(entries, "水平速度 0.00 m/s")
