// STRAY - LoD2 facade shader v2 (R9 visual upgrade). Author: Claude Code for STRAY.
// Purpose: turns untextured LoD2 walls into varied city facades without UVs or textures.
// Everything is procedural in world space; per-building parameters come from the vertex colour
// (StrayObjMesh.building_params): r = material seed, g = window seed, b = height/100, a = (base+10)/20.
// The look is GENERIC (Cologne post-war mix: plaster, brick, sandstone, modern panels) - it is
// not a reconstruction of the real facades of these buildings.
// Zones per building: plinth + shop ground floor, upper storeys with framed windows, cornice.
// WebGL2 / Compatibility friendly: no textures, no loops, a few hashes per fragment.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Target: Godot 4.7 Compatibility (GL ES 3 / WebGL2), forward. Budget: one pass, no texture
// samples, ~10 hashes per fragment; branches select facade zones (coherent per wall area).
group_uniforms night;
/** 1 = night, 0 = day (set by the street builder). */
uniform float night_factor : hint_range(0.0, 1.0) = 1.0;
/** Mean share of lit upper windows at night; varies per building. */
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.3;
uniform float lit_energy = 0.9;
uniform vec3 warm_light : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 cool_light : source_color = vec3(0.78, 0.86, 1.0);
/** Ground-floor shop interiors at night. */
uniform float shop_energy = 0.55;
/** Night: faint light from the street lamps on the lower storeys (else facades are pitch black). */
uniform float street_bounce = 0.07;
uniform vec3 bounce_color : source_color = vec3(1.0, 0.76, 0.5);
group_uniforms surfaces;
uniform vec3 sky_day : source_color = vec3(0.46, 0.55, 0.66);
uniform vec3 sky_night : source_color = vec3(0.035, 0.04, 0.06);
uniform float plaster_variation : hint_range(0.0, 0.3) = 0.07;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 bld;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 plaster_palette(float s) {
	int i = int(floor(fract(s * 7.31) * 7.0));
	if (i == 0) return vec3(0.66, 0.60, 0.50);   // warm beige
	if (i == 1) return vec3(0.60, 0.60, 0.58);   // light grey
	if (i == 2) return vec3(0.70, 0.59, 0.42);   // ochre
	if (i == 3) return vec3(0.64, 0.53, 0.49);   // pale rose
	if (i == 4) return vec3(0.73, 0.72, 0.68);   // off-white
	if (i == 5) return vec3(0.52, 0.55, 0.53);   // grey-green
	return vec3(0.62, 0.57, 0.52);               // taupe
}

