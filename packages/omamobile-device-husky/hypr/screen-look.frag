#version 300 es
// SPDX-License-Identifier: MIT
// Pixel 8 Pro screen look stopgap (#537): pow(rgb, 1.55) then x0.88, from
// blind rounds by eye on one panel: two gamma rounds (1.5-1.6 won) and one
// gain round, after a first pass with the names showing. The cause of the
// flat mid-tones is unknown.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;
void main() {
    vec4 c = texture(tex, v_texcoord);
    vec3 rgb = pow(max(c.rgb, vec3(0.0)), vec3(1.55));
    rgb *= 0.88;
    fragColor = vec4(rgb, c.a);
}
