#include <flutter/runtime_effect.glsl>

uniform float uTime;
uniform vec2 uSize;
uniform float uTransition;
uniform float uDark;

out vec4 fragColor;

vec3 permute(vec3 x) {
  return mod(((x * 34.0) + 1.0) * x, 289.0);
}

float snoise(vec2 v) {
  const vec4 C = vec4(
    0.211324865405187,
    0.366025403784439,
    -0.577350269189626,
    0.024390243902439
  );
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = x0.x > x0.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(
    permute(i.y + vec3(0.0, i1.y, 1.0))
    + i.x + vec3(0.0, i1.x, 1.0)
  );
  vec3 m = max(
    0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)),
    0.0
  );
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float transition = clamp(uTransition, 0.0, 1.0);
  float noise = snoise(uv * 3.2 + vec2(uTime * 0.08, -uTime * 0.05));
  float flow = snoise(uv * 5.0 - vec2(uTime * 0.14, uTime * 0.09));
  float wave = sin(uv.x * 8.0 + uv.y * 5.0 + uTime * 1.4 + noise * 2.0);
  float edge = uv.x + wave * 0.12 * (0.35 + transition * 0.65);
  float reveal = smoothstep(
    0.10 + transition * 0.72,
    0.42 + transition * 0.72,
    edge
  );

  vec3 surface = mix(vec3(0.976, 0.976, 0.976), vec3(0.055, 0.055, 0.055), uDark);
  vec3 accent = mix(vec3(0.831, 0.639, 0.451), vec3(0.180, 0.105, 0.045), uDark);
  vec3 deep = mix(vec3(0.510, 0.333, 0.149), vec3(0.070, 0.035, 0.012), uDark);
  vec3 color = mix(accent, surface, reveal);
  color = mix(color, deep, smoothstep(0.48, 0.95, flow) * 0.22);

  float sheen = smoothstep(0.55, 0.9, snoise(uv * 10.0 + uTime * 0.3));
  color += sheen * 0.035;
  fragColor = vec4(color, 1.0);
}
