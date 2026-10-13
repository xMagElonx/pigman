class_name KnifeMesh
extends MeshInstance3D
## 屠刀的刀身：把一条**二维轮廓**挤出成三维薄片，取代原来的矩形盒（BoxMesh）。
##
## ⚠️ 轮廓顶点来自美术规格，不是我另设计的：
##    documents/knife-profile-spec.md（art-director / PIGMAN-ART-001）
##    第 2 节的 14 个归一化顶点 + 第 3 节的楔形厚度方案 + 第 4 节的三个材质。
##    改轮廓 = 改那份规格，然后同步这里的 SPEC_UV。**不要在这里手改形状。**
##
## ── 为什么要换掉 BoxMesh ──────────────────────────────────────────
## 一块 BoxMesh 只有四个矩形面，屏幕上永远是矩形 —— 怎么调三边都是矩形。
## 「屠刀」的识别信号根本不在长宽高里，而在**侧影**里：收尖的刀尖（F1）、
## 外凸的弧腹（F2）、不平行的一对长边（F3）、厚背薄刃的楔形截面（F4）、
## 沿刃口的一条亮斜面（F5）。这五条只有画成一条轮廓线才存在。
##
## ── 技术路线：为什么是 SurfaceTool，不是 CSGPolygon3D / 拼方块 ─────
##   ① CSGPolygon3D：现成的「折线 + 挤出」，代码最少。但它的法线由 CSG 布尔
##      求值决定，薄片上容易出脏法线（刀身会「糊」）；几何还是运行期求值的。
##   ② 多个 BoxMesh 拼装：方块感正是要消灭的东西，且拼不出连续弧腹。
##   ③ SurfaceTool / ArrayMesh：逐顶点自己给法线，平面着色完全可控；
##      凹多边形交给 Geometry2D 三角化；厚度 = 每个轮廓点各自的半厚。
##      → **选它。** 本刀全场只有一把、是低模，性能不是约束，**法线正确性才是**。
##
## ── 和命中碰撞箱的关系（本项目踩过的最大一个坑）──────────────────
## 上一版死在「视觉改了、命中形状没改」（球覆盖不到刀尖，还横向胖 10 倍）。
## 所以这里立规矩：**刀身的尺寸只从这块网格来，没有任何一个数字是另写的。**
## main.gd 用 blade_length()（直接量网格包围盒）和 blade_center_z() 取值，
## 再注入 MeleeWeapon。拖面板上任何一根刀身滑条，模型和判定一起变。
##
## ── 坐标约定 ──────────────────────────────────────────────────
## Godot 里 -Z 是前方。本节点挂在「手腕」Pivot 下、自身不旋转；
## 网格局部坐标：y = u × 宽、z = −长 × v、x = ±半厚(u)（见规格 §2.1）。
## 于是刀根（v=0）在局部 z=0，刀尖（v=1、u=0）恒在节点的 -Z 轴上（y=0）——
## 这保证「网格刀尖」和 MeleeWeapon.tip_global_position() 是**同一个点**。

## 轮廓参数变了就发一次。main.gd 收到后重新把尺寸注入武器。
signal profile_changed

@export_group("刀身（尺寸 = 模型与碰撞箱的共同来源）")
## 刀身总长（米）。改它，命中胶囊跟着一起变长。
@export var blade_len := 0.40:
	set(v):
		blade_len = maxf(0.06, v)
		_rebuild()
## 最大宽度（米）：刀背到弧腹最深处的竖直距离（规格建议 0.148）。
@export var blade_width := 0.148:
	set(v):
		blade_width = maxf(0.03, v)
		_rebuild()
## 刀脊厚度（米）：截面上最厚处。规格 0.005 = 砍骨刀的厚背。
@export var thickness_spine := 0.005:
	set(v):
		thickness_spine = maxf(0.001, v)
		_rebuild()
## 刃口厚度（米）：截面最薄处。规格 0.0015 = 视觉上的锋利。
@export var thickness_edge := 0.0015:
	set(v):
		thickness_edge = maxf(0.0002, v)
		_rebuild()

