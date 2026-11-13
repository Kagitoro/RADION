shader_type canvas_item;
// Full-screen state effects: drunk double vision, nausea wobble, energy rush.
// All amounts are 0..1 and blend smoothly; at zero the pass is a plain copy.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float drunk : hint_range(0.0, 1.0) = 0.0;
uniform float nausea : hint_range(0.0, 1.0) = 0.0;
uniform float rush : hint_range(0.0, 1.0) = 0.0;
uniform float heave : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;

vec3 sample_rgb(vec2 uv, float split) {
	vec2 dir = (uv - 0.5) * split;
	return vec3(
		texture(screen, uv + dir).r,
		texture(screen, uv).g,
		texture(screen, uv - dir).b);
}

void fragment() {
	float t = TIME + time_offset;
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	float radius = length(centered);

	// Nausea: slow warping waves stronger at the edges, plus a lurch on each heave.
	float warp = nausea * 0.012 + heave * 0.02;
	uv += vec2(sin(uv.y * 9.0 + t * 1.7), cos(uv.x * 7.0 + t * 1.3)) * warp * (0.35 + radius);
	uv = 0.5 + (uv - 0.5) * (1.0 - heave * 0.035);

	// Drunk: ghost image drifting around the real one.
	vec2 ghost = vec2(sin(t * 0.9), cos(t * 0.7)) * drunk * 0.012;
	float lod = (nausea * 1.6 + heave * 2.2) * smoothstep(0.15, 0.65, radius);
	vec3 base = textureLod(screen, uv, lod).rgb;
	vec3 doubled = textureLod(screen, uv + ghost, lod + drunk).rgb;
	vec3 color = mix(base, doubled, drunk * 0.42);

	// Energy rush: chromatic split and a cleaner, punchier image.
	float split = rush * 0.006 + nausea * 0.003;
	if (split > 0.0001) {
		vec3 fringe = sample_rgb(uv, split);
		color = mix(color, fringe, 0.65);
	}
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, 1.0 + rush * 0.35 - nausea * 0.25);
	color = (color - 0.5) * (1.0 + rush * 0.12) + 0.5;

	// Sickly tint for nausea, warm haze for alcohol.
	color = mix(color, color * vec3(0.86, 1.02, 0.78), nausea * 0.55);
	color = mix(color, color * vec3(1.06, 0.98, 0.9), drunk * 0.25);

	// Vignette that tightens when sick.
	float vig = 1.0 - smoothstep(0.25, 0.85 - nausea * 0.25 - heave * 0.2, radius);
	color *= mix(1.0, vig, clamp(nausea * 0.6 + drunk * 0.3 + heave * 0.45 + rush * 0.2, 0.0, 0.85));
	COLOR = vec4(color, 1.0);
}
