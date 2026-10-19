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
signal world_generated(map: WorldMap, elapsed_ms: int)

# --- Отображение ---
@warning_ignore("unused_signal")
signal map_mode_changed(mode: int)

# --- Взаимодействие с картой (индекс клетки, -1 = вне карты) ---
@warning_ignore("unused_signal")
signal cell_hovered(cell: int)
@warning_ignore("unused_signal")
signal cell_clicked(cell: int)
