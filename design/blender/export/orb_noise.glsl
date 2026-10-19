// Noise for the eye orb shader. Blender's Noise Texture is Perlin; this is a hash-based value noise with
// smooth interpolation, which gives the same character at the scales the orb uses (wobble at 4x, wave at 1.1x).
// Deterministic, no textures, no derivatives needed. Works under Impeller (no bitwise ops, no integer tricks).

float hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

// value noise, 0..1, smooth (quintic fade like Perlin)
float vnoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float n000 = hash3(i + vec3(0,0,0)), n100 = hash3(i + vec3(1,0,0));
    float n010 = hash3(i + vec3(0,1,0)), n110 = hash3(i + vec3(1,1,0));
    float n001 = hash3(i + vec3(0,0,1)), n101 = hash3(i + vec3(1,0,1));
    float n011 = hash3(i + vec3(0,1,1)), n111 = hash3(i + vec3(1,1,1));
    float x00 = mix(n000, n100, u.x), x10 = mix(n010, n110, u.x);
    float x01 = mix(n001, n101, u.x), x11 = mix(n011, n111, u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

// Wobble: two channels for x and z (Blender used the noise's R and G).
vec2 wobbleNoise(vec2 xz) {
    return vec2(vnoise3(vec3(xz * 4.0, 0.0)), vnoise3(vec3(xz * 4.0, 7.31))) - 0.5;
}

// Wave warp: Blender used 4D noise (x, z, 0; W = wave_t). Fold time into the third axis.
float waveNoise(vec2 xz, float scale, float t) {
    return vnoise3(vec3(xz * scale, t));  // 0..1; subtract 0.5 and multiply by wave_amp
}

// Usage in the eye formula:
//   vec2 n = wobbleNoise(vec2(x, z));  X = x + wobble * n.x;  Z = z + wobble * n.y;
//   float w = (waveNoise(vec2(x, z), wave_scale, wave_t) - 0.5) * wave_amp;
// Value noise is a little softer than Perlin at the same scale; if the wave bands look too tame,
// use wave_scale 1.3 instead of 1.1. Judge against previews_toon/listening_wave_sequence.mp4.
