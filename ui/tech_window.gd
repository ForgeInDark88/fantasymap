class_name TechWindow
extends Control
## Окно технологий государства: пять веток, у каждой технологии — состояние
## (открыта, изучается, доступна, закрыта), стоимость, требования, эффекты и
## открываемые постройки. Сколько государств мира уже знает технологию — тоже здесь.

const REFRESH_MS := 1000
const EFFECT_NAMES := {&"science_mult": "наука", &"army_mult": "армия", &"trade_mult": "торговля", &"growth_mult": "рост",
	&"aggression_mult": "воинственность", &"production_mult": "добыча", &"siege_mult": "осады", &"naval_mult": "мореходство",
	&"expansion_mult": "экспансия", &"culture_mult": "культура", &"spy_mult": "разведка", &"stability": "стабильность",
	&"food": "пропитание", &"defense": "оборона"}

var _nation_id := -1
var _last_refresh_ms := 0
var _title: Label
var _subtitle: Label
var _columns: Array[RichTextLabel] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			visible = false)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1240, 640)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var header := HBoxContainer.new()
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	names.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.77, 0.85))
	names.add_child(_subtitle)
	header.add_child(names)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)
	box.add_child(header)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	box.add_child(body)
	for branch in TechDB.BRANCH_NAMES:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := Label.new()
		l.text = TechDB.BRANCH_NAMES[branch]
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", TechDB.BRANCH_COLORS[branch])
		col.add_child(l)
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.size_flags_vertical = Control.SIZE_EXPAND_FILL
		r.add_theme_font_size_override("normal_font_size", 12)
		col.add_child(r)
		body.add_child(col)
		_columns.append(r)
	var hint := Label.new()
	hint.text = "✔ открыта · ▶ изучается · ○ доступна · ✕ требования не выполнены или недоступна расе. В скобках — сколько государств мира её знает."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	box.add_child(hint)
	EventBus.tech_window_requested.connect(func(id: int) -> void:
		_nation_id = id
		visible = true
		refresh())
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void: visible = false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_refresh_ms > REFRESH_MS:
		refresh()


func refresh() -> void:
	_last_refresh_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null or _nation_id < 0 or _nation_id >= world.nations.size():
		return
	var nation := world.nations[_nation_id]
	var researching := TechDB.find(nation.researching) if nation.researching != &"" else null
	_title.text = "Знания государства %s" % nation.name
	_subtitle.text = "Открыто %d из %d · наука %.2f · очков исследований %.2f%s · престиж культуры %d" % [
		nation.techs.size(), TechDB.all().size(), nation.tech, nation.research,
		(" · изучается: %s" % researching.display_name) if researching != null else "", roundi(nation.culture_level)]
	var known_by := {}
	for n in world.nations:
		if n.alive:
			for t in n.techs:
				known_by[t] = known_by.get(t, 0) + 1
	var unlocks := {}
	for b in EconomyDB.buildings():
		if b.requires_tech != &"":
			unlocks[b.requires_tech] = unlocks.get(b.requires_tech, []) + [b.display_name]
	var k := 0
	for branch in TechDB.BRANCH_NAMES:
		var techs: Array[TechDef] = []
		for res in TechDB.all():
			if (res as TechDef).branch == branch:
				techs.append(res)
		techs.sort_custom(func(a: TechDef, b: TechDef) -> bool: return a.cost < b.cost)
		var lines: Array[String] = []
		for t in techs:
			var mark := "✕"
			var color := "#6c7080"
			if nation.techs.has(t.id):
				mark = "✔"
				color = "#9be39b"
			elif t.id == nation.researching:
				mark = "▶"
				color = "#ffe680"
			elif TechSystem.is_available(nation, t):
				mark = "○"
				color = "#e8eaf0"
			var progress := (" %d%%" % roundi(minf(1.0, nation.research / t.cost) * 100.0)) if t.id == nation.researching else ""
			lines.append("[color=%s]%s [b]%s[/b]%s[/color] [color=#8a90a0](%.1f · %d)[/color]" % [color, mark, t.display_name, progress, t.cost, known_by.get(t.id, 0)])
			var details: Array[String] = []
			for e in t.effects:
				var v: float = t.effects[e]
				details.append("%s %s" % [EFFECT_NAMES.get(e, str(e)), ("%+d%%" % roundi((v - 1.0) * 100.0)) if String(e).ends_with("_mult") else ("%+.2f" % v)])
			if unlocks.has(t.id):
				details.append("постройки: " + ", ".join(unlocks[t.id]))
			if not t.requires.is_empty() and not nation.techs.has(t.id):
				details.append("нужно: " + ", ".join(t.requires.map(func(r: StringName) -> String: return TechDB.find(r).display_name)))
			if t.race_weight(nation.race) <= 0.0:
				details.append("[color=#e07a6a]недоступна расе[/color]")
			lines.append("   [color=#9aa0b0]" + "; ".join(details) + "[/color]")
		_columns[k].text = "\n".join(lines)
		k += 1
