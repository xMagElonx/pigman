class_name TunerPanel
extends CanvasLayer
## Tab 呼出的调参面板。
##
## 它存在的唯一理由：把「改一个数字」的成本，
## 从「改代码 → 保存 → 重开项目 → 走到那个地方试一下」
## 降到「拖一下滑条」。
##
## 这个面板的优先级高于「多做一个敌人」。
## 计划书 6.1 已经把「关键参数有可调入口」写成了硬性验收条件。
##
## ── 2026-10-13 修复（面板显示不全 / 不能滚动）──────────────────
## 原来是「标签一行 + 滑条一行」的竖排，17 个参数需要 958px 高，
## 从 y=24 开始 → 底部 982px，而窗口只有 900px，最下面两行永远调不到。
## 三处改动：
##   ① 标签 + 滑条 + 数值 压到**同一行** → 每行高约减半
##   ② 滑条区套 ScrollContainer → 参数再多也不会掉出屏幕
##   ③ 面板高度每次窗口变化时重算，永远不超过视口
## 标题和底部读数**不进滚动区** —— 读数是仪表，不能滚走。
##
## ── 2026-10-14 新增：保存 ────────────────────────────────────────
## 痛点：拖了半天的滑条，关掉游戏就没了。
## 三层，都在这里：
##   自动保存  改动 0.6 秒后写盘，下次启动自动读回（你什么都不用按）
##   快照      调出一版觉得好 → 按「存快照」；再实验别的方向，随时「取快照」
##   恢复默认  回到代码里的 @export 初值
## 值存到哪、为什么存外面不存回 .gd，见 tuning_store.gd 的注释。

const PANEL_WIDTH := 452.0
const MARGIN := 16.0
const LABEL_WIDTH := 168.0
const VALUE_WIDTH := 54.0
## 拖动停止多久之后写盘。太短会频繁 IO，太长则「拖完立刻关游戏」会丢。
const AUTOSAVE_DELAY := 0.6

var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _readout: Label
var _status: Label
var _rows: Array[Dictionary] = []
var _entries: Array = []
var _last_viewport := Vector2.ZERO
var _dirty := false
var _dirty_t := 0.0


## entries 里每一项：
## { label: String, target: Object, prop: String, min: float, max: float, step: float }
func setup(entries: Array, readout_prefix: String = "") -> void:
	_entries = entries

	_panel = PanelContainer.new()
	_panel.position = Vector2(MARGIN, MARGIN)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = "调参面板   ·   Tab 开 / 关   ·   改动自动保存"
	col.add_child(title)

	var hint := Label.new()
	hint.text = "Esc 释放鼠标 · 点画面重新锁定 · R 复位靶子 · 滚轮翻页 · 拖完 0.6 秒自动存盘"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.55)
	col.add_child(hint)

	col.add_child(HSeparator.new())

	# 滑条区：参数只会越来越多（M4 断肢还会再加一批），
	# 没有滚动容器，超出屏幕的那几行就永远调不到。
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	for e in entries:
		_add_row(e)

	col.add_child(HSeparator.new())

	# 按钮行 —— 保存三件事：存快照 / 取快照 / 恢复默认。
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	col.add_child(btn_row)
	_add_button(btn_row, "存快照", _on_save_snapshot)
	_add_button(btn_row, "取快照", _on_load_snapshot)
	_add_button(btn_row, "恢复默认", _on_reset_defaults)

	_status = Label.new()
	_status.text = _autoload_status()
	_status.add_theme_font_size_override("font_size", 11)
	_status.modulate = Color(0.62, 0.88, 0.72, 0.95)
	col.add_child(_status)

	_readout = Label.new()
	_readout.text = readout_prefix
	_readout.add_theme_font_size_override("font_size", 12)
	_readout.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_readout)

	_last_viewport = Vector2.ZERO


## 面板永远不超过窗口。窗口变了就重算一次（拖窗口 / 改分辨率都会触发）。
func _process(delta: float) -> void:
	_tick_autosave(delta)

	if _panel == null or _scroll == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.is_equal_approx(_last_viewport):
		return
	_last_viewport = vp

	# 固定部分 = 标题 + 提示 + 分隔线 + 按钮 + 状态 + 底部读数 + 内边距
	# （ScrollContainer 在 AUTO 模式下竖直最小尺寸为 0，所以这里量到的就是固定部分）
	var fixed_h: float = _panel.get_combined_minimum_size().y
	var want_h: float = fixed_h + _list.get_combined_minimum_size().y
	var limit_h: float = maxf(360.0, vp.y - MARGIN * 2.0)
	_panel.size = Vector2(PANEL_WIDTH, minf(want_h, limit_h))


func toggle() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not _panel.visible else Input.MOUSE_MODE_VISIBLE


