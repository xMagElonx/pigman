extends Node
## 常驻自检门（P0-3）—— 跑完**不删**，进仓库，跟着 Git 走。
##
## ── 为什么需要它 ────────────────────────────────────────────────
## 以前的自检脚本都是「跑完即删」。删掉之后，那些已经跑通的不变量
## （模型 = 碰撞箱、改轮廓判定跟着改、一次挥击只结算一次……）
## 就可以被后来的改动静默改坏 —— 不报错、不崩，只是悄悄不对了。
## 这个场景就是那张网：**改动之后跑一次，绿了再提交。**
##
## ── 怎么跑（不用开窗口）──────────────────────────────────────────
##   godot --headless --path . res://checks/selfcheck.tscn
##   退出码：全过 = 0，有 FAIL = 1（将来接 CI 也认这个）。
##
## ── 两条纪律 ────────────────────────────────────────────────────
## ① **基准固定**：进场先 `apply_defaults`，一律按代码默认值测，
##    不看你的 user://tuning.cfg —— 否则「同一把刀换个姿态能差 7cm」，
##    数字无法跨轮比较（这是本项目踩过的坑）。
## ② **只读不写**：本脚本不 save 任何存档。
##
## ⚠️ 它只验「机器能验的」。打击感 / 视觉 / 听觉仍然只能由人开窗口验，
##    见 documents/knife-visual-check.svg 与 knife-handle-check.svg。
##
## ── 加一条断言 ──────────────────────────────────────────────────
##   在 _run() 里加一个 `await _check_xxx(main)`，函数内用 `_ok(名字, 条件, 读数)` 记录。

const MAIN_SCENE := "res://scenes/main.tscn"
const TOL := 0.001

var _fails := 0
var _total := 0


func _ready() -> void:
	await _run()
	print("")
	if _fails == 0:
		print("=== 自检门：全部通过（%d 项）===" % _total)
	else:
		print("=== 自检门：%d / %d 项失败 ===" % [_fails, _total])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	print("=== 自检门 selfcheck（P0-3）· Godot %s ===" % Engine.get_version_info().string)

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ok("装载 main.tscn", false, "load 失败")
		return
	var main: Node = packed.instantiate()
	add_child(main)
	await _frames(6)

	# ① 基准固定：一律按代码默认值测（不写盘）。
	var n: int = TuningStore.apply_defaults(main._tuning_entries)
	print("（基准：已恢复代码默认值 %d 项；本脚本只读不写存档）" % n)
	await _frames(3)

	await _check_model_is_hitbox(main)
	await _check_tip_matches_mesh(main)
	await _check_blade_length_follows(main)
	await _check_handle_axis(main)
	await _check_one_swing_one_hit(main)
	await _check_audio_wired(main)
	await _check_keys_unique(main)
	await _check_legacy_migration(main)


# --- 工具 -------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ok(item: String, cond: bool, detail: String = "") -> void:
	_total += 1
	var tail := ("  · " + detail) if detail != "" else ""
	if cond:
		print("  [PASS] %s%s" % [item, tail])
	else:
		_fails += 1
		print("  [FAIL] %s%s" % [item, tail])


# --- ① 模型 = 碰撞箱（本项目最值钱的那条链）---------------------------------

func _check_model_is_hitbox(main: Node) -> void:
	var kn = main._knife
	var w = main._weapon
	if kn == null or w == null:
		_ok("① 模型 = 碰撞箱", false, "取不到 _knife / _weapon")
		return

	var mesh_z: float = (kn.mesh as Mesh).get_aabb().size.z
	var gd_len: float = kn.blade_length()
	var injected: float = w.blade_length
	var cap_h: float = (w._shapecast.shape as CapsuleShape3D).height
	var expect_h: float = maxf(mesh_z, w.blade_radius * 2.0 + 0.001) + w.blade_radius * 2.0

	_ok("① KnifeMesh.blade_length() 就是网格包围盒",
		absf(gd_len - mesh_z) < TOL,
		"blade_length=%.6f   mesh.z=%.6f" % [gd_len, mesh_z])
	_ok("① 注入武器的长度 == 网格包围盒（碰撞箱 = 模型的函数）",
		absf(injected - mesh_z) < TOL,
		"weapon.blade_length=%.6f" % injected)
	_ok("① 命中胶囊按 blade_length 重建（不是留了个旧高度）",
		absf(cap_h - expect_h) < 0.01,
		"cap.height=%.6f   expect=%.6f" % [cap_h, expect_h])


