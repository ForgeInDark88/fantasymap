extends CanvasLayer
## Интерфейс: управление временем, панель генерации мира, режимы карты,
## легенда, летопись, карточка выбранного государства и информация о клетке.
## Общается с остальной игрой только через EventBus.

## Максимальная высота списка легенды (доля высоты экрана); дальше — прокрутка.
const LEGEND_MAX_HEIGHT := 0.55
## Сколько последних записей летописи показывать в ленте.
const FEED_LINES := 7
## Как часто (мс) обновлять карточку и легенду во время симуляции.
const PANEL_REFRESH_MS := 300
const LEGEND_REFRESH_MS := 1000
const CHRONICLE_COLORS := {
	&"nation": "#f0d98a", &"city": "#9fd3ff", &"building": "#b8c4d0",
	&"ruler": "#d6b3ff", &"famine": "#ff9a7a",
	&"war": "#ff6b5b", &"siege": "#ff9580", &"conquest": "#ff8a5c", &"peace": "#9be39b",
	&"treaty": "#8fd0c8", &"vassal": "#c0a0ff", &"rebellion": "#ffb04a", &"collapse": "#ff7070",
	&"fall": "#d06060", &"colony": "#7fc8ff", &"plague": "#b8d070", &"disaster": "#e0a070",
	&"monsters": "#e08cc0", &"hero": "#ffe680", &"great": "#ffd24a", &"fate": "#e6b3ff", &"religion": "#f2e2a8", &"tech": "#a8e0ff", &"culture": "#ffc8e8",
	&"intrigue": "#c8a0e0", &"org": "#9fd8c0", &"legacy": "#e0c090", &"trade": "#f0c870", &"climate": "#b0d8e8",
}

@onready var _mode_buttons: HBoxContainer = %ModeButtons
@onready var _panel_buttons: HBoxContainer = %PanelButtons
@onready var _gen_panel: PanelContainer = %GenPanel
@onready var _seed_edit: LineEdit = %SeedEdit
@onready var _random_seed: Button = %RandomSeedButton
@onready var _size_option: OptionButton = %SizeOption
@onready var _land_slider: HSlider = %LandSlider
@onready var _land_value: Label = %LandValue
@onready var _continents_spin: SpinBox = %ContinentsSpin
@onready var _river_slider: HSlider = %RiverSlider
@onready var _river_value: Label = %RiverValue
@onready var _climate_slider: HSlider = %ClimateSlider
@onready var _climate_value: Label = %ClimateValue
@onready var _nations_spin: SpinBox = %NationsSpin
@onready var _races_grid: GridContainer = %RacesGrid
@onready var _regen_button: Button = %RegenButton
@onready var _new_world_button: Button = %NewWorldButton
@onready var _status: Label = %StatusLabel
@onready var _legend: PanelContainer = %Legend
@onready var _legend_box: VBoxContainer = %LegendBox
@onready var _legend_title: Label = %LegendTitle
@onready var _legend_scroll: ScrollContainer = %LegendScroll
@onready var _cell_info: Label = %CellInfo
@onready var _nation_panel: NationPanel = %NationPanel
@onready var _time_controls: HBoxContainer = %TimeControls
@onready var _year_label: Label = %YearLabel
@onready var _toggle_chronicle: Button = %ToggleChronicleButton
@onready var _chronicle_feed: PanelContainer = %ChronicleFeed
@onready var _chronicle_text: RichTextLabel = %ChronicleText

var _mode := MapMode.POLITICAL
var _race_checks: Dictionary[StringName, CheckBox] = {}
var _mode_button_list: Array[Button] = []
var _speed_buttons: Array[Button] = []
## Левые панели: открыта максимум одна. Имя → [кнопка, панель].
var _left_panels: Dictionary = {}
var _clicked_cell := -1
var _fate_panel: FatePanel
var _saves_panel := SavesPanel.new()
var _fate_button: Button
var _chronicle_shown := -1
var _panel_refresh_ms := 0
var _legend_refresh_ms := 0


