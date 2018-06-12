﻿Shader "BoatAttack/LWVegetationShader"
{
    Properties
    {
        _MainTex("Albedo", 2D) = "white" {}
        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        _Gloss("Gloss", Range(0.0, 1.0)) = 0.5
        [Toggle(_CORRECTNORMALS)] _CorrectNormals("Correct Normals", Float) = 1.0
        [Toggle(_VERTEXANIMATION)] _VertexAnimation("Vertex Animation", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}
    }

    SubShader
    {
        // Lightweight Pipeline tag is required. If Lightweight pipeline is not set in the graphics settings
        // this Subshader will fail. One can add a subshader below or fallback to Standard built-in to make this
        // material work with both Lightweight Pipeline and Builtin Unity Pipeline
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "LightweightPipeline" "IgnoreProjector" = "True"}

        // ------------------------------------------------------------------
        //  Base forward pass (directional light, emission, lightmaps, ...)
        Pass
        {
            // Lightmode matches the ShaderPassName set in LightweightPipeline.cs. SRPDefaultUnlit and passes with
            // no LightMode tag are also rendered by Lightweight Pipeline
            Tags{"LightMode" = "LightweightForward"}

            ZWrite On
            AlphaToMask On
            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1
            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _CORRECTNORMALS
            #pragma shader_feature _VERTEXANIMATION

            // -------------------------------------
            // Lightweight Pipeline keywords
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _VERTEX_LIGHTS
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
            #pragma multi_compile _ _SHADOWS_ENABLED

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile_fog
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            // Including the following two function is enought for shading with Lightweight Pipeline. Everything is included in them.
            // Core.hlsl will include SRP shader library, all constant buffers not related to materials (perobject, percamera, perframe).
            // It also includes matrix/space conversion functions and fog.
            // Lighting.hlsl will include the light functions/data to abstract light constants. You should use GetMainLight and GetLight functions
            // that initialize Light struct. Lighting.hlsl also include GI, Light BDRF functions. It also includes Shadows.
            //#include "LWRP/ShaderLibrary/Core.hlsl"
                        // Not required but included here for simplicity. This defines all material related constants for the Standard surface shader like _Color, _MainTex, and so on.
            // These are specific to this shader. You should define your own constants.
            #include "InputSurfaceVegetation.hlsl"
            #include "Vegetation.hlsl"

			#pragma vertex VegetationVertex
			#pragma fragment LitPassFragment

            void InitializeInputData(VegetationVertexOutput IN, half3 normalTS, out InputData inputData)
            {
                inputData = (InputData)0;

                inputData.positionWS = IN.posWS;

            #ifdef _NORMALMAP
                half3 viewDir = half3(IN.normal.w, IN.tangent.w, IN.binormal.w);
                inputData.normalWS = TangentToWorldNormal(normalTS, IN.tangent.xyz, IN.binormal.xyz, IN.normal.xyz);
            #else
                half3 viewDir = IN.viewDir;
                inputData.normalWS = FragmentNormalWS(IN.normal);
            #endif

                inputData.viewDirectionWS = FragmentViewDirWS(viewDir);
            #ifdef _SHADOWS_ENABLED
                inputData.shadowCoord = IN.shadowCoord;
            #else
                inputData.shadowCoord = float4(0, 0, 0, 0);
            #endif
                inputData.fogCoord = IN.fogFactorAndVertexLight.x;
                inputData.vertexLighting = IN.fogFactorAndVertexLight.yzw;
                inputData.bakedGI = SAMPLE_GI(IN.lightmapUV, IN.vertexSH, inputData.normalWS);
            }

			//vert
			VegetationVertexOutput VegetationVertex(VegetationVertexInput v)
			{
				VegetationVertexOutput o = (VegetationVertexOutput)0;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.uv.xy = TRANSFORM_TEX(v.texcoord, _MainTex);

                float3 posWS = TransformObjectToWorld(v.position.xyz);
                o.clipPos = TransformWorldToHClip(posWS);

                #if _VERTEXANIMATION
				/////////////////////////////////////vegetation stuff//////////////////////////////////////////////////
                float3 objectOrigin = UNITY_ACCESS_INSTANCED_PROP(Props, _Position).xyz;
                v.position.xyz = VegetationDeformation(v.position.xyz, objectOrigin, v.normal, v.color.x, v.color.z, v.color.y);
				//////////////////////////////////////////////////////////////////////////////////////////////////////
				posWS = TransformObjectToWorld(v.position.xyz);
                o.clipPos = TransformWorldToHClip(posWS);
                #endif
                half3 viewDir = VertexViewDirWS(GetCameraPositionWS() - posWS);

                #ifdef _NORMALMAP
                    o.normal.w = viewDir.x;
                    o.tangent.w = viewDir.y;
                    o.binormal.w = viewDir.z;
                #else
                    o.viewDir = viewDir;
                #endif

                // initializes o.normal and if _NORMALMAP also o.tangent and o.binormal
                OUTPUT_NORMAL(v, o);

				// We either sample GI from lightmap or SH. lightmap UV and vertex SH coefficients
				// are packed in lightmapUVOrVertexSH to save interpolator.
				// The following funcions initialize
                OUTPUT_LIGHTMAP_UV(v.lightmapUV, unity_LightmapST, o.lightmapUV);
                OUTPUT_SH(o.normal.xyz, o.vertexSH);

				half3 vertexLight = VertexLighting(o.posWS, o.normal.xyz);
            #if defined(FOG_EXP)
                half fogFactor = ComputeGlobalFogFactor(posWS);
            #else
                half fogFactor = ComputeFogFactor(o.clipPos.z);
            #endif
                    o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

                #ifdef _SHADOWS_ENABLED
                #if SHADOWS_SCREEN
                    o.shadowCoord = ComputeShadowCoord(o.clipPos);
                #else
                    o.shadowCoord = TransformWorldToShadowCoord(posWS);
                #endif
                #endif

                o.occlusion = v.color.a;

				return o;
			}

			//frag
            half4 LitPassFragment(VegetationVertexOutput IN, half facing : VFACE) : SV_Target
			{
                UNITY_SETUP_INSTANCE_ID(IN);

                SurfaceData surfaceData;
                InitializeStandardLitSurfaceData(IN.uv, surfaceData);

                surfaceData.occlusion = IN.occlusion;

                InputData inputData;
                InitializeInputData(IN, surfaceData.normalTS, inputData);

                #if _CORRECTNORMALS
                inputData.normalWS *= facing;
                #endif

                half4 color = LightweightFragmentPBR(inputData, surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.occlusion, surfaceData.emission, surfaceData.alpha);

                ApplyFog(color.rgb, inputData.fogCoord);
                #ifdef LOD_FADE_CROSSFADE // enable dithering LOD transition if user select CrossFade transition in LOD group
            	    LODDitheringTransition(IN.clipPos, unity_LODFade.x);
            	#endif
                return color;
			}

            ENDHLSL
        }

Pass
        {
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            AlphaToMask On
            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #pragma vertex ShadowPassVegetationVertex
            #pragma fragment ShadowPassVegetationFragment

            #include "InputSurfaceVegetation.hlsl"
            #include "ShadowPassVegetation.hlsl"

            ENDHLSL
        }

        Pass
        {
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            AlphaToMask On
            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1
            #pragma shader_feature _VERTEXANIMATION

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #include "InputSurfaceVegetation.hlsl"
            #include "LWRP/ShaderLibrary/Core.hlsl"
            #include "Vegetation.hlsl"

            VegetationVertexOutput DepthOnlyVertex(VegetationVertexInput v)
            {
                VegetationVertexOutput o = (VegetationVertexOutput)0;
                UNITY_SETUP_INSTANCE_ID(v);

                #if _VERTEXANIMATION
                /////////////////////////////////////vegetation stuff//////////////////////////////////////////////////
                //half phaseOffset = UNITY_ACCESS_INSTANCED_PROP(Props, _PhaseOffset);
                float3 objectOrigin = UNITY_ACCESS_INSTANCED_PROP(Props, _Position).xyz;

                v.position.xyz = VegetationDeformation(v.position.xyz, objectOrigin, v.normal, v.color.x, v.color.z, v.color.y);
                #endif

                o.uv.xy = TRANSFORM_TEX(v.texcoord, _MainTex);
                o.clipPos = TransformObjectToHClip(v.position.xyz);
                return o;
            }

            half4 DepthOnlyFragment(VegetationVertexOutput IN) : SV_TARGET
            {
                half alpha = SampleAlbedoAlpha(IN.uv.xy, TEXTURE2D_PARAM(_MainTex, sampler_MainTex)).a;
                clip(alpha - _Cutoff);
                #ifdef LOD_FADE_CROSSFADE // enable dithering LOD transition if user select CrossFade transition in LOD group
            	    LODDitheringTransition(IN.clipPos, unity_LODFade.x);
            	#endif
                return 0;
            }

            ENDHLSL
        }

        // This pass it not used during regular rendering, only for lightmap baking.
        Pass
        {
            Tags{"LightMode" = "Meta"}

            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles

            #pragma vertex LightweightVertexMeta
            #pragma fragment LightweightFragmentMeta

            #define _METALLICSPECGLOSSMAP 1
            #pragma shader_feature EDITOR_VISUALIZATION

            #pragma shader_feature _SPECGLOSSMAP

            #include "InputSurfaceVegetation.hlsl"
            #include "LWRP/ShaderLibrary/LightweightPassMetaPBR.hlsl"

            ENDHLSL
        }
    }
    FallBack "Hidden/InternalErrorShader"
}
