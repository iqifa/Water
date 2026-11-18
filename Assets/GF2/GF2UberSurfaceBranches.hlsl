// 原资源 Uber 2810/2813/2814/2817/2818；参数名由 Unity shader 序列化绑定表核实。
// 这些是表面分支，不能用脸/头发的 _BlendTex 或 URP 通用 Detail 替代。
#ifndef GF2_UBER_SURFACE_BRANCHES
#define GF2_UBER_SURFACE_BRANCHES
TEXTURE2D(_DetailAlbedo);SAMPLER(sampler_DetailAlbedo);
TEXTURE2D(_DetailNormalRM);SAMPLER(sampler_DetailNormalRM);
TEXTURE2D(_DetailMask);SAMPLER(sampler_DetailMask);
TEXTURE2D(_GlitterMap);SAMPLER(sampler_GlitterMap);
TEXTURE2D(_MatcapTex);SAMPLER(sampler_MatcapTex);
TEXTURE2D(_MatcapNormalTex);SAMPLER(sampler_MatcapNormalTex);
float3 GFUnpackSurfaceNormal(float4 p) {
    float2 xy=float2(p.r*p.a,1-p.g)*2-1;
    return float3(xy,sqrt(1-min(dot(xy,xy),1)));
}
float3 GFSurfaceWorldNormal(float3 tangentNormal,float3 t,float3 b,float3 geom) {
    return normalize(t*tangentNormal.x+b*tangentNormal.y+geom*tangentNormal.z);
}
void GFDetailSurface(float2 uv,float2 uv2,inout float3 base,inout float3 normalTS,inout float4 rmo) {
    // 2817：Mask 使用原 UV0 的 G；两张细节图共用 UV2 * DetailAlbedo_ST。
    // 不使用 _DetailNormalRM_ST，也不把 DetailNormalRM 按主法线 AG/翻 G 解码。
    float mask=SAMPLE_TEXTURE2D(_DetailMask,sampler_DetailMask,uv).g;
    float2 detailUV=uv2*_DetailAlbedo_ST.xy+_DetailAlbedo_ST.zw;
    float4 detail=SAMPLE_TEXTURE2D(_DetailAlbedo,sampler_DetailAlbedo,detailUV);
    base=lerp(base,detail.rgb,mask*detail.a*_DetailAlbedoIntensity);
    bool normalOn=_DetailNormalIntensity>.000061,rmOn=_DetailRMIntensity>.000061;
    if(normalOn || rmOn) {
        float weight=mask*saturate(mask*detail.a*_DetailAlphaIntensity);
        float4 packed=SAMPLE_TEXTURE2D(_DetailNormalRM,sampler_DetailNormalRM,detailUV);
        float2 xy=(packed.rg*2-1)*_DetailNormalIntensity*weight;
        float3 mixed=normalize(float3(normalTS.xy+xy,normalTS.z*sqrt(max(1-dot(xy,xy),0))));
        if(normalOn)normalTS=mixed;
        if(rmOn)rmo.rg=lerp(rmo.rg,packed.ba,weight*_DetailRMIntensity);
    }
    // 当前编译程序不读取 _DetailAlphaMode，不因此修改透明度或套通用 Alpha 混合。
}
float3 GFDecodeSurfaceCube(float3 direction,float mip) {
    float4 c=SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0,samplerunity_SpecCube0,direction,mip);
    float scale=pow(max(1+unity_SpecCube0_HDR.w*(c.a-1),0),unity_SpecCube0_HDR.y)*unity_SpecCube0_HDR.x;
    return c.rgb*scale;
}
void GFVolumeSurface(float2 uv,float3 normalTS,float3 t,float3 b,float3 geom,float3 view,float rough,inout float3 base,inout float3 extra) {
    // 2813/2814：几何 N 单位化后构造观察方向 TS，偏移不是常规 height/v.z 视差。
    float3 ng=normalize(geom);
    float3 viewTS=normalize(float3(dot(t,view),dot(b,view),dot(ng,view)));
    float2 blendUV=uv*_BlendTex_ST.xy+_BlendTex_ST.zw;
    float height=SAMPLE_TEXTURE2D(_BlendTex,sampler_BlendTex,blendUV).r;
    float h=saturate((1-height+_InsideHeightBias)*_InsideHeightContrast);
    float4 unshifted=SAMPLE_TEXTURE2D(_BlendTex,sampler_BlendTex,uv);
    float2 offsetUV=blendUV+viewTS.xy*(h-1)*.35;
    float3 inside=SAMPLE_TEXTURE2D(_BlendTex,sampler_BlendTex,offsetUV).rgb;
    inside=(inside+_InsideColorBias)*_InsideColorContrast*_InsideBaseColor.rgb;
    float3 tinted=base*inside;
    float luminance=dot(max(tinted,0),float3(.212673,.715152,.072175));
    if(_UseMatcapRef>.5) {
        float3 mcN=GFUnpackSurfaceNormal(SAMPLE_TEXTURE2D(_MatcapNormalTex,sampler_MatcapNormalTex,offsetUV));
        mcN=GFSurfaceWorldNormal(mcN,t,b,geom);
        float2 mcUV=mul((float3x3)UNITY_MATRIX_V,mcN).xy*.5+.5;
        float3 mc=SAMPLE_TEXTURE2D(_MatcapTex,sampler_MatcapTex,mcUV).rgb;
        extra+=mc*mc*mc*_MatcapIntensity*luminance;
        float2 rimUV=mul((float3x3)UNITY_MATRIX_V,ng).xy*.5+.5;
        float rim=pow(1-saturate(dot(view,ng)),_MatcapRimPower*5)*_MatcapRimPower*5;
        extra+=SAMPLE_TEXTURE2D(_MatcapTex,sampler_MatcapTex,rimUV).rgb*rim;
    }
    float blend=1+unshifted.a*(saturate(1-luminance+_BaseInsideLerp)-1);
    base=lerp(tinted,base,blend);
    // 特别保留原 2813 的混合空间：这里直接用 normalTS 与 world view 构建 cube 方向。
    // 不擅自“纠正”为普通世界反射；后面的 Fresnel 使用 TBN 变换后的法线。
    float3 internalReflection=view-2*dot(view,normalTS)*normalTS;
    float3 cube=GFDecodeSurfaceCube(internalReflection,rough*10);
    float3 rawWorldNormal=t*normalTS.x+b*normalTS.y+ng*normalTS.z;
    float oneMinusNV=1-dot(rawWorldNormal,view);
    float fifth=oneMinusNV*oneMinusNV;fifth=fifth*fifth*oneMinusNV;
    float f=saturate(_ReflectionFresnelF0+(1-_ReflectionFresnelF0)*fifth);
    extra+=base*lerp(_FakeIntensity.xxx,cube*_ReflectionIntensity,f)*unshifted.a;
}
struct GFGlitterSurfaceData {float3 rgb;float rim;};
GFGlitterSurfaceData GFGlitterSurface(float2 uv,float3 t,float3 b,float3 geom,float3 view,inout float4 rmo) {
    GFGlitterSurfaceData o=(GFGlitterSurfaceData)0;
    if(_UseStockingFalloff<=.5 || _UseGlitter<=0)return o;
    float vt=dot(normalize(t),view),vb=dot(normalize(b),view),vn=dot(normalize(geom),view);
    float shape=pow(saturate(vt*vt+vb*vb*_GlitterViewWeight),_GlitterRimFalloff);
    o.rim=saturate(lerp(_GlitterRimMin,_GlitterRimMax,shape));
    float curvature=lerp(1,max(1-50*(abs(ddx(vn))+abs(ddy(vn))),0),_GlitterCurvature);
    // 名为 Speed，但这个分支没有读取时间：控制的是双向视差距离。
    float2 offset=float2(vt,vb)/(vn+.42)*(_GlitterSpeed*.005)*curvature;
    float4 a=SAMPLE_TEXTURE2D(_GlitterMap,sampler_GlitterMap,(uv+offset)*_GlitterDensity);
    float4 bMap=SAMPLE_TEXTURE2D(_GlitterMap,sampler_GlitterMap,(uv-offset)*_GlitterDensity);
    o.rgb=a.rgb*bMap.a;
    float luma=dot(o.rgb,float3(.299,.587,.114));
    rmo.rg=saturate(rmo.rg+float2(-_GlitterRoughness,_GlitterMetallic)*luma*o.rim);
    return o;
}
float3 GFGlitterLighting(GFGlitterSurfaceData glitter,float3 base,float3 diffuseTerm,float3 specularTerm,float nl) {
    // 2810 主光段：两项在主光颜色/距离衰减之外加入，而不是简单的自发光点。
    float3 spec=min(2*glitter.rgb*(diffuseTerm+10*specularTerm),2)*_GlitterSpecIntensity;
    float3 rim=min(base*glitter.rgb*((nl*.5+.5)*glitter.rim*_GlitterRimIntensity*10),2);
    return spec+rim;
}
#endif
