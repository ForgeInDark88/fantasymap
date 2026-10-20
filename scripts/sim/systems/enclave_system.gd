class_name EnclaveSystem
extends RefCounted
## Ликвидация анклавов.
##
## Клочок государства, отрезанный от основной территории (той, где столица)
## и со всех сторон по суше окружённый одним соседом, переходит к этому соседу:
## удержать его невозможно. Заморские колонии и прибрежные владения с выходом
## к морю остаются (их снабжают по морю), если они не совсем крошечные.

## Раз в сколько лет проверять каждое государство (со сдвигом по id).
const PERIOD := 25
## Прибрежный клочок меньше этого размера всё равно считается анклавом.
const MIN_COASTAL_POCKET := 15


func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id) % PERIOD == 0:
		absorb(world, nation)


## Быстрая проверка после захвата: если регионы государства по-прежнему
## связаны между собой (граф регионов), анклава почти наверняка нет — полный
## обход клеток не нужен (раз в PERIOD лет он всё равно выполняется).
static func absorb_if_split(world: World, nation: Nation) -> int:
	if not nation.alive or nation.region_counts.size() < 2:
		return 0
	var keys := nation.region_counts.keys()
	var seen := {keys[0]: true}
	var queue: Array = [keys[0]]
	while not queue.is_empty():
		var rid: int = queue.pop_back()
		for nb in world.regions[rid].neighbors:
			if not seen.has(nb) and nation.region_counts.has(nb):
				seen[nb] = true
				queue.append(nb)
	if seen.size() == keys.size():
		return 0
	return absorb(world, nation)


## Находит связные куски территории и отдаёт окружённые соседям.
## dry_run — только посчитать анклавы (для тестов). Возвращает число анклавов.
static func absorb(world: World, nation: Nation, dry_run: bool = false) -> int:
	if not nation.alive or nation.cells.size() < 2:
		return 0
	var map := world.map
	var w := map.width
	var n := map.cell_count()
	var stamp := world.next_stamp()
	var mark := world.mark
	var owner := world.owner
	var pieces: Array[PackedInt32Array] = []
	for start in nation.cells:
		if mark[start] == stamp:
			continue
		var piece := PackedInt32Array([start])
		mark[start] = stamp
		var qi := 0
		while qi < piece.size():
			var c := piece[qi]
			qi += 1
			var x := c % w
			for k in 4:
				var nb := -1
				match k:
					0: nb = c - 1 if x > 0 else -1
					1: nb = c + 1 if x < w - 1 else -1
					2: nb = c - w
					3: nb = c + w
				if nb >= 0 and nb < n and mark[nb] != stamp and owner[nb] == nation.id:
					mark[nb] = stamp
					piece.append(nb)
		pieces.append(piece)
	world.mark = mark
	if pieces.size() < 2:
		return 0
	# Основная часть — со столицей (или самая большая).
	var main := 0
	var capital_cell := world.cities[nation.capital_city].cell if nation.capital_city >= 0 else -1
	for i in pieces.size():
		if capital_cell >= 0 and pieces[i].has(capital_cell):
			main = i
			break
		if pieces[i].size() > pieces[main].size():
			main = i
	var found := 0
	for i in pieces.size():
		if i == main:
			continue
		var piece := pieces[i]
		var encloser := -2
		var coastal := false
		for c in piece:
			for nb in map.neighbors4(c):
				var o := world.owner[nb]
				if o == nation.id:
					continue
				if not map.is_land(nb):
					var b := map.biome[nb]
					if b == Biome.OCEAN or b == Biome.SEA:
						coastal = true
					continue
				if o < 0:
					encloser = -1  # граничит с ничьей землёй — не анклав
				elif encloser == -2:
					encloser = o
				elif encloser != o:
					encloser = -1  # несколько соседей — не анклав
			if encloser == -1:
				break
		if encloser < 0 or (coastal and piece.size() >= MIN_COASTAL_POCKET):
			continue
		found += 1
		if dry_run:
			continue
		for c in piece:
			world.set_owner(c, encloser)
		if piece.size() >= 4:
			world.log_event(&"conquest", "Отрезанные земли %s (%d кл.) перешли к государству %s." % [
				nation.short_name, piece.size(), world.nations[encloser].short_name],
					PackedInt32Array([nation.id, encloser]))
	return found
