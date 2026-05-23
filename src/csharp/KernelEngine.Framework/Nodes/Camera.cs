using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene-graph node that acts as a camera. Add it to a tree (<c>tree.AddNode(new Camera(), "Camera")</c>)
/// and it auto-activates when no other camera is current. Switch with <see cref="MakeCurrent"/>.
/// </summary>
public class Camera : Node
{
    // ── ECS registration ──────────────────────────────────────────────────────

    public static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(IEcsRegistry registry)
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

    /// <summary>True when this camera is the one the render system draws from.</summary>
    public bool IsCurrent => World != null && World.ActiveCamera == Entity;

    /// <summary>
    /// Make this the current camera. Deactivates any other camera that was current (last-wins).
    /// </summary>
    public void MakeCurrent()
    {
        if (World != null) World.ActiveCamera = Entity;
    }

    protected override void Start()
    {
        if (ComponentId == uint.MaxValue) return;
        var comp = AddComponent<CameraComponent>(ComponentId);
        comp[0] = new CameraComponent
        {
            Fov = Fov * MathF.PI / 180f,
            Near = Near,
            Far = Far,
            Orthographic = Orthographic ? (byte)1 : (byte)0,
        };
        // Auto-activate when no camera is current yet (so a single-camera scene "just works").
        if (World != null && World.ActiveCamera == 0) MakeCurrent();
    }
}
