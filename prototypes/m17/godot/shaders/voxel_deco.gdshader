shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, UV2.x + 0.5));
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
