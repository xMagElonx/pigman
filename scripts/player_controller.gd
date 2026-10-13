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
##     2400 → 约 0.13 m   当前默认 ← 手感上已经等于「指哪走哪」
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
## ⚠️ 它和 steer_rate 耦合：2400 时转身 3 帧就转完了，它几乎没有发挥空间。
##    想试它的效果，先把 steer_rate 拖到 400 附近。
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

## 跳跃初速度（米/秒）。**默认 7.0 —— 跳高约 1.02 m。按空格。**
##
## ── 它为什么曾经是 0（2026-10-14 上午）────────────────────────
##   当时的理由是「跳跃是手感三变量之外的第四个变量」。
## ── 那个理由是错的（2026-10-14 晚，由用户实测推翻）──────────
##   挥砍的三个变量（挥击窗口 / 反馈 / 目标反应）**全是战斗变量**。
##   跳跃是**移动变量** —— 它和 walk_speed、steer_rate 才是一类东西，
##   属于 M1 的地盘。移动和战斗不竞争，所以「第四个变量」这个顾虑不成立。
##   用户的实测反应：「一点进去就想跳」。
##   → 那不是「跳跃很爽」的证据，是**对空间操控权的第一反应**。
##     一个人进到一个新空间，第一件事是测试「这里能被怎么玩」。
##   → 但它是真的需求，所以默认开。
##
## ── 它立刻会撞上的那个冲突（这才是要你去测的东西）────────────
##   刀的水平基准高度 ≈ 1.43 m（眼高 1.65 − 手腕相对下移 0.22）。
##   靶子全高 2.00 m。
##   跳高 1.02 m 时，刀的基准高度升到 ≈ 2.45 m
##   → **高出靶子头顶 0.45 m。**
##   也就是说：跳起来**平视**挥刀会砍空，必须**低头**才砍得到。
##   这不是 bug，这是「跳跃 × 近战」的第一个真实交点 —— 也是你下一件要判断的事。
##
## 换算：跳跃高度 ≈ v² / (2 × gravity)
##   gravity = 24 时：v=5 → 0.52 m   v=7 → 1.02 m   v=9 → 1.69 m
##   面板读数显示理论高度；落地后还会附上**实测最高点**（那个才是真的发生的）。
##
## ⚠️ 2026-10-14 之前，它绑的是 Godot 内置的 ui_accept，
##    而屏幕上从来没有写过「按什么键跳」—— 于是拖了滑条也看不出反应。
##    现在它是一个独立动作 jump（空格），并且写进了屏幕提示和面板标签。
@export var jump_velocity := 7.0

var _head: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _pitch := 0.0

# 腾空高度采样（2026-10-14 新增）。给「我到底跳了多高」一个实测数字。
var _airborne := false
var _air_origin_y := 0.0
var _air_peak := 0.0
var _last_jump_peak := 0.0


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

	if is_on_floor() and jump_velocity > 0.0 and Input.is_action_just_pressed("jump"):
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

	# 腾空高度采样：记录「离开地面到重新落地」这段时间里的最高点。
	# 落地那一刻冻结成 _last_jump_peak —— 理论值是 v²/2g，这个才是真的发生的。
	#
	# ⚠️ 基准 y 必须**站在地面上时**就持续刷新。
	#    第一版写成「离地那一刻才记基准」，结果基准取到了起跳后的第一帧 ——
	#    那时玩家已经上升了约 0.11 m（v=6.7、1/60 秒），于是实测值
	#    系统性地少报整整一帧的上升量（0.88 而不是 0.99）。
	#    这类错误不报错、不崩溃，只是数字一直偏一点 —— 最难发现的那种。
	if is_on_floor():
		_air_origin_y = global_position.y
		if _airborne:
			_last_jump_peak = _air_peak
			_airborne = false
	else:
		if not _airborne:
			_airborne = true
			_air_peak = 0.0
		_air_peak = maxf(_air_peak, global_position.y - _air_origin_y)


## 当前 jump_velocity 对应的理论跳跃高度（米）。给面板读数用的 ——
## 拖滑条时能立刻看见「这个数字意味着跳多高」，不用自己算 v²/2g。
func jump_height() -> float:
	if jump_velocity <= 0.0:
		return 0.0
	return jump_velocity * jump_velocity / (2.0 * maxf(gravity, 0.001))


## 上一次跳跃的**实测**最高点（米，相对起飞点）。落地那一刻冻结。
## 它是 jump_height() 的对照面：公式算出来的和真的跳出来的，
## 差多少就是这一帧这一步的手感真相。
func last_jump_peak() -> float:
	return _last_jump_peak


## 给调参面板用的实时读数。
func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 「速度方向」和「朝向」差了多少度。
##
## 这是转身漂移修复的核心 —— 它是那个「莫名其妙的左右位移」的度量。
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
