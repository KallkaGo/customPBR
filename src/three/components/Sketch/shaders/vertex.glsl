varying vec2 vUv;
varying vec3 vWolrdPosition;
varying vec3 vWorldNormal;

void main() {
  vec4 modelPosition = modelMatrix * vec4(position, 1.0);
  vWolrdPosition = modelPosition.xyz;
  vWorldNormal = (modelMatrix * vec4(normal, 0.0)).xyz;
  gl_Position = projectionMatrix * viewMatrix * modelPosition;
  vUv = uv;
}