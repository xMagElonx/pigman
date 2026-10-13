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
##
## ── 2026-10-14 三处改动 ──────────────────────────────────────────
##   ① 刀身尺寸抽成常量 BLADE_SIZE / BLADE_CENTER_Z，
##      模型和命中碰撞箱**共用同一个来源** → 两者不可能再对不上。
##   ② 参数持久化：启动时读 user://tuning.cfg，面板改动 0.6 秒后自动写回。
##   ③ 跳跃从借用的 ui_accept 改成独立的 jump 动作（空格），并显示跳跃高度。
##
## ── 2026-10-14 晚：跳跃默认打开 + 垂直尺 ────────────────────────
##   ④ jump_velocity 默认 0 → 7.0（跳高约 1.02 m）。
##      原因见 player_controller.gd 里那段注释：跳跃是**移动变量**，
##      不是战斗的第四个变量，它属于 M1。用户实测「一点进去就想跳」。
##   ⑤ 墙上加高度刻度（垂直尺）。地面刻度量「走多远」，它量「跳多高」。

@export_group("房间")
## 房间尺寸（米）。改这里，整个灰盒会按新尺寸重建。
@export var room_size := Vector3(14.0, 3.0, 9.0)
## 要不要天花板。默认关掉 —— 开着的话平行光进不来，灰盒会变得很平、很难读深度。
## ⚠️ 跳跃打开之后这条更值得注意：天花板一开，跳太高会撞头。
@export var with_ceiling := false
## 地面每 2 米一道刻度，用来看速度（**水平尺**）。
@export var floor_stripes := true
## 墙上每 0.5 米一道高度刻度，用来看跳跃（**垂直尺**）。1.0 m 那条是橙色。
@export var height_marks := true
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

# ── 屠刀的身材。只在这里写一次，模型和碰撞箱都从它来。──────────────
# 改这里 = 同时改模型和命中范围，永远不会出现「看着更长、判定更短」。
#
# ⚠️ 2026-10-14 的第二版换型。第一版没做成屠刀，原因很具体：
#
#   ① **刀太长**（0.80 m × 0.165 m，长高比 4.8:1）。那不是屠刀的比例，
#      是一把砍刀的。真实屠刀的长高比在 1.8:1 上下 —— 短而高。
#      → 现在 0.40 × 0.22 = 1.8:1。
#
#   ② **刀面朝向错了**（这一条才是主因，跟尺寸无关）。
#      刀刃朝正下方时，刀面是**侧对**镜头的 —— 你从上往下看刀背，
#      眼睛里剩下的是厚度那 3 厘米。所以刀做得再宽，看到的都是一根细铁条。
#      → 修法不在模型里，在**持刀姿态**里：把刀绕自身长轴转过来
#        （weapon.gd 的 `hold_roll_deg`，默认 -45°）。
#        这意味着「武器看起来不像屠刀」这个问题，
#        真正的开关不在 main.gd 而在 weapon.gd —— 这一行注释就是路标。
#
#   ③ **手长在脸上**。手腕原来只在眼前 0.12 m 处，等于刀是从脸上长出来的。
#      → 现在手腕在眼前约 0.42 m（SHOULDER_OFFSET + WRIST_OFFSET），
#        刀身作为「一条伸出去的手臂的延长」出现。
const BLADE_SIZE := Vector3(0.032, 0.22, 0.40)
## 刀身中点相对手腕（Pivot）的 z 偏移。负数 = 朝前。
## 算法：刀根固定在腕前 0.11，所以中点 = -(0.11 + 刀长/2)。
const BLADE_CENTER_Z := -0.31
## 刀根（护手位置）相对手腕的 z 偏移。
const BLADE_ROOT_Z := -0.11
## 「肩膀」相对摄像机（Head）的偏移。
## 第一人称看不见身体，所以它只是一个**不可见的旋转中心** ——
## 但挥砍必须绕它转，理由见 _build_weapon() 里那段注释。
const SHOULDER_OFFSET := Vector3(0.17, -0.38, 0.02)
## 「手腕」相对肩膀的偏移。手臂长度 = 它的模长 ≈ 0.46 m。
const WRIST_OFFSET := Vector3(0.10, 0.10, -0.44)

var _player: PlayerController
var _weapon: MeleeWeapon
var _tuner: TunerPanel
var _dummies: Array[TargetDummy] = []
var _last_dummy_switch := 1.0
var _last_auto_respawn := 2.5
var _tuning_entries: Array = []


