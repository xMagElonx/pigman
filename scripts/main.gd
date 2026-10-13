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
##
## ── 2026-10-14 深夜：刀身换成轮廓挤出网格 ────────────────────────
##   ⑥ 刀身不再是一块按长宽高缩放的矩形盒，而是 scripts/knife_mesh.gd
##      挤出的一条二维侧影。尺寸从常量搬到了 KnifeMesh 节点上，由面板驱动。
##      唯一不变的那条规矩：**碰撞箱仍是模型的函数** —— 长度直接从网格
##      包围盒量出来注入武器（见 _sync_blade_geometry）。
##
## ── 2026-10-14 夜（第二轮）：刀柄与握持点参数化 + 去护手 ──────────
##   ⑦ 柄不再是一行硬编码的 BoxMesh。按美术规格 §7「柄部规格（无护手版）」，
##      整根柄换成四个节点：刀身 → **Neck（金属柄舌）** → **Handle（木圆棒）**
##      → [可选] 柄尾加粗段。四根滑条进面板（见 _rebuild_handle）。
##   ⑧ **护手删掉。** 档案原文「刀身尾端呈尖錐狀，刀柄以木材製作，呈圓形短棒，
##      於木棒頂端挖洞插入尖錐固定」—— 没有护手。旧 Collar 节点整个移除。
##   ⑨ 柄身改成**圆柱木棒**（档案「圓形短棒」），radial_segments = 8（八棱，§7.2.4）。
##      ⚠️ 三条结构性的规矩（本轮新增，别拆）：
##        · 刀根固定在 z = BLADE_ROOT_Z（−0.11）—— 刀身一个顶点都没动。
##        · 「握持点」= 把**整坨武器**沿 Z 平移（§7.3.3）。默认平移 0 →
##          reach / blade_center / 刀尖距眼**全部不变**；一旦拖动，
##          视觉与命中胶囊**一起正确地变**。
##        · 「碰撞箱 = 模型的函数」这条链**原样保留**：挪刀根之后立刻
##          重走 _sync_blade_geometry（柄一变，命中胶囊跟着变）。
##   ⑩ 旧金属配重块 Butt 删（§7.2.5：剑的柄首，屠刀没有）→ 换成**可选木柄尾加粗**，
##      默认关。它钉在柄尾上，柄变长跟着走。
##      knife_mesh.gd 的刀身几何**一个字没动**。

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

@export_group("刀柄 / 握持")
## 柄长（米）：木柄从前端到柄尾的长度。默认 0.20（= 刀身的一半，§7.2.3）。
## 范围 0.14–0.28：低于 0.14「握不住」，高于 0.28 开始读成关刀。
@export var handle_len := 0.200:
	set(v):
		handle_len = maxf(0.05, v)
		_rebuild_handle()
## 柄径（米）：圆木棒的**直径**。默认 0.040（一手攥死，§7.2.1–7.2.2）。
@export var handle_dia := 0.040:
	set(v):
		handle_dia = maxf(0.012, v)
		_rebuild_handle()
## 握持点前后平移（米）——⭐ 玩家点名要的那一根（§7.3.3）。
## ⚠️ 它不是「手在柄上滑」，而是**把整坨武器沿 Z 前后平移**（手=Pivot 位置锁死）：
##   + = 武器前移 → 手相对柄靠尾（靠尾握）→ 刀尖距眼**变远**、绕肩半径**变大**
##   − = 武器后移 → 手相对柄贴刀根（贴刀握）→ 刀尖距眼**变近**
## 默认 0.000 → 刀根仍在 −0.11 → reach / 刀尖距眼**一个都不变**（§7.6 不变量）。
@export var grip_offset := 0.000:
	set(v):
		grip_offset = v
		_rebuild_handle()
## 露柄舌长（米）：刀根与木柄之间**露出**的金属柄颈长（§7.1.4）。0 = 完全没入。
@export var neck_len := 0.010:
	set(v):
		neck_len = maxf(0.0, v)
		_rebuild_handle()
## 柄尾加粗（米，直径增量）：木柄最后 1.5 cm 略微加粗（§7.2.5）。0 = 不加粗（默认）。
## 它是旧金属配重块 Butt 的替代 —— 仍是木色，不引入金属。
@export var butt_bulge := 0.000:
	set(v):
		butt_bulge = maxf(0.0, v)
		_rebuild_handle()

