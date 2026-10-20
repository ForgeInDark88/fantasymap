class_name SocietySystem
extends RefCounted
## Тайные общества и культы (раз в год для всего мира, их немного).
##
## Возникают в неспокойных державах: культы (тёмных вер — Бездны, Вечной Ночи —
## или ересей), тайные братства (грабят казну) и заговоры (метят на трон).
## Влияние растёт там, где власть слаба, расползается по соседним регионам и
## разжигает недовольство; стабильные державы и теократии давят общества, а
## разведка раскрывает их. Набрав силу в столице слабой державы, общество
## захватывает власть: культ обращает страну в свою веру, заговорщики сажают
## на трон своего вожака.

const MAX_SOCIETIES := 6
## Шанс в год, что где-то возникнет новое общество.
const SPAWN_CHANCE := 0.06
## Рост влияния в регионе в год при нулевой стабильности владельца.
const GROWTH := 0.05
## Подавление в стабильной державе (стабильность > 0.6) и у теократий.
const SUPPRESS := 0.06
## Расползание в соседний регион.
const SPREAD := 0.05
## Больше стольких регионов тайное общество не охватывает (ячейки не уследят друг за другом).
const MAX_REGIONS := 12
## Охота разведки: цена в очках и сколько влияния снимает.
const HUNT_COST := 5.0
const HUNT_POWER := 0.25
## Влияние в столичном регионе, нужное для захвата власти.
const COUP_INFLUENCE := 0.6
const NAMES := {
	&"cult": ["Культ Багрового Ока", "Слуги Чёрной Луны", "Культ Пепла", "Дети Бездны", "Культ Безмолвных",
		"Свидетели Конца", "Культ Змеиного Кольца"],
	&"brotherhood": ["Братство Серой Руки", "Братство Ночных Ключей", "Гильдия Шёпота", "Братство Медной Монеты",
		"Общество Тихого Пера"],
	&"conspiracy": ["Заговор Зари", "Орден Кинжала", "Совет Теней", "Лига Истинного Престола", "Круг Девяти"],
}


func tick_year(world: World) -> void:
	_maybe_spawn(world)
	for s in world.societies:
		if s.alive:
			_tick_society(world, s)


func _maybe_spawn(world: World) -> void:
	var rng := world.rng
	var alive := 0
	for s in world.societies:
		if s.alive:
			alive += 1
	if alive >= MAX_SOCIETIES or rng.randf() > SPAWN_CHANCE:
		return
	# Чем слабее власть, тем вероятнее тайное общество.
	var total := 0.0
	for n in world.nations:
		if n.alive and n.capital_city >= 0 and not n.race.has_trait(&"demonic"):
			total += 1.0 - n.stability
	if total <= 0.0:
		return
	# Храм забытых богов пробуждает культ.
	var temple := RuinSystem.temple_for_cult(world)
	if temple != null:
		var host := world.nations[world.owner[temple.cell]]
		temple.revived = true
		var s := found(world, host, world.region_of[temple.cell], &"cult")
		if s != null:
			world.log_event(&"ruins", "В руинах «%s» снова горят огни: там собирается %s." % [temple.name, s.name], PackedInt32Array([host.id]))
		return
	var roll := rng.randf() * total
	for n in world.nations:
		if not n.alive or n.capital_city < 0 or n.race.has_trait(&"demonic"):
			continue
		roll -= 1.0 - n.stability
		if roll <= 0.0:
			found(world, n, world.region_of[world.cities[n.capital_city].cell] if rng.randf() < 0.3 else -1)
			return


## Основывает общество в государстве (в регионе rid или в случайном). Панель Бога — тоже сюда.
static func found(world: World, nation: Nation, rid: int = -1, kind: StringName = &"") -> Society:
	var rng := world.rng
	if rid < 0:
		var keys := nation.region_counts.keys()
		if keys.is_empty():
			return null
		rid = keys[rng.randi_range(0, keys.size() - 1)]
	var s := Society.new()
	s.id = world.societies.size()
	s.home = nation.id
	s.founded_year = world.year
	if kind == &"":
		var dark := _dark_faith(world)
		var roll := rng.randf()
		kind = &"cult" if roll < 0.4 else (&"brotherhood" if roll < 0.65 else &"conspiracy")
		if kind == &"cult":
			s.religion = dark if dark >= 0 and rng.randf() < 0.6 else _any_faith(world, nation)
	elif kind == &"cult":
		s.religion = _any_faith(world, nation)
	s.kind = kind
	var names: Array = NAMES[kind]
	s.name = names[rng.randi_range(0, names.size() - 1)]
	s.leader = NameGenerator.unique(world.used_names, NameGenerator.person_name.bind(nation.race, rng))
	s.influence[rid] = 0.25
	world.societies.append(s)
	var faith := (" (вера «%s»)" % world.religions[s.religion].name) if s.religion >= 0 else ""
	world.log_event(&"intrigue", "В регионе %s (%s) тайно собирается %s «%s»%s; во главе — %s." % [
		world.regions[rid].name, nation.short_name, s.kind_name(), s.name, faith, s.leader], PackedInt32Array([nation.id]))
	return s


