// ============================================================
//  HLSLWater.shader  –  Unity 6 URP
//  FIXED: edge-only foam, correct ortho + perspective depth
// ============================================================
//  Author: VoxarDev | Discord: str_voxar 
// ============================================================

Shader "Custom/HLSLWater"
{
    Properties
    {
        [Header(Colors)]
        _ShallowColor       ("Shallow Color",               Color)   = (0.20, 0.75, 0.80, 0.55)
        _DeepColor          ("Deep Color",                  Color)   = (0.04, 0.22, 0.45, 0.92)
        _DepthMaxDistance   ("Depth Max Distance",          Float)   = 2.0

        [Header(Waves)]
        _WaveA              ("Wave A  dir.xy | amp | freq", Vector)  = (1.0, 0.0,  0.10, 1.2)
        _WaveB              ("Wave B  dir.xy | amp | freq", Vector)  = (0.7, 0.7,  0.06, 2.1)
        _WaveC              ("Wave C  dir.xy | amp | freq", Vector)  = (-0.5, 0.9, 0.04, 1.7)
        _WaveSpeed          ("Wave Speed",                  Float)   = 1.0

        [Header(Normal Map)]
        _NormalMap          ("Normal Map",                  2D)      = "bump" {}
        _NormalStrength     ("Normal Strength",             Range(0,2))   = 0.6
        _NormalTiling       ("Normal Tiling",               Float)   = 2.0
        _NormalSpeedA       ("Normal Layer A Speed XY",     Vector)  = (0.03,  0.02, 0, 0)
        _NormalSpeedB       ("Normal Layer B Speed XY",     Vector)  = (-0.02, 0.01, 0, 0)

        [Header(Refraction)]
        _RefractionStrength ("Refraction Strength",         Range(0,0.08)) = 0.02

        [Header(Edge Foam)]
        _FoamColor          ("Foam Color",                  Color)   = (1, 1, 1, 1)
        _FoamDistance       ("Foam Distance",               Float)   = 0.4
        _FoamCutoff         ("Foam Cutoff",                 Range(0,1))   = 0.4
        _FoamNoiseTiling    ("Foam Noise Tiling",           Float)   = 5.0
        _FoamNoiseSpeed     ("Foam Noise Speed",            Float)   = 0.06

        [Header(Surface Foam)]
        _SurfaceFoamColor   ("Surface Foam Color",          Color)   = (0.88, 0.94, 1.0, 1.0)
        _SurfaceFoamAmount  ("Surface Foam Amount",         Range(0,1))   = 0.25
        _SurfaceFoamTiling  ("Surface Foam Tiling",         Float)   = 3.5
        _SurfaceFoamSpeed   ("Surface Foam Speed",          Float)   = 0.04

        [Header(Specular)]
        _SpecColor          ("Specular Color",              Color)   = (1, 1, 1, 1)
        _Shininess          ("Shininess",                   Range(4,512)) = 80
        _SpecularStrength   ("Specular Strength",           Range(0,2))   = 0.7
        _SunDirection       ("Sun Direction XYZ",           Vector)  = (0.5, 1.0, 0.3, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderType"      = "Transparent"
            "Queue"           = "Transparent"
            "RenderPipeline"  = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }

        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off

        Pass
        {
            Name "StylizedWaterForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   WaterVert
            #pragma fragment WaterFrag
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            // ------------------------------------------------
            //  SRP Batcher CBUFFER
            // ------------------------------------------------
            CBUFFER_START(UnityPerMaterial)
                float4 _ShallowColor;
                float4 _DeepColor;
                float  _DepthMaxDistance;

                float4 _WaveA;
                float4 _WaveB;
                float4 _WaveC;
                float  _WaveSpeed;

                float4 _NormalMap_ST;
                float  _NormalStrength;
                float  _NormalTiling;
                float4 _NormalSpeedA;
                float4 _NormalSpeedB;

                float  _RefractionStrength;

                float4 _FoamColor;
                float  _FoamDistance;
                float  _FoamCutoff;
                float  _FoamNoiseTiling;
                float  _FoamNoiseSpeed;

                float4 _SurfaceFoamColor;
                float  _SurfaceFoamAmount;
                float  _SurfaceFoamTiling;
                float  _SurfaceFoamSpeed;

                float4 _SpecColor;
                float  _Shininess;
                float  _SpecularStrength;
                float4 _SunDirection;
            CBUFFER_END

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            // ================================================
            //  DEPTH HELPERS
            // ================================================

            // Convert raw depth buffer value → linear eye depth (view-space units)
            // Works for BOTH perspective and orthographic cameras in Unity 6.
            float ToLinearEyeDepth(float rawDepth)
            {
                // unity_OrthoParams.w == 1 when orthographic, 0 when perspective
                #if defined(UNITY_REVERSED_Z)
                    rawDepth = 1.0 - rawDepth;
                #endif

                // Orthographic: depth is linear in [0,1] between near and far
                float orthoDepth = lerp(_ProjectionParams.y, _ProjectionParams.z, rawDepth);

                // Perspective: standard formula
                // NOTE: we feed the already-un-reversed rawDepth back in for perspective
                #if defined(UNITY_REVERSED_Z)
                    float perspRaw = 1.0 - rawDepth; // un-flip for LinearEyeDepth
                #else
                    float perspRaw = rawDepth;
                #endif
                float perspDepth = LinearEyeDepth(perspRaw, _ZBufferParams);

                return lerp(perspDepth, orthoDepth, unity_OrthoParams.w);
            }

            // Eye-space depth of the water surface fragment itself
            // Perspective  : clip.w == view-space Z (Unity guarantee)
            // Orthographic : clip.w == 1, so we must derive from NDC Z instead
            float GetWaterFragDepth(float4 positionCS)
            {
                // For perspective, positionCS.w is view-space depth directly
                float perspDepth = positionCS.w;

                // For orthographic, reconstruct from NDC Z
                // NDC Z = posCS.z / posCS.w.  In ortho w=1, so NDC Z = posCS.z
                // Raw depth in [0,1] (handle reversed Z)
                float ndcZ = positionCS.z;
                #if defined(UNITY_REVERSED_Z)
                    ndcZ = 1.0 - ndcZ;
                #endif
                float orthoDepth = lerp(_ProjectionParams.y, _ProjectionParams.z, ndcZ);

                return lerp(perspDepth, orthoDepth, unity_OrthoParams.w);
            }

            // ================================================
            //  GERSTNER WAVES
            // ================================================
            float3 GerstnerWave(float4 wave, float3 posWS, float time,
                                inout float3 tangent, inout float3 binormal)
            {
                float steepness = 0.5;
                float2 dir  = normalize(wave.xy);
                float  amp  = wave.z;
                float  freq = wave.w;

                float k  = TWO_PI * freq;
                float c  = sqrt(9.8 / max(k, 0.0001));
                float f  = k * (dot(dir, posWS.xz) - c * time);
                float qa = steepness * amp;

                tangent += float3(
                    -dir.x * dir.x * (qa * sin(f)),
                     dir.x * amp   * cos(f),
                    -dir.x * dir.y * (qa * sin(f))
                );
                binormal += float3(
                    -dir.x * dir.y * (qa * sin(f)),
                     dir.y * amp   * cos(f),
                    -dir.y * dir.y * (qa * sin(f))
                );

                return float3(
                    dir.x * amp * cos(f),
                    amp         * sin(f),
                    dir.y * amp * cos(f)
                );
            }

            // ================================================
            //  PROCEDURAL NOISE
            // ================================================
            float Hash(float2 p)
            {
                p  = frac(p * float2(443.8975, 397.2973));
                p += dot(p, p + 19.19);
                return frac(p.x * p.y);
            }

            float ValueNoise(float2 uv)
            {
                float2 i = floor(uv);
                float2 f = frac(uv);
                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(
                    lerp(Hash(i),             Hash(i + float2(1,0)), u.x),
                    lerp(Hash(i+float2(0,1)), Hash(i + float2(1,1)), u.x),
                    u.y
                );
            }

            // ================================================
            //  STRUCTS
            // ================================================
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
                float3 positionWS  : TEXCOORD0;
                float2 uv          : TEXCOORD1;
                float4 screenPos   : TEXCOORD2;
                float3 normalWS    : TEXCOORD3;
                float3 viewDirWS   : TEXCOORD4;
                float3 tangentWS   : TEXCOORD5;
                float3 binormalWS  : TEXCOORD6;
                float4 clipPos     : TEXCOORD7;  // raw clip pos for ortho depth
            };

            // ================================================
            //  VERTEX SHADER
            // ================================================
            Varyings WaterVert(Attributes IN)
            {
                Varyings OUT;

                float3 posWS = TransformObjectToWorld(IN.positionOS.xyz);
                float  t     = _Time.y * _WaveSpeed;

                float3 tangent  = float3(1, 0, 0);
                float3 binormal = float3(0, 0, 1);

                posWS += GerstnerWave(_WaveA, posWS, t, tangent, binormal);
                posWS += GerstnerWave(_WaveB, posWS, t, tangent, binormal);
                posWS += GerstnerWave(_WaveC, posWS, t, tangent, binormal);

                float3 normalWS = normalize(cross(binormal, tangent));

                OUT.positionWS  = posWS;
                OUT.normalWS    = normalWS;
                OUT.tangentWS   = normalize(tangent);
                OUT.binormalWS  = normalize(binormal);
                OUT.uv          = IN.uv;
                OUT.viewDirWS   = GetWorldSpaceViewDir(posWS);

                float4 posCS    = TransformWorldToHClip(posWS);
                OUT.positionCS  = posCS;
                OUT.clipPos     = posCS;            // store for depth calc
                OUT.screenPos   = ComputeScreenPos(posCS);

                return OUT;
            }

            // ================================================
            //  FRAGMENT SHADER
            // ================================================
            half4 WaterFrag(Varyings IN) : SV_Target
            {
                // Perspective-correct screen UV
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;

                // --------------------------------------------
                //  1. DEPTH
                // --------------------------------------------
                float rawScene    = SampleSceneDepth(screenUV);
                float sceneDepth  = ToLinearEyeDepth(rawScene);
                float fragDepth   = GetWaterFragDepth(IN.clipPos);

                // Depth difference in world units
                float depthDiff   = sceneDepth - fragDepth;

                // Clamp negatives (avoid foam on sky/nothing)
                depthDiff = max(0.0, depthDiff);

                float waterDepth  = saturate(depthDiff / _DepthMaxDistance);

                // --------------------------------------------
                //  2. NORMAL MAP
                // --------------------------------------------
                float2 worldUV = IN.positionWS.xz;

                float2 uvA = worldUV * _NormalTiling        + _Time.y * _NormalSpeedA.xy;
                float2 uvB = worldUV * _NormalTiling * 0.65 + _Time.y * _NormalSpeedB.xy;

                float3 nA = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvA));
                float3 nB = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvB));

                float3 blended = normalize(float3(nA.xy + nB.xy, max(nA.z, nB.z)));
                blended        = normalize(lerp(float3(0,0,1), blended, _NormalStrength));

                float3x3 TBN = float3x3(
                    normalize(IN.tangentWS),
                    normalize(IN.binormalWS),
                    normalize(IN.normalWS)
                );
                float3 waterNormalWS = normalize(mul(blended, TBN));

                // --------------------------------------------
                //  3. REFRACTION
                // --------------------------------------------
                float2 refrOffset  = blended.xy * _RefractionStrength;
                float2 refractedUV = screenUV + refrOffset;

                // Safety: don't sample above water
                float refRaw   = SampleSceneDepth(refractedUV);
                float refDepth = ToLinearEyeDepth(refRaw);
                float2 finalUV = (refDepth - fragDepth) > 0.01 ? refractedUV : screenUV;

                half3 refractedColor = SampleSceneColor(finalUV).rgb;

                // --------------------------------------------
                //  4. WATER COLOR
                // --------------------------------------------
                half4 waterCol   = lerp(_ShallowColor, _DeepColor, waterDepth);
                half3 finalColor = lerp(refractedColor, waterCol.rgb,
                                        waterCol.a * saturate(waterDepth * 1.2));

                // --------------------------------------------
                //  5. SURFACE FOAM  (only in shallow water)
                // --------------------------------------------
                float2 sfA = worldUV * _SurfaceFoamTiling       + _Time.y * _SurfaceFoamSpeed;
                float2 sfB = worldUV * _SurfaceFoamTiling * 1.4 - _Time.y * _SurfaceFoamSpeed * 0.6;

                float sfNoise = ValueNoise(sfA) * ValueNoise(sfB);
                // Fade surface foam out in deep water
                float sfFoam  = step(1.0 - _SurfaceFoamAmount, sfNoise)
                              * (1.0 - saturate(waterDepth * 2.0));

                finalColor = lerp(finalColor, _SurfaceFoamColor.rgb, sfFoam * _SurfaceFoamColor.a);

                // --------------------------------------------
                //  6. EDGE FOAM  (intersection only)
                // --------------------------------------------
                // depthDiff is in world units — foam only where diff < _FoamDistance
                float foamDepth = saturate(depthDiff / _FoamDistance);

                float2 fnUV   = worldUV * _FoamNoiseTiling + _Time.y * _FoamNoiseSpeed;
                float  fnoise = ValueNoise(fnUV);

                // (1 - foamDepth) is 1 at the very edge, 0 farther away
                // step threshold keeps it as a band, not filled
                float ring1 = step(_FoamCutoff + fnoise * 0.2, 1.0 - foamDepth);
                float ring2 = step(0.80         + fnoise * 0.1, 1.0 - foamDepth * 1.5);

                float foam = saturate(ring1 + ring2 * 0.5);
                finalColor = lerp(finalColor, _FoamColor.rgb, foam * _FoamColor.a);

                // --------------------------------------------
                //  7. SPECULAR
                // --------------------------------------------
                float3 sunDir  = normalize(_SunDirection.xyz);
                float3 viewDir = normalize(IN.viewDirWS);
                float3 halfDir = normalize(sunDir + viewDir);

                float NdotH = saturate(dot(waterNormalWS, halfDir));
                float spec  = pow(NdotH, _Shininess);
                spec        = step(0.5, spec) * spec;

                finalColor += _SpecColor.rgb * spec * _SpecularStrength;

                // --------------------------------------------
                //  8. ALPHA
                // --------------------------------------------
                float alpha = lerp(_ShallowColor.a, _DeepColor.a, waterDepth);
                alpha = saturate(alpha + foam * 0.6);

                return half4(finalColor, alpha);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/InternalErrorShader"
}
