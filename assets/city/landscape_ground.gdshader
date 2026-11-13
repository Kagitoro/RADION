shader_type spatial;

uniform sampler2D grass : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 grass_color : source_color = vec4(0.39216, 0.46275, 0.31373, 1.0);
uniform vec4 subway_opening;
varying vec2 ground_position;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	if (all(greaterThan(ground_position, subway_opening.xy)) &&
		all(lessThan(ground_position, subway_opening.zw))) {
		discard;
	}
	ALBEDO = texture(grass, UV * 7.0).rgb * grass_color.rgb;
	ROUGHNESS = 1.0;
}
