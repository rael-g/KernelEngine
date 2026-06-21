using System.Numerics;
using System.Runtime.InteropServices;

namespace KernelEngine.Render;

/// <summary>Directional light parameters published in the frame packet.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct DirectionalLightData
{
    public Vector3 Direction;
    public Vector3 Color;
    public float Intensity;
}

/// <summary>Point light parameters published in the frame packet.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct PointLightData
{
    public Vector3 Position;
    public float Radius;
    public Vector3 Color;
    public float Intensity;
}

/// <summary>Spot light parameters published in the frame packet.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct SpotLightData
{
    public Vector3 Position;
    public float Range;
    public Vector3 Direction;
    public float InnerAngle;
    public float OuterAngle;
    public Vector3 Color;
    public float Intensity;
}
