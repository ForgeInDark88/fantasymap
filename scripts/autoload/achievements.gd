extends Node
## Достижения (autoload «Achievements»): соединяет мир с AchievementTracker.
## Подключает World.observer, превращая записи летописи и счётчики в сигнал
## EventBus.world_event; по нему и по смене года проверяет условия и объявляет
## новые достижения сигналом EventBus.achievement_unlocked.

var tracker: AchievementTracker


func _ready() -> void:
	tracker = AchievementTracker.new()
	EventBus.world_generated.connect(func(world: World, _ms: int) -> void:
		world.observer = func(what: StringName, data: Dictionary) -> void: EventBus.world_event.emit(what, data)
		tracker.reset_world(world))
	EventBus.world_event.connect(_on_event)
	EventBus.year_passed.connect(func(_y: int) -> void:
		if WorldState.world != null:
			_announce(tracker.new_year(WorldState.world)))


func _on_event(what: StringName, data: Dictionary) -> void:
	_announce(tracker.handle(WorldState.world, what, data))


## Событие интерфейса (экспорт хроники…).
func ui_event(key: StringName) -> void:
	_announce(tracker.handle(WorldState.world, &"ui", {"key": key}))


func _announce(got: Array[AchievementDef]) -> void:
	for d in got:
		EventBus.achievement_unlocked.emit(d)
