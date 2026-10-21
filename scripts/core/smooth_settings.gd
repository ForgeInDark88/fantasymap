class_name SmoothSettings
extends RefCounted
## Настройки плавности (раздел [smooth] в user://settings.cfg) и общие
## функции сглаживания. Касаются только отображения: камера, анимации
## интерфейса, переходы границ и значков, визуальные эффекты событий.
## На симуляцию и её ГСЧ не влияют — хэш мира от них не зависит.

const PATH := "user://settings.cfg"
const SECTION := "smooth"
## Плавность камеры: 0 — мгновенно, 1 — мягко, 2 — сильно (коэффициент сглаживания, 1/с).
const CAMERA_K: Array[float] = [0.0, 14.0, 6.0]
const PRESETS := {
	"instant": {"camera": 0, "ui_anim": false, "border_anim": false, "event_fx": false},
	"soft": {"camera": 1, "ui_anim": true, "border_anim": true, "event_fx": true},
	"max": {"camera": 2, "ui_anim": true, "border_anim": true, "event_fx": true},
}
const PRESET_NAMES := {"instant": "Мгновенно", "soft": "Мягко", "max": "Максимально плавно"}

static var camera := 1
static var ui_anim := true
static var border_anim := true
static var event_fx := true
static var preset := "soft"
## Бюджет анимаций: больше стольких клеток сменили владельца за кадр —
## граница меняется мгновенно (не просесть по FPS и не «плыть» на x50).
static var border_budget := 2500


static func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	preset = name
	var p: Dictionary = PRESETS[name]
	camera = p.camera
	ui_anim = p.ui_anim
	border_anim = p.border_anim
	event_fx = p.event_fx


## Флаги по имени (для окна настроек): ui_anim, border_anim, event_fx.
static func flag(key: String) -> bool:
	match key:
		"ui_anim":
			return ui_anim
		"border_anim":
			return border_anim
		"event_fx":
			return event_fx
	return false


static func set_flag(key: String, on: bool) -> void:
	match key:
		"ui_anim":
			ui_anim = on
		"border_anim":
			border_anim = on
		"event_fx":
			event_fx = on


static func load_settings(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	preset = cfg.get_value(SECTION, "preset", preset)
	camera = clampi(int(cfg.get_value(SECTION, "camera", camera)), 0, 2)
	ui_anim = bool(cfg.get_value(SECTION, "ui_anim", ui_anim))
	border_anim = bool(cfg.get_value(SECTION, "border_anim", border_anim))
	event_fx = bool(cfg.get_value(SECTION, "event_fx", event_fx))


static func save_settings(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # другие разделы (звук) не трогаем
	cfg.set_value(SECTION, "preset", preset)
	cfg.set_value(SECTION, "camera", camera)
	cfg.set_value(SECTION, "ui_anim", ui_anim)
	cfg.set_value(SECTION, "border_anim", border_anim)
	cfg.set_value(SECTION, "event_fx", event_fx)
	cfg.save(path)


## Доля пути к цели за кадр при экспоненциальном сглаживании — не зависит от FPS:
## два кадра по delta/2 дают ровно то же, что один кадр delta.
static func factor(k: float, delta: float) -> float:
	if k <= 0.0:
		return 1.0
	return 1.0 - exp(-k * delta)


static func damp(current: float, target: float, k: float, delta: float) -> float:
	return lerpf(current, target, factor(k, delta))


static func damp_v(current: Vector2, target: Vector2, k: float, delta: float) -> Vector2:
	return current.lerp(target, factor(k, delta))


static func camera_k() -> float:
	return CAMERA_K[clampi(camera, 0, 2)]
