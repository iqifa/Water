// 追放人物着色 · Unity 2022.3 / URP 14 重建版。
// [还原] 可追溯到 Evidence/uber_2809.annotated.asm 的基础分支。
// [适配] 光源/阴影绑定、坐标、环境探针和雾使用 URP 14；不是原游戏完整渲染器。
// 丝袜/两种各向异性/脸部方向遮罩/刘海模板链见 GF2CharacterAdvanced.hlsl。
#ifndef GF2_CHARACTER_COMMON
#define GF2_CHARACTER_COMMON
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "GF2MaterialBuffer.hlsl"
TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
TEXTURE2D(_RMOTex); SAMPLER(sampler_RMOTex);
TEXTURE2D(_RampMap); SAMPLER(sampler_RampMap);
TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
TEXTURE2D(_Specularmap); SAMPLER(sampler_Specularmap);
TEXTURE2D(_BlendTex); SAMPLER(sampler_BlendTex);

struct GFAttributes {
    float4 positionOS:POSITION;
    float3 normalOS:NORMAL;
    float4 tangentOS:TANGENT;
    float2 uv:TEXCOORD0;
    float2 uv2:TEXCOORD1;
    float4 color:COLOR;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};
struct GFVaryings {
    float4 positionCS:SV_POSITION;
    float2 uv:TEXCOORD0;
    float3 positionWS:TEXCOORD1;
    float3 normalWS:TEXCOORD2;
    float4 tangentWS:TEXCOORD3;
    float4 shadowCoord:TEXCOORD4;
    float fog:TEXCOORD5;
    float eyeShift:TEXCOORD6;
    float2 uv2:TEXCOORD7;
    #if defined(GF_TRANSPARENT)
    float3 frameBitangentWS:TEXCOORD8;
    float3 frameViewWS:TEXCOORD9;
    float frameStateWeight:TEXCOORD10;
    #endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};
GFVaryings GFVertex(GFAttributes v) {
    GFVaryings o=(GFVaryings)0;
    UNITY_SETUP_INSTANCE_ID(v); UNITY_TRANSFER_INSTANCE_ID(v,o); UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    VertexPositionInputs p=GetVertexPositionInputs(v.positionOS.xyz);
    VertexNormalInputs n=GetVertexNormalInputs(v.normalOS,v.tangentOS);
    o.positionCS=p.positionCS; o.positionWS=p.positionWS; o.normalWS=n.normalWS;
    o.tangentWS=float4(n.tangentWS,v.tangentOS.w*GetOddNegativeScale());
    o.uv=v.uv; o.uv2=v.uv2; o.shadowCoord=GetShadowCoord(p); o.fog=ComputeFogFactor(p.positionCS.z);
    #if defined(GF_TRANSPARENT)
    o.normalWS=normalize(n.normalWS);o.tangentWS.xyz=normalize(n.tangentWS);
    o.frameBitangentWS=cross(o.normalWS,o.tangentWS.xyz)*o.tangentWS.w;
    o.frameViewWS=GetCameraPositionWS()-p.positionWS;
    o.frameStateWeight=(1-_GFFrameStateEnable<.01)?1-((sin(_Time.y*5)+1)*.35+.2):0;
    #endif
    // [还原眼球 VS 0] 偏移由观察方向 OS.z、顶点色 G、tangent.w、负缩放符号共同控制。
    // 原项目骨架/模型朝向仍需与导出的 FBX 对齐；这是网格驱动的视差，不是随意滚动 UV。
    float3 viewOS=SafeNormalize(TransformWorldToObjectDir(GetWorldSpaceViewDir(p.positionWS),false));
    o.eyeShift=viewOS.z*v.color.g*v.tangentOS.w*GetOddNegativeScale();
    return o;
}
float2 GFUV(float2 uv,float4 st) { return uv*st.xy+st.zw; }
float4 GFBase(GFVaryings i) { return SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,GFUV(i.uv,_BaseMap_ST))*_BaseColor; }
void GFClip(float alpha) {
    // 原材质的 _ALPHATEST_ON 是编译变体；这里也接受数值开关，方便自动导入和 Inspector 修改。
    #if defined(_ALPHATEST_ON)
        clip(alpha-_Cutoff);
    #else
        if(_UseAlphaTest>0.5) clip(alpha-_Cutoff);
    #endif
}
float3 GFNormal(GFVaryings i,bool front) {
    // [还原] 原程序只翻转基础 N，不把整个 TBN 三轴同时取负。
    float3 n=normalize(i.normalWS)*(front?1:-1);
    if(_GFNormalEnabled<0.5) return n;
    float4 packed=SAMPLE_TEXTURE2D(_BumpMap,sampler_BumpMap,GFUV(i.uv,_BumpMap_ST));
    // 原始 PNG 必须按 Default + 线性导入。若让 Unity 按 NormalMap 再打包，会重复解码。
    float2 xy=float2(packed.r*packed.a,1-packed.g)*2-1;
    float z=sqrt(1-min(dot(xy,xy),1));
    float3 t=normalize(i.tangentWS.xyz);
    float3 b=cross(normalize(i.normalWS),t)*i.tangentWS.w;
    return normalize(t*xy.x+b*xy.y+n*z);
}
float3 GFRamp(float x,float band) {
    // [还原] 显式 LOD 0；四条带不是四个材质。原 Ramp 为线性 RGBAHalf。
    return SAMPLE_TEXTURE2D_LOD(_RampMap,sampler_RampMap,float2(saturate(x),band),0).rgb;
}
float GFD(float nh,float roughness) {
    // [还原] D 项不带显式 PI；后续 Ramp 峰值归一化也使用同一约定。
    float a=roughness*roughness;
    float denom=max((nh*a)*(nh*a)+1-nh*nh,1e-8);
    return min(2048,(a/denom)*(a/denom));
}
float GFAnisotropicD(float3 n,float3 bitangent,float3 h,float roughness) {
    // [uber 2810] _AnisotropicGXX 是真正的微表面各向异性，与头发贴图高光开关不同。
    // 2810/2814：只单位化输入 B，两个 cross 结果不再次单位化。
    float3 t=cross(normalize(bitangent),n);
    float3 b=cross(n,t);
    float a=roughness*roughness;
    float ax=max(a*(1+_AnisotropicGXX),0.001),ay=max(a*(1-_AnisotropicGXX),0.001);
    float product=ax*ay;
    float3 q=float3(dot(t,h)*ay,dot(b,h)*ax,dot(n,h)*product);
    float d=product/max(dot(q,q),1e-10);
    return d*d*product*0.318310;
}
float GFV(float nv,float nl,float roughness) {
    float a=roughness*roughness;
    return min(1,0.5/max(nl*(nv*(1-a)+a)+nv*(nl*(1-a)+a),0.0001));
}
float3 GFDiffuseRamp(float nl,float band) {
    if(_UseRampMap<0.5) return nl.xxx;
    float x=max(nl*0.9999,0.000061);
    float3 c=GFRamp(x,band);
    // [还原] 主光最低输入保持 Ramp 阴影端；额外灯不向背光面添加常数光。
    if(band>0.8 || x>0.000061) c*=min(nl/x,1);
    return c;
}
float3 GFLightTerms(float3 n,float3 bitangent,float3 v,float3 diffuse,float3 f0,float roughness,Light light,float band,float diffuseAlpha,out float3 diffuseTerm,out float3 specularTerm) {
    float3 h=SafeNormalize(v+light.direction);
    float nl=saturate(dot(n,light.direction));
    float nh=saturate(dot(n,h)), vh=saturate(dot(v,h)), lh=saturate(dot(light.direction,h));
    float nv=min(saturate(dot(n,v))+0.00001,1);
    float d=GFD(nh,roughness),vis=GFV(nv,nl,roughness);
    if(_UseStockingFalloff>0.5 && abs(_AnisotropicGXX)>0.001) d=GFAnisotropicD(n,bitangent,h,roughness);
    float fresnel=1+(saturate(50*f0.g)-1)*pow(max(1-vh,0.001),5);
    float3 spec=(d*vis*fresnel).xxx;
    if(_UseRampMap>0.5) {
        // [还原] 先按峰值 D/V 归一化，查 0.375 带，再恢复峰值；不是直接 Ramp(NdotH)。
        float peak=GFD(1,roughness)*GFV(vh,lh,roughness);
        spec=GFRamp(saturate(d*vis/max(peak,1e-8)),0.375)*peak*fresnel;
    }
    // [适配] 阴影使用 URP 接口；原有 shadow/MRT/角色专用遮挡不由这一步完整恢复。
    float3 response=GFDiffuseRamp(nl*light.shadowAttenuation,band);
    diffuseTerm=diffuse*diffuseAlpha*response;
    specularTerm=f0*clamp(spec,0,10)*response;
    return (diffuseTerm+specularTerm)*light.color*light.distanceAttenuation;
}
float3 GFLight(float3 n,float3 bitangent,float3 v,float3 diffuse,float3 f0,float roughness,Light light,float band,float diffuseAlpha) {
    float3 d,s;return GFLightTerms(n,bitangent,v,diffuse,f0,roughness,light,band,diffuseAlpha,d,s);
}
float3 GFGI(float3 n,bool flatten) {
    float3 sh=max(SampleSH(n),0.001);
    if(flatten) {
        // [还原基础式] 保留方向色相，用 SH 常量部分的亮度压平方向明暗。
        float3 constantPart=float3(unity_SHAr.w,unity_SHAg.w,unity_SHAb.w)+
            float3(unity_SHBr.z,unity_SHBg.z,unity_SHBb.z)*0.3333;
        float3 luma=float3(0.212673,0.715152,0.072175);
        sh*=dot(constantPart,luma)/max(dot(sh,luma),1e-5);
    }
    return max(sh,0);
}
#include "GF2CharacterAdvanced.hlsl"
#include "GF2UberSurfaceBranches.hlsl"
float4 GFShade(GFVaryings i,bool front,float faceShadow) {
    UNITY_SETUP_INSTANCE_ID(i); UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    float4 base=GFBase(i); GFClip(base.a);
    float3 n=GFNormal(i,front),v=SafeNormalize(GetWorldSpaceViewDir(i.positionWS));
    Light mainLight=GetMainLight(i.shadowCoord);
    if(_AnisotropicSpecular>0.5) {
        float3 art=GFArtisticLighting(i,n,v,base.rgb,mainLight,faceShadow);
        return float4(MixFog(art*_FinalTint.rgb,i.fog),base.a);
    }
    float4 rmo=_GFUseRMO>0.5?SAMPLE_TEXTURE2D(_RMOTex,sampler_RMOTex,GFUV(i.uv,_RMOTex_ST)):float4(0.6,0,1,0);
    float3 geom=normalize(i.normalWS)*(front?1:-1);
    float3 tangent=normalize(i.tangentWS.xyz);
    float3 surfaceBitangent=cross(normalize(i.normalWS),tangent)*i.tangentWS.w;
    float3 normalTS=_GFNormalEnabled>.5?GFUnpackSurfaceNormal(SAMPLE_TEXTURE2D(_BumpMap,sampler_BumpMap,GFUV(i.uv,_BumpMap_ST))):float3(0,0,1);
    // 原资源这些是不同编译变体；同时请求 Volume/Detail 时显式以 Volume 为先。
    if(_UseDetailMap>.5 && _UseVolumetricEffect<=.5)GFDetailSurface(i.uv,i.uv2,base.rgb,normalTS,rmo);
    bool anisotropicSurface=_UseStockingFalloff>.5 && abs(_AnisotropicGXX)>.001;
    float3 surfaceExtra=anisotropicSurface?0:base.rgb*_EmissiveIntensity*rmo.a;
    if(_UseVolumetricEffect>.5)GFVolumeSurface(i.uv,normalTS,tangent,surfaceBitangent,geom,v,rmo.r,base.rgb,surfaceExtra);
    GFGlitterSurfaceData glitter=GFGlitterSurface(i.uv,tangent,surfaceBitangent,geom,v,rmo);
    if(_UseDetailMap>.5 || _UseVolumetricEffect>.5 || _UseStockingFalloff>.5)n=GFSurfaceWorldNormal(normalTS,tangent,surfaceBitangent,geom);
    float roughness=(_UseDetailMap>.5 || _UseVolumetricEffect>.5 || _UseStockingFalloff>.5)?rmo.r:max(rmo.r,.02);
    float dielectric=anisotropicSurface?.08*rmo.a:.04;
    float3 diffuse=base.rgb*(1-rmo.g),f0=base.rgb*rmo.g+dielectric*(1-rmo.g);
    // [uber 2810] 只调制漫反射颜色；不是直接给最终图套一个 Fresnel 黑边。
    if(_UseStockingFalloff>0.5) {
        float f=pow(min(saturate(dot(n,v))+0.00001,1),max(_StockingFalloffPower,0.0001));
        diffuse*=lerp(_StockingFalloffColor.rgb,_StockingCenterColor.rgb,f);
    }
    float3 bitangent=SafeNormalize(cross(normalize(i.normalWS),normalize(i.tangentWS.xyz))*i.tangentWS.w);
    float diffuseAlpha=1;
    #if defined(GF_TRANSPARENT)
        // [适配] 预乘模式只压低漫反射，保留高光；普通 SrcAlpha 模式交给 Blend。
        diffuseAlpha=lerp(1,base.a,_PreMulAlpha);
    #endif
    float3 mainDiffuse,mainSpecular;
    float3 result=GFLightTerms(n,bitangent,v,diffuse,f0,roughness,mainLight,0.125,diffuseAlpha,mainDiffuse,mainSpecular);
    result+=GFGlitterLighting(glitter,base.rgb,mainDiffuse,mainSpecular,max(dot(n,mainLight.direction),0));
    #if defined(_ADDITIONAL_LIGHTS)
        uint count=GetAdditionalLightsCount();
        for(uint k=0;k<count;k++) {
            Light light=GetAdditionalLight(k,i.positionWS,half4(1,1,1,1));
            result+=GFLight(n,bitangent,v,diffuse,f0,roughness,light,0.875,diffuseAlpha);
        }
    #endif
    // [还原] RMO.B 只调制这里的环境漫反射，不直接乘整个最终颜色。
    result+=diffuse*GFGI(n,_UseGIFlatten>0.5)*rmo.b*diffuseAlpha;
    float nv=saturate(dot(n,v));
    float4 c=roughness*float4(-1,-0.0275,-0.572,0.022)+float4(1,0.0425,1.04,-0.04);
    float a004=min(c.x*c.x,exp2(-9.28*nv))*c.x+c.y;
    float2 ab=a004*float2(1.04,-1.04)+c.wz;
    if(_UseRampMap>0.5) {
        // [适配] 原 cb0 1337..1341 使用角色/场景辅助方向；Unity 无对应全局量。
        // 暴露世界方向作为替代，不伪称这个向量已经恢复成原游戏运行值。
        ab.x=GFRamp(ab.x*saturate(dot(n,SafeNormalize(_GFRampEnvironmentDirection.xyz))),0.625).r;
    }
    // [适配] 使用 URP 探针采样/解码；原版本直接 roughness*6 选择 cubemap mip。
    float3 environment=GlossyEnvironmentReflection(reflect(-v,n),i.positionWS,roughness,1);
    result+=environment*(f0*ab.y+ab.x);
    // [还原] RMO.A 是额外基色项遮罩，不是 Alpha。
    result+=surfaceExtra;
    result*=_FinalTint.rgb;
    result=MixFog(result,i.fog); // [适配] 通用 URP 雾，不是原角色选择/受击/全息特效。
    #if defined(GF_TRANSPARENT)
        return float4(result,base.a);
    #else
        return float4(result,1);
    #endif
}
float4 GFFragment(GFVaryings i,FRONT_FACE_TYPE face:FRONT_FACE_SEMANTIC):SV_Target {
    return GFShade(i,IS_FRONT_VFACE(face,true,false),0);
}
GFVaryings GFHairMaskVertex(GFAttributes v) {
    GFVaryings o=GFVertex(v);
    // [uber VS 5642] 原位移是世界 X/Y，随主光 X 改变，不是沿光方向的投影阴影贴图。
    o.positionWS+=float3(-0.0045*GetMainLight().direction.x,-0.0075,0)*_GFHairShadowScale;
    o.positionCS=TransformWorldToHClip(o.positionWS);return o;
}
float4 GFHairMaskFragment(GFVaryings i):SV_Target {
    clip(0.1-abs(_GFRole-3)); return 0; // 仅刘海；颜色写入由 ColorMask 0 关闭。
}
float4 GFFaceShadowFragment(GFVaryings i,FRONT_FACE_TYPE face:FRONT_FACE_SEMANTIC):SV_Target {
    clip(0.1-abs(_GFRole-1));
    return GFShade(i,IS_FRONT_VFACE(face,true,false),_GFFaceShadowStrength);
}
float4 GFFringeFragment(GFVaryings i,FRONT_FACE_TYPE face:FRONT_FACE_SEMANTIC):SV_Target {
    clip(0.1-abs(_GFRole-3));
    float4 c=GFShade(i,IS_FRONT_VFACE(face,true,false),0);c.a=GFBase(i).a;return c;
}

