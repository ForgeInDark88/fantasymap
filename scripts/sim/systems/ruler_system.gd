class_name RulerSystem
extends RefCounted
## Смена правителей: возраст, срок правления и наследование.


func tick(world: World, nation: Nation) -> void:
	nation.ruler_age += 1
	nation.reign_left -= 1
	if nation.reign_left > 0:
		return
	var old := nation.ruler_display()
	world.new_ruler(nation)
	var reason := "пал" if nation.race.lifespan <= 0 else "умер"
	world.log_event(&"ruler", "%s: %s %s, новый правитель — %s." % [nation.name, old, reason, nation.ruler_display()],
			PackedInt32Array([nation.id]))
	# Смена власти слегка расшатывает государство.
	nation.stability = maxf(0.0, nation.stability - world.rng.randf_range(0.0, 0.08))
