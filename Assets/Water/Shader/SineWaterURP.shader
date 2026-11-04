Shader "Custom/SineWaterURP"
{
    Properties
    {
        _WaveCount ("Wave Count", Range(1, 64)) = 4
        _UseFBM ("Use FBM", Float) = 0

        // FBM Vertex Parameters
        _VertexWaveCount ("Vertex Wave Count", Range(1, 64)) = 8
        _VertexSeed ("Vertex Seed", Float) = 0
        _VertexSeedIter ("Vertex Seed Iterator", Float) = 1253.2131
        _VertexFrequency ("Vertex Frequency", Float) = 1.0
        _VertexFrequencyMult ("Vertex Frequency Mult", Float) = 1.18
        _VertexAmplitude ("Vertex Amplitude", Float) = 1.0
        _VertexAmplitudeMult ("Vertex Amplitude Mult", Float) = 0.82
        _VertexMaxPeak ("Vertex Max Peak", Float) = 1.0
        _VertexPeakOffset ("Vertex Peak Offset", Float) = 1.0
        _VertexInitialSpeed ("Vertex Initial Speed", Float) = 2.0
        _VertexSpeedRamp ("Vertex Speed Ramp", Float) = 1.07
        _VertexDrag ("Vertex Drag", Float) = 1.0
        _VertexHeight ("Vertex Height", Float) = 1.0

        // FBM Fragment Parameters
        _FragmentWaveCount ("Fragment Wave Count", Range(1, 64)) = 40
        _FragmentSeed ("Fragment Seed", Float) = 0
        _FragmentSeedIter ("Fragment Seed Iterator", Float) = 1253.2131
        _FragmentFrequency ("Fragment Frequency", Float) = 1.0
        _FragmentFrequencyMult ("Fragment Frequency Mult", Float) = 1.18
        _FragmentAmplitude ("Fragment Amplitude", Float) = 1.0
        _FragmentAmplitudeMult ("Fragment Amplitude Mult", Float) = 0.82
        _FragmentMaxPeak ("Fragment Max Peak", Float) = 1.0
        _FragmentPeakOffset ("Fragment Peak Offset", Float) = 1.0
        _FragmentInitialSpeed ("Fragment Initial Speed", Float) = 2.0
        _FragmentSpeedRamp ("Fragment Speed Ramp", Float) = 1.07
        _FragmentDrag ("Fragment Drag", Float) = 1.0
        _FragmentHeight ("Fragment Height", Float) = 1.0
        _NormalStrength ("Normal Strength", Float) = 1.0

        // Material Properties
        _FresnelColor ("Fresnel / Sky Color", Color) = (0.7, 0.85, 0.95, 1)
        _FresnelPower ("Fresnel Power", Float) = 5.0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.95
        _SpecularStrength ("Specular Strength", Range(0, 5)) = 1.0
        // 浪尖白沫参数
        _TipColor ("Tip Color", Color) = (1, 1, 1, 1)
        _TipThreshold ("Tip Min Height (生成起始高度)", Float) = 0.5
        _TipSpread ("Tip Spread (过渡范围/宽度)", Float) = 0.2

        // 关键新增：水下与折射参数 (与 GerstnerWater 统一走 WaterVolumeLighting.hlsl)
        _WaterAbsorptionColor ("Water Absorption (Shallow Color)", Color) = (0.15, 0.88, 0.78, 1.0)
        _AbsorptionScale ("Clarity Depth Scale (m)", Range(0.5, 50.0)) = 8.0
        _WaterScatteringColor ("Water Scattering (Deep Color)", Color) = (0.04, 0.42, 0.68, 1.0)
        _ScatteringScale ("Scattering Brightness", Range(0.0, 3.0)) = 1.2
        _PhaseG ("Sun Forward Scatter (PhaseG)", Range(0.0, 0.9)) = 0.45
        _SunGlowIntensity ("Sun Glow Intensity", Range(0.0, 5.0)) = 1.5
        _RefractionStrength ("Refraction Strength (折射强度)", Range(0, 0.2)) = 0.02
        _RefractionFadeDepth ("Refraction Fade Depth (m)", Range(0.01, 2.0)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Transparent"
            "Queue"="Transparent"
            "RenderPipeline"="UniversalPipeline"
        }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Assets/Water/Shader/WaterVolumeLighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 viewDirWS : TEXCOORD2;
                float waveHeight : TEXCOORD3;
                float4 screenPos : TEXCOORD4;
            };

            struct Wave
            {
                float2 direction;
                float2 origin;
                float frequency;
                float amplitude;
                float phase;
                float steepness;
                int waveType;
            };

            StructuredBuffer<Wave> _Waves;

            CBUFFER_START(UnityPerMaterial)
                int _WaveCount;
                float _UseFBM;

                // FBM Vertex
                int _VertexWaveCount;
                float _VertexSeed, _VertexSeedIter, _VertexFrequency, _VertexFrequencyMult;
                float _VertexAmplitude, _VertexAmplitudeMult, _VertexMaxPeak, _VertexPeakOffset;
                float _VertexInitialSpeed, _VertexSpeedRamp, _VertexDrag, _VertexHeight;

                // FBM Fragment
                int _FragmentWaveCount;
                float _FragmentSeed, _FragmentSeedIter, _FragmentFrequency, _FragmentFrequencyMult;
                float _FragmentAmplitude, _FragmentAmplitudeMult, _FragmentMaxPeak, _FragmentPeakOffset;
                float _FragmentInitialSpeed, _FragmentSpeedRamp, _FragmentDrag, _FragmentHeight;
                float _NormalStrength;

                // Material
                float4 _FresnelColor;
                float _FresnelPower;
                float _Smoothness;
                float _SpecularStrength;
                float4 _TipColor;
                float _TipThreshold;
                float _TipSpread;

                // Underwater & Refraction (与 GerstnerWater 统一)
                float4 _WaterAbsorptionColor;
                float _AbsorptionScale;
                float4 _WaterScatteringColor;
                float _ScatteringScale;
                float _PhaseG;
                float _SunGlowIntensity;
                float _RefractionStrength;
                float _RefractionFadeDepth;
            CBUFFER_END

            float3 VertexFBM(float3 worldPos)
            {
                float f = _VertexFrequency;
                float a = _VertexAmplitude;
                float speed = _VertexInitialSpeed;
                float seed = _VertexSeed;
                float3 p = worldPos;
                float amplitudeSum = 0.0;
                float h = 0.0;

                for (int i = 0; i < _VertexWaveCount; i++)
                {
                    float2 d = normalize(float2(cos(seed), sin(seed)));
                    float x = dot(d, p.xz) * f + _Time.y * speed;
                    float wave = a * exp(_VertexMaxPeak * sin(x) - _VertexPeakOffset);
                    float dx = _VertexMaxPeak * wave * cos(x);

                    h += wave;
                    p.xz += d * (-dx) * a * _VertexDrag;

                    amplitudeSum += a;
                    f *= _VertexFrequencyMult;
                    a *= _VertexAmplitudeMult;
                    speed *= _VertexSpeedRamp;
                    seed += _VertexSeedIter;
                }

                float3 output = float3(h, 0, 0);
                if (amplitudeSum > 0.001)
                {
                    output /= amplitudeSum;
                }
                output.x *= _VertexHeight;
                return output;
            }

            float3 FragmentFBM(float3 worldPos)
            {
                float f = _FragmentFrequency;
                float a = _FragmentAmplitude;
                float speed = _FragmentInitialSpeed;
                float seed = _FragmentSeed;
                float3 p = worldPos;
                float h = 0.0;
                float2 n = 0.0;
                float amplitudeSum = 0.0;

                for (int i = 0; i < _FragmentWaveCount; i++)
                {
                    float2 d = normalize(float2(cos(seed), sin(seed)));
                    float x = dot(d, p.xz) * f + _Time.y * speed;
                    float wave = a * exp(_FragmentMaxPeak * sin(x) - _FragmentPeakOffset);
                    float2 dw = f * d * (_FragmentMaxPeak * wave * cos(x));

                    h += wave;
                    p.xz += -dw * a * _FragmentDrag;
                    n += dw;

                    amplitudeSum += a;
                    f *= _FragmentFrequencyMult;
                    a *= _FragmentAmplitudeMult;
                    speed *= _FragmentSpeedRamp;
                    seed += _FragmentSeedIter;
                }

                float3 output = float3(h, n.x, n.y);
                if (amplitudeSum > 0.001)
                {
                    output /= amplitudeSum;
                }
                output.x *= _FragmentHeight;
                return output;
            }

            float CalculateSineWave(float3 worldPos, Wave w)
            {
                float2 d = w.direction;
                float coord = dot(d, worldPos.xz);
                return w.amplitude * sin(coord * w.frequency + _Time.y * w.phase);
            }

            float3 CalculateSineNormal(float3 worldPos, Wave w)
            {
                float2 d = w.direction;
                float coord = dot(d, worldPos.xz);
                float2 n = w.frequency * w.amplitude * d * cos(coord * w.frequency + _Time.y * w.phase);
                return float3(n.x, 0, n.y);
            }

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 offset = float3(0, 0, 0);

                if (_UseFBM > 0.5)
                {
                    float3 fbm = VertexFBM(positionWS);
                    offset.y = fbm.x;
                }
                else
                {
                    for (int i = 0; i < _WaveCount; i++)
                    {
                        offset.y += CalculateSineWave(positionWS, _Waves[i]);
                    }
                }

                positionWS += offset;
                output.positionWS = positionWS;
                output.positionCS = TransformWorldToHClip(positionWS);
                output.waveHeight = offset.y;

                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.viewDirWS = GetWorldSpaceViewDir(positionWS);
                output.screenPos = ComputeScreenPos(output.positionCS);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // 1. 法线计算
                float3 normal = float3(0, 1, 0);
                float waveHeight = input.waveHeight;

                if (_UseFBM > 0.5)
                {
                    float3 fbm = FragmentFBM(input.positionWS);
                    waveHeight = fbm.x;
                    normal = normalize(float3(-fbm.y * _NormalStrength, 1.0, -fbm.z * _NormalStrength));
                }
                else
                {
                    float3 normalOffset = float3(0, 0, 0);
                    for (int i = 0; i < _WaveCount; i++)
                    {
                        waveHeight += CalculateSineWave(input.positionWS, _Waves[i]);
                        normalOffset += CalculateSineNormal(input.positionWS, _Waves[i]);
                    }
                    normal = normalize(float3(-normalOffset.x, 1.0, -normalOffset.z));
                }

                // 2. 折射采样与体积渲染 (统一走 WaterVolumeLighting.hlsl)
                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float surfaceDepth = input.screenPos.w;

                float2 refractUV;
                float viewDepth, verticalDepth;
                WaterSampleRefraction(screenUV, surfaceDepth, input.positionWS,
                    normal, _RefractionStrength, _RefractionFadeDepth,
                    refractUV, viewDepth, verticalDepth);

                half3 sceneColor = SampleSceneColor(refractUV);

                // 3. 双程消光 + 内散射 (与 GerstnerWater 同一套模型)
                Light mainLight = GetMainLight();
                float3 lightDir = mainLight.direction;
                float3 viewDir = normalize(input.viewDirWS);

                half3 underwaterFinal = WaterVolumeShading(
                    sceneColor,
                    viewDepth, verticalDepth,
                    normal, viewDir, mainLight,
                    _WaterAbsorptionColor.rgb, _AbsorptionScale,
                    _WaterScatteringColor.rgb, _ScatteringScale,
                    _PhaseG, _SunGlowIntensity);

                // 菲涅尔效应 (垂直看透明，平视看反光)
                float NdotV = saturate(dot(viewDir, normal));
                float fresnel = pow(1.0 - NdotV, _FresnelPower);
                fresnel = clamp(fresnel, 0.02, 1.0); // 水的基底反射率约 0.02

                // 镜面高光 (太阳光斑)
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotH = saturate(dot(normal, halfDir));
                float spec = pow(NdotH, _Smoothness * 256.0 + 1.0);
                float3 specular = mainLight.color * spec * _SpecularStrength;

                // 浪尖白沫
                float foamMask = smoothstep(_TipThreshold, _TipThreshold + _TipSpread, waveHeight);
                // float foamMask=step(_TipThreshold,waveHeight); 
                float3 tipColor = _TipColor.rgb * foamMask;

                // 5. 最终物理融合 (折射透水 + 菲涅尔反射 + 高光 + 白沫)
                float3 surfaceReflection = _FresnelColor.rgb * mainLight.color;
                float3 finalColor = lerp(underwaterFinal, surfaceReflection, fresnel) + specular + tipColor;

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // Shadow caster pass
        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode"="ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}