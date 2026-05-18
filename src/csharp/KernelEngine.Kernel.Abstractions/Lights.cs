using System.Numerics;
using System.Runtime.InteropServices;

namespace KernelEngine.Kernel;

/// <summary>Directional light parameters published in the frame packet.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct DirectionalLight
{
    public Vector3 Direction;
    public Vector3 Color;
    public float Intensity;
}

/// <summary>Point light parameters published in the frame packet.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct PointLight
{
    public Vector3 Position;
    public float Radius;
    public Vector3 Color;
    public float Intensity;
}

/// <summary>Spot light parameters published in the frame packet.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct SpotLight
{
    public Vector3 Position;
    public float Range;
    public Vector3 Direction;
    public float InnerAngle;
    public float OuterAngle;
    public Vector3 Color;
    public float Intensity;
}
