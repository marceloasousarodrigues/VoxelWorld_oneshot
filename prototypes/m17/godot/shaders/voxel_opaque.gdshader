shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, UV2.x));
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.28;
}
