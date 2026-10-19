class_name PopulationSystem
extends RefCounted
## Логистический рост населения каждого народа государства к ёмкости его земли.

## Базовый прирост в год (× рост расы).
const BASE_GROWTH := 0.03


func tick(_world: World, nation: Nation) -> void:
	for r in nation.pop.size():
		var p := nation.pop[r]
		var cap := nation.capacity[r] * (1.0 + nation.food_bonus)
		if cap <= 0.0:
			# Земли этого народа больше нет — остатки рассеиваются.
			nation.pop[r] = p * 0.85 if p > 1.0 else 0.0
			continue
		var race := RaceDB.by_index(r)
		if p < 1.0:
			p = cap * 0.01  # первые поселенцы
		var dp := BASE_GROWTH * race.growth * p * (1.0 - p / cap)
		if nation.famine_years > 0 and race.food_need > 0.0:
			dp -= p * 0.05
		nation.pop[r] = maxf(0.0, p + dp)
