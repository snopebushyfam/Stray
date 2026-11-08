// STRAY - LoD2 facade shader (Prototype 001). Author: Claude Code for STRAY.
// Purpose: turns untextured LoD2 walls into plastered facades with a window grid
// (storeys + window columns) computed in world space, so no UVs are needed.
// Upper-floor windows light up at night from a stable per-window hash.
// Ground floor (below ground_floor_top) stays plaster; shopfronts are separate geometry.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

group_uniforms surfaces;
uniform vec3 plaster_color : source_color = vec3(0.46, 0.42, 0.37);
uniform vec3 frame_color : source_color = vec3(0.18, 0.17, 0.16);
uniform vec3 glass_color : source_color = vec3(0.025, 0.03, 0.04);
uniform float plaster_variation : hint_range(0.0, 0.3) = 0.08;

group_uniforms grid;
/** Top of the ground floor above street level (m); no upper windows below it. */
uniform float ground_floor_top = 4.4;
uniform float storey_height = 3.2;
uniform float window_spacing = 2.6;
uniform float window_width = 1.25;
uniform float window_height = 1.6;
/** Sill height above the storey floor (m). */
uniform float window_sill = 0.9;
uniform float frame_width = 0.06;

group_uniforms night_lights;
/** Share of windows lit at night (0..1). */
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.25;
/** 1 = night, 0 = day (set by the street builder). */
uniform float night_factor : hint_range(0.0, 1.0) = 1.0;
uniform vec3 warm_light : source_color = vec3(1.0, 0.74, 0.44);
uniform vec3 cool_light : source_color = vec3(0.70, 0.82, 1.0);
uniform float lit_energy = 1.1;

varying vec3 world_pos;
varying vec3 world_normal;

// Cheap 2D hash -> [0, 1).
float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise (bilinear between hashed lattice points) for soft plaster stains.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	// Horizontal direction along the wall (perpendicular to the wall normal).
	vec2 along = normalize(vec2(-n.z, n.x) + vec2(1e-5));
	float u = dot(world_pos.xz, along);
	float h = world_pos.y;

	// Plaster: soft large stains (~3 m) + fine grain, darker towards the ground (dirt).
	float stain = 0.65 * vnoise(vec2(u, h) * 0.33) + 0.35 * vnoise(vec2(u, h) * 2.7);
	float grime = clamp(1.0 - h / 2.5, 0.0, 1.0) * 0.18;
	vec3 albedo = plaster_color * (1.0 - plaster_variation + 2.0 * plaster_variation * stain) * (1.0 - grime);
	float roughness = 0.92;
	vec3 emission = vec3(0.0);

	if (h > ground_floor_top) {
		float storey = floor((h - ground_floor_top) / storey_height);
		float y_in = (h - ground_floor_top) - storey * storey_height;
		float column = floor(u / window_spacing);
		float x_in = u - column * window_spacing - 0.5 * (window_spacing - window_width);
		bool in_window = x_in > 0.0 && x_in < window_width && y_in > window_sill && y_in < window_sill + window_height;
		if (in_window) {
			bool on_frame = x_in < frame_width || x_in > window_width - frame_width
				|| y_in < window_sill + frame_width || y_in > window_sill + window_height - frame_width;
			if (on_frame) {
				albedo = frame_color;
			} else {
				// Seed per window: column, storey and quantised wall orientation (stable across frames).
				float seed = hash12(vec2(column, storey) + floor(n.xz * 8.0) * 17.0);
				albedo = glass_color;
				roughness = 0.08;
				if (seed < lit_ratio) {
					vec3 tint = seed < lit_ratio * 0.75 ? warm_light : cool_light;
					emission = tint * lit_energy * night_factor * (0.6 + 0.4 * hash12(vec2(storey, column) * 3.1));
				}
			}
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	EMISSION = emission;
}
