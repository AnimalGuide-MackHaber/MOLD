#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D texture;
uniform vec2 texOffset;
uniform float diffuseRate;
uniform float decayFactor;

varying vec4 vertTexCoord;

void main() {
  vec2 uv = vertTexCoord.st;
  vec2 off = texOffset;

  // Toroidal wrap using fract
  vec4 sTL = texture2D(texture, fract(uv + vec2(-off.x, -off.y)));
  vec4 sTC = texture2D(texture, fract(uv + vec2( 0.0,   -off.y)));
  vec4 sTR = texture2D(texture, fract(uv + vec2( off.x, -off.y)));

  vec4 sML = texture2D(texture, fract(uv + vec2(-off.x,  0.0)));
  vec4 sMC = texture2D(texture, uv);
  vec4 sMR = texture2D(texture, fract(uv + vec2( off.x,  0.0)));

  vec4 sBL = texture2D(texture, fract(uv + vec2(-off.x,  off.y)));
  vec4 sBC = texture2D(texture, fract(uv + vec2( 0.0,    off.y)));
  vec4 sBR = texture2D(texture, fract(uv + vec2( off.x,  off.y)));

  vec4 sum = sTL + sTC + sTR + sML + sMR + sBL + sBC + sBR;
  
  vec4 result = (sMC * (1.0 - diffuseRate) + sum * (0.125 * diffuseRate)) * decayFactor;
  
  // Cutoff to clear ghostly floating point trails
  if (result.r < 0.005) result.r = 0.0;
  
  gl_FragColor = vec4(result.r, 0.0, 0.0, 1.0);
}