void vertex() {
	// Adjacent LoD2 buildings/parts share coplanar walls. With per-building materials they z-fight
	// (speckled mix of two facades). Push each building's walls out by 0..2 cm (stable per building)
	// so exactly one surface wins.
	VERTEX += NORMAL * (0.002 + 0.018 * COLOR.r) * (1.0 - abs(NORMAL.y));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bld = COLOR;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec2 along = normalize(vec2(-n.z, n.x) + vec2(1e-5));
	float u = dot(world_pos.xz, along);
	// Snap the per-building values to the 8-bit grid they were packed on: interpolation leaves ~1e-7
	// jitter per pixel, and the sin-hash below amplifies that into speckles (random bays per pixel).
	vec4 q = floor(bld * 255.0 + 0.5);
	float s1 = q.r / 255.0;
	float s2 = q.g / 255.0;
	float id1 = q.r;  // integer-valued seeds for hashing (small, exact)
	float id2 = q.g;
	float top = max(bld.b * 100.0, 3.0);
	float base = bld.a * 20.0 - 10.0;
	float h = world_pos.y - base;
	// Material type: 0 plaster, 1 modern panels, 2 sandstone, 3 brick.
	int kind = s1 < 0.6 ? 0 : (s1 < 0.72 ? 1 : (s1 < 0.85 ? 2 : 3));
	float big = vnoise(vec2(u, h) * 0.3);
	float fine = vnoise(vec2(u, h) * 3.1);
	vec3 albedo;
	float rough = 0.9;
	if (kind == 0) {
		albedo = plaster_palette(s1) * (1.0 - plaster_variation + 2.0 * plaster_variation * (0.65 * big + 0.35 * fine));
	} else if (kind == 1) {
		// Fibre-cement / metal panels 1.25 m x storey, slight tone per panel.
		vec2 cell = floor(vec2(u / 1.25, h / 3.2));
		vec2 f = vec2(u / 1.25, h / 3.2) - cell;
		albedo = mix(vec3(0.30, 0.31, 0.33), vec3(0.50, 0.50, 0.49), fract(s1 * 13.0)) * (0.92 + 0.12 * hash12(cell + id1 * 0.17));
		if (f.x < 0.012 || f.y < 0.006) albedo *= 0.55;
		rough = 0.65;
	} else if (kind == 2) {
		// Sandstone ashlar 0.9 x 0.4 m, running bond.
		float row = floor(h / 0.4);
		float uu = u / 0.9 + 0.5 * mod(row, 2.0);
		vec2 f = vec2(fract(uu), fract(h / 0.4));
		albedo = vec3(0.62, 0.55, 0.43) * (0.88 + 0.18 * hash12(vec2(floor(uu), row))) * (0.92 + 0.12 * fine);
		if (f.x < 0.012 || f.y < 0.025) albedo *= 0.7;
	} else {
		// Brick 0.24 x 0.075 m, half-brick offset, mortar joints.
		float row = floor(h / 0.075);
		float uu = u / 0.25 + 0.5 * mod(row, 2.0);
		vec2 f = vec2(fract(uu), fract(h / 0.075));
		vec3 brick = mix(vec3(0.42, 0.18, 0.12), vec3(0.55, 0.30, 0.20), hash12(vec2(floor(uu), row)));
		albedo = (f.x < 0.05 || f.y < 0.14) ? vec3(0.55, 0.53, 0.5) : brick * (0.9 + 0.15 * fine);
	}
	// Dirt towards the ground.
	albedo *= 1.0 - 0.2 * clamp(1.0 - h / 2.2, 0.0, 1.0);

	vec3 emission = vec3(0.0);
	float metal = 0.0;  // kept for clarity; metallic sparkles the same way, so it stays 0
	float gf_top = mix(3.7, 4.7, fract(s1 * 11.3));
	// Facade reflection colour for glass: sky by day, dark navy at night.
	vec3 sky = mix(sky_day, sky_night, night_factor);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	if (h < 0.55) {
		// Plinth: dark stone cladding.
		albedo = vec3(0.2, 0.2, 0.21) * (0.85 + 0.25 * fine);
		rough = 0.7;
	} else if (h < gf_top) {
		// Ground floor: shop bays (glazing, closed glass or roller shutter) + fascia band on top.
		float bay_w = mix(3.4, 5.2, fract(s2 * 17.0));
		float bay = floor(u / bay_w);
		float bx = u - bay * bay_w;
		float bseed = hash12(vec2(bay, id1 + id2 * 0.37));
		float glass_top = gf_top - 0.7;
		bool fascia = h > glass_top;
		bool pier = bx < 0.35 || bx > bay_w - 0.35;
		if (fascia) {
			albedo *= 0.55;
			if (bseed > 0.55 && bx > 0.6 && bx < bay_w - 0.6 && h > glass_top + 0.15 && h < gf_top - 0.15) {
				// Shop sign strip: lit lettering band at night, coloured panel by day.
				vec3 sc = bseed > 0.85 ? vec3(0.9, 0.25, 0.2) : (bseed > 0.7 ? vec3(0.25, 0.55, 0.9) : vec3(0.95, 0.85, 0.6));
				albedo = sc * 0.5;
				emission += sc * 0.9 * night_factor * step(0.5, fract(bx * 1.7 + bseed));
			}
		} else if (!pier) {
			float frame = 0.07;
			bool on_frame = bx < 0.35 + frame || bx > bay_w - 0.35 - frame || h < 0.55 + frame || h > glass_top - frame
				|| abs(bx - bay_w * 0.5) < 0.04;
			if (on_frame) {
				albedo = vec3(0.12, 0.12, 0.13);
				rough = 0.4;
			} else if (bseed < 0.16) {
				// Roller shutter (closed shop): ribbed grey metal.
				albedo = vec3(0.42, 0.43, 0.44) * (0.85 + 0.15 * step(0.5, fract(h / 0.09)));
				rough = 0.55;
			} else {
				albedo = vec3(0.015, 0.017, 0.02);
				// >= 0.3: lower roughness sparkles (precision limits of the Compatibility GGX path);
				// the reflection look comes from the sky term in EMISSION instead.
				rough = 0.35;
				emission += sky * (0.25 + 0.8 * fres) * (1.0 - night_factor * 0.7);
				if (bseed > 0.32) {
					// Lit shop interior: brighter under the ceiling, darker shelves/counter below.
					float gy = clamp((h - 0.55) / max(glass_top - 0.55, 0.1), 0.0, 1.0);
					vec3 tint = bseed > 0.85 ? vec3(0.85, 0.92, 1.0) : vec3(1.0, 0.82, 0.6);
					float shelf = 0.55 + 0.45 * step(0.35, gy) * (0.7 + 0.3 * vnoise(vec2(bx * 3.0, gy * 6.0)));
					emission += tint * shop_energy * night_factor * (0.35 + 0.65 * gy) * shelf;
				}
			}
		} else {
			albedo *= 0.8;
		}
	} else if (h < top - 0.8) {
		// Upper storeys: framed windows with sill, mullion, reveal shadow, varied night lighting.
		float storey_h = mix(3.0, 3.5, fract(s2 * 2.31));
		float spacing = kind == 1 ? 1.25 * floor(mix(2.0, 3.0, fract(s2 * 4.7)) + 0.5) : mix(1.9, 3.0, fract(s2 * 3.71));
		float ww = kind == 1 ? spacing - 0.25 : spacing * mix(0.42, 0.58, fract(s2 * 5.33));
		float wh = mix(1.35, 1.8, fract(s2 * 9.13));
		float sill = mix(0.8, 1.0, fract(s2 * 7.7));
		float hs = h - gf_top;
		float storey = floor(hs / storey_h);
		float y_in = hs - storey * storey_h;
		float column = floor(u / spacing);
		float x_in = u - column * spacing - 0.5 * (spacing - ww);
		// String course between storeys on some plaster buildings.
		if (kind == 0 && fract(s2 * 21.0) > 0.5 && y_in < 0.12) {
			albedo *= 1.12;
		}
		bool in_win = x_in > 0.0 && x_in < ww && y_in > sill && y_in < sill + wh;
		bool on_sill = x_in > -0.06 && x_in < ww + 0.06 && y_in > sill - 0.07 && y_in <= sill;
		if (on_sill) {
			albedo = kind == 3 ? vec3(0.62, 0.6, 0.56) : albedo * 1.25;
		}
		// Rain streaks under the sills.
		if (!in_win && x_in > 0.1 && x_in < ww - 0.1 && y_in < sill - 0.07 && y_in > sill - 1.2) {
			albedo *= 0.94 + 0.06 * (sill - y_in) / 1.2;
		}
		if (in_win) {
			float fw = 0.075;
			vec3 frame_col = kind == 1 ? vec3(0.1, 0.1, 0.11) : (fract(s2 * 31.0) > 0.25 ? vec3(0.86, 0.86, 0.84) : vec3(0.22, 0.16, 0.12));
			bool on_frame = x_in < fw || x_in > ww - fw || y_in < sill + fw || y_in > sill + wh - fw
				|| (ww > 1.0 && abs(x_in - ww * 0.5) < 0.035);
			if (on_frame) {
				albedo = frame_col;
				rough = 0.5;
			} else {
				float seed = hash12(vec2(column, storey) + floor(n.xz * 8.0 + 0.5) * 17.0 + id1 * 0.61);
				float gy = (y_in - sill) / wh;
				// Reveal: the frame casts a soft shadow into the opening (fake depth).
				float reveal = smoothstep(fw, fw + 0.12, min(min(x_in, ww - x_in), min(y_in - sill, sill + wh - y_in)));
				albedo = vec3(0.02, 0.022, 0.026);
				rough = 0.35;
				// Curtains by day in some windows.
				if (seed > 0.7) {
					albedo = mix(albedo, vec3(0.55, 0.52, 0.48), 0.6 * step(0.35, gy));
				}
				emission += sky * (0.2 + 0.9 * fres) * (0.6 + 0.4 * gy) * (1.0 - night_factor * 0.6) * reveal;
				float ratio = lit_ratio * mix(0.35, 1.7, fract(s1 * 13.7));
				if (seed < ratio) {
					float pick = hash12(vec2(storey * 3.1, column * 1.7) + id2 * 0.13);
					vec3 tint = pick < 0.68 ? warm_light : (pick < 0.9 ? cool_light : (pick < 0.96 ? vec3(0.35, 0.5, 1.0) : vec3(1.0, 0.55, 0.3)));
					float level = mix(0.35, 1.0, hash12(vec2(column, storey * 7.0) + id1 * 0.29));
					float blinds = seed < ratio * 0.3 ? (0.55 + 0.45 * step(0.5, fract(gy * 9.0))) : 1.0;
					emission += tint * lit_energy * level * night_factor * (0.55 + 0.45 * gy) * blinds * reveal;
				}
			}
		}
	} else {
		// Cornice / attic band under the roof edge.
		albedo *= h > top - 0.35 ? 0.72 : 1.1;
	}
	// Night: lamps and shops brighten the lower storeys a little (otherwise pure black walls).
	emission += albedo * bounce_color * street_bounce * night_factor * clamp(1.0 - h / 14.0, 0.0, 1.0);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emission;
}