func _ready() -> void:
	for i in MapSettings.SIZE_PRESETS.size():
		var s := MapSettings.SIZE_PRESETS[i]
		_size_option.add_item("%s (%d×%d)" % [MapSettings.SIZE_NAMES[i], s.x, s.y], i)
	_size_option.select(MapSettings.DEFAULT_SIZE_PRESET)

	_build_mode_buttons()
	_build_race_checks()
	_build_time_controls()
	_build_left_panels()
	_toggle_chronicle.toggled.connect(func(on: bool) -> void:
		_chronicle_feed.visible = on and not (_left_panels["Летопись"][1] as Control).visible)
	_land_slider.value_changed.connect(func(v: float) -> void: _land_value.text = "%d%%" % v)
	_river_slider.value_changed.connect(func(v: float) -> void: _river_value.text = "%d%%" % v)
	_climate_slider.value_changed.connect(func(v: float) -> void: _climate_value.text = "%+d" % v if v != 0 else "0")
	_regen_button.pressed.connect(_request_generation)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _request_generation())
	_random_seed.pressed.connect(_randomize_seed)
	_new_world_button.pressed.connect(func() -> void:
		_randomize_seed()
		_request_generation())
	_nation_panel.close_requested.connect(EventBus.nation_selected.emit.bind(-1))

	EventBus.generation_started.connect(_on_generation_started)
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.cell_hovered.connect(_on_cell_hovered)
	EventBus.nation_selected.connect(_on_nation_selected)
	EventBus.cell_clicked.connect(func(cell: int) -> void: _clicked_cell = cell)
	EventBus.year_passed.connect(_on_year_passed)
	EventBus.speed_changed.connect(_on_speed_changed)
	EventBus.map_mode_changed.connect(func(mode: int) -> void:
		_mode = mode
		# button_pressed шлёт только toggled (не pressed), а ButtonGroup снимет остальные кнопки.
		_mode_button_list[mode].button_pressed = true
		_rebuild_legend())
	_rebuild_legend()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		EventBus.nation_selected.emit(-1)
	elif key.keycode == KEY_SPACE:
		WorldState.toggle_pause()
	elif key.keycode == KEY_F5:
		_saves_panel.save_game(SavesPanel.QUICK_SAVE)
		_status.text = "Быстрое сохранение: " + WorldState.world.date_text() if WorldState.world != null else ""
	elif key.keycode == KEY_F9:
		_saves_panel.load_game(SavesPanel.QUICK_SAVE)
	# 1–9, 0, −, = — режимы карты.
	elif MapMode.HOTKEYS.find(key.keycode) >= 0 and MapMode.HOTKEYS.find(key.keycode) < MapMode.NAMES.size():
		EventBus.map_mode_changed.emit(MapMode.HOTKEYS.find(key.keycode))


func _build_mode_buttons() -> void:
	var group := ButtonGroup.new()
	for mode in MapMode.NAMES.size():
		var b := Button.new()
		b.text = MapMode.NAMES[mode]
		b.tooltip_text = "Клавиша %s" % MapMode.hotkey_label(mode)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = mode == _mode
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(EventBus.map_mode_changed.emit.bind(mode))
		_mode_buttons.add_child(b)
		_mode_button_list.append(b)


func _build_time_controls() -> void:
	var group := ButtonGroup.new()
	for i in WorldState.SPEEDS.size():
		var b := Button.new()
		b.text = WorldState.SPEED_NAMES[i]
		b.tooltip_text = "Пауза / продолжить — Пробел" if i == 0 else "%d дней в секунду" % roundi(WorldState.SPEEDS[i] * WorldState.DAYS_PER_SECOND)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == WorldState.speed_index
		b.pressed.connect(WorldState.set_speed.bind(i))
		_time_controls.add_child(b)
		_speed_buttons.append(b)
	for step_def in [["+день", "Прожить один день", 0], ["+мес.", "Прожить один месяц", 1], ["+год", "Прожить один год", 2]]:
		var step := Button.new()
		step.text = step_def[0]
		step.tooltip_text = step_def[1]
		step.focus_mode = Control.FOCUS_NONE
		var span: int = step_def[2]
		step.pressed.connect(func() -> void:
			WorldState.set_speed(0)
			if span == 0:
				WorldState.step_day()
			elif span == 1:
				WorldState.step_month()
			else:
				WorldState.step_year())
		_time_controls.add_child(step)


