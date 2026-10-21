class_name Loc
## Локализация интерфейса (этап 11.F). Ключ — сама русская строка интерфейса,
## перевод — data/locale/<язык>.txt (строка по-русски<TAB>перевод). Переводы
## регистрируются в TranslationServer, а элементы интерфейса Godot переводят
## свои надписи и подсказки сами (auto_translate) — достаточно сменить язык.
## Текст мира (летопись, имена, описания) остаётся на языке мира.

const LOCALES := ["ru", "en"]
const LOCALE_NAMES := {"ru": "Русский", "en": "English"}
const DIR := "res://data/locale/"
const SETTINGS := "user://settings.cfg"

static var locale := "ru"
static var _loaded := false


## Таблица перевода языка: русская строка → перевод (ru — пусто).
static func table(lang: String) -> Dictionary:
	var res := {}
	if lang == "ru":
		return res
	var f := FileAccess.open(DIR + lang + ".txt", FileAccess.READ)
	if f == null:
		return res
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split("\t")
		if parts.size() == 2:
			res[parts[0]] = parts[1]
	return res


static func init() -> void:
	if not _loaded:
		_loaded = true
		for lang in LOCALES:
			var t := table(lang)
			if t.is_empty():
				continue
			var tr := Translation.new()
			tr.locale = lang
			for k in t:
				tr.add_message(k, t[k])
			TranslationServer.add_translation(tr)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		locale = str(cfg.get_value("ui", "locale", locale))
	set_locale(locale, false)


static func set_locale(lang: String, save: bool = true) -> void:
	locale = lang if LOCALES.has(lang) else "ru"
	TranslationServer.set_locale(locale)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("ui", "locale", locale)
		cfg.save(SETTINGS)


## Перевод строки интерфейса (для текстов, собираемых в коде).
static func t(text: String) -> String:
	return TranslationServer.translate(text) if locale != "ru" else text
