class_name HeroRelations
## Взаимодействия героев друг с другом.
##
## Встретившись в одном регионе, герои могут разговориться (у костра,
## в таверне, на перекрёстке), и разговор меняет их отношение (bonds):
## похожая натура и дружественные расы сближают, противоположная карма —
## отталкивает. Из отношений вырастают:
##   • дружба — друзья не дерутся, помогают друг другу на войне, мстят за гибель;
##   • отряд — друзья-странники путешествуют вместе (вожак — сильнейший),
##     вместе безопаснее биться с чудовищами;
##   • наставничество — опытный учит младшего (тот быстро растёт);
##   • брак — супруги неразлучны;
##   • вербовка — слуга государства уговаривает друга присягнуть его стране;
##   • вражда — враги ищут поединка.
## Кроме того, странники приходят на помощь друзьям и добрым народам на войне
## (против демонов — особенно) или нанимаются за золото.

## Реплики для летописи (подставляются имена и регион).
const TALKS: Array[String] = [
	"%s и %s разговорились у костра в регионе %s и расстались друзьями.",
	"%s и %s до утра спорили в таверне региона %s о судьбах мира.",
	"%s рассказал %s о древних руинах региона %s.",
	"%s и %s поделились хлебом на перекрёстке дорог в регионе %s.",
]
const QUARRELS: Array[String] = [
	"%s и %s повздорили в регионе %s — теперь они враги.",
	"%s оскорбил %s при встрече в регионе %s; вражда неизбежна.",
]


## Встреча двух героев без поединка.
static func meet(world: World, a: Hero, b: Hero, where: String) -> void:
	var rng := world.rng
	if a.spouse == b.id or a.party_leader == b.id or b.party_leader == a.id:
		a.add_bond(b, 0.02)
		return
	var likeness := 1.0 - absf(a.karma - b.karma)  # 1 — одна натура, -1 — противоположные
	var race := a.race.relation_to(b.race)
	var delta := (likeness - 0.4) * 0.25 + race * 0.1 + rng.randf_range(-0.1, 0.1)
	var before := a.bond(b.id)
	a.add_bond(b, delta)
	var bond := a.bond(b.id)
	var ids := _ids(a, b)
	# Наставничество: опытный учит младшего.
	if bond > 0.1 and absi(a.level - b.level) >= 3:
		var teacher := a if a.level > b.level else b
		var pupil := b if teacher == a else a
		pupil.add_xp(world, 2.0 + teacher.level * 0.2)
		if pupil.mentor < 0:
			pupil.mentor = teacher.id
			pupil.add_deed(world, "стал учеником героя %s" % teacher.name)
			teacher.add_deed(world, "взял в ученики героя %s" % pupil.name)
			world.log_event(&"hero", "%s (%s) взял в ученики героя %s." % [teacher.display_name(),
				teacher.hero_class.display_name.to_lower(), pupil.display_name()], ids)
		return
	if bond > 0.8 and a.spouse < 0 and b.spouse < 0 and a.race == b.race and rng.randf() < 0.3:
		a.spouse = b.id
		b.spouse = a.id
		a.add_deed(world, "сочетался браком с героем %s" % b.name)
		b.add_deed(world, "сочетался браком с героем %s" % a.name)
		world.log_event(&"hero", "Герои %s и %s сочетались браком в регионе %s." % [a.display_name(), b.display_name(), where], ids)
		return
	if bond > 0.5:
		_friendship(world, a, b, where, ids, before <= 0.5)
		return
	if bond < -0.4:
		if before >= -0.4:
			world.log_event(&"hero", QUARRELS[rng.randi_range(0, QUARRELS.size() - 1)] % [a.display_name(), b.display_name(), where], ids)
		return
	if delta > 0.05 and rng.randf() < 0.15:
		world.log_event(&"hero", TALKS[rng.randi_range(0, TALKS.size() - 1)] % [a.display_name(), b.display_name(), where], ids)
	a.add_xp(world, 0.3)
	b.add_xp(world, 0.3)


static func _friendship(world: World, a: Hero, b: Hero, where: String, ids: PackedInt32Array, new_friends: bool) -> void:
	var rng := world.rng
	if new_friends:
		a.add_deed(world, "поклялся в дружбе с героем " + b.name)
		b.add_deed(world, "поклялся в дружбе с героем " + a.name)
		world.log_event(&"hero", "%s и %s поклялись в вечной дружбе в регионе %s." % [a.display_name(), b.display_name(), where], ids)
	# Вербовка: слуга государства зовёт друга-странника на службу.
	for pair in [[a, b], [b, a]]:
		var lord: Hero = pair[0]
		var free: Hero = pair[1]
		if lord.nation_id >= 0 and free.nation_id < 0 and free.party_leader < 0 and rng.randf() < 0.35:
			var n := world.nations[lord.nation_id]
			if n.alive and not n.race.has_trait(&"demonic"):
				free.nation_id = n.id
				n.hero_ids.append(free.id)
				free.add_deed(world, "по зову друга %s присягнул государству %s" % [lord.name, n.name])
				world.log_event(&"hero", "%s уговорил друга %s присягнуть государству %s." % [lord.display_name(), free.display_name(), n.name], ids)
				return
	# Отряд: два странника идут вместе за сильнейшим.
	if a.nation_id < 0 and b.nation_id < 0 and a.party_leader < 0 and b.party_leader < 0 and rng.randf() < 0.4:
		var leader := a if a.level >= b.level else b
		var follower := b if leader == a else a
		follower.party_leader = leader.id
		follower.add_deed(world, "вступил в отряд героя %s" % leader.name)
		world.log_event(&"hero", "%s и %s собрали отряд и странствуют вместе." % [leader.display_name(), follower.display_name()], ids)


