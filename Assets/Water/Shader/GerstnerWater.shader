Shader "Custom/GerstnerWater"
{
    Properties
    {
        [Header(UE5 MI_Water_Lake Authentic Parameters)]
//        [Tooltip("UE5 Water Absorption: 选你希望水透出来的颜色(如青蓝)，内部通过 (1 - Color) 算出吸收率")]
        _WaterAbsorptionColor ("Water Absorption (Color)", Color) = (0.06, 0.45, 0.65, 1.0)
//        [Tooltip("控制吸收发生的深度比例(米)，值越小水越快变黑")]
        _AbsorptionScale ("Absorption Scale (m)", Range(0.1, 50.0)) = 3.5

        [Space(10)]
//        [Tooltip("UE5 Water Scattering: 水体内部悬浮微粒散射出的颜色")]
        _WaterScatteringColor ("Water Scattering (Color)", Color) = (0.02, 0.22, 0.28, 1.0)
//        [Tooltip("散射强度缩放，值越大水越浑浊/亮，0则为纯清澈黑水")]
        _ScatteringScale ("Scattering Scale", Range(0.0, 2.0)) = 0.25

        [Space(10)]
//        [Tooltip("UE5 PhaseG: 各向异性散射 (-1 ~ 1)，正值会让迎着太阳看水体时内部发亮(透光感)")]
        _PhaseG ("Anisotropy PhaseG", Range(-0.9, 0.9)) = 0.25

        [Header(Refraction)]
        _RefractionStrength ("Refraction Distortion", Range(0.0, 0.2)) = 0.03
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
            Name "UE5SingleLayerWater"
            Tags { "LightMode" = "UniversalForward" }

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
                float _RefractionStrength;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float4 screenPos  : TEXCOORD2;
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

            // =================================================================
            // UE5 Henyey-Greenstein 相位函数 (复刻自 ParticipatingMediaCommon.ush)
            // 作用：当摄像机逆光看水面时，阳光穿透水波的体积散射会显著增强（翡翠透光感）
            // =================================================================
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

                // 1. 折射采样与前景防穿帮回退
                float2 refractOffset = normalWS.xz * _RefractionStrength;
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
                // 2. 转换 UE5 材质面板参数为 SingleLayerWater 底层物理系数
                // =============================================================
                // [UE5 原版转换]：吸收系数 = (1 - 颜色) / 距离缩放
                float3 absorptionCoeff = (1.0 - saturate(_WaterAbsorptionColor.rgb)) / max(_AbsorptionScale, 0.001);
                
                // [UE5 原版转换]：散射系数 = 散射颜色 * 强度缩放
                float3 scatteringCoeff = saturate(_WaterScatteringColor.rgb) * _ScatteringScale;

                // [UE5 核心]：总消光系数 Extinction = Absorption + Scattering
                float3 extinctionCoeff = max(absorptionCoeff + scatteringCoeff, 1e-5);

                // [UE5 核心]：单次散射反照率 (Single Scattering Albedo = sigma_s / sigma_t)
                // 决定水体消光后究竟是偏黑(吸收占优)还是偏浑浊发亮(散射占优)
                float3 scatteringAlbedo = scatteringCoeff / extinctionCoeff;

                // =============================================================
                // 3. 求解 SingleLayerWater 体积传输方程
                // =============================================================
                // 光线在水下经过的总光学路径 (视线长度 + 阳光入射深度)
                float opticalDepth = viewDepth + verticalDepth;

                // 比尔-朗伯总透过率 T = exp(-Extinction * Depth)
                half3 transmittance = exp(-extinctionCoeff * opticalDepth);

                // 计算相位函数 (太阳方向与视线方向的夹角决定前向透射亮点)
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));
                // 光线从太阳射入水中的方向为 -mainLight.direction，传向眼睛的方向为 viewDirWS
                float cosTheta = dot(-mainLight.direction, viewDirWS);
                // 乘以 4*PI 归一化相位增益，使其在 g=0 时基准为 1.0
                float phaseFunction = HenyeyGreensteinPhase(_PhaseG, cosTheta) * (4.0 * PI);

                // 水体接收到的环境光(SH) + 主光源(含阴影与相位调制)
                half3 waterIncomingLight = SampleSH(float3(0, 1, 0)) 
                                         + mainLight.color * mainLight.shadowAttenuation * phaseFunction;

                // [UE5 最终水下合成方程]：
                // 水底透射项 = 水底原色 * Transmittance
                half3 transmittedSceneColor = sceneColorBehindWater * transmittance;

                // 水体散射项 = 入射光 * 散射反照率(sigma_s / sigma_t) * (1 - Transmittance)
                half3 inScatteredLuminance = waterIncomingLight * scatteringAlbedo * (1.0 - transmittance);

                half3 finalWaterVolumeColor = transmittedSceneColor + inScatteredLuminance;

                return half4(finalWaterVolumeColor, 1.0);
            }
            ENDHLSL
        }
    }
}