class_name Chronicler
extends RefCounted
## Летописец: собирает из данных мира связные истории для панели «Хроники»
## (эпохи, войны, герои, державы и династии, веры, организации) по шаблонам
## data/chronicle_templates. Варианты выбирает собственный ГСЧ, засеянный
## id истории и seed мира: тексты стабильны и не трогают ГСЧ симуляции.
## Каждое событие летописи и каждая история получают «значимость» —
## по ней отбирается главное. Экспорт истории — Markdown в user://chronicles/.

## Значимость записи летописи по её виду (остальные — 1).
const KIND_WEIGHT := {&"great": 5.0, &"crisis": 5.0, &"era": 4.5, &"fall": 4.0, &"nation": 3.0, &"conquest": 3.0,
	&"war": 2.5, &"peace": 2.0, &"religion": 2.5, &"gods": 2.0, &"rebellion": 2.0, &"legacy": 3.0, &"org": 2.0,
	&"fate": 2.5, &"artifact": 2.0, &"lineage": 1.5, &"order": 1.5, &"hero": 1.2, &"climate": 2.0, &"underground": 2.0}
## Порог «ключевого» события.
const KEY_EVENT := 4.0
## Чем стали поводы войн (для текста «Поводом стали …»).
const CAUSE_TEXT := {&"territory": "споры о землях", &"resources": "богатства соседа", &"racial": "вековая вражда народов",
	&"holy": "дела веры", &"crusade": "призыв к крестовому походу", &"schism": "раскол веры", &"religious": "дела веры",
	&"espionage": "раскрытые козни шпионов", &"reunification": "мечты о воссоединении империи", &"invasion": "жажда нашествия",
	&"revenge": "старые обиды", &"independence": "стремление к свободе", &"civil": "распри внутри державы",
	&"expansion": "жажда завоеваний", &"reconquest": "утраченные земли", &"coalition": "страх перед гегемоном",
	&"demonic": "голод бездны", &"divine": "воля богов"}
const TOPIC_SHORT := {&"era": "Эпоха", &"war": "Война", &"hero": "Герой", &"nation": "Держава", &"religion": "Вера", &"org": "Союз"}
const TOPIC_NAMES := {&"era": "Эпохи", &"war": "Войны", &"hero": "Герои", &"nation": "Державы и династии",
	&"religion": "Веры", &"org": "Организации"}
const EXPORT_DIR := "user://chronicles/"
## Сколько событий эпохи и державы попадает в рассказ.
const EVENTS_PER_STORY := 6

static var _templates: Registry


static func template(topic: StringName) -> ChronicleTemplateDef:
	if _templates == null:
		_templates = Registry.new("res://data/chronicle_templates/", ChronicleTemplateDef)
	for t in _templates.items:
		if (t as ChronicleTemplateDef).topic == topic:
			return t
	return null


static func significance(entry: Dictionary) -> float:
	var w: float = KIND_WEIGHT.get(entry.kind, 1.0)
	return w + minf(1.0, (entry.nations as PackedInt32Array).size() * 0.25) if entry.has("nations") else w


## Ключевые события летописи (значимость ≥ KEY_EVENT), новые первыми.
static func key_events(world: World, limit: int = 200) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for i in range(world.chronicle.size() - 1, -1, -1):
		var e: Dictionary = world.chronicle[i]
		if significance(e) >= KEY_EVENT:
			res.append(e)
			if res.size() >= limit:
				break
	return res


static func bookmark_key(e: Dictionary) -> String:
	return "%d.%d.%d|%s" % [int(e.year), int(e.month), int(e.day), e.text]


static func is_bookmarked(world: World, e: Dictionary) -> bool:
	var key := bookmark_key(e)
	return world.bookmarks.any(func(b: Dictionary) -> bool: return bookmark_key(b) == key)


static func toggle_bookmark(world: World, e: Dictionary) -> bool:
	var key := bookmark_key(e)
	for i in world.bookmarks.size():
		if bookmark_key(world.bookmarks[i]) == key:
			world.bookmarks.remove_at(i)
			return false
	world.bookmarks.append({"year": int(e.year), "month": int(e.month), "day": int(e.day), "kind": String(e.kind), "text": e.text})
	return true


# ---------------------------------------------------------------------------
# Список историй (только заголовки и связи — текст собирается по запросу)
# ---------------------------------------------------------------------------

