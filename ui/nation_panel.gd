class_name NationPanel
extends PanelContainer
## Карточка государства. Обновляется на лету, пока идёт симуляция
## (полная панель с дипломатией и историей — этап 5).

signal close_requested

const GOODS_COLORS: Array[String] = ["#9fd88a", "#c89a6a", "#b8bcc4", "#9fb8d8", "#f0d060"]

@onready var _icon: TextureRect = %Icon
@onready var _name: Label = %NameLabel
@onready var _sub: Label = %SubLabel
@onready var _color_bar: ColorRect = %ColorBar
@onready var _body: RichTextLabel = %Body

var _nation_id := -1
## Клетка, по которой кликнули (регион и город в ней показываются вверху карточки).
var _cell := -1


func _ready() -> void:
	%CloseButton.pressed.connect(close_requested.emit)
	_body.scroll_active = true
	_body.meta_underlined = false
	_body.fit_content = false
	_body.meta_clicked.connect(func(meta: Variant) -> void:
		if str(meta) == "techs":
			EventBus.tech_window_requested.emit(_nation_id)
			return
		var id := int(str(meta))
		if id >= 0:
			EventBus.nation_selected.emit(id))


func show_nation(world: World, nation: Nation, cell: int = -1) -> void:
	if nation.id != _nation_id or cell >= 0:
		_cell = cell
	_nation_id = nation.id
	refresh(world)
	show()


