class_name MarketWindow
extends Control
## Окно «Рынок» (этап 11.D): слева — мировой рынок (средние цены к базовой,
## производство и спрос по миру, лучшие производители, караваны в пути,
## наёмники и займы); справа — рынок выбранного государства: товары (запас,
## цена, сделано, нужно, ввоз и вывоз), сословия, рабство, индекс цен, долги,
## нанятые отряды. Обновляется на лету, пока открыто.

const REFRESH_MS := 700

var _world_text: RichTextLabel
var _nation_text: RichTextLabel
var _nation: OptionButton
var _nation_ids: Array[int] = []
var _selected := -1
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
	title.text = "Рынок"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_nation = OptionButton.new()
	_nation.custom_minimum_size = Vector2(260, 0)
	_nation.tooltip_text = "Чей рынок показать"
	_nation.item_selected.connect(func(i: int) -> void:
		_selected = _nation_ids[i] if i < _nation_ids.size() else -1
		refresh())
	header.add_child(_nation)
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
	_world_text = _column(cols)
	_nation_text = _column(cols)
	EventBus.market_window_requested.connect(open_window)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void: visible = false)


func _column(parent: Control) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(600, 620)
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
	var list := world.nations.filter(func(n: Nation) -> bool: return n.alive)
	list.sort_custom(func(a: Nation, b: Nation) -> bool: return a.population > b.population)
	for n in list:
		_nation.add_item(n.name)
		_nation_ids.append(n.id)
	if nation_id < 0 or not _nation_ids.has(nation_id):
		nation_id = _nation_ids[0] if not _nation_ids.is_empty() else -1
	_selected = nation_id
	if nation_id >= 0:
		_nation.select(_nation_ids.find(nation_id))
	refresh()


func refresh() -> void:
	_last_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null:
		return
	_world_text.text = world_text(world)
	_nation_text.text = nation_text(world, world.nations[_selected]) if _selected >= 0 else ""


static func _price_color(k: float) -> String:
	return "#ff8a6a" if k > 1.6 else ("#ffd24a" if k > 1.15 else ("#9be39b" if k < 0.8 else "#e0e0e0"))


static func world_text(world: World) -> String:
	var goods := MarketDB.all()
	var prices := MarketSystem.world_prices(world)
	var made := PackedFloat32Array()
	made.resize(goods.size())
	var demand := PackedFloat32Array()
	demand.resize(goods.size())
	var top: Array = []
	top.resize(goods.size())
	for i in goods.size():
		top[i] = [-1, 0.0]
	for n in world.nations:
		if not n.alive or n.market_made.size() != goods.size():
			continue
		for i in goods.size():
			made[i] += n.market_made[i]
			demand[i] += n.market_demand[i]
			if n.market_made[i] > top[i][1]:
				top[i] = [n.id, n.market_made[i]]
	var lines: Array[String] = ["[b]Мировой рынок[/b] — средняя цена (к обычной), сделано / нужно за год, главный производитель", ""]
	for i in goods.size():
		var g: GoodDef = goods[i]
		var k := prices[i] / g.base_price
		var who: String = world.nations[top[i][0]].short_name if int(top[i][0]) >= 0 else "—"
		lines.append("[color=#%s]■[/color] [b]%s[/b]: [color=%s]%.2f[/color] (×%.2f) · %s / %s · %s" % [g.color.to_html(false), g.display_name,
			_price_color(k), prices[i], k, ArmySystem._num(made[i]), ArmySystem._num(demand[i]), who])
	lines.append("")
	var transit := 0
	for c in world.caravans:
		if c.alive:
			transit += 1
	lines.append("Караванов в пути: [b]%d[/b] · дошло за историю: %d · разграблено: %d" % [transit, world.counters.get(&"caravans_arrived", 0),
		world.counters.get(&"caravans_robbed", 0)])
	var free := 0
	var hired := 0
	for m in world.mercs:
		if m.alive:
			if m.employer >= 0:
				hired += 1
			else:
				free += 1
	lines.append("Наёмные отряды: на службе %d, вольных %d" % [hired, free])
	lines.append("Займов: %d · дефолтов за историю: %d" % [world.loans.size(), world.counters.get(&"defaults", 0)])
	var slavers := world.nations.filter(func(n: Nation) -> bool: return n.alive and n.slavery).size()
	lines.append("Рабство дозволено: в %d державах · восстаний рабов: %d · отмен: %d" % [slavers, world.counters.get(&"slave_revolts", 0),
		world.counters.get(&"abolitions", 0)])
	return "\n".join(lines)


static func nation_text(world: World, n: Nation) -> String:
	var goods := MarketDB.all()
	if n.market_price.size() != goods.size():
		return "[b]%s[/b]\nРынок ещё не открыт (первый год государства)." % n.name
	var lines: Array[String] = ["[b]%s[/b] — запас · цена · сделано / нужно · ввоз / вывоз" % n.name, ""]
	for i in goods.size():
		var g: GoodDef = goods[i]
		var k := n.market_price[i] / g.base_price
		var short := n.market_demand[i] > 0.5 and n.market_used[i] < n.market_demand[i] * 0.8
		lines.append("[color=#%s]■[/color] %s%s: %s · [color=%s]%.2f[/color] · %s / %s · %s / %s" % [g.color.to_html(false), g.display_name,
			" [color=#ff8a6a](нехватка)[/color]" if short else "", ArmySystem._num(n.market_stock[i]), _price_color(k), n.market_price[i],
			ArmySystem._num(n.market_made[i]), ArmySystem._num(n.market_demand[i]), ArmySystem._num(n.market_in[i]), ArmySystem._num(n.market_out[i])])
	lines.append("")
	lines.append(class_line(n))
	lines.append("Рабство: %s · индекс цен: [b]%.2f[/b]" % ["дозволено" if n.slavery else "запрещено", n.inflation])
	lines.append("Казна: %d золота · долги: %d" % [roundi(n.stock[Goods.GOLD]), roundi(CreditSystem.debts_of(world, n.id))])
	for l in world.loans:
		if int(l.debtor) == n.id:
			lines.append("  должен «%s»: %d под %d%%%s" % [CreditSystem.lender_name(world, int(l.lender)), roundi(float(l.left)),
				roundi(float(l.rate) * 100.0), " — просрочка!" if int(l.missed) > 0 else ""])
		elif int(l.lender) == n.id:
			lines.append("  ему должно %s: %d" % [world.nations[int(l.debtor)].short_name, roundi(float(l.left))])
	for m in world.mercs:
		if m.alive and m.employer == n.id:
			lines.append("Наёмники: %s — %s воинов, плата %d в год" % [m.name, ArmySystem._num(m.strength), roundi(m.wage * n.inflation)])
	return "\n".join(lines)


static func class_line(n: Nation) -> String:
	var parts: Array[String] = []
	for k in 4:
		if n.classes[k] >= 0.005:
			parts.append("%s %d%%" % [MarketSystem.CLASS_NAMES[k], roundi(n.classes[k] * 100.0)])
	return "Сословия: " + ", ".join(parts)
