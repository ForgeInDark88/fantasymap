class_name Tutorial
extends PanelContainer
## Обучение (этап 11.F): тур по интерфейсу при первом запуске (шаги с
## подсветкой нужной кнопки; «Далее», «Назад», «Пропустить»), повтор — меню
## «☰ → Обучение». Пройден — флаг [ui] tutorial_done в user://settings.cfg.
## TIPS — советы: после создания мира всплывает случайный.

const SETTINGS := "user://settings.cfg"
## Шаг: [заголовок, текст, надпись кнопки для подсветки ("" — без)].
const STEPS := [
	["Добро пожаловать!", "Перед вами живой мир: государства растут, воюют, торгуют и распадаются сами. Вы — наблюдатель, а если захотите — бог или герой.", ""],
	["Карта", "Колесо мыши или Q/E — зум к курсору, перетаскивание — перемещение, F — вся карта. Миникарта в углу — клик переносит камеру.", ""],
	["Время", "Пауза — пробел. Скорости x1…x50, шаги «+день», «+мес.», «+год».", "Пауза"],
	["Режимы карты", "Политика, расы, религии, торговля, опасности, языки, товары… Клавиши 1–9, 0, −, =, [, ], \\.", "Политика"],
	["Государства", "Клик по земле — карточка государства: правитель, армия, рынок, нрав, слухи. 🔔 — следить за ним.", ""],
	["Летопись и хроники", "Лента внизу слева, «Летопись» с фильтрами, «Хроники» — связные истории мира.", "Хроники"],
	["Бог", "Панель Бога: создавайте государства, бедствия, героев, караваны, слухи… Выберите инструмент и кликните по карте.", "Бог"],
	["Сыграй за героя", "«Герои» → «Играть за героя»: задания, торговля, служба в войске, плен и слава.", "Герои"],
	["Меню ☰", "Справочник по всему миру, история и ветви (вернуться в прошлое), экспорт карты, уведомления, язык интерфейса.", "☰"],
]
const TIPS := [
	"Совет: окно «Рынок» показывает, где товар дешевле — караваны везут его туда, где дороже.",
	"Совет: в «Истории мира» (меню ☰) можно вернуться в прошлое и прожить другую ветвь.",
	"Совет: 🔔 в карточке государства — уведомления о его войнах и бедах.",
	"Совет: режим «Опасности» ([) показывает логова чудовищ, орды и поветрия.",
	"Совет: в «Дипломатии» флажок «Показать правду» раскрывает, какие слухи — вымысел.",
	"Совет: «☰ → Экспорт карты» сохраняет карту в PNG (и в стиле пергамента) и SVG-легенду.",
	"Совет: «Справочник» в меню ☰ собран прямо из данных игры — по нему удобно искать.",
]

var _title: Label
var _text: Label
var _step := 0
var _highlight: Control
var _hud: Node


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(520, 0)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -260.0
	offset_right = 260.0
	offset_top = -260.0
	offset_bottom = -110.0
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(500, 60)
	box.add_child(_text)
	var row := HBoxContainer.new()
	for b in [["Назад", -1], ["Далее", 1], ["Пропустить", 0]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		var d: int = b[1]
		btn.pressed.connect(func() -> void:
			if d == 0:
				finish()
			else:
				show_step(_step + d))
		row.add_child(btn)
	box.add_child(row)
	UiAnim.attach(self, Vector2(0, 12))
	EventBus.tutorial_requested.connect(func() -> void: start())


func setup(hud: Node) -> void:
	_hud = hud
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK or not bool(cfg.get_value("ui", "tutorial_done", false)):
		start.call_deferred()


func start() -> void:
	visible = true
	show_step(0)


func show_step(i: int) -> void:
	if i >= STEPS.size():
		finish()
		return
	_step = clampi(i, 0, STEPS.size() - 1)
	var s: Array = STEPS[_step]
	_title.text = "%s (%d/%d)" % [Loc.t(s[0]), _step + 1, STEPS.size()]
	_text.text = Loc.t(s[1])
	if _highlight != null and is_instance_valid(_highlight):
		_highlight.modulate = Color.WHITE
	_highlight = _find_button(_hud, String(s[2])) if _hud != null and not String(s[2]).is_empty() else null


func finish() -> void:
	if _highlight != null and is_instance_valid(_highlight):
		_highlight.modulate = Color.WHITE
	_highlight = null
	UiAnim.hide(self)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "tutorial_done", true)
	cfg.save(SETTINGS)


func _process(_delta: float) -> void:
	if visible and _highlight != null and is_instance_valid(_highlight):
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
		_highlight.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.85, 0.3), k)


static func _find_button(node: Node, text: String) -> Control:
	if node is BaseButton and (node as BaseButton).get("text") == text:
		return node as Control
	for c in node.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null
