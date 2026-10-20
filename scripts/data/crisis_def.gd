class_name CrisisDef
extends Resource
## Мировой кризис (data/crises/*.tres): длится десятилетиями, идёт стадиями,
## меняет правила для всего мира (эффекты государств, урожай, гибель людей,
## шансы событий) и даёт повод объединиться (Великий союз). Особое поведение
## задаётся полем special и реализовано в CrisisSystem.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Как назовут эпоху, пока кризис длится.
@export var era_name: String = "Эпоха Бедствий"
## Относительная частота и самый ранний год.
@export var weight: float = 1.0
@export var min_year: int = 100

@export_group("Стадии")
@export var stage_names: PackedStringArray = []
## Длительность стадий в годах.
@export var stage_years: PackedInt32Array = []
## Эффекты для всех государств на стадии (ключи Nation.effects).
@export var stage_effects: Array[Dictionary] = []
## Урожайность во всём мире (множитель) и ежегодная гибель населения (доля).
@export var stage_harvest: PackedFloat32Array = []
@export var stage_pop_loss: PackedFloat32Array = []
## Множители шансов событий data/events на стадии: id события → множитель.
@export var stage_events: Array[Dictionary] = []

@export_group("Особое")
## plague, ice, invasion, titan, drought, star_fall, gods_war.
@export var special: StringName = &""
## Для нашествия — раса пришельцев.
@export var invader_race: StringName = &"orcs"
## Собрать Великий союз против кризиса.
@export var unite: bool = true
## Расы с этими особенностями кризис не трогает (нежить не болеет).
@export var immune_traits: Array[StringName] = []
@export_multiline var start_text: String = ""
@export_multiline var end_text: String = ""
