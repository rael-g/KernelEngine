using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct MeshVertex
{
    public System.Numerics.Vector3 Position;
    public System.Numerics.Vector3 Normal;
    public System.Numerics.Vector2 Uv;
    public System.Numerics.Vector3 Tangent;
}