## История: {id, topic, ref, title, start, end, significance, nations, races, religions, heroes}.
static func stories(world: World) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for i in world.eras.size():
		var e: Dictionary = world.eras[i]
		var end := int(e.end) if int(e.end) >= 0 else world.year
		res.append(_story("era:%d" % i, &"era", i, _title(world, &"era", "era:%d" % i, {"era": e.name, "start": e.start, "end": end}),
			int(e.start), end, 3.0 + (end - int(e.start)) / 25.0))
	var wars: Array[War] = []
	wars.append_array(world.diplomacy.past_wars)
	wars.append_array(world.diplomacy.wars)
	for w in wars:
		var s := _story("war:%d" % w.id, &"war", w.id, w.name, w.start_year, w.end_year if w.end_year >= 0 else world.year,
			1.0 + w.battles * 0.3 + w.casualties / 50000.0 + (w.attackers.size() + w.defenders.size()) * 0.2)
		s.nations = PackedInt32Array(Array(w.attackers) + Array(w.defenders))
		for first in [w.first_attacker, w.first_defender]:
			if first >= 0 and not s.nations.has(first):
				s.nations.append(first)
		for n in s.nations:
			_add(s.races, world.nations[n].race_id)
		res.append(s)
	for h in world.heroes:
		if h.level < 6 and h.deeds.size() < 8:
			continue
		var s := _story("hero:%d" % h.id, &"hero", h.id, _title(world, &"hero", "hero:%d" % h.id, {"hero": h.display_name()}),
			h.born_year, world.year if h.alive else h.born_year + h.age, 1.0 + h.level * 0.3 + h.deeds.size() * 0.05)
		s.heroes = PackedInt32Array([h.id])
		_add(s.races, h.race_id)
		if h.nation_id >= 0:
			s.nations = PackedInt32Array([h.nation_id])
		res.append(s)
	for n in world.nations:
		var end := world.year if n.alive else _last_seen(world, n.id)
		if not n.alive and end - n.founded_year < 20:
			continue
		var peak := _peak(world, n.id)
		var s := _story("nation:%d" % n.id, &"nation", n.id, _title(world, &"nation", "nation:%d" % n.id, {"nation": n.name, "start": n.founded_year, "end": end}),
			n.founded_year, end, 1.0 + peak.x / 60.0 + (end - n.founded_year) / 100.0)
		s.nations = PackedInt32Array([n.id])
		_add(s.races, n.race_id)
		if n.state_religion >= 0:
			s.religions = PackedInt32Array([n.state_religion])
		res.append(s)
	for r in world.religions:
		var s := _story("religion:%d" % r.id, &"religion", r.id, _title(world, &"religion", "religion:%d" % r.id, {"religion": r.name}),
			r.founded_year, world.year, 2.0 + (1.0 if r.alive else 0.0))
		s.religions = PackedInt32Array([r.id])
		res.append(s)
	for o in world.orgs:
		var s := _story("org:%d" % o.id, &"org", o.id, _title(world, &"org", "org:%d" % o.id, {"org": o.name}),
			o.founded_year, world.year, 1.5 + o.members.size() * 0.2)
		s.nations = o.members.duplicate()
		res.append(s)
	res.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.start < b.start if a.start != b.start else a.id < b.id)
	return res


static func _story(id: String, topic: StringName, ref: int, title: String, start: int, end: int, sig: float) -> Dictionary:
	return {"id": id, "topic": topic, "ref": ref, "title": title, "start": start, "end": end, "significance": sig,
		"nations": PackedInt32Array(), "races": [], "religions": PackedInt32Array(), "heroes": PackedInt32Array()}


static func _add(list: Array, v: Variant) -> void:
	if not list.has(v):
		list.append(v)


## Фильтр: f = {topic, nation, era, race, religion, hero, text} (пустые / -1 — любые).
static func matches(world: World, s: Dictionary, f: Dictionary) -> bool:
	if f.get("topic", &"") != &"" and s.topic != f.topic:
		return false
	if int(f.get("nation", -1)) >= 0 and not (s.nations as PackedInt32Array).has(int(f.nation)):
		return false
	if int(f.get("religion", -1)) >= 0 and not (s.religions as PackedInt32Array).has(int(f.religion)):
		return false
	if int(f.get("hero", -1)) >= 0 and not (s.heroes as PackedInt32Array).has(int(f.hero)):
		return false
	if f.get("race", &"") != &"" and not (s.races as Array).has(f.race):
		return false
	if int(f.get("era", -1)) >= 0 and int(f.era) < world.eras.size():
		var e: Dictionary = world.eras[int(f.era)]
		var end := int(e.end) if int(e.end) >= 0 else world.year
		if s.end < int(e.start) or s.start > end:
			return false
	var q := String(f.get("text", "")).strip_edges().to_lower()
	if not q.is_empty() and not String(s.title).to_lower().contains(q):
		return String(text(world, s)).to_lower().contains(q)
	return true