# --- ② 刀尖读数真的落在网格刀尖上 ------------------------------------------

func _check_tip_matches_mesh(main: Node) -> void:
	var kn = main._knife
	var w = main._weapon
	if kn == null or w == null:
		_ok("② 刀尖读数 == 网格刀尖", false, "取不到 _knife / _weapon")
		return

	var tip_g: Vector3 = w.tip_global_position()
	var lt: Vector3 = kn.to_local(tip_g)
	var a: AABB = (kn.mesh as Mesh).get_aabb()
	var cx: float = a.position.x + a.size.x * 0.5
	var cy: float = a.position.y + a.size.y * 0.5

	var at_z_end: bool = absf(lt.z - a.position.z) < 0.01 or absf(lt.z - a.end.z) < 0.01
	var on_axis: bool = absf(lt.x - cx) < 0.01 and absf(lt.y - cy) < 0.01

	_ok("② 刀尖读数落在网格刀尖上（±1cm）",
		at_z_end and on_axis,
		"刀尖(网格局部)=(%.4f, %.4f, %.4f)  mesh z∈[%.4f, %.4f] 面心=(%.4f, %.4f)"
			% [lt.x, lt.y, lt.z, a.position.z, a.end.z, cx, cy])


# --- ③ 改刀身长 → 网格与胶囊一起跟随 ----------------------------------------

func _check_blade_length_follows(main: Node) -> void:
	var kn = main._knife
	var w = main._weapon
	if kn == null or w == null:
		_ok("③ 改刀身长 → 胶囊跟随", false, "取不到 _knife / _weapon")
		return

	var before: float = w.blade_length
	kn.blade_len = 0.50
	await _frames(2)
	var mesh_z: float = (kn.mesh as Mesh).get_aabb().size.z
	var after: float = w.blade_length
	var cap_h: float = (w._shapecast.shape as CapsuleShape3D).height
	var expect_h: float = maxf(mesh_z, w.blade_radius * 2.0 + 0.001) + w.blade_radius * 2.0

	_ok("③ 改刀身长 → 网格、注入长度、胶囊一起跟随",
		absf(mesh_z - 0.50) < TOL and absf(after - 0.50) < TOL and absf(cap_h - expect_h) < 0.01,
		"网格=%.6f  注入=%.6f  胶囊=%.6f（改前注入 %.6f）" % [mesh_z, after, cap_h, before])

	kn.blade_len = 0.40
	await _frames(2)


# --- ④ 柄轴沿刀轴（不竖穿刀身）---------------------------------------------

func _check_handle_axis(main: Node) -> void:
	var h = main._handle
	var kn = main._knife
	if h == null or kn == null:
		_ok("④ 柄轴与刀轴共线（不竖穿刀身）", false, "取不到 _handle / _knife")
		return

	var a: AABB = (h.mesh as Mesh).get_aabb()
	var long_is_y: bool = a.size.y > a.size.x * 1.5 and a.size.y > a.size.z * 1.5

	# ⚠️ 拿「世界 Z 轴」去比是错的：柄和刀都挂在 Pivot 下，会被持刀姿态
	#    一起转掉（hold_pitch 8° / yaw 10° → 世界轴偏约 12.8°，看起来像"歪了"）。
	#    要比的是**柄轴与刀轴是否共线** —— 那才是「不竖穿刀身」。
	var h_axis: Vector3 = h.global_transform.basis.y.normalized()
	var k_axis: Vector3 = kn.global_transform.basis.z.normalized()
	var dot: float = absf(h_axis.dot(k_axis))

	_ok("④ 柄轴与刀轴共线（不竖穿刀身）",
		long_is_y and dot > 0.99,
		"柄局部 AABB=(%.3f, %.3f, %.3f)（长轴=Y）  柄轴·刀轴=%.4f"
			% [a.size.x, a.size.y, a.size.z, dot])


