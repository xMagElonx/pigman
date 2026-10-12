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

@export_group("速度")
## 慢走速度（米/秒）。先把这个调顺，再去动冲刺。
@export var walk_speed := 4.0
## 冲刺速度。计划书 2.2 要求「高响应」，所以它应该明显更快。
@export var sprint_speed := 8.5
## 加速速率。越大越「硬」，越小越「滑」。
@export var acceleration := 45.0
## 松手后的减速速率。它比 acceleration 小，你就会有惯性。
@export var deceleration := 28.0

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

	var speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = acceleration if wish.length_squared() > 0.0001 else deceleration
	horizontal = horizontal.move_toward(wish * speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()


## 给调参面板用的实时读数。
func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
