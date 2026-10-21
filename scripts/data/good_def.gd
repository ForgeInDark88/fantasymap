class_name GoodDef
extends Resource
## Товар рынка (data/goods/*.tres, этап 11.D): зерно, рыба, соль, вино, кони,
## меха, шёлк, пряности, оружие, самоцветы, мифрил… Производство — от земель
## государства (биомы, побережье, реки, месторождения) или ремесло (из
## металла); спрос — у сословий и армии; запасы портятся. Цена — на рынке
## каждого государства: дефицит дорожит, избыток дешевит (MarketSystem).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE
## Базовая цена (золото за 1000 единиц).
@export var base_price: float = 1.0
## Доля запаса, что портится за год.
@export var spoil: float = 0.1
## Производство на клетку по биомам (BiomeDef.id → единиц в год).
@export var biomes: Dictionary[StringName, float] = {}
## На клетку приморского края и на клетку с рекой.
@export var coastal: float = 0.0
@export var river: float = 0.0
## Месторождение (DepositDef.id) и выход с его клетки.
@export var deposit: StringName = &""
@export var deposit_amount: float = 0.0
## Ремесло: из Goods (например &"metal") — сколько единиц из единицы сырья.
@export var crafted_from: StringName = &""
@export var craft_ratio: float = 0.0
## Спрос на 1000 жителей сословия: &"nobles", &"burghers", &"peasants", &"slaves"; и на 1000 воинов.
@export var demand: Dictionary[StringName, float] = {}
@export var army_demand: float = 0.0
## Предмет роскоши (знать довольна, когда его вдоволь) или насущный (нехватка — ропот).
@export var luxury: bool = false
@export var staple: bool = false
## Военный товар: его достаток крепит армию (кони, оружие).
@export var military: bool = false