# ── 轮廓顶点表（规格 §2.2）。Vector2(u, v)：u = 宽度方向（−0.5 刃 / +0.5 背），
#    v = 长度方向（0 刀根 / 1 刀尖）。顺序：刀根·背 → 沿背到刀尖 → 沿刃回刀根。
#    ⚠️ 这 14 个点就是规格里的 V1…V14，**不要在这里改形状**。
const SPEC_UV: Array = [
	Vector2(0.42, 0.00),   # V1  刀根·背角
	Vector2(0.50, 0.06),   # V2  刀背
	Vector2(0.50, 0.34),   # V3  刀背（近直段）
	Vector2(0.48, 0.55),   # V4  刀背（开始下沉）
	Vector2(0.41, 0.72),   # V5  刀背（收尖斜面）
	Vector2(0.16, 0.89),   # V6  刀背（收尖）
	Vector2(0.00, 1.00),   # V7  刀尖
	Vector2(-0.16, 0.89),  # V8  刃口（收尖）
	Vector2(-0.33, 0.77),  # V9  刃口（弧腹上行）
	Vector2(-0.45, 0.61),  # V10 刃口（弧腹）
	Vector2(-0.50, 0.43),  # V11 刃口最深点 / 弧腹顶点
	Vector2(-0.50, 0.25),  # V12 刃口
	Vector2(-0.45, 0.10),  # V13 刃口（向刀根回收）
	Vector2(-0.32, 0.00),  # V14 刀根·刃角
]

# ── 端盖内边界（规格 §5.1 分面修正）。同样是归一化 (u, v)。
#    由 art-director 在**米制空间**沿轮廓法向内缩得到（脊带 13 mm、刃带 9 mm），
#    再换算回归一化 —— 所以这里直接当 (u, v) 用，映射方式与 SPEC_UV 完全一致。
#    用途：把端盖显式切成「脊带 / 刃带 / 主体」三块，各块单独三角化，
#    这样刀面上才会出现**连续的**暗脊带与亮刃带（否则 F5 失效，见 _build_geometry）。
const SPINE_INNER_UV: Array = [   # 对应 V1…V5，向 −u 内缩 13 mm
	Vector2(0.3412, 0.0144),
	Vector2(0.4125, 0.0628),
	Vector2(0.4122, 0.3395),
	Vector2(0.3925, 0.5472),
	Vector2(0.3232, 0.7151),
]
const EDGE_INNER_UV: Array = [    # 对应 V8…V14，向 +u 内缩 9 mm
	Vector2(-0.1061, 0.8796),
	Vector2(-0.2732, 0.7619),
	Vector2(-0.3902, 0.6059),
	Vector2(-0.4393, 0.4288),
	Vector2(-0.4393, 0.2513),
	Vector2(-0.3912, 0.1058),
	Vector2(-0.2652, 0.0098),
]

# ── 三个材质（规格 §4）。三档明度彻底拉开，近距才分得出哪边是刃。
#    ⚠️ 这里只管 albedo（灰盒 / 成品两档都不变）；metallic 分灰盒/成品两档，
#       见 _rebuild() 里 mats 上方的「回成品档的路」注释。
const BODY_COLOR := Color(0.30, 0.29, 0.28)   # 脏暖灰：钝钢 + 陈年污
const SPINE_COLOR := Color(0.15, 0.12, 0.11)  # 暗锈褐：最暗，重背感
const EDGE_COLOR := Color(0.76, 0.77, 0.78)   # 亮磨钢：最亮，一条亮线

# surface 索引（提交顺序必须与 MATERIALS 一致）
const SURF_BODY := 0
const SURF_SPINE := 1
const SURF_EDGE := 2

# 只有进树之后才建网格。
# 原因：@export 的 setter 会在**属性初始化阶段**就被调用，那时其它成员未必就位，
# 拿半成品参数建网格会得到一堆 NaN。所以拿一个开关把手，_ready() 里才开。
var _built := false


