shader_type sky;

// Procedural sky for VoxelWorld.  It replaces the flat procedural gradient with
// a layered gradient, a warm horizon at dawn/dusk, a sun/moon disc from the
// scene's directional light, slow cloud cover and sparse stars at night.
// Every input is a uniform so the day/night clock fully controls the look.

uniform vec3 sky_top : source_color = vec3(0.18, 0.48, 0.77);
uniform vec3 sky_horizon : source_color = vec3(0.81, 0.89, 0.91);
uniform vec3 ground_bottom : source_color = vec3(0.30, 0.38, 0.42);
uniform vec3 ground_horizon : source_color = vec3(0.78, 0.84, 0.86);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.52, 0.26);
uniform float sunset_amount : hint_range(0.0, 1.0) = 0.0;
uniform float day_amount : hint_range(0.0, 1.0) = 1.0;
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_speed = 0.0035;
uniform float cloud_scale = 0.32;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;

	// Base gradient: horizon colour at the horizon, top colour at the zenith.
	vec3 col = mix(sky_horizon, sky_top, smoothstep(-0.02, 0.35, h));

	// Warm the horizon band in the sun's half of the sky at dawn/dusk.
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	vec2 flat_dir = normalize(vec2(dir.x, dir.z) + vec2(0.0001));
	vec2 flat_sun = normalize(vec2(sun_dir.x, sun_dir.z) + vec2(0.0001));
	float azimuth = max(dot(flat_dir, flat_sun), 0.0);
	float band = 1.0 - smoothstep(0.0, 0.38, abs(h));
	float warmth = clamp(sunset_amount * band * (0.35 + 0.65 * azimuth), 0.0, 0.9);
	col = mix(col, sunset_color, warmth);

	// Sun / moon disc and a soft glow around the light.
	float sun_dot = max(dot(dir, sun_dir), 0.0);
	col += LIGHT0_COLOR * (pow(sun_dot, 1400.0) * 2.4 + pow(sun_dot, 14.0) * 0.10 * day_amount);

	// Ground half of the sky.
	if (h < 0.0) {
		float g = smoothstep(0.0, -0.45, h);
		col = mix(mix(ground_horizon, ground_bottom, g), sky_horizon, 0.12);
	}

	// Cloud layer, faded out at the horizon so it never becomes a hard band.
	if (h > 0.004) {
		vec2 cloud_uv = dir.xz / max(h, 0.09) * cloud_scale;
		float clouds = fbm(cloud_uv + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.6));
		float cover = smoothstep(0.42, 0.74, clouds) * smoothstep(0.004, 0.20, h);
		vec3 cloud_col = mix(sky_horizon, vec3(1.0), 0.45) * (0.46 + 0.54 * day_amount);
		col = mix(col, cloud_col, cover * cloud_amount);
	}

	// Stars: one per quantised direction cell at night.
	if (h > 0.0 && star_amount > 0.001) {
		vec2 sphere = vec2(atan(dir.z, dir.x), asin(clamp(dir.y, -1.0, 1.0))) * 42.0;
		vec2 cell = floor(sphere);
		vec2 f = fract(sphere);
		float rnd = hash21(cell);
		vec2 star_pos = fract(vec2(rnd * 13.13, rnd * 7.37)) * 0.8 + 0.1;
		float star = smoothstep(0.055, 0.0, distance(f, star_pos)) * step(0.90, rnd);
		col += vec3(0.90, 0.95, 1.0) * star * star_amount;
	}

	COLOR = col;
}
