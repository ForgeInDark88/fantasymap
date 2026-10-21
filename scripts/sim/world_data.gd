class_name WorldData
extends RefCounted
## Поля мира (World): карта, календарь, государства, клетки, сущности всех
## систем. Сюда же — летопись и счётчики, которыми пользуются все части.

const NO_RACE := 255
## Сколько записей летописи хранить.
const CHRONICLE_LIMIT := 4000
## Минимальное расстояние между городами (в клетках, по Чебышёву).
const CITY_SPACING := 6

var map: WorldMap
var settings: MapSettings
var year := 0
## Месяц текущего года: 0..11; день месяца: 0..29.
var month := 0
var day := 0
var rng := RandomNumberGenerator.new()

var nations: Array[Nation] = []
var cities: Array[City] = []
## Регионы (провинции) — постоянная нарезка суши, см. RegionGenerator.
var regions: Array[Region] = []
## Регион каждой клетки (-1 — вода).
var region_of := PackedInt32Array()
## Регион клетки для шейдера (RGBA8: R,G — id + 1), неизменен после создания мира.
var region_texels := PackedByteArray()

## id государства-владельца для каждой клетки (-1 — ничья).
var owner := PackedInt32Array()
## То же в виде RGBA8 для шейдера: R,G — (id + 1) в 16 битах, B — суша (255) / вода (0).
var owner_texels := PackedByteArray()
## Позиция клетки в Nation.cells владельца (для удаления за O(1)).
var cell_slot := PackedInt32Array()
## Какой народ живёт в клетке (RaceDef.index; NO_RACE — никто).
## Народ остаётся на месте при смене владельца — так появляются многорасовые государства.
var cell_race := PackedByteArray()
## Месторождение в клетке: индекс в EconomyDB.deposits() + 1 (0 — нет).
var deposit := PackedByteArray()
## Добыча клетки в год: cell * Goods.COUNT + goods.
var cell_yield := PackedFloat32Array()
## Ёмкость клетки для её народа (кэш для карты населения; 0 — не заселена).
var cell_cap := PackedFloat32Array()
## id города в клетке (-1 — нет).
var city_cell := PackedInt32Array()
## Сколько городов ближе CITY_SPACING к клетке (0 — здесь можно основать город).
## Счётчик, а не флаг, чтобы при разрушении города (этап 4) просто вычесть.
var city_block := PackedByteArray()
## Растёт при каждом изменении границ — рендер по нему понимает, что пора обновиться.
var ownership_version := 0
## Растёт при постройке и гибели дорог (кэши дорог в системах; не сохраняется).
var road_version := 0
## Метки для обходов карты без выделения памяти: клетка посещена, если mark[c] == stamp.
var mark := PackedInt32Array()
var _stamp := 0
## Какое-то государство потеряло последнюю клетку — cleanup_dead есть что делать.
var _maybe_dead := false
## Растёт при изменении рельефа (панель Бога) — рендер перерисовывает карту и регионы.
var terrain_version := 0

var diplomacy := Diplomacy.new()
var heroes: Array[Hero] = []
## Счётчики событий мира (ассимиляции, ереси, извержения…) — для тестов,
## статистики и достижений; см. count().
var counters: Dictionary[StringName, int] = {}

