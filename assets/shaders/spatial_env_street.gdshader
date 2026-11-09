// STRAY - street surfaces shader (Prototype 001). Author: Claude Code for STRAY.
// Purpose: asphalt, concrete paving slabs and kerb stones without UVs: patterns are
// computed in world space, aligned to the street axis (street_axis uniform).
// surface_kind: 0 = asphalt, 1 = paving slabs, 2 = kerb / median stone.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform int surface_kind = 0;
uniform vec3 base_color : source_color = vec3(0.035, 0.035, 0.038);
/** Unit vector of the street axis in world XZ (Godot x, z). */
uniform vec2 street_axis = vec2(0.0, -1.0);
/** Paving slab size along / across the street (m). */
uniform vec2 slab_size = vec2(0.4, 0.4);
uniform float joint_width = 0.012;
uniform float color_variation : hint_range(0.0, 0.4) = 0.12;
/** Extra specular sheen on asphalt at night (slightly damp city street look). */
uniform float sheen : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise, bilinear between hashed lattice points.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 axis = normalize(street_axis);
	vec2 across = vec2(-axis.y, axis.x);
	vec2 st = vec2(dot(world_pos.xz, axis), dot(world_pos.xz, across));
	vec3 albedo = base_color;
	float rough = 0.9;
	if (surface_kind == 0) {
		// Asphalt: two octaves of grain + larger patches.
		float g = 0.6 * vnoise(st * 9.0) + 0.4 * vnoise(st * 37.0);
		float patch = vnoise(st * 0.35);
		albedo *= 0.75 + 0.5 * g * (0.8 + 0.4 * patch);
		rough = mix(0.95, 0.55, sheen * patch);
		// R9: rectangular repair patches (newer, darker asphalt) on a 6 x 3 m grid, ~1 in 6 cells.
		vec2 pc = floor(st / vec2(6.0, 3.0));
		vec2 pf = st / vec2(6.0, 3.0) - pc;
		float has_patch = step(0.83, hash12(pc + 7.0)) * step(0.15, pf.x) * step(pf.x, 0.75) * step(0.2, pf.y) * step(pf.y, 0.8);
		albedo *= 1.0 - 0.28 * has_patch;
		// Fine cracks: thin dark lines where a stretched noise crosses its mid value.
		float cr = vnoise(st * vec2(0.9, 2.3) + 13.0);
		albedo *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.012, abs(cr - 0.5))) * step(0.55, vnoise(st * 0.2 + 3.0));
	} else if (surface_kind == 1) {
		// Concrete slabs with dark joints and per-slab tone.
		vec2 cell = floor(st / slab_size);
		vec2 f = st / slab_size - cell;
		vec2 jw = joint_width / slab_size;
		bool joint = f.x < jw.x || f.y < jw.y;
		float tone = 1.0 - color_variation + 2.0 * color_variation * hash12(cell);
		albedo *= joint ? 0.45 : tone * (0.9 + 0.2 * vnoise(st * 23.0));
		// R9: chewing-gum spots and darker weathered slabs (city sidewalk).
		float gum = step(0.985, hash12(floor(st * 7.0) + 3.0));
		albedo *= 1.0 - 0.45 * gum * (joint ? 0.0 : 1.0);
		albedo *= 1.0 - 0.12 * step(0.9, hash12(cell + 11.0));
		rough = joint ? 0.98 : 0.85;
	} else {
		// Kerb / median stone: long blocks (1 m) along the axis.
		float block = floor(st.x / 1.0);
		float f = fract(st.x / 1.0);
		albedo *= (f < 0.015 ? 0.5 : 0.9 + 0.2 * hash12(vec2(block, 3.0))) * (0.92 + 0.16 * vnoise(st * 30.0));
		rough = 0.75;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
}