func _tick_society(world: World, s: Society) -> void:
	var rng := world.rng
	var add := {}
	for rid in s.influence.keys():
		var region := world.regions[rid]
		var owner := world.owner[region.center] if region.center >= 0 else -1
		var v: float = s.influence[rid]
		if owner < 0:
			v -= 0.05
		else:
			var n := world.nations[owner]
			v += GROWTH * (1.0 - n.stability)
			if n.stability > 0.6:
				v -= SUPPRESS
			if s.kind == &"cult" and n.government != null and n.government.id == &"theocracy" and s.religion != n.state_religion:
				v -= SUPPRESS
			# Культ своей веры живёт открыто — его не душат, но и бунтов он не сеет.
			if s.kind == &"cult" and s.religion == n.state_religion:
				v += 0.02
			else:
				region.unrest += v * 0.06
			if s.kind == &"brotherhood":
				n.stock[Goods.GOLD] -= v * 3.0
			if s.kind == &"cult" and s.religion >= 0:
				ReligionSystem.shift(region.faith, s.religion, v * 0.03)
			# Разведка выслеживает общество.
			if n.intel >= HUNT_COST and rng.randf() < 0.3 * v:
				n.intel -= HUNT_COST
				v -= HUNT_POWER
				if rng.randf() < 0.12:
					world.log_event(&"intrigue", "Тайная стража государства %s раскрыла ячейку общества «%s» в регионе %s." % [
						n.short_name, s.name, region.name], PackedInt32Array([n.id]))
			_maybe_coup(world, s, n, region, v)
			if not s.alive:
				return
		if v > 0.3 and not region.neighbors.is_empty() and s.influence.size() + add.size() < MAX_REGIONS:
			var nb: int = region.neighbors[rng.randi_range(0, region.neighbors.size() - 1)]
			add[nb] = add.get(nb, 0.0) + SPREAD
		s.influence[rid] = clampf(v, 0.0, 1.0)
	for rid in add:
		s.influence[rid] = minf(1.0, s.influence.get(rid, 0.0) + add[rid])
	for rid in s.influence.keys():
		if s.influence[rid] < 0.03:
			s.influence.erase(rid)
	if s.total_influence() < 0.05:
		s.alive = false
		world.log_event(&"intrigue", "%s «%s» рассеян — о нём помнят лишь слухи." % [s.kind_name().capitalize(), s.name])


func _maybe_coup(world: World, s: Society, n: Nation, region: Region, v: float) -> void:
	if s.kind == &"brotherhood" or n.capital_city < 0 or world.region_of[world.cities[n.capital_city].cell] != region.id:
		return
	if v < COUP_INFLUENCE or n.stability >= 0.45 or world.rng.randf() > 0.2 or s.seized >= 0:
		return
	if s.kind == &"cult" and s.religion == n.state_religion:
		return  # вера культа и так государственная
	var old := n.ruler_display()
	world.new_ruler(n, true)
	if s.kind == &"cult" and s.religion >= 0:
		n.state_religion = s.religion
		world.log_event(&"intrigue", "«%s» захватил власть в государстве %s: %s свергнут, вера «%s» объявлена государственной." % [
			s.name, n.name, old, world.religions[s.religion].name], PackedInt32Array([n.id]))
		s.seized = n.id
		return
	n.ruler_name = s.leader
	n.ruler_number = 1
	world.log_event(&"intrigue", "Переворот в государстве %s: «%s» сверг правителя %s, на трон взошёл %s." % [
		n.name, s.name, old, n.ruler_display()], PackedInt32Array([n.id]))
	s.seized = n.id
	s.alive = false  # заговор достиг цели и вышел из тени


## Вера Бездны или Вечной Ночи, если такие веры живы.
static func _dark_faith(world: World) -> int:
	for r in world.religions:
		if r.alive and r.def != null and (r.def.id == &"abyss" or r.def.id == &"eternal_night") and r.parent < 0:
			if r.def.id == &"abyss":
				for n in world.nations:
					if n.alive and n.race.has_trait(&"demonic"):
						return r.id
			else:
				return r.id
	return -1


## Ересь или чужая вера — для культа без тёмной веры.
static func _any_faith(world: World, nation: Nation) -> int:
	var options: Array[int] = []
	for r in world.religions:
		if r.alive and r.id != nation.state_religion:
			options.append(r.id)
	return options[world.rng.randi_range(0, options.size() - 1)] if not options.is_empty() else -1
