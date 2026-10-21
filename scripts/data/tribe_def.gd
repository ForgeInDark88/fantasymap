class_name TribeDef
extends Resource
## Вид племени (data/tribes/*.tres): народ без государства в ничейных землях.
## Оседлые племена растут на месте и сопротивляются экспансии; кочевники
## бродят по ничейным краям, набегают на соседей и, окрепнув, собираются в
## орду — а орда, найдя свободную землю, основывает государство (TribeSystem).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Народ (RaceDef.id).
@export var race: StringName
## Кочевники ходят по краям и собираются в орды; оседлые — сидят на месте.
@export var nomad: bool = false
## Любимые биомы (BiomeDef.id): здесь племена рождаются и сюда кочуют.
@export var biomes: Array[StringName] = []
@export var weight: float = 1.0
## Сила при рождении (воины) и рост силы в год (доля).
@export var strength: Vector2 = Vector2(800.0, 2500.0)
@export var growth: float = 0.04
## Шанс набега на соседнее государство в месяц.
@export var raid_chance: float = 0.05
## Сила, при которой кочевники собираются в орду, и сила, с которой орда основывает государство.
@export var horde_strength: float = 6000.0
@export var found_strength: float = 9000.0
## Как зовут племя и орду: {name} — имя на языке народа.
@export var tribe_name: String = "Племя {name}"
@export var horde_name: String = "Орда {name}"
