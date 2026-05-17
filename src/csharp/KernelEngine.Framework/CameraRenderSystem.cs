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

    public void Update(World world, float dt, FramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;

        var registry = world.Registry;
        var cameras = registry.Query<CameraComponent>(_cameraCid);
        if (cameras.Length == 0) return;

        var transform = registry.GetComponent<TransformComponent>(cameras.Entities[0], _transformCid);
        if (transform == null) return;

        var camera = cameras.Data[0];
        var raw = packet.NativePointer;

        // view = inverse of the world matrix (TRS inverse: transpose 3x3 rotation, negate translation).
        // Reading raw 16 floats from world_matrix (column-major, written by the native TransformSystem).
        InvertTrs((float*)&transform->WorldMatrix, (float*)&raw->camera.view.m);

        if (camera.Orthographic != 0)
            BuildOrtho((float*)&raw->camera.proj.m, -Aspect * 10f, Aspect * 10f, -10f, 10f, camera.Near, camera.Far);
        else
            BuildPerspective((float*)&raw->camera.proj.m, camera.Fov, Aspect, camera.Near, camera.Far);

        raw->camera.pos_x = transform->Position.X;
        raw->camera.pos_y = transform->Position.Y;
        raw->camera.pos_z = transform->Position.Z;
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_cameraCid, _transformCid],
        Writes = []
    };

    // ── Matrix helpers (column-major, matching ke_mat4_* in src/c/kernel/include/kernel_engine/kernel/common/math.h) ──

    private static void InvertTrs(float* m, float* o)
    {
        // Transpose 3x3 rotation block; negate translation transformed by the transposed rotation.
        o[0] = m[0]; o[1] = m[4]; o[2] = m[8];   o[3] = 0f;
        o[4] = m[1]; o[5] = m[5]; o[6] = m[9];   o[7] = 0f;
        o[8] = m[2]; o[9] = m[6]; o[10] = m[10]; o[11] = 0f;
        o[12] = -(o[0] * m[12] + o[4] * m[13] + o[8]  * m[14]);
        o[13] = -(o[1] * m[12] + o[5] * m[13] + o[9]  * m[14]);
        o[14] = -(o[2] * m[12] + o[6] * m[13] + o[10] * m[14]);
        o[15] = 1f;
    }

    private static void BuildPerspective(float* m, float fov, float aspect, float near, float far)
    {
        var f = 1f / MathF.Tan(fov * 0.5f);
        for (int i = 0; i < 16; i++) m[i] = 0f;
        m[0] = f / aspect;
        m[5] = f;
        m[10] = -far / (far - near);
        m[11] = -1f;
        m[14] = -(far * near) / (far - near);
    }

    private static void BuildOrtho(float* m, float left, float right, float bottom, float top, float near, float far)
    {
        for (int i = 0; i < 16; i++) m[i] = 0f;
        m[0] = 2f / (right - left);
        m[5] = 2f / (top - bottom);
        m[10] = 1f / (far - near);
        m[12] = -(right + left) / (right - left);
        m[13] = -(top + bottom) / (top - bottom);
        m[14] = -near / (far - near);
        m[15] = 1f;
    }
}
