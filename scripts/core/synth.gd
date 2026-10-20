class_name Synth
extends RefCounted
## Процедурный синтез звука без внешних файлов: эмбиент-темы (бас, пэд,
## мелодия по ладу, ударные) и короткие звуки событий. Возвращает PCM 16 бит
## моно (PackedByteArray) — генерировать можно в фоновом потоке; AudioStreamWAV
## из них собирает make_stream в главном. Мелодии — случайное блуждание по
## ступеням лада (свой ГСЧ, засеянный именем темы): повторяемо и без копий
## известных мелодий.

const RATE := 22050
## Лады: ступени в полутонах от тоники.
const SCALES := {
	&"major": [0, 2, 4, 5, 7, 9, 11], &"minor": [0, 2, 3, 5, 7, 8, 10], &"dorian": [0, 2, 3, 5, 7, 9, 10],
	&"lydian": [0, 2, 4, 6, 7, 9, 11], &"phrygian": [0, 1, 3, 5, 7, 8, 10], &"locrian": [0, 1, 3, 5, 6, 8, 10],
	&"pent_major": [0, 2, 4, 7, 9], &"pent_minor": [0, 3, 5, 7, 10], &"hijaz": [0, 1, 4, 5, 7, 8, 10],
	&"harmonic": [0, 2, 3, 5, 7, 8, 11], &"mixolydian": [0, 2, 4, 5, 7, 9, 10],
}
## Лейтмотивы рас: лад, тембр (sine, triangle, square, saw), тоника (MIDI).
const RACE_MOTIFS := {
	&"humans": [&"major", &"triangle", 57], &"elves": [&"lydian", &"sine", 62], &"dwarves": [&"dorian", &"square", 50],
	&"orcs": [&"phrygian", &"saw", 48], &"goblins": [&"pent_minor", &"square", 55], &"undead": [&"locrian", &"sine", 52],
	&"demons": [&"harmonic", &"saw", 47], &"nagas": [&"hijaz", &"sine", 58], &"halflings": [&"pent_major", &"triangle", 60],
}
## Контексты музыки: темп (уд/мин), тёмный лад вместо мажорного, ударные, громкость мелодии, плотность нот.
const CONTEXTS := {
	&"peace": {"bpm": 72, "dark": false, "drums": false, "lead": 0.22, "density": 0.55},
	&"tension": {"bpm": 104, "dark": true, "drums": true, "lead": 0.2, "density": 0.75},
	&"dark": {"bpm": 58, "dark": true, "drums": false, "lead": 0.16, "density": 0.35},
	&"heroic": {"bpm": 116, "dark": false, "drums": true, "lead": 0.26, "density": 0.8},
	&"crisis": {"bpm": 64, "dark": true, "drums": true, "lead": 0.14, "density": 0.3},
}
## Тёмные лады для контекстов dark/tension/crisis (минорный двойник лада расы).
const DARK_OF := {&"major": &"minor", &"lydian": &"dorian", &"pent_major": &"pent_minor", &"mixolydian": &"dorian"}
## Длина музыкальной петли (тактов по 4 доли).
const BARS := 8


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


static func wave(kind: StringName, phase: float) -> float:
	var p := fposmod(phase, 1.0)
	match kind:
		&"triangle":
			return 4.0 * absf(p - 0.5) - 1.0
		&"square":
			return 0.6 if p < 0.5 else -0.6
		&"saw":
			return (2.0 * p - 1.0) * 0.7
	return sin(p * TAU)


## Параметры темы: лад, тембр, тоника, темп… по контексту и расе.
static func theme(context: StringName, race: StringName) -> Dictionary:
	var motif: Array = RACE_MOTIFS.get(race, RACE_MOTIFS[&"humans"])
	var ctx: Dictionary = CONTEXTS.get(context, CONTEXTS[&"peace"])
	var scale: StringName = motif[0]
	if ctx.dark:
		scale = DARK_OF.get(scale, scale)
	return {"name": "%s_%s" % [context, race], "scale": scale, "timbre": motif[1], "root": int(motif[2]),
		"bpm": int(ctx.bpm), "drums": bool(ctx.drums), "lead": float(ctx.lead), "density": float(ctx.density)}


