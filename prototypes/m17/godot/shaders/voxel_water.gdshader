shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 water_tint : source_color = vec4(0.20, 0.44, 0.78, 1.0);
uniform float frame_rate = 3.0;
uniform float frames = 8.0;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.60;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.90;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cycle = TIME * frame_rate;
	float frame_a = mod(floor(cycle), frames);
	float frame_b = mod(frame_a + 1.0, frames);
	float blend = fract(cycle);
	vec4 tex_a = texture(atlas, vec3(UV, UV2.x + frame_a));
	vec4 tex_b = texture(atlas, vec3(UV, UV2.x + frame_b));
	vec4 tex = mix(tex_a, tex_b, blend);

	// Gentle geometric ripple so the surface is not a perfectly flat plane.
	float ripple = sin(world_position.x * 0.9 + TIME * 1.3) * cos(world_position.z * 1.1 - TIME * 1.1);
	vec3 tint = water_tint.rgb * (1.0 + 0.06 * ripple);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tex.rgb * COLOR.rgb * tint;
	ROUGHNESS = mix(0.05, 0.22, fresnel);
	METALLIC = 0.06;
	SPECULAR = 0.85;
	ALPHA = mix(shallow_alpha, deep_alpha, fresnel) * tex.a;
}
