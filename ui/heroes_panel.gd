class_name HeroesPanel
extends PanelContainer
## Список героев мира и карточка выбранного героя.

var _list: VBoxContainer
var _card: RichTextLabel
var _show_dead: CheckBox
var _details: Button
var _play: Button
var _new_race: OptionButton
var _new_class: OptionButton
var _new_name: LineEdit
var _selected := -1
var _last_refresh_ms := 0
var _last_click_ms := 0


func _init() -> void:
	custom_minimum_size = Vector2(440, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Герои"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	_show_dead = CheckBox.new()
	_show_dead.text = "Показывать павших и ушедших на трон"
	_show_dead.toggled.connect(func(_on: bool) -> void: _refresh())
	box.add_child(_show_dead)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	box.add_child(scroll)
	_card = RichTextLabel.new()
	_card.bbcode_enabled = true
	_card.fit_content = true
	_card.scroll_active = false
	_card.custom_minimum_size = Vector2(420, 0)
	_card.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_card)
	_details = Button.new()
	_details.text = "Подробнее о герое…"
	_details.focus_mode = Control.FOCUS_NONE
	_details.visible = false
	_details.pressed.connect(func() -> void: EventBus.hero_window_requested.emit(_selected))
	box.add_child(_details)
	# Режим «Сыграй за героя» скрыт (Features.HERO_PLAY) — без кнопок режима.
	if Features.HERO_PLAY:
		_play = Button.new()
		_play.text = "Играть за героя"
		_play.tooltip_text = "Сыграй за героя: управляйте им сами, мир живёт дальше"
		_play.focus_mode = Control.FOCUS_NONE
		_play.visible = false
		_play.pressed.connect(func() -> void:
			if WorldState.world != null and PlayerSystem.take_control(WorldState.world, _selected):
				EventBus.my_hero_requested.emit(true))
		box.add_child(_play)
		_build_player_row(box)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	EventBus.hero_selected.connect(func(id: int) -> void:
		_selected = id
		_refresh())


## Свой герой: раса, класс, имя, затем клик по стартовому региону.
func _build_player_row(box: Container) -> void:
	var row := HBoxContainer.new()
	_new_race = OptionButton.new()
	for race in RaceDB.all():
		_new_race.add_item(race.display_name)
	row.add_child(_new_race)
	_new_class = OptionButton.new()
	for c in PoliticsDB.hero_classes():
		_new_class.add_item(c.display_name)
	row.add_child(_new_class)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "имя (необязательно)"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_new_name)
	box.add_child(row)
	var create := Button.new()
	create.text = "Создать своего героя (затем клик по стартовому региону)"
	create.focus_mode = Control.FOCUS_NONE
	create.pressed.connect(func() -> void:
		EventBus.god_tool_changed.emit(&"player_create", {"race": RaceDB.all()[_new_race.selected],
			"cls": PoliticsDB.hero_classes()[_new_class.selected], "name": _new_name.text}))
	box.add_child(create)


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_refresh_ms > 1500:
		_refresh()


func _refresh() -> void:
	_last_refresh_ms = Time.get_ticks_msec()
	var world := WorldState.world
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if world == null:
		return
	var heroes: Array[Hero] = []
	for h in world.heroes:
		if (h.alive and not h.is_ruler) or _show_dead.button_pressed:
			heroes.append(h)
	heroes.sort_custom(func(a: Hero, b: Hero) -> bool:
		if a.alive != b.alive:
			return a.alive
		return a.level > b.level)
	if heroes.is_empty():
		var l := Label.new()
		l.text = "Героев пока нет — они приходят в мир сами (или по воле Бога)."
		l.add_theme_font_size_override("font_size", 12)
		_list.add_child(l)
	for h in heroes:
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.icon = h.race.icon
		b.add_theme_constant_override("icon_max_width", 16)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", h.hero_class.color if h.alive else Color(0.55, 0.55, 0.6))
		b.text = "%s — %s, ур. %d · %s" % [h.display_name(), h.hero_class.display_name.to_lower(), h.level, _status(world, h)]
		b.pressed.connect(func() -> void:
			if _selected == h.id and Time.get_ticks_msec() - _last_click_ms < 400:
				EventBus.hero_window_requested.emit(h.id)
			_last_click_ms = Time.get_ticks_msec()
			EventBus.hero_selected.emit(h.id)
			if h.alive:
				EventBus.focus_cell.emit(h.cell))
		_list.add_child(b)
	_show_card(world)


func _status(world: World, h: Hero) -> String:
	if h.is_ruler:
		return "правитель"
	if not h.alive:
		return "пал"
	if h.nation_id >= 0:
		return "служит: " + world.nations[h.nation_id].short_name
	return "странствует"


func _show_card(world: World) -> void:
	_details.visible = _selected >= 0 and _selected < world.heroes.size()
	if _play != null:
		_play.visible = _details.visible and world.heroes[_selected].alive and not world.heroes[_selected].is_ruler and world.player != _selected
	if not _details.visible:
		_card.text = "[color=#8a90a0]Выберите героя, чтобы увидеть его историю (двойной клик — окно героя).[/color]"
		return
	var h := world.heroes[_selected]
	var region := world.region_at(h.cell) if h.cell >= 0 else null
	var lines: Array[String] = [
		"[b]%s[/b] — %s, %s · %s" % [h.display_name(), h.race.display_name.to_lower(), h.hero_class.display_name.to_lower(), h.hero_class.description],
		"Уровень %d · возраст %d · побед в поединках: %d · чудовищ: %d" % [h.level, h.age, h.kills, h.monsters_slain],
		"Сейчас: %s%s" % [_status(world, h), (" · регион " + region.name) if region != null and not region.name.is_empty() else ""],
	]
	var rel: Array[String] = []
	if h.spouse >= 0:
		rel.append("супруг(а): " + world.heroes[h.spouse].display_name())
	if h.mentor >= 0:
		rel.append("наставник: " + world.heroes[h.mentor].display_name())
	if h.party_leader >= 0:
		rel.append("в отряде героя " + world.heroes[h.party_leader].display_name())
	if h.ally_nation >= 0:
		rel.append("[color=#ff9a7a]сражается за %s[/color]" % world.nations[h.ally_nation].short_name)
	if h.vendetta >= 0:
		rel.append("[color=#ff6b5b]поклялся отомстить: %s[/color]" % world.heroes[h.vendetta].display_name())
	var friends: Array[String] = []
	var foes: Array[String] = []
	for other_id in h.bonds:
		var o := world.heroes[other_id]
		if h.bonds[other_id] > 0.5:
			friends.append(o.display_name() + ("" if o.alive else " †"))
		elif h.bonds[other_id] < -0.4:
			foes.append(o.display_name() + ("" if o.alive else " †"))
	if not friends.is_empty():
		rel.append("[color=#9be39b]друзья:[/color] " + ", ".join(friends))
	if not foes.is_empty():
		rel.append("[color=#ff9a7a]враги:[/color] " + ", ".join(foes))
	lines.append_array(rel)
	lines.append("Натура: %s (карма %+.2f)%s" % [h.alignment_name(), h.karma, (" · оружие: " + h.artifact) if not h.artifact.is_empty() else ""])
	lines.append("[b]Деяния:[/b]")
	for d in h.deeds:
		lines.append("• " + d)
	_card.text = "\n".join(lines)
