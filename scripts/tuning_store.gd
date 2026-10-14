class_name TuningStore
extends RefCounted
## 调参值的持久化。
##
## 它解决的痛点只有一句话：**拖了半天的滑条，关掉游戏就没了。**
##
## ── 三层，各管一件事 ────────────────────────────────────────────────
##   1. user://tuning.cfg            自动保存
##      改动后 0.6 秒写盘，下次启动自动读回。你什么都不用按。
##   2. user://tuning_snapshot.cfg   手动快照
##      调出一版觉得好 → 按「存快照」。再实验别的方向，随时「取快照」回来。
##      这一层是为「调参最大的敌人不是调不出来，是你忘了昨天那版什么样」写的。
##   3. 脚本里的 @export 初值        出厂默认
##      「恢复默认」按钮的目标。注意它在启动时被采集一次，
##      所以它永远是**代码里的值**，不会被你的拖动污染。
##
## ── 为什么不把值直接写回 .gd 文件 ──────────────────────────────────
##   脚本归 Git 管。你每天 commit 的应该是「我改了什么」，
##   不是「我把 walk_speed 拖到了 4.3」。
##   手感值属于「这台机器上的我」，不属于「这个项目的代码」——
##   两者混在一起，三个月后你分不清哪些是设计、哪些是临场试出来的。
##
## ── 文件在哪 ────────────────────────────────────────────────────
##   Windows: %APPDATA%\Godot\app_userdata\PigMan\
##   （想手改也行，它是纯文本 cfg，改完重启项目即可。）

const AUTO_PATH := "user://tuning.cfg"
const SNAPSHOT_PATH := "user://tuning_snapshot.cfg"
const SECTION := "tuning"

## 启动时采集的「代码默认值」。键 → 值。
static var _defaults := {}


# --- 键 ---------------------------------------------------------------------

## 键 = 「组.属性名」。组有两种来源，**显式声明永远优先**：
##   ① entry 里写了 "group" → 用它。（新增可调对象时推荐：一眼看得见归谁。）
##   ② 否则按 target 的类型推断：PlayerController→player、MeleeWeapon→weapon、
##      KnifeMesh→blade。
##   ③ 还认不出来 → 落 "world"。
##
## ⚠️ 组名就是键名的一半 —— **改组名 = 改键名 = 用户存档里的值读不回来**。
##    所以除非同时写了旧档迁移（见 load_into），否则不要动这里的映射。
##
## ⚠️ 兜底组 "world" 是「没被认领」的意思，不该有第二个人住进来：
##    两个不同对象一旦同名属性都落进来，会**静默互相覆盖**（存档里换值，不报错）。
##    M3 的 Enemy 参数必须**显式声明 "group"**，不要靠推断。
static func key_of(e: Dictionary) -> String:
	# ① 显式声明最高优先。
	if e.has("group"):
		return "%s.%s" % [e["group"], e.get("prop", "?")]
	# ② 类型推断。
	var t: Object = e.get("target")
	var g := "world"
	if t is PlayerController:
		g = "player"
	elif t is MeleeWeapon:
		g = "weapon"
	elif t is KnifeMesh:
		g = "blade"
	# ③ 兜底。
	return "%s.%s" % [g, e.get("prop", "?")]


## 旧档里这条 entry 曾经用的键。
##
## 历史：在引入分组之前，只有 PlayerController / MeleeWeapon 有专属组，
## 其余（刀身 / 柄 / 靶子 / 音效）**全部挤在 "world.<prop>" 下**。
## 本次改动把它们拆进 blade / handle / dummy / sfx 四个组 ——
## 于是旧键的值必须搬过来，否则用户拖了半天的数就没了。
##
## player / weapon 的键从来没变过，返回空串（表示「这条没有旧键要迁」）。
static func legacy_key_of(e: Dictionary) -> String:
	var t: Object = e.get("target")
	if t is PlayerController or t is MeleeWeapon:
		return ""
	return "world.%s" % e.get("prop", "?")


