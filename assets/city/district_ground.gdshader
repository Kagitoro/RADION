shader_type spatial;
render_mode specular_disabled;
uniform sampler2D asphalt : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D pavers : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float club_half_width;
varying vec2 district_position;

void vertex() {
	district_position = VERTEX.xz + vec2(-45.45,-.5);
}

void fragment() {
	vec2 p = district_position;
	if (p.x > -33.60 && p.x < -21.80 && abs(p.y+4.2) < club_half_width) {
		discard;
	}
	float avenue = min(abs(p.x+18.8),abs(p.x+55.3));
	float cross_street = min(abs(p.y+20.7),abs(p.y-21.3));
	bool vertical = avenue < 3.2 && abs(p.y+1.0)<27.5;
	bool horizontal = cross_street < 3.2 && p.x > -58.5 && p.x < -15.6;
	bool parking = p.x > -47.2 && p.x < -31.2 && abs(p.y-14.6) < 2.7;
	vec3 pavement = texture(pavers,p*.44).rgb*vec3(.65,.65,.72);
	vec3 tarmac = texture(asphalt,p*.26).rgb*vec3(.60,.65,.73);
	bool divider = vertical && avenue < .047 && cross_street>3.35 && mod(p.y+33.0,3.0)<1.35;
	divider = divider || (horizontal && cross_street<.047 && avenue>3.35 && mod(p.x+59.0,3.0)<1.35);
	bool crossing = abs(p.x+18.8)<2.95 && abs(p.y)<1.35 && mod(p.x+22.0,.86)<.38;
	bool parking_line = parking && mod(p.x+47.2,4.0)<.075;
	ALBEDO = vertical || horizontal || parking ? tarmac : pavement;
	if (divider || crossing || parking_line) {
		ALBEDO = mix(ALBEDO, vec3(.72,.67,.55),.84);
	}
	ROUGHNESS = .98;
}
