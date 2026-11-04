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
            #include "Assets/Water/Shader/WaterVolumeLighting.hlsl"

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

            half4 frag(Varyings input) : SV_Target
            {
                float2 baseScreenUV = input.screenPos.xy / input.screenPos.w;
                float surfaceEyeDepth = input.screenPos.w;
                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

                // =============================================================
                // 水体体积渲染 (统一走 WaterVolumeLighting.hlsl)
                // =============================================================
                float2 refractedUV;
                float viewDepth, verticalDepth;
                WaterSampleRefraction(baseScreenUV, surfaceEyeDepth, input.positionWS,
                    normalWS, _RefractionStrength, _RefractionFadeDepth,
                    refractedUV, viewDepth, verticalDepth);

                half3 sceneColorBehindWater = SampleSceneColor(refractedUV);

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));

                half3 finalWaterVolumeColor = WaterVolumeShading(
                    sceneColorBehindWater,
                    viewDepth, verticalDepth,
                    normalWS, viewDirWS, mainLight,
                    _WaterAbsorptionColor.rgb, _AbsorptionScale,
                    _WaterScatteringColor.rgb, _ScatteringScale,
                    _PhaseG, _SunGlowIntensity);

                return half4(finalWaterVolumeColor, 1.0);
            }
            ENDHLSL
        }
    }
}