class_name Graybox
extends RefCounted
## 灰盒房间生成器。
##
## 全部由最简单的方块构成，一处美术都没有 —— 这是刻意的。
## M0/M1 只回答一个问题：移动这件事，能不能被看见、被感受到。
##
## 房间参数由 main.gd 通过 @export 传进来，可以在 Inspector 里直接改。
## 所有几何体都带碰撞；地面条纹和墙上刻度只是视觉参照，不带碰撞。
##
## ── 两把尺子（2026-10-14）────────────────────────────────────────
##   地面刻度线：**水平尺**，每 2 米一道 —— 量你「走多远」。
##   墙上高度刻度：**垂直尺**，每 0.5 米一道 —— 量你「跳多高」。
## 两把尺子是同一条理由：把不可见的量变成可读的参照。
## 没有尺子，拖滑条就只是盲调 —— 你分不清「我改了」和「我以为我改了」。

const FLOOR_COLOR := Color(0.34, 0.34, 0.36)
const STRIPE_COLOR := Color(0.50, 0.50, 0.53)
const WALL_COLOR := Color(0.25, 0.25, 0.27)
const FRAME_COLOR := Color(0.78, 0.42, 0.30)
const WALL_THICKNESS := 0.25


static func build(
	parent: Node3D,
	room_size: Vector3,
	with_ceiling: bool,
	stripes: bool,
	door_width: float,
	door_height: float,
	height_marks: bool = true
) -> void:
	var half := room_size * 0.5
	var t := WALL_THICKNESS

	# 地面：顶面正好在 y = 0，玩家原点即脚底
	_box(parent, "Floor", Vector3(room_size.x, t, room_size.z), Vector3(0, -t * 0.5, 0), FLOOR_COLOR)

	if with_ceiling:
		_box(parent, "Ceiling", Vector3(room_size.x, t, room_size.z), Vector3(0, room_size.y + t * 0.5, 0), WALL_COLOR)

	# 南 / 西 / 东三面实墙
	_box(parent, "Wall_S", Vector3(room_size.x, room_size.y, t), Vector3(0, half.y, half.z + t * 0.5), WALL_COLOR)
	_box(parent, "Wall_W", Vector3(t, room_size.y, room_size.z), Vector3(-half.x - t * 0.5, half.y, 0), WALL_COLOR)
	_box(parent, "Wall_E", Vector3(t, room_size.y, room_size.z), Vector3(half.x + t * 0.5, half.y, 0), WALL_COLOR)

	# 北墙：中间留门洞 —— 左右两段 + 上方门楣
	var dw: float = clampf(door_width, 0.6, room_size.x - 0.6)
	var dh: float = clampf(door_height, 0.6, room_size.y - 0.1)
	var seg: float = (room_size.x - dw) * 0.5
	var z_n: float = -half.z - t * 0.5
	_box(parent, "Wall_N_L", Vector3(seg, room_size.y, t), Vector3(-(dw * 0.5 + seg * 0.5), half.y, z_n), WALL_COLOR)
	_box(parent, "Wall_N_R", Vector3(seg, room_size.y, t), Vector3(dw * 0.5 + seg * 0.5, half.y, z_n), WALL_COLOR)
	_box(parent, "Wall_N_Lintel", Vector3(dw, room_size.y - dh, t), Vector3(0, dh + (room_size.y - dh) * 0.5, z_n), WALL_COLOR)

	# 门框标记：让「可行动方向」一眼可辨（计划书 4.1 的要求）
	_decal(parent, "DoorPost_L", Vector3(0.06, dh, 0.06), Vector3(-dw * 0.5, dh * 0.5, z_n + t * 0.5 + 0.04), FRAME_COLOR)
	_decal(parent, "DoorPost_R", Vector3(0.06, dh, 0.06), Vector3(dw * 0.5, dh * 0.5, z_n + t * 0.5 + 0.04), FRAME_COLOR)

	# 地面刻度：每 2 米一道。这是灰盒里最容易被忽略、却最该先做的东西 ——
	# 没有它，你根本判断不出「我把 acceleration 调大了」到底有没有生效。
	if stripes:
		var step := 2.0
		var count := int(room_size.z / step)
		for i in range(count):
			var z: float = -half.z + step * (float(i) + 0.5)
			var col: Color = STRIPE_COLOR if i % 2 == 0 else FLOOR_COLOR.darkened(0.2)
			_decal(parent, "Stripe_%d" % i, Vector3(room_size.x, 0.015, 0.10), Vector3(0, 0.008, z), col)

	if height_marks:
		_height_marks(parent, room_size)


# --- 高度刻度（垂直尺）-------------------------------------------------------
#
# 地面刻度线量的是「你走多远」，它量不了「你跳多高」。
# 而跳跃一打开，后者立刻是第一个要判断的问题 ——
# 没有一根垂直的参照，拖 jump_velocity 仍然是在盲调。
#
# 1.0 m 那条用门框的橙色：因为「跳不跳得过一米」是这里唯一的关键判断，
# 它该在一眼之间被读出来，而不是靠数刻度。
static func _height_marks(parent: Node3D, room_size: Vector3) -> void:
	var half := room_size * 0.5
	var length: float = minf(room_size.z - 0.6, 6.0)
	for h in [0.5, 1.0, 1.5, 2.0]:
		var hf: float = h
		if hf > room_size.y - 0.12:
			continue
		var major: bool = is_equal_approx(hf, 1.0)
		var col: Color = FRAME_COLOR if major else STRIPE_COLOR
		var thick: float = 0.09 if major else 0.06
		for sx in [-1.0, 1.0]:
			_decal(
				parent,
				"HMark_%s_%d" % ["W" if sx < 0.0 else "E", int(hf * 10.0)],
				Vector3(0.02, thick, length),
				Vector3(sx * (half.x - 0.02), hf, 0.0),
				col
			)


# --- 内部工具：带碰撞的方块 -------------------------------------------------

static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	parent.add_child(body)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _material(color)
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


# --- 内部工具：无碰撞的贴面（只为了看得见）----------------------------------

static func _decal(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.position = pos
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _material(color)
	parent.add_child(mesh)


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.metallic = 0.0
	return m
