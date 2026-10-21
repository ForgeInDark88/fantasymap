class_name LairSystem
extends RefCounted
## Логова чудовищ и великие чудовища (этап 11.C, data/lairs). Логово стоит в
## диком крае своего биома и набегает на соседние края (жители, золото,
## порядок). Великое чудовище (дракон, гидра, песчаный червь) — одно на
## логово: бродит до great_range краёв от логова и бьёт больнее. Логово
## разоряют герои (странствующие в том же крае) или войско государства,
## занявшего край; добыча — золото, герою — слава.
##
## Ход: каждое логово — раз в месяц в «свой» день (Lair.day), рождение — раз в год.

const REGIONS_PER_LAIR := 18
const MAX_LAIRS := 30
const MAX_GREAT := 3
const SPAWN_CHANCE := 0.4
const GREAT_CHANCE := 0.05
## После стольких лет великое чудовище может уснуть (шанс 4% в год).
const GREAT_YEARS := 80
## Герой в крае логова решается на схватку с таким шансом (проверка раз в квартал).
const HERO_FIGHT_CHANCE := 0.5
## Войско государства идёт на логово своего края: шанс в месяц и нужный перевес.
const ARMY_CLEAR_CHANCE := 0.15
const ARMY_CLEAR_RATIO := 0.25
## Обычное логово растёт не больше чем до этой силы.
const MAX_STRENGTH := 6000.0
const GREAT_NAMES := ["Скарвакс", "Мальгор", "Ведра", "Ургхал", "Тиамаш", "Сарнах", "Кхаэль", "Морвин", "Фафнар", "Зигрот"]
const GREAT_EPITHETS := ["Пепельный", "Чёрный", "Древний", "Багровый", "Ненасытный", "Безглазый", "Шепчущий", "Костяной"]


static func seed_world(world: World) -> void:
	var n := clampi(world.regions.size() / REGIONS_PER_LAIR, 3, MAX_LAIRS)
	for i in n:
		spawn(world, _pick_def(world, false), -1)


static func alive_lairs(world: World) -> Array[Lair]:
	var res: Array[Lair] = []
	for l in world.lairs:
		if l.alive:
			res.append(l)
	return res


static func _pick_def(world: World, great: bool) -> LairDef:
	var total := 0.0
	var defs: Array[LairDef] = []
	for d in LairDB.all():
		var def: LairDef = d
		if def.great == great and world.year >= def.min_year:
			defs.append(def)
			total += def.weight
	if defs.is_empty():
		return null
	var roll := world.rng.randf() * total
	for def in defs:
		roll -= def.weight
		if roll <= 0.0:
			return def
	return defs[defs.size() - 1]


## Логово вида def в крае клетки cell (-1 — дикий край подходящего биома).
static func spawn(world: World, def: LairDef, cell: int) -> Lair:
	if def == null:
		return null
	var rng := world.rng
	var region: Region = null
	if cell >= 0:
		region = world.region_at(cell)
	else:
		var best_score := -INF
		for k in 16:
			var r := world.regions[rng.randi_range(0, world.regions.size() - 1)]
			if r.cells.size() < 3:
				continue
			var score := rng.randf()
			if def.biomes.has(BiomeDB.get_def(world.map.biome[r.center]).id):
				score += 2.0
			if r.owner_counts.is_empty():
				score += 1.5
			if lair_in(world, r.id) != null:
				score -= 4.0
			if score > best_score:
				best_score = score
				region = r
	if region == null:
		return null
	var l := Lair.new()
	l.id = world.lairs.size()
	l.def = def
	l.home = region.id
	l.region = region.id
	l.cell = region.cells[rng.randi_range(0, region.cells.size() - 1)]
	l.strength = rng.randf_range(def.strength.x, def.strength.y)
	l.born = world.year
	l.day = rng.randi_range(0, Simulation.DAYS - 1)
	if def.great:
		l.name = "%s %s" % [GREAT_NAMES[rng.randi_range(0, GREAT_NAMES.size() - 1)], GREAT_EPITHETS[rng.randi_range(0, GREAT_EPITHETS.size() - 1)]]
	world.lairs.append(l)
	world.count(&"lairs")
	if world.year > 0 and (def.great or rng.randf() < 0.25):
		var text := ("В крае %s пробудился %s — %s." % [_rname(region), def.monster, l.name]) if def.great \
				else ("В крае %s завелось %s." % [_rname(region), def.display_name.to_lower()])
		var c := region.controller()
		world.log_event(&"lair", text, PackedInt32Array([c]) if c >= 0 else PackedInt32Array())
	return l


