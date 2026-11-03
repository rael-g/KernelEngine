using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct CameraFrustum
{
    public float TanHalfFovY;

    public float Aspect;

    public float NearPlane;

    public float FarPlane;
}
