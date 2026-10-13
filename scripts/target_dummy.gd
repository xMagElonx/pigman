class_name TargetDummy
extends StaticBody3D
## 练习靶子。
##
## 注意它叫什么：**靶子**，不是敌人。
## 它没有 AI、不会移动、不会攻击、不会躲闪 —— 这是刻意的，不是还没做完。
##
## 理由：你现在要回答的问题只有一个 ——「砍起来爽不爽」。
## 这个问题的变量只有三个：
##   ① 我的挥击窗口对不对（命中检测）
##   ② 反馈够不够（顿帧 / 屏震 / 声音）
##   ③ 目标有没有反应（受击）
## 一个会移动、会反击、会绕后的目标，会往这三个变量里塞进第四个（AI 行为）。
## 于是你测出「不爽」的时候，分不清是哪一个坏了。
##
## 它给玩家三样东西：
##   1. 一个可失去的对象 —— 没有它，那几个移动滑条没有被验证的资格
##   2. 一把尺子 —— 两个靶子在不同距离，测「起步 + 冲刺 + 刹车」这一串
##   3. M3 敌人的底座 —— 敌人将来就在这个文件上长出状态机
##
## 它做的唯一一件事：被打，然后有反应。
##
## ── 2026-10-13 修复 ──────────────────────────────────────────────
## 修一：倒地后**关闭碰撞**。原来只让视觉倒下、碰撞胶囊还立着，
##       于是「尸体会挡路」—— 你看不见它，但会被它撞停。
## 修二：新增**自动复位**。练习靶本来就该自己站起来；
##       不然杀掉它之后，你就少了一个可测的对象。

signal hit_received(point: Vector3, dir: Vector3, speed: float, hp_left: int)

@export_group("抵抗")
## 挨几下倒地。设大一点方便你反复测同一件事。
@export var max_hp := 6

@export_group("复位")
## 倒地后几秒自动站起来。0 = 不自动（手动按 R）。
## ⚠️ M3 的真敌人请设为 0 —— 敌人不该复活。
@export var auto_respawn_delay := 2.5

@export_group("受击反应")
## 后仰角度（度）。这是「打击感」里最便宜也最有效的一半 —— 目标动了，你的力才存在。
@export var tilt_deg := 13.0
## 后仰用多久（秒）
@export var tilt_time := 0.10
## 回正用多久（秒）
@export var recover_time := 0.40

const BODY_COLOR := Color(0.60, 0.30, 0.33)
const HEAD_COLOR := Color(0.74, 0.44, 0.46)
const SNOUT_COLOR := Color(0.86, 0.70, 0.68)
const LIMB_COLOR := Color(0.44, 0.37, 0.40)
const FLASH_COLOR := Color(1.0, 0.86, 0.76)

var hp := 0
var down := false

var _pivot: Node3D
var _col: CollisionShape3D
var _mats: Array[StandardMaterial3D] = []
var _tilt_axis := Vector3.RIGHT
var _tilt_amount := 0.0
var _tween: Tween
var _flash_tween: Tween
var _down_timer := 0.0
var _active := true


func _ready() -> void:
	_build()
	respawn()


func _process(delta: float) -> void:
	if not down:
		return
	if auto_respawn_delay <= 0.0:
		return
	_down_timer += delta
	if _down_timer >= auto_respawn_delay:
		respawn()


# --- 组装 -------------------------------------------------------------------

func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	# 朝向标记：+Z 是正面。灰盒阶段你需要一眼看出它面对哪边。
	_part("Torso", Vector3(0.66, 1.02, 0.46), Vector3(0.0, 1.02, 0.0), BODY_COLOR)
	_part("Shoulders", Vector3(1.06, 0.30, 0.44), Vector3(0.0, 1.46, 0.0), BODY_COLOR.darkened(0.10))
	_part("Head", Vector3(0.44, 0.44, 0.46), Vector3(0.0, 1.79, 0.0), HEAD_COLOR)
	_part("Snout", Vector3(0.22, 0.16, 0.16), Vector3(0.0, 1.74, 0.29), SNOUT_COLOR)
	_part("Arm_L", Vector3(0.20, 0.72, 0.20), Vector3(-0.60, 1.10, 0.0), LIMB_COLOR)
	_part("Arm_R", Vector3(0.20, 0.72, 0.20), Vector3(0.60, 1.10, 0.0), LIMB_COLOR)
	_part("Leg_L", Vector3(0.22, 0.55, 0.22), Vector3(-0.19, 0.27, 0.0), LIMB_COLOR)
	_part("Leg_R", Vector3(0.22, 0.55, 0.22), Vector3(0.19, 0.27, 0.0), LIMB_COLOR)

	# 一整根胶囊当碰撞体 —— 刀的扫掠只要碰到这一个形状就够。
	# 分部位碰撞是 M4 断肢的事，现在做了只会让你分不清「没打中」和「打中了别的部位」。
	# 注意：它挂在**自己**身上而不是 Pivot 上，所以视觉倒地时它不会跟着倒 ——
	# 这正是「倒地要手动关掉它」的原因。
	_col = CollisionShape3D.new()
	_col.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.0
	_col.shape = cap
	_col.position = Vector3(0.0, 1.0, 0.0)
	add_child(_col)