func refresh(world: World) -> void:
	if world == null or _nation_id < 0 or _nation_id >= world.nations.size():
		return
	var nation := world.nations[_nation_id]
	var race := nation.race
	_icon.texture = race.icon
	_name.text = nation.name
	_sub.text = "%s · основано в %d г. · %s" % [race.display_name, nation.founded_year,
			("%d лет" % (world.year - nation.founded_year)) if nation.alive else "[пало]"]
	_color_bar.color = nation.color

	var capital := world.cities[nation.capital_city] if nation.capital_city >= 0 else null
	var lines: Array[String] = []
	_append_place(world, nation, lines)
	var gov_name := nation.government.display_name if nation.government != null else "—"
	var trait_text := ""
	if nation.ruler_trait != null:
		trait_text = " · [color=#e8d9a0]%s[/color]" % nation.ruler_trait.display_name.to_lower()
	lines.append_array([
		"[b]Правление:[/b] %s, род %s" % [gov_name, nation.dynasty],
		"[b]Правитель:[/b] %s (%d лет)%s" % [nation.ruler_display(), nation.ruler_age, trait_text],
		"[b]Столица:[/b] %s (%s жит.)" % [capital.name, fmt(capital.population)] if capital != null else "[b]Столица:[/b] —",
		"[b]Территория:[/b] %d клеток · [b]городов:[/b] %d" % [nation.cell_count, nation.city_ids.size()],
		"[b]Население:[/b] %s из %s возможных" % [fmt(UiAnim.roll("n%d.pop" % nation.id, nation.population)), fmt(nation.total_capacity())],
		"[b]Армия:[/b] %s · [b]наука:[/b] %.1f" % [fmt(UiAnim.roll("n%d.army" % nation.id, nation.army)), nation.tech],
		"[b]Стабильность:[/b] %s" % _stability_text(nation.stability),
	])
	var researching := TechDB.find(nation.researching) if nation.researching != &"" else null
	lines.append("[b]Знания:[/b] %d из %d технологий%s · [url=techs][color=#a8e0ff]окно технологий[/color][/url]" % [
		nation.techs.size(), TechDB.all().size(),
		(" · изучается: %s (%d%%)" % [researching.display_name, roundi(minf(1.0, nation.research / researching.cost) * 100.0)]) if researching != null else ""])
	var roads := {}
	var trade := 0.0
	for id in nation.city_ids:
		for rid in world.city_roads.get(id, PackedInt32Array()):
			var r := world.roads[rid]
			if r.alive and not roads.has(rid):
				roads[rid] = r
				trade += r.traffic * (0.5 if world.cities[r.other(id)].nation_id != nation.id else 1.0)
	if not roads.is_empty():
		var sea := roads.values().filter(func(r: Road) -> bool: return r.sea).size()
		lines.append("[b]Пути:[/b] дорог %d, морских %d · торговля по ним: %s золота в год" % [roads.size() - sea, sea, fmt(trade)])
	_append_market(world, nation, lines)
	var caves := UndergroundSystem.owned_by(world, nation.id)
	if not caves.is_empty():
		lines.append("[b]Под землёй:[/b] пещер %d, подземных городов %d%s" % [caves.size(), caves.filter(func(c: Cave) -> bool: return c.city).size(),
			(" · жилы: " + ", ".join(caves.filter(func(c: Cave) -> bool: return c.kind == &"mithril" or c.kind == &"gems").map(func(c: Cave) -> String: return c.kind_name()))) if caves.any(func(c: Cave) -> bool: return c.kind == &"mithril" or c.kind == &"gems") else ""])
	var spies := SpySystem.spies_of(world, nation).size()
	lines.append("[b]Разведка:[/b] %d очков%s" % [roundi(nation.intel), (" · шпионов на службе: %d" % spies) if spies > 0 else ""])
	var armies := ArmySystem.armies_of(world, nation.id)
	if not armies.is_empty():
		lines.append("[b]Армии:[/b] " + ", ".join(armies.map(func(a: Army) -> String:
			return "%s %s (%s, дух %d%%%s)" % ["⚓" if a.kind == &"fleet" else "⚔", ArmySystem._num(a.strength(world)),
				ArmyCard.STATE_NAMES.get(a.state, String(a.state)), roundi(a.morale * 100.0),
				(", " + ArmySystem.general_name(world, a.general)) if a.general >= 0 else ""])))
	var gens := world.generals.filter(func(g: Dictionary) -> bool: return g.alive and int(g.nation) == nation.id)
	if not gens.is_empty():
		lines.append("[b]Полководцы:[/b] " + ", ".join(gens.slice(0, 5).map(func(g: Dictionary) -> String:
			return "%s (%d%%%s)" % [g.name, roundi(float(g.skill) * 100.0), ", в плену" if int(g.captured_by) >= 0 else ""])))
	var orgs := OrgSystem.orgs_of(world, nation.id)
	if not orgs.is_empty():
		lines.append("[b]Организации:[/b] " + ", ".join(orgs.map(func(o: Organization) -> String:
			return "[color=#%s]%s[/color]%s" % [o.def.color.to_html(false), o.name, " (основатель)" if o.founder == nation.id else ""])))
	if nation.legacy >= 0:
		var lg := world.legacies[nation.legacy]
		lines.append("[b]Наследие:[/b] осколок державы %s (память — до %d г.)%s" % [lg.name, lg.until_year,
			" · [color=#ffd24a]собиратель земель[/color]" if lg.collector == nation.id else ""])
	var relics: Array[String] = []
	for a in world.artifacts:
		if a.nation == nation.id:
			relics.append(a.name)
	if not relics.is_empty():
		lines.append("[b]Сокровищница:[/b] [color=#e8c060]%s[/color]" % ", ".join(relics))
	if nation.god_boon != &"" and LoreDB.god(nation.god_boon) != null:
		var g := LoreDB.god(nation.god_boon)
		lines.append("[b]Милость бога:[/b] [color=#%s]%s %s[/color] %s (до %d г.)" % [g.color.to_html(false), g.symbol, g.display_name,
			g.boon_text, nation.god_boon_until])
	var halls: Array[String] = []
	for o in world.orders:
		if o.alive and o.hall_cell >= 0 and world.owner[o.hall_cell] == nation.id:
			halls.append("%s (%d)" % [o.name, o.members.size()])
	if not halls.is_empty():
		lines.append("[b]Обители орденов:[/b] [color=#a8c8f0]%s[/color]" % ", ".join(halls))
	var secret: Array[String] = []
	for s in world.societies:
		if not s.alive:
			continue
		var inf := 0.0
		for rid in s.influence:
			if world.regions[rid].controller() == nation.id:
				inf = maxf(inf, s.influence[rid])
		if inf > 0.0:
			secret.append("%s «%s» (до %d%%)" % [s.kind_name(), s.name, roundi(inf * 100.0)])
	if not secret.is_empty():
		lines.append("[b]Тайные общества:[/b] [color=#c8a0e0]%s[/color]" % ", ".join(secret))
	if nation.culture >= 0:
		var culture := world.cultures[nation.culture]
		lines.append("[b]Культура:[/b] [color=#%s]%s[/color] (престиж %d) · обычаи: %s" % [culture.color.to_html(false), culture.name,
			roundi(nation.culture_level), ", ".join(culture.customs)])
	if not nation.hero_ids.is_empty():
		var heroes := Array(nation.hero_ids).map(func(id: int) -> String:
			var h := world.heroes[id]
			return "%s (%s, ур. %d)" % [h.display_name(), h.hero_class.display_name.to_lower(), h.level])
		lines.append("[b]Герои на службе:[/b] " + ", ".join(heroes))
	if nation.famine_years > 0:
		lines.append("[color=#ff9a7a]Голод уже %d г.[/color]" % nation.famine_years)

	# Народы государства — если оно многорасовое.
	var total := nation.population
	if total > 0.0 and nation.primary_share() < 0.995:
		var peoples: Array[String] = []
		for r in nation.pop.size():
			if nation.pop[r] / total >= 0.005:
				peoples.append("%s %d%%" % [RaceDB.by_index(r).display_name, roundi(nation.pop[r] / total * 100.0)])
		lines.append("[b]Народы:[/b] " + ", ".join(peoples))

	lines.append("")
	lines.append("[b]Запасы (прирост за год):[/b]")
	var goods_parts: Array[String] = []
	for g in Goods.COUNT:
		goods_parts.append("[color=%s]%s %s (%+d)[/color]" % [GOODS_COLORS[g], Goods.NAMES[g], fmt(nation.stock[g]), roundi(nation.income[g])])
	lines.append(", ".join(goods_parts))

	var built := {}
	for id in nation.city_ids:
		for b in world.cities[id].buildings:
			built[b] = built.get(b, 0) + 1
	if not built.is_empty():
		var parts: Array[String] = []
		for b in built:
			var def := EconomyDB.get_building(b)
			parts.append("%s ×%d" % [def.display_name if def != null else str(b), built[b]])
		lines.append("[b]Постройки:[/b] " + ", ".join(parts))

	_append_diplomacy(world, nation, lines)

	_append_history(world, nation, lines)

	lines.append("")
	lines.append("[b]Особенности расы:[/b]")
	for t in race.traits:
		var def := RaceDB.get_trait(t)
		if def != null:
			lines.append("• [color=#e8d9a0]%s[/color] — %s" % [def.display_name, def.description])
	lines.append("[b]Отношение к расам:[/b]")
	var rel_parts: Array[String] = []
	for other in RaceDB.all():
		var v := race.relation_to(other)
		var color := "#7fd18b" if v > 0.15 else ("#e07a6a" if v < -0.15 else "#c9ccd4")
		rel_parts.append("[color=%s]%s %+.1f[/color]" % [color, other.display_name, v])
	lines.append(", ".join(rel_parts))
	_body.text = "\n".join(lines)
	# Высота — по экрану; длинная карточка прокручивается.
	_body.custom_minimum_size = Vector2(300, clampf(get_viewport_rect().size.y - 190.0, 280.0, 680.0))