func _ready() -> void:
	_built = true
	_rebuild()


# --- 对外接口：尺寸的唯一出口 -------------------------------------------------

## 刀身长度（米）—— **直接量网格包围盒**，不是另存的一份数字。
func blade_length() -> float:
	if mesh == null:
		return blade_len
	return mesh.get_aabb().size.z


## 刀身中点相对手腕（Pivot）的 z 偏移（负值 = 朝前）。
func blade_center_z() -> float:
	return position.z - blade_length() * 0.5


## 刀尖在本节点局部空间的位置。它恒在刀身轴线（y = 0）上。
func tip_local_position() -> Vector3:
	return Vector3(0.0, 0.0, -blade_length())


## 轮廓顶点数（自检用）。
func outline_vertex_count() -> int:
	return SPEC_UV.size()


# --- 生成 -------------------------------------------------------------------

func _rebuild() -> void:
	if not _built:
		return

	var out := ArrayMesh.new()
	var sts: Array[SurfaceTool] = []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)

	_build_geometry(sts)

	# 提交顺序 = surface 顺序（body / spine / edge），必须和下面的材质表对齐。
	for st in sts:
		st.commit(out)

	# 🎚️ 灰盒档 metallic（规格 §4.1 左列）。顺序 = surface 顺序 = body / spine / edge。
	#
	# ⚠️ 回成品档的路（有天空盒 / 反射探针的环境下用右列，2026-10-14 team-lead 拍板）：
	#      刃口 surf2 → metallic 0.90   （§4 原始值，靠反射把「最亮的边」拉出来）
	#      刀身 surf0 → metallic 0.40   （§4 原始值）
	#      刀脊 surf1 → metallic 0.10   （本就是 0.10，灰盒 / 成品两档都一样）
	#   为什么灰盒要压低：**高 metalness 不发亮，只反射**。灰盒环境无天空、无反射探针
	#   （Environment 走 BG_COLOR + AMBIENT_SOURCE_COLOR）+ 一盏平行光 —— metallic 越高
	#   越没东西可反射、越显黑，刃口 0.90 反而可能比刀身还暗，F5「最亮的一条边」直接不成立。
	#   所以灰盒把三者都压到 ≈0.10–0.15，让明暗**全部由 albedo 决定**（0.30/0.15/0.76 三档已经拉开）。
	#   这是**环境适配**，不是美术偏好：回成品环境时把上面三个数改回右列即可，albedo 一律不动。
	#   本阶段**明确不加 emission**（美术要求先调对比度；发光只在最后手段、且极轻 0.10–0.15，
	#   否则刃口会像一条「荧光条」，和超现实恐怖的克制基调打架）。
	var mats := [
		_mat(BODY_COLOR, 0.60, 0.15),
		_mat(SPINE_COLOR, 0.90, 0.10),
		_mat(EDGE_COLOR, 0.22, 0.15),
	]
	for i in mini(mats.size(), out.get_surface_count()):
		out.surface_set_material(i, mats[i])

	mesh = out
	profile_changed.emit()


## 每个轮廓点的半厚度（米）——楔形截面（规格 §3）：
##   刀脊带  u ≥ +0.35        → 最厚（= thickness_spine）
##   主体段  −0.28 ≤ u < 0.35 → 略薄（0.9 × 脊厚）
##   刃口斜面 u < −0.28       → 从主体厚线性薄到 thickness_edge
## 它让「厚背薄刃」成为一条看得见的斜面（F4），而不是一块等厚板。
func _half_thickness(u: float) -> float:
	var body := thickness_spine * 0.9
	if u >= 0.35:
		return thickness_spine * 0.5
	if u >= -0.28:
		return body * 0.5
	var t := clampf((-0.28 - u) / 0.22, 0.0, 1.0)
	return lerpf(body, thickness_edge, t) * 0.5


