class_name EventDef
extends Resource
## Случайное событие (data/events/*.tres). Происходит с государством в одном
## из его регионов; эффекты складываются из полей ниже, поэтому новое событие
## можно собрать из готовых «кубиков» без кода.

@export var id: StringName
@export var display_name: String = ""
## Вид записи в летописи (plague, disaster, hero, monsters…).
@export var chronicle_kind: StringName = &"disaster"
## Шанс в год для одного государства.
@export_range(0.0, 0.2, 0.0001) var chance: float = 0.002
@export var min_population: float = 0.0
## Расы с этими особенностями не подвержены событию (нежить не болеет и не голодает).
@export var immune_traits: Array[StringName] = []
## Событие возможно только в регионе с одним из этих биомов в центре (пусто — везде).
@export var requires_biomes: Array[StringName] = []
## Нужна река в регионе.
@export var requires_river: bool = false

@export_group("Мгновенные эффекты")
## Доля населения, которая гибнет.
@export_range(0.0, 1.0) var population_loss: float = 0.0
@export_range(0.0, 1.0) var army_loss: float = 0.0
@export_range(-1.0, 1.0) var stability_change: float = 0.0
## Доли запасов золота и еды, которые пропадают.
@export_range(0.0, 1.0) var gold_loss: float = 0.0
@export_range(0.0, 1.0) var food_loss: float = 0.0
## Начинается голод (как после неурожая).
@export var causes_famine: bool = false
## Шанс разрушить город региона (не столицу).
@export_range(0.0, 1.0) var destroys_city_chance: float = 0.0
## Сколько построек может разрушить в городе региона.
@export var destroys_buildings: int = 0
## Сколько пограничных клеток региона опустошается (становятся ничьими).
@export var lost_cells: int = 0
## В регионе появляется герой (раса — по народу региона, класс — по расе).
@export var spawns_hero: bool = false

@export_group("Длительные эффекты")
## Сколько лет действуют множители ниже (0 — нет длительного эффекта).
@export var duration: int = 0
@export var army_mult: float = 1.0
@export var growth_mult: float = 1.0
@export var science_mult: float = 1.0
## Шанс перекинуться на каждого соседа (эпидемии).
@export_range(0.0, 1.0) var spread_chance: float = 0.0

@export_group("Текст")
## Шаблон для летописи: {nation}, {region}, {city}, {hero}, {ruler}.
@export_multiline var text: String = "{nation}: {name}."