## Место клика: регион (народ, лояльность, претензии) и город (уровень, специализация, постройки).
func _append_place(world: World, nation: Nation, lines: Array[String]) -> void:
	if _cell < 0 or world.owner[_cell] != nation.id:
		return
	var region := world.region_at(_cell)
	var city := world.city_at(_cell)
	if city != null:
		var built := Array(city.buildings).map(func(b: StringName) -> String:
			var def := EconomyDB.get_building(b)
			return def.display_name if def != null else str(b))
		lines.append("[color=#9fd3ff][b]%s[/b][/color] — %s, %s; %s жителей (%s), основан в %d г.%s" % [
			city.name, city.tier_name().to_lower(), city.specialization(), fmt(city.population),
			RaceDB.get_race(city.race_id).display_name.to_lower(), city.founded_year,
			(" · столица" if city.is_capital else "")])
		if not built.is_empty():
			lines.append("Постройки: " + ", ".join(built))
		var rc := RoadSystem.road_count(world, city.id)
		if rc > 0:
			lines.append("Путей: %d%s" % [rc, " — торговый перекрёсток" if rc >= 3 else ""])
	if region != null:
		var people := world.region_majority_race(region, nation.id)
		var people_name := RaceDB.by_index(people).display_name.to_lower() if people != World.NO_RACE else "—"
		var claims := Array(region.claims.keys()).filter(func(id: int) -> bool: return id != nation.id and world.nations[id].alive)
		lines.append("[color=#e8d9a0][b]Регион %s[/b][/color] — %d кл., народ: %s, %s жит.; лояльность %d%%, недовольство %d%%" % [
			region.name, region.cells.size(), people_name, fmt(world.region_population(region, nation.id)),
			roundi(region.loyalty * 100.0), roundi(minf(region.unrest, 1.0) * 100.0)])
		if not region.faith.is_empty():
			lines.append("Вера: " + faith_text(world, region.faith, 3))
		var here: Array[String] = []
		for r in world.ruins:
			if r.cell >= 0 and not r.revived and world.region_of[r.cell] == region.id:
				here.append("%s (%s%s)" % [r.name, r.kind_name(), ", исчерпаны" if r.depleted() else ""])
		if not here.is_empty():
			lines.append("[color=#b8a8a0]Руины: %s[/color]" % ", ".join(here))
		for s in world.societies:
			if s.alive and s.influence.has(region.id):
				lines.append("[color=#c8a0e0]%s «%s»: влияние %d%%[/color]" % [s.kind_name().capitalize(), s.name, roundi(s.influence[region.id] * 100.0)])
		if region.culture >= 0:
			var rc := world.cultures[region.culture]
			lines.append("Культура: [color=#%s]%s[/color]%s" % [rc.color.to_html(false), rc.name,
				(" · ассимиляция %d%%" % roundi(region.assim * 100.0)) if region.culture != nation.culture else ""])
		if region.language >= 0:
			var lang := world.languages[region.language]
			lines.append("Язык: [color=#%s]%s[/color]%s" % [lang.color.to_html(false), LanguageSystem.title(world, region.language),
				(" · переход на язык державы %d%%" % roundi(region.lang_assim * 100.0)) if region.language != nation.language else ""])
		for w in wild_lines(world, region):
			lines.append("[color=#e0a080]%s[/color]" % w)
		if not claims.is_empty():
			lines.append("Претензии на регион: " + ", ".join(claims.map(func(id: int) -> String: return world.nations[id].short_name)))
	lines.append("")


