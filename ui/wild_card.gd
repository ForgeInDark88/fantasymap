class_name WildCard
extends PanelContainer
## Карточка дикого края и дорог (клик по значку логова, племени, каравана или
## отряда наёмников): кто это, сила, где; «К месту» — плавный перелёт камеры.

const REFRESH_MS := 500

var _entity: RefCounted
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
	go.text = "К месту"
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(func() -> void:
		var c := _cell()
		if c >= 0:
			EventBus.focus_cell.emit(c))
	row.add_child(go)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: EventBus.wild_selected.emit(null))
	row.add_child(close)
	box.add_child(row)
	UiAnim.attach(self, Vector2(0, -8))
	EventBus.wild_selected.connect(func(e: RefCounted) -> void:
		_entity = e
		if e == null:
			UiAnim.hide(self)
		else:
			visible = true
			refresh())
	EventBus.army_selected.connect(func(a: Army) -> void:
		if a != null:
			_entity = null
			visible = false)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_entity = null
		visible = false)


func _cell() -> int:
	var world := WorldState.world
	if _entity is Tribe:
		return (_entity as Tribe).cell
	if _entity is Lair and world != null:
		var l := _entity as Lair
		return l.cell if l.region == l.home else world.regions[l.region].center
	if _entity is MercCompany:
		return (_entity as MercCompany).cell
	if _entity is Caravan and world != null:
		return world.cities[(_entity as Caravan).from_city].cell
	return -1


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_ms > REFRESH_MS:
		refresh()


func refresh() -> void:
	_last_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null or _entity == null:
		return
	var lines: Array[String] = []
	if _entity is Lair:
		var l := _entity as Lair
		lines.append("[font_size=16][b]%s[/b][/font_size]" % l.label())
		lines.append("[color=#b8b0a8]%s[/color]" % l.def.description)
		if not l.alive:
			lines.append("[color=#8a90a0]%s[/color]" % ("Уснуло." if l.slain_by == "сон" else "Разорено: %s." % l.slain_by))
		else:
			lines.append("Сила: [b]%s[/b] · набегов: %d · с %d г." % [ArmySystem._num(l.strength), l.raids, l.born])
			lines.append("Логово: край %s" % world.region_label(l.cell, "дикие земли"))
			if l.region != l.home:
				lines.append("Сейчас бродит: край %s" % world.regions[l.region].name)
			lines.append("Добыча за победу: %d золота" % roundi(l.def.loot))
	elif _entity is Tribe:
		var t := _entity as Tribe
		lines.append("[font_size=16][b]%s[/b][/font_size]" % t.label())
		lines.append("%s · народ: %s%s" % [t.def.display_name, t.race.display_name.to_lower(), " · [color=#ff9a6a]орда[/color]" if t.horde else ""])
		lines.append("[color=#b8b0a8]%s[/color]" % t.def.description)
		if not t.alive:
			lines.append("[color=#8a90a0]Племени больше нет: осело, растворилось в державе или ушло.[/color]")
		else:
			lines.append("Воинов: [b]%s[/b] · набегов: %d · с %d г." % [ArmySystem._num(t.strength), t.raids, t.born])
			lines.append("Край: %s" % world.region_label(t.cell, "дикие земли"))
			if t.def.nomad:
				var need := t.def.found_strength if t.horde else t.def.horde_strength
				lines.append("%s: %d%%" % ["До своего государства" if t.horde else "До орды", mini(100, roundi(t.strength / need * 100.0))])
	elif _entity is Caravan:
		var c := _entity as Caravan
		var g: GoodDef = MarketDB.all()[c.good]
		lines.append("[font_size=16][b]Караван: %s[/b][/font_size]" % g.display_name)
		lines.append("%s → %s (%s → %s)" % [world.cities[c.from_city].name, world.cities[c.to_city].name,
			world.nations[c.from_nation].short_name, world.nations[c.to_nation].short_name])
		if not c.alive:
			lines.append("[color=#8a90a0]%s[/color]" % ("Разграблен." if c.robbed else "Дошёл."))
		else:
			lines.append("Груз: %s ед. · цена у отправителя %.2f, у получателя %.2f" % [ArmySystem._num(c.amount), c.price,
				world.nations[c.to_nation].market_price[c.good] if world.nations[c.to_nation].market_price.size() > c.good else 0.0])
			lines.append("В пути: месяц %d из %d · безопасность дороги %d%%" % [c.done + 1, c.months,
				roundi(world.roads[c.road].safety * 100.0) if c.road < world.roads.size() else 0])
	elif _entity is MercCompany:
		var m := _entity as MercCompany
		lines.append("[font_size=16][b]%s[/b][/font_size]" % m.name)
		lines.append("Наёмники · народ: %s" % m.race.display_name.to_lower())
		if not m.alive:
			lines.append("[color=#8a90a0]Отряд распался.[/color]")
		else:
			lines.append("Воинов: [b]%s[/b] · плата: %d золота в год · с %d г." % [ArmySystem._num(m.strength), roundi(m.wage), m.born])
			lines.append(("На службе у государства %s" % world.nations[m.employer].short_name) if m.employer >= 0 else "Вольный — ищет нанимателя среди воюющих")
			if m.unpaid > 0:
				lines.append("[color=#ff8a6a]Плату задерживают![/color]")
	_text.text = "\n".join(lines)