static func _last_seen(world: World, nation_id: int) -> int:
	for i in range(world.history.size() - 1, -1, -1):
		if (world.history[i].nations as Dictionary).has(nation_id):
			return int(world.history[i].year)
	return world.nations[nation_id].founded_year


## Пик державы по снимкам истории: (клеток, жителей).
static func _peak(world: World, nation_id: int) -> Vector2:
	var best := Vector2.ZERO
	for h in world.history:
		var snap: Dictionary = h.nations
		if snap.has(nation_id):
			var v: PackedFloat32Array = snap[nation_id]
			if v[1] > best.x:
				best = Vector2(v[1], v[0])
	return best


# ---------------------------------------------------------------------------
# Текст истории
# ---------------------------------------------------------------------------

static func _rng(world: World, id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) ^ world.settings.world_seed
	return rng


static func _title(world: World, topic: StringName, id: String, vars: Dictionary) -> String:
	var t := template(topic)
	if t == null or t.titles.is_empty():
		return str(vars.values()[0])
	var rng := _rng(world, id + ":title")
	return _fill(t, t.titles[rng.randi_range(0, t.titles.size() - 1)], vars, rng)


## Вариант части key (с уточнением spec, если есть такой ключ, иначе общий).
static func _part(t: ChronicleTemplateDef, key: String, vars: Dictionary, rng: RandomNumberGenerator, spec: String = "") -> String:
	var k := key + "_" + spec if not spec.is_empty() and t.parts.has(key + "_" + spec) else key
	if not t.parts.has(k) or t.parts[k].is_empty():
		return ""
	return _fill(t, t.parts[k][rng.randi_range(0, t.parts[k].size() - 1)], vars, rng)


static func _fill(t: ChronicleTemplateDef, pattern: String, vars: Dictionary, rng: RandomNumberGenerator) -> String:
	var s := pattern.format(vars)
	var common := template(&"common")
	var i := s.find("[")
	while i >= 0:
		var j := s.find("]", i)
		if j < 0:
			break
		var word := s.substr(i + 1, j - i - 1)
		var pool: PackedStringArray = t.words.get(word, common.words.get(word, PackedStringArray()) if common != null else PackedStringArray())
		var rep := pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else word
		s = s.substr(0, i) + rep + s.substr(j + 1)
		i = s.find("[", i + rep.length())
	return s


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if not s.is_empty() else s


static func _low(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1) if not s.is_empty() else s


static func _names(world: World, ids: PackedInt32Array) -> String:
	return ", ".join(Array(ids).map(func(id: int) -> String: return world.nations[id].name))