## Рынок и общество (этап 11.D): сословия, рабство, индекс цен, долги, наёмники, дефицит.
func _append_market(world: World, nation: Nation, lines: Array[String]) -> void:
	if nation.market_price.size() != MarketDB.size():
		return
	lines.append("[b]Общество:[/b] %s%s" % [MarketWindow.class_line(nation).trim_prefix("Сословия: "),
		" · [color=#ff9a6a]рабство[/color]" if nation.slavery else ""])
	var short: Array[String] = []
	var goods := MarketDB.all()
	for i in goods.size():
		if nation.market_demand[i] > 0.5 and nation.market_used[i] < nation.market_demand[i] * 0.8:
			short.append((goods[i] as GoodDef).display_name.to_lower())
	var debts := CreditSystem.debts_of(world, nation.id)
	lines.append("[b]Рынок:[/b] индекс цен %.2f%s%s" % [nation.inflation, (" · долги %s" % fmt(debts)) if debts > 0.0 else "",
		(" · нехватка: " + ", ".join(short)) if not short.is_empty() else ""])
	for m in world.mercs:
		if m.alive and m.employer == nation.id:
			lines.append("[color=#c8c0a8]Наёмники: %s (%s воинов)[/color]" % [m.name, fmt(m.strength)])


## Дикий мир края (этап 11.C): логово, племя, поветрие — короткими строками.
static func wild_lines(world: World, region: Region) -> Array[String]:
	var res: Array[String] = []
	for l in world.lairs:
		if l.alive and (l.home == region.id or l.region == region.id):
			res.append("%s%s: сила %s" % [l.label(), "" if l.home == region.id else " (бродит здесь)", ArmySystem._num(l.strength)])
	var t := TribeSystem.tribe_in(world, region.id)
	if t != null:
		res.append("%s (%s): %s воинов" % [t.label(), t.race.display_name.to_lower(), ArmySystem._num(t.strength)])
	var d := DiseaseSystem.region_text(world, region.id)
	if not d.is_empty():
		res.append("Болезнь: " + d)
	return res


## Последние записи летописи о государстве.
func _append_history(world: World, nation: Nation, lines: Array[String]) -> void:
	var found: Array[String] = []
	for i in range(world.chronicle.size() - 1, -1, -1):
		var e: Dictionary = world.chronicle[i]
		if (e.nations as PackedInt32Array).has(nation.id):
			found.append("[color=#8a90a0]%d[/color] %s" % [e.year, e.text])
			if found.size() >= 8:
				break
	if found.is_empty():
		return
	lines.append("")
	lines.append("[b]История:[/b]")
	lines.append_array(found)