# ── 屠刀的身材 ─────────────────────────────────────────────────────
#
# ⚠️ 2026-10-14 夜 · 第三版：刀身从「矩形盒」改成**二维轮廓挤出的网格**。
#
#   前两版为什么都不够（完整对比见 documents/knife-mesh-implementation.md）：
#   ① 长高比只是「大概像」，它改不出刀背的平直、刃口的弧、刀尖的收 ——
#      因为这些信息在**侧影**里，不在长宽高三个数字里。
#   ② 一根 BoxMesh 只有四个矩形面，第一人称看过去永远是一块铁板。
#
#   → 现在刀身 = scripts/knife_mesh.gd（KnifeMesh）：把一条二维轮廓
#     沿厚度方向挤出，得到有刀背脊、有刃口亮带、有一端收尖的真侧影。
#     轮廓顶点来自美术规格 documents/knife-profile-spec.md（14 点 + 楔形截面）。
#
#   ⚠️ **刀身的所有尺寸不再写在这个文件里。** 它们长在 KnifeMesh 节点上，
#      由面板的「刀身 长 / 宽 / 刀脊厚 / 刃口厚」四根滑条驱动。
#      main.gd 只做一件事：从**网格包围盒**量出长度、从节点位置量出中点，
#      注入 MeleeWeapon —— 碰撞箱依旧是**模型的函数**，而且这次连长度都是。
#      这就是上一版那个「看着砍到了却判不到」的坑，在结构上被焊死的地方。
#
#   （更早两版的记录仍然成立，留着当路标）
#     · 「武器看起来不像屠刀」有**两个**开关，缺一不可：
#         形状 —— 现在由轮廓决定（knife_mesh.gd）
#         朝向 —— 刀面必须斜朝镜头，否则你只看得到刀背的厚度。
#                 那个开关在 weapon.gd 的 `hold_roll_deg`（默认 -45°），不在模型里。
#     · 手腕在眼前约 0.42 m（SHOULDER_OFFSET + WRIST_OFFSET），
#       刀身是「一条伸出去的手臂的延长」，不是从脸上长出来的。
## 刀根在手腕空间的 z。§7 明文保住它 = −0.11（grip_offset = 0 时 reach 不变）。
const BLADE_ROOT_Z := -0.110
## 柄舌**藏进木头**里的深度（米，§7.1.3）。结构量、看不见 → 按 §7 不给滑条，写死。
## 它只保证「尖锥确实插进去了」这条叙事成立。
const TANG_INSERT := 0.050
## 露柄舌/柄颈的直径（米，§7.1.3）：比木柄细、比筷子粗的一条金属腰。
const NECK_DIA := 0.024
## 柄尾加粗段的长度（米，§7.2.5）：木柄最后 1.5 cm 略粗。
const BUTT_LEN := 0.015
## §7.5 低模配色（albedo / roughness / metallic）。木柄是介电质 → metallic 0。
const WOOD_COLOR := Color(0.24, 0.175, 0.13)      # 暖中褐（旧木/见油）
const NECK_COLOR := Color(0.33, 0.32, 0.31)       # 暗磨钢（比刀身略亮）
const WOOD_DARK_COLOR := Color(0.18, 0.13, 0.10)  # 更深的老木（柄尾加粗段）
## 「肩膀」相对摄像机（Head）的偏移。
## 第一人称看不见身体，所以它只是一个**不可见的旋转中心** ——
## 但挥砍必须绕它转，理由见 _build_weapon() 里那段注释。
const SHOULDER_OFFSET := Vector3(0.17, -0.38, 0.02)
## 「手腕」相对肩膀的偏移。手臂长度 = 它的模长 ≈ 0.46 m。
const WRIST_OFFSET := Vector3(0.10, 0.10, -0.44)

