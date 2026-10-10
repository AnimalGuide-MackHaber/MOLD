#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D texture;
uniform float visualSharpness;
uniform int paletteIdx;
uniform int gradientColorCount;

varying vec4 vertTexCoord;

vec3 getPaletteColor(int idx, vec3 p0, vec3 p1, vec3 p2, vec3 p3, vec3 p4, vec3 p5, vec3 p6, vec3 p7) {
  if (idx <= 0) return p0;
  if (idx == 1) return p1;
  if (idx == 2) return p2;
  if (idx == 3) return p3;
  if (idx == 4) return p4;
  if (idx == 5) return p5;
  if (idx == 6) return p6;
  return p7;
}

void main() {
  vec2 uv = vertTexCoord.st;
  vec4 valColor = texture2D(texture, uv);
  float val = valColor.r * 255.0; // scale up to our original 0-255 range

  vec3 p0, p1, p2, p3, p4, p5, p6, p7;

  if (paletteIdx == 0) { // Yellow (Zorn / Physarum)
    p0 = vec3(115.0, 65.0, 8.0) / 255.0;
    p1 = vec3(140.0, 82.0, 8.0) / 255.0;
    p2 = vec3(161.0, 98.0, 7.0) / 255.0;
    p3 = vec3(188.0, 122.0, 8.0) / 255.0;
    p4 = vec3(212.0, 150.0, 8.0) / 255.0;
    p5 = vec3(234.0, 179.0, 8.0) / 255.0;
    p6 = vec3(248.0, 212.0, 56.0) / 255.0;
    p7 = vec3(254.0, 240.0, 138.0) / 255.0;
  } else if (paletteIdx == 1) { // Mono (Grayscale)
    p0 = vec3(45.0, 45.0, 52.0) / 255.0;
    p1 = vec3(70.0, 70.0, 78.0) / 255.0;
    p2 = vec3(95.0, 95.0, 105.0) / 255.0;
    p3 = vec3(122.0, 122.0, 132.0) / 255.0;
    p4 = vec3(148.0, 148.0, 158.0) / 255.0;
    p5 = vec3(175.0, 175.0, 185.0) / 255.0;
    p6 = vec3(210.0, 210.0, 218.0) / 255.0;
    p7 = vec3(245.0, 245.0, 250.0) / 255.0;
  } else { // Cyan (Bio Cyan)
    p0 = vec3(4.0, 52.0, 75.0) / 255.0;
    p1 = vec3(5.0, 85.0, 118.0) / 255.0;
    p2 = vec3(6.0, 120.0, 160.0) / 255.0;
    p3 = vec3(14.0, 152.0, 186.0) / 255.0;
    p4 = vec3(22.0, 182.0, 212.0) / 255.0;
    p5 = vec3(34.0, 211.0, 238.0) / 255.0;
    p6 = vec3(120.0, 232.0, 246.0) / 255.0;
    p7 = vec3(207.0, 250.0, 254.0) / 255.0;
  }

  vec3 cSharp = p7;
  float moldCutoff = mix(0.8, 0.4, visualSharpness);

  if (val < moldCutoff) {
    gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
    return;
  }

  int count = gradientColorCount;
  if (count < 1) count = 1;
  if (count > 8) count = 8;

  int targetPalIdx;
  if (count <= 1) {
    targetPalIdx = 7;
  } else {
    float u = clamp((log(val) - log(moldCutoff)) / (log(36.0) - log(moldCutoff)), 0.0, 1.0);
    int band = int(floor(u * float(count)));
    if (band >= count) band = count - 1;
    targetPalIdx = int(floor(float(band) * 7.0 / float(count - 1) + 0.5));
  }

  vec3 chosenColor = getPaletteColor(targetPalIdx, p0, p1, p2, p3, p4, p5, p6, p7);
  vec3 outColor = mix(chosenColor, cSharp, visualSharpness);

  gl_FragColor = vec4(outColor, 1.0);
}
