class_name MeleeWeapon
extends Node3D
## 第一人称近战的第一版。
##
## 它刻意只做四件事：
##   ① 三段计时 —— 前摇 windup / 有效窗口 active / 后摇 recovery
##      挥击不是「一直开着」的，它是一个有开始和结束的事件。
##   ② 有效窗口内沿刀身做扫掠 —— 用 ShapeCast3D，不是 Area3D
##   ③ 同一次挥击对同一目标只结算一次 —— 靠一次一清的命中集合
##   ④ 命中反馈：顿帧 + 屏震
##
## 它刻意不做：伤害数值、连招、动画、敌人反应、断肢。
## 那些是 M3 / M4 的事。现在多写一行，你就多一个「坏了也分不清是哪坏的」变量。
##
## 关于声音：这里留了两个空函数（_play_swing_sound / _play_hit_sound）。
## 它们是空的，不是我忘了 —— 声音是《猪人》的签名，属于作者性，不该由 AI 塞占位素材。
## 但这意味着 M2 那条「闭眼也能分辨切中与挥空」的验收，在你填进自己的声音之前，
## 只能靠顿帧和屏震裸考 —— 大概率过不了。这是设计，不是缺陷。

signal hit_landed(target: Object, point: Vector3, speed: float)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

@export_group("节奏（挥击的三段计时）")
## 前摇：抬手到起刀之间。它决定敌人有没有时间「看见」你要砍。
## 0 = 没有预警，指哪砍哪；0.25 以上 = 一个笨重的身体。
@export var windup := 0.12
## 有效窗口：只有这段时间里刀才「是刀」。窗口越短，越需要预判，越难砍中。
@export var active := 0.10
## 后摇：收刀。这段时间你不能再次挥击 —— 它是「挥空有代价」的唯一来源。
@export var recovery := 0.30

@export_group("形状")
## 一次挥击扫过的角度。90 以下像戳，150 以上像抡。
@export var swing_angle_deg := 110.0
## 扫掠用的球半径（米）。它相当于「刀的厚度 + 容错」。
## 太小 → 明明看着砍到了却没算中；太大 → 隔空砍中。
@export var hit_radius := 0.42

@export_group("反馈")
## 顿帧时长（秒）。命中瞬间世界几乎停住 —— 这是最重要的一味料。
@export var hitstop := 0.06
## 屏震强度（米）。0.02 已经能感觉到，0.1 会晕。
@export var shake_strength := 0.045
@export var shake_time := 0.16

@export_group("开关")
@export var enable := true

# 给验收用的计数：挥击多少次、命中多少次。
# 「一次挥击打了五下」这个 bug 会在这里现形 —— 不用靠眼睛。
var swing_count := 0
var hit_count := 0

var _phase: Phase = Phase.IDLE
var _t := 0.0
var _pivot: Node3D
var _blade_mid: Marker3D
var _shapecast: ShapeCast3D
var _camera: Camera3D
var _hit_this_swing := {}
var _prev_mid := Vector3.ZERO
var _has_prev := false
var _shake_left := 0.0
var _hitstop_busy := false


func _ready() -> void:
	_pivot = get_node_or_null("Pivot")
	_blade_mid = get_node_or_null("Pivot/BladeMid") as Marker3D
	_shapecast = get_node_or_null("Pivot/ShapeCast3D") as ShapeCast3D

	# 刀不能砍到自己：把第一个 CharacterBody3D 祖先排除掉。
	if _shapecast != null:
		var n: Node = self
		while n != null and not (n is CharacterBody3D):
			n = n.get_parent()
		if n != null:
			_shapecast.add_exception(n)


func _physics_process(delta: float) -> void:
	if _pivot == null:
		return

	if enable and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_action_just_pressed("attack"):
		start_swing()

	_advance(delta)
	_apply_pose()
	_update_shake(delta)
	if _phase == Phase.ACTIVE:
		_detect(delta)


# --- 三段计时 ---------------------------------------------------------------

func start_swing() -> void:
	if _phase != Phase.IDLE:
		return
	_phase = Phase.WINDUP
	_t = 0.0
	swing_count += 1