var _player: PlayerController
var _weapon: MeleeWeapon
## 刀身（轮廓挤出网格）。尺寸的唯一来源 —— 模型和碰撞箱都从它量。
var _knife: KnifeMesh
## 刀柄四件（Neck / Handle / Butt）。位置 / 尺寸全部由 _rebuild_handle() 算。
var _neck: MeshInstance3D
var _handle: MeshInstance3D
var _butt: MeshInstance3D
## 手柄装配是否就绪。@export 的 setter 会在**属性初始化阶段**就被调用，
## 那时这些节点还不存在 —— 拿它当把手（与 KnifeMesh._built 同一套路）。
var _weapon_ready := false
## BladeMid / ShapeCast 的位置要跟着刀身中点走，所以把引用留下。
var _blade_mid: Marker3D
var _shape_node: ShapeCast3D
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

	# ── 刀柄（§7 无护手版）：刀身 → Neck（金属柄舌）→ Handle（木圆棒）
	#    → [可选] Butt（柄尾加粗段）────────────────────────────────
	# 位置与尺寸**全部由 _rebuild_handle() 算**，这里只建节点。
	# 四根柄滑条（柄长 / 柄径 / 握持点 / 露柄舌，§7.4）+ 一根可选柄尾加粗，
	# 改动时都会重走 _rebuild_handle()。
	# 三个都是圆柱 —— 档案原文「木柄呈圓形短棒」，柄舌是它里面露出来的金属芯。
	_neck = _make_cyl_node("Neck", NECK_COLOR, 0.55, 0.15)
	pivot.add_child(_neck)
	_handle = _make_cyl_node("Handle", WOOD_COLOR, 0.85, 0.0)
	pivot.add_child(_handle)
	# 柄尾加粗段（可选，默认关）。§7.2.5：它取代旧的金属配重块（那是剑的柄首，删）。
	# ⚠️ 开了之后它必须钉在**柄尾**上：柄变长，它跟着走（见 _rebuild_handle）。
	_butt = _make_cyl_node("Butt", WOOD_DARK_COLOR, 0.90, 0.0)
	_butt.visible = false
	pivot.add_child(_butt)

	# ── 刀身：二维轮廓挤出的网格（scripts/knife_mesh.gd）────────────────
	# 它不再是「一块按长宽高缩放的盒子」—— 那个东西在第一人称下永远是一块铁板。
	# 现在它由一条侧影轮廓挤出：平直的刀背、鼓起的刃口、收尖的刀尖，
	# 再加上一条凸出的刀背脊和一条亮刃口，全都在这个节点内部生成。
	#
	# 它的四个 @export（长 / 宽 / 刀脊厚 / 刃口厚）会出现在调参面板里，
	# 拖任意一根都会重建网格、并重新把尺寸注入武器（见 _sync_blade_geometry）。
	# 形状本身（收尖 / 弧腹 / 不平行长边）来自美术规格 knife-profile-spec.md。
	_knife = KnifeMesh.new()
	_knife.name = "Blade"
	# 刀根位置不再写死 —— 它 = 柄前端，由 _rebuild_handle() 按 grip_offset 设。
	# 刀尖恒在节点的 -Z 轴上（局部 z = 0 处是刀根）。
	pivot.add_child(_knife)
	# 轮廓一变，就把「模型 → 碰撞箱」那条链重新走一遍。
	_knife.profile_changed.connect(_sync_blade_geometry)

	# 刀身中点。扫掠检测以它为参照 —— 它比刀尖更代表「刀在哪」。
	# 位置不写死：由 _sync_blade_geometry() 跟着刀身中点走。
	_blade_mid = Marker3D.new()
	_blade_mid.name = "BladeMid"
	pivot.add_child(_blade_mid)

	# 命中形状的载体。它挂在 Pivot 下、绕 X 转 -90°，
	# 于是它自身的 Y 轴正好指向刀尖方向 —— **朝向自动跟随挥砍，不用手写**。
	# 形状本身（胶囊）由 MeleeWeapon._rebuild_shape() 按 blade_length 生成。
	_shape_node = ShapeCast3D.new()
	_shape_node.name = "ShapeCast3D"
	_shape_node.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_shape_node.target_position = Vector3.ZERO
	pivot.add_child(_shape_node)

	# 手柄装配就绪 —— 现在 @export 的 setter 才能真正干活。
	_weapon_ready = true
	# 按当前参数把柄舌 / 木柄 / 柄尾 / 刀根一次性摆到位（内含一次 _sync_blade_geometry）。
	_rebuild_handle()

	# 把刀身的真实尺寸交给武器 —— 这是「碰撞箱 = 模型的函数」的那一次传递。
	# 长度直接量 KnifeMesh 的网格包围盒，中点从节点位置推出，全是**模型自己**的数。
	# 必须在 add_child 之前设，因为 weapon._ready() 里会立刻按它生成形状。
	_sync_blade_geometry()

	head.add_child(_weapon)


