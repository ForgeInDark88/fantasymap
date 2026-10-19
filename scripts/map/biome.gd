class_name Biome
## Индексы биомов. Генератор классифицирует клетки в эти значения;
## свойства каждого биома описаны в data/biomes/<id>.tres (см. BiomeDef, BiomeDB).
##
## Порядок важен: все водные биомы идут первыми (см. is_water).

const OCEAN := 0
const SEA := 1
const LAKE := 2
const PLAINS := 3
const STEPPE := 4
const FOREST := 5
const JUNGLE := 6
const SWAMP := 7
const DESERT := 8
const TUNDRA := 9
const SNOW := 10
const HILLS := 11
const MOUNTAINS := 12

const COUNT := 13


static func is_water(biome: int) -> bool:
	return biome <= LAKE
