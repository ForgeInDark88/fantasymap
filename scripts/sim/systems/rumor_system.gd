class_name RumorSystem
extends RefCounted
## Слухи (этап 11.E): правдивые и ложные. Раз в год рождаются слухи о
## державах — слабость армии, полная казна, мор, коварные замыслы, болезнь
## правителя. Правдив ли слух — решает сам мир в миг рождения (Rumor.truth);
## интриганы распускают слухи о соперниках нарочно — чаще ложные. Верит ли
## держава слуху: если её разведка (Nation.intel) слабее «правдоподобия» слуха,
## верит любому; сильная разведка видит правду. Поверившие действуют: на
## «слабого» нападают охотнее, на «богатого» — тоже, «коварный» сосед теряет
## дружбу. В окне «Дипломатия» — переключатель «показать правду».
## Слух: {id, year, kind, about, target, source, truth, cred, until, text}.

const MAX_RUMORS := 40
const YEARS := 6
## Слухов, рождённых самим миром, в год.
const NATURAL := 2
const KIND_NAMES := {&"weak": "слабость войска", &"rich": "полная казна", &"plague": "мор", &"treachery": "коварный замысел",
	&"heir": "болезнь правителя"}


static func active(world: World) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for r in world.rumors:
		if int(r.until) >= world.year:
			res.append(r)
	return res


## Верит ли держава слуху (сильная разведка видит правду).
static func believes(world: World, nation: Nation, r: Dictionary) -> bool:
	if int(r.source) == nation.id or int(r.until) < world.year:
		return false
	return bool(r.truth) or nation.intel < float(r.cred)


## Насколько слухи разжигают желание nation воевать с target (множитель).
static func war_factor(world: World, nation: Nation, target: Nation) -> float:
	var k := 1.0
	for r in world.rumors:
		if int(r.about) != target.id or int(r.until) < world.year:
			continue
		if (r.kind == &"weak" or r.kind == &"rich") and believes(world, nation, r):
			k *= 1.5 if r.kind == &"weak" else 1.2
	return k


## Правда ли сейчас слух такого вида о державе.
static func is_true(world: World, kind: StringName, n: Nation, target: Nation) -> bool:
	match kind:
		&"weak":
			var around := 0.0
			var k := 0
			for o in n.borders:
				if world.nations[o].alive:
					around += world.nations[o].power()
					k += 1
			return k > 0 and n.power() < around / k * 0.6
		&"rich":
			return n.stock[Goods.GOLD] > (n.population / 1000.0 * 0.3 + 10.0) * 10.0
		&"plague":
			for o in world.outbreaks:
				if o.alive and o.nations.has(n.id):
					return true
			return false
		&"treachery":
			return target != null and world.diplomacy.opinion(world, n.id, target.id) < -0.3
		&"heir":
			return n.ruler_age > maxi(40, int(n.race.lifespan * 0.8))
	return false


static func _text(world: World, kind: StringName, n: Nation, target: Nation) -> String:
	match kind:
		&"weak":
			return "Говорят, войско государства %s ослабло — бери голыми руками." % n.short_name
		&"rich":
			return "Говорят, казна государства %s ломится от золота." % n.short_name
		&"plague":
			return "Говорят, в землях государства %s мор — купцы обходят их стороной." % n.short_name
		&"treachery":
			return "Говорят, %s тайно готовит удар по государству %s." % [n.short_name, target.short_name if target != null else "?"]
		&"heir":
			return "Говорят, %s при смерти — быть смуте." % n.ruler_display()
	return ""


## Пустить слух (мир, интриган или Бог). truth = null — решает сам мир.
static func spread(world: World, kind: StringName, about: Nation, target: Nation, source: int, truth: Variant = null) -> Dictionary:
	var rng := world.rng
	var r := {"id": world.rumor_serial, "year": world.year, "kind": kind, "about": about.id, "target": target.id if target != null else -1,
		"source": source, "truth": is_true(world, kind, about, target) if truth == null else bool(truth),
		"cred": rng.randf_range(15.0, 55.0), "until": world.year + YEARS, "text": _text(world, kind, about, target)}
	world.rumor_serial += 1
	world.rumors.append(r)
	world.count(&"rumors")
	if not bool(r.truth):
		world.count(&"rumors_false")
	# Коварный замысел: поверившая жертва перестаёт доверять.
	if kind == &"treachery" and target != null and believes(world, target, r):
		world.diplomacy.add_grudge(target.id, about.id, 0.1)
		if target.allies.has(about.id):
			world.diplomacy.set_alliance(world, target.id, about.id, false)
			DealSystem.journal(world, &"rumor", target.id, about.id, false, "Слух о коварстве: %s разрывает союз с %s." % [target.short_name, about.short_name])
	if rng.randf() < 0.12:
		world.log_event(&"rumor", "Слух: " + String(r.text), PackedInt32Array([about.id]))
	return r


func tick_year(world: World) -> void:
	var rng := world.rng
	world.rumors = world.rumors.filter(func(r: Dictionary) -> bool: return int(r.until) >= world.year)
	var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive)
	if alive.size() < 2:
		return
	var kinds := KIND_NAMES.keys()
	# Слухи, рождённые миром: о случайной державе — бывают и правдой, и вымыслом.
	for k in NATURAL:
		if world.rumors.size() >= MAX_RUMORS:
			break
		var n: Nation = alive[rng.randi_range(0, alive.size() - 1)]
		var kind: StringName = kinds[rng.randi_range(0, kinds.size() - 1)]
		var target: Nation = null
		if kind == &"treachery":
			if n.borders.is_empty():
				continue
			target = world.nations[n.borders.keys()[rng.randi_range(0, n.borders.size() - 1)]]
		spread(world, kind, n, target, -1)
	# Интриганы — нарочно, о соперниках (чаще ложь).
	for n in alive:
		if world.rumors.size() >= MAX_RUMORS:
			break
		var p: PersonalityDef = n.personality
		if p == null or rng.randf() > p.rumor:
			continue
		var rival: Nation = null
		var worst := 2.0
		for o in n.borders:
			var on := world.nations[o]
			if on.alive:
				var op := world.diplomacy.opinion(world, n.id, o)
				if op < worst:
					worst = op
					rival = on
		if rival == null:
			continue
		if rng.randf() < 0.5 and not rival.borders.is_empty():
			var victim := world.nations[rival.borders.keys()[rng.randi_range(0, rival.borders.size() - 1)]]
			if victim.alive and victim != n:
				spread(world, &"treachery", rival, victim, n.id)
				continue
		spread(world, &"weak", rival, null, n.id)
