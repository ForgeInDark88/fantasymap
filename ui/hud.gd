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
}

@onready var _mode_buttons: HBoxContainer = %ModeButtons
@onready var _toggle_gen: Button = %ToggleGenButton
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

	_toggle_gen.toggled.connect(func(on: bool) -> void: _gen_panel.visible = on)
	_toggle_chronicle.toggled.connect(func(on: bool) -> void: _chronicle_feed.visible = on)
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
	# 1..6 — режимы карты.
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + MapMode.NAMES.size():
		EventBus.map_mode_changed.emit(key.keycode - KEY_1)


func _build_mode_buttons() -> void:
	var group := ButtonGroup.new()
	for mode in MapMode.NAMES.size():
		var b := Button.new()
		b.text = MapMode.NAMES[mode]
		b.tooltip_text = "Клавиша %d" % (mode + 1)
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
		b.tooltip_text = "Пауза / продолжить — Пробел" if i == 0 else "%s лет в секунду" % str(WorldState.SPEEDS[i] * WorldState.YEARS_PER_SECOND)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == WorldState.speed_index
		b.pressed.connect(WorldState.set_speed.bind(i))
		_time_controls.add_child(b)
		_speed_buttons.append(b)
	var step := Button.new()
	step.text = "+1 год"
	step.tooltip_text = "Прожить один год"
	step.focus_mode = Control.FOCUS_NONE
	step.pressed.connect(func() -> void:
		WorldState.set_speed(0)
		WorldState.step_once())
	_time_controls.add_child(step)


func _on_speed_changed(index: int) -> void:
	_speed_buttons[index].button_pressed = true


func _on_year_passed(year: int) -> void:
	_year_label.text = "Год %d" % year
	_refresh_chronicle()
	var now := Time.get_ticks_msec()
	if _nation_panel.visible and now - _panel_refresh_ms >= PANEL_REFRESH_MS:
		_panel_refresh_ms = now
		_nation_panel.refresh(WorldState.world)
	if (_mode == MapMode.POLITICAL or _mode == MapMode.RACES) and now - _legend_refresh_ms >= LEGEND_REFRESH_MS:
		_legend_refresh_ms = now
		_rebuild_legend()


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
	_status.text = "Мир %d×%d: %d государств, %d городов. Создан за %.2f с" % [
		world.map.width, world.map.height, world.nations.size(), world.cities.size(), elapsed_ms / 1000.0]
	_nation_panel.hide()
	_year_label.text = "Год %d" % world.year
	_chronicle_shown = -1
	_refresh_chronicle()
	_rebuild_legend()


func _on_nation_selected(nation_id: int) -> void:
	var world := WorldState.world
	if world == null or nation_id < 0:
		_nation_panel.hide()
	else:
		_nation_panel.show_nation(world, world.nations[nation_id])
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
		parts.append("%s%s (%s жит.)" % ["★ " if city.is_capital else "● ", city.name, NationPanel.fmt(city.population)])
	var nation := world.nation_at(cell)
	if nation != null:
		parts.append("%s (%s)" % [nation.name, nation.race.display_name])
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
