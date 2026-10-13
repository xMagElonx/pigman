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
##
## ── 2026-10-14 修复：命中形状与刀身对不上 ────────────────────────
## 症状：看着砍到了，却经常判不到。
## 原因（自检实测）：原来是一个 **半径 0.42 的球、圆心走在刀身中点**。
##     视觉刀尖 1.235 m  →  检测最远 1.080 m  →  **尖端 15.5 cm 是断的**
##   而且反过来，球在横向足足有 ±0.42 m 宽 —— 比刀刃实际厚度（0.085 m）
##   胖了约 10 倍，所以同时存在「够不着」和「隔空砍中」两种错，方向相反。
## 修法：形状换成**沿刀身的胶囊**，长度直接取自 Blade 网格的 size。
##   从此「模型改了但碰撞箱没改」这件事在结构上不可能再发生 ——
##   因为碰撞箱是**从模型算出来的**，不是另写一份。
##
## 一句话记法：**碰撞箱不应该是一个数字，应该是模型的一个函数。**

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

@export_group("挥击形状")
## 一次挥击扫过的角度。90 以下像戳，150 以上像抡。
@export var swing_angle_deg := 110.0

## 挥击的**倾斜**（度）。**这一项决定「像不像一次真的挥砍」。**
##
##   0  = 纯横扫：刀在**一个水平面里**扫过去 —— 这就是改之前唯一的动作，
##        也就是你说的「只有左右砍」。
##   90 = 纯下劈：刀从上往下直落。
##   30 = 斜劈：从右上往左下 —— **屠刀真实的用法**，也是当前默认。
##
## 它为什么比「扫掠角」更值得动：
##   扫掠角决定「扫多远」，倾斜决定「往哪个平面扫」。
##   第一人称看不见自己的手，所以「刀在一个水平面上平移」这件事
##   读起来不像挥砍，更像画面里横着划过一根铁条。
##   一旦它有了下压分量，你的前庭才认得出那是一次「劈」。
##
## ⚠️ 0 和 180 都不动它 —— 那是两个极端，各自只在特定武器上成立。
##    屠刀是重工具，它只有一种挥法：抡起来砸下去。
@export var swing_tilt_deg := 30.0

## 刀刃的**容错半径**（米）。检测形状是沿刀身的胶囊，这就是它的半径。
##
## 它该有多大：屠刀实际厚 0.040 m（半厚 0.020），但判定是**一条沿刀身的胶囊**，
## 它量的是「差一点点擦到算不算中」，不是刀有多宽。
##   0.07  → 「差一点擦到也算中」，横向总宽 0.14 m。
##   0.02  → 只认真正的刀刃，手感很「硬」，容易擦身而过判不到。
##   0.20  → 隔空砍中，你会开始怀疑「我明明没碰到它」。
## ⚠️ 它同时是检测**长度**上多出来的那一点点（两端各加一个半径），
##    所以「臂展」这个读数永远 = 视觉刀尖 + 它。
## ⚠️ 屠刀刀身宽 0.165 m，比这个直径大 —— 也就是说**刀背那一侧会先于判定碰到**。
##    灰盒阶段无所谓；等 M4 断肢要分「刃砍 / 背砸」时，这里必须重做。
@export var blade_radius := 0.07:
	set(value):
		blade_radius = value
		_rebuild_shape()

## 刀身长度（米）。**不要手填** —— 由 main.gd 从刀身网格的包围盒读出来注入。
## 它存在的唯一理由是让「碰撞箱 = 模型的函数」这句话成立。
##
## 2026-10-14 夜：加了 setter —— 现在**改长度就立刻重建命中胶囊**。
## 以前它是个哑变量：改了长度，必须有人记得再调一次 _rebuild_shape()，
## 忘了就又是「视觉改了、判定没改」。绑死之后这件事不可能再发生。
var blade_length := 0.80:
	set(v):
		blade_length = v
		_rebuild_shape()
## 刀身中点距手腕的距离（米）。同上，由模型注入。
var blade_center := 0.485

@export_group("持刀姿态")
## ⭐ **这一组里只有一项必须懂：roll。** 另外两项是微调。
##
## ── 为什么刀刃朝下的时候，你反而看不见刀 ──────────────────────
## 一把刀可以看成一个薄片：长（刀身方向）× 高（刀面）× 厚。
## 屠刀的「刀面」有 20 多厘米高，但你**从上往下看刀背**的时候，
## 眼睛里剩下的是**厚度那 3 厘米**。
## 所以无论刀做得多宽、多重、多像屠刀 ——
## 只要它刀刃朝正下方、刀尖朝正前方，第一人称看到的永远是一根细铁条。
##
## **这不是建模没做好，这是视角问题。** 真人持刀时会把手腕翻过来，
## 让刀面朝向自己 —— 那个动作就是 roll。
##
## 拖到 0    → 刀面完全侧对镜头，你只能看见刀背的厚度（= 改之前的样子）
## 拖到 -45  → 刀面斜朝镜头（当前默认）。刀有多宽、刃口多亮，全看得见
## 拖到 -90  → 刀面完全正对镜头，像举着一面镜子
## 它是「这把刀长什么样」和「这把刀看起来像不像武器」之间的唯一开关。
@export var hold_roll_deg := -45.0:
	set(v):
		hold_roll_deg = v
		_apply_hold()

