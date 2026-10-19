shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Cutout voxel surface (leaves, cacti).  Same material model as the opaque
// shader, with an alpha scissor instead of a solid surface.
uniform sampler2DArray atlas : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float macro_strength : hint_range(0.0, 0.4) = 0.10;

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

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, UV2.x));
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float macro = value_noise(world_pos.xz * 0.09) * 0.65 + value_noise(world_pos.xz * 0.31) * 0.35;
	ALBEDO = tex.rgb * COLOR.rgb * (1.0 - macro_strength + 2.0 * macro_strength * macro);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
