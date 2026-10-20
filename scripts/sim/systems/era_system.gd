class_name EraSystem
extends RefCounted
## Эпохи мира (раз в ERA_CHECK лет). Название эпохи — по тому, что
## господствовало в летописи последних WINDOW лет: войны («Эпоха Мечей»), мор,
## пророки и ереси, знания, герои, тайны, смуты, мир и торговля («Золотой
## век»), стихии, глубины. Идущий мировой кризис даёт эпохе своё имя («Эпоха
## Мора»), а если одна раса держит больше RACE_DOMINANCE занятой суши —
## эпоха её («Эпоха Железных королей»). Эпохи — в World.eras с годами начала
## и конца; текущая видна в шапке и в летописи.

const ERA_CHECK := 25
const WINDOW := 50
const RACE_DOMINANCE := 0.35
## Тема → (виды записей летописи, имя эпохи, вес).
const THEMES := {
	"war": [[&"war", &"siege", &"conquest"], "Эпоха Мечей", 1.0],
	"plague": [[&"plague", &"famine", &"disaster"], "Эпоха Поветрий", 1.6],
	"faith": [[&"religion"], "Эпоха Пророков", 1.8],
	"lore": [[&"tech", &"culture"], "Эпоха Знаний", 1.6],
	"heroes": [[&"hero", &"great"], "Эпоха Героев", 0.3],
	"intrigue": [[&"intrigue"], "Эпоха Тайн", 1.0],
	"strife": [[&"rebellion", &"collapse", &"fall"], "Эпоха Смут", 1.8],
	"peace": [[&"treaty", &"trade", &"org", &"peace"], "Золотой век", 1.4],
	"elements": [[&"climate"], "Эпоха Стихий", 2.0],
	"depths": [[&"underground"], "Эпоха Глубин", 2.0],
}


func tick_year(world: World) -> void:
	if world.eras.is_empty():
		world.eras.append({"name": "Эпоха Зари", "start": world.year, "end": -1})
		return
	# Кризис начался или кончился — эпоха меняется сразу, иначе — раз в ERA_CHECK лет.
	var crisis_era := _crisis_era(world)
	var now := current(world)
	var crisis_changed := (not crisis_era.is_empty() and now != crisis_era) or (crisis_era.is_empty() and _is_crisis_era(now))
	if world.year % ERA_CHECK != 0 and not crisis_changed:
		return
	var name := current_name(world)
	if not world.eras.is_empty() and world.eras[world.eras.size() - 1].name == name:
		return
	if not world.eras.is_empty():
		world.eras[world.eras.size() - 1].end = world.year
	world.eras.append({"name": name, "start": world.year, "end": -1})
	if world.year > 0:
		world.log_event(&"era", "Наступает %s (%d г.)." % [name, world.year])


## Имя эпохи по нынешнему положению дел.
static func current_name(world: World) -> String:
	var crisis_era := _crisis_era(world)
	if not crisis_era.is_empty():
		return crisis_era
	# Господство одной расы.
	var owned := {}
	var total := 0
	for n in world.nations:
		if n.alive:
			owned[n.race_id] = owned.get(n.race_id, 0) + n.cell_count
			total += n.cell_count
	for race_id in owned:
		var race := RaceDB.get_race(race_id)
		if total > 0 and owned[race_id] > total * RACE_DOMINANCE and race != null and not race.era_title.is_empty():
			return "Эпоха %s" % race.era_title
	# Тема летописи последних WINDOW лет.
	var counts := {}
	for e in world.chronicle:
		if e.year >= world.year - WINDOW:
			counts[e.kind] = counts.get(e.kind, 0) + 1
	var best := "Эпоха Зари"
	var best_score := 0.0
	for theme in THEMES:
		var def: Array = THEMES[theme]
		var score := 0.0
		for kind in def[0]:
			score += counts.get(kind, 0)
		score *= def[2]
		if score > best_score:
			best_score = score
			best = def[1]
	return best


static func _crisis_era(world: World) -> String:
	if world.crisis.is_empty():
		return ""
	var def := CrisisDB.find(StringName(world.crisis.id))
	return def.era_name if def != null else ""


static func _is_crisis_era(name: String) -> bool:
	for c in CrisisDB.all():
		if (c as CrisisDef).era_name == name:
			return true
	return false


static func current(world: World) -> String:
	return world.eras[world.eras.size() - 1].name if not world.eras.is_empty() else "Эпоха Зари"
