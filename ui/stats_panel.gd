class_name StatsPanel
extends PanelContainer
## Статистика мира: сводка и графики по эпохам (World.history).

const VIEWS: Array[String] = ["Население рас", "Площадь государств", "Население государств"]
const TOP := 8

var _summary: RichTextLabel
var _chart: LineChart
var _view := 0
var _last_refresh_ms := 0


func _init() -> void:
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Статистика"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_summary)
	var tabs := HBoxContainer.new()
	var group := ButtonGroup.new()
	for i in VIEWS.size():
		var b := Button.new()
		b.text = VIEWS[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_view = i
			_refresh())
		tabs.add_child(b)
	box.add_child(tabs)
	_chart = LineChart.new()
	box.add_child(_chart)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_refresh_ms > 1500:
		_refresh()


func _refresh() -> void:
	_last_refresh_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null:
		return
	var alive := 0
	var pop := 0.0
	var cities := 0
	for n in world.nations:
		if n.alive:
			alive += 1
			pop += n.population
			cities += n.city_ids.size()
	var heroes := 0
	for h in world.heroes:
		if h.alive and not h.is_ruler:
			heroes += 1
	_summary.text = "[b]%s[/b] · государств: %d (всего было %d) · население: %s · городов: %d\nИдёт войн: %d (всего было %d) · героев: %d · записей летописи: %d · месяц симулируется за %.2f мс" % [
		world.date_text(), alive, world.nations.size(), NationPanel.fmt(pop), cities,
		world.diplomacy.wars.size(), world.diplomacy.wars.size() + world.diplomacy.past_wars.size(),
		heroes, world.chronicle_total, WorldState.avg_tick_ms]
	var series: Array[Dictionary] = []
	if _view == 0:
		for race in RaceDB.all():
			var pts := PackedVector2Array()
			for snap in world.history:
				pts.append(Vector2(snap.year, snap.races[race.index]))
			series.append({"name": race.display_name, "color": race.color, "points": pts})
	else:
		var metric := 1 if _view == 1 else 0
		# Топ государств по текущему показателю (среди живых) + павшие гиганты прошлого не нужны.
		var nations: Array[Nation] = []
		for n in world.nations:
			if n.alive:
				nations.append(n)
		nations.sort_custom(func(a: Nation, b: Nation) -> bool:
			return (a.cell_count if metric == 1 else a.population) > (b.cell_count if metric == 1 else b.population))
		for n in nations.slice(0, TOP):
			var pts := PackedVector2Array()
			for snap in world.history:
				if snap.nations.has(n.id):
					pts.append(Vector2(snap.year, snap.nations[n.id][metric]))
			series.append({"name": n.short_name, "color": n.color, "points": pts})
	_chart.set_series(series)
