shader_type canvas_item;

uniform bool alt_palette = false;
uniform vec3 alt_tint = vec3(0.35, 0.65, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color = vec3(1.0, 1.0, 1.0);
uniform float aura_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 aura_color = vec3(1.0, 0.72, 0.22);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float pulse = 0.78 + 0.22 * sin(TIME * 14.0 - UV.y * 28.0);

	if (tex.a < 0.05) {
		// Animated silhouette-hugging energy halo outside the sprite edge (DBFZ / Tekken Rage style)!
		if (aura_intensity > 0.01) {
			float n1 = texture(TEXTURE, UV + vec2(px.x * 1.5, 0.0)).a;
			float n2 = texture(TEXTURE, UV - vec2(px.x * 1.5, 0.0)).a;
			float n3 = texture(TEXTURE, UV + vec2(0.0, px.y * 1.5)).a;
			float n4 = texture(TEXTURE, UV - vec2(0.0, px.y * 1.5)).a;
			float n5 = texture(TEXTURE, UV + vec2(px.x * 2.5, px.y * 2.0)).a;
			float n6 = texture(TEXTURE, UV + vec2(-px.x * 2.5, px.y * 2.0)).a;
			float edge = clamp((n1 + n2 + n3 + n4) * 0.45 + (n5 + n6) * 0.28, 0.0, 1.0);
			float wave = 0.55 + 0.45 * sin(TIME * 18.0 + UV.y * 42.0 + UV.x * 16.0);
			float halo_a = edge * aura_intensity * wave * 0.82;
			if (halo_a > 0.03) {
				vec3 glow = mix(aura_color, vec3(1.0, 0.96, 0.82), edge * 0.5);
				COLOR = vec4(glow, halo_a);
			} else {
				discard;
			}
		} else {
			discard;
		}
	} else {
		vec3 rgb = tex.rgb;
		if (alt_palette) {
			float luma = dot(rgb, vec3(0.299, 0.587, 0.114));
			float sat = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b));
			if (sat > 0.14 && luma > 0.12) {
				vec3 tinted = mix(rgb, alt_tint * (luma * 1.35 + 0.15), 0.52);
				rgb = clamp(tinted, 0.0, 1.0);
			}
		}

		// Inner fiery rim lighting on silhouette edges when Rage / Ultimate Ready / Active Ult!
		if (aura_intensity > 0.01) {
			float a_l = texture(TEXTURE, UV - vec2(px.x * 1.5, 0.0)).a;
			float a_r = texture(TEXTURE, UV + vec2(px.x * 1.5, 0.0)).a;
			float a_u = texture(TEXTURE, UV - vec2(0.0, px.y * 1.5)).a;
			float a_d = texture(TEXTURE, UV + vec2(0.0, px.y * 1.5)).a;
			float rim = clamp(1.0 - min(min(a_l, a_r), min(a_u, a_d)), 0.0, 1.0);
			rgb = mix(rgb, mix(aura_color, vec3(1.0, 0.98, 0.88), 0.35), rim * aura_intensity * pulse * 0.65);
			rgb += aura_color * (aura_intensity * 0.12 * pulse);
		}

		rgb = mix(rgb, flash_color, flash_amount);
		COLOR = vec4(clamp(rgb, 0.0, 1.0), tex.a);
	}
}
