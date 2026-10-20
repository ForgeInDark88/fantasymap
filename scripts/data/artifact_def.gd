class_name ArtifactDef
extends Resource
## Вид артефакта (data/artifacts/*.tres): кольца, короны, книги, оружие,
## реликвии. Конкретный предмет (Artifact) получает имя по шаблону и
## переходит из рук в руки — даром, трофеем, кражей, наследством.

@export var id: StringName
@export var display_name: String = ""
@export_enum("weapon", "ring", "crown", "book", "relic", "amulet") var kind: String = "weapon"
## Шаблоны имён: {weapon} — оружие класса героя, {name} — имя (в родительном),
## {place} — название на языке расы.
@export var name_patterns: PackedStringArray = []
## Сила героя-владельца (множитель), сдвиг кармы в год, прибавка к уму.
@export var power_mult: float = 1.2
@export var karma_drift: float = 0.0
@export var wits_bonus: float = 0.0
## Эффекты для государства, в чьей сокровищнице лежит предмет (ключи Nation.effects).
@export var nation_effects: Dictionary[StringName, float] = {}
## Проклятый (тянет карму вниз, за ним охотятся злодеи).
@export var cursed: bool = false
## Относительная частота при находке.
@export var weight: float = 1.0
## Слава предмета: такие реликвии становятся целью войн и походов.
@export var famous: bool = false
