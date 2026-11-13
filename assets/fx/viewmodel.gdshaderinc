// Shared body of the first-person viewmodel shaders (hands and held items).
// The vertex stage squeezes depth toward the near plane so hands never clip into walls,
// while keeping their own depth order intact. Lighting comes from the real scene.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.7, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.0;
uniform float sss : hint_range(0.0, 1.0) = 0.0;
// 0..1 range of the depth buffer the viewmodel is squeezed into (near side).
uniform float depth_squeeze = 0.06;

void vertex() {
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Godot 4 uses reversed Z: w is the near plane. Pull every vertex close to it.
	POSITION.z = mix(POSITION.w, POSITION.z, depth_squeeze);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV * uv_scale);
	ALBEDO = albedo.rgb * tex.rgb * COLOR.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	EMISSION = emission.rgb * emission_energy;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	EMISSION += rim_color.rgb * rim * rim_amount * 0.35;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = 0.15;
	SSS_STRENGTH = sss;
#ifdef VIEWMODEL_ALPHA
	ALPHA = albedo.a * tex.a * COLOR.a;
#endif
}