static func lair_in(world: World, region_id: int) -> Lair:
	for l in world.lairs:
		if l.alive and (l.home == region_id or l.region == region_id):
			return l
	return null


## Логово в крае или по соседству (для подвигов героев).
static func lair_near(world: World, region_id: int) -> Lair:
	var l := lair_in(world, region_id)
	if l != null:
		return l
	for nb in world.regions[region_id].neighbors:
		l = lair_in(world, nb)
		if l != null:
			return l
	return null


static func _rname(region: Region) -> String:
	return region.name if not region.name.is_empty() else "без имени"


## Логова по «своим» дням месяца — пересобираются при изменении списка (и раз в год).
var _days: Array = []
var _days_key := Vector3i(-1, -1, -1)


func tick_day(world: World) -> void:
	var key := Vector3i(world.get_instance_id() % 1000000007, world.lairs.size(), world.year)
	if key != _days_key:
		_days_key = key
		_days = WildDays.bucket(world.lairs)
	for l in _days[world.day]:
		if l.alive:
			_month(world, l)


func tick_year(world: World) -> void:
	var rng := world.rng
	var alive := alive_lairs(world)
	var great := alive.filter(func(l: Lair) -> bool: return l.def.great).size()
	var limit := clampi(world.regions.size() / REGIONS_PER_LAIR, 3, MAX_LAIRS)
	if alive.size() - great < limit and rng.randf() < SPAWN_CHANCE:
		spawn(world, _pick_def(world, false), -1)
	if great < MAX_GREAT and rng.randf() < GREAT_CHANCE:
		spawn(world, _pick_def(world, true), -1)
	# Великие чудовища не вечны в мире смертных: старые засыпают или уходят.
	for l in alive:
		if l.def.great and world.year - l.born > GREAT_YEARS and rng.randf() < 0.04:
			l.alive = false
			l.slain_by = "сон"
			var c := world.regions[l.home].controller()
			world.log_event(&"lair", "%s погрузился в долгий сон в своём логове — края вздохнули свободнее." % l.label(),
				PackedInt32Array([c]) if c >= 0 else PackedInt32Array())
	var keep: Array[Lair] = []
	for l in world.lairs:
		if l.alive:
			l.id = keep.size()
			keep.append(l)
	world.lairs = keep


func _month(world: World, l: Lair) -> void:
	var rng := world.rng
	if l.def.great or l.strength < MAX_STRENGTH:
		l.strength *= 1.0 + l.def.growth / 12.0
	# Герои в крае чудовища (кроме героя игрока — он решает сам); раз в квартал.
	for h in (world.wandering_heroes() if (world.month + l.day) % 3 == 0 else []):
		if h.alive and h.cell >= 0 and h.id != world.player and world.region_of[h.cell] == l.region \
				and rng.randf() < HERO_FIGHT_CHANCE and h.dares(l.strength * 0.4, rng):
			hero_fight(world, h, l)
			if not l.alive:
				return
	# Войско хозяина края.
	var home := world.regions[l.home]
	var c := home.controller()
	if c >= 0:
		var n := world.nations[c]
		if n.alive and n.power() * ARMY_CLEAR_RATIO > l.strength * (0.8 + rng.randf() * 0.4) and rng.randf() < ARMY_CLEAR_CHANCE * (3.0 if l.def.great else 1.0):
			n.army = maxf(0.0, n.army - l.strength * 0.4)
			n.stock[Goods.GOLD] += l.def.loot
			_slain(world, l, "войско государства %s" % n.short_name, PackedInt32Array([n.id]))
			return
	if rng.randf() < l.def.raid_chance:
		_raid(world, l)


