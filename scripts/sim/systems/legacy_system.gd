class_name LegacySystem
extends RefCounted
## Наследие империй (раз в год для всего мира).
##
## Когда от великой державы (не меньше LEGACY_MIN_REGIONS регионов) откалываются
## земли, мир запоминает её как «культурную империю»: все осколки получают
## общее наследие на LEGACY_YEARS лет. Наследники ближе друг к другу (мнение),
## могут воссоединиться добровольно (сосед того же народа и веры, с хорошим
## мнением, заметно меньше), а сильнейший наследник объявляет себя
## «собирателем земель»: коренные земли империи в чужих руках — повод для войны
## «за воссоединение империи».

const LEGACY_MIN_REGIONS := 12
const LEGACY_YEARS := 160
## Шанс в год мирного воссоединения подходящей пары наследников.
const REUNION_CHANCE := 0.04
## Мнение наследников друг о друге.
const OPINION_BONUS := 0.2


## Вызывается из World.split_off перед разделом: великая держава получает
## наследие (если его ещё нет), осколок его наследует.
static func on_split(world: World, old: Nation, part: Nation) -> void:
	if old.legacy < 0:
		var controlled := 0
		for rid in old.region_counts:
			if world.regions[rid].controller() == old.id:
				controlled += 1
		if controlled < LEGACY_MIN_REGIONS:
			return
		create(world, old)
	part.legacy = old.legacy


static func create(world: World, nation: Nation) -> Legacy:
	var lg := Legacy.new()
	lg.id = world.legacies.size()
	lg.origin = nation.id
	lg.name = nation.name
	lg.founded_year = world.year
	lg.until_year = world.year + LEGACY_YEARS
	for rid in nation.region_counts:
		if world.regions[rid].controller() == nation.id:
			lg.regions.append(rid)
	world.legacies.append(lg)
	nation.legacy = lg.id
	world.log_event(&"legacy", "Держава %s трещит по швам — но осколки будут помнить общее наследие." % nation.name,
			PackedInt32Array([nation.id]))
	return lg


func tick_year(world: World) -> void:
	for lg in world.legacies:
		if lg.alive:
			_tick_legacy(world, lg)


func _tick_legacy(world: World, lg: Legacy) -> void:
	var members: Array[Nation] = []
	for n in world.nations:
		if n.alive and n.legacy == lg.id:
			members.append(n)
	if members.is_empty() or world.year >= lg.until_year:
		lg.alive = false
		for n in members:
			n.legacy = -1
		world.log_event(&"legacy", "Память о державе %s угасла: наследники больше не считают себя одним народом." % lg.name)
		return
	# Собиратель земель — сильнейший наследник, если он заметно сильнее прочих.
	var strongest := members[0]
	for n in members:
		if n.power() > strongest.power():
			strongest = n
	if lg.collector != strongest.id and members.size() >= 2 and _core_held(world, lg, strongest) >= 2:
		var second := 0.0
		for n in members:
			if n != strongest:
				second = maxf(second, n.power())
		if strongest.power() > second * 1.5 and world.rng.randf() < 0.2:
			set_collector(world, lg, strongest)
	if lg.collector >= 0 and not world.nations[lg.collector].alive:
		lg.collector = -1
	_reunions(world, lg, members)


static func set_collector(world: World, lg: Legacy, nation: Nation) -> void:
	lg.collector = nation.id
	nation.legacy = lg.id
	world.log_event(&"legacy", "%s провозглашает себя собирателем земель державы %s." % [nation.name, lg.name],
			PackedInt32Array([nation.id]))


## Мирное воссоединение: соседи-наследники того же народа и веры с хорошим мнением.
func _reunions(world: World, lg: Legacy, members: Array[Nation]) -> void:
	var d := world.diplomacy
	for a in members:
		if not a.alive:
			continue
		for b in members:
			if b == a or not b.alive or not a.borders.has(b.id) or a.race != b.race or a.state_religion != b.state_religion:
				continue
			if b.cell_count > a.cell_count * 0.4 or d.war_between(a.id, b.id) != null or not d.wars_of(b.id).is_empty():
				continue
			if d.opinion(world, b.id, a.id) < 0.35 or world.rng.randf() > REUNION_CHANCE:
				continue
			for c in b.cells.duplicate():
				world.set_owner(c, a.id)
			world.log_event(&"legacy", "Воссоединение: %s добровольно возвращается в лоно державы %s — наследие %s живо." % [
				b.name, a.name, lg.name], PackedInt32Array([a.id, b.id]))
			return


## Сколько коренных регионов империи контролирует государство.
static func _core_held(world: World, lg: Legacy, nation: Nation) -> int:
	var c := 0
	for rid in lg.regions:
		if world.regions[rid].controller() == nation.id:
			c += 1
	return c


## Держит ли target коренные земли наследия, которое собирает nation.
static func reunification_target(world: World, nation: Nation, target: Nation) -> bool:
	if nation.legacy < 0:
		return false
	var lg := world.legacies[nation.legacy]
	if not lg.alive or lg.collector != nation.id:
		return false
	for rid in lg.regions:
		if world.regions[rid].controller() == target.id:
			return true
	return false
