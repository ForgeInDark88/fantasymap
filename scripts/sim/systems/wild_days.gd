class_name WildDays
## Раскладка сущностей дикого мира (племена, логова) по «своему» дню месяца
## (поле day): ход раз в месяц без ежедневного перебора всего списка. Порядок
## внутри дня — порядок списка, поэтому раскладка детерминирована.


static func bucket(list: Array) -> Array:
	var days := []
	days.resize(Simulation.DAYS)
	for d in Simulation.DAYS:
		days[d] = []
	for x in list:
		days[x.day].append(x)
	return days
