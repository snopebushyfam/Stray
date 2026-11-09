// STRAY - character clothing shader (R10 character upgrade). Author: Claude Code for STRAY.
// Purpose: dresses the CC0 Quaternius UAL mannequin as an everyday person without new assets.
// Each vertex carries a clothing zone + its bind-pose position in COLOR (StrayCharacterLook):
//   r = zone / 15, g = rest y / 2, b = rest x / 2 + 0.5, a = rest z / 2 + 0.5  (model faces +Z)
// Zones (kept in COLOR.r for diagnostics): 0 skin, 1 hair, 2 top, 3 sleeve, 4 pants, 5 shoes,
//        6 neck, 7 hands, 8 face. The shader itself splits by bind-pose landmarks (smooth lines).
// One material per look (uniform colours); the mesh is shared by every character.
// Target: Godot 4.7 Compatibility (WebGL2), forward, skinned. No textures; a few noise lookups.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

group_uniforms look;
uniform vec3 skin : source_color = vec3(0.78, 0.6, 0.48);
uniform vec3 hair : source_color = vec3(0.12, 0.08, 0.05);
uniform vec3 top : source_color = vec3(0.25, 0.3, 0.22);
/** Trim colour: hood lining, zipper, cuffs, drawstrings. */
uniform vec3 trim : source_color = vec3(0.12, 0.12, 0.12);
uniform vec3 pants : source_color = vec3(0.12, 0.15, 0.24);
uniform vec3 shoes : source_color = vec3(0.85, 0.85, 0.83);
uniform vec3 sole : source_color = vec3(0.95, 0.95, 0.93);
/** 1 = T-shirt (forearms bare). */
uniform float short_sleeves : hint_range(0.0, 1.0) = 0.0;
/** 1 = high collar / hood around the neck. */
uniform float collar : hint_range(0.0, 1.0) = 0.0;
/** 1 = front zipper line (jackets), 0 = pullover / hoodie pocket. */
uniform float zipper : hint_range(0.0, 1.0) = 0.0;
/** 1 = bald (hair zone uses the skin colour). */
uniform float bald : hint_range(0.0, 1.0) = 0.0;
/** Fabric roughness of the top (leather ~0.45, cotton ~0.9). */
uniform float top_roughness : hint_range(0.0, 1.0) = 0.88;

group_uniforms rig;
// Bind-pose landmarks (m) measured from the skeleton/mesh by StrayCharacterLook. Zone borders are
// straight lines in the bind pose, so they stay clean (per-triangle zones looked jagged).
uniform float eye_y = 1.66;
uniform float face_z = 0.1;
uniform float head_y0 = 1.55;
uniform float head_y1 = 1.83;
uniform float head_zc = 0.0;
uniform float neck_y = 1.47;
uniform float shoulder_x = 0.2;
uniform float elbow_x = 0.45;
uniform float wrist_x = 0.7;
uniform float belt_y = 0.98;
uniform float ankle_y = 0.1;

varying flat float zone;  // diagnostics only
varying vec3 rest;

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

void vertex() {
	// No clothing inflation: pushing the segmented mannequin along its normals opened visible cracks.
	zone = floor(COLOR.r * 15.0 + 0.5);
	rest = vec3(COLOR.b * 2.0 - 1.0, COLOR.g * 2.0, COLOR.a * 2.0 - 1.0);
}

void fragment() {
	vec3 c = skin;
	float rough = 0.6;
	float fab = vnoise(rest.xy * 180.0) * 0.5 + vnoise(rest.zy * 60.0) * 0.5;  // woven fabric grain
	float ax = abs(rest.x);
	float sleeve_end = short_sleeves > 0.5 ? mix(shoulder_x, elbow_x, 0.55) : wrist_x;
	if (ax > wrist_x - 0.01 && rest.y > 1.0) {
		c = skin;  // hands (arms are horizontal in the bind pose)
	} else if (rest.y > head_y0 && ax < 0.16) {
		float rel = (rest.y - head_y0) / max(head_y1 - head_y0, 0.001);
		bool is_hair = rel > 0.7 || (rest.z < head_zc - 0.02 && rel > 0.32);
		if (is_hair) {
			c = bald > 0.5 ? skin * 0.95 : hair * (0.85 + 0.3 * vnoise(vec2(rest.x * 90.0, rest.y * 400.0)));
			rough = 0.75;
		} else {
			// Face: eyes and brows (no textures, readable at street distance).
			float ex = abs(ax - 0.034);
			if (rest.z > face_z - 0.02 && ex < 0.011 && abs(rest.y - eye_y) < 0.007) c = vec3(0.05, 0.04, 0.04);
			else if (rest.z > face_z - 0.03 && ex < 0.016 && abs(rest.y - (eye_y + 0.022)) < 0.004) c = hair * 0.9;
			rough = 0.55;
		}
	} else if (rest.y > neck_y && ax < 0.13) {
		c = collar > 0.5 && rest.y < neck_y + 0.05 ? mix(top, trim, 0.4) : skin;  // neck / collar band
		rough = collar > 0.5 ? top_roughness : 0.6;
	} else if (ax > sleeve_end && rest.y > 1.0) {
		c = skin;  // bare forearm (T-shirt)
	} else if (rest.y > belt_y) {
		// Top: body + sleeves.
		c = top * (0.9 + 0.2 * fab);
		rough = top_roughness;
		if (short_sleeves < 0.5 && ax > wrist_x - 0.06 && rest.y > 1.0) c = trim;  // cuffs
		else if (rest.y < belt_y + 0.05 && ax < 0.3) c = top * 0.78;               // hem band
		else if (rest.z > 0.0 && ax < 0.3) {
			if (zipper > 0.5 && ax < 0.007) c = trim;
			else if (zipper < 0.5 && rest.y > belt_y + 0.06 && rest.y < belt_y + 0.2 && abs(ax - 0.11) < 0.006) c = top * 0.7;
		}
	} else if (rest.y > ankle_y) {
		// Denim-like trousers: diagonal twill + faded thighs.
		float twill = step(0.5, fract((rest.y + rest.x) * 260.0));
		c = pants * (0.88 + 0.08 * twill + 0.12 * fab);
		if (rest.z > 0.0 && rest.y > 0.55 && rest.y < 0.85) c *= 1.08;
		rough = 0.92;
	} else {
		c = rest.y < 0.035 ? sole : shoes;
		rough = 0.55;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
