Shader "GF2/GF2UberShader"
{
    Properties
    {
        _AlbedoTex("_Albedo",2D)="white"{}
        _BumpMap("_BumpMap",2D)="white"{}
        [Toggle]_front("front",Float)=0
        [Toggle]_UseRamp("_UseRamp",Float)=0
        _BloomWeightParam("_BloomWeightParam",Float)=0
        _RMOTex("_RMOTex",2D)="white"{}
        _RampMapTex("_RampMapTex",2D)="white"{}



        [Toggle]_Test("_Test",Float)=0
        [Toogle]_AnisotropicSpecular("_AnisotropicSpecular",Float)=0

    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "GF_Forward_Lit_MRT"
            Tags
            {
                "LightMode" = "UniversalForward"
            }


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
            #include "GF2Light_Core.hlsl"


            struct GFAttributes
            {
                float4 positionOS:POSITION;
                float3 normalOS:NORMAL;
                float4 tangentOS:TANGENT;
                float2 uv:TEXCOORD0;
                float2 uv2:TEXCOORD1;
                float4 color:COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct GFVaryings
            {
                float4 positionCS:SV_POSITION;
                float2 uv:TEXCOORD0;
                float3 positionWS:TEXCOORD1;
                float3 normalWS:TEXCOORD2;
                float4 tangentWS:TEXCOORD3;
                float4 shadowCoord:TEXCOORD4;
                float fog:TEXCOORD5;
                float eyeShift:TEXCOORD6;
                float2 uv2:TEXCOORD7;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            struct GFOut
            {
                float4 rt0_HDRColor:SV_Target0;
                float4 rt1_NormalFlag:SV_Target1;
            };


            TEXTURE2D(_AlbedoTex);
            SAMPLER(sampler_AlbedoTex);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            TEXTURE2D(_RMOTex);
            SAMPLER(sampler_RMOTex);
            TEXTURE2D(_RampMapTex);
            SAMPLER(sampler_RampMapTex);

            CBUFFER_START(UnityPerMaterial)
                float _front;
                float _UseRamp;
                half _BloomWeightParam;
                float _Test;
                float _AnisotropicSpecular;
            CBUFFER_END


            GFVaryings vert(GFAttributes input)
            {
                GFVaryings output;
                output.positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformObjectToHClip(input.positionOS);
                output.normalWS = TransformObjectToWorldDir(input.normalOS);
                output.tangentWS = float4(
                    TransformObjectToWorldDir(input.tangentOS.xyz),
                    input.tangentOS.w * GetOddNegativeScale()
                );
                output.uv = input.uv;
                output.uv2 = input.uv2;
                output.shadowCoord = TransformWorldToShadowCoord(TransformObjectToWorld(input.positionOS));
                output.fog = ComputeFogFactor(output.positionCS.z);


                return output;
            }

            float PBR_D(float nh, float roughness)
            {
                roughness *= roughness;
                float denom = max((nh * roughness) * (nh * roughness) + 1 - nh * nh, 1e-8);
                float D = min(2048, (roughness / denom) * (roughness / denom));
                return D;
            }

            float PBR_V(float nv, float nl, float roughness)
            {
                roughness *= roughness;
                float V = min(1, 0.5 / max(
                                  nl * (nv * (1 - roughness) + roughness) + nv * (nl * (1 - roughness) +
                                      roughness), 0.0001));
                return V;
            }

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

            GFOut frag(GFVaryings input)
            {
                GFOut output;
                float4 baseColor = SAMPLE_TEXTURE2D(_AlbedoTex, sampler_AlbedoTex, input.uv);
                //Clip


                //顶点数据
                float3 n = normalize(input.normalWS) * (_front ? 1 : -1);

                float4 packedNormal = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv);

                float2 xy = float2(packedNormal.r * packedNormal.a, 1 - packedNormal.g) * 2 - 1;

                float z = sqrt(1 - min(dot(xy, xy), 1));
                float3 t = normalize(input.tangentWS.xyz);


                float3 b = cross(normalize(input.normalWS), t) * input.tangentWS.w;
                float3 Normal = normalize(t * xy.x + b * xy.y + n * z);
                float3 view = SafeNormalize(GetWorldSpaceViewDir(input.positionWS));


                Light mainLight = GetMainLight(input.shadowCoord);


                if (_AnisotropicSpecular > 0.5)
                {
                    
                }


                float4 rmo = SAMPLE_TEXTURE2D(_RMOTex, sampler_RMOTex, input.uv);
                float roughness = max(rmo.r, 0.02);
                float3 diffuse = baseColor.rgb * (1 - rmo.g), f0 = lerp(float3(0.04, 0.04, 0.04), baseColor.rgb, rmo.g);


                float3 halfDir = SafeNormalize(view + mainLight.direction);
                float nl = saturate(dot(Normal, mainLight.direction));
                float nh = saturate(dot(Normal, halfDir)), vh = saturate(dot(view, halfDir)), lh = saturate(
                          dot(mainLight.direction, halfDir));
                float nv = min(saturate(dot(Normal, view)) + 0.00001, 1);


                float V = PBR_V(nv, nl, roughness);
                //V=原来的G除以pbr公式下面的依托

                float fresnel = 1 + (saturate(50 * f0.g) - 1) * pow(max(1 - vh, 0.001), 5);


                float D = PBR_D(nh, roughness);

                float3 spec = (D * V * fresnel).xxx;


                float3 diffuse_stren = nl * mainLight.shadowAttenuation;
                if (_UseRamp > 0.5)
                {
                    float peak = PBR_D(1, roughness) * PBR_V(vh, lh, roughness);
                    spec = SAMPLE_TEXTURE2D_LOD(_RampMapTex, sampler_RampMapTex,
                                                float2(saturate(D*V/max(peak,1e-8)),0.375),
                                                0).rgb * peak * fresnel;
                    diffuse_stren = SAMPLE_TEXTURE2D_LOD(_RampMapTex, sampler_RampMapTex,
                   float2(nl,0.125), 0).rgb;
                }
                float3 PBR_Color = (diffuse + f0 * clamp(spec, 0, 10)) * diffuse_stren * mainLight.color * mainLight.
                    distanceAttenuation;

                output.rt0_HDRColor = float4(PBR_Color, 1.0);


                float2 octNormal = EncodeOctahedronNormal(input.normalWS);

                half bloomWeight = 0.5h - 0.5h * _BloomWeightParam;

                output.rt1_NormalFlag = half4(octNormal.x, octNormal.y, 0.499h, bloomWeight);
                return output;
                //丝袜
            }
            ENDHLSL
        }
    }
}