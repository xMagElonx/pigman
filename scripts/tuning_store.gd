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

## 键 = 「组.属性名」。组由 target 的类型推出，不用在 entries 里手写。
##
## ⚠️ 以后新增可调对象时，如果它不是 PlayerController / MeleeWeapon，
##    会落到 "world" 组 —— 那时若出现同名属性，两个参数会互相覆盖。
##    真遇到再加分支即可。
static func key_of(e: Dictionary) -> String:
	var t: Object = e.get("target")
	var g := "world"
	if t is PlayerController:
		g = "player"
	elif t is MeleeWeapon:
		g = "weapon"
	return "%s.%s" % [g, e.get("prop", "?")]


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
static func load_into(entries: Array, path: String) -> int:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return -1
	var n := 0
	for e in entries:
		var k := key_of(e)
		if not cf.has_section_key(SECTION, k):
			continue
		var v: Variant = cf.get_value(SECTION, k)
		if v == null:
			continue
		e.target.set(e.prop, v)   # set 会按属性声明的类型转换
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
