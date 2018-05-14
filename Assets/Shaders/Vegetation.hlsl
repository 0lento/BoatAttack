#include "LWRP/ShaderLibrary/Lighting.hlsl"
#define UNITY_USE_SHCOEFFS_ARRAYS 1

struct VegetationVertexInput
{
    float4 position : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 texcoord : TEXCOORD0;
    float2 lightmapUV : TEXCOORD1;
    float4 color : COLOR;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct VegetationVertexOutput
{
    float3 uv                       : TEXCOORD0;//z holds vert AO
    DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 1);
    float3 posWS               : TEXCOORD2;

#ifdef _NORMALMAP
    half4 normal                    : TEXCOORD3;    // xyz: normal, w: viewDir.x
    half4 tangent                   : TEXCOORD4;    // xyz: tangent, w: viewDir.y
    half4 binormal                  : TEXCOORD5;    // xyz: binormal, w: viewDir.z
#else
    half3  normal                   : TEXCOORD3;
    half3 viewDir                   : TEXCOORD4;
#endif

    half4 fogFactorAndVertexLight   : TEXCOORD6; // x: fogFactor, yzw: vertex light

#ifdef _SHADOWS_ENABLED
    float4 shadowCoord              : TEXCOORD7;
#endif

    float4 clipPos                  : SV_POSITION;
    half occlusion                  : TEXCOORD8;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

UNITY_INSTANCING_BUFFER_START(Props)
    UNITY_DEFINE_INSTANCED_PROP(half4, _Position)
UNITY_INSTANCING_BUFFER_END(Props)

/////////////////////////////////////vegetation stuff//////////////////////////////////////////////////
half4 SmoothCurve( half4 x ) {
    return x * x *( 3.0 - 2.0 * x );
}

half4 TriangleWave( half4 x ) {
    return abs( frac( x + 0.5 ) * 2.0 - 1.0 );
}

half4 SmoothTriangleWave( half4 x ) {
    return SmoothCurve( TriangleWave( x ) );
}

float3 VegetationDeformation(float3 position, float3 origin, float3 normal, half leafStiffness, half branchStiffness, half phaseOffset)
{
    ///////Main Bending
    float fBendScale = 0.05;//main bend opacity
    float fLength = length(position);//distance to origin
    float2 vWind = float2(sin(_Time.y + origin.x) * 0.1, sin(_Time.y + origin.z) * 0.1);//wind direction

    // Bend factor - Wind variation is done on the CPU.
    float fBF = position.y * fBendScale;
    // Smooth bending factor and increase its nearby height limit.
    fBF += 1.0;
    fBF *= fBF;
    fBF = fBF * fBF - fBF;
    // Displace position
    float3 vNewPos = position;
    vNewPos.xz += vWind.xy * fBF;
    // Rescale
    position = normalize(vNewPos.xyz) * fLength;

    ////////Detail blending
    float fSpeed = 0.25;//leaf occil
    float fDetailFreq = 0.3;//detail leaf occil
    float fEdgeAtten = leafStiffness;//leaf stiffness(red)
    float fDetailAmp = 0.1;//leaf edge amplitude of movement
    float fBranchAtten = 1 - branchStiffness;//branch stiffness(blue)
    float fBranchAmp = 5.5;//branch amplitude of movement
    float fBranchPhase = phaseOffset * 3.3;//leaf phase(green)

    // Phases (object, vertex, branch)
    float fObjPhase = dot(origin, 1);
    fBranchPhase += fObjPhase;
    float fVtxPhase = dot(position, fBranchPhase + fBranchPhase);
    // x is used for edges; y is used for branches
    float2 vWavesIn = _Time.y + float2(fVtxPhase, fBranchPhase );
    // 1.975, 0.793, 0.375, 0.193 are good frequencies
    float4 vWaves = (frac( vWavesIn.xxyy * float4(1.975, 0.793, 0.375, 0.193) ) * 2.0 - 1.0 ) * fSpeed * fDetailFreq;
    vWaves = SmoothTriangleWave( vWaves );
    float2 vWavesSum = vWaves.xz + vWaves.yw;
    // Edge (xy) and branch bending (z)
    return position + vWavesSum.xyx * float3(fEdgeAtten * fDetailAmp * normal.x, fBranchAtten * fBranchAmp, fEdgeAtten * fDetailAmp * normal.z);
}
//////////////////////////////////////////////////////////////////////////////////////////////////////