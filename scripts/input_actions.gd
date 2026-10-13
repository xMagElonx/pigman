class_name InputActions
extends RefCounted
## 集中注册本项目用到的输入动作。
##
## 为什么不写在 Project Settings → Input Map 里？
## 因为写成代码，它能被搜索、被对比、被 AI 读到、跟着 Git 走。
## 如果你更想在编辑器里改键（Project Settings → Input Map），
## 照下面的表把动作加进去就行，代码一行都不用动 ——
## 这个函数只在动作「不存在」时才创建，不会覆盖你手改的结果。
##
## 键用 physical_keycode（物理键位），所以换键盘布局也不会错位。

const ACTIONS := {
	"move_forward":  {"keys": [KEY_W, KEY_UP]},
	"move_back":     {"keys": [KEY_S, KEY_DOWN]},
	"move_left":     {"keys": [KEY_A, KEY_LEFT]},
	"move_right":    {"keys": [KEY_D, KEY_RIGHT]},
	"sprint":        {"keys": [KEY_SHIFT]},
	"jump":          {"keys": [KEY_SPACE]},
	"toggle_panel":  {"keys": [KEY_TAB]},
	"attack":        {"buttons": [MOUSE_BUTTON_LEFT]},
	"reset_dummies": {"keys": [KEY_R]},
}

## Esc 释放鼠标用的是 Godot 内置的 ui_cancel，不需要在这里注册。
##
## 跳跃也**不用** ui_accept —— 那个键同时兼任 UI 的「确认」，
## 而且它不可见（Godot 内置），拖动 jump_velocity 滑条的人
## 在屏幕上找不到任何「按什么键跳」的线索。
## 起一个自己的 jump 动作，好处是它出现在这张表里 —— 可搜索、可改、跟 Git 走。


static func ensure() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		var spec: Dictionary = ACTIONS[action]

		for key in spec.get("keys", []):
			var kev := InputEventKey.new()
			kev.physical_keycode = key
			InputMap.action_add_event(action, kev)

		for button in spec.get("buttons", []):
			var mev := InputEventMouseButton.new()
			mev.button_index = button
			InputMap.action_add_event(action, mev)
