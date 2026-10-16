shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, UV2.x + 0.5));
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.75;
	ALPHA = tex.a * opacity;
}
