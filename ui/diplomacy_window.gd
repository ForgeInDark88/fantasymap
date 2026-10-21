class_name DiplomacyWindow
extends Control
## Окно «Дипломатия» (этап 11.E): журнал предложений (принятые и отвергнутые
## сделки, разрывы из-за слухов) с фильтром по державе и виду; характеры
## держав; слухи — с переключателем «Показать правду» (✓ правда, ✗ вымысел, и
## кто из держав поверил).

const REFRESH_MS := 900

var _journal: RichTextLabel
var _side: RichTextLabel
var _nation: OptionButton
var _kind: OptionButton
var _truth: CheckBox
var _nation_ids: Array[int] = []
var _kinds: Array[StringName] = []
var _last_ms := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	UiAnim.attach(self, Vector2.ZERO)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1240, 700)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Дипломатия"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_nation = OptionButton.new()
	_nation.custom_minimum_size = Vector2(240, 0)
	_nation.tooltip_text = "Держава"
	_nation.item_selected.connect(func(_i: int) -> void: refresh())
	header.add_child(_nation)
	_kind = OptionButton.new()
	_kind.custom_minimum_size = Vector2(200, 0)
	_kind.tooltip_text = "Вид сделки"
	_kind.add_item("Все сделки")
	_kinds.append(&"")
	for k in DealSystem.KINDS:
		_kind.add_item(String(DealSystem.KINDS[k]).capitalize())
		_kinds.append(k)
	_kind.item_selected.connect(func(_i: int) -> void: refresh())
	header.add_child(_kind)
	_truth = CheckBox.new()
	_truth.text = "Показать правду"
	_truth.tooltip_text = "Слухи: правда или вымысел — и кто им поверил"
	_truth.focus_mode = Control.FOCUS_NONE
	_truth.toggled.connect(func(_on: bool) -> void: refresh())
	header.add_child(_truth)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: UiAnim.hide(self))
	header.add_child(close)
	box.add_child(header)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	box.add_child(cols)
	_journal = _column(cols, 680)
	_side = _column(cols, 520)
	EventBus.diplomacy_window_requested.connect(open_window)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void: visible = false)


func _column(parent: Control, width: float) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(width, 620)
	t.add_theme_font_size_override("normal_font_size", 13)
	parent.add_child(t)
	return t


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_ms > REFRESH_MS:
		refresh()


func open_window(nation_id: int = -1) -> void:
	var world := WorldState.world
	if world == null:
		return
	visible = true
	_nation.clear()
	_nation_ids.clear()
	_nation.add_item("Все державы")
	_nation_ids.append(-1)
	var list := world.nations.filter(func(n: Nation) -> bool: return n.alive)
	list.sort_custom(func(a: Nation, b: Nation) -> bool: return a.population > b.population)
	for n in list:
		_nation.add_item(n.name)
		_nation_ids.append(n.id)
	_nation.select(maxi(0, _nation_ids.find(nation_id)))
	refresh()


func refresh() -> void:
	_last_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null:
		return
	var nid: int = _nation_ids[_nation.selected] if _nation.selected >= 0 and _nation.selected < _nation_ids.size() else -1
	var kind: StringName = _kinds[_kind.selected] if _kind.selected >= 0 else &""
	_journal.text = journal_text(world, nid, kind)
	_side.text = side_text(world, nid, _truth.button_pressed)


static func journal_text(world: World, nid: int, kind: StringName) -> String:
	var lines: Array[String] = ["[b]Журнал дипломатии[/b] — свежие сверху", ""]
	var shown := 0
	for k in range(world.diplo_journal.size() - 1, -1, -1):
		var j: Dictionary = world.diplo_journal[k]
		if nid >= 0 and int(j.a) != nid and int(j.b) != nid:
			continue
		if kind != &"" and j.kind != kind:
			continue
		lines.append("[color=%s]%d г.[/color] %s" % ["#9be39b" if bool(j.ok) else "#ff9a8a", int(j.year), j.text])
		shown += 1
		if shown >= 120:
			break
	if shown == 0:
		lines.append("[color=#8a90a0]Пока ни одного предложения.[/color]")
	var deals: int = world.counters.get(&"deals", 0)
	var proposed: int = world.counters.get(&"deals_proposed", 0)
	lines.append("")
	lines.append("Всего предложений: %d, принято: %d · продано краёв: %d · мир выкуплен: %d · столиц перенесено: %d" % [proposed, deals,
		world.counters.get(&"regions_sold", 0), world.counters.get(&"peace_bought", 0), world.counters.get(&"capitals_moved", 0)])
	return "\n".join(lines)


static func side_text(world: World, nid: int, truth: bool) -> String:
	var lines: Array[String] = []
	if nid >= 0:
		var n := world.nations[nid]
		if n.personality != null:
			lines.append("[b]%s[/b] — нрав: [b]%s[/b]" % [n.name, n.personality.display_name])
			lines.append("[color=#a8b0c0]%s[/color]" % n.personality.description)
		lines.append("Разведка: %d" % roundi(n.intel))
		lines.append("")
	else:
		var counts := {}
		for n in world.nations:
			if n.alive and n.personality != null:
				counts[n.personality] = counts.get(n.personality, 0) + 1
		lines.append("[b]Нравы держав[/b]")
		for p in counts:
			lines.append("%s — %d" % [(p as PersonalityDef).display_name, counts[p]])
		lines.append("")
	lines.append("[b]Слухи[/b]%s" % (" — с правдой" if truth else ""))
	var shown := 0
	var rumors := RumorSystem.active(world)
	for k in range(rumors.size() - 1, -1, -1):
		var r: Dictionary = rumors[k]
		if nid >= 0 and int(r.about) != nid and int(r.target) != nid:
			continue
		var line := "%d г. %s" % [int(r.year), r.text]
		if truth:
			var believers := 0
			for n in world.nations:
				if n.alive and RumorSystem.believes(world, n, r):
					believers += 1
			line += " %s · верят: %d" % ["[color=#9be39b]✓ правда[/color]" if bool(r.truth) else "[color=#ff8a6a]✗ вымысел[/color]", believers]
			if int(r.source) >= 0:
				line += " · пустил: %s" % world.nations[int(r.source)].short_name
		lines.append(line)
		shown += 1
		if shown >= 40:
			break
	if shown == 0:
		lines.append("[color=#8a90a0]Слухов нет.[/color]")
	return "\n".join(lines)