func _ready() -> void:
	InputActions.ensure()
	_build_environment()
	Graybox.build(self, room_size, with_ceiling, floor_stripes, door_width, door_height, height_marks)
	_player = _build_player()
	_build_weapon()

	# 调参值必须在**建靶子之前**载入 —— 因为 dummy_auto_respawn 会被
	# 传进每个靶子，晚了这一步，靶子用的就还是代码初值。
	_tuning_entries = _tuner_entries()
	TuningStore.capture_defaults(_tuning_entries)
	var loaded := TuningStore.load_into(_tuning_entries, TuningStore.AUTO_PATH)

	_build_dummies()
	_build_tuner()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[PIGMAN M0/M1/M2] WASD 移动 · Shift 冲刺 · 鼠标左键 挥砍 · 空格 跳跃 · R 复位靶子 · Tab 调参面板 · Esc 释放鼠标")
	if loaded > 0:
		print("[调参] 已从 %s 载入 %d 项" % [TuningStore.human_path(TuningStore.AUTO_PATH), loaded])
	else:
		print("[调参] 没有存档，使用代码默认值。改动会自动存到 %s" % TuningStore.human_path(TuningStore.AUTO_PATH))


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
	# 「刀面偏角」是 2026-10-14 晚加的读数。
	# 它回答的是一个肉眼问题：**这片刀面到底看不看得见。**
	#   0°  = 刀面正对镜头，屠刀有多宽一目了然
	#   90° = 刀面侧对镜头，眼睛里只剩刀背那 3 厘米（= 改之前的样子）
	# 拖「持刀翻转 roll」时盯这一格 —— 它就是把「看起来不像屠刀」变成数字的地方。
	_tuner.set_readout(
		"%s    刀尖距眼 %.2f m   刀面偏角 %.0f°\n速度 %.2f m/s   %s   %s   方向偏差 %.0f°   FPS %d\n靶子 %s"
		% [
			weapon_txt,
			_tip_distance(),
			_face_angle(),
			_player.horizontal_speed(),
			"地面" if _player.is_on_floor() else "空中(操控 %.2f)" % _player.air_control,
			_jump_text(),
			_player.steer_offset_deg(),
			Engine.get_frames_per_second(),
			_dummy_hp_text(),
		]
	)


## 刀尖到眼睛的距离（米）。
## 为什么不用武器自己报的 reach()：那是**从手腕**量的。
## 手腕自己也在被挥砍带着绕肩膀转 —— 从手腕量会少算一截，
## 而玩家感知到的距离是「刀尖离我的眼睛多远」。
func _tip_distance() -> float:
	var cam := _camera()
	if _weapon == null or cam == null:
		return 0.0
	return cam.global_position.distance_to(_weapon.tip_global_position())


func _face_angle() -> float:
	var cam := _camera()
	if _weapon == null or cam == null:
		return 0.0
	return _weapon.blade_face_angle_to_deg(cam.global_position)


func _camera() -> Camera3D:
	if _player == null:
		return null
	return _player.get_node_or_null("Head/Camera3D") as Camera3D


