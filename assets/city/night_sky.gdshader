shader_type sky;

float hash21(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(cell),hash21(cell+vec2(1,0)),f.x),
		mix(hash21(cell+vec2(0,1)),hash21(cell+vec2(1,1)),f.x),f.y);
}

void sky() {
	float height = max(EYEDIR.y,0.0);
	vec3 horizon = vec3(.17,.115,.25);
	vec3 zenith = vec3(.012,.025,.085);
	vec3 color = mix(horizon,zenith,smoothstep(0.0,.73,height));
	vec2 cloud_uv = EYEDIR.xz/max(.13,height)*2.2;
	float clouds = noise(cloud_uv)*.66+noise(cloud_uv*2.6)*.24+noise(cloud_uv*6.0)*.10;
	color += vec3(.115,.095,.17)*smoothstep(.49,.71,clouds)*smoothstep(.045,.24,height);
	vec2 stars = SKY_COORDS*vec2(460.0,230.0);
	float star = (1.0-smoothstep(.035,.15,length(fract(stars)-.5)))*step(.986,hash21(floor(stars)));
	color += vec3(.65,.76,1.0)*star*smoothstep(.06,.40,height)*(1.0-smoothstep(.48,.73,clouds));
	float moon = distance(EYEDIR,normalize(vec3(-.79,.46,.36)));
	color += vec3(.19,.23,.38)*exp(-moon*19.0);
	color += vec3(.95,.94,1.0)*(1.0-smoothstep(.024,.026,moon));
	COLOR = mix(vec3(.032,.025,.059),color,smoothstep(-.14,.015,EYEDIR.y));
}