## 把刀身的真实尺寸从网格读出来，注入武器，并让 BladeMid / ShapeCast 跟上。
##
## 这是「碰撞箱 = 模型的函数」这句话的**唯一执行点**。只要轮廓变了，
## KnifeMesh.profile_changed 就会触发它 —— 模型和判定永远一起变，
## 上一版「视觉改了、命中形状没改」的事故在这里被结构性排除。
func _sync_blade_geometry() -> void:
	if _knife == null:
		return
	var length := _knife.blade_length()        # ← 直接量网格包围盒，不读任何常量
	var center_z := _knife.blade_center_z()
	if _blade_mid != null:
		_blade_mid.position = Vector3(0.0, 0.0, center_z)
	if _shape_node != null:
		_shape_node.position = Vector3(0.0, 0.0, center_z)
	if _weapon != null:
		# blade_length 的 setter 会立刻重建命中胶囊（见 weapon.gd）。
		_weapon.blade_length = length
		_weapon.blade_center = absf(center_z)


## 柄上的一个圆柱件（轴对齐 Z，与刀身同轴）。
## ⚠️ §7.2.4 那条最容易漏的旋转：Godot 的 CylinderMesh 轴向是 +Y，
##    本刀的轴是 Z —— 必须绕 X 转 90°，否则柄会**竖着穿过刀身**。
func _make_cyl_node(node_name: String, color: Color, roughness: float, metallic: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	mi.material_override = m
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	return mi


## 制一根柄用圆柱 mesh（八棱，§7.2.4：radial_segments = 8 够圆、又保留低模棱面）。
func _make_cyl_mesh(radius: float, height: float) -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 8      # 默认 64 会白烧 8 倍面（§7.2.4）
	cyl.rings = 1
	return cyl


## 按 handle_len / handle_dia / grip_offset / neck_len / butt_bulge 把柄四件与刀根摆到位。
##
## ── 坐标约定（Pivot 局部空间，−Z 朝前）──────────────────────────
##   手腕（Pivot 原点）＝ 手，永远在 z = 0（位置由 SHOULDER/WRIST_OFFSET 锁死）。
##   刀根 z0 = BLADE_ROOT_Z − grip_offset        ← 「握持点」= 整坨武器沿 Z 平移
##   柄舌 Neck：从 z0 向 +Z —— 露 neck_len，再藏 TANG_INSERT 进木头
##   木柄 Handle：前端接在露出的柄舌之后，长 handle_len
##   柄尾加粗 Butt：钉在木柄最后 1.5 cm（可选）
##
## ── 为什么「柄长」不改变刀的位置、而「握持点」会 ────────────────
##   柄长只往**身后**长（柄尾方向），前端钉在柄舌/刀根上 →
##   拖「柄长」纯粹改手柄外观（+ 柄尾加粗段跟着走），刀尖距眼、挥砍半径都不动。
##   真正会挪刀的是 grip_offset —— 它把**整坨**（刀身+柄舌+木柄+柄尾）沿 Z 平移，
##   于是刀尖距眼、绕肩半径一起变（§7.3.3 已说明这是物理事实、非 bug）。
##   两者刻意分开，玩家才不会「想调柄的长短、却顺手把战斗距离也改了」。
func _rebuild_handle() -> void:
	if not _weapon_ready:
		return
	var hl := maxf(0.05, handle_len)
	var hr := maxf(0.010, handle_dia * 0.5)
	var neck_l := maxf(0.0, neck_len)
	var z0 := BLADE_ROOT_Z - grip_offset        # 刀根在手腕空间的 z

	if _knife != null:
		# 刀根 = 柄舌起点 —— 刀身从这里向前生长（刀身几何一个顶点都没动）。
		_knife.position = Vector3(0.0, 0.0, z0)

	if _neck != null:
		# 柄舌：露 neck_l + 藏 TANG_INSERT（写死的结构量，看不见）。
		var neck_total := neck_l + TANG_INSERT
		_neck.mesh = _make_cyl_mesh(NECK_DIA * 0.5, neck_total)
		_neck.position = Vector3(0.0, 0.0, z0 + neck_total * 0.5)

	if _handle != null:
		_handle.mesh = _make_cyl_mesh(hr, hl)
		_handle.position = Vector3(0.0, 0.0, z0 + neck_l + hl * 0.5)

	if _butt != null:
		# 柄尾加粗段（可选，默认关）。加粗量 = butt_bulge（直径增量）。
		var bulge := maxf(0.0, butt_bulge)
		_butt.visible = bulge > 0.0001
		if _butt.visible:
			_butt.mesh = _make_cyl_mesh(hr + bulge * 0.5, BUTT_LEN)
			# 钉在柄尾：木柄后端最后 BUTT_LEN 那一段。
			_butt.position = Vector3(0.0, 0.0, z0 + neck_l + hl - BUTT_LEN * 0.5)

	# ⚠️ 刀根一动，「模型 → 碰撞箱」那条链要立刻重走一遍（否则又是「视觉改了、判定没改」）。
	_sync_blade_geometry()


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

	# 刀身轮廓。这四根滑条改刀身的**侧影与截面** —— 拖任意一根，网格立刻重建，
	# 尺寸随之重新注入武器（碰撞箱跟着一起变）。
	# 「像不像屠刀」的形状本身（收尖 / 弧腹 / 不平行长边）由美术规格的 14 个顶点
	# 决定，不再用滑条去捏 —— 见 documents/knife-profile-spec.md 与 knife_mesh.gd 的 SPEC_UV。
	if _knife != null:
		entries.append_array([
			{"label": "│ 刀身 长 m", "target": _knife, "prop": "blade_len", "min": 0.20, "max": 0.80, "step": 0.01},
			{"label": "│ 刀身 宽 m", "target": _knife, "prop": "blade_width", "min": 0.06, "max": 0.30, "step": 0.0001},
			{"label": "│ 刀脊 厚 m", "target": _knife, "prop": "thickness_spine", "min": 0.002, "max": 0.020, "step": 0.0001},
			{"label": "│ 刃口 厚 m", "target": _knife, "prop": "thickness_edge", "min": 0.0004, "max": 0.008, "step": 0.0001},
		])

	# 刀柄 / 握持（§7.4 的四根 + 一个可选的柄尾加粗）。
	# ⚠️ 「握持点前后」把**整坨武器**沿 Z 平移 → 刀尖距眼、挥砍绕肩半径一起变（预期，非 bug）；
	#    「柄长 / 柄径 / 露柄舌」只改柄外观，不动刀（见 _rebuild_handle 注释）。
	entries.append_array([
		{"label": "│ 柄长 m", "target": self, "prop": "handle_len", "min": 0.140, "max": 0.280, "step": 0.005},
		{"label": "│ 柄径 m", "target": self, "prop": "handle_dia", "min": 0.028, "max": 0.052, "step": 0.001},
		{"label": "│ 握持点前后 m", "target": self, "prop": "grip_offset", "min": -0.050, "max": 0.050, "step": 0.005},
		{"label": "│ 露柄舌长 m", "target": self, "prop": "neck_len", "min": 0.000, "max": 0.030, "step": 0.002},
		{"label": "│ 柄尾加粗 m", "target": self, "prop": "butt_bulge", "min": 0.000, "max": 0.020, "step": 0.002},
	])

	entries.append_array([
		{"label": "│ 靶子开关 0/1", "target": self, "prop": "dummy_switch", "min": 0.0, "max": 1.0, "step": 1.0},
		{"label": "│ 靶子自动复位 sec", "target": self, "prop": "dummy_auto_respawn", "min": 0.0, "max": 10.0, "step": 0.5},
	])

	# 音效音量（探索卡 §5 列的「音效音量」入口）。
	# target 是 autoload `Sfx` —— TuningStore 会把它归到 world 组，
	# 键名 master_db 在整棵树上唯一，不与刀身/柄/靶子撞名。
	# 没有音色文件时它是「静音也没关系」的状态，见 scripts/sfx.gd。
	entries.append_array([
		{"label": "│ 音效音量 dB", "target": Sfx, "prop": "master_db", "min": -40.0, "max": 6.0, "step": 1.0},
	])

	return entries


func _build_tuner() -> void:
	_tuner = TunerPanel.new()
	_tuner.name = "TunerPanel"
	add_child(_tuner)
	_tuner.setup(_tuning_entries, "挥击 0 · 命中 0   待机")
