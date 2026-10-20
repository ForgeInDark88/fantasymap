extends Node
## Звук и музыка (autoload «AudioManager»). Всё синтезируется в коде (Synth):
## эмбиент-темы по контексту мира (мирная, напряжённая — войны, мрачная —
## кризисы, героическая — подвиги и игра за героя, особая — мировой кризис) с
## лейтмотивом ведущей расы (лад и тембр), плавные кроссфейды, звуки
## интерфейса и событий. Темы генерируются в фоновом потоке и кешируются.
## Настройки — user://settings.cfg. В headless-режиме звук выключен.

const SETTINGS := "user://settings.cfg"
const CROSSFADE := 3.0
## Как часто пересматривать контекст музыки (с).
const CONTEXT_EVERY := 2.0
## Героическая тема держится после великого деяния (с).
const HEROIC_HOLD := 25.0
## Не чаще одного звука одного вида за столько секунд.
const SFX_GAP := 0.4
## Звуки событий летописи: [вид записи, фрагмент текста (пусто — любой), звук].
const EVENT_SFX := [
	[&"war", "мир", &"peace"], [&"war", "перемири", &"peace"], [&"war", "", &"war"], [&"conquest", "", &"siege"],
	[&"great", "Врата бездны", &"portal"], [&"great", "", &"great"], [&"event", "ум", &"plague"], [&"event", "Мор", &"plague"],
	[&"crisis", "", &"plague"], [&"lineage", "стал героем", &"birth"], [&"hero", "объявился", &"birth"],
	[&"hero", "погиб", &"death"], [&"hero", "пал", &"death"], [&"fate", "", &"death"],
]

var disabled := DisplayServer.get_name() == "headless"
var master := 0.8
var music := 0.6
var sfx := 0.7
var music_on := true
var sfx_on := true

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _sfx_player: AudioStreamPlayer
var _themes: Dictionary = {}
var _pending: Dictionary = {}
var _sfx_streams: Dictionary = {}
var _sfx_last: Dictionary = {}
var _theme := ""
var _context_timer := 0.0
var _heroic_until := 0.0
var _music_bus := 0
var _sfx_bus := 0


func _ready() -> void:
	load_settings()
	if disabled:
		return
	_music_bus = _bus("Music")
	_sfx_bus = _bus("SFX")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	_sfx_player.max_polyphony = 4
	add_child(_sfx_player)
	apply_volumes()
	# Звуки событий — маленькие, сразу; темы — в фоне по мере надобности.
	for id in Synth.SFX:
		_sfx_streams[id] = Synth.make_stream(Synth.render_sfx(id), false)
	EventBus.world_event.connect(_on_world_event)
	EventBus.achievement_unlocked.connect(func(_d: AchievementDef) -> void: play_sfx(&"achievement"))
	for sig in [EventBus.hero_window_requested, EventBus.tech_window_requested]:
		sig.connect(func(_id: int) -> void: play_sfx(&"open"))
	for sig in [EventBus.chronicles_window_requested, EventBus.achievements_window_requested, EventBus.underworld_window_requested]:
		sig.connect(func() -> void: play_sfx(&"open"))
	EventBus.map_mode_changed.connect(func(_m: int) -> void: play_sfx(&"click"))
	EventBus.nation_selected.connect(func(_n: int) -> void: play_sfx(&"click"))


func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


func load_settings(path: String = SETTINGS) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	master = cfg.get_value("audio", "master", master)
	music = cfg.get_value("audio", "music", music)
	sfx = cfg.get_value("audio", "sfx", sfx)
	music_on = cfg.get_value("audio", "music_on", music_on)
	sfx_on = cfg.get_value("audio", "sfx_on", sfx_on)


func save_settings(path: String = SETTINGS) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # остальные разделы настроек не трогаем
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("audio", "sfx_on", sfx_on)
	cfg.save(path)


func apply_volumes() -> void:
	if disabled:
		return
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, master)))
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(0.0001, music)))
	AudioServer.set_bus_mute(_music_bus, not music_on)
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(0.0001, sfx)))
	AudioServer.set_bus_mute(_sfx_bus, not sfx_on)


func set_volume(which: String, value: float) -> void:
	set(which, clampf(value, 0.0, 1.0))
	apply_volumes()
	save_settings()


func set_enabled(which: String, on: bool) -> void:
	set(which, on)
	apply_volumes()
	save_settings()


func play_sfx(id: StringName) -> void:
	if disabled or not sfx_on or not _sfx_streams.has(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_sfx_last.get(id, -10.0)) < SFX_GAP:
		return
	_sfx_last[id] = now
	_sfx_player.stream = _sfx_streams[id]
	_sfx_player.play()


func _on_world_event(what: StringName, data: Dictionary) -> void:
	if what != &"log":
		return
	for e in EVENT_SFX:
		if data.kind == e[0] and (String(e[1]).is_empty() or String(data.text).contains(e[1])):
			if e[2] == &"great" or e[2] == &"portal":
				_heroic_until = Time.get_ticks_msec() / 1000.0 + HEROIC_HOLD
			play_sfx(e[2])
			return


## Контекст музыки по состоянию мира.
static func pick_context(world: World, heroic: bool) -> StringName:
	if world == null:
		return &"peace"
	if not world.crisis.is_empty():
		return &"crisis"
	if world.player >= 0 or heroic:
		return &"heroic"
	var alive := 0
	var plague := 0
	for n in world.nations:
		if n.alive:
			alive += 1
			if n.modifiers.any(func(m: Dictionary) -> bool: return m.id == &"plague"):
				plague += 1
	if alive > 0 and plague > alive / 3:
		return &"dark"
	var fighting := {}
	for w in world.diplomacy.wars:
		for id in w.attackers:
			fighting[id] = true
		for id in w.defenders:
			fighting[id] = true
	if alive > 0 and fighting.size() > alive * 0.4:
		return &"tension"
	return &"peace"


## Ведущая раса для лейтмотива: раса героя игрока, выбранной державы или крупнейшей.
static func leading_race(world: World) -> StringName:
	if world == null or world.nations.is_empty():
		return &"humans"
	if world.player >= 0:
		return world.heroes[world.player].race_id
	var best: Nation = null
	for n in world.nations:
		if n.alive and (best == null or n.cell_count > best.cell_count):
			best = n
	return best.race_id if best != null else &"humans"


func _process(delta: float) -> void:
	if disabled:
		return
	_context_timer -= delta
	if _context_timer > 0.0:
		return
	_context_timer = CONTEXT_EVERY
	var t := Synth.theme(pick_context(WorldState.world, Time.get_ticks_msec() / 1000.0 < _heroic_until), leading_race(WorldState.world))
	if t.name == _theme:
		return
	if _themes.has(t.name):
		_crossfade(t.name)
	elif not _pending.has(t.name):
		_pending[t.name] = WorkerThreadPool.add_task(func() -> void:
			var pcm := Synth.render_theme(t)
			_theme_ready.call_deferred(t.name, pcm), false, "Music theme")


func _theme_ready(theme_name: String, pcm: PackedByteArray) -> void:
	WorkerThreadPool.wait_for_task_completion(_pending[theme_name])
	_pending.erase(theme_name)
	_themes[theme_name] = Synth.make_stream(pcm, true)
	_context_timer = 0.0


func _crossfade(theme_name: String) -> void:
	_theme = theme_name
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	p.stream = _themes[theme_name]
	p.volume_db = -40.0
	p.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "volume_db", 0.0, CROSSFADE)
	tw.tween_property(old, "volume_db", -60.0, CROSSFADE)
	tw.chain().tween_callback(old.stop)
