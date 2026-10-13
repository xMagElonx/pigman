extends Node
## 音效单例（autoload 名：`Sfx`）。
##
## ── 为什么单独开一个单例，而不是把播放器挂进 weapon.gd ──────────────
## 武器不该持有音频资源。三层分开，各管各的：
##   武器（weapon.gd）  负责「什么时刻响」   ← 已经接好了
##   Sfx（本文件）      负责「怎么响」       ← 管道，归 AI
##   音色文件           负责「是什么声音」   ← 签名，归你
## 玩家换音色时不需要碰任何一行代码。
##
## ── 怎么用（只有两步）────────────────────────────────────────────
## 1. 把音色文件按下面的文件名放进 `assets/audio/`
## 2. 打开游戏砍一刀 —— 响了就是接上了
## 没有文件时**静默跳过**（不崩、不报错、不打日志），
## 所以「先接线、后录音」是安全的。
##
## ── 事件表（要加新声音就改这里）──────────────────────────────────
##   sfx_swing_whoosh   每次挥击的破空声（短、亮、**不要低频**）
##   sfx_swing_hit      命中时**叠在上面**的撞击声（骤停、暗、**要有低频冲击**）
##   sfx_limb_sever     断肢（M4 预留：只占名字，M2 不要填内容）
##
## ── 为什么是这两条、以及为什么必须这样分 ──────────────────────────
## M2 的验收是「闭眼分辨切中 / 挥空」。做法不是「两种完全不同的音」，
## 而是「恒定底层 + 可变上层」：
##   挥空 = 只有 whoosh（一层风）
##   命中 = whoosh + hit 叠在一起（风 + 撞）
## 底层恒定，判据才立得住 —— 所以 whoosh 每次必须完全一样，不许随机。

## 事件名 → 文件路径。改这张表就能加新声音。
const EVENTS := {
	&"sfx_swing_whoosh": "res://assets/audio/sfx_swing_whoosh.ogg",
	&"sfx_swing_hit": "res://assets/audio/sfx_swing_hit.ogg",
	&"sfx_limb_sever": "res://assets/audio/sfx_limb_sever.ogg",
}

## 找不到 .ogg 时，再按顺序试这几个扩展名。
## 用途：你可以先塞一个 .wav 进来听效果，不必先转格式。
const FALLBACK_EXTS := ["wav", "mp3"]

## 同时能响几个（池化）。挥砍很快，一个播放器不够叠层。
const POOL_SIZE := 8

## 总音量（dB）。调参面板最下面有一根「音效音量」滑条接在这里。
##    0  = 原始音量
##   -6  = 一半响度（默认，给音色留 headroom）
##  -40  = 几乎听不见
var master_db := -6.0:
	set(v):
		master_db = v
		_apply_volume()

var _players: Array[AudioStreamPlayer] = []
var _next := 0
## 事件 → AudioStream（或 null）。缓存住，避免每次挥击都去查磁盘。
var _cache := {}

## 计数器（给自检门 checks/selfcheck.gd 用）。
## 「钩子被调用」和「有音色可播」是两件事 —— requests 涨了，
## 才能证明「挥空音钩子真的接上了」（在这之前它是死代码，requests 恒为 0）。
var requests := 0
## 真的播出去的次数。没有音色文件时不会涨（静默跳过）。
var played := 0


func _ready() -> void:
	# 顿帧走 Engine.time_scale —— 但「打中了」那一声不能被顿帧掐掉，
	# 所以这里和播放器都设成 ALWAYS 处理，不受暂停/时间缩放影响。
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		p.bus = &"Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)


## 播放一个事件（事件名见 EVENTS）。没有对应音色文件时静默返回。
## volume_offset_db：单个事件的音量微调，默认 0。
func play(event: StringName, volume_offset_db: float = 0.0) -> void:
	requests += 1
	var stream := _stream_for(event)
	if stream == null:
		return

	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = master_db + volume_offset_db
	# ⚠️ M2 硬约束：底层恒定 —— 不随机音高、不随机音量。
	#    「有没有第二层」这个判据，全靠底层每次都一样。
	p.pitch_scale = 1.0
	played += 1
	p.play()


## 这个事件现在有没有音色文件（供面板/自检显示「还缺哪几条」）。
func has_sound(event: StringName) -> bool:
	return _stream_for(event) != null


## 返回还没接上音色的事件名列表。给「我该录哪几条」一个明确答案。
func missing_events() -> Array:
	var out: Array = []
	for e in EVENTS:
		if _stream_for(e) == null:
			out.append(e)
	return out


func _stream_for(event: StringName) -> AudioStream:
	if _cache.has(event):
		return _cache[event]

	var path: String = str(EVENTS.get(event, ""))
	var found: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		found = load(path) as AudioStream
	elif path != "":
		var base := path.get_basename()
		for ext in FALLBACK_EXTS:
			var alt := "%s.%s" % [base, ext]
			if ResourceLoader.exists(alt):
				found = load(alt) as AudioStream
				break

	_cache[event] = found
	return found


func _apply_volume() -> void:
	for p in _players:
		p.volume_db = master_db
