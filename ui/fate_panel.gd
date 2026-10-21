class_name FatePanel
extends Control
## «Чертоги Судьбы» — полноэкранная панель суда над павшими героями.
## Игрок решает судьбу каждого: второй шанс, покой или проклятие (душа
## заточается в оружие, на карте появляется пустой трон со стражем).
## Пока панель открыта, время остановлено.

signal closed

var _list: VBoxContainer
var _card: RichTextLabel
var _buttons: HBoxContainer
var _thrones: RichTextLabel
var _count: Label
var _selected := -1
var _speed_before := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	UiAnim.attach(self, Vector2.ZERO)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120, 680)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Чертоги Судьбы"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	header.add_child(title)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	header.add_child(_count)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(close_panel)
	header.add_child(close)
	box.add_child(header)
	var hint := Label.new()
	hint.text = "Павшие герои ждут твоего суда. Верни их в мир живых, отпусти с миром — или прокляни: душа уйдёт в оружие, а на карте возникнет пустой трон, который будут осаждать искатели силы."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.78, 0.8, 0.88))
	box.add_child(hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	box.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	body.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_card = RichTextLabel.new()
	_card.bbcode_enabled = true
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.add_theme_font_size_override("normal_font_size", 13)
	right.add_child(_card)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	for d in [["Второй шанс", _second_chance, Color(0.6, 0.95, 0.6)], ["Оставить в покое", _ignore, Color(0.85, 0.85, 0.9)],
			["Проклясть и заточить в оружие", _curse, Color(1.0, 0.55, 0.45)]]:
		var b := Button.new()
		b.text = d[0]
		b.add_theme_color_override("font_color", d[2])
		b.pressed.connect(d[1])
		_buttons.add_child(b)
	right.add_child(_buttons)
	var tl := Label.new()
	tl.text = "Пустые троны"
	tl.add_theme_font_size_override("font_size", 16)
	right.add_child(tl)
	_thrones = RichTextLabel.new()
	_thrones.bbcode_enabled = true
	_thrones.custom_minimum_size = Vector2(0, 150)
	_thrones.add_theme_font_size_override("normal_font_size", 12)
	right.add_child(_thrones)


func open_panel() -> void:
	_speed_before = WorldState.speed_index
	WorldState.set_speed(0)
	visible = true
	AudioManager.duck_for(3600.0)
	refresh()


func close_panel() -> void:
	UiAnim.hide(self)
	AudioManager.duck_for(0.0)
	if _speed_before > 0:
		WorldState.set_speed(_speed_before)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var world := WorldState.world
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if world == null:
		return
	var pending := Fate.pending(world)
	pending.reverse()  # свежие — сверху
	_count.text = "   ждут суда: %d" % pending.size()
	if _selected >= 0 and not world.fate_queue.has(_selected):
		_selected = -1
	if _selected < 0 and not pending.is_empty():
		_selected = pending[0].id
	for h in pending:
		var b := Button.new()
		b.flat = true
		b.toggle_mode = true
		b.button_pressed = h.id == _selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = h.race.icon
		b.add_theme_constant_override("icon_max_width", 18)
		b.add_theme_color_override("font_color", _karma_color(h.karma))
		b.text = "%s — %s, ур. %d · %s" % [h.display_name(), h.hero_class.display_name.to_lower(), h.level, h.alignment_name()]
		b.pressed.connect(func() -> void:
			_selected = h.id
			refresh())
		_list.add_child(b)
	if pending.is_empty():
		var l := Label.new()
		l.text = "Никто не ждёт суда."
		_list.add_child(l)
	_show_card(world)
	_show_thrones(world)


func _show_card(world: World) -> void:
	_buttons.visible = _selected >= 0
	if _selected < 0:
		_card.text = "[color=#8a90a0]Выбери павшего героя слева.[/color]"
		return
	var h := world.heroes[_selected]
	var lines: Array[String] = [
		"[font_size=20][b]%s[/b][/font_size]" % h.display_name(),
		"%s · %s · уровень %d · прожил %d лет" % [h.race.display_name, h.hero_class.display_name, h.level, h.age],
		"Натура: [color=%s]%s[/color] (карма %+.2f) · побед в поединках: %d · чудовищ: %d" % [
			_karma_color(h.karma).to_html(false), h.alignment_name(), h.karma, h.kills, h.monsters_slain],
	]
	if not h.artifact.is_empty():
		lines.append("Оружие: " + h.artifact)
	var god := LoreDB.god(h.patron_god) if h.patron_god != &"" else null
	if god != null:
		lines.append("[color=#%s]%s Покровитель: %s, %s%s[/color]" % [god.color.to_html(false), god.symbol, god.display_name,
			god.title.to_lower(), " — избранник бога: Судьба может вернуть его на раз больше; проклятие заточит душу в «%s»" % god.curse_weapon if h.chosen else ""])
	if h.returns > 0:
		lines.append("[color=#ffd080]Судьба уже возвращала его %d раз(а)%s[/color]" % [h.returns,
			" — больше нельзя" if h.returns >= Fate.max_returns(h) else ""])
	lines.append("")
	lines.append("[b]Деяния:[/b]")
	for d in h.deeds:
		lines.append("• " + d)
	_card.text = "\n".join(lines)
	(_buttons.get_child(0) as Button).disabled = h.returns >= Fate.max_returns(h)


func _show_thrones(world: World) -> void:
	var lines: Array[String] = []
	for lm in world.landmarks:
		if lm.kind != &"throne":
			continue
		var region := world.region_at(lm.cell)
		var where := region.name if region != null else "?"
		if lm.active:
			lines.append("[color=#ff9a7a]%s[/color] — регион %s; ждёт героя оружие «%s», страж силой %d" % [lm.name, where, lm.artifact, roundi(lm.guardian)])
		else:
			lines.append("[color=#8a90a0]%s — регион %s; оружие уже забрали[/color]" % [lm.name, where])
	_thrones.text = "\n".join(lines) if not lines.is_empty() else "[color=#8a90a0]Пока ни одна душа не проклята.[/color]"


func _second_chance() -> void:
	var world := WorldState.world
	if world != null and _selected >= 0:
		Fate.second_chance(world, world.heroes[_selected])
		_after_judgement()


func _ignore() -> void:
	var world := WorldState.world
	if world != null and _selected >= 0:
		Fate.ignore(world, world.heroes[_selected])
		_after_judgement()


func _curse() -> void:
	var world := WorldState.world
	if world != null and _selected >= 0:
		Fate.curse(world, world.heroes[_selected])
		_after_judgement()


func _after_judgement() -> void:
	_selected = -1
	EventBus.year_passed.emit(WorldState.world.year)
	refresh()


static func _karma_color(k: float) -> Color:
	if k >= 0.3:
		return Color(0.65, 0.95, 0.7)
	if k <= -0.3:
		return Color(1.0, 0.55, 0.5)
	return Color(0.9, 0.88, 0.8)
