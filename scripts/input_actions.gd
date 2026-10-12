class_name InputActions
extends RefCounted
## 集中注册本项目用到的输入动作。
##
## 为什么不写在 Project Settings → Input Map 里？
## 因为写成代码，它能被搜索、被对比、被 AI 读到、跟着 Git 走。
## 如果你更想在编辑器里改键（Project Settings → Input Map），
## 照下面把六个动作加进去就行，代码一行都不用动 ——
## 这个函数只在动作「不存在」时才创建，不会覆盖你手改的结果。

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"toggle_panel": [KEY_TAB],
}
## 说明：用的是 physical_keycode（物理键位），所以换键盘布局也不会错位。

## Esc 释放鼠标用的是 Godot 内置的 ui_cancel，不需要在这里注册。


static func ensure() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
