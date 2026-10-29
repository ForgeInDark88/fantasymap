class_name BattleReplay
## Пересказ записи боя (этап 12.E): шаги {phase, text, a, b} — реплика и доли сил
## сторон (0..1) на этом шаге. Свой ГСЧ с зерном BattleRecord.replay_seed: тот же
## бой — тот же рассказ, мир не трогается (просмотр не меняет историю).

const DIR := "res://data/battle_lines/"

static var _reg: Registry


static func lines(phase: StringName) -> PackedStringArray:
	if _reg == null:
		_reg = Registry.new(DIR, BattleLinesDef)
	var d: BattleLinesDef = _reg.find(phase)
	return d.lines if d != null else PackedStringArray()


## Всего реплик в data/battle_lines (проверка «не меньше 150»).
static func total_lines() -> int:
	if _reg == null:
		_reg = Registry.new(DIR, BattleLinesDef)
	var n := 0
	for d in _reg.items:
		n += (d as BattleLinesDef).lines.size()
	return n


static func _fill(text: String, r: BattleRecord, world: World, fallen: String) -> String:
	var a: Dictionary = r.sides[0] if r.sides.size() > 0 else {}
	var b: Dictionary = r.sides[1] if r.sides.size() > 1 else {}
	var w: Dictionary = r.sides[r.winner] if r.winner >= 0 and r.winner < r.sides.size() else a
	var l: Dictionary = r.sides[1 - r.winner] if r.winner >= 0 and r.winner < r.sides.size() else b
	var place := "диких земель"
	if world != null and r.region >= 0 and r.region < world.regions.size() and not world.regions[r.region].name.is_empty():
		place = world.regions[r.region].name
	var terrain := "равнина"
	var bd := BiomeDB.find_by_id(r.terrain) if r.terrain != &"" else null
	if bd != null:
		terrain = bd.display_name.to_lower()
	var out := text.format({"a": a.get("name", "?"), "b": b.get("name", "?"), "w": w.get("name", "?"), "l": l.get("name", "?"),
		"place": place, "terrain": terrain, "ga": a.get("general", "") if str(a.get("general", "")) != "" else "командир",
		"gb": b.get("general", "") if str(b.get("general", "")) != "" else "командир", "fallen": fallen})
	# Подстановка в начале фразы («степь скрывает…») — с заглавной.
	return out.left(1).to_upper() + out.substr(1) if not out.is_empty() else out


static func _pick(rng: RandomNumberGenerator, phase: StringName) -> String:
	var ls := lines(phase)
	return ls[rng.randi_range(0, ls.size() - 1)] if not ls.is_empty() else ""


## Шаги пересказа записи r (world — для названий краёв; может быть null).
static func script(r: BattleRecord, world: World = null) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = r.replay_seed
	var phases: Array[StringName] = []
	match r.kind:
		&"battle":
			phases.append(&"opening")
			if rng.randf() < 0.6:
				phases.append(&"terrain")
			if str(r.sides[0].get("general", "")) != "" or str(r.sides[1].get("general", "")) != "":
				phases.append(&"general")
			for k in rng.randi_range(2, 4):
				phases.append(&"clash")
			phases.append_array([&"turn", &"victory", &"rout", &"aftermath"])
		&"duel":
			phases.append(&"duel_open")
			for k in rng.randi_range(2, 4):
				phases.append(&"duel_exchange")
			phases.append(&"duel_kill" if r.killed else &"duel_spare")
		_:
			phases.append(&"meet_open")
			phases.append(StringName("meet_" + (str(r.outcome) if r.outcome != &"" else "talk")))
	var fallen := ArmySystem._num(r.fallen)
	# Доли сил: от 1 к итогу (у битвы — по потерям, у поединка — проигравший к 0).
	var end_a := 1.0
	var end_b := 1.0
	if r.kind == &"battle" and r.sides.size() == 2:
		end_a = clampf(1.0 - float(r.sides[0].losses) / maxf(1.0, float(r.sides[0].power) * 10.0), 0.2, 1.0)
		end_b = clampf(1.0 - float(r.sides[1].losses) / maxf(1.0, float(r.sides[1].power) * 10.0), 0.2, 1.0)
		if r.winner == 0:
			end_b = minf(end_b, end_a * 0.7)
		else:
			end_a = minf(end_a, end_b * 0.7)
	elif r.kind == &"duel":
		end_a = rng.randf_range(0.35, 0.8)
		end_b = 0.0 if r.killed else 0.15
	var steps: Array[Dictionary] = []
	var used := {}
	for i in phases.size():
		var t := float(i + 1) / phases.size()
		var text := _pick(rng, phases[i])
		# Повтор той же реплики в одном рассказе — берём другую (если есть).
		for tries in 3:
			if not used.has(text):
				break
			text = _pick(rng, phases[i])
		used[text] = true
		var wob := rng.randf_range(-0.05, 0.05) if i < phases.size() - 1 else 0.0
		steps.append({"phase": phases[i], "text": _fill(text, r, world, fallen),
			"a": clampf(lerpf(1.0, end_a, t) + wob, 0.0, 1.0), "b": clampf(lerpf(1.0, end_b, t) - wob, 0.0, 1.0)})
	return steps


## Заголовок записи для списков и карточки.
static func title(r: BattleRecord, world: World = null) -> String:
	var a: String = r.sides[0].name if r.sides.size() > 0 else "?"
	var b: String = r.sides[1].name if r.sides.size() > 1 else "?"
	var what: String = {&"battle": "Битва", &"duel": "Поединок", &"meeting": "Встреча"}.get(r.kind, "Столкновение")
	var place := ""
	if world != null and r.region >= 0 and r.region < world.regions.size() and not world.regions[r.region].name.is_empty():
		place = " у " + world.regions[r.region].name
	return "%s%s: %s — %s (%d г.)" % [what, place, a, b, r.year]