## Связный текст истории: абзацы через пустую строку.
static func text(world: World, s: Dictionary) -> String:
	var t := template(s.topic)
	if t == null:
		return ""
	var rng := _rng(world, s.id)
	var p: Array[String] = []
	match s.topic:
		&"era":
			var e: Dictionary = world.eras[int(s.ref)]
			var vars := {"era": e.name, "start": s.start, "end": s.end}
			var counts := {&"war": 0, &"fall": 0, &"nation": 0}
			var events: Array[Dictionary] = []
			for c in world.chronicle:
				if int(c.year) < s.start or int(c.year) > s.end:
					continue
				if counts.has(c.kind):
					counts[c.kind] += 1
				events.append(c)
			var dark: bool = String(e.name).contains("Мор") or String(e.name).contains("Смут") or String(e.name).contains("Мечей") \
					or String(e.name).contains("Ледник") or String(e.name).contains("Орд") or counts[&"war"] > counts[&"nation"] * 3
			var bright: bool = String(e.name).contains("Золот") or String(e.name).contains("Знани") or String(e.name).contains("Пророк")
			p.append(_part(t, "intro", vars, rng, "dark" if dark else ("bright" if bright else "")))
			vars.merge({"wars": counts[&"war"], "falls": counts[&"fall"], "born": counts[&"nation"]})
			p.append(_part(t, "stats", vars, rng))
			p.append(_events_text(t, events, rng))
			p.append(_part(t, "outro", vars, rng))
		&"war":
			var w := _war(world, int(s.ref))
			var a_id := w.first_attacker if w.first_attacker >= 0 else (w.attackers[0] if not w.attackers.is_empty() else -1)
			var d_id := w.first_defender if w.first_defender >= 0 else (w.defenders[0] if not w.defenders.is_empty() else -1)
			var att := world.nations[a_id].name if a_id >= 0 else "без имени"
			var def := world.nations[d_id].name if d_id >= 0 else "без имени"
			var years := maxi(1, int(s.end) - int(s.start))
			var vars := {"war": w.name, "start": s.start, "end": s.end, "attacker": att, "defender": def,
				"cause": CAUSE_TEXT.get(w.cause, "давние распри"), "battles": w.battles, "casualties": _num(w.casualties),
				"years": "%d %s" % [years, _years_word(years)]}
			p.append(_part(t, "intro", vars, rng))
			if w.attackers.size() > 1:
				vars.att_allies = _names(world, w.attackers.slice(1))
				p.append(_part(t, "allies", vars, rng))
			if w.defenders.size() > 1:
				vars.def_allies = _names(world, w.defenders.slice(1))
				p.append(_part(t, "def_allies", vars, rng))
			p.append(_part(t, "battles", vars, rng))
			if w.end_year < 0:
				p.append(_part(t, "ongoing", vars, rng))
			else:
				p.append(_part(t, "victory" if w.score > 25.0 else ("defeat" if w.score < -25.0 else "draw"), vars, rng))
				p.append(_part(t, "outro", vars, rng))
		&"hero":
			var h := world.heroes[int(s.ref)]
			var vars := {"hero": h.display_name(), "race": h.race.display_name.to_lower(), "cls": h.hero_class.display_name.to_lower(),
				"born": h.born_year, "age": h.age}
			var spec := String(h.race_id) if t.parts.has("intro_" + String(h.race_id)) else ("light" if h.karma > 0.4 else ("dark" if h.karma < -0.4 else ""))
			p.append(_part(t, "intro", vars, rng, spec))
			if h.lineage >= 0:
				vars.lineage = world.lineages[h.lineage].name
				p.append(_part(t, "family", vars, rng))
			var deeds: Array[String] = []
			for d in h.deeds:
				deeds.append(_part(t, "deed", {"deed": d, "Deed": _cap(d)}, rng))
			p.append(" ".join(deeds))
			p.append(_part(t, "outro_ruler" if h.is_ruler else ("outro_dead" if not h.alive else "outro_alive"), vars, rng))
		&"nation":
			var n := world.nations[int(s.ref)]
			var peak := _peak(world, n.id)
			var vars := {"nation": n.name, "race": n.race.display_name, "start": s.start, "end": s.end,
				"dynasty": n.dynasty, "ruler": n.ruler_display(), "cells": int(peak.x), "pop": _num(peak.y)}
			var gov := String(n.government.id) if n.government != null else ""
			p.append(_part(t, "intro", vars, rng, gov))
			if n.alive and not n.dynasty.is_empty():
				p.append(_part(t, "dynasty", vars, rng))
			if peak.x > 0.0:
				p.append(_part(t, "peak", vars, rng))
			var wars := 0
			var main: War = null
			for w in world.diplomacy.past_wars + world.diplomacy.wars:
				if w.side_of(n.id) != 0:
					wars += 1
					if main == null or w.casualties > main.casualties:
						main = w
			if main != null:
				vars.merge({"wars": wars, "main_war": main.name})
				p.append(_part(t, "wars", vars, rng))
			var events: Array[Dictionary] = []
			for c in world.chronicle:
				if (c.nations as PackedInt32Array).has(n.id):
					events.append(c)
			p.append(_events_text(t, events, rng))
			p.append(_part(t, "alive" if n.alive else "fell", vars, rng))
		&"religion":
			var r := world.religions[int(s.ref)]
			var vars := {"religion": r.name, "start": r.founded_year}
			p.append(_part(t, "intro", vars, rng))
			if r.parent >= 0:
				vars.parent = world.religions[r.parent].name
				vars.origin = world.nations[r.origin_nation].name if r.origin_nation >= 0 else "неведомом"
				p.append(_part(t, "heresy", vars, rng))
			if not r.dogmas.is_empty():
				vars.dogmas = ", ".join(r.dogmas).to_lower()
				p.append(_part(t, "dogmas", vars, rng))
			var followers := PackedInt32Array()
			for n in world.nations:
				if n.alive and n.state_religion == r.id:
					followers.append(n.id)
			if not followers.is_empty():
				vars.nations = _names(world, followers)
				p.append(_part(t, "followers", vars, rng))
			elif not r.alive:
				p.append(_part(t, "dead", vars, rng))
		&"org":
			var o := world.orgs[int(s.ref)]
			var vars := {"org": o.name, "kind": o.def.display_name.to_lower() if o.def != null else "союз", "start": o.founded_year,
				"founder": world.nations[o.founder].name if o.founder >= 0 else "неведомое государство"}
			p.append(_part(t, "intro", vars, rng))
			if o.alive and not o.members.is_empty():
				vars.members = _names(world, o.members)
				p.append(_part(t, "members", vars, rng))
			elif not o.alive:
				p.append(_part(t, "dead", vars, rng))
	return "\n\n".join(p.filter(func(x: String) -> bool: return not x.is_empty()))


