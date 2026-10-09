#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D texture;
uniform float visualSharpness;
uniform int paletteIdx;

varying vec4 vertTexCoord;

void main() {
  vec2 uv = vertTexCoord.st;
  vec4 valColor = texture2D(texture, uv);
  float val = valColor.r * 255.0; // scale up to our original 0-255 range

  vec3 cBg, cAtrophy, cMargin, cSheet, cArtery;

  if (paletteIdx == 0) { // Yellow
    cBg = vec3(6.0, 7.0, 10.0) / 255.0;
    cAtrophy = vec3(115.0, 65.0, 8.0) / 255.0;
    cMargin = vec3(161.0, 98.0, 7.0) / 255.0;
    cSheet = vec3(234.0, 179.0, 8.0) / 255.0;
    cArtery = vec3(254.0, 240.0, 138.0) / 255.0;
  } else if (paletteIdx == 1) { // Mono
    cBg = vec3(6.0, 7.0, 10.0) / 255.0;
    cAtrophy = vec3(45.0, 45.0, 52.0) / 255.0;
    cMargin = vec3(95.0, 95.0, 105.0) / 255.0;
    cSheet = vec3(175.0, 175.0, 185.0) / 255.0;
    cArtery = vec3(245.0, 245.0, 250.0) / 255.0;
  } else { // Cyan
    cBg = vec3(5.0, 8.0, 12.0) / 255.0;
    cAtrophy = vec3(4.0, 52.0, 75.0) / 255.0;
    cMargin = vec3(6.0, 120.0, 160.0) / 255.0;
    cSheet = vec3(34.0, 211.0, 238.0) / 255.0;
    cArtery = vec3(207.0, 250.0, 254.0) / 255.0;
  }

  vec3 cSharp = cArtery;

  float moldCutoff = mix(0.8, 0.4, visualSharpness);
  vec3 cAtrophyActive = mix(cAtrophy, cSharp, visualSharpness);
  vec3 cMarginActive  = mix(cMargin,  cSharp, visualSharpness);
  vec3 cSheetActive   = mix(cSheet,   cSharp, visualSharpness);
  vec3 cArteryActive  = cArtery;

  vec3 outColor;
  float outAlpha = 1.0;

  if (val < moldCutoff) {
    outColor = vec3(0.0);
    outAlpha = 0.0;
  } else if (val < 4.0) {
    outColor = cAtrophyActive;
  } else if (val < 10.0) {
    outColor = cMarginActive;
  } else if (val < 30.0) {
    outColor = cSheetActive;
  } else {
    outColor = cArteryActive;
  }

  gl_FragColor = vec4(outColor, outAlpha);
}