# --- ⑤ 一次挥击只结算一次（去重键还在）-------------------------------------

func _check_one_swing_one_hit(main: Node) -> void:
	var w = main._weapon
	var cam: Camera3D = main._camera()
	if w == null or cam == null or main._dummies.is_empty():
		_ok("⑤ 一次挥击只结算一次", false, "取不到 武器/相机/靶子")
		return
	var d = main._dummies[0]

	var tip: Vector3 = w.tip_global_position()
	var tip_dist: float = cam.global_position.distance_to(tip)

	var any_hit := false
	var any_multi := false
	var detail := ""

	# 沿视线（眼睛 → 刀尖）方向摆几个距离，总有一个会落在扫掠弧内。
	for frac in [0.55, 0.70, 0.85, 1.00]:
		d.respawn()
		await _frames(2)

		var dir: Vector3 = tip - cam.global_position
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3(0.0, 0.0, -1.0)
		dir = dir.normalized()
		d.global_position = cam.global_position + dir * (tip_dist * float(frac))
		d.global_position.y = 0.0
		await _frames(2)

		var hb: int = w.hit_count
		var hp: int = d.hp
		w.start_swing()
		# 等这次挥砍彻底走完（用状态机判断，比数帧可靠 —— 顿帧会缩时间）。
		var guard := 0
		while w.phase_name() != "待机" and guard < 600:
			await get_tree().physics_frame
			guard += 1
		await _frames(3)

		var dh: int = w.hit_count - hb
		var dhp: int = hp - d.hp
		if dh > 0:
			any_hit = true
		if dh > 1:
			any_multi = true
		detail += "d=%.2fm→命中%d/HP-%d; " % [tip_dist * float(frac), dh, dhp]

	_ok("⑤ 一次挥击恰好结算一次（无重复扣血）",
		any_hit and not any_multi,
		"刀尖距眼 %.3f m ｜ %s" % [tip_dist, detail])


# --- ⑥ 挥击音频钩子真的被调用（曾经是死代码）-------------------------------

func _check_audio_wired(main: Node) -> void:
	var w = main._weapon
	if w == null:
		_ok("⑥ 挥击音频钩子真的被调用", false, "取不到 _weapon")
		return

	# 把靶子挪到天边，保证这一挥**不会命中** → 期望只有 whoosh 一层。
	var d = null
	var saved := Vector3.ZERO
	if not main._dummies.is_empty():
		d = main._dummies[0]
		saved = d.global_position
		d.global_position = Vector3(0.0, -50.0, 0.0)
	await _frames(2)

	var req0: int = Sfx.requests
	w.start_swing()
	var guard := 0
	while w.phase_name() != "待机" and guard < 600:
		await get_tree().physics_frame
		guard += 1
	await _frames(2)
	var delta: int = Sfx.requests - req0

	if d != null:
		d.global_position = saved
	await _frames(1)

	_ok("⑥ 挥击钩子真的被调用（挥空音不再是死代码）",
		delta == 1,
		"一次挥击 → Sfx 被调用 %d 次（期望 1）｜已播 %d 次｜还缺的音色: %s"
			% [delta, Sfx.played, str(Sfx.missing_events())])


# --- ⑦ 调参键全局唯一（防未来撞名）-----------------------------------------

