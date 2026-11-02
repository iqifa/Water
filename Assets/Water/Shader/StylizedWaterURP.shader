Shader "Custom/StylizedWaterURP"
{
    Properties
    {
        // ---- 波形 (保留 Gerstner 位移, 风格化也需要形体) ----
        _WaveCount ("Wave Count (波数量)", Range(1, 64)) = 8
        _SpeedMultiplier ("Speed Multiplier (整体速度)", Range(0, 3)) = 0.5

        // ---- 风格化三色阶 (EVA LCL 配色) ----
        _ShallowColor ("Shallow Band (浅水色阶)", Color) = (1.0, 0.72, 0.25, 1)
        _MidColor ("Mid Band (中水色阶)", Color) = (0.92, 0.45, 0.12, 1)
        _DeepColor ("Deep Band (深水色阶)", Color) = (0.45, 0.16, 0.05, 1)
        _BandSmoothness ("Band Smoothness (色阶过渡柔和度, 0=硬切)", Range(0.001, 0.5)) = 0.05
        _ShallowBandStart ("Shallow Band Start (浅阶深度)", Range(0, 2)) = 0.15
        _DeepBandStart ("Deep Band Start (深阶深度)", Range(0, 5)) = 0.8

        // ---- 岸线泡沫描边 (深度图阈值) ----
        _ShoreFoamColor ("Shore Foam Color (岸线泡沫色)", Color) = (1.0, 0.85, 0.6, 1)
        _ShoreFoamWidth ("Shore Foam Width (岸线宽度)", Range(0, 1)) = 0.25
        _ShoreFoamNoiseScale ("Shore Foam Noise Scale (泡沫噪声密度)", Range(0, 50)) = 12
        _ShoreFoamSpeed ("Shore Foam Speed (泡沫流速)", Range(0, 2)) = 0.5

        // ---- 波峰泡沫 ----
        _TipColor ("Tip Foam Color (浪尖白沫色)", Color) = (1.0, 0.85, 0.6, 1)
        _TipThreshold ("Tip Threshold (浪尖阈值)", Range(0, 1)) = 0.75
        _TipSpread ("Tip Spread (浪尖过渡)", Range(0.01, 1)) = 0.15
        _TipNoiseScale ("Tip Noise Scale (浪尖噪声密度)", Range(0, 50)) = 8

        // ---- 简化菲涅尔视野反光 ----
        _ViewGlowColor ("View Glow Color (视野反光色)", Color) = (1.0, 0.8, 0.5, 1)
        _ViewGlowPower ("View Glow Power (反光聚拢度)", Range(1, 16)) = 6
        _ViewGlowStrength ("View Glow Strength (反光强度)", Range(0, 1)) = 0.5

        // ---- 高光 ----
        _SpecularColor ("Specular Color (高光色)", Color) = (1.0, 0.9, 0.65, 1)
        _SpecularSize ("Specular Size (高光大小)", Range(8, 256)) = 64
        _SpecularStrength ("Specular Strength (高光强度)", Range(0, 4)) = 1.8
        _GlitterStrength ("Glitter Strength (闪点强度)", Range(0, 1)) = 0.35

        _SteepnessScale ("Steepness Scale", Float) = 1
        [HideInInspector] _DebugMode ("Debug Mode", Float) = 0
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #define PI 3.14159265
            #define GRAVITY 9.8

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float4 screenPos : TEXCOORD4;
                float3 restPosWS : TEXCOORD5;
            };

            StructuredBuffer<float4> _Waves;       // x=dir.x, y=dir.z, z=波长, w=振幅
            StructuredBuffer<float2> _Steepnesses; // x=陡峭度, y=相位

            CBUFFER_START(UnityPerMaterial)
                int _WaveCount;
                float _SpeedMultiplier;
                float _SteepnessScale;

                float4 _ShallowColor, _MidColor, _DeepColor;
                float _BandSmoothness, _ShallowBandStart, _DeepBandStart;

                float4 _ShoreFoamColor;
                float _ShoreFoamWidth, _ShoreFoamNoiseScale, _ShoreFoamSpeed;

                float4 _TipColor;
                float _TipThreshold, _TipSpread, _TipNoiseScale;

                float4 _ViewGlowColor;
                float _ViewGlowPower, _ViewGlowStrength;

                float4 _SpecularColor;
                float _SpecularSize, _SpecularStrength, _GlitterStrength;

                float _DebugMode;
            CBUFFER_END

            // ---- 值噪声 (风格化泡沫破碎用, 无贴图依赖) ----
            float2 hash22(float2 p)
            {
                float3 p3 = frac(p.xyx * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xx + p3.yz) * p3.zy);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f); // smoothstep 插值
                float a = hash22(i).x;
                float b = hash22(i + float2(1, 0)).x;
                float c = hash22(i + float2(0, 1)).x;
                float d = hash22(i + float2(1, 1)).x;
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            // 滚动噪声 (泡沫动画的核心: 时间偏移两层噪声交叉)
            float foamNoise(float2 uv, float t)
            {
                float n1 = valueNoise(uv + float2(t, t * 0.6));
                float n2 = valueNoise(uv * 1.7 - float2(t * 0.7, t * 0.3));
                return n1 * 0.6 + n2 * 0.4;
            }

            // ---- Gerstner 位移 (与物理版同款) ----
            void EvaluateGerstner(float2 p, inout float3 offset, inout float2 slope, inout float zSlope)
            {
                [loop]
                for (int i = 0; i < _WaveCount; i++)
                {
                    float4 wave = _Waves[i];
                    float2 d = wave.xy;
                    float wavelength = max(wave.z, 0.01);
                    float amplitude = wave.w;
                    float steep = _Steepnesses[i].x * _SteepnessScale;

                    float dispersion = 2.0 * PI / wavelength;
                    float wavespeed = sqrt(dispersion * GRAVITY);
                    float phase = dispersion * dot(d, p) - wavespeed * _Time.y * _SpeedMultiplier;

                    float waveSin = sin(phase);
                    float waveCos = cos(phase);

                    float wKA = amplitude * dispersion;
                    float q = steep / max(wKA, 0.001);

                    offset.xz += -q * waveSin * d * amplitude;
                    offset.y += waveCos * amplitude;

                    slope += waveSin * wKA * d;
                    zSlope += waveCos * steep * saturate(amplitude * 50.0 / wavelength);
                }
            }

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                float3 restPosWS = TransformObjectToWorld(input.positionOS.xyz);

                float3 offset = float3(0, 0, 0);
                float2 slope = float2(0, 0);
                float zSlope = 0.0;
                EvaluateGerstner(restPosWS.xz, offset, slope, zSlope);

                float3 positionWS = restPosWS + offset;

                output.restPosWS = restPosWS;
                output.positionWS = positionWS;
                output.positionCS = TransformWorldToHClip(positionWS);
                output.screenPos = ComputeScreenPos(output.positionCS);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // ---- 法线 & 浪高 (静坐标逐像素, 与物理版同款) ----
                float3 offset = float3(0, 0, 0);
                float2 slope = float2(0, 0);
                float zSlope = 0.0;
                float ampSum = 0.0;

                EvaluateGerstner(input.restPosWS.xz, offset, slope, zSlope);
                [loop]
                for (int i = 0; i < _WaveCount; i++) ampSum += _Waves[i].w;

                float3 normal = normalize(float3(slope.x, 1.0 - zSlope, slope.y));
                float waveHeight = offset.y / max(ampSum, 0.001);

                // ---- 深度差 (岸线泡沫和色阶都靠它) ----
                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float surfaceDepth = input.screenPos.w;
                float rawSceneDepth = SampleSceneDepth(screenUV);
                float sceneDepth = LinearEyeDepth(rawSceneDepth, _ZBufferParams);
                float depthDiff = max(0.0, sceneDepth - surfaceDepth);

                // ---- 1. 三色阶 (smoothstep 柔和分带, 0 时硬切) ----
                float band1 = smoothstep(_ShallowBandStart - _BandSmoothness, _ShallowBandStart + _BandSmoothness, depthDiff);
                float band2 = smoothstep(_DeepBandStart - _BandSmoothness, _DeepBandStart + _BandSmoothness, depthDiff);
                float3 waterColor = lerp(lerp(_ShallowColor.rgb, _MidColor.rgb, band1), _DeepColor.rgb, band2);

                // ---- 2. 岸线泡沫描边 ----
                float foamN = foamNoise(input.restPosWS.xz * _ShoreFoamNoiseScale * 0.1, _Time.y * _ShoreFoamSpeed);
                // 噪声把泡沫边缘咬碎成不规则的絮状
                float shoreMask = smoothstep(_ShoreFoamWidth, _ShoreFoamWidth * 0.3, depthDiff + foamN * 0.12);
                float3 shoreFoam = _ShoreFoamColor.rgb * shoreMask;

                // ---- 3. 浪尖泡沫 (归一化浪高 + 噪声破碎) ----
                float tipN = foamNoise(input.restPosWS.xz * _TipNoiseScale * 0.1 + 17.3, _Time.y * 0.3);
                float tipMask = smoothstep(_TipThreshold, _TipThreshold + _TipSpread, waveHeight + (tipN - 0.5) * 0.3);
                float3 tipFoam = _TipColor.rgb * tipMask;

                // ---- 4. 视野反光 (简化菲涅尔: 风格化不受物理曲线束缚) ----
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - input.positionWS);
                float NdotV = saturate(dot(viewDir, normal));
                float viewGlow = pow(1.0 - NdotV, _ViewGlowPower) * _ViewGlowStrength;
                // 反光也用噪声轻微破碎, 避免像油膜
                viewGlow *= 0.8 + 0.4 * foamNoise(input.restPosWS.xz * 3.0, _Time.y * 0.2);

                // ---- 5. 高光 + 闪点 ----
                Light mainLight = GetMainLight();
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float NdotH = saturate(dot(normal, halfDir));
                float3 specular = _SpecularColor.rgb * pow(NdotH, _SpecularSize) * _SpecularStrength;

                // 闪点: 高频噪声做锐利亮斑, 太阳下的碎钻感
                float glitter = step(0.97, foamNoise(input.restPosWS.xz * 40.0, _Time.y * 1.5)) * _GlitterStrength;

                // ---- 融合 ----
                float3 finalColor = waterColor + viewGlow * _ViewGlowColor.rgb;
                finalColor = lerp(finalColor, _ShoreFoamColor.rgb, shoreMask);
                finalColor += tipFoam + specular + glitter * _SpecularColor.rgb;

                // ---- 调试模式 ----
                UNITY_BRANCH
                if (_DebugMode > 0.5)
                {
                    if (_DebugMode < 1.5)      return half4(normal * 0.5 + 0.5, 1);
                    else if (_DebugMode < 2.5) return half4((depthDiff * 0.5).xxx, 1);
                    else if (_DebugMode < 3.5) return half4(shoreMask.xxx, 1);
                    else if (_DebugMode < 4.5) return half4(tipMask.xxx, 1);
                    else if (_DebugMode < 5.5) return half4(waterColor, 1);
                    else if (_DebugMode < 6.5) return half4((viewGlow).xxx, 1);
                }

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