## Кнопки и сами левые панели: генерация мира, Бог, летопись, статистика, герои.
func _build_left_panels() -> void:
	var defs := [
		["Мир", "Генерация мира", _gen_panel],
		["Бог", "Панель Бога: вмешательство в историю", GodPanel.new()],
		["Летопись", "Полная летопись с фильтрами", ChroniclePanel.new()],
		["Статистика", "Графики по эпохам", StatsPanel.new()],
		["Герои", "Герои мира", HeroesPanel.new()],
		["Сохранения", "Сохранить или загрузить мир (F5 / F9)", _saves_panel],
	]
	var root: Control = _gen_panel.get_parent()
	for d in defs:
		var panel: Control = d[2]
		if panel.get_parent() == null:
			panel.position = _gen_panel.position
			panel.visible = false
			root.add_child(panel)
			# Левые панели — под лентой событий по z-порядку не важны: лента прячется, пока открыта летопись.
		var b := Button.new()
		b.text = d[0]
		b.tooltip_text = d[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(_on_left_panel_toggled.bind(d[0]))
		_panel_buttons.add_child(b)
		_left_panels[d[0]] = [b, panel]
	_left_panels["Мир"][0].button_pressed = true
	# Судьба — отдельная полноэкранная панель.
	_fate_panel = FatePanel.new()
	root.add_child(_fate_panel)
	root.add_child(HeroWindow.new())
	root.add_child(TechWindow.new())
	_fate_button = Button.new()
	_fate_button.text = "Судьба"
	_fate_button.tooltip_text = "Чертоги Судьбы: суд над павшими героями"
	_fate_button.focus_mode = Control.FOCUS_NONE
	_fate_button.pressed.connect(_fate_panel.open_panel)
	_panel_buttons.add_child(_fate_button)


func _on_left_panel_toggled(on: bool, panel_name: String) -> void:
	for key in _left_panels:
		var entry: Array = _left_panels[key]
		if key == panel_name:
			entry[1].visible = on
		elif on:
			entry[0].set_pressed_no_signal(false)
			entry[1].visible = false
	# Полная летопись заменяет ленту.
	_chronicle_feed.visible = _toggle_chronicle.button_pressed and not (_left_panels["Летопись"][1] as Control).visible


func _on_speed_changed(index: int) -> void:
	_speed_buttons[index].button_pressed = true


func _on_year_passed(year: int) -> void:
	_year_label.text = _date_line(WorldState.world) if WorldState.world != null else "Год %d" % year
	_refresh_chronicle()
	if WorldState.world != null:
		var n := WorldState.world.fate_queue.size()
		_fate_button.text = "Судьба (%d)" % n if n > 0 else "Судьба"
	var now := Time.get_ticks_msec()
	if _nation_panel.visible and now - _panel_refresh_ms >= PANEL_REFRESH_MS:
		_panel_refresh_ms = now
		_nation_panel.refresh(WorldState.world)
	if _mode in [MapMode.POLITICAL, MapMode.RACES, MapMode.RELIGION, MapMode.CULTURE, MapMode.TRADE] and now - _legend_refresh_ms >= LEGEND_REFRESH_MS:
		_legend_refresh_ms = now
		_rebuild_legend()


## Дата, время года и климатические беды.
func _date_line(world: World) -> String:
	var parts: Array[String] = [world.date_text(), ClimateSystem.season(world.month)]
	if world.ash_until > world.year:
		parts.append("пепельная зима")
	return " · ".join(parts)


## Последние записи летописи (полная летопись с фильтрами — этап 5).
func _refresh_chronicle() -> void:
	var world := WorldState.world
	if world == null or world.chronicle_total == _chronicle_shown:
		return
	_chronicle_shown = world.chronicle_total
	var lines: Array[String] = []
	var entries := world.chronicle.slice(maxi(0, world.chronicle.size() - FEED_LINES))
	entries.reverse()
	for e in entries:
		var color: String = CHRONICLE_COLORS.get(e.kind, "#dddddd")
		lines.append("[color=#8a90a0]%d[/color]  [color=%s]%s[/color]" % [e.year, color, e.text])
	_chronicle_text.text = "\n".join(lines)


func _build_race_checks() -> void:
	for race in RaceDB.all():
		if not race.spawn_at_start:
			continue  # наги и демоны приходят только через великие деяния
		var cb := CheckBox.new()
		cb.text = race.display_name
		cb.icon = race.icon
		cb.button_pressed = true
		cb.tooltip_text = race.description
		cb.add_theme_constant_override("icon_max_width", 18)
		_races_grid.add_child(cb)
		_race_checks[race.id] = cb


# ---------------------------------------------------------------------------
# Легенда
# ---------------------------------------------------------------------------

func _rebuild_legend() -> void:
	var scroll := _legend_scroll.scroll_vertical
	for child in _legend_box.get_children():
		_legend_box.remove_child(child)
		child.queue_free()
	var world := WorldState.world
	_legend_title.text = ""
	match _mode:
		MapMode.POLITICAL:
			if world != null:
				var nations: Array[Nation] = []
				for n in world.nations:
					if n.alive:
						nations.append(n)
				# Крупнейшие — сверху; список целиком, с прокруткой.
				nations.sort_custom(func(a: Nation, b: Nation) -> bool: return a.cell_count > b.cell_count)
				_legend_title.text = "Государства (%d)" % nations.size()
				for nation in nations:
					_legend_nation_row(nation)
		MapMode.RACES:
			_legend_title.text = "Расы"
			var counts := {}
			if world != null:
				for nation in world.nations:
					if nation.alive:
						counts[nation.race_id] = counts.get(nation.race_id, 0) + 1
			for race in RaceDB.all():
				_legend_row(race.color, race.icon, "%s — %d" % [race.display_name, counts.get(race.id, 0)], race.description)
		MapMode.POPULATION:
			_legend_title.text = "Плотность населения"
			var steps := [["пусто", Color(0.16, 0.12, 0.25)], ["редко", Color(0.45, 0.15, 0.4)],
				["средне", Color(0.85, 0.3, 0.2)], ["густо", Color(0.98, 0.75, 0.25)], ["города и долины рек", Color(1.0, 1.0, 0.85)]]
			for st in steps:
				_legend_row(st[1], null, st[0], "")
			_legend_row(Color(0.2, 0.21, 0.22), null, "ничья земля", "")
		MapMode.RESOURCES:
			_legend_title.text = "Ресурсы"
			for dep in EconomyDB.deposits():
				_legend_row(dep.color, null, "%s (+%s %s)" % [dep.display_name, str(dep.amount), Goods.NAMES[Goods.index_of(dep.goods)].to_lower()], "")
			_legend_row(Color(0.25, 0.55, 0.2), null, "лес — дерево", "")
			_legend_row(Color(0.65, 0.65, 0.7), null, "камень", "")
			_legend_row(Color(0.45, 0.55, 0.8), null, "руда в горах", "")
		MapMode.RELIGION:
			_legend_title.text = "Религии"
			if world != null:
				var regions := {}
				var states := {}
				for region in world.regions:
					var r := region.main_faith()
					if r >= 0:
						regions[r] = regions.get(r, 0) + 1
				for n in world.nations:
					if n.alive and n.state_religion >= 0:
						states[n.state_religion] = states.get(n.state_religion, 0) + 1
				var ids := regions.keys()
				ids.sort_custom(func(a: int, b: int) -> bool: return regions[a] > regions[b])
				for id in ids:
					var faith := world.religions[id]
					var tip := "%s\nДогматы: %s\nМиссионерство %.0f%%, терпимость %.0f%%, рвение %.0f%%" % [
						faith.def.description if faith.def != null and not faith.is_heresy() else "Ответвление веры «%s» (%d г.)" % [world.religions[faith.parent].name, faith.founded_year] if faith.is_heresy() else "",
						", ".join(faith.dogmas), faith.missionary * 100.0, faith.tolerance * 100.0, faith.zeal * 100.0]
					_legend_row(faith.color, faith.icon(), "%s %s — регионов %d, держав %d" % [faith.symbol, faith.name, regions[id], states.get(id, 0)], tip)
		MapMode.CULTURE:
			_legend_title.text = "Культуры"
			if world != null:
				var regions := {}
				for region in world.regions:
					if region.culture >= 0:
						regions[region.culture] = regions.get(region.culture, 0) + 1
				var ids := regions.keys()
				ids.sort_custom(func(a: int, b: int) -> bool: return regions[a] > regions[b])
				for id in ids.slice(0, 40):
					var c := world.cultures[id]
					var race := RaceDB.by_index(c.race)
					_legend_row(c.color, race.icon, "%s — регионов %d" % [c.name, regions[id]],
						"Культура %s (%s), с %d г.\nОбычаи: %s" % [c.name, race.display_name.to_lower(), c.founded_year, ", ".join(c.customs)])
		MapMode.TRADE:
			_legend_title.text = "Торговые пути"
			if world != null:
				var land := 0
				var sea := 0
				var traffic := 0.0
				var unsafe := 0
				for r in world.roads:
					if r.alive:
						if r.sea:
							sea += 1
						else:
							land += 1
						traffic += r.traffic
						if r.safety < 0.6:
							unsafe += 1
				_legend_row(Color(0.95, 0.75, 0.3), null, "дороги — %d" % land, "Толщина — торговый оборот за год")
				_legend_row(Color(0.5, 0.8, 1.0), null, "морские пути — %d" % sea, "Между портами (гаванями)")
				_legend_row(Color(0.9, 0.35, 0.3), null, "опасные пути — %d" % unsafe, "Разбойники и пираты снижают доход")
				_legend_row(Color(0.8, 0.8, 0.8), null, "оборот: %s золота в год" % NationPanel.fmt(traffic), "")
		MapMode.BIOMES:
			_legend_title.text = "Биомы"
			for def in BiomeDB.all():
				_legend_row(def.color, null, def.display_name, "")
	_legend.visible = _legend_box.get_child_count() > 0 and not _nation_panel.visible
	_fit_legend_scroll.call_deferred(scroll)


## Высота прокрутки = высоте содержимого, но не больше доли экрана.
func _fit_legend_scroll(scroll: int) -> void:
	var content := _legend_box.get_combined_minimum_size()
	var max_h := get_viewport().get_visible_rect().size.y * LEGEND_MAX_HEIGHT
	_legend_scroll.custom_minimum_size = Vector2(content.x + 12.0, minf(content.y, max_h))
	_legend_scroll.scroll_vertical = scroll
	# Схлопываем панель в угол — с grow = BEGIN она вырастет вверх-влево ровно под содержимое.
	_legend.offset_left = _legend.offset_right
	_legend.offset_top = _legend.offset_bottom


func _legend_row(color: Color, icon: Texture2D, text: String, tooltip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.tooltip_text = tooltip
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	if icon != null:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.custom_minimum_size = Vector2(16, 16)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	_legend_box.add_child(row)
	return row


## Строка государства — кнопка: клик выбирает государство.
func _legend_nation_row(nation: Nation) -> void:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = nation.short_name
	button.icon = nation.race.icon
	button.add_theme_constant_override("icon_max_width", 16)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", nation.color.lightened(0.35))
	button.tooltip_text = "%s (%s)" % [nation.name, nation.race.display_name]
	button.pressed.connect(EventBus.nation_selected.emit.bind(nation.id))
	_legend_box.add_child(button)


# ---------------------------------------------------------------------------
# Генерация
# ---------------------------------------------------------------------------

## Собирает MapSettings из полей панели и просит мир сгенерироваться.
func _request_generation() -> void:
	var s := MapSettings.new()
	s.world_seed = _parse_seed(_seed_edit.text)
	s.apply_size_preset(_size_option.get_selected_id())
	s.land_fraction = _land_slider.value / 100.0
	s.continents = int(_continents_spin.value)
	s.river_density = _river_slider.value / 100.0
	s.temperature_bias = _climate_slider.value / 100.0
	s.nation_count = int(_nations_spin.value)
	var enabled: Array[StringName] = []
	for id in _race_checks:
		if _race_checks[id].button_pressed:
			enabled.append(id)
	# Все отмечены — оставляем список пустым (так новые расы из data/ включаются автоматически).
	if enabled.size() != _race_checks.size():
		s.enabled_races = enabled
	if enabled.is_empty():
		s.nation_count = 0
	EventBus.generate_requested.emit(s)


## Seed может быть числом или любым словом («Арда» → хэш).
static func _parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		return randi_range(1, 999999)
	if t.is_valid_int():
		return absi(t.to_int())
	return hash(t) & 0x7fffffff


func _randomize_seed() -> void:
	_seed_edit.text = str(randi_range(1, 999999))


func _on_generation_started() -> void:
	_regen_button.disabled = true
	_new_world_button.disabled = true
	_status.text = "Генерация мира…"


func _on_world_generated(world: World, elapsed_ms: int) -> void:
	_regen_button.disabled = false
	_new_world_button.disabled = false
	# Синхронизируем поля с фактическими настройками мира (например, при первом запуске).
	var s := world.settings
	if _parse_seed(_seed_edit.text) != s.world_seed:
		_seed_edit.text = str(s.world_seed)
	var preset := s.size_preset_index()
	if preset >= 0:
		_size_option.select(preset)
	_land_slider.value = roundf(s.land_fraction * 100.0)
	_continents_spin.value = s.continents
	_river_slider.value = roundf(s.river_density * 100.0)
	_climate_slider.value = roundf(s.temperature_bias * 100.0)
	_nations_spin.value = s.nation_count
	_status.text = "Мир %d×%d: %d государств, %d городов. %s за %.2f с" % [
		world.map.width, world.map.height, world.nations.size(), world.cities.size(),
		"Создан" if world.year <= 0 else "Загружен (%s)" % world.date_text(), elapsed_ms / 1000.0]
	_nation_panel.hide()
	_year_label.text = _date_line(world)
	_chronicle_shown = -1
	_refresh_chronicle()
	_rebuild_legend()


func _on_nation_selected(nation_id: int) -> void:
	var world := WorldState.world
	if world == null or nation_id < 0:
		_nation_panel.hide()
	else:
		_nation_panel.show_nation(world, world.nations[nation_id], _clicked_cell)
		_clicked_cell = -1
	# Карточка и легенда делят правый край экрана.
	_legend.visible = not _nation_panel.visible and _legend_box.get_child_count() > 0


func _on_cell_hovered(cell: int) -> void:
	var world := WorldState.world
	if cell < 0 or world == null:
		_cell_info.text = "Наведите курсор на карту"
		return
	var map := world.map
	var p := map.cell_pos(cell)
	var parts: Array[String] = []
	var city := world.city_at(cell)
	if city != null:
		parts.append("%s%s — %s, %s (%s жит.)" % ["★ " if city.is_capital else "", city.name,
				city.tier_name().to_lower(), city.specialization(), NationPanel.fmt(city.population)])
	var nation := world.nation_at(cell)
	if nation != null:
		parts.append("%s (%s)" % [nation.name, nation.race.display_name])
	var region := world.region_at(cell)
	if region != null and not region.name.is_empty():
		var region_text := "регион %s" % region.name
		if nation != null:
			region_text += " (%s жит., лояльность %d%%)" % [
				NationPanel.fmt(world.region_population(region, nation.id)), roundi(region.loyalty * 100.0)]
		var people := world.cell_race[cell]
		if people != World.NO_RACE and nation != null and people != nation.race.index:
			region_text += ", живут %s" % RaceDB.by_index(people).display_name.to_lower()
		parts.append(region_text)
	parts.append(BiomeDB.get_def(map.biome[cell]).display_name)
	var dep := world.deposit_at(cell)
	if dep != null:
		parts.append("месторождение: " + dep.display_name)
	if map.is_land(cell):
		parts.append("%d м" % roundi(map.altitude_meters(cell)))
	else:
		parts.append("глубина %d м" % roundi(-map.altitude_meters(cell)) if map.elevation[cell] < 0.0 else "пресная вода")
	parts.append("%+d °C" % roundi(map.temperature_celsius(cell)))
	parts.append("влажность %d%%" % roundi(map.moisture[cell] * 100.0))
	if map.river[cell] > 0:
		parts.append(["", "ручей", "река", "великая река"][map.river[cell]])
	parts.append("(%d, %d)" % [p.x, p.y])
	_cell_info.text = "  ·  ".join(parts)
