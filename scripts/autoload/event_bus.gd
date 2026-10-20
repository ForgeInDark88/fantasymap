extends Node
## Глобальная шина событий (autoload «EventBus»).
##
## Системы не знают друг о друге напрямую: генератор, рендер, UI и (позже)
## симуляция общаются только через эти сигналы. Сигналы объявлены здесь,
## а испускаются из других скриптов, поэтому предупреждение unused_signal подавлено.

# --- Генерация мира ---
@warning_ignore("unused_signal")
signal generate_requested(settings: MapSettings)
@warning_ignore("unused_signal")
signal generation_started
@warning_ignore("unused_signal")
signal world_generated(world: World, elapsed_ms: int)

# --- Симуляция ---
## Прошёл один или несколько лет (испускается не чаще раза за кадр).
@warning_ignore("unused_signal")
signal year_passed(year: int)
## Индекс скорости в WorldState.SPEEDS (0 — пауза).
@warning_ignore("unused_signal")
signal speed_changed(speed_index: int)

# --- Отображение ---
@warning_ignore("unused_signal")
signal map_mode_changed(mode: int)

# --- Взаимодействие с картой (индекс клетки, -1 = вне карты) ---
@warning_ignore("unused_signal")
signal cell_hovered(cell: int)
@warning_ignore("unused_signal")
signal cell_clicked(cell: int)

## Камера должна показать клетку (клик в летописи, списке героев…).
@warning_ignore("unused_signal")
signal focus_cell(cell: int)
## Инструмент панели Бога: id (&"" — нет инструмента) и параметры.
@warning_ignore("unused_signal")
signal god_tool_changed(tool: StringName, params: Dictionary)
## Рельеф изменился — перерисовать карту.
@warning_ignore("unused_signal")
signal terrain_changed

# --- Выбор объектов (-1 = снять выбор) ---
@warning_ignore("unused_signal")
signal nation_selected(nation_id: int)
@warning_ignore("unused_signal")
signal hero_selected(hero_id: int)
## Открыть окно героя с подробностями.
@warning_ignore("unused_signal")
signal hero_window_requested(hero_id: int)
## Открыть окно технологий государства.
@warning_ignore("unused_signal")
signal tech_window_requested(nation_id: int)
## Открыть окно подземного мира.
@warning_ignore("unused_signal")
signal underworld_window_requested

## Режим «Сыграй за героя»: открыть панель «Мой герой» (true) или «Герои» (false — выбрать героя).
signal my_hero_requested(open_my_hero: bool)

## Открыть окно «Хроники» (связные истории летописца).
signal chronicles_window_requested
