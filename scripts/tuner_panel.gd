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

const PANEL_WIDTH := 404.0

var _panel: PanelContainer
var _list: VBoxContainer
var _readout: Label
var _rows: Array[Dictionary] = []


## entries 里每一项：
## { label: String, target: Object, prop: String, min: float, max: float, step: float }
func setup(entries: Array, readout_prefix: String = "") -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 24)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	margin.add_child(_list)

	var title := Label.new()
	title.text = "调参面板   ·   Tab 开 / 关"
	_list.add_child(title)

	var hint := Label.new()
	hint.text = "Esc 释放鼠标   ·   点击画面重新锁定"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.55)
	_list.add_child(hint)

	var sep := HSeparator.new()
	_list.add_child(sep)

	for e in entries:
		_add_row(e)

	if readout_prefix != "":
		var sep2 := HSeparator.new()
		_list.add_child(sep2)
		_readout = Label.new()
		_readout.text = readout_prefix
		_readout.add_theme_font_size_override("font_size", 12)
		_readout.modulate = Color(1, 1, 1, 0.7)
		_list.add_child(_readout)


func toggle() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not _panel.visible else Input.MOUSE_MODE_VISIBLE


func set_readout(text: String) -> void:
	if _readout != null:
		_readout.text = text


func _add_row(e: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = str(e.label)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	head.add_child(name_label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(72, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 12)
	head.add_child(value_label)

	_list.add_child(head)

	var slider := HSlider.new()
	slider.min_value = float(e.min)
	slider.max_value = float(e.max)
	slider.step = float(e.step)
	slider.focus_mode = Control.FOCUS_NONE   # 否则 Tab 会被用作焦点切换
	slider.value = float(e.target.get(e.prop))
	slider.value_changed.connect(_on_slider_changed.bind(e, value_label))
	_list.add_child(slider)

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
	value_label.text = String.num(value, decimals)
