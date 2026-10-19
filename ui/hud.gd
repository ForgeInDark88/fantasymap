extends CanvasLayer
## Интерфейс этапа 1: панель генерации, переключатель режимов карты,
## легенда биомов и информация о клетке под курсором.
## Общается с остальной игрой только через EventBus.

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
@onready var _regen_button: Button = %RegenButton
@onready var _new_world_button: Button = %NewWorldButton
@onready var _status: Label = %StatusLabel
@onready var _legend: PanelContainer = %Legend
@onready var _legend_box: VBoxContainer = %LegendBox
@onready var _cell_info: Label = %CellInfo


func _ready() -> void:
	for i in MapSettings.SIZE_PRESETS.size():
		var s := MapSettings.SIZE_PRESETS[i]
		_size_option.add_item("%s (%d×%d)" % [MapSettings.SIZE_NAMES[i], s.x, s.y], i)
	_size_option.select(MapSettings.DEFAULT_SIZE_PRESET)

	_build_mode_buttons()
	_build_legend()

	_toggle_gen.toggled.connect(func(on: bool) -> void: _gen_panel.visible = on)
	_land_slider.value_changed.connect(func(v: float) -> void: _land_value.text = "%d%%" % v)
	_river_slider.value_changed.connect(func(v: float) -> void: _river_value.text = "%d%%" % v)
	_climate_slider.value_changed.connect(func(v: float) -> void: _climate_value.text = "%+d" % v if v != 0 else "0")
	_regen_button.pressed.connect(_request_generation)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _request_generation())
	_random_seed.pressed.connect(_randomize_seed)
	_new_world_button.pressed.connect(func() -> void:
		_randomize_seed()
		_request_generation())

	EventBus.generation_started.connect(_on_generation_started)
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.cell_hovered.connect(_on_cell_hovered)
	EventBus.map_mode_changed.connect(func(mode: int) -> void: _legend.visible = mode == MapMode.BIOMES)


func _build_mode_buttons() -> void:
	var group := ButtonGroup.new()
	for mode in MapMode.NAMES.size():
		var b := Button.new()
		b.text = MapMode.NAMES[mode]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = mode == MapMode.BIOMES
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(EventBus.map_mode_changed.emit.bind(mode))
		_mode_buttons.add_child(b)


func _build_legend() -> void:
	var title := Label.new()
	title.text = "Биомы"
	_legend_box.add_child(title)
	for def in BiomeDB.all():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.color = def.color
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.text = def.display_name
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(swatch)
		row.add_child(label)
		_legend_box.add_child(row)


## Собирает MapSettings из полей панели и просит мир сгенерироваться.
func _request_generation() -> void:
	var s := MapSettings.new()
	s.world_seed = _parse_seed(_seed_edit.text)
	s.apply_size_preset(_size_option.get_selected_id())
	s.land_fraction = _land_slider.value / 100.0
	s.continents = int(_continents_spin.value)
	s.river_density = _river_slider.value / 100.0
	s.temperature_bias = _climate_slider.value / 100.0
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


func _on_world_generated(map: WorldMap, elapsed_ms: int) -> void:
	_regen_button.disabled = false
	_new_world_button.disabled = false
	# Синхронизируем поля с фактическими настройками мира (например, при первом запуске).
	var s := map.settings
	if _parse_seed(_seed_edit.text) != s.world_seed:
		_seed_edit.text = str(s.world_seed)
	var preset := s.size_preset_index()
	if preset >= 0:
		_size_option.select(preset)
	_land_slider.value = roundf(s.land_fraction * 100.0)
	_continents_spin.value = s.continents
	_river_slider.value = roundf(s.river_density * 100.0)
	_climate_slider.value = roundf(s.temperature_bias * 100.0)
	_status.text = "Мир %d×%d создан за %.2f с" % [map.width, map.height, elapsed_ms / 1000.0]


func _on_cell_hovered(cell: int) -> void:
	var map := WorldState.map
	if cell < 0 or map == null:
		_cell_info.text = "Наведите курсор на карту"
		return
	var p := map.cell_pos(cell)
	var parts: Array[String] = [
		"(%d, %d)" % [p.x, p.y],
		BiomeDB.get_def(map.biome[cell]).display_name,
	]
	if map.is_land(cell):
		parts.append("%d м" % roundi(map.altitude_meters(cell)))
	else:
		parts.append("глубина %d м" % roundi(-map.altitude_meters(cell)) if map.elevation[cell] < 0.0 else "пресная вода")
	parts.append("%+d °C" % roundi(map.temperature_celsius(cell)))
	parts.append("влажность %d%%" % roundi(map.moisture[cell] * 100.0))
	if map.river[cell] > 0:
		parts.append(["", "ручей", "река", "великая река"][map.river[cell]])
	_cell_info.text = "  ·  ".join(parts)
