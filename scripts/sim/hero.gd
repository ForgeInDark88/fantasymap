class_name Hero
extends RefCounted
## Герой: личность со своей расой, классом и судьбой. Может странствовать
## сам по себе, совершать подвиги, сражаться с другими героями, присягнуть
## государству и биться за него, а то и занять трон.

var id := -1
var name := ""
var race: RaceDef
var race_id: StringName
var hero_class: HeroClassDef
var level := 1
var xp := 0.0
var age := 25
var max_age := 70
var born_year := 0
## Где герой сейчас (клетка карты).
var cell := -1
## Кому присягнул (-1 — сам по себе).
var nation_id := -1
var alive := true
## Стал правителем — больше не странствует.
var is_ruler := false
var kills := 0
var monsters_slain := 0
## Прозвище, заслуженное подвигами («Драконоборец», «Непобедимый»…).
var epithet := ""
## Важнейшие деяния (для карточки героя).
var deeds: Array[String] = []
## Через сколько месяцев герой сдвинется с места.
var move_in := 1
## Добро (+1) или зло (-1): определяет поступки; меняется от самих поступков.
var karma := 0.0
## Оружие-артефакт (легендарное или проклятое) и множитель силы от него.
var artifact := ""
var artifact_mult := 1.0
## Судьба после смерти: &"" — ждёт суда (или жив), &"rest" — покой, &"cursed" — заточён, &"returned" — второй шанс.
var fate: StringName = &""
## Сколько раз Судьба уже возвращала героя.
var returns := 0
## Куда герой направляется (клетка цели — например, проклятый трон), -1 — бродит.
var goal_cell := -1
## Ум (0..1): от класса и личный разброс. Умный трезво оценивает противника и
## идёт на бой, только если уверен в победе; глупец недооценивает врага.
var intellect := 0.5
## О чём герой думает сейчас (последнее решение) — для окна героя.
var thought := ""

# --- Связи с другими героями ---
## Отношение к другим героям: id → -1 (враг) … +1 (друг).
var bonds: Dictionary[int, float] = {}
var spouse := -1
var mentor := -1
## Вожак отряда, за которым герой следует (-1 — сам по себе или сам вожак).
var party_leader := -1
## Временная помощь государству на войне (за друга или за золото) до года ally_until.
var ally_nation := -1
var ally_until := 0
## Кому герой поклялся отомстить (-1 — никому).
var vendetta := -1
var killed_by := -1


## Трезвость суждений: ум плюс опыт (с уровнями герои умнеют).
func wits() -> float:
	return clampf(intellect + level * 0.008, 0.0, 1.0)


## Как герой видит силу противника. Чем он глупее, тем больше ошибается —
## и почти всегда в сторону недооценки («да я его одной левой»).
## clarity > 1 — противник перед глазами (оценка точнее).
func perceive(enemy_power: float, rng: RandomNumberGenerator, clarity: float = 1.0) -> float:
	var error := (1.0 - wits()) * 1.1 / clarity
	return enemy_power * maxf(0.1, 1.0 + rng.randf_range(-error, error * 0.25))


## Решится ли герой на бой с противником такой силы.
## Умный требует запас сил, безрассудный идёт и при равных (или худших) шансах.
func dares(enemy_power: float, rng: RandomNumberGenerator, clarity: float = 1.0) -> bool:
	var margin := 0.85 + wits() * 0.65
	return power() >= perceive(enemy_power, rng, clarity) * margin


func intellect_name() -> String:
	var w := wits()
	if w >= 0.8:
		return "мудрый"
	if w >= 0.6:
		return "рассудительный"
	if w >= 0.4:
		return "неглупый"
	if w >= 0.2:
		return "простодушный"
	return "безрассудный"


func bond(other_id: int) -> float:
	return bonds.get(other_id, 0.0)


func add_bond(other: Hero, amount: float) -> void:
	bonds[other.id] = clampf(bond(other.id) + amount, -1.0, 1.0)
	other.bonds[id] = clampf(other.bond(id) + amount, -1.0, 1.0)


## За кого герой сражается: государство, которому присягнул, или которому временно помогает.
func fights_for(nation: int) -> bool:
	return nation >= 0 and (nation_id == nation or ally_nation == nation)


## Сколько воинов стоит герой в бою.
func power() -> float:
	return hero_class.power * level * artifact_mult


func display_name() -> String:
	return name + (" " + epithet if not epithet.is_empty() else "")


func add_xp(world: World, amount: float) -> void:
	xp += amount
	while xp >= level * 1.5 and level < 20:
		xp -= level * 1.5
		level += 1
		if level == 5 or level == 10 or level == 15:
			world.log_event(&"hero", "Слава героя %s (%s, %s) гремит по миру: он достиг %d-го уровня." % [
				display_name(), race.display_name.to_lower(), hero_class.display_name.to_lower(), level],
				PackedInt32Array([nation_id]) if nation_id >= 0 else PackedInt32Array())


func add_deed(world: World, text: String) -> void:
	deeds.append("%d г.: %s" % [world.year, text])
	if deeds.size() > 40:
		deeds.remove_at(0)


func leave_service(world: World) -> void:
	if nation_id >= 0:
		var n := world.nations[nation_id]
		var i := n.hero_ids.find(id)
		if i >= 0:
			n.hero_ids.remove_at(i)
	nation_id = -1


## Смерть: герой уходит со службы и встаёт в очередь на суд Судьбы.
func die(world: World, killer: Hero = null) -> void:
	leave_service(world)
	alive = false
	ally_nation = -1
	party_leader = -1
	if killer != null:
		killed_by = killer.id
		# Друзья и супруг клянутся отомстить.
		for other_id in bonds:
			var other := world.heroes[other_id]
			if other.alive and (bonds[other_id] > 0.5 or other.spouse == id) and other.vendetta < 0:
				other.vendetta = killer.id
				other.add_deed(world, "поклялся отомстить %s за гибель %s" % [killer.name, name])
				other.thought = "%s убил %s. Я найду его." % [killer.name, name]
	fate = &""
	goal_cell = -1
	if not world.fate_queue.has(id):
		world.fate_queue.append(id)
	# Кого Судьба долго не судит — уходят на покой сами.
	while world.fate_queue.size() > 60:
		world.heroes[world.fate_queue[0]].fate = &"rest"
		world.fate_queue.remove_at(0)


func alignment_name() -> String:
	if karma >= 0.5:
		return "добрый"
	if karma >= 0.15:
		return "благородный"
	if karma > -0.15:
		return "себе на уме"
	if karma > -0.5:
		return "тёмный"
	return "злодей"


func become_ruler(world: World) -> void:
	var nation := nation_id
	leave_service(world)
	is_ruler = true
	add_deed(world, "взошёл на трон государства %s" % world.nations[nation].name)