# --- Климат (ClimateSystem) ---
## Вулканы (клетки гор), следы бедствий на карте {cell, radius, kind, until},
## медленные сдвиги климата (температура и влажность) и урожайность поясов
## (север, умеренный, юг) в текущем году.
var volcanoes := PackedInt32Array()
var scars: Array[Dictionary] = []
var temp_shift := 0.0
var moist_shift := 0.0
var zone_harvest := PackedFloat32Array([1.0, 1.0, 1.0])
## Климатические беды поясов: пояс → {kind, until}; пепельная зима — до года ash_until.
var zone_events: Dictionary[int, Dictionary] = {}
var ash_until := -1
## Мировой кризис (CrisisSystem): пусто — нет; иначе {id, stage, stage_start, start,
## invader, titan_cell, titan_power, titan_name}. История кризисов и эпох.
var crisis: Dictionary = {}
var crisis_history: Array[Dictionary] = []
var last_crisis_end := -1000
var crisis_harvest := 1.0
var crisis_events: Dictionary = {}
var eras: Array[Dictionary] = []
## Артефакты-предметы (ArtifactSystem), роды героев, ордена и гильдии (этап 10.1).
var artifacts: Array[Artifact] = []
## Роды героев: {name, founder, year}.
var lineages: Array[Dictionary] = []
## Ещё не выросшие дети героев: {parents, name, race, class, karma, intellect, adult, cell, lineage}.
var hero_births: Array[Dictionary] = []
var orders: Array[HeroOrder] = []
## Игра за героя (PlayerSystem, этап 10.2): id героя игрока (-1 — режим наблюдателя),
## текущая команда, выбор, ждущий решения, журнал приключений, репутация
## ("n<id>" — у державы, "r<id>" — у веры, "o<id>" — у ордена), месяцы без команд.
## Растянутые удары бедствий (StageSystem): {nation, months, step, pop, army, stab, gold, food, id}.
var staged_effects: Array[Dictionary] = []
## Армии, флоты и пираты (ArmySystem), полководцы {id, name, nation, skill, born,
## alive, captured_by, hero, army, parent, wins}, последние битвы {region, year, month, day, war, winner, fallen}.
var armies: Array[Army] = []
var generals: Array[Dictionary] = []
var recent_battles: Array[Dictionary] = []
## Дикий мир (этап 11.C): племена и орды, логова чудовищ, поветрия, языки и наречия.
var tribes: Array[Tribe] = []
var lairs: Array[Lair] = []
var outbreaks: Array[Outbreak] = []
var languages: Array[Language] = []
## Рынок и общество (этап 11.D): караваны в пути, вольные отряды наёмников,
## займы {id, lender, debtor, amount, left, rate, year, missed}, год последнего
## дефолта государства ("id" → год), итоги рынка за всю историю (made, used,
## lost, robbed, delivered — для проверки учёта).
var caravans: Array[Caravan] = []
var mercs: Array[MercCompany] = []
var loans: Array[Dictionary] = []
var loan_serial := 0
var defaults: Dictionary = {}
var market_totals: Dictionary = {}
## Дипломатия и ИИ (этап 11.E): журнал предложений {year, month, kind, a, b, ok,
## text} и слухи {id, year, kind, about, target, source, truth, cred, until, text}.
var diplo_journal: Array[Dictionary] = []
var rumors: Array[Dictionary] = []
var rumor_serial := 0
## Удобство (этап 11.F): ветвь истории (Snapshots) и откуда она пошла
## {branch, year}; за кем следит игрок (уведомления): державы и герои.
var branch := 0
var branch_from: Dictionary = {}
var watch_nations := PackedInt32Array()
var watch_heroes := PackedInt32Array()
## Товары краёв (MarketSystem.region_goods; производное от карты, не сохраняется).
var region_goods: Array = []
## Края, чьи товары надо пересчитать (смена биома, рельеф).
var goods_dirty: Dictionary = {}
var player := -1
## Наблюдатель за событиями мира (не сохраняется): интерфейс передаёт через него
## записи летописи и счётчики в EventBus — логика мира об EventBus не знает.
var observer: Callable
## Закладки на события летописи (панель «Хроники»): {year, month, day, kind, text}.
var bookmarks: Array[Dictionary] = []
var player_cmd: Dictionary = {}
var player_choice: Dictionary = {}
var player_journal: Array[Dictionary] = []
var player_rep: Dictionary = {}
var player_idle := 0
## Задания героя игрока (PlayerQuests) и предложения доски заданий, ждущие выбора.
var player_quests: Array[Dictionary] = []
var player_offers: Array[Dictionary] = []
## Служба героя игрока в войске {war, nation, role: "general"/"officer", since}
## и отложенные события цепочек {event, at: год·12 + месяц}.
var player_army: Dictionary = {}
var player_chain: Array[Dictionary] = []
## Руины (RuinSystem).
var ruins: Array[Ruin] = []
## Подземный мир: граф пещер (UndergroundSystem).
var caves: Array[Cave] = []
## Дороги и морские пути (граф между городами) и дороги каждого города.
var roads: Array[Road] = []
var city_roads: Dictionary[int, PackedInt32Array] = {}
## Тайные общества и культы, международные организации, наследия империй (этап 8).
var societies: Array[Society] = []
var orgs: Array[Organization] = []
var legacies: Array[Legacy] = []
## Культуры народов (CultureSystem).
var cultures: Array[Culture] = []
## Веры мира: стартовые (по data/religions) и рождённые в истории (ереси, новые веры).
var religions: Array[Religion] = []
## Странствующие (живые и не на троне) герои — чтобы не перебирать ежедневно всех павших.
var _wandering: Array[Hero] = []
## Те же герои, разложенные по «своему» дню месяца (id % 30); пересобирается при изменениях.
var _by_day: Array = []
var _by_day_dirty := true
## Источники силы, порталы, пустые троны, чудеса света.
var landmarks: Array[Landmark] = []
## Павшие герои, ждущие суда Судьбы (id героев).
var fate_queue := PackedInt32Array()
## Отложенные события (эпидемии, пришедшие от соседей): [nation_id, event_id].
var pending_events: Array = []
## Снимки статистики раз в HISTORY_STEP лет: {year, races: PackedFloat32Array, nations: {id: [население, клетки]}}.
var history: Array[Dictionary] = []
const HISTORY_STEP := 5

## Летопись: {year, kind, text, nations: PackedInt32Array}.
var chronicle: Array[Dictionary] = []
## Общее число записей за всю историю (не уменьшается при обрезке старых).
var chronicle_total := 0

## Уже выданные имена (города, государства, правители) — чтобы не повторялись.
var used_names: Dictionary = {}


func count(key: StringName, amount: int = 1) -> void:
	counters[key] = counters.get(key, 0) + amount
	if observer.is_valid():
		observer.call(&"count", {"key": key, "value": counters[key]})


func log_event(kind: StringName, text: String, nation_ids: PackedInt32Array = PackedInt32Array()) -> void:
	chronicle.append({"year": year, "month": month, "day": day, "kind": kind, "text": text, "nations": nation_ids})
	chronicle_total += 1
	if observer.is_valid():
		observer.call(&"log", {"kind": kind, "text": text, "nations": nation_ids})
	if chronicle.size() > CHRONICLE_LIMIT:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_LIMIT)
