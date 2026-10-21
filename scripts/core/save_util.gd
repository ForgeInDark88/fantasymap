class_name SaveUtil
extends RefCounted
## Вспомогательное для сохранений (часть SaveSystem): точная запись чисел
## с плавающей точкой, base64 Packed-массивов, цвета, словари с целыми ключами,
## порядок ключей.

## Версия формата. 1 — этап 6; 2 — религии, технологии и далее (этапы 7+).
## Старые версии загружаются: недостающее заполняется значениями по умолчанию.
const VERSION := 2
const SAVE_DIR := "user://saves/"
const EXACT_PREFIX := "~"


static func _str_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


## Парсер JSON в Godot теряет последний бит у ~30% чисел double, а за десятки
## лет такая ошибка меняет исход войны. Поэтому числа, которые не переживают
## запись в текст без потерь, пишутся как «~» + 16 hex-цифр их битов.
static func exact(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if JSON.stringify(f, "", false, true).to_float() == f:
				return f
			return EXACT_PREFIX + PackedFloat64Array([f]).to_byte_array().hex_encode()
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = exact(v[k])
			return out
		TYPE_ARRAY:
			var out := []
			out.resize(v.size())
			for i in v.size():
				out[i] = exact(v[i])
			return out
	return v


## Обратное к exact(): «~hex» снова становятся точными числами (на месте).
static func unexact(v: Variant) -> Variant:
	match typeof(v):
		TYPE_STRING:
			var s: String = v
			if s.length() == 17 and s.begins_with(EXACT_PREFIX):
				return s.substr(1).hex_decode().to_float64_array()[0]
		TYPE_DICTIONARY:
			for k in v:
				v[k] = unexact(v[k])
		TYPE_ARRAY:
			for i in v.size():
				v[i] = unexact(v[i])
	return v


## Сжимать большие массивы клеток (zstd) — включается для карт ×2 и крупнее
## (SaveSystem.to_dict): сохранения ×1 остаются байт в байт прежними.
static var compress_cells := false
## Сжимать массивы не меньше этого размера (байт).
const COMPRESS_MIN := 4096


static func _b64(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	if compress_cells and bytes.size() >= COMPRESS_MIN:
		# «z:<размер>:<base64 сжатого>» — _raw узнаёт формат по префиксу.
		return "z:%d:%s" % [bytes.size(), Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))]
	return Marshalls.raw_to_base64(bytes)


## Всегда сжатый base64 (для новых больших массивов, которых нет в старых сохранениях).
static func _zb64(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	return "z:%d:%s" % [bytes.size(), Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))]


static func _int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


# ---------------------------------------------------------------------------
# Чтение
# ---------------------------------------------------------------------------


## Переставляет ключи словаря в порядке order (значения не меняются).
static func _reorder(d: Dictionary, order: Array) -> void:
	var copy := d.duplicate()
	d.clear()
	for k in order:
		if copy.has(int(k)):
			d[int(k)] = copy[int(k)]
			copy.erase(int(k))
	for k in copy:
		d[k] = copy[k]


## Цвет без потерь (to_html округляет до 8 бит на канал).
static func _col(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _to_col(v: Variant) -> Color:
	if typeof(v) == TYPE_STRING:
		return Color.html(v)
	return Color(v[0], v[1], v[2], v[3])


static func _raw(text: String) -> PackedByteArray:
	if text.is_empty():
		return PackedByteArray()
	if text.begins_with("z:"):
		var sep := text.find(":", 2)
		var size := int(text.substr(2, sep - 2))
		return Marshalls.base64_to_raw(text.substr(sep + 1)).decompress(size, FileAccess.COMPRESSION_ZSTD)
	return Marshalls.base64_to_raw(text)
