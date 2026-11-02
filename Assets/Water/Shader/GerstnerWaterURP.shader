Shader "Custom/GerstnerWaterURP"
{
    Properties
    {
        // ==================== 功能开关 (每块独立) ====================
        [Toggle] _VertexDisplaceOn ("[波] 顶点位移", Float) = 1
        [Toggle] _ShoreAttenOn    ("[波] 岸边浪衰减 (UE TargetWaveMaskDepth)", Float) = 1
        [Toggle] _RefractionOn    ("[折射] 屏幕空间折射", Float) = 1
        [Toggle] _ScatterOn       ("[散射] 水体散射/吸收 (Beer-Lambert)", Float) = 1
        [Toggle] _FresnelOn       ("[菲涅尔] 反射率混合", Float) = 1
        [Toggle] _SpecularOn      ("[高光] 太阳镜面高光 (GGX)", Float) = 1
        [Toggle] _TipFoamOn       ("[泡沫] 浪尖白沫", Float) = 1
        [Toggle] _ShoreFoamOn     ("[泡沫] 岸边/物体边缘浮沫", Float) = 1
        [Toggle] _SSROn           ("[反射] SSR 屏幕空间反射", Float) = 1
        [Toggle] _PlanarOn        ("[反射] 平面镜面反射", Float) = 1

        // ==================== 波浪生成 ====================
        _WaveCount ("Wave Count (波数量)", Range(1, 64)) = 16
        _LowFrequencyMaxIndex ("Low Freq Max Index (低频档末尾索引)", Range(1, 64)) = 4
        _MiddleFrequencyMaxIndex ("Middle Freq Max Index (中频档末尾索引)", Range(1, 64)) = 10
        _NormalStrength ("Normal Strength (波纹法线强度)", Range(0, 2)) = 1.0
        _SpeedMultiplier ("Speed Multiplier (整体速度, 1=UE 原始物理)", Range(0, 3)) = 1
        // UE 按频率分档 (老版 .ush 的 GetPerFrequencyGerstnerWavesNew):
        // 低/中频段动顶点形成涌浪, 高频段只在像素算法线 (细节浪清晰不闪)
        _SteepnessScale ("Steepness Scale (打结防护)", Float) = 1
        _HorizontalBoost ("Horizontal Boost (水平摆动增幅 1=标准)", Range(0, 4)) = 1

        // ==================== 岸边浪衰减 ====================
        _WaveMaskDepth ("Wave Mask Depth (岸边浪衰减深度, 米)", Range(0.05, 5)) = 1.2

        // ==================== 菲涅尔 ====================
        _FresnelColor ("Fresnel / Sky Color", Color) = (0.7, 0.85, 0.95, 1)
        _FresnelBase ("Fresnel Base F0 (基底反射率, 水=0.02)", Range(0.005, 0.2)) = 0.02
        // 菲涅尔专用平滑法线强度: 0=完全平滑(只看大形状), 1=跟细节法线一致
        _FresnelNormalStrength ("Fresnel Normal Strength", Range(0, 1)) = 0.2

        // ==================== 高光 ====================
        _Smoothness ("Smoothness", Range(0, 1)) = 0.95
        _SpecularStrength ("Specular Strength", Range(0, 5)) = 1.0

        // ==================== 浪尖泡沫 ====================
        _TipColor ("Tip Color", Color) = (1, 1, 1, 1)
        _TipThreshold ("Tip Min Height (0.9=只有最高峰出沫)", Range(0, 1)) = 0.9
        _TipSpread ("Tip Spread (过渡范围/宽度)", Float) = 0.2

        // ==================== 岸边/物体边缘泡沫 ====================
        _ShoreFoamColor ("Shore Foam Color", Color) = (1, 1, 1, 1)
        _ShoreFoamDistance ("Shore Foam Distance (浮沫带宽, 米)", Range(0.05, 3)) = 0.5
        _ShoreFoamScale ("Foam Noise Scale (噪声斑尺寸, 米)", Range(0.1, 2)) = 0.5

        // ==================== 散射 (水体光学 Beer-Lambert) ====================
        // _ShallowColor = 透射 tint (1米穿水后的剩余比例, 白=清水, 蓝=水吸收红绿)
        // _DeepColor    = 内散射色 (无物体/深水处水体自身的颜色, 全吸收后只剩它)
        _ShallowColor ("Transmission Tint (1m 透射率)", Color) = (0.8, 0.92, 0.95, 1)
        _DeepColor ("Scatter Color (内散射色)", Color) = (0.05, 0.2, 0.3, 1)
        _DepthDensity ("Depth Density (吸收/散射率, 1/米)", Range(0.005, 2.0)) = 0.15

        // ==================== 折射 ====================
        _RefractionStrength ("Refraction Strength (折射强度)", Range(0, 0.2)) = 0.02

        // ==================== 反射 ====================
        [HideInInspector] _ReflectionTex ("Reflection Tex", 2D) = "black" {}
        _ReflectionStrength ("Reflection Strength (镜面反射强度)", Range(0, 1)) = 0.85

        // 调试: 0=正常 1=法线 2=菲涅尔 3=白沫 4=浪高 5=水下色 6=高光
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

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            #define PI 3.14159265
            #define GRAVITY 9.8
            #define STEEPNESS_THRESHOLD 50.0  // UE: SteepnessThreshold, 控制小波法线的圆滑度

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
                float4 screenPos : TEXCOORD4;
                float3 restPosWS : TEXCOORD5;   // 位移前的静水面坐标 (精确可插值)
            };

            // 每个波一个 float4:
            // x = dir.x, y = dir.z (已归一化), z = wavelength 波长, w = amplitude 振幅
            StructuredBuffer<float4> _Waves;
            // 每波独立参数: x=陡峭度, y=初相位 (对照 UE 每波存 Steepness)
            StructuredBuffer<float2> _Steepnesses;

            CBUFFER_START(UnityPerMaterial)
                // ---- 开关 ----
                float _VertexDisplaceOn, _ShoreAttenOn;
                float _RefractionOn, _ScatterOn;
                float _FresnelOn, _SpecularOn;
                float _TipFoamOn, _ShoreFoamOn;
                float _SSROn, _PlanarOn;

                // ---- 波浪生成 ----
                int _WaveCount;
                int _LowFrequencyMaxIndex;
                int _MiddleFrequencyMaxIndex;
                float _NormalStrength;
                float _SpeedMultiplier;
                float _SteepnessScale;
                float _HorizontalBoost;

                // ---- 岸边浪衰减 ----
                float _WaveMaskDepth;

                // ---- 菲涅尔 ----
                float4 _FresnelColor;
                float _FresnelBase;
                float _FresnelNormalStrength;

                // ---- 高光 ----
                float _Smoothness;
                float _SpecularStrength;

                // ---- 浪尖泡沫 ----
                float4 _TipColor;
                float _TipThreshold;
                float _TipSpread;

                // ---- 岸边/物体边缘泡沫 ----
                float4 _ShoreFoamColor;
                float _ShoreFoamDistance;
                float _ShoreFoamScale;

                // ---- 散射 ----
                float4 _ShallowColor;
                float4 _DeepColor;
                float _DepthDensity;

                // ---- 折射 ----
                float _RefractionStrength;

                // ---- 反射 ----
                float _ReflectionStrength;
                // 反射相机 view-projection (世界点 -> 反射纹理 UV)
                float4x4 _ReflectionUVMatrix;
                // 反射平面高度 (水面 y)
                float _ReflectionPlaneHeight;

                // ---- 调试 ----
                float _DebugMode;
            CBUFFER_END

            // 平面反射相机输出 (由 WaterPlanarReflection 绑定)
            TEXTURE2D(_ReflectionTex); SAMPLER(sampler_ReflectionTex);

            // ############################################################
            // #                  功能块 1: 波浪生成                       #
            // ############################################################

            // 统一的波段求值 (对照老版 .ush GetRangeGerstnerWavesNew):
            // [minIdx, maxIdx) 范围内 Gerstner 波叠加; bDisplace 时输出位移, 法线始终累加
            void EvaluateGerstnerRange(int minIdx, int maxIdx, float2 p,
                                       inout float3 offset, inout float2 slope, inout float zSlope)
            {
                // 循环上限钳到 _WaveCount, 保证动态循环能编译
                [loop]
                for (int i = 0; i < _WaveCount; i++)
                {
                    if (i < minIdx || i >= maxIdx) continue;

                    float4 wave = _Waves[i];
                    float2 d = wave.xy;
                    float wavelength = max(wave.z, 0.01);
                    float amplitude = wave.w;
                    // 缩放乘在 steep 源头: q (水平挤压) 和法线 zSlope 同时受控, 二者超限都会翻转法线
                    float steep = _Steepnesses[i].x * _SteepnessScale;

                    float dispersion = 2.0 * PI / wavelength;       // k
                    float wavespeed = sqrt(dispersion * GRAVITY);   // UE: sqrt(dispersion * Gravity)
                    float phase = dispersion * dot(d, p) - wavespeed * _Time.y * _SpeedMultiplier;

                    float waveSin = sin(phase);
                    float waveCos = cos(phase);

                    float wKA = amplitude * dispersion;
                    float q = steep / max(wKA, 0.001);              // UE: q = Steepness / wKA

                    // 水平位移单独增幅 (_HorizontalBoost): 拉开"前后荡漾"的运动感
                    offset.xz += -q * waveSin * d * amplitude * _HorizontalBoost;
                    offset.y += waveCos * amplitude;

                    // Normal 累加 (UE 的 z-up 公式换到 Unity y-up)
                    slope += waveSin * wKA * d;
                    zSlope += waveCos * steep * saturate(amplitude * STEEPNESS_THRESHOLD / wavelength);
                }
            }

            // 求全波段的位移+法线 (顶点/像素共用)
            void ComputeWaves(float2 p, out float3 offset, out float2 slope, out float zSlope, out float ampSum)
            {
                offset = float3(0, 0, 0);
                slope = float2(0, 0);
                zSlope = 0.0;
                ampSum = 0.0;

                EvaluateGerstnerRange(0, _WaveCount, p, offset, slope, zSlope);
                [loop]
                for (int i = 0; i < _WaveCount; i++) ampSum += _Waves[i].w;
            }

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                // 静水面坐标 (位移前): 平面网格上线性插值零误差,
                // fragment 用它求波, 与顶点求值严格一致, 避免波谷大三角形插值相位错乱
                float3 restPosWS = TransformObjectToWorld(input.positionOS.xyz);

                // [开关] 顶点位移: 关闭时水面保持平面, 只有像素级法线/泡沫在动
                float3 offset = float3(0, 0, 0);
                float2 slope = float2(0, 0);
                float zSlope = 0.0;
                float ampSum = 0.0;
                if (_VertexDisplaceOn > 0.5)
                {
                    // 顶点只负责位移形状 (低+中频段, UE: 高频波不动网格)
                    EvaluateGerstnerRange(0, _MiddleFrequencyMaxIndex + 1, restPosWS.xz,
                                          offset, slope, zSlope);
                }

                float3 positionWS = restPosWS + offset;

                output.restPosWS = restPosWS;
                output.positionWS = positionWS;
                output.positionCS = TransformWorldToHClip(positionWS);
                output.screenPos = ComputeScreenPos(output.positionCS);
                return output;
            }

            // ############################################################
            // #              功能块 2: 噪声 (泡沫共用工具)                 #
            // ############################################################

            // 简易 value-noise FBM: 三层八度, 世界坐标驱动, 时间缓慢流动
            float FoamNoise(float2 worldXZ, float scale, float time)
            {
                float2 np = worldXZ * (1.0 / max(scale, 0.05));
                float nt = time * 0.35;
                float noise = 0.0;
                float amp = 0.5;
                [unroll]
                for (int oct = 0; oct < 3; oct++)
                {
                    float2 seed = np + float2(oct * 17.3, oct * 9.1) + nt * (oct + 1) * 0.5;
                    float2 ii = floor(seed);
                    float2 ff = frac(seed);
                    ff = ff * ff * (3.0 - 2.0 * ff);
                    float a = frac(sin(dot(ii, float2(127.1, 311.7))) * 43758.5453);
                    float b = frac(sin(dot(ii + float2(1, 0), float2(127.1, 311.7))) * 43758.5453);
                    float c = frac(sin(dot(ii + float2(0, 1), float2(127.1, 311.7))) * 43758.5453);
                    float d2 = frac(sin(dot(ii + float2(1, 1), float2(127.1, 311.7))) * 43758.5453);
                    noise += amp * lerp(lerp(a, b, ff.x), lerp(c, d2, ff.x), ff.y);
                    np *= 2.03;
                    amp *= 0.5;
                }
                return noise;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // ############################################################
                // #               功能块 1: 波浪生成 (像素法线)               #
                // ############################################################
                float3 offset; float2 slope; float zSlope; float ampSum;
                ComputeWaves(input.restPosWS.xz, offset, slope, zSlope, ampSum);

                // 2. 屏幕深度与 UV (提前: 衰减/折射/泡沫都要用)
                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float surfaceDepth = input.screenPos.w;

                float rawSceneDepth = SampleSceneDepth(screenUV);
                float sceneDepth = LinearEyeDepth(rawSceneDepth, _ZBufferParams);
                float depthDiff = max(0.0, sceneDepth - surfaceDepth);

                // ############################################################
                // #            功能块 3: 岸边浪衰减 (UE 深度衰减)             #
                // ############################################################
                if (_ShoreAttenOn > 0.5)
                {
                    // UE ComputeWaveDepthAttenuationFactor: 浅水(岸线)波幅指数衰减
                    // factor = 1 - exp(-depth / (maskDepth/2)), 深水恒为 1, 岸线趋 0
                    float attenFactor = 1.0 - exp(-depthDiff / max(_WaveMaskDepth * 0.5, 0.01));
                    // 衰减作用于位移幅度与法线斜率 (波到岸边逐渐压平)
                    offset *= attenFactor;
                    slope *= attenFactor;
                    zSlope *= attenFactor;
                }

                float3 normal = normalize(float3(slope.x, 1.0 - zSlope, slope.y));
                normal.xz *= _NormalStrength;
                normal = normalize(normal);
                // 浪高按总振幅归一化到约 [-1, 1], 白沫阈值与整体浪高无关
                float waveHeight = offset.y / max(ampSum, 0.001);

                // ############################################################
                // #            功能块 4: 折射 (屏幕空间 UV 偏移)              #
                // ############################################################
                float2 refractUV = screenUV;
                if (_RefractionOn > 0.5)
                {
                    float2 refractOffset = normal.xz * _RefractionStrength;
                    refractUV = screenUV + refractOffset;

                    // 防穿帮: 偏移后采样到了水面上方物体时回退
                    refractUV = clamp(refractUV, 0.002, 0.998);
                    float rd = LinearEyeDepth(SampleSceneDepth(refractUV), _ZBufferParams);
                    if (rd < surfaceDepth)
                    {
                        refractUV = screenUV;
                    }
                }
                rawSceneDepth = SampleSceneDepth(refractUV);
                sceneDepth = LinearEyeDepth(rawSceneDepth, _ZBufferParams);
                depthDiff = max(0.0, sceneDepth - surfaceDepth);

                // ############################################################
                // #     功能块 5: 水下物体渲染 + 散射 (Beer-Lambert 双项)     #
                // ############################################################
                half3 sceneColor = SampleSceneColor(refractUV);
                half3 underwaterFinal;
                if (_ScatterOn > 0.5)
                {
                    // 透射: 物体光按穿水路径指数吸收, tint=1米处透射率 (近处几乎不染色)
                    half3 transmitted = sceneColor * pow(saturate(_ShallowColor.rgb), depthDiff * _DepthDensity);
                    // 内散射: 水体自色随深度累积; 无物体(无限深)时透射->0, 散射色完全接管
                    float fade = 1.0 - exp(-depthDiff * _DepthDensity);
                    underwaterFinal = transmitted + _DeepColor.rgb * fade;
                }
                else
                {
                    // 关闭散射: 纯水下画面, 无吸收无染色
                    underwaterFinal = sceneColor;
                }

                // 光照与视线 (后续块共用)
                Light mainLight = GetMainLight();
                float3 lightDir = mainLight.direction;
                // 视线逐像素重算: 顶点插值在大三角形掠射角处会偏到 NdotV≈0, 菲涅尔满格出白斑
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - input.positionWS);

                // ############################################################
                // #                 功能块 6: 菲涅尔                          #
                // ############################################################
                float fresnel = 0.0;
                if (_FresnelOn > 0.5)
                {
                    // 菲涅尔专用平滑法线: 细波纹不参与菲涅尔大形状, 只影响高光
                    float3 fresnelNormal = normal;
                    fresnelNormal.xz *= _FresnelNormalStrength;
                    fresnelNormal = normalize(fresnelNormal);

                    // Schlick 近似: 垂直俯视恒为 F0 (水=2%) 几乎全透, 掠射角升至 100%
                    float FNdotV = saturate(dot(viewDir, fresnelNormal));
                    fresnel = _FresnelBase + (1.0 - _FresnelBase) * pow(1.0 - FNdotV, 5.0);
                }

                // ############################################################
                // #                 功能块 7: 高光 (GGX)                      #
                // ############################################################
                float3 specular = float3(0, 0, 0);
                if (_SpecularOn > 0.5)
                {
                    float3 halfDir = normalize(lightDir + viewDir);
                    float NdotH = saturate(dot(normal, halfDir));
                    // 微表面高光: GGX 分布替代硬指数, 高光有柔和光晕不像油膜
                    float roughness = 1.0 - _Smoothness;
                    float a = max(roughness * roughness, 0.002);
                    float a2 = a * a;
                    float dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
                    float spec = a2 / max(PI * dd * dd, 0.0001);
                    specular = mainLight.color * spec * _SpecularStrength * 0.25;
                }

                // ############################################################
                // #            功能块 8a: 浪尖泡沫 (波峰白沫)                 #
                // ############################################################
                float3 foamColor = float3(0, 0, 0);
                if (_TipFoamOn > 0.5)
                {
                    // Gerstner 波峰更尖, 白沫集中在峰顶
                    float tipMask = smoothstep(_TipThreshold, _TipThreshold + _TipSpread, waveHeight);
                    foamColor += _TipColor.rgb * tipMask;
                }

                // ############################################################
                // #       功能块 8b: 岸边/水中物体边缘浮沫 (深度带+噪声)      #
                // ############################################################
                if (_ShoreFoamOn > 0.5)
                {
                    // 深度带: depthDiff 小于浮沫带宽处 (岸线/露出水面的物体边缘) 出沫,
                    // 噪声把边界打散成斑块, 随波起伏涌动
                    float foamBand = 1.0 - saturate(depthDiff / max(_ShoreFoamDistance, 0.01));
                    float noise = FoamNoise(input.restPosWS.xz, _ShoreFoamScale, _Time.y);
                    // 噪声调制浮沫带: 贴岸处噪声压低也几乎全沫, 远离处只剩噪声高点
                    float shoreFoam = foamBand * saturate(noise * 1.6 - (1.0 - foamBand) * 0.8);
                    foamColor += _ShoreFoamColor.rgb * saturate(shoreFoam);
                }

                // ############################################################
                // #   功能块 9: 反射 (9a SSR 屏幕内物体 + 9b 平面反射兜底)    #
                // ############################################################
                half3 reflection = float3(0, 0, 0);
                float reflectionWeight = 0.0;

                // ---- 9a SSR: 屏幕空间光线步进, 命中屏幕内物体用真实光路 ----
                if (_SSROn > 0.5)
                {
                    float3 reflDir = reflect(-viewDir, normal);
                    if (reflDir.y > 0.02)
                    {
                        float t = 0.3;
                        [loop]
                        for (int s = 0; s < 20; s++)
                        {
                            float3 p = input.positionWS + reflDir * t;
                            float4 clip = mul(UNITY_MATRIX_VP, float4(p, 1.0));
                            float2 suv = (clip.xy / clip.w) * 0.5 + 0.5;
                            if (suv.x < 0 || suv.x > 1 || suv.y < 0 || suv.y > 1) break;
                            // 射线点的视深度 vs 场景深度: 射线钻到几何后面 = 命中
                            float rayEyeDepth = -mul(UNITY_MATRIX_V, float4(p, 1.0)).z;
                            float sceneEyeDepth = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                            if (rayEyeDepth > sceneEyeDepth + 0.05)
                            {
                                reflection = SampleSceneColor(suv);
                                reflectionWeight = 1.0 - (float)s / 20.0; // 近处命中权重高
                                break;
                            }
                            t = t * 1.3 + 0.15; // 步长指数增长: 近处细远处粗
                        }
                    }
                }

                // ---- 9b 平面反射: 天空/屏幕外兜底 ----
                half3 planarColor = float3(0, 0, 0);
                if (_PlanarOn > 0.5)
                {
                    // 水面点经反射相机 VP 投影采反射纹理 (标准平面反射)
                    float4 reflUV4 = mul(_ReflectionUVMatrix, float4(input.positionWS, 1.0));
                    float2 reflUV = reflUV4.xy / max(reflUV4.w, 0.001);
                    // 法线扰动让反射边缘随波晃动
                    reflUV += normal.xz * _RefractionStrength * 4.0;
                    planarColor = SAMPLE_TEXTURE2D_LOD(_ReflectionTex, sampler_ReflectionTex, saturate(reflUV), 0).rgb;
                }
                // SSR 未命中处回落平面反射
                reflection = lerp(planarColor, reflection, reflectionWeight);

                // 菲涅尔加权: 掠射角反射强, 俯视几乎全透 (物理: 反射率 = fresnel)
                float3 reflectionFinal = _FresnelColor.rgb;
                if (_FresnelOn > 0.5)
                {
                    // 有反射源(开启任一)时用反射画面, 否则退回天空色
                    float hasSource = max(_SSROn, _PlanarOn);
                    reflectionFinal = lerp(_FresnelColor.rgb, reflection, saturate(_ReflectionStrength * 2.0) * hasSource);
                }

                // ############################################################
                // #                    最终融合                               #
                // ############################################################
                // 水是纯镜面介质: 无漫反射, 只有折射透射 + 菲涅尔反射 + 高光 + 泡沫
                float3 finalColor = lerp(underwaterFinal, reflectionFinal, fresnel) + specular + foamColor;

                // ---- 调试模式: 按数字键切换 (脚本 _DebugMode), 0=正常 ----
                // 1=法线可视化  2=菲涅尔  3=白沫蒙版  4=归一化浪高  5=水下色  6=高光
                UNITY_BRANCH
                if (_DebugMode > 0.5)
                {
                    if (_DebugMode < 1.5)      return half4(normal * 0.5 + 0.5, 1);
                    else if (_DebugMode < 2.5) return half4(fresnel.xxx, 1);
                    else if (_DebugMode < 3.5) return half4(saturate(foamColor).xxx, 1);
                    else if (_DebugMode < 4.5) return half4(saturate(waveHeight * 0.5 + 0.5).xxx, 1);
                    else if (_DebugMode < 5.5) return half4(underwaterFinal, 1);
                    else if (_DebugMode < 6.5) return half4(saturate(specular), 1);
                }

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
