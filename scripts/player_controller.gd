class_name PlayerController
extends CharacterBody3D
## 第一人称移动控制器。
##
## M1 阶段它只有一个使命：让移动「不别扭」。
## 下面每一个参数都会自动出现在 Tab 调参面板里 ——
## 手感是调出来的，不是写出来的。不要在代码里猜数字。
##
## 关于角色原点：本节点位于「脚底」，碰撞胶囊向上撑起身高。
## 所以 player.position.y = 0 就等于站在地面上。
##
## ── 三个方向参数的分工（2026-10-12 拆分，2026-10-13 补第三项）────
## 速度快慢  = acceleration / deceleration
## 方向快慢  = steer_rate_deg
## 转向代价  = turn_speed_keep      ← 2026-10-13 新增，默认 1.0（= 关闭）
##
## 为什么要分三个：第 1 条「按下立刻动」要 acceleration 大，
## 第 3 条「急转被甩出去」要 acceleration 小 —— 同一个参数方向相反。
## 拆开之后它们才不打架。

@export_group("速度")
## 慢走速度（米/秒）。先把这个调顺，再去动冲刺。
@export var walk_speed := 4.0
## 冲刺速度。计划书 2.2 要求「高响应」，所以它应该明显更快。
@export var sprint_speed := 8.5
## 加速速率。越大越「硬」，越小越「滑」。它只管「起步多快」。
@export var acceleration := 45.0
## 松手后的减速速率。它比 acceleration 小，你就会有惯性。
@export var deceleration := 28.0

@export_group("转向")
## 转身速率（度 / 秒）。它只管「方向转得多快」，和 acceleration 是两件事。
## 调大 = 指哪转哪（无惯性）；调小 = 转身要画个弧（有惯性）。
##
## ⚠️ 它决定了「转身漂移」有多大，而且漂移量 ∝ 速度：
##   转弯半径 R = 速度 ÷ (steer_rate 转成弧度/秒)
##   横向漂移 = R × (1 - cos 转角)
##   实测（冲刺 8.5 m/s、原地转 90°）：
##     4000 → 约 0.11 m   基本等于指哪打哪
##     2400 → 约 0.20 m   当前默认 ← 手感上已经等于「指哪走哪」
##     1500 → 约 0.30 m   有一点重量
##      720 → 约 0.61 m   明显能感觉到「被甩」（原来就是这个值）
##      300 → 约 1.8 m    几乎像在冰上
##
## 为什么默认从 720 改成 2400：本项目已定下的规则是
## **M1–M3 身体必须「听话」（白板基线，指哪打哪），M4 之后才引入别扭**。
## 720 会让冲刺转身横滑 0.6 米 —— 那是 M4「移植后身体不听话」要做的事，
## 不是基线该有的。想现在就尝那个手感？把滑条拖回 720 以下即可。
@export var steer_rate_deg := 2400.0

## 转向时的速度保留比例。1.0 = 转身不掉速（原来的行为）。
##
## 为什么要这个：原地转身时速度方向和朝向会分开，但速度**不减**，
## 所以那不是「有重量」，是「磁悬浮侧滑」——它读起来像故障，不像惯性。
## 把它拖到 0.5 附近，急转就会明显掉速，你才第一次感觉到身体有质量。
##
## 默认留 1.0（不改变你现有手感）—— 要不要开，由你在滑条上决定。
@export var turn_speed_keep := 1.0

@export_group("视角")
## 鼠标灵敏度。等价于计划书里写的 turn_response。
@export var mouse_sensitivity := 0.0022
## 抬头 / 低头的角度上限（度）。
@export var pitch_limit_deg := 89.0

@export_group("身体")
## 摄像机高度（眼睛高度）。运行时拖动会立刻生效。
@export var eye_height := 1.65:
	set(value):
		eye_height = value
		if _head != null:
			_head.position.y = value
## 重力。灰盒阶段由你手填，方便先调下落手感。
@export var gravity := 24.0
## 跳跃初速度。默认 0 = 不能跳。
## 计划书里没有跳跃 —— 先确认地面移动本身成立，再决定要不要给它。
@export var jump_velocity := 0.0

var _head: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_head = get_node_or_null("Head")
	if _head != null:
		_camera = _head.get_node_or_null("Camera3D")
		_head.position.y = eye_height
	_yaw = rotation.y
	# 这里刻意不设鼠标模式：初始状态由 main.gd 决定（先让调参面板可用），
	# 玩家点一下画面才锁定鼠标。


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = mouse_sensitivity
		_yaw -= event.relative.x * sens
		var limit: float = deg_to_rad(pitch_limit_deg)
		_pitch = clampf(_pitch - event.relative.y * sens, -limit, limit)
		rotation.y = _yaw
		if _head != null:
			_head.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if is_on_floor() and jump_velocity > 0.0 and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	# 输入：x = 左右，y = 前后（前进为 -1）
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Godot 里 -Z 是前方，所以前进方向是 -basis.z
	var b := global_transform.basis
	var wish := b.x * input.x + b.z * input.y
	var has_input := wish.length_squared() > 0.0001

	var speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if has_input:
		# 方向与大小分开算，这样「起步快」和「转身慢」就不打架。
		var wanted_dir := wish.normalized()
		# 已经在动时，朝向取「当前速度方向」；从静止起步时才直接用输入方向。
		var dir := horizontal.normalized() if horizontal.length() > 0.05 else wanted_dir
		var max_turn := deg_to_rad(steer_rate_deg) * delta
		var angle := dir.signed_angle_to(wanted_dir, Vector3.UP)
		dir = dir.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))

		# 转向的代价：转角越大，**目标**速度越低。
		#
		# 注意是改目标值，不是直接把当前速度乘一个系数 ——
		# 转 90° 要花 8 帧，而那 8 帧里 angle 一直很大，
		# 每帧乘一次就是复利，速度会崩到接近 0（那不叫掉速，叫刹车）。
		# 改成目标值之后它是稳定的：转身期间稳定在 speed × turn_speed_keep。
		var target_speed := speed
		if turn_speed_keep < 0.999:
			var turn_ratio := clampf(absf(angle) / (PI * 0.5), 0.0, 1.0)
			target_speed = lerpf(speed, speed * turn_speed_keep, turn_ratio)
		var cur := move_toward(horizontal.length(), target_speed, acceleration * delta)
		horizontal = dir * cur
	else:
		# 松手：方向不再改变（这是惯性的来源之一），只让速度衰减。
		horizontal = horizontal.move_toward(Vector3.ZERO, deceleration * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()


## 给调参面板用的实时读数。
func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 「速度方向」和「朝向」差了多少度。
##
## 这是本次修复的核心 —— 它是那个「莫名其妙的左右位移」的度量。
##   0°  = 身体听话，指哪走哪。
##   90° = 你转了，身体还在往原来的方向滑 —— 漂移正在发生。
##
## 为什么需要它：第一人称看不见自己的身体，所以「方向滞后」这件事
## 完全不可见，只能靠感觉 —— 而感觉只会告诉你「有点怪」。
## 有了这个数字，漂移就从「莫名其妙」变成「我知道它在发生」。
## M4 移植之后要判断「身体是不是开始不听话了」，也全靠它。
func steer_offset_deg() -> float:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length() < 0.05:
		return 0.0
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.001:
		return 0.0
	return rad_to_deg(h.normalized().angle_to(f.normalized()))
