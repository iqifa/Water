// EID2705/2693 的颜色算法。资源由 URP 提供；原绑定逐指令版本见 Evidence/*ExactPS.hlsl。
// 不走共用 Uber 的丝袜/各向异性/MatCap/AlphaTest 分支：这些均不在本次 PS 中。
#ifndef GF2_TRANS_REALTIME_LIGHTING
#define GF2_TRANS_REALTIME_LIGHTING
float3 GFTLookup(float x,float band) {
    // 原指令不 saturate 横坐标，越界行为由采样器决定。
    return SAMPLE_TEXTURE2D_LOD(_RampMap,sampler_RampMap,float2(x,band),0).rgb;
}
float GFTD(float nh,float r) {
    float a=r*r,den=mad(nh*a,nh*a,1-nh*nh);
    float v=a/den;return min(v*v,2048);
}
float GFTV(float nv,float nl,float r) {
    float a=r*r,b=1-a;
    return min(.5/max(nl*(nv*b+a)+nv*(nl*b+a),.0001),1);
}
float3 GFTResponse(float q,bool main) {
    if(_UseRampMap<=0)return q.xxx;
    float u=max(q*.9999,.000061);
    float3 c=GFTLookup(u,main?.125:.875);
    return (main && u<=.000061)?c:c*min(q/u,1);
}
float3 GFTLight(float3 n,float3 v,float3 l,float3 diffuse,float3 f0,float rough,float shadow,float k,bool main) {
    float3 h=normalize(v+l);
    float nl=max(dot(n,l),0),nh=max(dot(n,h),0),vh=max(dot(v,h),0);
    float nv=min(max(dot(n,v),0)+.00001,1);
    float d=GFTD(nh,rough),vis=GFTV(nv,nl,rough);
    float f=1+(saturate(f0.g*50)-1)*pow(max(1-vh,.001),5);
    float3 spec=(d*vis*f).xxx;
    if(_UseRampMap>0) {
        // 按原顺序分别除峰值 D 和 V，不能用 max(D*V,epsilon) 替代。
        float peakD=min(pow((rough*rough)/pow(rough*rough,2),2),2048);
        float peakV=GFTV(vh,max(dot(l,h),0),rough);
        float u=saturate((d*vis/peakD)/peakV);
        spec=GFTLookup(u,.375)*peakD*peakV*f;
    }
    return (diffuse*k+f0*min(max(spec,0),10))*GFTResponse(nl*shadow,main);
}
float3 GFTSH(float3 n) {
    // 直接展开原始 SH，避免 SampleSH 的顶点/像素混合和色彩空间分支。
    float4 p=float4(n,1),q=n.yzzx*n.xyzz;
    float3 sh=float3(dot(unity_SHAr,p),dot(unity_SHAg,p),dot(unity_SHAb,p))
        +float3(dot(unity_SHBr,q),dot(unity_SHBg,q),dot(unity_SHBb,q))
        +unity_SHC.rgb*(n.x*n.x-n.y*n.y);
    if(_UseGIFlatten<=0)return max(sh,0); // 普通路径没有 0.001 的下限。
    float3 positive=max(sh,.001);
    float3 constantPart=float3(unity_SHAr.w,unity_SHAg.w,unity_SHAb.w)
        +float3(unity_SHBr.z,unity_SHBg.z,unity_SHBb.z)*.3333;
    const float3 luma=float3(.212673,.715152,.072175);
    return positive/dot(positive,luma)*dot(constantPart,luma);
}
// Unity supplies current light/shadow resources. Keep the game's BRDF/Ramp below.
// Shadow bias is applied by Unity's shadow caster; do not apply captured receiver bias again.
Light GFTMainLight(float3 positionWS, float4 positionCS) {
    // Transparent passes sample the world shadow atlas: the opaque screen-space
    // shadow texture contains opaque depth and is not valid for this surface.
    float4 shadowCoord=TransformWorldToShadowCoord(positionWS);
    return GetMainLight(shadowCoord,positionWS,half4(1,1,1,1));
}
float4 GFTransparentShade(GFVaryings i,bool front) {
    UNITY_SETUP_INSTANCE_ID(i);UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    float4 base=GFBase(i);
    float4 rmo=SAMPLE_TEXTURE2D(_RMOTex,sampler_RMOTex,GFUV(i.uv,_RMOTex_ST));
    float4 packed=SAMPLE_TEXTURE2D(_BumpMap,sampler_BumpMap,GFUV(i.uv,_BumpMap_ST));
    float2 xy=float2(packed.r*packed.a,1-packed.g)*2-1;
    float3 geom=i.normalWS*(front?1:-1);
    // 原 VS 中单位化，插值后不逐轴重归一化；只归一化最终扰动法线。
    float3 n=normalize(i.tangentWS.xyz*xy.x+i.frameBitangentWS*xy.y+geom*sqrt(1-min(dot(xy,xy),1)));
    float3 v=normalize(i.frameViewWS);
    float rough=rmo.r; // 不加入 0.02 粗糙度钳制，保留原程序边界行为。
    float3 diffuse=base.rgb*(1-rmo.g),f0=base.rgb*rmo.g+.04*(1-rmo.g);
    float k=mad(_PreMulAlpha,base.a-1,1);
    Light mainLight=GFTMainLight(i.positionWS,i.positionCS);
    float3 mainDir=mainLight.direction;
    float3 color=GFTLight(n,v,mainDir,diffuse,f0,rough,mainLight.shadowAttenuation,k,true)*mainLight.color*mainLight.distanceAttenuation;
    color+=diffuse*GFTSH(n)*rmo.b*k;
    #if defined(_ADDITIONAL_LIGHTS)
        // 与抓帧一致，额外灯采样位置沿未重归一化几何 N 偏移 0.005。
        float3 p=i.positionWS+geom*.005;
        uint count=GetAdditionalLightsCount();
        for(uint j=0;j<count;j++) {
            Light extra=GetAdditionalLight(j,p,half4(1,1,1,1));
            // Realtime additional shadows feed the same Ramp response as the main shadow.
            color+=GFTLight(n,v,extra.direction,diffuse,f0,rough,extra.shadowAttenuation,k,false)*extra.color*extra.distanceAttenuation;
        }
    #endif
    float nv=max(dot(n,v),0);
    float4 c=rough*float4(-1,-.0275,-.572,.022)+float4(1,.0425,1.04,-.04);
    float a=min(c.x*c.x,exp2(-9.28*nv))*c.x+c.y;
    float2 ab=a*float2(1.04,-1.04)+c.wz;
    if(_UseRampMap>0) {
        // PS140–151：主光方向的 view-space X 符号 × inverse-view 第一列。
        // 不再使用旧适配版手填的世界方向。矩阵由当前 URP 相机提供。
        float viewX=mul((float3x3)UNITY_MATRIX_V,mainDir).x;
        float3 direction=normalize(sign(viewX)*float3(UNITY_MATRIX_I_V[0][0],UNITY_MATRIX_I_V[1][0],UNITY_MATRIX_I_V[2][0]));
        ab.x=GFTLookup(ab.x*saturate(dot(n,direction)),.625).r;
    }
    float4 cube=SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0,samplerunity_SpecCube0,reflect(-v,n),rough*6);
    // 即使平台走 native HDR，也保留原程序的这条显式解码链。
    float alpha=max(1+unity_SpecCube0_HDR.w*(cube.a-1),0);
    float decode=exp2(log2(alpha)*unity_SpecCube0_HDR.y)*unity_SpecCube0_HDR.x;
    color+=cube.rgb*decode*(f0*ab.y+ab.x);
    color+=base.rgb*_EmissiveIntensity*rmo.a;
    float3 tinted=color*_FinalTint.rgb;
    // EID2705 PS 380–382 + VS 68–75：状态脉冲，不是 URP MixFog。
    float state=i.frameStateWeight*_GFFrameStateColor.w;
    return float4(mad(state,_GFFrameStateColor.rgb-tinted,tinted),base.a);
}
#endif
