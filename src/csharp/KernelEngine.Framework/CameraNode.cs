using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that acts as a camera. Adds a <see cref="CameraComponent"/> to its ECS entity on start.
/// Register via <c>scene.AddNode(new CameraNode(), "Camera")</c>, then set
/// <c>world.ActiveCamera = cameraNode.Entity</c> so <see cref="CameraRenderSystem"/> picks it up.
/// </summary>
public class CameraNode : Node
{
    // ── ECS registration ──────────────────────────────────────────────────────

    public static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(EcsRegistry registry)
    {
        if (ComponentId == uint.MaxValue)
            ComponentId = registry.RegisterComponent<CameraComponent>("CameraComponent");
    }

    // ── Per-instance ──────────────────────────────────────────────────────────

    /// <summary>Vertical field of view in degrees.</summary>
    public float Fov { get; init; } = 60f;

    /// <summary>Near clip plane distance.</summary>
    public float Near { get; init; } = 0.1f;

    /// <summary>Far clip plane distance.</summary>
    public float Far { get; init; } = 1000f;

    /// <summary>Use orthographic projection instead of perspective.</summary>
    public bool Orthographic { get; init; } = false;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue) return;
        ref var comp = ref AddComponent<CameraComponent>(ComponentId);
        comp = new CameraComponent
        {
            Fov = Fov * MathF.PI / 180f,
            Near = Near,
            Far = Far,
            Orthographic = Orthographic ? (byte)1 : (byte)0,
        };
    }
}
