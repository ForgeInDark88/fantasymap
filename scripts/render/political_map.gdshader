// Политический слой поверх базовой текстуры карты.
//
// owner_tex — одна точка на клетку: RG = (id государства + 1) в 16 битах, B = суша.
// palette_tex — цвет по id (256 цветов в строке). Заливка, контуры границ,
// выделение выбранного государства считаются здесь, на GPU, поэтому смена
// владельцев клеток стоит лишь загрузки одной маленькой текстуры.
shader_type canvas_item;

uniform sampler2D owner_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;

uniform bool show_fill = true;
uniform bool show_borders = true;
uniform float fill_alpha = 0.5;
// Насколько обесцветить ничью сушу (чтобы государства выделялись).
uniform float unowned_desaturate = 0.0;
// Толщина контура в пикселях экрана.
uniform float border_px = 1.5;
uniform float border_darken = 0.5;
uniform int selected_id = -1;

int owner_at(ivec2 c, ivec2 size) {
	c = clamp(c, ivec2(0), size - ivec2(1));
	vec4 o = texelFetch(owner_tex, c, 0);
	return int(round(o.r * 255.0)) + int(round(o.g * 255.0)) * 256 - 1;
}

vec3 palette(int id) {
	return texelFetch(palette_tex, ivec2(id % 256, id / 256), 0).rgb;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	ivec2 size = textureSize(owner_tex, 0);
	vec2 cell_f = UV * vec2(size);
	ivec2 cell = ivec2(floor(cell_f));
	vec2 local = fract(cell_f);
	int id = owner_at(cell, size);
	vec3 col = base.rgb;

	if (id < 0) {
		bool land = texelFetch(owner_tex, clamp(cell, ivec2(0), size - ivec2(1)), 0).b > 0.5;
		if (land && show_fill) {
			float grey = dot(col, vec3(0.299, 0.587, 0.114));
			col = mix(col, vec3(grey), unowned_desaturate);
		}
	} else {
		vec3 nc = palette(id);
		bool selected = id == selected_id;
		if (show_fill) {
			col = mix(col, nc, clamp(fill_alpha * (selected ? 1.5 : 1.0), 0.0, 0.9));
		}
		if (show_borders) {
			// Ширина контура в долях клетки: тонкая линия при приближении,
			// целая клетка, когда клетка меньше пикселя.
			float px_per_cell = 1.0 / max(fwidth(cell_f.x), 1e-5);
			float bw = border_px * (selected ? 2.0 : 1.0) / px_per_cell;
			bool edge = false;
			if (bw >= 0.5) {
				edge = owner_at(cell + ivec2(-1, 0), size) != id || owner_at(cell + ivec2(1, 0), size) != id
					|| owner_at(cell + ivec2(0, -1), size) != id || owner_at(cell + ivec2(0, 1), size) != id;
			} else {
				bool l = local.x < bw, r = local.x > 1.0 - bw;
				bool t = local.y < bw, b = local.y > 1.0 - bw;
				edge = (l && owner_at(cell + ivec2(-1, 0), size) != id)
					|| (r && owner_at(cell + ivec2(1, 0), size) != id)
					|| (t && owner_at(cell + ivec2(0, -1), size) != id)
					|| (b && owner_at(cell + ivec2(0, 1), size) != id)
					// Диагонали закрывают «дырки» во внутренних углах.
					|| (l && t && owner_at(cell + ivec2(-1, -1), size) != id)
					|| (r && t && owner_at(cell + ivec2(1, -1), size) != id)
					|| (l && b && owner_at(cell + ivec2(-1, 1), size) != id)
					|| (r && b && owner_at(cell + ivec2(1, 1), size) != id);
			}
			if (edge) {
				col = selected ? mix(nc, vec3(1.0), 0.65) : nc * (1.0 - border_darken);
			}
		}
	}
	COLOR = vec4(col, base.a);
}
