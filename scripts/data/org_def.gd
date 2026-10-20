class_name OrgDef
extends Resource
## Международная организация (data/orgs/*.tres). Условия вступления заданы
## полями; OrgSystem проверяет их раз в год, собирает организацию, принимает
## и исключает членов. Правила (запрет войн между членами, общая оборона) и
## бонусы членства — тоже здесь.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Шаблон названия: {name} — основатель (короткое имя), {faith} — вера.
@export var name_template: String = "Союз {name}"
@export var color: Color = Color.WHITE

@export_group("Кто вступает")
## trade — торговые связи; tech — нужна технология; faith — общая вера;
## hegemon — страх перед гегемоном; abyss — пока в мире есть демоны.
@export_enum("trade", "tech", "faith", "hegemon", "abyss", "crisis") var basis: String = "trade"
@export var requires_tech: StringName = &""
## Минимум торговых договоров (для basis = trade).
@export var min_trade_partners: int = 2
## Минимум членов, чтобы организация возникла (и не распалась).
@export var min_members: int = 3
## Сколько организаций этого вида может быть в мире одновременно.
@export var max_count: int = 1
## Расы с этими особенностями не вступают (демоны в совет против бездны).
@export var excluded_traits: Array[StringName] = []

@export_group("Правила")
## Члены не воюют друг с другом.
@export var no_war: bool = true
## На члена напали — остальные вступают в войну.
@export var mutual_defense: bool = false
## Взнос: доля положительного дохода золотом в год.
@export_range(0.0, 0.3) var dues: float = 0.03
## Эффекты членства (ключи Nation.effects).
@export var effects: Dictionary[StringName, float] = {}
## Отношения членов друг к другу.
@export var opinion_bonus: float = 0.1