## 跳跃那一格读数。
## 两件事要在这里说清楚（都是曾经「拖了滑条没反应」留下的教训）：
##   ① jump_velocity = 0 时明确告诉玩家「未开」，而不是留白让人以为是 bug
##   ② 除了公式算的理论高度，还给出**落地后实测的最高点** ——
##      前者是设计意图，后者才是这台机器上真的发生的
func _jump_text() -> String:
	if _player.jump_velocity <= 0.0:
		return "跳跃 未开"
	var peak := _player.last_jump_peak()
	if peak > 0.05:
		return "跳高 %.2f m · 实测 %.2f（空格）" % [_player.jump_height(), peak]
	return "跳高 %.2f m（空格）" % _player.jump_height()


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

	# ── 两级节点。它们的分工必须分清楚（2026-10-14 晚改）──────────
	#
	#   Swing（肩膀）＝ **挥砍的旋转施加在这里**。位置固定，只转。
	#   Pivot（手腕）＝ 位置固定，只负责**静止持刀姿态**（刀面朝哪）。
	#
	# 为什么必须拆成两级 —— 改之前旋转是直接加在手腕上的：
	#   那样刀是**绕着手腕原地翻**，手腕自己一动不动。
	#   真实的挥砍是整条手臂绕肩膀转，手腕自己也在走一条弧线。
	#   这个差别肉眼读出来就是：
	#     绕手腕转 → 「刀被钉在脸上转了一下」
	#     绕肩膀转 → 「抡出去了」
	#   攻击动作「很怪」，一半的原因在这个旋转中心上，不在角度上。
	#
	# ⚠️ 第一人称看不见身体，肩膀是一个**不可见的点**。但它的位置必须给对
	#    （SHOULDER_OFFSET 在脑袋右侧偏下），否则整条手臂的圆心会跑到错误的地方。
	var shoulder := Node3D.new()
	shoulder.name = "Swing"
	shoulder.position = SHOULDER_OFFSET
	_weapon.add_child(shoulder)

	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = WRIST_OFFSET
	# 姿态由 weapon.gd 的 hold_* 三个参数驱动（可在面板上调）。
	shoulder.add_child(pivot)

	# 柄：屠刀是工具，柄粗、短（一手攥死）。颜色偏木/胶的暗调。
	pivot.add_child(_mesh_box("Handle", Vector3(0.042, 0.052, 0.26), Vector3(0.0, 0.0, 0.02), Color(0.20, 0.16, 0.13)))
	# 柄尾配重块。屠刀有这个 —— 它让「柄到哪算到头」一眼可辨。
	pivot.add_child(_mesh_box("Butt", Vector3(0.050, 0.060, 0.022), Vector3(0.0, 0.0, 0.165), Color(0.30, 0.29, 0.32)))
	# 挡片：屠刀没有十字护手，只有一块挡住手的小铁片。
	pivot.add_child(_mesh_box("Collar", Vector3(0.056, 0.17, 0.028), Vector3(0.0, 0.0, -0.118), Color(0.34, 0.32, 0.35)))

	# 刀身：尺寸来自常量 —— 和下面的命中形状是同一份数据。
	# 颜色刻意压暗一点：亮的是刃口那一线，刀面太亮会把刃口吃掉。
	pivot.add_child(_mesh_box("Blade", BLADE_SIZE, Vector3(0.0, 0.0, BLADE_CENTER_Z), Color(0.58, 0.60, 0.64)))

	# 屠刀的两个特征部位。它们**不参与命中判定**（判定是沿刀身的一条胶囊），
	# 存在的唯一理由是让你一眼看出**刃在哪一边**：
	#   上缘那根更厚的 = 背脊（刀背）    下缘那根更亮的 = 刃口
	#
	# ⚠️ 它们现在能被看见了 —— 但让它们被看见的不是这两行，
	#    是 weapon.gd 里的 hold_roll_deg。刀面侧对镜头时，
	#    这两根线和刀身处在同一个平面上，等于白做。
	pivot.add_child(_mesh_box("Spine", Vector3(0.046, 0.026, BLADE_SIZE.z),
		Vector3(0.0, BLADE_SIZE.y * 0.5 - 0.013, BLADE_CENTER_Z), Color(0.40, 0.41, 0.44)))
	pivot.add_child(_mesh_box("Edge", Vector3(0.012, 0.018, BLADE_SIZE.z),
		Vector3(0.0, -BLADE_SIZE.y * 0.5 + 0.009, BLADE_CENTER_Z), Color(0.95, 0.96, 0.99)))

	# 刀身中点。扫掠检测以它为参照 —— 它比刀尖更代表「刀在哪」。
	var mid := Marker3D.new()
	mid.name = "BladeMid"
	mid.position = Vector3(0.0, 0.0, BLADE_CENTER_Z)
	pivot.add_child(mid)

	# 命中形状的载体。它挂在 Pivot 下、位置在刀身中点、绕 X 转 -90°，
	# 于是它自身的 Y 轴正好指向刀尖方向 —— **朝向自动跟随挥砍，不用手写**。
	# 形状本身（胶囊）由 MeleeWeapon._rebuild_shape() 按 blade_length 生成。
	var sc := ShapeCast3D.new()
	sc.name = "ShapeCast3D"
	sc.position = Vector3(0.0, 0.0, BLADE_CENTER_Z)
	sc.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	sc.target_position = Vector3.ZERO
	pivot.add_child(sc)

	# 把刀身的真实尺寸交给武器 —— 这是「碰撞箱 = 模型的函数」的那一次传递。
	# 必须在 add_child 之前设，因为 _ready() 里会立刻按它生成形状。
	_weapon.blade_length = BLADE_SIZE.z
	_weapon.blade_center = absf(BLADE_CENTER_Z)

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

## 面板内容。抽成独立函数，是因为「载入存档」需要**在面板建好之前**拿到
## 这份清单（否则滑条会拿着旧值初始化）。
func _tuner_entries() -> Array:
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
		{"label": "jump_velocity  跳跃(空格)", "target": _player, "prop": "jump_velocity", "min": 0.0, "max": 12.0, "step": 0.1},
		{"label": "air_control  空中操控 0-1", "target": _player, "prop": "air_control", "min": 0.0, "max": 1.0, "step": 0.05},
	]

	if _weapon != null:
		entries.append_array([
			{"label": "│ 持刀翻转 roll °", "target": _weapon, "prop": "hold_roll_deg", "min": -90.0, "max": 0.0, "step": 5.0},
			{"label": "│ 持刀抬起 pitch °", "target": _weapon, "prop": "hold_pitch_deg", "min": -30.0, "max": 40.0, "step": 2.0},
			{"label": "│ 持刀偏向 yaw °", "target": _weapon, "prop": "hold_yaw_deg", "min": -30.0, "max": 40.0, "step": 2.0},
			{"label": "│ 挥击倾斜 tilt °", "target": _weapon, "prop": "swing_tilt_deg", "min": 0.0, "max": 90.0, "step": 5.0},
			{"label": "│ 刀刃容错 radius m", "target": _weapon, "prop": "blade_radius", "min": 0.02, "max": 0.30, "step": 0.005},
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

	return entries


func _build_tuner() -> void:
	_tuner = TunerPanel.new()
	_tuner.name = "TunerPanel"
	add_child(_tuner)
	_tuner.setup(_tuning_entries, "挥击 0 · 命中 0   待机")
