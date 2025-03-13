#include <cube_uv_reflection_fragment>

varying vec2 vUv;
varying vec3 vWolrdPosition;
varying vec3 vWorldNormal;

uniform sampler2D map;
uniform sampler2D normalMap;
uniform sampler2D roughnessMap;
uniform sampler2D metalnessMap;
uniform sampler2D aoMap;
uniform sampler2D emisssiveMap;
uniform sampler2D envMap;
uniform float intensity;

#define PI 3.14159265359

#define RECIPROCAL_PI 0.3183098861837907

#define SPECCUBE_LOD_STEPS 6

#define saturate( a ) clamp( a, 0.0, 1.0 )

float inverseLerp(float v, float minValue, float maxValue) {
  return (v - minValue) / (maxValue - minValue);
}

float remap(float v, float inMin, float inMax, float outMin, float outMax) {
  float t = inverseLerp(v, inMin, inMax);
  return mix(outMin, outMax, t);
}

mat3 getTangentFrame(vec3 eye_pos, vec3 surf_norm, vec2 uv) {

  vec3 q0 = dFdx(eye_pos.xyz);
  vec3 q1 = dFdy(eye_pos.xyz);
  vec2 st0 = dFdx(uv.st);
  vec2 st1 = dFdy(uv.st);

  vec3 N = surf_norm; // normalized

  vec3 q1perp = cross(q1, N);
  vec3 q0perp = cross(N, q0);

  vec3 T = q1perp * st0.x + q0perp * st1.x;
  vec3 B = q1perp * st0.y + q0perp * st1.y;

  float det = max(dot(T, T), dot(B, B));
  float scale = (det == 0.0) ? 0.0 : inversesqrt(det);

  return mat3(T * scale, B * scale, N);

}

vec3 UnpackNormal(sampler2D tex, vec2 uv) {
  vec4 normalTex = texture2D(tex, uv);
  vec3 normalTs = normalTex.rgb * 2.0 - 1.0;
  return normalTs;
}

vec3 DisneyDiffuse(float NdotV, float NdotL, float LdotH, float roughness, vec3 baseColor) {
  float fd90 = 0.5 + 2. * LdotH * LdotH * roughness;
  // Two schlick fresnel term
  float lightScatter = (1. + (fd90 - .1) * pow(1. - NdotL, 5.));
  float viewScatter = (1. + (fd90 - 1.) * pow(1. - NdotV, 5.));
  return baseColor * (lightScatter * viewScatter);
}
//D 法线分布函数
float D_GGX_TR(float NdotH, float roughness) {
  float a2 = roughness * roughness;
  float NdotH2 = NdotH * NdotH;
  float denom = (NdotH2 * (a2 - 1.0) + 1.0);
  denom = PI * denom * denom;
  denom = max(denom, 0.0000001); //防止分母为0
  return a2 / denom;
}

//F 菲涅尔函数
vec3 F_FrenelSchlick(float HdotV, vec3 F0) {
  return F0 + (1. - F0) * pow(1. - HdotV, 5.0);
}

  // 计算菲涅耳效应时纳入表面粗糙度(roughness)
vec3 FresnelSchlickRoughness(float NdotV, vec3 F0, float roughness) {
  vec3 oneMinusRoughness = vec3(1.0 - roughness);
  return F0 + (max(oneMinusRoughness, F0) - F0) * pow(1.0 - NdotV, 5.0);
}

// G 几何遮蔽函数
float GeometrySchlickGGX(float NdotV, float roughness) {
  float a = (roughness + 1.0) / 2.;
  float k = a * a / 4.;
  float nom = NdotV;
  float denom = NdotV * (1.0 - k) + k;
  denom = max(denom, 0.0000001); //防止分母为0
  return nom / denom;
}
float G_GeometrySmith(float NdotV, float NdotL, float roughness) {
  NdotV = max(NdotV, 0.0);
  NdotL = max(NdotL, 0.0);
  float ggx1 = GeometrySchlickGGX(NdotV, roughness);
  float ggx2 = GeometrySchlickGGX(NdotL, roughness);
  return ggx1 * ggx2;
}

