class_name UnderworldWindow
extends Control
## Окно подземного мира: мини-карта графа пещер (слева) и список узлов по
## хозяевам (справа). Клик по названию — камера к пещере.

const REFRESH_MS := 1000

var _map_view: Control
var _list: RichTextLabel
var _title: Label
var _last_refresh_ms := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.8)
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
	panel.custom_minimum_size = Vector2(1180, 640)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var header := HBoxContainer.new()
	_title = Label.new()
	_title.text = "Подземный мир"
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
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
	_map_view = Control.new()
	_map_view.custom_minimum_size = Vector2(640, 540)
	_map_view.draw.connect(_draw_map)
	body.add_child(_map_view)
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("normal_font_size", 12)
	_list.meta_clicked.connect(func(meta: Variant) -> void:
		var world := WorldState.world
		var id := int(str(meta))
		if world != null and id >= 0 and id < world.caves.size():
			visible = false
			EventBus.focus_cell.emit(world.caves[id].cell))
	body.add_child(_list)
	EventBus.underworld_window_requested.connect(func() -> void:
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
	if world == null:
		return
	_map_view.queue_redraw()
	var by_owner := {}
	for c in world.caves:
		var list: Array = by_owner.get(c.owner, [])
		list.append(c)
		by_owner[c.owner] = list
	var lines: Array[String] = []
	var owners := by_owner.keys()
	owners.sort()
	for o in owners:
		if o >= 0:
			var n := world.nations[o]
			lines.append("[b][color=#%s]%s[/color][/b] — пещер %d" % [n.color.lightened(0.3).to_html(false), n.name, by_owner[o].size()])
		else:
			lines.append("[b][color=#c08070]Дикие глубины[/color][/b] — %d" % by_owner[o].size())
		for c: Cave in by_owner[o]:
			var extra: Array[String] = ["глубина %d" % c.depth]
			if c.entrance:
				extra.append("вход")
			if c.city:
				extra.append("[color=#fff2c8]подземный город[/color]")
			if c.monsters > 0.0:
				extra.append("чудовища %s" % NationPanel.fmt(c.monsters))
			if c.kind == &"ruins":
				extra.append("исследованы" if c.explored else "не исследованы")
			lines.append("   [url=%d]%s[/url] — %s (%s)" % [c.id, c.name, c.kind_name(), ", ".join(extra)])
	_list.text = "\n".join(lines)


func _draw_map() -> void:
	var world := WorldState.world
	if world == null:
		return
	var size := _map_view.size
	_map_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.05))
	var map := world.map
	var k := minf(size.x / map.width, size.y / map.height)
	var off := (size - Vector2(map.width, map.height) * k) * 0.5
	var to_view := func(cell: int) -> Vector2: return off + (Vector2(map.cell_pos(cell)) + Vector2(0.5, 0.5)) * k
	for c in world.caves:
		for nb in c.neighbors:
			if nb > c.id:
				var shade := 0.85 - 0.12 * maxf(c.depth, world.caves[nb].depth)
				_map_view.draw_line(to_view.call(c.cell), to_view.call(world.caves[nb].cell), Color(shade, shade * 0.85, shade * 0.6), 1.5, true)
	for c in world.caves:
		var p: Vector2 = to_view.call(c.cell)
		var r := 2.5 + c.depth * 1.5
		_map_view.draw_circle(p, r, MapOverlay.CAVE_COLORS.get(c.kind, Color.GRAY))
		if c.owner >= 0:
			_map_view.draw_arc(p, r + 2.0, 0.0, TAU, 16, world.nations[c.owner].color.lightened(0.2), 1.5)
		if c.entrance:
			_map_view.draw_arc(p + Vector2(0, -r - 3.0), 3.0, PI, TAU, 8, Color(0.95, 0.9, 0.8), 1.5)
