﻿Shader "Unlit/Blocker"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "LightweightPipeline" "IgnoreProjector" = "True"}
        LOD 100
        
        Cull front

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "LWRP/ShaderLibrary/Core.hlsl"

            float4 vert (float4 vertex : POSITION) : SV_POSITION
            {
                return TransformObjectToHClip(vertex);
            }

            half4 frag () : SV_Target
            {
                return half4(0,0,0,1);
            }
            ENDHLSL
        }
    }
}
