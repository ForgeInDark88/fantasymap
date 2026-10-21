class_name UiAnim
extends RefCounted
## Единый хелпер анимаций интерфейса: плавное появление и скрытие панелей и
## окон (прозрачность + лёгкий сдвиг), мягкая подсветка кнопок, «докручивание»
## чисел. Все анимации прерываемы и не блокируют ввод; при выключенной
## настройке «Анимации интерфейса» всё происходит мгновенно.

const SHOW_TIME := 0.18
const HIDE_TIME := 0.14
const SHIFT := 10.0
## «Докручивание» чисел: скорость сглаживания (1/с).
const ROLL_K := 6.0

## Отображаемые значения «докручиваемых» чисел: ключ → [значение, время мс].
static var _rolled: Dictionary = {}


## Плавное появление при каждом показе (control.visible = true).
static func attach(control: Control, shift: Vector2 = Vector2(0, SHIFT)) -> void:
	if control.has_meta("ui_anim"):
		return
	control.set_meta("ui_anim", true)
	control.visibility_changed.connect(func() -> void:
		if control.visible and not control.get_meta("ui_anim_hiding", false):
			show(control, shift))


static func _kill(control: Control) -> void:
	if not control.has_meta("ui_anim_tween"):
		return
	var tw: Variant = control.get_meta("ui_anim_tween")
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()


static func show(control: Control, shift: Vector2 = Vector2(0, SHIFT)) -> void:
	_kill(control)
	control.set_meta("ui_anim_hiding", false)
	if not SmoothSettings.ui_anim or not control.is_inside_tree():
		control.modulate.a = 1.0
		return
	var base: Vector2 = control.get_meta("ui_anim_base", control.position)
	control.set_meta("ui_anim_base", base)
	control.modulate.a = 0.0
	control.position = base + shift
	var tw := control.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(control, "modulate:a", 1.0, SHOW_TIME)
	tw.tween_property(control, "position", base, SHOW_TIME)
	control.set_meta("ui_anim_tween", tw)


## Плавное скрытие; по окончании visible = false. Повторный показ прерывает.
static func hide(control: Control) -> void:
	if not control.visible:
		return
	_kill(control)
	if not SmoothSettings.ui_anim or not control.is_inside_tree():
		control.visible = false
		control.modulate.a = 1.0
		return
	control.set_meta("ui_anim_hiding", true)
	var tw := control.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(control, "modulate:a", 0.0, HIDE_TIME)
	tw.tween_callback(func() -> void:
		control.visible = false
		control.modulate.a = 1.0
		control.set_meta("ui_anim_hiding", false)
		if control.has_meta("ui_anim_base"):
			control.position = control.get_meta("ui_anim_base"))
	control.set_meta("ui_anim_tween", tw)


## Мягкая подсветка кнопки при наведении и нажатии.
static func hover(button: BaseButton) -> void:
	if button.has_meta("ui_hover"):
		return
	button.set_meta("ui_hover", true)
	var to := func(v: float) -> void:
		if not SmoothSettings.ui_anim or not button.is_inside_tree():
			button.self_modulate = Color(v, v, v)
			return
		var tw := button.create_tween()
		tw.tween_property(button, "self_modulate", Color(v, v, v), 0.12)
	button.mouse_entered.connect(func() -> void: to.call(1.18))
	button.mouse_exited.connect(func() -> void: to.call(1.0))
	button.button_down.connect(func() -> void: to.call(0.9))
	button.button_up.connect(func() -> void: to.call(1.18 if button.is_hovered() else 1.0))


## «Докручиваемое» число: возвращает значение на пути к target (по реальному времени).
static func roll(key: String, target: float) -> float:
	var now := Time.get_ticks_msec()
	if not SmoothSettings.ui_anim or not _rolled.has(key):
		_rolled[key] = [target, now]
		return target
	var e: Array = _rolled[key]
	var dt := (now - int(e[1])) / 1000.0
	var v := SmoothSettings.damp(float(e[0]), target, ROLL_K, dt)
	if absf(v - target) < maxf(0.5, absf(target) * 0.002):
		v = target
	_rolled[key] = [v, now]
	return v


## Уведомление: всплывает снизу и само гаснет через seconds.
static func toast(control: Control, seconds: float) -> void:
	show(control, Vector2(0, 16))
	var timer := control.get_tree().create_timer(seconds)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(control):
			if not SmoothSettings.ui_anim:
				control.queue_free()
				return
			var tw := control.create_tween()
			tw.tween_property(control, "modulate:a", 0.0, 0.4)
			tw.tween_callback(control.queue_free))