## Музыкальная петля темы: PCM16 моно.
static func render_theme(t: Dictionary) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(t.name))
	var steps: Array = SCALES[t.scale]
	var beat := 60.0 / float(t.bpm)
	var n := int(BARS * 4 * beat * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var root := int(t.root)
	# Гармония: тоника, субдоминанта, доминанта, параллель — по такту.
	var degrees := [0, 3, 4, 0, 5, 3, 4, 0]
	for bar in BARS:
		var deg: int = degrees[bar % degrees.size()]
		var start := int(bar * 4 * beat * RATE)
		var bar_len := int(4 * beat * RATE)
		# Бас и пэд (терция и квинта ступени).
		_note(buf, start, bar_len, midi_hz(root - 12 + _step(steps, deg)), &"sine", 0.22, 0.02, 0.3)
		for k in [0, 2, 4]:
			_note(buf, start, bar_len, midi_hz(root + _step(steps, deg + k)), &"sine", 0.07, 0.4, 0.6)
	# Мелодия: блуждание по ступеням.
	var pos := 0
	var deg := 0
	var eighth := int(beat * 0.5 * RATE)
	while pos < n - eighth:
		var dur := eighth * (1 if rng.randf() < 0.5 else 2)
		if rng.randf() < float(t.density):
			deg = clampi(deg + rng.randi_range(-2, 2), -3, 9)
			_note(buf, pos, dur, midi_hz(root + 12 + _step(steps, deg)), t.timbre, float(t.lead), 0.01, 0.5)
		pos += dur
	if t.drums:
		for b in BARS * 4:
			var at := int(b * beat * RATE)
			_noise(buf, at, int(0.08 * RATE), 0.25 if b % 2 == 0 else 0.12, rng)
			_note(buf, at, int(0.12 * RATE), 55.0, &"sine", 0.35 if b % 4 == 0 else 0.0, 0.002, 0.9)
	return _pcm(buf)


static func _step(steps: Array, degree: int) -> int:
	var octave := floori(float(degree) / steps.size())
	return int(steps[posmod(degree, steps.size())]) + 12 * octave


## Нота с огибающей (атака attack с, затухание — доля decay длительности).
static func _note(buf: PackedFloat32Array, start: int, length: int, hz: float, timbre: StringName, vol: float, attack: float, decay: float) -> void:
	if vol <= 0.0:
		return
	var a := maxi(1, int(attack * RATE))
	var rel := maxi(1, int(length * decay))
	var phase := 0.0
	var inc := hz / RATE
	var smooth := 0.0
	var end := mini(buf.size(), start + length)
	for i in range(start, end):
		var k := i - start
		var env := minf(1.0, float(k) / a) * minf(1.0, float(end - i) / rel)
		phase += inc
		# Мягкий фильтр — без резкого «писка» у квадрата и пилы.
		smooth += (wave(timbre, phase) - smooth) * 0.35
		buf[i] += smooth * env * vol


static func _noise(buf: PackedFloat32Array, start: int, length: int, vol: float, rng: RandomNumberGenerator) -> void:
	var end := mini(buf.size(), start + length)
	for i in range(start, end):
		buf[i] += rng.randf_range(-1.0, 1.0) * vol * (1.0 - float(i - start) / length)


## Мягкое ограничение и перевод в PCM16.
static func _pcm(buf: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(buf.size() * 2)
	for i in buf.size():
		var x := buf[i]
		x = x / (1.0 + absf(x))
		out.encode_s16(i * 2, int(clampf(x, -1.0, 1.0) * 32000.0))
	return out


## Звуки событий: id → [ноты (MIDI), длительность ноты (с), тембр, шум].
const SFX := {
	&"click": [[84], 0.04, &"sine", 0.0], &"open": [[72, 79], 0.06, &"triangle", 0.0],
	&"war": [[45, 44, 40], 0.22, &"saw", 0.4], &"siege": [[40, 40], 0.18, &"square", 0.5],
	&"peace": [[67, 71, 74, 79], 0.16, &"triangle", 0.0], &"plague": [[50, 49, 46], 0.3, &"sine", 0.2],
	&"achievement": [[72, 76, 79, 84], 0.12, &"triangle", 0.0], &"birth": [[76, 79, 84], 0.12, &"sine", 0.0],
	&"portal": [[38, 37, 31], 0.35, &"saw", 0.6], &"death": [[60, 55, 51, 48], 0.22, &"sine", 0.0],
	&"great": [[60, 64, 67, 72], 0.14, &"square", 0.1],
}


static func render_sfx(id: StringName) -> PackedByteArray:
	var d: Array = SFX.get(id, SFX[&"click"])
	var notes: Array = d[0]
	var step := int(float(d[1]) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(step * (notes.size() + 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(id))
	for i in notes.size():
		_note(buf, i * step, step * 2, midi_hz(float(notes[i])), d[2], 0.5, 0.005, 0.7)
		if float(d[3]) > 0.0:
			_noise(buf, i * step, step, float(d[3]) * 0.5, rng)
	return _pcm(buf)


static func make_stream(pcm: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = pcm
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = pcm.size() / 2
	return s