## 静止时刀尖抬起（正）/ 下压（负），单位度。微调项。
@export var hold_pitch_deg := 8.0:
	set(v):
		hold_pitch_deg = v
		_apply_hold()

## 静止时刀尖偏左（正）/ 偏右（负），单位度。微调项。
@export var hold_yaw_deg := 10.0:
	set(v):
		hold_yaw_deg = v
		_apply_hold()

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
## 「肩膀」。挥砍的旋转施加在它上面 —— 它不动位置，只转。
var _swing: Node3D
## 「手腕」。位置固定，只负责静止持刀姿态（刀面朝哪个方向）。
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
	_swing = get_node_or_null("Swing") as Node3D
	_pivot = get_node_or_null("Swing/Pivot") as Node3D
	_blade_mid = get_node_or_null("Swing/Pivot/BladeMid") as Marker3D
	_shapecast = get_node_or_null("Swing/Pivot/ShapeCast3D") as ShapeCast3D
	_apply_hold()
	_rebuild_shape()

	# 刀不能砍到自己：把第一个 CharacterBody3D 祖先排除掉。
	if _shapecast != null:
		var n: Node = self
		while n != null and not (n is CharacterBody3D):
			n = n.get_parent()
		if n != null:
			_shapecast.add_exception(n)


## 按当前 blade_length / blade_radius 重建检测形状。
## 谁改了刀刃尺寸都会调它 —— 滑条拖动时形状会立刻跟着变。
func _rebuild_shape() -> void:
	if _shapecast == null:
		return
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(0.005, blade_radius)
	# Godot 的 capsule height 是**总高**（含两端半球），
	# 所以要覆盖 blade_length 长的刀身、两端各留一个 radius 的容错：
	cap.height = maxf(blade_length, cap.radius * 2.0 + 0.001) + cap.radius * 2.0
	_shapecast.shape = cap


## 检测最远能到哪（距手腕，米）。视觉刀尖 + 一个容错半径。
## 自检和读数用它来核对「模型」和「碰撞箱」是否还对齐。
func reach() -> float:
	return blade_center + blade_length * 0.5 + blade_radius


## 视觉刀尖距手腕（米）。它必须永远等于 reach() − blade_radius。
func visual_tip() -> float:
	return blade_center + blade_length * 0.5


## 刀尖在**世界空间**的位置。
## 读数「刀尖距眼」和自检都用它 —— 之前的「臂展」是从手腕量的，
## 但手腕自己也会被挥砍带着跑（绕肩膀转），从手腕量会少算一截。
func tip_global_position() -> Vector3:
	if _pivot == null:
		return global_position
	return _pivot.global_transform * Vector3(0.0, 0.0, -visual_tip())


## 刀面法线与「手腕 → 目标」方向的夹角（度）。
##   0° = 刀面正对镜头，整片刀面都看得见
##  90° = 刀面完全侧对，眼睛里只剩刀背那几厘米厚度
##
## 自检用它把一个肉眼问题变成数字：**这片刀面到底看不看得见。**
## 「武器看起来不像屠刀」这件事，量出来的根因就是这个角。
func blade_face_angle_to_deg(target_global: Vector3) -> float:
	if _pivot == null:
		return 180.0
	var n := _pivot.global_transform.basis.x.normalized()
	var d := (target_global - _pivot.global_position)
	if d.length() < 0.0001:
		return 0.0
	d = d.normalized()
	# 刀有两个面，取朝向目标的那一个。
	return rad_to_deg(minf(acos(clampf(n.dot(d), -1.0, 1.0)),
		acos(clampf(-n.dot(d), -1.0, 1.0))))


func _physics_process(delta: float) -> void:
	if _swing == null:
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
				# 破空声落点：WINDUP → ACTIVE，与「命中窗口」同一时刻。
				# 这一步之后才可能命中，于是命中时是 whoosh + hit **两层叠在一起**。
				_play_swing_sound()
		Phase.ACTIVE:
			if _t >= active:
				_phase = Phase.RECOVERY
				_t = 0.0
		Phase.RECOVERY:
			if _t >= recovery:
				_phase = Phase.IDLE
				_t = 0.0


func _apply_pose() -> void:
	_swing.rotation = _swing_pose()


