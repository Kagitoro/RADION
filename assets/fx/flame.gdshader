shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Small lighter flame: camera-facing quad with a flickering teardrop shape.

uniform float intensity = 1.0;
uniform float depth_squeeze = 0.06;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	// Billboard around the local Y axis, then squeeze depth like the viewmodel.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1], vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, MODEL_MATRIX[1].xyz)), 0.0), MODEL_MATRIX[3]);
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z = mix(POSITION.w, POSITION.z, depth_squeeze);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 9.0;
	float sway = (noise(vec2(uv.y * 3.0, t * 0.6)) - 0.5) * 0.25 * (1.0 - uv.y);
	vec2 p = vec2((uv.x - 0.5 + sway) * 2.0, 1.0 - uv.y);
	// Teardrop: wide near the base, sharp tip at the top.
	float width = mix(0.55, 0.02, pow(p.y, 0.8)) * smoothstep(0.0, 0.18, p.y);
	float shape = 1.0 - smoothstep(width * 0.55, width, abs(p.x));
	shape *= smoothstep(1.0, 0.75, p.y + noise(vec2(t, 0.0)) * 0.15);
	float core = 1.0 - smoothstep(0.0, width * 0.45, abs(p.x));
	core *= smoothstep(0.55, 0.15, p.y) * smoothstep(0.02, 0.16, p.y);
	vec3 outer = vec3(1.0, 0.45, 0.08);
	vec3 inner = vec3(1.0, 0.92, 0.65);
	vec3 base_blue = vec3(0.2, 0.35, 1.0) * smoothstep(0.22, 0.05, p.y) * 0.8;
	vec3 color = mix(outer, inner, core) * shape + base_blue * shape;
	ALBEDO = color * intensity * 2.2;
	ALPHA = shape * intensity;
}
