class_name NationPanel
extends PanelContainer
## Краткая карточка государства (полная панель с отношениями и историей — этап 5).

signal close_requested

@onready var _icon: TextureRect = %Icon
@onready var _name: Label = %NameLabel
@onready var _sub: Label = %SubLabel
@onready var _color_bar: ColorRect = %ColorBar
@onready var _body: RichTextLabel = %Body


func _ready() -> void:
	%CloseButton.pressed.connect(close_requested.emit)


func show_nation(world: World, nation: Nation) -> void:
	var race := nation.race
	_icon.texture = race.icon
	_name.text = nation.name
	_sub.text = "%s · основано в %d г." % [race.display_name, nation.founded_year]
	_color_bar.color = nation.color

	var capital := world.cities[nation.capital_city] if nation.capital_city >= 0 else null
	var city_names: Array[String] = []
	for id in nation.city_ids:
		city_names.append(world.cities[id].name)
	var lines: Array[String] = [
		"[b]Правитель:[/b] %s" % nation.ruler_display(),
		"[b]Столица:[/b] %s" % (capital.name if capital != null else "—"),
		"[b]Города (%d):[/b] %s" % [city_names.size(), ", ".join(city_names)],
		"[b]Территория:[/b] %d клеток" % nation.cell_count,
		"[b]Население:[/b] %s" % _fmt(nation.population),
		"[b]Армия:[/b] %s" % _fmt(nation.army),
		"[b]Казна:[/b] %s золота" % _fmt(nation.wealth),
		"[b]Стабильность:[/b] %d%%" % roundi(nation.stability * 100.0),
	]
	lines.append("")
	lines.append("[b]Особенности расы:[/b]")
	for t in race.traits:
		var def := RaceDB.get_trait(t)
		if def != null:
			lines.append("• [color=#e8d9a0]%s[/color] — %s" % [def.display_name, def.description])
	lines.append("")
	lines.append("[b]Отношение к расам:[/b]")
	var rel_parts: Array[String] = []
	for other in RaceDB.all():
		var v := race.relation_to(other)
		var color := "#7fd18b" if v > 0.15 else ("#e07a6a" if v < -0.15 else "#c9ccd4")
		rel_parts.append("[color=%s]%s %+.1f[/color]" % [color, other.display_name, v])
	lines.append(", ".join(rel_parts))
	_body.text = "\n".join(lines)
	show()


## 1234567 → «1.2 млн», 12345 → «12.3 тыс.».
static func _fmt(v: float) -> String:
	if v >= 1_000_000.0:
		return "%.1f млн" % (v / 1_000_000.0)
	if v >= 10_000.0:
		return "%.1f тыс." % (v / 1000.0)
	return str(roundi(v))
