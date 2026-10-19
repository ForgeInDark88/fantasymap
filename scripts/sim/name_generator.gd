class_name NameGenerator
## Генератор имён на основе слогов языка расы (поля «Язык» в RaceDef).
## Детерминирован: всё случайное берётся из переданного RNG.

const VOWELS := "аеёиоуыэюяaeiouy"


## Корень слова: первый слог + (иногда) средний.
static func root(race: RaceDef, rng: RandomNumberGenerator) -> String:
	var s := _pick(race.name_prefixes, rng)
	if not race.name_middles.is_empty() and rng.randf() < race.middle_chance:
		s = _join(s, _pick(race.name_middles, rng), race, rng)
	return s


## Название места (город, страна).
static func place_name(race: RaceDef, rng: RandomNumberGenerator) -> String:
	return _join(root(race, rng), _pick(race.place_suffixes, rng), race, rng)


## Личное имя.
static func person_name(race: RaceDef, rng: RandomNumberGenerator) -> String:
	return _join(root(race, rng), _pick(race.person_suffixes, rng), race, rng)


## Форма правления: [полное название, титул правителя].
static func state_title(race: RaceDef, short_name: String, rng: RandomNumberGenerator) -> PackedStringArray:
	if race.state_forms.is_empty():
		return PackedStringArray([short_name, "Правитель"])
	var parts := _pick(race.state_forms, rng).split("|")
	var title := parts[1] if parts.size() > 1 else "Правитель"
	return PackedStringArray([parts[0].format({"name": short_name}), title])


## Повторяет генерацию, пока имя не окажется новым (не более 20 попыток).
static func unique(used: Dictionary, generator: Callable) -> String:
	var name: String = generator.call()
	for attempt in 20:
		if not used.has(name):
			break
		name = generator.call()
	used[name] = true
	return name


static func _pick(list: PackedStringArray, rng: RandomNumberGenerator) -> String:
	if list.is_empty():
		return ""
	return list[rng.randi_range(0, list.size() - 1)]


## Склеивает части слова: убирает удвоение букв на стыке и разбивает
## тяжёлые скопления согласных гласной-связкой.
static func _join(a: String, b: String, race: RaceDef, rng: RandomNumberGenerator) -> String:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	var last := a[a.length() - 1].to_lower()
	var first := b[0].to_lower()
	if last == first:
		return a + b.substr(1)
	var tail_consonants := 0
	for i in range(a.length() - 1, -1, -1):
		if _is_vowel(a[i]):
			break
		tail_consonants += 1
	var head_consonants := 0
	for i in b.length():
		if _is_vowel(b[i]):
			break
		head_consonants += 1
	# Не больше двух гласных подряд: «Ае» + «иэль» → «Аель».
	var tail_vowels := 0
	for i in range(a.length() - 1, -1, -1):
		if not _is_vowel(a[i]):
			break
		tail_vowels += 1
	if tail_vowels > 0:
		while b.length() > 1 and _is_vowel(b[0]) and tail_vowels >= 2:
			b = b.substr(1)
		if b.length() > 1 and _is_vowel(b[0]) and _is_vowel(b[1]):
			b = b.substr(1)
		return a + b
	if tail_consonants + head_consonants >= 3 and not race.connector_vowels.is_empty():
		var v := race.connector_vowels[rng.randi_range(0, race.connector_vowels.length() - 1)]
		return a + v + b
	return a + b


static func _is_vowel(ch: String) -> bool:
	return VOWELS.contains(ch.to_lower())
