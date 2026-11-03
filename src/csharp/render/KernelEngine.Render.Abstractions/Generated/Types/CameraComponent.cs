using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct CameraComponent
{
    public float Fov;

    public float NearPlane;

    public float FarPlane;

    public float OrthographicSize;
    public byte Orthographic;
    public uint CullMask;
}