## 统计哪些 prop 名在整份清单里**只出现一次**。
##
## 迁移的安全阀：旧键 world.<prop> 只按 prop 名认领，不看组。
## 若两个组有同名属性（比如 M3 的 Enemy 也有 blade_len），
## 它俩会去抢同一个 world.blade_len → **互相污染**。
## 只让「唯一名」参与迁移：有歧义时宁可放弃迁移，也绝不把值灌错对象。
static func _unique_props(entries: Array) -> Dictionary:
	var count := {}
	for e in entries:
		var p: String = e.get("prop", "?")
		count[p] = int(count.get(p, 0)) + 1
	var uniq := {}
	for p in count:
		if count[p] == 1:
			uniq[p] = true
	return uniq


# --- 默认值 ------------------------------------------------------------------

## 采集「出厂默认」。每次 _ready 调一次 —— 那时目标对象刚从 _build_* 造出来，
## 身上全是代码里写的初值，还没有被任何配置文件碰过。
static func capture_defaults(entries: Array) -> void:
	_defaults.clear()
	for e in entries:
		_defaults[key_of(e)] = e.target.get(e.prop)


static func has_defaults() -> bool:
	return not _defaults.is_empty()


## 「恢复默认」按钮：把值写回启动时采集的那一份。
static func apply_defaults(entries: Array) -> int:
	var n := 0
	for e in entries:
		var k := key_of(e)
		if _defaults.has(k):
			e.target.set(e.prop, _defaults[k])
			n += 1
	return n


# --- 存 / 取 ------------------------------------------------------------------

static func save(entries: Array, path: String) -> Error:
	var cf := ConfigFile.new()
	for e in entries:
		cf.set_value(SECTION, key_of(e), e.target.get(e.prop))
	return cf.save(path)


## 返回成功载入的条数；文件不存在返回 -1。
##
## ── 旧档迁移（一次性，用户无感）────────────────────────────────────
## 新键（blade.* / handle.* / dummy.* / sfx.*）取不到时，回退查旧键 world.<prop>。
## 命中就采用 —— 用户拖出来的值照旧读得回来，不会因为改组名而丢。
## 因为 ConfigFile.save() 会**整文件重写**，所以只要之后有任何一次自动保存，
## 文件就自然换成新键名，旧 world.* 键随之消失，迁移是一次性的。
##
## 三条精确性约束（缺一不可）：
##   ① 只在**新键不存在**时才查旧键 —— 新键一旦存在，旧键一律不参与。
##   ② 只有**曾经真的落在 world 组**的 entry 才迁（player/weapon 从没在 world 待过）。
##   ③ prop 名必须在整份清单里**唯一** —— 否则同名属性会抢同一个旧键，互相污染。
static func load_into(entries: Array, path: String) -> int:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return -1
	var unique_props := _unique_props(entries)
	var n := 0
	for e in entries:
		var k := key_of(e)
		# ① 新键优先。
		if cf.has_section_key(SECTION, k):
			var v: Variant = cf.get_value(SECTION, k)
			if v == null:
				continue
			e.target.set(e.prop, v)   # set 会按属性声明的类型转换
			n += 1
			continue
		# ②③ 新键没有 → 查旧键 world.<prop>（仅限旧档里真在 world 组的、且名唯一的）。
		var old_k := legacy_key_of(e)
		if old_k == "" or not unique_props.has(e.get("prop", "?")):
			continue
		if not cf.has_section_key(SECTION, old_k):
			continue
		var v_old: Variant = cf.get_value(SECTION, old_k)
		if v_old == null:
			continue
		e.target.set(e.prop, v_old)
		n += 1
	return n


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func erase(path: String) -> void:
	if exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 给面板显示用：cfg 文件在磁盘上的真实路径。
static func human_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)
