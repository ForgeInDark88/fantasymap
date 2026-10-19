class_name TraitDef
extends Resource
## Уникальная особенность расы (data/traits/*.tres).
## Описание — для интерфейса; эффект реализуется в коде симуляции
## проверкой RaceDef.has_trait(id).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
