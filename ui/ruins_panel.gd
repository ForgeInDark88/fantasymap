class_name RuinsPanel
extends PanelContainer
## Руины мира: список (богатые и неисследованные — сверху), вид, происхождение,
## опасность и проклятия. Клик — показать на карте.

var _list: RichTextLabel
var _show_all: CheckBox
var _last_refresh_ms := 0


func _init() -> void:
	custom_minimum_size = Vector2(480, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Руины и древности"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	_show_all = CheckBox.new()
	_show_all.text = "Показывать исчерпанные и возрождённые"
	_show_all.toggled.connect(func(_on: bool) -> void: _refresh())
	box.add_child(_show_all)
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.custom_minimum_size = Vector2(460, 520)
	_list.add_theme_font_size_override("normal_font_size", 12)
	_list.meta_clicked.connect(func(meta: Variant) -> void:
		var cell := int(str(meta))
		if cell >= 0:
			EventBus.focus_cell.emit(cell))
	box.add_child(_list)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_refresh_ms > 2000:
		_refresh()


func _refresh() -> void:
	_last_refresh_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null:
		return
	var ruins: Array[Ruin] = []
	for r in world.ruins:
		if r.cell >= 0 and (_show_all.button_pressed or (not r.depleted() and not r.revived)):
			ruins.append(r)
	ruins.sort_custom(func(a: Ruin, b: Ruin) -> bool: return a.wealth > b.wealth)
	var lines: Array[String] = ["Всего руин: %d · в списке: %d" % [world.ruins.filter(func(r: Ruin) -> bool: return r.cell >= 0).size(), ruins.size()], ""]
	for r in ruins:
		var state := "возрождены" if r.revived else ("исчерпаны" if r.depleted() else "богатство ~%d" % roundi(r.wealth))
		var owner := world.owner[r.cell]
		lines.append("[url=%d][b]%s[/b][/url] — %s · %s%s" % [r.cell, r.name, r.kind_name(), state,
			" · [color=#c8a0e0]проклятие[/color]" if r.cursed else ""])
		lines.append("   [color=#9aa0b0]%s; стражи %s; %s[/color]" % [r.origin, NationPanel.fmt(r.danger),
			("земли %s" % world.nations[owner].short_name) if owner >= 0 else "дикие земли"])
	_list.text = "\n".join(lines)
