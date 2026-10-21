class_name PersonalityDef
extends Resource
## Характер государства (data/personalities/*.tres, этап 11.E): как правители
## держатся в дипломатии — воинственность, торговля, союзы, сделки, память об
## обидах, слухи, перенос столицы. Даётся при основании (по народу и форме
## правления), может смениться с новым правителем.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var weight: float = 1.0
## Кому свойственен: народы (RaceDef.id → множитель веса) и формы правления.
@export var races: Dictionary[StringName, float] = {}
@export var governments: Dictionary[StringName, float] = {}
## Множитель воинственности (эффект &"aggression_mult").
@export var aggression: float = 1.0
## Как часто ищет сделки (множитель шанса) и какие любит: &"region", &"goods",
## &"tech", &"peace", &"pact", &"subsidy" → множитель.
@export var deal_rate: float = 1.0
@export var deal_taste: Dictionary[StringName, float] = {}
## Насколько щедр (наценка, которую готов дать/взять: 0 — скуп, 1 — щедр).
@export var generosity: float = 0.5
## Память об обидах (множитель роста обид при отказах и дефолтах).
@export var grudge: float = 1.0
## Склонность распускать ложные слухи (шанс в год).
@export var rumor: float = 0.05
## Охота переносить столицу к сердцу земель.
@export var relocation: float = 1.0
