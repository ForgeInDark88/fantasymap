class_name MyHeroPanel
extends PanelContainer
## Панель «Мой герой» (режим «Сыграй за героя»): характеристики, репутация,
## миникарта с путём, команды, журнал приключений. Логика — PlayerSystem;
## путь выбирается кликом по карте (инструмент &"player_travel").

const REFRESH_MS := 200

var _title: Label
var _stats: RichTextLabel
var _minimap: Control
var _status: Label
var _journal: RichTextLabel
var _buttons: Dictionary[StringName, Button] = {}
var _empty: Label
var _hp: ProgressBar
var _perks: HBoxContainer
var _perk_buttons: Dictionary[String, Button] = {}
var _quests: VBoxContainer
var _body: VBoxContainer
var _map_tex: ImageTexture
var _map_world: World
var _last_refresh_ms := 0


func _init() -> void:
	custom_minimum_size = Vector2(440, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(440, 700)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	_title = Label.new()
	_title.text = "Мой герой"
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	_empty = Label.new()
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(400, 0)
	_empty.text = "Вы наблюдаете за миром. Чтобы сыграть за героя, выберите его в панели «Герои» и нажмите «Играть за героя» — или создайте своего."
	box.add_child(_empty)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	box.add_child(_body)
	_hp = ProgressBar.new()
	_hp.max_value = 1.0
	_hp.custom_minimum_size = Vector2(420, 14)
	_hp.show_percentage = false
	_hp.tooltip_text = "Здоровье: раны слабят героя и заживают со временем; при ранах 100% — смерть"
	_body.add_child(_hp)
	_stats = _rich(_body)
	_perks = HBoxContainer.new()
	for stat in PlayerSystem.PERKS:
		var b := Button.new()
		b.text = "+ " + String(PlayerSystem.PERKS[stat]).get_slice(" ", 0)
		b.tooltip_text = PlayerSystem.PERKS[stat]
		b.focus_mode = Control.FOCUS_NONE
		var key: String = stat
		b.pressed.connect(func() -> void:
			if WorldState.world != null:
				PlayerSystem.spend_perk(WorldState.world, key)
				refresh())
		_perks.add_child(b)
		_perk_buttons[stat] = b
	_body.add_child(_perks)
	_quests = VBoxContainer.new()
	_body.add_child(_quests)
	_minimap = Control.new()
	_minimap.custom_minimum_size = Vector2(420, 210)
	_minimap.draw.connect(_draw_minimap)
	_body.add_child(_minimap)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420, 0)
	_body.add_child(_status)
	var grid := GridContainer.new()
	grid.columns = 2
	_body.add_child(grid)
	for c in PlayerSystem.COMMANDS:
		var b := Button.new()
		b.text = c[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(205, 0)
		b.add_theme_font_size_override("font_size", 12)
		var kind: StringName = c[0]
		b.pressed.connect(func() -> void: _command(kind))
		grid.add_child(b)
		_buttons[kind] = b
	var row := HBoxContainer.new()
	var follow := Button.new()
	follow.text = "Следить"
	follow.focus_mode = Control.FOCUS_NONE
	follow.pressed.connect(func() -> void:
		var h := PlayerSystem.hero_of(WorldState.world) if WorldState.world != null else null
		if h != null and h.alive:
			EventBus.hero_selected.emit(h.id)
			EventBus.follow_hero_requested.emit(h.id))
	row.add_child(follow)
	var card := Button.new()
	card.text = "Окно героя"
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(func() -> void:
		if WorldState.world != null and WorldState.world.player >= 0:
			EventBus.hero_window_requested.emit(WorldState.world.player))
	row.add_child(card)
	var leave := Button.new()
	leave.text = "Вернуться к наблюдению"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(func() -> void:
		if WorldState.world != null:
			PlayerSystem.release(WorldState.world)
			refresh())
	row.add_child(leave)
	_body.add_child(row)
	var jl := Label.new()
	jl.text = "Журнал приключений"
	_body.add_child(jl)
	_journal = _rich(_body)
	_journal.fit_content = false
	_journal.scroll_active = true
	_journal.custom_minimum_size = Vector2(420, 200)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())


func _rich(parent: Control) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(420, 0)
	r.add_theme_font_size_override("normal_font_size", 12)
	parent.add_child(r)
	return r


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_refresh_ms > REFRESH_MS:
		refresh()


func _command(kind: StringName) -> void:
	var world := WorldState.world
	if world == null:
		return
	if kind == &"travel":
		_status.text = "Кликните по карте: куда идти? (ПКМ — отмена)"
		EventBus.god_tool_changed.emit(&"player_travel", {})
		return
	var res := PlayerSystem.command(world, kind)
	_status.text = res if not res.is_empty() else "Принято: %s." % PlayerSystem.command_name(kind).to_lower()
	refresh()


