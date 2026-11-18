// 高级分支：不是用一个通用各向异性高光替代游戏头发。
// 依据：uber 2810/2819；GF2.rdc ps_4785、4791、4798、4800；详见 Evidence/Advanced。
// 原始程序的材质字段保留；角色头朝向/脸部阴影强度等运行输入另设 GF 前缀，避免假称原值。
#ifndef GF2_ADVANCED
#define GF2_ADVANCED
float2 GFHeadXZ(float3 direction) {
    float3 local=SafeNormalize(TransformWorldToObjectDir(direction,false));
    if(_GFUseHeadBasis>0.5) local=float3(dot(direction,_GFHeadRightWS.xyz),0,dot(direction,_GFHeadForwardWS.xyz));
    return local.xz/max(length(local.xz),1e-5);
}
float2 GFBlendUV(GFVaryings i) { return _UseSpecularUV2>0.5?i.uv2:i.uv; }
float GFFaceDiffuse(GFVaryings i,float3 lightDirection,out float4 mask) {
    // [PS 4785 指令119..126] 原/镜像 R 共同参与；A 决定前后区域分支。
    float2 uv=GFBlendUV(i);
    mask=SAMPLE_TEXTURE2D(_BlendTex,sampler_BlendTex,uv);
    float mirror=SAMPLE_TEXTURE2D(_BlendTex,sampler_BlendTex,float2(1-uv.x,uv.y)).r;
    float2 xz=GFHeadXZ(lightDirection);
    // [适配] 原有主光与角色辅助方向的混合取当前主光；没有捕获到的头部控制值不硬编码。
    // PS 4785: (1-A)>0.5，即 A<0.5 时选择第一套区间，注意反编译布尔方向。
    float phase=xz.y*0.5+(mask.a<0.5?0.5:1.5);
    float lo=mask.a<0.5?mirror:mask.r,hi=mask.a<0.5?mask.r:mirror;
    if(xz.x<0)phase=2-phase;
    float width=max(_BlendSmoothness,0.0001);
    float a=frac((phase-width*0.5+4)*0.5)*2;
    float b=frac((phase+width*0.5+4)*0.5)*2;
    float u=saturate((lo-a)/width);
    float w=1-saturate((2-a-hi)/width);
    float first=a<1?u:w;
    float second=1-saturate((b-lo)/width);
    float threshold=b<1?min(second,first):max(w,first);
    float3 local=SafeNormalize(TransformWorldToObjectDir(lightDirection,false));
    return threshold*(1-abs(local.z)*0.5);
}
float3 GFArtisticLighting(GFVaryings i,float3 n,float3 v,float3 base,Light mainLight,float faceShadow) {
    float nl=saturate(dot(n,mainLight.direction));
    bool isFace=_GFRole==1 || _GFRole==4;
    float4 mask=0;float direct=nl;
    if(isFace) direct=GFFaceDiffuse(i,mainLight.direction,mask);
    direct*=mainLight.shadowAttenuation*(1-faceShadow);
    float3 diffuse=GFDiffuseRamp(direct,0.125);
    float3 spec=0;
    float2 uv=GFBlendUV(i);
    // [uber 2819] V 轴偏移取归一化世界观察向量的 y 分量，不是 NdotH 拉伸。
    uv.y-=v.y*_AnisotropyShift;
    if(!isFace) {
        float3 painted=SAMPLE_TEXTURE2D(_BlendTex,sampler_BlendTex,uv).rgb;
        spec=painted*saturate(dot(n,v))*_Anisotropy*(0.031831+0.286479*direct);
    } else {
        // [PS 4785 238..273] 面部 G/B 是两个阈值，G 另有饱和区遮罩；不当成头发 RGB。
        // 原辅助视线向量用当前相机观察方向替代，0.85 混合权重来自指令。
        float2 mixed=normalize(lerp(GFHeadXZ(mainLight.direction),GFHeadXZ(v),0.85)+float2(1e-7,0));
        if(mixed.x<0) uv.x=1-uv.x;
        float4 specMask=SAMPLE_TEXTURE2D(_BlendTex,sampler_BlendTex,uv);
        float threshold=clamp(saturate(-mixed.y-0.707107)*3.414213,0.01,0.99);
        float area=step(threshold,specMask.b)*step(1-threshold,specMask.g);
        float power=area*saturate(dot(n,v))*_Anisotropy*0.318310*saturate(mask.g*4-3);
        spec=(power*direct*(0.1+0.9*mainLight.shadowAttenuation)).xxx;
    }
    float3 color=(base*diffuse+spec)*mainLight.color*mainLight.distanceAttenuation+base*GFGI(n,_UseGIFlatten>0.5);
    #if defined(_ADDITIONAL_LIGHTS)
    for(uint k=0;k<GetAdditionalLightsCount();k++) {
        Light a=GetAdditionalLight(k,i.positionWS,half4(1,1,1,1));
        // [2819] 额外灯只加漫反射，不重复画同一条主光手绘高光。
        color+=base*GFDiffuseRamp(saturate(dot(n,a.direction))*a.shadowAttenuation,0.875)*a.color*a.distanceAttenuation;
    }
    #endif
    float environmentFactor=-0.0024;
    if(_UseRampMap>0.5)environmentFactor=GFRamp(-0.0024*saturate(dot(n,SafeNormalize(_GFRampEnvironmentDirection.xyz))),0.625).r;
    color+=GlossyEnvironmentReflection(reflect(-v,n),i.positionWS,1,1)*(environmentFactor+0.018096);
    return color;
}
#endif