## Великое чудовище уходит в край рядом с логовом и бьёт его; обычные — соседний край.
func _raid(world: World, l: Lair) -> void:
	var rng := world.rng
	var rid := l.home
	var steps := l.def.great_range if l.def.great else 1
	var options := PackedInt32Array()
	var cur := rid
	for s in steps:
		var nbs := world.regions[cur].neighbors
		if nbs.is_empty():
			break
		cur = nbs[rng.randi_range(0, nbs.size() - 1)]
		if world.regions[cur].controller() >= 0:
			options.append(cur)
	if world.regions[l.home].controller() >= 0:
		options.append(l.home)
	if options.is_empty():
		if l.def.great:
			l.region = l.home
		return
	var target := world.regions[options[rng.randi_range(0, options.size() - 1)]]
	if l.def.great:
		l.region = target.id
	var n := world.nations[target.controller()]
	if not n.alive:
		return
	l.raids += 1
	var share := float(target.owner_counts.get(n.id, 0)) / maxf(1.0, float(n.cell_count))
	var loss := l.def.raid_pop * share
	for r in n.pop.size():
		n.pop[r] *= 1.0 - loss
	n.stock[Goods.GOLD] -= minf(maxf(0.0, n.stock[Goods.GOLD]) * 0.05, l.def.raid_gold)
	n.stability = maxf(0.0, n.stability - (0.004 if l.def.great else 0.0))
	world.count(&"lair_raids")
	# Пострадавшие собирают поход на логово.
	if n.power() * ARMY_CLEAR_RATIO > l.strength * (0.8 + rng.randf() * 0.6) and rng.randf() < ARMY_CLEAR_CHANCE:
		n.army = maxf(0.0, n.army - l.strength * 0.4)
		n.stock[Goods.GOLD] += l.def.loot
		_slain(world, l, "войско государства %s" % n.short_name, PackedInt32Array([n.id]))
		return
	if (l.def.great and rng.randf() < 0.15) or rng.randf() < 0.03:
		world.log_event(&"lair", "%s разоряет край %s (%s)." % [l.label(), _rname(target), n.short_name], PackedInt32Array([n.id]))


## Схватка героя с чудовищем: победа — слава, золото, опыт; поражение — раны или гибель.
static func hero_fight(world: World, h: Hero, l: Lair) -> bool:
	var rng := world.rng
	var hp := h.power()
	var p := hp / (hp + l.strength * 0.4)
	var region := world.regions[l.region]
	var c := region.controller()
	var ids := PackedInt32Array([c]) if c >= 0 else PackedInt32Array()
	if rng.randf() < p:
		h.gold += l.def.loot * 0.3
		h.monsters_slain += 1
		h.add_xp(world, 2.0 if l.def.great else 0.5)
		h.karma = minf(1.0, h.karma + 0.05)
		var deed := ("сразил чудовище %s" % l.label()) if l.def.great else ("разорил %s в крае %s" % [l.def.display_name.to_lower(), _rname(region)])
		h.add_deed(world, deed)
		_slain(world, l, "герой %s" % h.display_name(), ids)
		return true
	h.wounds = minf(1.0, h.wounds + 0.3)
	if rng.randf() < (0.25 if l.def.great else 0.08):
		world.log_event(&"hero", "Герой %s пал в схватке: %s." % [h.display_name(), l.label()], ids)
		h.die(world)
	l.strength *= 0.95
	return false


static func _slain(world: World, l: Lair, by: String, ids: PackedInt32Array) -> void:
	l.alive = false
	l.slain_by = by
	world.count(&"lairs_cleared")
	if l.def.great:
		world.count(&"great_monsters_slain")
	if l.def.great or world.rng.randf() < 0.4:
		var verb := "сразил" if by.begins_with("герой") else "разорило"
		world.log_event(&"lair", "%s %s %s." % [by.left(1).to_upper() + by.substr(1), verb,
			("чудовище " + l.label()) if l.def.great else l.def.display_name.to_lower()], ids)


## Опасность краёв для режима карты «Опасности» (0..1 на край): логова и их
## набеги, племена, орды, пираты, поветрия.
static func danger_map(world: World) -> PackedFloat32Array:
	var res := PackedFloat32Array()
	res.resize(world.regions.size())
	for l in world.lairs:
		if not l.alive:
			continue
		var d := 0.9 if l.def.great else 0.6
		res[l.home] = maxf(res[l.home], d)
		res[l.region] = maxf(res[l.region], d)
		for nb in world.regions[l.region].neighbors:
			res[nb] = maxf(res[nb], d * 0.45)
	for t in world.tribes:
		if not t.alive:
			continue
		var d := 0.75 if t.horde else 0.35
		res[t.region] = maxf(res[t.region], d)
		for nb in world.regions[t.region].neighbors:
			res[nb] = maxf(res[nb], d * (0.6 if t.horde else 0.3))
	for a in world.armies:
		if a.alive and a.kind == &"pirates" and a.region >= 0:
			res[a.region] = maxf(res[a.region], 0.55)
	for o in world.outbreaks:
		if o.alive:
			for rid in o.regions:
				res[rid] = maxf(res[rid], 0.8 if o.def.plague else 0.5)
	return res