func _append_diplomacy(world: World, nation: Nation, lines: Array[String]) -> void:
	var d := world.diplomacy
	lines.append("")
	if nation.overlord >= 0:
		lines.append("[color=#c0a0ff]Вассал государства %s[/color]" % world.nations[nation.overlord].name)
	var vassals := d.vassals_of(world, nation.id)
	if not vassals.is_empty():
		lines.append("[b]Вассалы:[/b] " + ", ".join(Array(vassals).map(func(id: int) -> String: return world.nations[id].short_name)))
	var wars := d.wars_of(nation.id)
	if wars.is_empty():
		lines.append("[color=#9be39b]Мир[/color]")
	for war in wars:
		var side := war.side_of(nation.id)
		var enemies := Array(war.members(-side)).map(func(id: int) -> String:
			return "[url=%d]%s[/url]" % [id, world.nations[id].short_name])
		var score := war.score * side
		var color := "#9be39b" if score > 10 else ("#ff7a6a" if score < -10 else "#e0d090")
		lines.append("[color=#ff6b5b]%s[/color] — против %s, %d г., счёт [color=%s]%+d[/color]" % [
			war.name, ", ".join(enemies), world.year - war.start_year, color, roundi(score)])
	if not nation.allies.is_empty():
		lines.append("[b]Союзники:[/b] " + ", ".join(nation.allies.keys().map(func(id: int) -> String: return world.nations[id].short_name)))
	if not nation.trade_partners.is_empty():
		lines.append("[b]Торговля:[/b] " + ", ".join(nation.trade_partners.keys().map(func(id: int) -> String: return world.nations[id].short_name)))
	if not nation.borders.is_empty():
		var parts: Array[String] = []
		for other in nation.borders:
			var op := d.opinion(world, nation.id, other)
			var color := "#7fd18b" if op > 0.15 else ("#e07a6a" if op < -0.15 else "#c9ccd4")
			parts.append("[url=%d][color=%s]%s %+.1f[/color][/url]" % [other, color, world.nations[other].short_name, op])
		lines.append("[b]Соседи (мнение):[/b] " + ", ".join(parts))
	var regions := 0
	var unruly := 0
	for rid in nation.region_counts:
		var region := world.regions[rid]
		if region.controller() == nation.id:
			regions += 1
			if region.unrest >= 0.5:
				unruly += 1
	lines.append("[b]Регионов:[/b] %d%s" % [regions, (" · [color=#ffb04a]неспокойных: %d[/color]" % unruly) if unruly > 0 else ""])
	if nation.state_religion >= 0:
		var faith := world.religions[nation.state_religion]
		lines.append("[b]Вера:[/b] [color=#%s]%s %s[/color]%s — единство %d%%; догматы: %s" % [faith.color.to_html(false), faith.symbol,
			faith.name, " (ересь)" if faith.is_heresy() else "", roundi(nation.faith_unity * 100.0), ", ".join(faith.dogmas).to_lower()])
		var shares := ReligionSystem.nation_shares(world, nation)
		shares.erase(nation.state_religion)
		if not shares.is_empty():
			lines.append("Иноверцы: " + faith_text(world, shares, 4))


## «☀ Церковь Света 70%, ☾ Вечная Ночь 20%» — крупнейшие доли вер.
static func faith_text(world: World, faith: Dictionary, top: int) -> String:
	var ids := faith.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return faith[a] > faith[b])
	var parts: Array[String] = []
	for id in ids.slice(0, top):
		var r := world.religions[id]
		parts.append("[color=#%s]%s %s[/color] %d%%" % [r.color.to_html(false), r.symbol, r.name, roundi(faith[id] * 100.0)])
	return ", ".join(parts)


static func _stability_text(v: float) -> String:
	var color := "#7fd18b" if v >= 0.6 else ("#f0d060" if v >= 0.4 else "#e07a6a")
	return "[color=%s]%d%%[/color]" % [color, roundi(v * 100.0)]


## 1234567 → «1.2 млн», 12345 → «12.3 тыс.».
static func fmt(v: float) -> String:
	var a := absf(v)
	var prefix := "-" if v < 0.0 else ""
	if a >= 1_000_000.0:
		return "%s%.1f млн" % [prefix, a / 1_000_000.0]
	if a >= 10_000.0:
		return "%s%.1f тыс." % [prefix, a / 1000.0]
	return str(roundi(v))
