#ifndef WATER_VOLUME_LIGHTING_INCLUDED
#define WATER_VOLUME_LIGHTING_INCLUDED

// ============================================================================
// WaterVolumeLighting.hlsl
// 水体体积渲染共享库：双程消光透射 + 体积内散射 (In-Scattering)
//
// 光路模型 (Two-Pass Extinction)：
//
//   太阳 --[去程: 水中光程]--> 水底 --[返程: 视线光程]--> 人眼
//
//   - 去程透过率 T_sun  = exp(-sigma * L_sun)   L_sun = 垂直水深 / sin(太阳高度角)
//   - 返程透过率 T_view = exp(-sigma * L_view)  L_view = 视线方向水下距离
//   - 水底直射光贡献 = T_sun * T_view (经历两次吸收)
//   - 环境光贡献     = 较弱去程 * T_view (天空光从四面八方入水，平均光程更短)
//
// 依赖 (由宿主 shader 在 include 本文件之前 #include)：
//   - URP Core.hlsl / Lighting.hlsl
//   - DeclareDepthTexture.hlsl / DeclareOpaqueTexture.hlsl
// ============================================================================

// ----------------------------------------------------------------------------
// Henyey-Greenstein 相位函数 (归一化增益，g=0 时基准为 1.0)
// 用于逆光看水时体积散射的前向增强 (翡翠透光感)
// ----------------------------------------------------------------------------
float WaterHenyeyGreensteinPhase(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * PI * pow(max(denom, 0.0001), 1.5));
}

// ----------------------------------------------------------------------------
// 读取视线水深与垂直水深
// ----------------------------------------------------------------------------
void WaterSampleDepths(
    float2 screenUV,
    float surfaceEyeDepth,
    float3 surfacePosWS,
    out float viewWaterDepth,
    out float verticalWaterDepth)
{
    float rawDepth = SampleSceneDepth(screenUV);
    float sceneEyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

    viewWaterDepth = max(0.0, sceneEyeDepth - surfaceEyeDepth);

    #if !UNITY_REVERSED_Z
    rawDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, rawDepth);
    #endif
    float3 bottomPosWS = ComputeWorldSpacePosition(screenUV, rawDepth, unity_MatrixInvVP);
    verticalWaterDepth = max(0.0, surfacePosWS.y - bottomPosWS.y);
}

// ----------------------------------------------------------------------------
// 折射采样 + 前景防穿帮回退
// 返回: refractedUV (可能回退到 baseUV), viewDepth, verticalDepth
// ----------------------------------------------------------------------------
void WaterSampleRefraction(
    float2 baseScreenUV,
    float surfaceEyeDepth,
    float3 surfacePosWS,
    float3 normalWS,
    float refractionStrength,
    float refractionFadeDepth,
    out float2 refractedUV,
    out float viewDepth,
    out float verticalDepth)
{
    // 前景物体太近时折射偏移会采样到水面上的东西，按水下距离淡出偏移
    float rawDepthBase = SampleSceneDepth(baseScreenUV);
    float baseViewDepth = max(0.0, LinearEyeDepth(rawDepthBase, _ZBufferParams) - surfaceEyeDepth);
    float refractionDepthFade = saturate(baseViewDepth / max(refractionFadeDepth, 0.001));

    float2 refractOffset = normalWS.xz * (refractionStrength * refractionDepthFade);
    refractedUV = clamp(baseScreenUV + refractOffset, 0.001, 0.999);

    WaterSampleDepths(refractedUV, surfaceEyeDepth, surfacePosWS, viewDepth, verticalDepth);

    // 偏移后采样到了水面前方 (穿帮) 时回退到未偏移 UV
    if (viewDepth <= 0.0001)
    {
        refractedUV = baseScreenUV;
        WaterSampleDepths(refractedUV, surfaceEyeDepth, surfacePosWS, viewDepth, verticalDepth);
    }
}