func _part(node_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm

	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	m.metallic = 0.0
	# 受击闪白：自发光预先开着、能量为 0，受击时只推能量，不重建材质。
	m.emission_enabled = true
	m.emission = FLASH_COLOR
	m.emission_energy_multiplier = 0.0
	mesh.material_override = m

	mesh.position = pos
	_pivot.add_child(mesh)
	_mats.append(m)


# --- 受击 -------------------------------------------------------------------

## 武器命中时调用的唯一入口。
## 参数是一个字典，因为它的字段会随里程碑增加（M4 会加 part_name、impulse）。
func take_hit(info: Dictionary) -> void:
	if down or hp <= 0:
		return

	hp = maxi(0, hp - 1)

	var point: Vector3 = info.get("point", global_position)
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var speed: float = info.get("speed", 0.0)

	_flash()
	_knock(dir, speed)
	hit_received.emit(point, dir, speed, hp)

	if hp <= 0:
		_fall()


func _knock(dir: Vector3, speed: float) -> void:
	var h := Vector3(dir.x, 0.0, dir.z)
	if h.length_squared() < 0.0001:
		h = Vector3(0.0, 0.0, 1.0)
	h = h.normalized()

	# 绕「上 × 受击方向」转 —— 得到的就是「往受击方向倒」。
	_tilt_axis = Vector3.UP.cross(h)
	if _tilt_axis.length_squared() < 0.0001:
		_tilt_axis = Vector3.RIGHT
	_tilt_axis = _tilt_axis.normalized()

	# 打得越快倒得越狠 —— 这一条是「力度可读」的来源，不要省。
	var strength := clampf(speed / 14.0, 0.45, 1.7)
	var target := deg_to_rad(tilt_deg) * strength

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_tilt, _tilt_amount, target, tilt_time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(_set_tilt, target, 0.0, recover_time) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _set_tilt(v: float) -> void:
	_tilt_amount = v
	if _pivot != null:
		_pivot.basis = Basis(_tilt_axis, v)


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	for m in _mats:
		m.emission_energy_multiplier = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash_energy, 1.0, 0.0, 0.16)


func _set_flash_energy(v: float) -> void:
	for m in _mats:
		m.emission_energy_multiplier = v


func _fall() -> void:
	down = true
	_down_timer = 0.0
	# 关键：碰撞要跟着一起关。只让视觉倒下，会留下一根看不见的柱子把你撞停。
	if _col != null:
		_col.disabled = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_method(_set_tilt, _tilt_amount, deg_to_rad(86.0), 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_pivot, "position:y", -0.42, 0.35)
	_tween.chain().tween_callback(_clear_tween_ref)


func _clear_tween_ref() -> void:
	_tween = null


# --- 复位 -------------------------------------------------------------------

## 站起来。按 R 会立刻调用它；auto_respawn_delay > 0 时也会被自动调用。
func respawn() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	down = false
	_down_timer = 0.0
	hp = max_hp
	_tilt_amount = 0.0
	if _pivot != null:
		_pivot.basis = Basis()
		_pivot.position = Vector3.ZERO
	if _col != null:
		_col.disabled = not _active
	for m in _mats:
		m.emission_energy_multiplier = 0.0


## 面板上的「靶子开关」用这个：隐藏时连碰撞一起关掉。
## 只设 visible 是不够的 —— 你会撞上一个看不见的墙，那比不做开关更糟。
func set_active(v: bool) -> void:
	_active = v
	visible = v
	if _col != null:
		_col.disabled = (not v) or down


## 给面板读数用的倒计时。
func down_timer() -> float:
	return _down_timer