## 生成轮廓顶点（已换算到局部坐标）。
## 每项：{ u: 归一化宽度, pos: Vector2(z, y), half: 半厚度 }
func _vertices() -> Array:
	var verts: Array = []
	for uv in SPEC_UV:
		var u: float = uv.x
		var v: float = uv.y
		verts.append({
			"u": u,
			# 局部坐标：z = −长 × v（刀根在 0），y = u × 宽。见规格 §2.1。
			"pos": Vector2(-blade_len * v, u * blade_width),
			"half": _half_thickness(u),
		})
	return verts


func _build_geometry(sts: Array) -> void:
	var verts := _vertices()
	var n := verts.size()

	# 多边形重心（2D），用来判断侧壁法线该朝里还是朝外。
	var centroid := Vector2.ZERO
	for i in n:
		centroid += verts[i]["pos"]
	centroid /= float(n)

	# ── 端盖：按规格 §5.1「显式切成三块，各自单独三角化」──
	# ⚠️ 不能「先切整个 14 边形、再按三角面重心 u 分类」：耳切出来的三角又大又随机，
	#    重心基本不落在 u 带上，结果刀面上并没有一条沿刀背的暗带、也没有沿刃口的亮带，
	#    只有弧腹上一块亮补丁 → F5（亮刃线）失效，轮廓白做。
	#    显式分块后，每一块自己是一个**简单多边形**，可安全耳切；三块并集 = 原轮廓
	#    （面积残差 0），带边界共享同一组点 → 无缝无裂。
	_add_cap_region(sts, _region_spine(), SURF_SPINE)
	_add_cap_region(sts, _region_edge(), SURF_EDGE)
	_add_cap_region(sts, _region_body(), SURF_BODY)

	# ── 侧壁：按轮廓段分类（V1→V7 脊 / V7→V14 刃 / V14→V1 主体），与端盖分区无关。
	# 规格 §5.3：V1→V7 的侧壁 = 刀背（暗），V7→V14 = 刃口（亮），V14→V1 = 主体。
	# 用端点原始编号判定，与绕序无关。
	for a in n:
		var b := (a + 1) % n
		var hi := maxi(a, b)
		var lo := mini(a, b)
		var surf := SURF_BODY
		if hi <= 6:
			surf = SURF_SPINE          # 段落在 V1..V7 内 = 刀背
		elif lo >= 6:
			surf = SURF_EDGE           # 段落在 V7..V14 内 = 刃口
		var st: SurfaceTool = sts[surf]
		var va: Dictionary = verts[a]
		var vb: Dictionary = verts[b]
		var ref := _wall_ref(va["pos"], vb["pos"], centroid)
		var af := _v3(va, true)
		var bf := _v3(vb, true)
		var ab := _v3(va, false)
		var bb := _v3(vb, false)
		_tri_geo(st, af, bf, bb, ref)
		_tri_geo(st, af, bb, ab, ref)


# --- 端盖三块（规格 §5.1）-----------------------------------------------------
# 每块边界共享同一组点（V 点或内边界点），所以三块拼起来无缝、无裂、面积残差 0。

## 刀脊带：外缘 V1..V5、内缘 spine_inner（反向）。
func _region_spine() -> Array:
	var r: Array = []
	for i in range(0, 5):
		r.append(SPEC_UV[i])
	for i in range(SPINE_INNER_UV.size() - 1, -1, -1):
		r.append(SPINE_INNER_UV[i])
	return r


## 刃口带：外缘 V8..V14、内缘 edge_inner（反向）。
## ⚠️ 从 V8 起（不是 V7）：用 V7 会让内边界穿过刀尖、使主体自交；
##    从 V8 起，刃带在刀尖前几毫米自然收口，肉眼等效。
func _region_edge() -> Array:
	var r: Array = []
	for i in range(7, 14):
		r.append(SPEC_UV[i])
	for i in range(EDGE_INNER_UV.size() - 1, -1, -1):
		r.append(EDGE_INNER_UV[i])
	return r