vec2 EnvBRDFApprox(  float Roughness, float NoV )
{
    const vec4 c0 = vec4(-1., -0.0275, -0.573, 0.0229 );
    const vec4 c1 = vec4(1., 0.0425, 1.0417, -0.0417);
    vec4 r = Roughness * c0 + c1;
    float a004 = min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
    vec2 AB = vec2( -1.0417, 1.0417 ) * a004 + r.zw;
    return AB;
}

float PerceptualRoughnessToMipmapLevel(float perceptualRoughness, int maxMipLevel) {
  perceptualRoughness = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness);
  return perceptualRoughness * float(maxMipLevel);
}

float PerceptualRoughnessToMipmapLevel(float perceptualRoughness) {
  return PerceptualRoughnessToMipmapLevel(perceptualRoughness, SPECCUBE_LOD_STEPS);
}

float PerceptualRoughnessToRoughness(float perceptualRoughness) {
  return perceptualRoughness * perceptualRoughness;
}

void main() {

  mat3 tbn = getTangentFrame(vWolrdPosition, normalize(vWorldNormal), vUv);

  vec3 N = UnpackNormal(normalMap, vUv);

  N = tbn * N;

  vec3 L = vec3(0., 0., 0.);
  vec3 V = normalize(cameraPosition - vWolrdPosition);
  vec3 H = normalize(L + V);

  float NdotL = max(dot(N, L), 0.0);
  float NdotV = max(dot(N, V), 0.0);
  float NdotH = max(dot(N, H), 0.0);
  float HdotV = max(dot(H, V), 0.0);
  float LdotH = max(dot(L, H), 0.0);

  float perceptualRoughness = texture2D(roughnessMap, vUv).g;

  float roughness = max(PerceptualRoughnessToRoughness(perceptualRoughness), 0.002);

  float metalness = texture2D(metalnessMap, vUv).b;

  vec3 albedo = texture2D(map, vUv).rgb;

  vec3 F0 = mix(vec3(0.04), albedo, metalness);

  float ao = texture2D(aoMap, vUv).r;

  /* Direct Light */

  // Diffuse BRDF
  vec3 diffuseBRDF = DisneyDiffuse(NdotV, NdotL, LdotH, perceptualRoughness, albedo) * NdotL;

  // Specular BRDF
  float D = D_GGX_TR(NdotH, roughness);
  vec3 F = F_FrenelSchlick(HdotV, F0);
  float G = G_GeometrySmith(NdotV, NdotL, roughness);

  // Cook-Torrance BRDF = (D * G * F) / (4 * NdotL * NdotV)
  vec3 DGF = D * G * F;
  float denominator = 4.0 * NdotL * NdotV + 0.00001;
  vec3 specularBRDF = DGF / denominator;

  vec3 lightColor = vec3(1.);

  // 反射方程
  vec3 ks = F;
  vec3 kd = 1. - ks;
  kd *= (1. - metalness);
  vec3 directLight = (diffuseBRDF * kd + specularBRDF) * NdotL * lightColor;

  /* Indirect Light */
  vec3 ks_indirect = FresnelSchlickRoughness(NdotV, F0, roughness);
  vec3 kd_indirect = 1.0 - ks_indirect;
  kd_indirect *= (1. - metalness);

  vec3 diffuseIndirect = vec3(0.);
  diffuseIndirect = kd_indirect * albedo * RECIPROCAL_PI * intensity;

  vec3 R = reflect(-V, N);

  vec3 prefilteredColor = vec3(0.);

  // prefilteredColor = textureLod(envMap, R, PerceptualRoughnessToMipmapLevel(roughness)).rgb;

  prefilteredColor = textureCubeUV(envMap, R, perceptualRoughness).rgb;

  vec2 envBRDF = EnvBRDFApprox(roughness,NdotV);

  vec3 specularIndirect = prefilteredColor * (ks_indirect * envBRDF.x + envBRDF.y);

  vec3 indirectLight = (diffuseIndirect + specularIndirect) * ao;

  vec3 resColor = directLight + indirectLight;

  vec3 emissive = texture2D(emisssiveMap, vUv).rgb;

  resColor += emissive;

  gl_FragColor.rgb = pow(resColor, vec3(1. / 2.2));
  // gl_FragColor.rgb = vec3(PerceptualRoughnessToMipmapLevel(roughness));
  gl_FragColor.a = 1.;
}