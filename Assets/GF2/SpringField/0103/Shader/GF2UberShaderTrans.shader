Shader "GF2/GF2UberShaderTrans"
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


        _GFTransparentMRT("float _GFTransparentMRT",Float)=0

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
            #pragma fragment transparentFrag


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

                float _GFTransparentMRT;

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


            float4 transparentFrag(GFVaryings input,FRONT_FACE_TYPE face: FRONT_FACE_SEMANTIC):SV_Target0
            {
                UNITY_SETUP_INSTANCE_ID(input);


                clip(0.5 - _GFTransparentMRT);


                float4 baseColor = SAMPLE_TEXTURE2D(_AlbedoTex, sampler_AlbedoTex, input.uv);
                float4 rmo = SAMPLE_TEXTURE2D(_RMOTex, sampler_RMOTex, input.uv);
                float4 packedNormal = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv);
                float2 xy = float2(packedNormal.r * packedNormal.a, 1 - packedNormal.g) * 2 - 1;
                
            }
            ENDHLSL
        }
    }
}