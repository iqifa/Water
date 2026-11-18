#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
// #include "GF2MaterialBuffer.hlsl"

float _AnisotropicGXX;

float3 GFArtisticLighting(float3 normal,float3 bitangent,float3 halfangle,float roughness)
{
    float3 tangent=cross(normalize(bitangent),normal);
    float3 fragbit=cross(normal,tangent);
    
    
    float a=roughness*roughness;
    float ax=max(a)
    
    
    
}