extends Node2D
## Корневая сцена: связывает камеру, рендер карты и ввод мыши с EventBus.
## Игровой логики здесь нет — она в WorldState/World/Simulation; инструменты
## панели Бога — в GodTools.

@onready var _renderer: MapRenderer = $MapRenderer
@onready var _camera: MapCamera = $MapCamera

var _hovered_cell := -1
var _last_map_size := Vector2i.ZERO
var _selected_nation := -1
## Активный инструмент панели Бога (&"" — обычный выбор государства).
var _tool: StringName = &""
var _tool_params: Dictionary = {}


func _ready() -> void:
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.nation_selected.connect(func(id: int) -> void: _selected_nation = id)
	EventBus.god_tool_changed.connect(func(tool: StringName, params: Dictionary) -> void:
		_tool = tool
		_tool_params = params)
	EventBus.focus_cell.connect(_focus)
	_camera.map_clicked.connect(_on_map_clicked)

	var settings := MapSettings.new()
	settings.world_seed = randi_range(1, 999999)
	EventBus.generate_requested.emit(settings)


func _process(_delta: float) -> void:
	var cell := _renderer.cell_at(get_global_mouse_position())
	if cell != _hovered_cell:
		_hovered_cell = cell
		EventBus.cell_hovered.emit(cell)


func _unhandled_input(event: InputEvent) -> void:
	# ПКМ без перетаскивания отменяет инструмент Бога.
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _tool != &"":
		EventBus.god_tool_changed.emit(&"", {})


## Клик по карте: инструмент Бога или выбор государства под курсором.
func _on_map_clicked(pos: Vector2) -> void:
	var cell := _renderer.cell_at(pos)
	var world := WorldState.world
	if world == null or cell < 0:
		EventBus.nation_selected.emit(-1)
		return
	if _tool != &"":
		_apply_tool(world, cell)
		return
	# Клик по значку героя — окно героя.
	var radius := 9.0 / _camera.zoom.x
	var best: Hero = null
	for h in world.wandering_heroes():
		if h.cell >= 0:
			var d := _renderer.cell_center(h.cell).distance_to(pos)
			if d < radius:
				radius = d
				best = h
	if best != null:
		EventBus.hero_window_requested.emit(best.id)
		return
	EventBus.cell_clicked.emit(cell)
	EventBus.nation_selected.emit(world.owner[cell])


func _apply_tool(world: World, cell: int) -> void:
	match _tool:
		&"create_nation":
			var nation := GodTools.create_nation(world, _tool_params.race, cell)
			if nation != null:
				EventBus.nation_selected.emit(nation.id)
		&"event":
			GodTools.trigger_event(world, WorldState.simulation, _tool_params.event, cell)
		&"war":
			GodTools.declare_war(world, _selected_nation, world.owner[cell])
		&"raise":
			GodTools.reshape(world, cell, _tool_params.get("radius", 3), 0.12)
		&"lower":
			GodTools.reshape(world, cell, _tool_params.get("radius", 3), -0.12)
		&"hero":
			GodTools.spawn_hero(world, cell)
		&"source":
			HeroSystem.power_source(world, null, cell)
		&"spy":
			var target := world.owner[cell]
			if _selected_nation >= 0 and target >= 0 and target != _selected_nation:
				SpySystem.run(world, world.nations[_selected_nation], world.nations[target], _tool_params.op)
		&"society":
			if world.owner[cell] >= 0 and world.region_of[cell] >= 0:
				SocietySystem.found(world, world.nations[world.owner[cell]], world.region_of[cell])
		&"org":
			if world.owner[cell] >= 0:
				if OrgSystem.try_form(world, _tool_params.org, world.nations[world.owner[cell]]) == null:
					world.log_event(&"org", "Призыв %s собрать организацию «%s» остался без ответа." % [
						world.nations[world.owner[cell]].name, _tool_params.org.display_name])
		&"eruption":
			GodTools.eruption(world, cell)
		&"drought":
			GodTools.drought(world, cell)
		&"invasion":
			UndergroundSystem.invasion(world, cell)
		&"ruin":
			GodTools.ancient_ruin(world, cell)
		&"road":
			GodTools.road_from(world, cell)
		&"collector":
			var o := world.owner[cell]
			if o >= 0 and world.nations[o].legacy >= 0:
				LegacySystem.set_collector(world, world.legacies[world.nations[o].legacy], world.nations[o])
		&"insight":
			if world.owner[cell] >= 0:
				GodTools.insight(world, world.nations[world.owner[cell]])
		&"assimilate":
			GodTools.assimilate(world, cell)
		&"religion":
			if world.owner[cell] >= 0:
				ReligionSystem.found_religion(world, world.nations[world.owner[cell]])
		&"heresy":
			if world.owner[cell] >= 0:
				ReligionSystem.start_heresy(world, world.nations[world.owner[cell]])
		&"portal":
			var demons := HeroSystem.open_portal(world, cell, null)
			if demons != null:
				EventBus.nation_selected.emit(demons.id)
		&"rebellion":
			var rebel := GodTools.incite_rebellion(world, cell)
			if rebel != null:
				EventBus.nation_selected.emit(rebel.id)
	# Мир изменился вне тика — обновить интерфейс.
	EventBus.year_passed.emit(world.year)


func _focus(cell: int) -> void:
	if cell < 0:
		return
	_camera.position = _renderer.cell_center(cell)
	_camera.zoom = Vector2.ONE * maxf(_camera.zoom.x, 2.0)


func _on_world_generated(world: World, _elapsed_ms: int) -> void:
	_hovered_cell = -2  # обновить подсказку для нового мира
	_selected_nation = -1
	var rect := _renderer.get_map_rect()
	_camera.bounds = rect
	# Камеру сбрасываем только если поменялся размер карты — при перегенерации
	# с тем же размером удобно сравнивать миры с одного ракурса.
	var size := Vector2i(world.map.width, world.map.height)
	if size != _last_map_size:
		_last_map_size = size
		_camera.fit_to(rect)
