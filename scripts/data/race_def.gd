class_name RaceDef
extends Resource
## Описание расы (data/races/*.tres). Чтобы добавить расу, достаточно
## создать новый .tres с этим скриптом — код менять не нужно.

@export var id: StringName
## Название во множественном числе («Эльфы»).
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE
@export var icon: Texture2D
## Появляется ли раса в начале мира (наги и демоны приходят только через великие деяния и порталы).
@export var spawn_at_start: bool = true
## Как назовут эпоху господства этой расы («Железных королей» → «Эпоха Железных королей»).
@export var era_title: String = ""

@export_group("Биомы")
## Сродство с биомами: id биома → 0..1 (1 — родной, 0 — враждебный).
@export var biome_affinity: Dictionary[StringName, float] = {}
## Сродство для биомов, которых нет в списке.
@export_range(0.0, 1.0) var default_affinity: float = 0.3
## Во сколько раз дороже экспансия в биом с нулевым сродством.
@export_range(1.0, 10.0) var foreign_biome_penalty: float = 2.5
## Тяга к побережью при выборе мест для поселений (0..1).
@export_range(0.0, 1.0) var coast_affinity: float = 0.3

@export_group("Модификаторы")
@export_range(0.1, 3.0) var growth: float = 1.0
@export_range(0.1, 3.0) var military: float = 1.0
@export_range(0.1, 3.0) var trade: float = 1.0
@export_range(0.1, 3.0) var science: float = 1.0
@export_range(0.1, 3.0) var expansion: float = 1.0
## Средняя продолжительность жизни в годах; 0 — бессмертны.
@export_range(0, 2000) var lifespan: int = 70
## Потребность в еде (0 — не нуждаются).
@export_range(0.0, 2.0) var food_need: float = 1.0
## Сколько клеток территории приходится на один город (чем меньше, тем гуще города).
@export_range(10, 400) var cells_per_city: int = 70
## Доля населения, живущая в городах.
@export_range(0.0, 0.6) var urban_share: float = 0.15

@export_group("Дипломатия")
## Отношение к другим расам: id расы → -1 (вражда) .. +1 (дружба). Нет в списке — нейтралитет.
@export var relations: Dictionary[StringName, float] = {}
## Отношение к другим государствам своей расы.
@export_range(-1.0, 1.0) var same_race_relation: float = 0.3
## Склонность начинать войны (множитель).
@export_range(0.0, 3.0) var aggression: float = 1.0

@export_group("Особенности")
## id особенностей из data/traits/.
@export var traits: Array[StringName] = []

@export_group("Язык")
## Первые слоги имён (с заглавной буквы).
@export var name_prefixes: PackedStringArray = []
## Необязательные средние слоги.
@export var name_middles: PackedStringArray = []
## Окончания названий мест (города, государства).
@export var place_suffixes: PackedStringArray = []
## Окончания личных имён.
@export var person_suffixes: PackedStringArray = []
## Формы правления: «Шаблон|Титул», где {name} — название. Пример: «Королевство {name}|Король».
@export var state_forms: PackedStringArray = []
## Гласные-связки между слогами, когда стыкуются согласные.
@export var connector_vowels: String = "аоу"
@export_range(0.0, 1.0) var middle_chance: float = 0.4

## Порядковый номер расы (назначает RaceDB); хранится в World.cell_race.
var index := -1
## Сродство по индексу биома (кэш, строится RaceDB при загрузке).
var affinity_by_biome := PackedFloat32Array()


func build_cache() -> void:
	affinity_by_biome.resize(Biome.COUNT)
	for i in Biome.COUNT:
		var def := BiomeDB.get_def(i)
		affinity_by_biome[i] = 0.0 if def.is_water else biome_affinity.get(def.id, default_affinity)


func has_trait(trait_id: StringName) -> bool:
	return traits.has(trait_id)


func relation_to(other: RaceDef) -> float:
	if other == self:
		return same_race_relation
	return relations.get(other.id, 0.0)


## Стоимость экспансии в клетку с биомом biome_index (1 ≈ своя равнина).
func expansion_cost(biome_index: int) -> float:
	var aff := affinity_by_biome[biome_index]
	var terrain := 1.0 + (BiomeDB.get_def(biome_index).move_cost - 1.0) * (1.0 - aff * 0.7)
	return lerpf(foreign_biome_penalty, 0.6, aff) * terrain / expansion
