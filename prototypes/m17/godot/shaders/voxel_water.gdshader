shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, diffuse_burley, specular_schlick_ggx;

// Water: a transparent surface whose colour and opacity follow the *scene*
// depth behind it, so the shoreline is clear and deep water absorbs the light.
// Surface normals come from a small world-space wave field instead of a tiled
// texture, which avoids the checkerboard animation of the earlier shader.
uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 water_tint : source_color = vec4(0.11, 0.31, 0.58, 1.0);
uniform float frame_rate = 3.0;
uniform float frames = 8.0;
uniform float wave_strength : hint_range(0.0, 0.2) = 0.045;
uniform float alpha_shore : hint_range(0.0, 1.0) = 0.52;
uniform float alpha_deep : hint_range(0.0, 1.0) = 0.985;
// A larger depth scale softens the one-block seabed steps that otherwise read
// as hard contour stripes through the transparent surface.
uniform float depth_scale = 7.0;

varying vec3 world_position;

float wave(vec2 p, float t) {
	return sin(p.x * 0.70 + t * 1.10) * 0.5
		+ sin(p.y * 0.90 - t * 0.90) * 0.5
		+ sin((p.x + p.y) * 0.45 + t * 0.60) * 0.35;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fine animated detail from the atlas.  The layer coordinate is sampled at
	// the exact integer frame (the M17 corruption regression contract).
	float cycle = TIME * frame_rate;
	float frame_a = mod(floor(cycle), frames);
	float frame_b = mod(frame_a + 1.0, frames);
	float blend = fract(cycle);
	vec4 tex_a = texture(atlas, vec3(UV, UV2.x + frame_a));
	vec4 tex_b = texture(atlas, vec3(UV, UV2.x + frame_b));
	vec4 tex = mix(tex_a, tex_b, blend);

	// World-space wave normal (expressed in view space for Godot).
	float e = 0.35;
	float h = wave(world_position.xz, TIME);
	float hx = wave(world_position.xz + vec2(e, 0.0), TIME);
	float hz = wave(world_position.xz + vec2(0.0, e), TIME);
	vec3 wave_normal = normalize(vec3((h - hx) / e * wave_strength, 1.0, (h - hz) / e * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);

	// Scene depth behind this fragment (the opaque prepass wrote it).
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, raw_depth), 1.0);
	scene_view.xyz /= scene_view.w;
	float thickness = max(0.0, (-scene_view.z) - (-VERTEX.z));
	float depth_t = clamp(thickness / depth_scale, 0.0, 1.0);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	// The animated atlas only adds a subtle surface grain; the wave normals and
	// depth tint carry the look, so the blocky texture pattern stays invisible.
	vec3 water = water_tint.rgb * (0.975 + 0.025 * tex.rgb);
	ALBEDO = water * mix(1.00, 0.90, depth_t);
	ROUGHNESS = mix(0.06, 0.24, fresnel);
	METALLIC = 0.0;
	SPECULAR = 0.78;

	// A bright, translucent band where the water is very thin reads as a
	// shoreline without a separate foam texture.
	float foam = 1.0 - smoothstep(0.0, 0.9, thickness);
	ALBEDO += vec3(0.03, 0.05, 0.055) * foam;
	float alpha = mix(alpha_shore, alpha_deep, depth_t);
	ALPHA = clamp(max(alpha, foam * 0.34) * mix(0.92, 1.0, tex.a), 0.0, 1.0);
}
