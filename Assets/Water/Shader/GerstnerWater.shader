Shader "Custom/GerstnerWater_VolumeOnly"
{
    Properties
    {
        [Header(UE5 Water Absorption (Shallow Tint and Clarity))]
        // 浅水透射色：决定浅水区水底透出来的颜色（选高明度、高饱和的青绿/湖蓝）
        _WaterAbsorptionColor ("Water Absorption (Shallow Color)", Color) = (0.15, 0.88, 0.78, 1.0)
        // 清澈度深度(米)：值越大水越清澈见底，值越小越快过渡到深水色
        _AbsorptionScale ("Clarity Depth Scale (m)", Range(0.5, 50.0)) = 8.0

        [Space(10)]
        [Header(UE5 Water Scattering (Deep Volume Color))]
        // 深水散射色：水体内部悬浮微粒散射出的本底色（决定深水区颜色，不要选太暗）
        _WaterScatteringColor ("Water Scattering (Deep Color)", Color) = (0.04, 0.42, 0.68, 1.0)
        // 散射通透亮度：1.0 为标准物理亮度，调高会让水体内部更透亮像翡翠
        _ScatteringScale ("Scattering Brightness", Range(0.0, 3.0)) = 1.2

        [Space(10)]
        [Header(Subsurface Sun Glow)]
        // 各向异性前向散射 (0 ~ 0.9)：控制逆光看水时的内部透光增强
        _PhaseG ("Sun Forward Scatter (PhaseG)", Range(0.0, 0.9)) = 0.45
        // 逆光透射强度
        _SunGlowIntensity ("Sun Glow Intensity", Range(0.0, 5.0)) = 1.5

        [Header(Refraction)]
        _RefractionStrength ("Refraction Distortion", Range(0.0, 0.2)) = 0.03
        _RefractionFadeDepth ("Refraction Fade Depth (m)", Range(0.01, 2.0)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "UE5SingleLayerWaterVolume"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Blend One Zero
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _WaterAbsorptionColor;
                float _AbsorptionScale;
                float4 _WaterScatteringColor;
                float _ScatteringScale;
                float _PhaseG;
                float _SunGlowIntensity;
                float _RefractionStrength;
                float _RefractionFadeDepth;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 screenPos : TEXCOORD2;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.screenPos = ComputeScreenPos(output.positionCS);
                return output;
            }

            // Henyey-Greenstein 相位函数 (归一化增益)
            float HenyeyGreensteinPhase(float g, float cosTheta)
            {
                float g2 = g * g;
                float denom = 1.0 + g2 - 2.0 * g * cosTheta;
                return (1.0 - g2) / (4.0 * PI * pow(max(denom, 0.0001), 1.5));
            }

            // 读取视线水深与垂直水深
            void SampleWaterDepths(
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

            half4 frag(Varyings input) : SV_Target
            {
                float2 baseScreenUV = input.screenPos.xy / input.screenPos.w;
                float surfaceEyeDepth = input.screenPos.w;
                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

                // =============================================================
                // 1. 深度自适应折射采样与前景防穿帮回退
                // =============================================================
                float rawDepthBase = SampleSceneDepth(baseScreenUV);
                float baseViewDepth = max(0.0, LinearEyeDepth(rawDepthBase, _ZBufferParams) - surfaceEyeDepth);
                float refractionDepthFade = saturate(baseViewDepth / max(_RefractionFadeDepth, 0.001));

                float2 refractOffset = normalWS.xz * (_RefractionStrength * refractionDepthFade);
                float2 refractedUV = clamp(baseScreenUV + refractOffset, 0.001, 0.999);

                float viewDepth, verticalDepth;
                SampleWaterDepths(refractedUV, surfaceEyeDepth, input.positionWS, viewDepth, verticalDepth);

                if (viewDepth <= 0.0001)
                {
                    refractedUV = baseScreenUV;
                    SampleWaterDepths(refractedUV, surfaceEyeDepth, input.positionWS, viewDepth, verticalDepth);
                }

                half3 sceneColorBehindWater = SampleSceneColor(refractedUV);

                // =============================================================
                // 2. 光学消光与色相渐变计算 (解决发黑问题)
                // =============================================================
                // 使用平方曲线映射 (1 - Color)，让高明度颜色的红绿蓝衰减拉开差距，浅水更亮更清澈
                float3 invColor = 1.0 - saturate(_WaterAbsorptionColor.rgb);
                float3 extinctionCoeff = (invColor * invColor * 2.5 + 0.02) / max(_AbsorptionScale, 0.1);

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));

                // =============================================================
                // 双程光路：去程 (太阳 -> 水底) + 返程 (水底 -> 人眼)
                // =============================================================
                // 返程透过率：只用视线水深 (水底反射光沿视线回到人眼被吸收)
                half3 returnTransmittance = exp(-extinctionCoeff * viewDepth);

                // 去程光程：太阳斜射入水的路径长度 = 垂直水深 / sin(太阳高度角)
                // 太阳越低，光线在水中走的路越长，吸收越强 (黄昏时水底明显更暗更蓝)
                float sunSinHeight = max(mainLight.direction.y, 0.05); // 防止地平线处除零
                float sunPathLength = verticalDepth / sunSinHeight;
                half3 sunTransmittance = exp(-extinctionCoeff * sunPathLength);

                // [水底透射项]：
                // - 直射光贡献 (主要部分)：经历去程+返程两次吸收 -> T_sun * T_ret
                // - 环境光贡献 (近似，占 30% 强度)：只经历一次斜射吸收，用较弱的去程衰减
                //   (天空环境光从四面八方入水，平均光程介于垂直与斜射之间)
                half3 directTransmittance = sunTransmittance * returnTransmittance;
                half3 ambientTransmittance = exp(-extinctionCoeff * sunPathLength * 0.5) * returnTransmittance;
                half3 transmittedSceneColor = sceneColorBehindWater *
                    lerp(ambientTransmittance, directTransmittance, 0.7);

                // =============================================================
                // 3. 通透体积散射与逆光翡翠透射 (In-Scattering)
                // =============================================================

                // 计算太阳穿透水波向人眼散射的夹角 (引入波浪法线扰动，让波峰处逆光更透亮)
                float3 perturbedLightDir = normalize(mainLight.direction + float3(normalWS.x, 0.0, normalWS.z) * 0.4);
                float cosTheta = dot(-perturbedLightDir, viewDirWS);

                // 顺光保持 1.0 基础漫散射亮度(不压暗)，逆光叠加 HG 相位峰值
                float hgPhase = HenyeyGreensteinPhase(_PhaseG, cosTheta) * (4.0 * PI);
                float phaseBoost = 1.0 + max(0.0, hgPhase - 1.0) * _SunGlowIntensity;

                // 水体内部接收的总光照：环境天空球谐光 + 太阳光 (阴影仅保留 70% 压暗，水下散射会柔化阴影)
                half3 ambientLight = SampleSH(float3(0, 1, 0));
                half shadowFactor = lerp(0.3, 1.0, mainLight.shadowAttenuation);

                // 计算一个标量的散射显现权重（基于水深，而非分通道相乘，避免颜色偏纯蓝）
                float scatterMask = 1.0 - exp(-viewDepth / max(_AbsorptionScale, 0.1));

                // 散射颜色随水深平滑显现，浅水清澈，深水呈现你选的 Scattering Color
                half3 scatterColor = _WaterScatteringColor.rgb * _ScatteringScale;

                // 散射光同样走双程：
                // - 太阳分量：光先从水面射到视线下方各点 (随深度增加去程吸收越强)，
                //   再散射向人眼 (返程吸收已含在 scatterMask 的积分近似中)。
                //   用返程一半深度处的去程透过率近似积分：exp(-σ * (verticalDepth*0.5)/sin(sunHeight))
                half3 sunScatterTransmittance = exp(-extinctionCoeff * (verticalDepth * 0.5) / sunSinHeight);
                half3 directInScatter = mainLight.color * (shadowFactor * phaseBoost) * sunScatterTransmittance;

                // - 环境分量：从四周入水，去程吸收弱一些
                half3 ambientInScatter = ambientLight * exp(-extinctionCoeff * verticalDepth * 0.25);

                half3 inScatteredLuminance = (directInScatter + ambientInScatter) * scatterColor * scatterMask;

                // 最终合成
                half3 finalWaterVolumeColor = transmittedSceneColor + inScatteredLuminance;

                return half4(finalWaterVolumeColor, 1.0);
            }
            ENDHLSL
        }
    }
}