## 键名 = 「组.属性名」，是存档里的地址。两条不同的 entry 一旦算出同一个键，
## 它们就会**静默互相覆盖** —— 拖 A 会改到 B，交换存读还不报错。
##
## 这条断言是给未来买的保险：M3 加 Enemy 参数时，只要键撞了，这里立刻报红。
func _check_keys_unique(main: Node) -> void:
	var seen := {}
	var dups: Array = []
	for e in main._tuning_entries:
		var k: String = TuningStore.key_of(e)
		if seen.has(k):
			dups.append(k)
		seen[k] = true

	_ok("⑦ 调参键全局唯一（无同名互覆盖）",
		dups.is_empty(),
		"%d 条 entry → %d 个唯一键%s"
			% [main._tuning_entries.size(), seen.size(),
				"；重复: " + str(dups) if not dups.is_empty() else ""])


# --- ⑧ 旧档迁移（改组名不许丢用户的值）-------------------------------------

## 造一份**旧格式** cfg（非 player/weapon 的参数全躺在 world 组下）写进一个
## **临时路径**，让 load_into 读它，断言值确实被读进了 target 属性。
##
## ⚠️ 只用临时路径 user://_selfcheck_migrate.cfg，**绝不碰**真正的
##    user://tuning.cfg / tuning_snapshot.cfg。跑完把临时文件删掉。
func _check_legacy_migration(main: Node) -> void:
	var tmp := "user://_selfcheck_migrate.cfg"

	var cf := ConfigFile.new()
	# 旧键：刀身 / 柄 / 靶子 / 音效 —— 都曾在 world 组。
	cf.set_value(TuningStore.SECTION, "world.blade_len", 0.71)
	cf.set_value(TuningStore.SECTION, "world.handle_len", 0.212)
	cf.set_value(TuningStore.SECTION, "world.dummy_auto_respawn", 7.5)
	cf.set_value(TuningStore.SECTION, "world.master_db", -18.5)
	# 精确性①的对照：同名属性**新键已存在**时，旧键必须被无视，新键胜出。
	cf.set_value(TuningStore.SECTION, "world.blade_width", 0.30)      # 旧（应被忽略）
	cf.set_value(TuningStore.SECTION, "blade.blade_width", 0.19)      # 新（应胜出）
	var werr := cf.save(tmp)

	# 先把目标属性改成**明显不同**的哨兵值，这样「读进来了」才看得见。
	main._knife.blade_len = 0.20
	main._knife.blade_width = 0.10
	main.handle_len = 0.111
	main.dummy_auto_respawn = 1.0
	Sfx.master_db = 3.0

	var n: int = TuningStore.load_into(main._tuning_entries, tmp)

	var ok_blade: bool = absf(main._knife.blade_len - 0.71) < TOL
	var ok_handle: bool = absf(main.handle_len - 0.212) < TOL
	var ok_dummy: bool = absf(main.dummy_auto_respawn - 7.5) < TOL
	var ok_sfx: bool = absf(Sfx.master_db - (-18.5)) < TOL
	var ok_prio: bool = absf(main._knife.blade_width - 0.19) < TOL   # 新键胜出

	_ok("⑧ 旧档迁移：world.* 旧键的值被读回新组键",
		werr == OK and n >= 4 and ok_blade and ok_handle and ok_dummy and ok_sfx,
		"写临时档=%s 载入=%d 项 ｜ blade_len=%.4f handle_len=%.4f "
			% [("OK" if werr == OK else "ERR"), n, main._knife.blade_len, main.handle_len]
			+ "dummy_respawn=%.3f master_db=%.2f"
			% [main.dummy_auto_respawn, Sfx.master_db])

	_ok("⑧ 精确性：新键存在时旧键被忽略（新键胜出）",
		ok_prio,
		"旧 world.blade_width=0.30 / 新 blade.blade_width=0.19 → 实得 %.4f"
			% main._knife.blade_width)

	# 清场：临时文件必须删掉（它只是这次自检的道具）。
	TuningStore.erase(tmp)
	_ok("⑧ 迁移自检的临时文件已删除",
		not FileAccess.file_exists(tmp),
		"%s → 存在=%s" % [tmp, str(FileAccess.file_exists(tmp))])
