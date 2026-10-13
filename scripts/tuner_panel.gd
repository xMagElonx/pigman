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

const PANEL_WIDTH := 452.0
const MARGIN := 16.0
const LABEL_WIDTH := 168.0
const VALUE_WIDTH := 54.0

var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _readout: Label
var _rows: Array[Dictionary] = []
var _last_viewport := Vector2.ZERO


## entries 里每一项：
## { label: String, target: Object, prop: String, min: float, max: float, step: float }
func setup(entries: Array, readout_prefix: String = "") -> void:
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
	title.text = "调参面板   ·   Tab 开 / 关"
	col.add_child(title)

	var hint := Label.new()
	hint.text = "Esc 释放鼠标 · 点画面重新锁定 · R 复位靶子 · 滚轮翻页"
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

	_readout = Label.new()
	_readout.text = readout_prefix
	_readout.add_theme_font_size_override("font_size", 12)
	_readout.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_readout)

	_last_viewport = Vector2.ZERO


## 面板永远不超过窗口。窗口变了就重算一次（拖窗口 / 改分辨率都会触发）。
func _process(_delta: float) -> void:
	if _panel == null or _scroll == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.is_equal_approx(_last_viewport):
		return
	_last_viewport = vp

	# 固定部分 = 标题 + 提示 + 分隔线 + 底部读数 + 内边距
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


## 面板高度体检（自检用）。
## x = 固定部分（标题/提示/读数/内边距）高度，y = 滑条区最小高度。
## 两者相加再加 MARGIN×2 就是面板真实需要的高度。
func metrics() -> Vector2:
	if _panel == null or _list == null:
		return Vector2.ZERO
	return Vector2(_panel.get_combined_minimum_size().y, _list.get_combined_minimum_size().y)


func row_count() -> int:
	return _rows.size()


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
