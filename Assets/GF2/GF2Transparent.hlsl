// ubertrans 专用出口；普通颜色与 MRT 共用游戏着色逻辑及 Unity 实时光照。
#ifndef GF2_TRANSPARENT_OUTPUT
#define GF2_TRANSPARENT_OUTPUT
#include "GF2TransparentLighting.hlsl"
#if defined(GF_TRANSPARENT)

float4 GFTransparentColorFragment(GFVaryings i, FRONT_FACE_TYPE face:FRONT_FACE_SEMANTIC):SV_Target0 {
    UNITY_SETUP_INSTANCE_ID(i);
    // 避免 MRT Feature 与 URP UniversalForward 重复叠加同一层透明。
    clip(0.5-_GFTransparentMRT);
    return GFTransparentShade(i,IS_FRONT_VFACE(face,true,false));
}

struct GFTransparentTargets {
    float4 color:SV_Target0;
    float4 normalFlag:SV_Target1;
};

GFTransparentTargets GFTransparentMRTFragment(GFVaryings i, FRONT_FACE_TYPE face:FRONT_FACE_SEMANTIC) {
    UNITY_SETUP_INSTANCE_ID(i);
    clip(_GFTransparentMRT-0.5);
    GFTransparentTargets o;
    bool front=IS_FRONT_VFACE(face,true,false);
    o.color=GFTransparentShade(i,front);
    // EID2705：RT1 编码几何法线，不是法线贴图扰动后的 N。
    float3 n=normalize(i.normalWS)*(front?1:-1);
    n/=max(dot(abs(n),1.0.xxx),1e-6);
    float2 fold=saturate(-n.z)*(float2(n.x>=0?1:-1,n.y>=0?1:-1));
    o.normalFlag=float4((n.xy+fold)*0.5+0.5,0.498,0.5);
    // ColorMask RGB 1 保留目的 A；不伪造运动向量或游戏历史权重预写。
    return o;
}
#endif
#endif
