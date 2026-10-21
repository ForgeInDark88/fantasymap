extends Node2D
## Корневая сцена: связывает камеру, рендер карты и ввод мыши с EventBus.
## Игровой логики здесь нет — она в WorldState/World/Simulation; инструменты
## панели Бога — в GodTools.

@onready var _renderer: MapRenderer = $MapRenderer
@onready var _camera: MapCamera = $MapCamera
@onready var _overlay: MapOverlay = $MapOverlay
## За каким героем следит камера (-1 — ни за каким).
var _follow_hero := -1

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
	EventBus.follow_hero_requested.connect(func(id: int) -> void:
		_follow_hero = id
		if id >= 0 and WorldState.world != null and id < WorldState.world.heroes.size() and WorldState.world.heroes[id].cell >= 0:
			_camera.fly_to(_overlay.hero_visual_pos(WorldState.world.heroes[id]), maxf(_camera.target_zoom, 2.0)))
	_camera.user_moved.connect(func() -> void: _follow_hero = -1)
	_camera.map_clicked.connect(_on_map_clicked)

	var settings := MapSettings.new()
	settings.world_seed = randi_range(1, 999999)
	EventBus.generate_requested.emit(settings)


func _process(_delta: float) -> void:
	# Слежение за героем: камера едет за его плавно движущимся значком.
	var world := WorldState.world
	if _follow_hero >= 0 and world != null and _follow_hero < world.heroes.size():
		var h := world.heroes[_follow_hero]
		if not h.alive or h.is_ruler or h.cell < 0:
			_follow_hero = -1
		else:
			_camera.follow(_overlay.hero_visual_pos(h))
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
	# Клик по значку армии — карточка армии.
	var arad := 10.0 / _camera.zoom.x
	var army: Army = null
	for a in world.armies:
		if a.alive and a.cell >= 0:
			var d := _overlay.army_visual_pos(a).distance_to(pos)
			if d < arad:
				arad = d
				army = a
	if army != null:
		EventBus.army_selected.emit(army)
		return
	EventBus.army_selected.emit(null)
	# Клик по логову или племени — карточка дикого края.
	var wrad := 10.0 / _camera.zoom.x
	var wild: RefCounted = null
	for l in world.lairs:
		if l.alive:
			var d := _renderer.cell_center(l.cell if l.region == l.home else world.regions[l.region].center).distance_to(pos)
			if d < wrad:
				wrad = d
				wild = l
	for t in world.tribes:
		if t.alive and t.cell >= 0:
			var d := _renderer.cell_center(t.cell).distance_to(pos)
			if d < wrad:
				wrad = d
				wild = t
	for c in world.caravans:
		if c.alive:
			var d := _overlay.caravan_pos(world, c).distance_to(pos)
			if d < wrad:
				wrad = d
				wild = c
	for m in world.mercs:
		if m.alive and m.cell >= 0:
			var d := (_renderer.cell_center(m.cell) + Vector2(9.0, -9.0) / _camera.zoom.x).distance_to(pos)
			if d < wrad:
				wrad = d
				wild = m
	EventBus.wild_selected.emit(wild)
	if wild != null:
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
		&"crisis":
			CrisisSystem.start(world, _tool_params.crisis)
		&"road":
			GodTools.road_from(world, cell)
		&"army":
			GodTools.create_army(world, cell)
		&"fleet":
			GodTools.launch_fleet(world, cell)
		&"destroy_army":
			GodTools.destroy_army(world, cell)
		&"tribe":
			GodTools.spawn_tribe(world, cell)
		&"lair":
			GodTools.spawn_lair(world, cell, false)
		&"great_monster":
			GodTools.spawn_lair(world, cell, true)
		&"disease":
			GodTools.start_disease(world, cell, _tool_params.disease)
		&"dialect":
			GodTools.split_dialect(world, cell)
		&"caravan":
			GodTools.send_caravan(world, cell)
		&"mercs":
			GodTools.spawn_mercs(world, cell)
		&"gold_rush":
			GodTools.gold_rush(world, cell)
		&"slavery":
			GodTools.toggle_slavery(world, cell)
		&"forgive":
			GodTools.forgive_debts(world, cell)
		&"mutiny":
			var rebels := GodTools.mutiny(world, cell)
			if rebels != null:
				EventBus.nation_selected.emit(rebels.id)
		&"player_travel":
			if world.region_of[cell] >= 0:
				var res := PlayerSystem.command(world, &"travel", world.region_of[cell])
				if not res.is_empty():
					PlayerSystem.note(world, "Не выйдет: %s." % res)
			EventBus.god_tool_changed.emit(&"", {})
		&"player_create":
			if world.region_of[cell] >= 0 and PlayerSystem.create_hero(world, _tool_params.race, _tool_params.cls, _tool_params.name, world.region_of[cell]) != null:
				EventBus.my_hero_requested.emit(true)
			EventBus.god_tool_changed.emit(&"", {})
		&"artifact":
			GodTools.gift_artifact(world, _tool_params.artifact, cell)
		&"bless":
			GodTools.bless(world, _tool_params.god, cell)
		&"chosen":
			GodTools.choose_hero(world, _tool_params.god, cell)
		&"child":
			GodTools.hero_child(world, cell)
		&"order":
			GodTools.found_order(world, cell)
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
	_follow_hero = -1
	_camera.fly_to(_renderer.cell_center(cell), maxf(_camera.target_zoom, 2.0))


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
