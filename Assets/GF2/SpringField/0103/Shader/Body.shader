Shader "GF2/CharacterBody_MRT_URP"
{
    Properties
    {
        [Header(Base Textures)]
        _BaseMap ("Base Map (Color SRGB)", 2D) = "white" {}
        _BaseColor ("Base Color Tint", Color) = (1, 1, 1, 1)
        
        [NoScaleOffset] _NormalMap ("Normal Map (Linear, R*A & 1-G)", 2D) = "bump" {}
        _NormalScale ("Normal Scale", Range(0, 2)) = 1.0
        
        [NoScaleOffset] _RMOTex ("RMO (R:Rough, G:Metal, B:AO, A:Extra)", 2D) = "white" {}
        [NoScaleOffset] _RampMap ("Ramp Map (256x16 Linear RGBAHalf)", 2D) = "white" {}

        [Header(Material Controls)]
        _RoughnessScale ("Roughness Scale", Range(0, 2)) = 1.0
        _MetallicScale ("Metallic Scale", Range(0, 2)) = 1.0
        _AOStrength ("AO Strength", Range(0, 1)) = 1.0
        _SpecularScale ("Specular Ramp Scale", Range(0, 3)) = 1.0
        _EnvBRDFScale ("Env BRDF Ramp Scale", Range(0, 2)) = 1.0
        
        [Header(Extra Emission and Post Buffer)]
        _ExtraColor ("Extra Color (RMO.A)", Color) = (1, 1, 1, 1)
        _ExtraIntensity ("Extra Intensity", Range(0, 5)) = 0.0
        _BloomWeightParam ("Bloom Weight Param (RT1.A)", Range(-1, 1)) = 0.0

        [Header(Outline Pass)]
        _OutlineColor ("Outline Color", Color) = (0.15, 0.12, 0.12, 1.0)
        _OutlineWidth ("Outline Width (px)", Range(0, 10)) = 2.0
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Geometry" 
        }

        // =========================================================================
        // Pass 1: 核心前向光照 + 双 MRT 输出 (RT0: HDR颜色, RT1: 八面体几何法线+角色标记)
        // =========================================================================
        Pass
        {
            Name "ForwardLitMRT"
            Tags { "LightMode" = "GF2ForwardMRT" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2; // 原始几何法线（不经 NormalMap 扰动，专供 RT1）
                float4 tangentWS   : TEXCOORD3;
            };

            // 双 MRT 输出结构体（已移除 TAA 所需的 SV_Target2 Velocity）
            struct FragOutput
            {
                half4 rt0_HDRColor   : SV_Target0; // RGBA16F: 光照后的 HDR 颜色
                half4 rt1_NormalFlag : SV_Target1; // RGBA8:   RG=八面体几何法线, B=0.498角色标记, A=Bloom权重
            };

            TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);  SAMPLER(sampler_NormalMap);
            TEXTURE2D(_RMOTex);     SAMPLER(sampler_RMOTex);
            TEXTURE2D(_RampMap);    SAMPLER(sampler_RampMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _NormalScale;
                half _RoughnessScale;
                half _MetallicScale;
                half _AOStrength;
                half _SpecularScale;
                half _EnvBRDFScale;
                half4 _ExtraColor;
                half _ExtraIntensity;
                half _BloomWeightParam;
                half4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.normalWS = normInputs.normalWS;
                output.tangentWS = float4(normInputs.tangentWS, input.tangentOS.w);
                return output;
            }

            // 1. 专属贴图法线解包：R*A 与 1-G（仅用于着色光照，不写入 RT1）
            float3 UnpackGF2Normal(float4 nSample, float scale)
            {
                float2 xy = float2(nSample.r * nSample.a, 1.0 - nSample.g) * 2.0 - 1.0;
                xy *= scale;
                float z = sqrt(saturate(1.0 - dot(xy, xy)));
                return float3(xy, z);
            }

            // 2. PS 4777 指令 465-472 还原：几何法线 L1 归一化 + 负半球折叠八面体编码 -> [0, 1]
            float2 EncodeOctahedronNormal(float3 n)
            {
                n = normalize(n);
                // L1 归一化投影到八面体
                n /= (abs(n.x) + abs(n.y) + abs(n.z));
                // 负半球折叠
                if (n.z < 0.0)
                {
                    float2 signNotZero = float2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
                    n.xy = (1.0 - abs(n.yx)) * signNotZero;
                }
                // 映射至 [0, 1] 写入 RGBA8
                return n.xy * 0.5 + 0.5;
            }

            // 3. 四带 Ramp 采样
            half3 SampleRampBand(float u, float vCenter)
            {
                return SAMPLE_TEXTURE2D_LOD(_RampMap, sampler_RampMap, float2(saturate(u), vCenter), 0).rgb;
            }

            // 4. 微表面高光近似
            float CalcGGXSpecular(float NdotH, float NdotL, float NdotV, float roughness)
            {
                float a = max(roughness * roughness, 0.002);
                float a2 = a * a;
                float d = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                float D = a2 / (PI * d * d + 1e-6);

                float k = (roughness + 1.0);
                k = (k * k) / 8.0;
                float G_V = NdotV / (NdotV * (1.0 - k) + k);
                float G_L = NdotL / (NdotL * (1.0 - k) + k);
                return (D * G_V * G_L) / max(4.0 * NdotV * NdotL, 0.001);
            }

            FragOutput frag(Varyings input)
            {
                FragOutput output;

                // --- A. 贴图采样与解包 ---
                half4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseSample.rgb * _BaseColor.rgb;

                half4 rmo = SAMPLE_TEXTURE2D(_RMOTex, sampler_RMOTex, input.uv);
                half roughness = saturate(rmo.r * _RoughnessScale);
                half metallic  = saturate(rmo.g * _MetallicScale);
                half ao        = lerp(1.0h, rmo.b, _AOStrength);
                half extraMask = rmo.a;

                // 凹凸法线（仅参与光照计算）
                float4 nSample = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv);
                float3 normalTS = UnpackGF2Normal(nSample, _NormalScale);
                float3 geomNormalWS = normalize(input.normalWS); // 保留未扰动的几何法线
                float3 bitangentWS = cross(geomNormalWS, input.tangentWS.xyz) * input.tangentWS.w;
                float3x3 TBN = float3x3(input.tangentWS.xyz, bitangentWS, geomNormalWS);
                float3 shadedNormalWS = normalize(mul(normalTS, TBN));

                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float NdotV = saturate(dot(shadedNormalWS, viewDirWS));

                half3 diffuseColor = baseColor * (1.0h - metallic);
                half3 F0 = lerp(half3(0.04h, 0.04h, 0.04h), baseColor, metallic);

                // --- B. 主光计算 (V=0.125 漫反射 & V=0.375 高光) ---
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float3 lightDirWS = normalize(mainLight.direction);
                float3 halfDir = normalize(lightDirWS + viewDirWS);

                float NdotL = saturate(dot(shadedNormalWS, lightDirWS));
                float NdotH = saturate(dot(shadedNormalWS, halfDir));
                float LdotH = saturate(dot(lightDirWS, halfDir));
                float atten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;

                float mainDiffInput = NdotL * atten;
                half3 mainDiffRamp = SampleRampBand(mainDiffInput, 0.125);
                half3 mainDiffuse = diffuseColor * mainDiffRamp * mainLight.color;

                float rawSpec = CalcGGXSpecular(NdotH, NdotL, NdotV, roughness);
                half3 specRamp = SampleRampBand(saturate(rawSpec * 0.25), 0.375) * _SpecularScale;
                half3 F = F0 + (1.0h - F0) * pow(1.0h - LdotH, 5.0h);
                half3 mainSpecular = specRamp * F * mainLight.color * mainDiffInput;

                // --- C. 环境光照与反射探针 (V=0.625) ---
                half3 sh = SampleSH(shadedNormalWS);
                half3 indirectDiffuse = sh * diffuseColor * ao;

                float3 reflDir = reflect(-viewDirWS, shadedNormalWS);
                half3 envColor = GlossyEnvironmentReflection(reflDir, roughness, ao);
                half3 envRamp = SampleRampBand(NdotV, 0.625) * _EnvBRDFScale;
                half3 envFresnel = F0 + (max(half3(1.0h - roughness, 1.0h - roughness, 1.0h - roughness), F0) - F0) * pow(1.0h - NdotV, 5.0h);
                half3 indirectSpecular = envColor * envFresnel * envRamp;

                // --- D. 附加光循环 (V=0.875 漫反射 & V=0.375 高光) ---
                half3 addLightsTotal = half3(0, 0, 0);
                #ifdef _ADDITIONAL_LIGHTS
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light addLight = GetAdditionalLight(lightIndex, input.positionWS);
                    float addNdotL = saturate(dot(shadedNormalWS, addLight.direction));
                    float addAtten = addLight.shadowAttenuation * addLight.distanceAttenuation;
                    float addInput = addNdotL * addAtten;

                    half3 addDiffRamp = SampleRampBand(addInput, 0.875);
                    half3 addDiff = diffuseColor * addDiffRamp * addLight.color;

                    float3 addHalf = normalize(addLight.direction + viewDirWS);
                    float addNdotH = saturate(dot(shadedNormalWS, addHalf));
                    float addRawSpec = CalcGGXSpecular(addNdotH, addNdotL, NdotV, roughness);
                    half3 addSpecRamp = SampleRampBand(saturate(addRawSpec * 0.25), 0.375) * _SpecularScale;
                    half3 addSpec = addSpecRamp * F0 * addLight.color * addInput;

                    addLightsTotal += (addDiff + addSpec);
                }
                #endif

                // --- E. 附加发光项 ---
                half3 extraColor = baseColor * _ExtraColor.rgb * _ExtraIntensity * extraMask;
                half3 finalHDR = mainDiffuse + mainSpecular + indirectDiffuse + indirectSpecular + addLightsTotal + extraColor;

                // --- F. 组装双 MRT 输出 ---
                // RT0: 最终 HDR 颜色
                output.rt0_HDRColor = half4(finalHDR, 1.0h);

                // RT1: 几何法线八面体编码(RG) + 0.498角色排除标记(B) + Bloom权重(A)
                float2 octNormal = EncodeOctahedronNormal(geomNormalWS);
                half bloomWeight = 0.5h - 0.5h * _BloomWeightParam; // PS 4777 指令 475
                output.rt1_NormalFlag = half4(octNormal.x, octNormal.y, 0.498h, bloomWeight);

                return output;
            }
            ENDHLSL
        }

        // =========================================================================
        // Pass 2: 几何描边 Pass (同样写入双 MRT，B 通道标记为 0.499)
        // =========================================================================
        Pass
        {
            Name "OutlineMRT"
            Tags { "LightMode" = "GF2OutlineMRT" }

            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vertOutline
            #pragma fragment fragOutline

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

            struct FragOutput
            {
                half4 rt0_HDRColor   : SV_Target0;
                half4 rt1_NormalFlag : SV_Target1;
            };

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _NormalScale;
                half _RoughnessScale;
                half _MetallicScale;
                half _AOStrength;
                half _SpecularScale;
                half _EnvBRDFScale;
                half4 _ExtraColor;
                half _ExtraIntensity;
                half _BloomWeightParam;
                half4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

            float2 EncodeOctahedronNormal(float3 n)
            {
                n = normalize(n);
                n /= (abs(n.x) + abs(n.y) + abs(n.z));
                if (n.z < 0.0)
                {
                    float2 signNotZero = float2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
                    n.xy = (1.0 - abs(n.yx)) * signNotZero;
                }
                return n.xy * 0.5 + 0.5;
            }

            Varyings vertOutline(Attributes input)
            {
                Varyings output;
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 normalCS = TransformWorldToHClipDir(normalWS);

                float2 offset = normalize(normalCS.xy) * (_OutlineWidth * input.color.a) * posInputs.positionCS.w * 2.0 / _ScreenParams.xy;
                posInputs.positionCS.xy += offset;

                output.positionCS = posInputs.positionCS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.normalWS = normalWS;
                return output;
            }

            FragOutput fragOutline(Varyings input)
            {
                FragOutput output;
                half3 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 finalOutline = lerp(_OutlineColor.rgb, baseColor * _OutlineColor.rgb, 0.5h);

                output.rt0_HDRColor = half4(finalOutline, 1.0h);

                // PS 4723: 描边同样写八面体法线，B 通道写入 0.499（同样 >= 0.495，免受全屏 AO 干扰）
                float2 octNormal = EncodeOctahedronNormal(input.normalWS);
                half bloomWeight = 0.5h - 0.5h * _BloomWeightParam;
                output.rt1_NormalFlag = half4(octNormal.x, octNormal.y, 0.499h, bloomWeight);
                return output;
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}