func refresh() -> void:
	_last_refresh_ms = Time.get_ticks_msec()
	var world := WorldState.world
	var h := PlayerSystem.hero_of(world) if world != null else null
	_empty.visible = h == null
	_body.visible = h != null
	if h == null:
		_title.text = "Мой герой"
		return
	_title.text = "Мой герой: " + h.display_name()
	_hp.value = UiAnim.roll("hero.hp", 1.0 - h.wounds)
	_hp.modulate = Color(0.5, 1.0, 0.5) if h.wounds < 0.3 else (Color(1.0, 0.85, 0.3) if h.wounds < 0.6 else Color(1.0, 0.4, 0.35))
	_perks.visible = h.perk_points > 0
	for stat in _perk_buttons:
		_perk_buttons[stat].text = "+ %s (%d)" % [String(PlayerSystem.PERKS[stat]).get_slice(" ", 0), int(h.get(stat))]
	_fill_quests(world)
	var lines: Array[String] = [
		"Здоровье %d%% · кошель %d зол. · снаряжение %d/%d%s%s" % [roundi(UiAnim.roll("hero.hp%", (1.0 - h.wounds) * 100.0)), int(UiAnim.roll("hero.gold", h.gold)), h.gear, PlayerQuests.GEAR_MAX,
			(" · охрана %d (до %d г.)" % [h.guards, h.guards_until]) if h.guards > 0 else "",
			(" · [color=#ffd24a]очков развития: %d[/color]" % h.perk_points) if h.perk_points > 0 else ""],
		"Развитие: сила %d · ум %d · обаяние %d" % [h.strength, h.wit, h.charm],
		"%s, %s · уровень %d (опыт %.1f / %.1f) · возраст %d" % [h.race.display_name, h.hero_class.display_name.to_lower(), h.level, h.xp, h.level * 1.5, h.age],
		"Сила: %.0f · ум: %s (%.2f) · натура: %s (%+.2f)" % [h.power(), h.intellect_name(), h.wits(), h.alignment_name(), h.karma],
		"Где: %s%s" % [world.region_label(h.cell, "дикие земли"), (" · служит: " + world.nations[h.nation_id].short_name) if h.nation_id >= 0 else ""],
	]
	# Живой мир (этап 11.H): плен, войско, груз, язык края.
	if h.captive_by >= 0:
		lines.append("[color=#ff8a6a]В плену у государства %s до %d г. — выкуп %d зол. или побег.[/color]" % [world.nations[h.captive_by].short_name,
			h.captive_until, int(PlayerWorld.ransom_price(h))])
	if not world.player_army.is_empty():
		var a := PlayerWorld.player_army(world)
		lines.append("[color=#ffd24a]%s в войске государства %s%s[/color]" % ["Полководец" if world.player_army.role == "general" else "Офицер",
			world.nations[int(world.player_army.nation)].short_name, (" · " + world.region_label(a.cell, "")) if a != null else ""])
	if not h.cargo.is_empty():
		var items: Array[String] = []
		for gi in h.cargo:
			items.append("%s %d" % [(MarketDB.all()[int(gi)] as GoodDef).display_name.to_lower(), roundi(float(h.cargo[gi]))])
		lines.append("Груз (%d/%d): %s" % [int(PlayerWorld.cargo_total(h)), int(PlayerWorld.cargo_cap(h)), ", ".join(items)])
	if not PlayerWorld.speaks_here(world, h):
		lines.append("[color=#c0c8f0]Здесь говорят на чужом языке: цены выше, заданий меньше.[/color]")
	if not h.artifact.is_empty():
		lines.append("Предмет: %s (×%.2f)" % [h.artifact, h.artifact_mult])
	if h.patron_god != &"" and LoreDB.god(h.patron_god) != null:
		lines.append("Бог: %s%s" % [LoreDB.god(h.patron_god).display_name, " (избранник)" if h.chosen else ""])
	if h.order >= 0:
		lines.append("Орден: " + world.orders[h.order].name)
	var company: Array[String] = []
	if h.spouse >= 0 and world.heroes[h.spouse].alive:
		company.append("супруг(а) " + world.heroes[h.spouse].display_name())
	for o in world.wandering_heroes():
		if o.party_leader == h.id:
			company.append("%s (ур. %d)" % [o.display_name(), o.level])
		elif o.mentor == h.id:
			company.append("ученик " + o.display_name())
	if not company.is_empty():
		lines.append("Спутники: " + ", ".join(company))
	var rep := PlayerSystem.reputation(world)
	if not rep.is_empty():
		lines.append("Репутация: " + ", ".join(rep.slice(0, 5).map(func(r: Array) -> String:
			return "[color=%s]%s %+.2f[/color]" % ["#9be39b" if r[1] >= 0.0 else "#ff9a7a", r[0], r[1]])))
	_stats.text = "\n".join(lines)
	var cmd := world.player_cmd
	if not world.player_choice.is_empty():
		_status.text = "Ждёт вашего решения: %s" % world.player_choice.title
	elif cmd.is_empty():
		if not _status.text.begins_with("Кликните"):
			_status.text = "Отдыхает%s." % ((" (%d мес. без дел)" % world.player_idle) if world.player_idle > 1 else "")
	elif cmd.kind == "travel":
		_status.text = "В пути в регион %s: осталось шагов %d." % [world.regions[int(cmd.target)].name, (cmd.path as Array).size()]
	else:
		_status.text = "Занят: %s." % PlayerSystem.command_name(StringName(cmd.kind)).to_lower()
	for kind in _buttons:
		var why := PlayerSystem.why_not(world, kind) if kind != &"travel" else ""
		_buttons[kind].disabled = not why.is_empty()
		_buttons[kind].tooltip_text = why
	var j: Array[String] = []
	for i in range(world.player_journal.size() - 1, maxi(-1, world.player_journal.size() - 40), -1):
		var e: Dictionary = world.player_journal[i]
		j.append("[color=#8a90a0]%d г., %d мес.[/color] %s" % [int(e.year), int(e.month) + 1, e.text])
	_journal.text = "\n".join(j)
	_minimap.queue_redraw()


