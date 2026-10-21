class_name QuestDef
extends Resource
## Вид задания героя игрока (data/quests/*.tres, этап 11.H). Что и как
## проверяется — по полю handler в PlayerQuests; здесь — название, частота,
## награда и срок. Подстановки в title: {region}, {target}, {nation}, {good},
## {amount}.

@export var id: StringName
@export var display_name: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
## Обработчик: hunt, ruins, deliver, bandits, artifact, lair, raid, caravan,
## trade, intel, epidemic, embassy, treasure.
@export var handler: StringName
@export var weight: float = 1.0
## Награда: золото и опыт — база и за каждый шаг пути; множитель опасности.
@export var gold_base: float = 20.0
@export var gold_per_step: float = 15.0
@export var xp_base: float = 1.5
@export var xp_per_step: float = 0.6
@export var danger: float = 1.0
## Срок: лет сверх половины шагов пути.
@export var years: int = 2
## Только на доске (false) — или и из событий пути.
@export var board: bool = true
