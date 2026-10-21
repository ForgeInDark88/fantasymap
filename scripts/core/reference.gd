class_name Reference
## Справочник (этап 11.F), собранный из данных игры: расы, биомы, постройки,
## технологии, веры, товары, болезни, логова, племена, нравы держав, задания,
## классы героев, формы правления, кризисы, события, артефакты, боги,
## организации, режимы карты, инструменты Бога и команды героя. Один источник
## для окна «Справочник» и для docs/REFERENCE.md (tests/reference_test.gd
## проверяет, что файл не устарел: tests/gen_reference.gd его пересобирает).

const DOC := "res://docs/REFERENCE.md"


## Разделы: [{title, entries: [{name, text}]}].
static func sections() -> Array:
	var res: Array = []
	res.append(_section("Расы", RaceDB.all(), func(r: RaceDef) -> String:
		return "%s Особенности: %s." % [r.description, ", ".join(r.traits.map(func(t: StringName) -> String: return String(t))) if not r.traits.is_empty() else "нет"]))
	res.append(_section("Биомы", BiomeDB.all(), func(b: BiomeDef) -> String: return b.description if "description" in b and not str(b.get("description")).is_empty() else ""))
	res.append(_section("Постройки", EconomyDB.buildings(), func(b: BuildingDef) -> String: return b.description))
	res.append(_section("Технологии", TechDB.all(), func(t: Resource) -> String: return str(t.get("description"))))
	res.append(_section("Веры", ReligionDB.all(), func(r: Resource) -> String: return str(r.get("description"))))
	res.append(_section("Товары рынка", MarketDB.all(), func(g: GoodDef) -> String:
		return "%s Обычная цена: %.1f; портится %d%% в год%s." % [g.description, g.base_price, roundi(g.spoil * 100.0),
			" · роскошь" if g.luxury else (" · насущный" if g.staple else (" · военный" if g.military else ""))]))
	res.append(_section("Болезни", DiseaseDB.all(), func(d: DiseaseDef) -> String:
		return "%s Держится %d мес., губит до %d%% жителей края, иммунитет %d лет." % [d.description, d.months, roundi(d.lethality * 100.0), d.immunity_years]))
	res.append(_section("Логова и чудовища", LairDB.all(), func(l: LairDef) -> String:
		return "%s%s Сила %d–%d." % [l.description, " Великое чудовище." if l.great else "", roundi(l.strength.x), roundi(l.strength.y)]))
	res.append(_section("Племена", TribeDB.all(), func(t: TribeDef) -> String:
		return "%s %s." % [t.description, "Кочевники (собираются в орды)" if t.nomad else "Оседлые"]))
	res.append(_section("Нравы держав", PersonalityDB.all(), func(p: PersonalityDef) -> String:
		return "%s Воинственность ×%.2f, охота к сделкам ×%.1f." % [p.description, p.aggression, p.deal_rate]))
	if Features.HERO_PLAY:
		res.append(_section("Задания героя", QuestDB.all(), func(q: QuestDef) -> String: return q.description if not q.description.is_empty() else q.title))
	res.append(_section("Классы героев", PoliticsDB.hero_classes(), func(c: HeroClassDef) -> String: return c.description))
	res.append(_section("Черты правителей", PoliticsDB.ruler_traits(), func(t: RulerTraitDef) -> String: return t.description))
	res.append(_section("Мировые кризисы", CrisisDB.all(), func(c: Resource) -> String: return str(c.get("description"))))
	res.append(_section("События государств", EconomyDB.events(), func(e: EventDef) -> String: return e.text.replace("{", "").replace("}", "")))
	res.append(_section("Артефакты", LoreDB.artifacts(), func(a: Resource) -> String: return str(a.get("description"))))
	res.append(_section("Боги", LoreDB.gods(), func(g: Resource) -> String: return str(g.get("description"))))
	res.append(_section("Организации", OrgDB.orgs(), func(o: Resource) -> String: return str(o.get("description"))))
	res.append(_section("Поселения", SettlementDB.all(), func(d: Resource) -> String: return str(d.get("description"))))
	var modes: Array = []
	for i in MapMode.NAMES.size():
		modes.append({"name": MapMode.NAMES[i], "text": "Клавиша %s." % MapMode.hotkey_label(i)})
	res.append({"title": "Режимы карты", "entries": modes})
	var tools: Array = []
	for t in GodToolList.TOOLS:
		tools.append({"name": t[1], "text": t[2]})
	res.append({"title": "Инструменты Бога", "entries": tools})
	if Features.HERO_PLAY:
		var cmds: Array = []
		for c in PlayerSystem.COMMANDS:
			cmds.append({"name": c[1], "text": ("Занимает месяцев: %d." % c[2]) if int(c[2]) > 0 else "Сразу."})
		res.append({"title": "Команды героя", "entries": cmds})
	return res


static func _section(title: String, items: Array, describe: Callable) -> Dictionary:
	var entries: Array = []
	for it in items:
		var name := str(it.get("display_name")) if it.get("display_name") != null else str(it.get("id"))
		entries.append({"name": name, "text": String(describe.call(it)).strip_edges()})
	return {"title": title, "entries": entries}


static func to_markdown() -> String:
	var lines: Array[String] = ["# Справочник Fantasy Map Simulator", "",
		"Собран из данных игры (`data/`) скриптом `tests/gen_reference.gd`; не правьте вручную.", ""]
	for s in sections():
		lines.append("## %s" % s.title)
		lines.append("")
		for e in s.entries:
			lines.append("- **%s**%s" % [e.name, (" — " + String(e.text)) if not String(e.text).is_empty() else ""])
		lines.append("")
	return "\n".join(lines)
