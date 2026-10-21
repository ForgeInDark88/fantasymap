class_name ArmyCard
extends PanelContainer
## Карточка армии (клик по значку армии): состав, полководец, снабжение,
## боевой дух, состояние и цель; «К армии» — плавный перелёт камеры.

const REFRESH_MS := 400
const STATE_NAMES := {&"muster": "собирается", &"march": "на марше", &"siege": "осаждает", &"retreat": "отступает",
	&"sail": "плывёт с десантом", &"idle": "стоит лагерем"}

var _army: Army
var _text: RichTextLabel
var _last_ms := 0


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(340, 0)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -170.0
	offset_right = 170.0
	offset_top = 110.0
	var box := VBoxContainer.new()
	add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(320, 0)
	_text.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_text)
	var row := HBoxContainer.new()
	var go := Button.new()
	go.text = "К армии"
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(func() -> void:
		if _army != null and _army.cell >= 0:
			EventBus.focus_cell.emit(_army.cell))
	row.add_child(go)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: EventBus.army_selected.emit(null))
	row.add_child(close)
	box.add_child(row)
	UiAnim.attach(self, Vector2(0, -8))
	EventBus.army_selected.connect(func(a: Army) -> void:
		_army = a
		if a == null:
			UiAnim.hide(self)
		else:
			visible = true
			refresh())
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_army = null
		visible = false)


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_ms > REFRESH_MS:
		refresh()


func refresh() -> void:
	_last_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null or _army == null:
		return
	var a := _army
	if not a.alive:
		_text.text = "[b]%s[/b]\n[color=#8a90a0]Армия распущена или разбита.[/color]" % a.label(world)
		return
	var lines: Array[String] = ["[font_size=16][b]%s[/b][/font_size]" % a.label(world)]
	if a.kind == &"pirates":
		lines.append("Сила: %s · грабят порт края %s" % [ArmySystem._num(a.strength(world)), world.region_label(a.cell, "моря")])
		_text.text = "\n".join(lines)
		return
	var n := world.nations[a.nation]
	lines.append("%s · %s" % ["флот" if a.kind == &"fleet" else "войско народа «%s»" % n.race.display_name, STATE_NAMES.get(a.state, String(a.state))])
	lines.append("Сила: [b]%s[/b] · боевая: %s" % [ArmySystem._num(UiAnim.roll("army%d.s" % a.get_instance_id(), a.strength(world))),
		ArmySystem._num(a.fighting_power(world))])
	lines.append("Боевой дух: %s · снабжение: %s" % [_bar(a.morale), _bar(a.supply)])
	if a.general >= 0:
		var g: Dictionary = world.generals[a.general]
		lines.append("Полководец: [color=#ffe08a]%s[/color] (мастерство %d%%, побед %d)%s" % [g.name, roundi(float(g.skill) * 100.0),
			int(g.wins), " — герой" if int(g.hero) >= 0 else ""])
	else:
		lines.append("[color=#8a90a0]Без полководца[/color]")
	var war: War = null
	for w in world.diplomacy.wars:
		if w.id == a.war:
			war = w
	if war != null:
		lines.append("Война: %s" % war.name)
		if war.siege_region >= 0:
			lines.append("Цель: регион %s%s" % [world.regions[war.siege_region].name,
				(" · осада %d%%" % roundi(war.siege_progress * 100.0)) if a.state == &"siege" else ""])
	lines.append("Где: %s · битв %d, побед %d" % [world.region_label(a.cell, "дикие земли"), a.battles, a.wins])
	if not a.path.is_empty():
		lines.append("Путь: ещё %d краёв" % a.path.size())
	_text.text = "\n".join(lines)


static func _bar(v: float) -> String:
	var col := "#9be39b" if v > 0.6 else ("#ffd24a" if v > 0.3 else "#ff7a6a")
	return "[color=%s]%d%%[/color]" % [col, roundi(v * 100.0)]