func _fill_quests(world: World) -> void:
	for c in _quests.get_children():
		_quests.remove_child(c)
		c.queue_free()
	for i in world.player_quests.size():
		var q := world.player_quests[i]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "❖ %s — %d зол., до %d г." % [q.title, int(q.gold), int(q.deadline)]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var go := Button.new()
		go.text = "Идти"
		go.focus_mode = Control.FOCUS_NONE
		var index := i
		go.pressed.connect(func() -> void:
			var res := PlayerSystem.command(WorldState.world, &"quest_go", index)
			_status.text = res if not res.is_empty() else "В путь — к цели задания."
			refresh())
		row.add_child(go)
		_quests.add_child(row)


## Горячие клавиши режима героя (панель открыта): T — идти, H — охота, R — отдых, Q — к цели задания.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or not key.pressed or key.echo or WorldState.world == null or WorldState.world.player < 0:
		return
	var kinds := {KEY_T: &"travel", KEY_H: &"hunt", KEY_R: &"rest", KEY_G: &"quest_go"}
	if kinds.has(key.keycode):
		_command(kinds[key.keycode])
		get_viewport().set_input_as_handled()


func _draw_minimap() -> void:
	var world := WorldState.world
	var h := PlayerSystem.hero_of(world) if world != null else null
	if h == null:
		return
	if _map_world != world:
		_map_world = world
		var img := MapPainter.paint(world.map, MapMode.BIOMES)
		img.resize(int(_minimap.custom_minimum_size.x), int(_minimap.custom_minimum_size.y), Image.INTERPOLATE_BILINEAR)
		_map_tex = ImageTexture.create_from_image(img)
	var size := _minimap.size
	_minimap.draw_texture_rect(_map_tex, Rect2(Vector2.ZERO, size), false)
	var k := Vector2(size.x / world.map.width, size.y / world.map.height)
	var at := func(cell: int) -> Vector2: return (Vector2(world.map.cell_pos(cell)) + Vector2(0.5, 0.5)) * k
	var cmd := world.player_cmd
	if not cmd.is_empty() and cmd.kind == "travel":
		var prev: Vector2 = at.call(h.cell)
		for r in cmd.path:
			var region := world.regions[int(r)]
			var p: Vector2 = at.call(region.cells[region.cells.size() / 2])
			_minimap.draw_line(prev, p, Color(1.0, 0.9, 0.4), 1.5, true)
			prev = p
	for q in world.player_quests:
		var qc := PlayerQuests.target_cell(world, q)
		if qc >= 0:
			_minimap.draw_circle(at.call(qc), 3.5, Color(1.0, 0.85, 0.2))
			_minimap.draw_arc(at.call(qc), 5.5, 0.0, TAU, 12, Color(0.1, 0.1, 0.1), 1.0)
	_minimap.draw_circle(at.call(h.cell), 4.0, Color(1.0, 0.3, 0.2))
	_minimap.draw_arc(at.call(h.cell), 6.0, 0.0, TAU, 16, Color.WHITE, 1.0)
