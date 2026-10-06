shader_type canvas_item;
// A face on a mission briefing card (Briefing): the user's portrait on a little CRT tinted
// teal like the HUD (user: "The avatars should have a crtv tinted effect over them", "Teal like the
// HUD"). The picture's brightness is mapped onto a teal ramp (near black, the HUD's teal, near
// white), drawn on a coarse raster with a scanline every other screen pixel, a soft glow round the
// bright parts, grain, a faint bar of hum rolling down, a slightly curved screen and dark corners.
// The speaker's face is lit, the listener's dimmed (lit). It switches on like an old CRT (power
// 0 -> 1: a dot, a line across, the line opening into the picture, over-bright then settling), and
// a burst of static covers it while the caller changes (static_amt). The card's sides lean like the
// rest of the UI (slant): outside them it's clear.

// The part of the texture drawn (its UV origin and size): the picture is cropped to the card.
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float lit : hint_range(0.0, 1.0) = 1.0;
uniform float power : hint_range(0.0, 1.0) = 1.0;
uniform float static_amt : hint_range(0.0, 1.0) = 0.0;
// 0..1 while they talk (up with each letter): the picture lifts a little with the voice.
uniform float talk : hint_range(0.0, 1.0) = 0.0;
// How far the card's top sits right of its bottom, as a part of its width (0: a plain box).
uniform float slant : hint_range(0.0, 0.5) = 0.0;
// The ramp: UiKit's PANEL_SOLID, TEAL, and a hot near white.
uniform vec3 dark = vec3(0.012, 0.045, 0.05);
uniform vec3 teal = vec3(0.384, 0.839, 0.753);
uniform vec3 hot = vec3(0.86, 1.0, 0.95);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 ramp(float l) {
	return l < 0.62 ? mix(dark, teal, l / 0.62) : mix(teal, hot, (l - 0.62) / 0.38);
}

void fragment() {
	// Where this pixel is in the frame (0..1), bent a little like a curved screen.
	vec2 box = (UV - region.xy) / region.zw;
	bool cut = box.x < slant * (1.0 - box.y) || box.x > 1.0 - slant * box.y;  // (outside the card)
	vec2 c = box - 0.5;
	c *= 1.0 + dot(c, c) * 0.09;
	// The switch-on: a line grows across (first third), then opens up and down.
	float across = smoothstep(0.0, 0.3, power);
	float open = smoothstep(0.25, 0.7, power);
	float height = mix(0.03, 1.0, open);
	bool on = abs(c.x) <= across * 0.5 && abs(c.y) <= height * 0.5 && abs(c.x) < 0.5 && abs(c.y) < 0.5;
	if (!on) {
		COLOR = vec4(dark * 0.35, 1.0);
	} else {
		// The picture squashed into the opening band, the way a CRT's picture opens up.
		vec2 b = vec2(0.5 + c.x, 0.5 + c.y / height);
		// The odd line tears sideways a little (many, in the static).
		float row = floor(b.y * 50.0);
		float tear = hash(vec2(row, floor(TIME * 12.0)));
		b.x += step(0.965 - static_amt * 0.5, tear) * (tear - 0.5) * (0.025 + static_amt * 0.14);
		vec2 uv = region.xy + clamp(b, 0.0, 1.0) * region.zw;
		// A soft box filter (the picture is shrunk about 3x), and a wider one for the glow.
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec3 s = texture(TEXTURE, uv).rgb * 0.36;
		s += texture(TEXTURE, uv + vec2(px.x, px.y) * 1.1).rgb * 0.16;
		s += texture(TEXTURE, uv + vec2(-px.x, px.y) * 1.1).rgb * 0.16;
		s += texture(TEXTURE, uv + vec2(px.x, -px.y) * 1.1).rgb * 0.16;
		s += texture(TEXTURE, uv + vec2(-px.x, -px.y) * 1.1).rgb * 0.16;
		float g = 0.0;
		g += luma(texture(TEXTURE, uv + vec2(4.0, 0.0) * px).rgb);
		g += luma(texture(TEXTURE, uv + vec2(-4.0, 0.0) * px).rgb);
		g += luma(texture(TEXTURE, uv + vec2(0.0, 4.0) * px).rgb);
		g += luma(texture(TEXTURE, uv + vec2(0.0, -4.0) * px).rgb);
		g *= 0.25;
		float l = luma(s);
		l = pow(clamp(l * 1.3, 0.0, 1.0), 0.85) * (1.0 + talk * 0.08);
		vec3 col = ramp(clamp(l, 0.0, 1.0));
		col += teal * max(g - 0.42, 0.0) * 0.9;  // glow round the bright parts
		col *= 0.66 + 0.34 * step(0.5, fract(FRAGCOORD.y * 0.5));  // a scanline every other pixel
		col *= 1.0 + 0.07 * smoothstep(0.82, 1.0, sin((box.y - TIME * 0.3) * 6.2832) * 0.5 + 0.5);  // hum bar
		col += (hash(floor(FRAGCOORD.xy) + floor(TIME * 24.0)) - 0.5) * 0.07;  // grain
		col *= 0.985 + 0.015 * sin(TIME * 47.0);  // flicker
		// Static: snow, banded by line, over the picture.
		float snow = hash(floor(FRAGCOORD.xy) * 0.73 + floor(TIME * 30.0) * 1.37);
		float band = 0.55 + 0.45 * hash(vec2(row, floor(TIME * 20.0)));
		vec3 st = mix(dark, hot * 0.9, snow * band);
		col = mix(col, st, static_amt);
		col *= 1.0 - dot(c, c) * 1.25;  // dark corners
		col *= mix(0.3, 1.0, lit);  // the listener's face dimmed
		// Over-bright as it warms up, settling; the thin line itself near white.
		float warm = 1.0 + 1.3 * (1.0 - smoothstep(0.5, 1.0, power));
		col = mix(hot, col * warm, open);
		COLOR = vec4(col, 1.0);
	}
	if (cut) {
		COLOR = vec4(0.0);
	}
}
