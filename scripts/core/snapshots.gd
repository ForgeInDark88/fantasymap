class_name Snapshots
extends RefCounted
## Снимки истории и ветви (этап 11.F). Снимок — сжатое точное сохранение мира
## (SaveSystem) с годом и номером ветви; хранятся в памяти (до LIMIT, старые
## выпадают; авто — раз в AUTO_YEARS лет). «Вернуться в это время» загружает
## снимок как новую ветвь: World.branch — номер ветви, World.branch_from —
## {branch, year} — откуда она пошла. Продолжение снимка детерминировано: без
## вмешательства новая ветвь повторяет прежнюю историю.

const LIMIT := 10
const AUTO_YEARS := 50

var items: Array[Dictionary] = []
var _next_branch := 1


func take(world: World, label: String = "") -> Dictionary:
	# Сбор данных — в главном потоке (мир не меняется под ногами); JSON и
	# сжатие — в фоне: exact() строит отдельную копию, мир она не держит.
	var data: Variant = SaveSystem.exact(SaveSystem.to_dict(world))
	var snap := {"year": world.year, "month": world.month, "day": world.day, "branch": world.branch,
		"label": label if not label.is_empty() else "%s · ветвь %d" % [world.date_text(), world.branch],
		"size": 0, "data": PackedByteArray(), "task": -1}
	snap.task = WorkerThreadPool.add_task(func() -> void:
		var raw := JSON.stringify(data, "", false, true).to_utf8_buffer()
		snap.size = raw.size()
		snap.data = raw.compress(FileAccess.COMPRESSION_ZSTD), false, "Snapshot")
	items.append(snap)
	_next_branch = maxi(_next_branch, world.branch + 1)
	while items.size() > LIMIT:
		_wait(items[0])
		items.remove_at(0)
	return snap


## Дождаться фонового сжатия снимка.
static func _wait(snap: Dictionary) -> void:
	if int(snap.task) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(snap.task))
		snap.task = -1


## Авто-снимок в начале года (раз в AUTO_YEARS лет).
func maybe_auto(world: World) -> void:
	if world.year > 0 and world.year % AUTO_YEARS == 0 and not items.any(func(s: Dictionary) -> bool: return s.year == world.year and s.branch == world.branch):
		take(world, "%d г. · ветвь %d (авто)" % [world.year, world.branch])


## Мир из снимка как новая ветвь истории.
func restore(index: int) -> World:
	if index < 0 or index >= items.size():
		return null
	var snap: Dictionary = items[index]
	_wait(snap)
	var raw: PackedByteArray = (snap.data as PackedByteArray).decompress(int(snap.size), FileAccess.COMPRESSION_ZSTD)
	var world := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(raw.get_string_from_utf8())))
	if world == null:
		return null
	world.branch_from = {"branch": int(snap.branch), "year": int(snap.year)}
	world.branch = _next_branch
	_next_branch += 1
	world.log_event(&"era", "Ветвь истории %d: мир вернулся в %d год (из ветви %d)." % [world.branch, int(snap.year), int(snap.branch)])
	return world
