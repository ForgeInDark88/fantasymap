class_name HistoryWindow
extends WindowBase
## Окно «История мира» (этап 11.F): снимки истории (авто — раз в 50 лет и
## по кнопке), ветви и «Вернуться в это время» — мир продолжится оттуда новой
## ветвью; прежние снимки остаются, к ним можно вернуться снова.

var _list: ItemList
var _info: Label


func _init() -> void:
	build("История мира", Vector2(760, 520))
	var snap := Button.new()
	snap.text = "Сделать снимок"
	snap.focus_mode = Control.FOCUS_NONE
	snap.pressed.connect(func() -> void:
		WorldState.take_snapshot()
		_refresh())
	header.add_child(snap)
	var back := Button.new()
	back.text = "Вернуться в это время"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void:
		var sel := _list.get_selected_items()
		if not sel.is_empty() and WorldState.restore_snapshot(int(sel[0])):
			UiAnim.hide(self))
	header.add_child(back)
	add_close()
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 13)
	content.add_child(_info)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(720, 400)
	content.add_child(_list)
	EventBus.history_window_requested.connect(func() -> void:
		visible = true
		_refresh())


func _refresh() -> void:
	var world := WorldState.world
	_list.clear()
	for s in WorldState.snapshots.items:
		_list.add_item("%s — %s" % [s.label, ("%d КБ" % (int(s.size) / 1024)) if int(s.size) > 0 else "сжимается…"])
	if world != null:
		_info.text = "Сейчас: %s, ветвь %d%s. Снимков: %d (до %d)." % [world.date_text(), world.branch,
			(" (от ветви %d, %d г.)" % [int(world.branch_from.branch), int(world.branch_from.year)]) if not world.branch_from.is_empty() else "",
			WorldState.snapshots.items.size(), Snapshots.LIMIT]