// ----------------------------------------------------------------------------
// 核心：双程消光 + 内散射，返回水体体积最终颜色
//
// 参数:
//   sceneColor      折射后的水底场景色 (SampleSceneColor)
//   viewDepth       视线方向水下距离 (米)
//   verticalDepth   垂直水深 (米)
//   normalWS        水面法线 (用于相位扰动，让波峰逆光更透亮)
//   viewDirWS       指向人眼的方向
//   mainLight       主光 (含阴影衰减)
//   absorptionColor 浅水透射色 (高明度青绿/湖蓝，决定吸收率与浅水染色)
//   absorptionScale 清澈度深度(米)：越大越清澈
//   scatteringColor 深水散射色 (水体内部本底色)
//   scatteringScale 散射亮度
//   phaseG          HG 各向异性参数 (0~0.9, 正值=前向散射增强)
//   sunGlow         逆光透射强度
// ----------------------------------------------------------------------------
half3 WaterVolumeShading(
    half3 sceneColor,
    float viewDepth,
    float verticalDepth,
    float3 normalWS,
    float3 viewDirWS,
    Light mainLight,
    float3 absorptionColor,
    float absorptionScale,
    float3 scatteringColor,
    float scatteringScale,
    float phaseG,
    float sunGlow)
{
    // ---- 消光系数：平方映射让 RGB 衰减拉开差距，浅水更亮更清澈 ----
    float3 invColor = 1.0 - saturate(absorptionColor);
    float3 extinction = (invColor * invColor * 2.5 + 0.02) / max(absorptionScale, 0.1);

    // ===================== 双程透射 (Transmittance) =====================
    // 返程：水底反射光沿视线回到人眼
    half3 returnT = exp(-extinction * viewDepth);

    // 去程：太阳斜射入水，光程 = 垂直水深 / sin(高度角)
    // 太阳越低去程越长 -> 黄昏时水底自然更暗更蓝
    float sunSinHeight = max(mainLight.direction.y, 0.05);
    float sunPath = verticalDepth / sunSinHeight;
    half3 sunT = exp(-extinction * sunPath);

    // 直射光经历两次吸收 (T_sun * T_view, 权重 70%)；
    // 环境光平均去程约一半 (权重 30%)
    half3 directT = sunT * returnT;
    half3 ambientT = exp(-extinction * sunPath * 0.5) * returnT;
    half3 totalTransmittance = lerp(ambientT, directT, 0.7);

    half3 transmittedScene = sceneColor * totalTransmittance;

    // ===================== 内散射 (In-Scattering) =====================
    // 太阳方向加入波浪法线扰动，波峰处逆光更透亮
    float3 perturbedLightDir = normalize(mainLight.direction + float3(normalWS.x, 0.0, normalWS.z) * 0.4);
    float cosTheta = dot(-perturbedLightDir, viewDirWS);

    // 顺光保持 1.0 基础亮度，逆光叠加 HG 相位峰值
    float hgPhase = WaterHenyeyGreensteinPhase(phaseG, cosTheta) * (4.0 * PI);
    float phaseBoost = 1.0 + max(0.0, hgPhase - 1.0) * sunGlow;

    half3 ambientLight = SampleSH(float3(0, 1, 0));
    // 阴影只压 70%：水下散射会柔化阴影边界
    half shadowFactor = lerp(0.3, 1.0, mainLight.shadowAttenuation);

    // 散射显现权重 (标量，避免分通道相乘导致颜色偏纯蓝)
    float scatterMask = 1.0 - exp(-viewDepth / max(absorptionScale, 0.1));

    // 散射光的双程：太阳分量取半垂直深度处的去程透过率 (积分近似)
    half3 sunScatterT = exp(-extinction * (verticalDepth * 0.5) / sunSinHeight);
    half3 directInScatter = mainLight.color * (shadowFactor * phaseBoost) * sunScatterT;

    // 环境分量去程更弱 (四周入水)
    half3 ambientInScatter = ambientLight * exp(-extinction * verticalDepth * 0.25);

    half3 inScatter = (directInScatter + ambientInScatter)
                    * (scatteringColor * scatteringScale)
                    * scatterMask;

    return transmittedScene + inScatter;
}

#endif // WATER_VOLUME_LIGHTING_INCLUDED