## 静止持刀姿态。只写一次，挥砍不会动它。
## 它和挥击是**两个节点**上的两件事 ——
##   Pivot（手腕）＝ 刀怎么拿      Swing（肩膀）＝ 刀怎么挥
## 混在一起写，你就会在调姿态时把动作一起改掉。
func _apply_hold() -> void:
	if _pivot != null:
		_pivot.rotation_degrees = Vector3(hold_pitch_deg, hold_yaw_deg, hold_roll_deg)


## 挥击的姿态 —— 返回 (pitch, yaw, roll)，作用在肩膀节点上。
##
## 用「归一化进度 s ∈ [-1, +1]」统一描述整个动作，三段自动衔接：
##   s = -1 → 抬到右上（举起）
##   s =  0 → 正前方（落点）
##   s = +1 → 压到左下（收势）
##
## 两个分量分别跟 s 走：
##   yaw   = s × 半个扫掠角   → 横向扫过多远
##   pitch = -s × 倾斜角      → 纵向劈下多少（**这就是「像不像劈砍」的那一项**）
##
## 为什么 pitch 要跟着 s 一起走，而不是单独做一段抬手动画：
##   因为**一次挥砍只有一个动作**。抬手和劈下是同一个弧的两端，
##   分成两段写，中间一定会在某一帧对不上，看起来就是「抖了一下」。
func _swing_pose() -> Vector3:
	var half := deg_to_rad(swing_angle_deg) * 0.5
	var tilt := deg_to_rad(swing_tilt_deg)
	match _phase:
		Phase.WINDUP:
			# 抬手：刀尖往右上走。用缓出 —— 起步快、到位慢，像真的在蓄力。
			var k := _ease_out(clampf(_t / maxf(windup, 0.001), 0.0, 1.0))
			return Vector3(tilt * k, -half * k, 0.0)
		Phase.ACTIVE:
			# 挥出：**匀速**扫过。匀速才看得出「有效窗口」在哪 ——
			# 一旦这里做缓动，命中窗口就变成了一个不可预期的时刻。
			var s := lerpf(-1.0, 1.0, clampf(_t / maxf(active, 0.001), 0.0, 1.0))
			return Vector3(-tilt * s, half * s, 0.0)
		Phase.RECOVERY:
			# 收刀：从落点回到持刀姿态。
			var k := 1.0 - _ease_out(clampf(_t / maxf(recovery, 0.001), 0.0, 1.0))
			return Vector3(-tilt * k, half * k, 0.0)
	return Vector3.ZERO


func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 2.0)


# --- 命中检测 ---------------------------------------------------------------

func _detect(delta: float) -> void:
	if _blade_mid == null or _shapecast == null or _shapecast.shape == null:
		return

	var mid := _blade_mid.global_position
	if not _has_prev:
		_prev_mid = mid
		_has_prev = true
		return

	# 从「上一帧刀身中点」扫到「这一帧刀身中点」——
	# 这样高速挥砍也不会穿过一个薄目标（隧道效应）。
	#
	# ⚠️ 2026-10-14 修正：这里曾经是
	#     _shapecast.global_transform = Transform3D(Basis(), _prev_mid)
	#     _shapecast.target_position = seg
	#   那样写会把形状的旋转重置成 identity。以前形状是**球**，球没有朝向，
	#   所以看不出问题；换成沿刀身的胶囊之后，那样写会让胶囊**永远竖着**，
	#   等于又错一次。正确做法是：**不动节点**（它挂在 Pivot 下，朝向自动跟随刀身），
	#   只把世界位移转进节点自己的局部空间 —— 因为 target_position 是局部坐标。
	var seg := mid - _prev_mid
	_shapecast.target_position = _shapecast.global_transform.basis.inverse() * (-seg)
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


## 声音钩子 —— **接线已由 AI 做好，你只需要把音色文件放进 `assets/audio/`**。
##
## 这两个函数就是「哪一刻响」的全部。文件名见 assets/audio/README.md。
## 没有文件时会静默跳过（不崩、不报错），所以现在直接跑也没问题 ——
## 「先接线、后录音」是安全的。
##
## 落点说明：本函数在 `_advance()` 的 **WINDUP → ACTIVE** 转换处被调用，
## 也就是「挥出去、开始能打中」的那一帧 —— 不是抬手的瞬间。
##
## 挥空那一下：短、亮、**不要低频**。
func _play_swing_sound() -> void:
	Sfx.play(&"sfx_swing_whoosh")


## 切中那一下：骤停、暗、**要有低频冲击**。
##
## ⚠️ M2 的验收「闭眼也能分辨切中与挥空」**全部押在两条音色的对比上**：
##     挥空 = 只有 whoosh（一层风）
##     命中 = whoosh + 本音（两层：风 + 撞）
##   所以 whoosh 每次必须完全一致（不许随机音高），否则叠层就分辨不出来。
func _play_hit_sound() -> void:
	Sfx.play(&"sfx_swing_hit")


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