float4 GFEyeFragment(GFVaryings i):SV_Target {
    UNITY_SETUP_INSTANCE_ID(i);
    float2 uv=GFUV(i.uv,_MainTex_ST);
    float3 base=SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,uv+float2(i.eyeShift*_CorneaParallax,0)).rgb;
    float3 spec=SAMPLE_TEXTURE2D(_Specularmap,sampler_Specularmap,uv+float2(i.eyeShift*_SpecularParallax,0)).rgb*_SpecularIntensity;
    float3 n=normalize(i.normalWS); Light l=GetMainLight(i.shadowCoord);float nl=saturate(dot(n,l.direction));
    // [还原 eye 288] 基础照明有 _ShadowIntensity 底值；高光贴图是一层手绘响应。
    float3 color=(base*lerp(_ShadowIntensity,1,nl)+spec*nl)*l.color*l.shadowAttenuation+base*GFGI(n,true);
    #if defined(_ADDITIONAL_LIGHTS)
        for(uint k=0;k<GetAdditionalLightsCount();k++) {
            Light a=GetAdditionalLight(k,i.positionWS,half4(1,1,1,1));
            color+=(base+spec)*saturate(dot(n,a.direction))*a.color*a.distanceAttenuation*a.shadowAttenuation;
        }
    #endif
    return float4(color*_BaseColor.rgb,0); // 原基础分支输出 Alpha=0；Pass 只写 RGB。
}
float4 GFEyeAddFragment(GFVaryings i):SV_Target {
    float4 c=SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,GFUV(i.uv,_MainTex_ST))*_MainColor;
    // [还原 add 48] 高光强度带 0.2 的背光底值；Pass One/One。
    float lightFactor=saturate(dot(i.normalWS,GetMainLight().direction))*0.8+0.2;
    return float4(c.rgb*_SpecularIntensity*lightFactor,c.a);
}
float4 GFEyeMultiplyFragment(GFVaryings i):SV_Target {
    float3 c=SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,GFUV(i.uv,_MainTex_ST)).rgb*_MainColor.rgb;
    // [还原 multiply 16] 强度=0 时输出白色，DstColor/Zero 乘法不会改变背景。
    return float4(lerp(float3(1,1,1),c,_SpecularIntensity),1);
}
GFVaryings GFOutlineVertex(GFAttributes v) {
    GFVaryings o=GFVertex(v);
    // [替代实现] 屏幕像素外扩轮廓；原算法的顶点色/方向宽度/ZBias 没有等价移植。
    float2 normalVS=TransformWorldToViewDir(o.normalWS).xy;
    float len=max(length(normalVS),1e-5);
    o.positionCS.xy+=normalVS/len*_OutlineWidth*_GFOutlineScale*2/_ScaledScreenParams.xy*o.positionCS.w;
    return o;
}
float4 GFOutlineFragment(GFVaryings i):SV_Target {
    clip(_OutlineWidth-0.00001);GFClip(GFBase(i).a);
    return float4(_OutlineColor.rgb*_OutlineIntensity,1);
}
float4 GFDepthFragment(GFVaryings i):SV_Target { GFClip(GFBase(i).a); return 0; }
float4 GFDepthNormalsFragment(GFVaryings i,FRONT_FACE_TYPE face:FRONT_FACE_SEMANTIC):SV_Target {
    GFClip(GFBase(i).a);return float4(GFNormal(i,IS_FRONT_VFACE(face,true,false)),0);
}
float3 _LightDirection;float3 _LightPosition;
GFVaryings GFShadowVertex(GFAttributes v) {
    GFVaryings o=GFVertex(v);
    #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
        float3 lightDirection=normalize(_LightPosition-o.positionWS);
    #else
        float3 lightDirection=_LightDirection;
    #endif
    o.positionCS=TransformWorldToHClip(ApplyShadowBias(o.positionWS,normalize(o.normalWS),lightDirection));
    #if UNITY_REVERSED_Z
        o.positionCS.z=min(o.positionCS.z,UNITY_NEAR_CLIP_VALUE*o.positionCS.w);
    #else
        o.positionCS.z=max(o.positionCS.z,UNITY_NEAR_CLIP_VALUE*o.positionCS.w);
    #endif
    return o;
}
#endif