## Шанс поединка с учётом дружбы, вражды и мести.
static func duel_modifier(a: Hero, b: Hero) -> float:
	if a.vendetta == b.id or b.vendetta == a.id:
		return 0.6
	var bond := a.bond(b.id)
	if a.spouse == b.id or a.party_leader == b.id or b.party_leader == a.id:
		return -1.0
	if bond > 0.4:
		return -1.0  # друзья не дерутся
	if bond < -0.4:
		return 0.15
	return 0.0


## Годовые дела, связанные с другими героями: помощь на войне, наём, месть, отряды, ученики.
static func yearly(world: World, hero: Hero) -> void:
	var rng := world.rng
	if hero.ally_nation >= 0 and (world.year >= hero.ally_until or not world.nations[hero.ally_nation].alive
			or world.diplomacy.wars_of(hero.ally_nation).is_empty()):
		hero.add_deed(world, "закончил помогать государству %s" % world.nations[hero.ally_nation].short_name)
		hero.thought = ""
		hero.ally_nation = -1
	if hero.party_leader >= 0:
		var leader := world.heroes[hero.party_leader]
		if not leader.alive or leader.is_ruler or leader.nation_id >= 0 or rng.randf() < 0.05:
			hero.party_leader = -1
	if hero.vendetta >= 0:
		var target := world.heroes[hero.vendetta]
		if not target.alive:
			hero.add_deed(world, "узнал, что враг %s уже мёртв, — месть окончена" % target.name)
			hero.thought = "%s мёртв и без меня. Месть окончена." % target.name
			hero.vendetta = -1
	if hero.nation_id < 0 and hero.ally_nation < 0:
		_join_war(world, hero)
	# Старый мастер берёт ученика — новый герой его класса.
	if hero.level >= 8 and hero.age > hero.max_age * 0.6 and hero.nation_id >= 0 and rng.randf() < 0.08:
		var n := world.nations[hero.nation_id]
		var region := world.region_at(hero.cell)
		if region != null and n.alive:
			var pupil := HeroSystem.spawn(world, n, region)
			if pupil != null:
				pupil.hero_class = hero.hero_class
				pupil.race = hero.race
				pupil.race_id = hero.race_id
				pupil.mentor = hero.id
				pupil.karma = clampf(hero.karma + rng.randf_range(-0.3, 0.3), -1.0, 1.0)
				pupil.add_bond(hero, 0.7)
				pupil.add_deed(world, "ученик великого героя " + hero.name)
				hero.add_deed(world, "воспитал ученика " + pupil.name)


## Странник приходит на помощь на войне: другу, доброму народу против бездны, или за золото.
static func _join_war(world: World, hero: Hero) -> void:
	var rng := world.rng
	var choice := -1
	var reason := ""
	for other_id in hero.bonds:
		if hero.bonds[other_id] < 0.5:
			continue
		var friend := world.heroes[other_id]
		if friend.alive and friend.nation_id >= 0 and not world.diplomacy.wars_of(friend.nation_id).is_empty():
			choice = friend.nation_id
			reason = "на помощь другу %s" % friend.name
			break
	if choice < 0 and hero.karma > 0.3:
		for war in world.diplomacy.wars:
			for side in [1, -1]:
				var enemy := world.nations[war.leader(-side)] if war.leader(-side) >= 0 else null
				if enemy != null and enemy.race.has_trait(&"demonic") and war.leader(side) >= 0:
					choice = war.leader(side)
					reason = "против демонов бездны"
	if choice < 0 and hero.karma < 0.3 and rng.randf() < 0.25:
		# Наёмник: идёт к богатому воюющему государству.
		var best := -1
		for war in world.diplomacy.wars:
			if not war.active:
				continue
			for m in war.attackers + war.defenders:
				var n := world.nations[m]
				if n.alive and n.stock[Goods.GOLD] >= 400.0 and (best < 0 or n.stock[Goods.GOLD] > world.nations[best].stock[Goods.GOLD]):
					best = n.id
		if best >= 0:
			world.nations[best].stock[Goods.GOLD] -= 250.0
			choice = best
			reason = "наёмником за 250 золота"
	if choice < 0 or rng.randf() > 0.5:
		return
	var n := world.nations[choice]
	if n.race.has_trait(&"demonic") != hero.race.has_trait(&"demonic"):
		return
	hero.ally_nation = choice
	hero.ally_until = world.year + 5
	hero.thought = "Сражаюсь за %s — %s." % [n.short_name, reason]
	hero.add_deed(world, "встал за государство %s (%s)" % [n.name, reason])
	world.log_event(&"hero", "Герой %s сражается за %s (%s)." % [hero.display_name(), n.short_name, reason],
			PackedInt32Array([choice]))


static func _ids(a: Hero, b: Hero) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for n in [a.nation_id, b.nation_id]:
		if n >= 0 and not ids.has(n):
			ids.append(n)
	return ids