func set_readout(text: String) -> void:
	if _readout != null:
		_readout.text = text


# --- 保存 -------------------------------------------------------------------

## 把滑条当前值重新刷一遍 —— 取快照 / 恢复默认之后必须调它，
## 否则值变了但滑条还停在老位置上。
func refresh_all() -> void:
	for r in _rows:
		var e: Dictionary = r.entry
		var v := float(e.target.get(e.prop))
		(r.slider as HSlider).set_value_no_signal(v)
		_refresh_value(e, v, r.label)


func _tick_autosave(delta: float) -> void:
	if not _dirty:
		return
	_dirty_t += delta
	if _dirty_t >= AUTOSAVE_DELAY:
		_flush()


## 立刻写盘。自动保存到时调它，退出游戏时也调它（见 _exit_tree）。
func _flush() -> void:
	if not _dirty or _entries.is_empty():
		return
	_dirty = false
	_dirty_t = 0.0
	var err := TuningStore.save(_entries, TuningStore.AUTO_PATH)
	if err == OK:
		_set_status("已保存 %d 项 → %s" % [_entries.size(), TuningStore.human_path(TuningStore.AUTO_PATH)])
	else:
		_set_status("⚠️ 保存失败（错误码 %d）→ %s" % [err, TuningStore.human_path(TuningStore.AUTO_PATH)])


func _autoload_status() -> String:
	if TuningStore.exists(TuningStore.AUTO_PATH):
		return "存档：%s" % TuningStore.human_path(TuningStore.AUTO_PATH)
	return "还没有存档 —— 拖一下滑条就会自动生成"


func _on_save_snapshot() -> void:
	var err := TuningStore.save(_entries, TuningStore.SNAPSHOT_PATH)
	if err == OK:
		_set_status("快照已存。之后随便改，按「取快照」就回到现在这一版。")
	else:
		_set_status("⚠️ 快照存不了（错误码 %d）" % err)


func _on_load_snapshot() -> void:
	var n := TuningStore.load_into(_entries, TuningStore.SNAPSHOT_PATH)
	if n < 0:
		_set_status("还没有快照 —— 先按「存快照」。")
		return
	refresh_all()
	_dirty = true
	_dirty_t = 0.0
	_set_status("已取回快照，%d 项。" % n)


func _on_reset_defaults() -> void:
	if not TuningStore.has_defaults():
		return
	var n := TuningStore.apply_defaults(_entries)
	refresh_all()
	_dirty = true
	_dirty_t = 0.0
	_set_status("已恢复代码默认值，%d 项。" % n)


func _exit_tree() -> void:
	# 关窗口时兜底：0.6 秒节流可能刚好没走完。
	_flush()


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# --- 体检 / 自检用 -------------------------------------------------------------

## 面板高度体检（自检用）。
## x = 固定部分（标题/提示/按钮/读数/内边距）高度，y = 滑条区最小高度。
## 两者相加再加 MARGIN×2 就是面板真实需要的高度。
func metrics() -> Vector2:
	if _panel == null or _list == null:
		return Vector2.ZERO
	return Vector2(_panel.get_combined_minimum_size().y, _list.get_combined_minimum_size().y)


func row_count() -> int:
	return _rows.size()


func entry_count() -> int:
	return _entries.size()


# --- 行 ---------------------------------------------------------------------

func _add_button(parent: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # 否则 Tab/空格 会落到按钮上
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)


func _add_row(e: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = str(e.label)
	name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.clip_text = true
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = float(e.min)
	slider.max_value = float(e.max)
	slider.step = float(e.step)
	slider.focus_mode = Control.FOCUS_NONE   # 否则 Tab 会被用作焦点切换
	slider.custom_minimum_size = Vector2(120, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = float(e.target.get(e.prop))
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 12)
	row.add_child(value_label)

	_list.add_child(row)

	# 顺序要紧：先入树、再连信号，否则回调里拿不到那个 Label。
	slider.value_changed.connect(_on_slider_changed.bind(e, value_label))
	_refresh_value(e, slider.value, value_label)
	_rows.append({"entry": e, "slider": slider, "label": value_label})


func _on_slider_changed(value: float, e: Dictionary, value_label: Label) -> void:
	e.target.set(e.prop, value)
	_refresh_value(e, value, value_label)
	# 标记「有未写盘的改动」—— 真正的写盘在 _process 里节流进行。
	_dirty = true
	_dirty_t = 0.0


func _refresh_value(e: Dictionary, value: float, value_label: Label) -> void:
	var step: float = float(e.step)
	var decimals := 1
	if step < 0.0005:
		decimals = 4
	elif step < 0.05:
		decimals = 2
	elif step >= 1.0:
		decimals = 0
	value_label.text = String.num(value, decimals)