## Главные события (по значимости) — абзац «В 123 году: …».
static func _events_text(t: ChronicleTemplateDef, events: Array[Dictionary], rng: RandomNumberGenerator) -> String:
	var top := events.duplicate()
	top.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return significance(a) > significance(b))
	top = top.slice(0, EVENTS_PER_STORY)
	top.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.year) < int(b.year))
	var lines: Array[String] = []
	for e in top:
		lines.append(_part(t, "event", {"year": e.year, "text": e.text, "lower": _low(e.text)}, rng))
	return " ".join(lines)


static func _war(world: World, id: int) -> War:
	for w in world.diplomacy.wars:
		if w.id == id:
			return w
	for w in world.diplomacy.past_wars:
		if w.id == id:
			return w
	return War.new()


static func _num(v: float) -> String:
	if v >= 1e6:
		return "%.1f млн" % (v / 1e6)
	if v >= 1e3:
		return "%d тыс." % roundi(v / 1e3)
	return str(roundi(v))


static func _years_word(n: int) -> String:
	var m := n % 100
	if m >= 11 and m <= 14:
		return "лет"
	match n % 10:
		1:
			return "год"
		2, 3, 4:
			return "года"
	return "лет"


# ---------------------------------------------------------------------------
# Экспорт
# ---------------------------------------------------------------------------

## Сущности истории для ссылок: [тип, id, имя].
static func entities(world: World, s: Dictionary) -> Array:
	var res: Array = []
	for n in s.nations:
		res.append(["nation", n, world.nations[n].name])
	for h in s.heroes:
		res.append(["hero", h, world.heroes[h].display_name()])
	for r in s.religions:
		res.append(["religion", r, world.religions[r].name])
	return res


## Markdown-файл истории в user://chronicles/. Возвращает путь (или "" при ошибке).
static func export_markdown(world: World, s: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var body := text(world, s)
	var ents := entities(world, s)
	for e in ents:
		var anchor := "%s-%d" % [e[0], e[1]]
		var i := body.find(e[2])
		if i >= 0:
			body = body.substr(0, i) + "[%s](#%s)" % [e[2], anchor] + body.substr(i + String(e[2]).length())
	var lines: Array[String] = ["# %s" % s.title, "", "*%d—%d гг. · %s · значимость %.1f*" % [s.start, s.end,
		TOPIC_NAMES.get(s.topic, ""), s.significance], "", body]
	if not ents.is_empty():
		lines.append_array(["", "## Упомянутые", ""])
		for e in ents:
			var what: String = {"nation": "государство", "hero": "герой", "religion": "вера"}[e[0]]
			lines.append("- <a id=\"%s-%d\"></a>**%s** — %s" % [e[0], e[1], e[2], what])
	var slug := String(s.title).to_lower().replace(" ", "_")
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "«", "»", "(", ")", "—", ","]:
		slug = slug.replace(ch, "")
	var path := EXPORT_DIR + "%s_%s.md" % [slug.left(60), String(s.id).replace(":", "_")]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return path
