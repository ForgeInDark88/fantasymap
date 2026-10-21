class_name DiseaseDef
extends Resource
## Болезнь (data/diseases/*.tres): поветрие идёт по краям вдоль дорог и
## морских путей (и слабее — к соседям), в каждом крае держится months
## месяцев, губит долю жителей и оставляет иммунитет. Чума (plague = true) —
## частный случай: самая смертоносная, ставит государствам модификатор чумы
## (DiseaseSystem).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var weight: float = 1.0
@export var min_year: int = 0
## Доля жителей края, гибнущая за всё время болезни в нём.
@export var lethality: float = 0.04
## Шанс в месяц перейти по дороге / к соседнему краю без дороги / по морю.
@export var road_spread: float = 0.25
@export var land_spread: float = 0.05
@export var sea_spread: float = 0.12
## Сколько месяцев болезнь держится в крае и сколько лет край помнит её (иммунитет).
@export var months: int = 6
@export var immunity_years: int = 30
## Кого не берёт: расы (RaceDef.id) и особенности рас (например &"undying").
@export var immune_races: Array[StringName] = []
@export var immune_traits: Array[StringName] = []
## Чума: модификатор &"plague" государствам заражённых краёв.
@export var plague: bool = false
@export var color: Color = Color(0.5, 0.8, 0.3)
