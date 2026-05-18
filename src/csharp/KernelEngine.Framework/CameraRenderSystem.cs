using KernelEngine.Framework.Internal;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed render system that extracts camera state from the ECS and writes it
/// into the frame packet. Mirrors the math conventions of <c>ke_mat4_*</c> (column-major,
/// right-handed, Vulkan depth [0,1]) so the output is binary-identical to the previous
/// C++ implementation; bgfx/shaders consume it without any change.
/// </summary>
public sealed unsafe class CameraRenderSystem : ISystem
{
    private const float Aspect = 1.77f; // 16:9 — TODO: query from window once exposed

    private readonly uint _cameraCid;
    private readonly uint _transformCid;

    public CameraRenderSystem(uint cameraCid, uint transformCid)
    {
        _cameraCid = cameraCid;
        _transformCid = transformCid;
    }

    public void Update(IWorld iworld, float dt, IFramePacket? ipacket = null, IInputReader? input = null)
    {
        if (ipacket == null) return;
        var world = (World)iworld;
        var packet = (FramePacket)ipacket;

        var registry = world.Registry;
        var cameras = registry.Query<CameraComponent>(_cameraCid);
        if (cameras.Length == 0) return;

        var transform = registry.GetComponent<TransformComponent>(cameras.Entities[0], _transformCid);
        if (transform == null) return;

        var camera = cameras.Data[0];
        var raw = packet.NativePointer;

        // view = inverse of the world matrix (TRS inverse: transpose 3x3 rotation, negate translation).
        // Reading raw 16 floats from world_matrix (column-major, written by the native TransformSystem).
        Mat4.InvertTrs((float*)&transform->WorldMatrix, (float*)&raw->camera.view.m);

        if (camera.Orthographic != 0)
            Mat4.Ortho((float*)&raw->camera.proj.m, -Aspect * 10f, Aspect * 10f, -10f, 10f, camera.Near, camera.Far);
        else
            Mat4.Perspective((float*)&raw->camera.proj.m, camera.Fov, Aspect, camera.Near, camera.Far);

        raw->camera.pos_x = transform->Position.X;
        raw->camera.pos_y = transform->Position.Y;
        raw->camera.pos_z = transform->Position.Z;
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_cameraCid, _transformCid],
        Writes = []
    };
}
