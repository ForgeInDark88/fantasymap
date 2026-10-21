class_name Notices
## Уведомления (этап 11.F): какие записи летописи важны игроку — о державах и
## героях, за которыми он следит (World.watch_nations / watch_heroes), и
## мировые потрясения (кризисы, эпохи, великие деяния, падение держав).

const GLOBAL_KINDS: Array[StringName] = [&"crisis", &"era", &"great", &"fall", &"collapse"]


static func matters(world: World, entry: Dictionary) -> bool:
	var kind: StringName = entry.get("kind", &"")
	if GLOBAL_KINDS.has(kind):
		return true
	for id in entry.get("nations", PackedInt32Array()):
		if world.watch_nations.has(id):
			return true
	var text: String = entry.get("text", "")
	for hid in world.watch_heroes:
		if hid >= 0 and hid < world.heroes.size() and text.contains(world.heroes[hid].name):
			return true
	return false


static func toggle_nation(world: World, id: int) -> bool:
	var i := world.watch_nations.find(id)
	if i >= 0:
		world.watch_nations.remove_at(i)
		return false
	world.watch_nations.append(id)
	return true


static func toggle_hero(world: World, id: int) -> bool:
	var i := world.watch_heroes.find(id)
	if i >= 0:
		world.watch_heroes.remove_at(i)
		return false
	world.watch_heroes.append(id)
	return true