## 主体：edge_inner（正序）+ V14 + V1 + spine_inner（正序）+ V5、V6、V7、V8。
func _region_body() -> Array:
	var r: Array = []
	r.append_array(EDGE_INNER_UV)
	r.append(SPEC_UV[13])          # V14
	r.append(SPEC_UV[0])           # V1
	r.append_array(SPINE_INNER_UV)
	r.append(SPEC_UV[4])           # V5
	r.append(SPEC_UV[5])           # V6
	r.append(SPEC_UV[6])           # V7
	r.append(SPEC_UV[7])           # V8
	return r


## 把一块端盖（归一化 (u,v) 点列）三角化，前/后两面写进指定 surface。
func _add_cap_region(sts: Array, region: Array, surf: int) -> void:
	if region.size() < 3:
		return
	var poly := PackedVector2Array()
	for p in region:
		# 与 SPEC_UV 用同一套映射：z = −长 × v，y = u × 宽。
		poly.append(Vector2(-blade_len * p.y, p.x * blade_width))
	var uv: Array = region.duplicate()

	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		var rp := PackedVector2Array()
		var ru: Array = []
		for i in range(region.size() - 1, -1, -1):
			rp.append(poly[i])
			ru.append(uv[i])
		tri = Geometry2D.triangulate_polygon(rp)
		if tri.is_empty():
			push_warning("KnifeMesh：端盖分区三角化失败")
			return
		poly = rp
		uv = ru

	var st: SurfaceTool = sts[surf]
	for t in range(0, tri.size(), 3):
		var a: Vector2 = uv[tri[t]]
		var b: Vector2 = uv[tri[t + 1]]
		var c: Vector2 = uv[tri[t + 2]]
		var pa: Vector2 = poly[tri[t]]
		var pb: Vector2 = poly[tri[t + 1]]
		var pc: Vector2 = poly[tri[t + 2]]
		# 前盖朝 +x，后盖朝 −x；端盖每个点的 x = ±half_thickness(u)。
		_tri_geo(st, _cap_v3(a, pa, true), _cap_v3(b, pb, true), _cap_v3(c, pc, true), Vector3.RIGHT)
		_tri_geo(st, _cap_v3(a, pa, false), _cap_v3(b, pb, false), _cap_v3(c, pc, false), Vector3.LEFT)


## 端盖顶点：uv = 归一化 (u, v)，p2 = (z, y)。x = ±half_thickness(u)。
func _cap_v3(uv: Vector2, p2: Vector2, front: bool) -> Vector3:
	var h := _half_thickness(uv.x)
	return Vector3(h if front else -h, p2.y, p2.x)


## 二维轮廓点 (z, y) → 三维点 (x, y, z)。
func _v3(v: Dictionary, front: bool) -> Vector3:
	var p: Vector2 = v["pos"]
	var h: float = v["half"]
	return Vector3(h if front else -h, p.y, p.x)


## 侧壁的**参考外法线**：在 YZ 平面内、垂直于该边、背离多边形重心。
func _wall_ref(pa: Vector2, pb: Vector2, centroid: Vector2) -> Vector3:
	var d := pb - pa                       # (dz, dy)
	var nrm := Vector3(0.0, d.x, -d.y)     # 三维里垂直于该边的候选法线
	if nrm.length_squared() < 1e-16:
		return Vector3.ZERO
	nrm = nrm.normalized()
	var mid := (pa + pb) * 0.5 - centroid  # 2D：重心 → 边的中点
	var outward := Vector3(0.0, mid.y, mid.x)
	if nrm.dot(outward) < 0.0:
		nrm = -nrm
	return nrm


## 加一个三角形：法线取**几何法线**（这样楔形斜面上也是对的），
## 再用参考方向纠正朝向，最后保证绕序与法线一致（否则背面剔除会挖出破洞）。
func _tri_geo(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ref: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-18:
		return
	n = n.normalized()
	if ref != Vector3.ZERO and n.dot(ref) < 0.0:
		n = -n
	_tri(st, a, b, c, n)


## 保证三角形绕序与给定法线一致（Godot 背面剔除看的是绕序，不是法线属性）。
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m