func _advance(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_t += delta
	match _phase:
		Phase.WINDUP:
			if _t >= windup:
				_phase = Phase.ACTIVE
				_t = 0.0
				# 一次挥击开始时清空 —— 这一行就是「不会多帧重复结算」的全部实现。
				_hit_this_swing.clear()
				_has_prev = false
		Phase.ACTIVE:
			if _t >= active:
				_phase = Phase.RECOVERY
				_t = 0.0
		Phase.RECOVERY:
			if _t >= recovery:
				_phase = Phase.IDLE
				_t = 0.0


func _apply_pose() -> void:
	_pivot.rotation.y = _swing_angle()


func _swing_angle() -> float:
	var half := deg_to_rad(swing_angle_deg) * 0.5
	match _phase:
		Phase.WINDUP:
			var p := clampf(_t / maxf(windup, 0.001), 0.0, 1.0)
			return lerpf(0.0, -half, _ease_out(p))     # 往右后抬
		Phase.ACTIVE:
			var p := clampf(_t / maxf(active, 0.001), 0.0, 1.0)
			return lerpf(-half, half, p)               # 匀速扫过去 —— 匀速才看得出窗口
		Phase.RECOVERY:
			var p := clampf(_t / maxf(recovery, 0.001), 0.0, 1.0)
			return lerpf(half, 0.0, _ease_out(p))      # 收刀
	return 0.0


func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 2.0)


# --- 命中检测 ---------------------------------------------------------------

func _detect(delta: float) -> void:
	if _blade_mid == null or _shapecast == null:
		return

	var mid := _blade_mid.global_position
	if not _has_prev:
		_prev_mid = mid
		_has_prev = true
		return

	# 从「上一帧刀身中点」扫到「这一帧刀身中点」——
	# 这样高速挥砍也不会穿过一个薄目标（隧道效应）。
	var seg := mid - _prev_mid
	_shapecast.global_transform = Transform3D(Basis(), _prev_mid)
	_shapecast.target_position = seg
	_shapecast.force_shapecast_update()

	var count := _shapecast.get_collision_count()
	for i in range(count):
		var c: Object = _shapecast.get_collider(i)
		if c == null or not c.has_method("take_hit"):
			continue
		var id := c.get_instance_id()
		if _hit_this_swing.has(id):
			continue
		_hit_this_swing[id] = true

		var point := _shapecast.get_collision_point(i)
		var speed := seg.length() / maxf(delta, 0.0001)
		hit_count += 1
		c.call("take_hit", {"point": point, "dir": seg.normalized(), "speed": speed})
		hit_landed.emit(c, point, speed)
		_on_hit()

	_prev_mid = mid


func _on_hit() -> void:
	_shake_left = shake_time
	_play_hit_sound()
	_start_hitstop()


# --- 反馈 -------------------------------------------------------------------

func _start_hitstop() -> void:
	if _hitstop_busy or hitstop <= 0.0:
		return
	_hitstop_busy = true
	Engine.time_scale = 0.06
	# 第四个参数 = 忽略 time_scale，否则这个计时器会把自己冻住。
	await get_tree().create_timer(hitstop, true, false, true).timeout
	if not is_instance_valid(self):
		return
	Engine.time_scale = 1.0
	_hitstop_busy = false


func _update_shake(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var k := _shake_left / maxf(shake_time, 0.0001)
		_camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) \
			* shake_strength * k
	elif _camera.position != Vector3.ZERO:
		_camera.position = Vector3.ZERO


## 声音钩子 —— 归你填。挥空那一下。
func _play_swing_sound() -> void:
	pass


## 声音钩子 —— 归你填。切中那一下。
## 「闭眼也能分辨切中与挥空」这条验收，全部押在这个函数上。
func _play_hit_sound() -> void:
	pass


# --- 读数 -------------------------------------------------------------------

func phase_name() -> String:
	match _phase:
		Phase.WINDUP:
			return "前摇"
		Phase.ACTIVE:
			return "命中窗口"
		Phase.RECOVERY:
			return "后摇"
	return "待机"


func stats() -> String:
	return "挥击 %d · 命中 %d" % [swing_count, hit_count]
