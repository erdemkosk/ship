shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Low-res bake of the rain field. Pane space matches glass.gdshader: UV 0–1
// covers ±2.2 m by ±1.0 m, which is every wheelhouse pane. Godot's shader
// baker does not help here — that is compile-ahead, not "stop shading
// every windscreen pixel". This pass is a few hundred thousand pixels,
// a handful of times a second, instead of the whole view at 60.

#include "res://shaders/glass_rain.gdshaderinc"

uniform float rain : hint_range(0.0, 1.0) = 0.0;

const vec2 PANE_SPAN = vec2(4.4, 2.0);

void fragment() {
	vec2 pane = (UV - vec2(0.5)) * PANE_SPAN;
	COLOR = rain_cover(pane, rain, TIME);
}
