class_name World
extends RefCounted
## Полное состояние мира: карта + государства + города + принадлежность клеток.
##
## Это «модель» симуляции: никакой отрисовки, никаких нод. Рендер читает
## owner_texels, интерфейс — списки nations/cities. Все изменения владельцев
## клеток проходят через set_owner(), чтобы данные для GPU и счётчики
## государств всегда были согласованы.

var map: WorldMap
var settings: MapSettings
var year := 0
var rng := RandomNumberGenerator.new()

var nations: Array[Nation] = []
var cities: Array[City] = []

## id государства-владельца для каждой клетки (-1 — ничья).
var owner := PackedInt32Array()
## То же в виде RGBA8 для шейдера: R,G — (id + 1) в 16 битах, B — суша (255) / вода (0).
var owner_texels := PackedByteArray()
## id города в клетке (-1 — нет).
var city_cell := PackedInt32Array()
## Растёт при каждом изменении границ — рендер по нему понимает, что пора обновиться.
var ownership_version := 0

## Уже выданные имена (города, государства, правители) — чтобы не повторялись.
var used_names: Dictionary = {}


## Полный цикл создания мира: карта + стартовые государства. Синхронно —
## WorldState вызывает это в фоновом потоке, тесты — напрямую.
static func create(s: MapSettings) -> World:
	var world := World.new(MapGenerator.new().generate(s))
	WorldSeeder.new().seed_world(world)
	return world


func _init(world_map: WorldMap) -> void:
	map = world_map
	settings = world_map.settings
	rng.seed = hash(str(settings.world_seed) + ":world")
	var n := map.cell_count()
	owner.resize(n)
	owner.fill(-1)
	city_cell.resize(n)
	city_cell.fill(-1)
	owner_texels.resize(n * 4)
	for i in n:
		owner_texels[i * 4 + 2] = 255 if map.is_land(i) else 0
		owner_texels[i * 4 + 3] = 255


func set_owner(cell: int, nation_id: int) -> void:
	var old := owner[cell]
	if old == nation_id:
		return
	if old >= 0:
		nations[old].cell_count -= 1
	if nation_id >= 0:
		nations[nation_id].cell_count += 1
	owner[cell] = nation_id
	var v := nation_id + 1
	owner_texels[cell * 4] = v & 0xff
	owner_texels[cell * 4 + 1] = (v >> 8) & 0xff
	ownership_version += 1


func nation_at(cell: int) -> Nation:
	var id := owner[cell]
	return nations[id] if id >= 0 else null


func city_at(cell: int) -> City:
	var id := city_cell[cell]
	return cities[id] if id >= 0 else null


func add_nation(race: RaceDef) -> Nation:
	var nation := Nation.new()
	nation.id = nations.size()
	nation.race = race
	nation.race_id = race.id
	nation.founded_year = year
	nations.append(nation)
	return nation


func add_city(nation: Nation, cell: int, race: RaceDef, is_capital: bool) -> City:
	var city := City.new()
	city.id = cities.size()
	city.cell = cell
	city.nation_id = nation.id
	city.race_id = race.id
	city.is_capital = is_capital
	city.founded_year = year
	city.name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(race, rng))
	cities.append(city)
	city_cell[cell] = city.id
	nation.city_ids.append(city.id)
	if is_capital:
		nation.capital_city = city.id
	return city


## Сколько жителей расы race может прокормить клетка (основа для роста на этапе 3).
func cell_capacity(race: RaceDef, cell: int) -> float:
	var b := map.biome[cell]
	if Biome.is_water(b):
		return 0.0
	var def := BiomeDB.get_def(b)
	var aff := race.affinity_by_biome[b]
	# Тем, кто не нуждается в еде, плодородие безразлично.
	var food := lerpf(0.6, 0.25 + def.fertility, clampf(race.food_need, 0.0, 1.0))
	var cap := 1000.0 * food * lerpf(0.35, 1.2, aff)
	if map.river[cell] > 0:
		cap *= 1.3
	if race.has_trait(&"farmers"):
		cap *= 1.0 + def.fertility * 0.3
	return cap


## Пересчитывает точку для подписи каждого государства: клетку территории,
## наиболее удалённую от границы (BFS от всех пограничных клеток сразу).
func compute_label_anchors() -> void:
	var w := map.width
	var h := map.height
	var n := map.cell_count()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n)
	var tail := 0
	for i in n:
		var id := owner[i]
		if id < 0:
			continue
		var x := i % w
		var y := i / w
		var border := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
				or owner[i - 1] != id or owner[i + 1] != id or owner[i - w] != id or owner[i + w] != id
		if border:
			dist[i] = 0
			queue[tail] = i
			tail += 1
	var head := 0
	while head < tail:
		var c := queue[head]
		head += 1
		var id := owner[c]
		var d := dist[c] + 1
		var x := c % w
		for k in 4:
			var nb := -1
			match k:
				0: nb = c - 1 if x > 0 else -1
				1: nb = c + 1 if x < w - 1 else -1
				2: nb = c - w
				3: nb = c + w
			if nb >= 0 and nb < n and dist[nb] == -1 and owner[nb] == id:
				dist[nb] = d
				queue[tail] = nb
				tail += 1
	var best := PackedInt32Array()
	best.resize(nations.size())
	best.fill(-1)
	for i in n:
		var id := owner[i]
		if id >= 0 and (best[id] == -1 or dist[i] > dist[best[id]]):
			best[id] = i
	for nation in nations:
		nation.label_cell = best[nation.id]
