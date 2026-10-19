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


func _ready() -> void:
	%CloseButton.pressed.connect(close_requested.emit)


func show_nation(world: World, nation: Nation) -> void:
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
	_sub.text = "%s · основано в %d г. · %d лет" % [race.display_name, nation.founded_year, world.year - nation.founded_year]
	_color_bar.color = nation.color

	var capital := world.cities[nation.capital_city] if nation.capital_city >= 0 else null
	var lines: Array[String] = [
		"[b]Правитель:[/b] %s (%d лет)" % [nation.ruler_display(), nation.ruler_age],
		"[b]Столица:[/b] %s (%s жит.)" % [capital.name, fmt(capital.population)] if capital != null else "[b]Столица:[/b] —",
		"[b]Территория:[/b] %d клеток · [b]городов:[/b] %d" % [nation.cell_count, nation.city_ids.size()],
		"[b]Население:[/b] %s из %s возможных" % [fmt(nation.population), fmt(nation.total_capacity())],
		"[b]Армия:[/b] %s · [b]наука:[/b] %.1f" % [fmt(nation.army), nation.tech],
		"[b]Стабильность:[/b] %s" % _stability_text(nation.stability),
	]
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
	# Карточка подстраивается под содержимое и сжимается, когда строк становится меньше.
	set_deferred("size", Vector2(size.x, 0.0))


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
