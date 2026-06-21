

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A scene-graph node that acts as a camera. Add it to a tree (<c>tree.AddNode(new Camera())</c>)
/// and it auto-activates when no other camera is current. Switch with <see cref="MakeCurrent"/>.
/// </summary>
public class Camera : Node
{
    // Backing fields hold values supplied before Start; after Start the ECS slot is authoritative
    // and the property accessors mirror through it (same pattern as DirectionalLight).
    private uint  _componentId = uint.MaxValue;
    private float _fov              = 60f;
    private float _near             = 0.1f;
    private float _far              = 1000f;
    private float _orthographicSize = 5f;
    private bool  _orthographic     = false;

    /// <summary>Vertical field of view in degrees (perspective mode only).</summary>
    public float Fov
    {
        get { var s = Slot(); return s.IsEmpty ? _fov : s[0].Fov * 180f / MathF.PI; }
        set { _fov = value; var s = Slot(); if (!s.IsEmpty) s[0].Fov = value * MathF.PI / 180f; }
    }

    /// <summary>Near clip plane distance.</summary>
    public float Near
    {
        get { var s = Slot(); return s.IsEmpty ? _near : s[0].Near; }
        set { _near = value; var s = Slot(); if (!s.IsEmpty) s[0].Near = value; }
    }

    /// <summary>Far clip plane distance.</summary>
    public float Far
    {
        get { var s = Slot(); return s.IsEmpty ? _far : s[0].Far; }
        set { _far = value; var s = Slot(); if (!s.IsEmpty) s[0].Far = value; }
    }

    /// <summary>
    /// Half-height of the orthographic viewport in world units (orthographic mode only).
    /// E.g. <c>5</c> = viewport is 10 units tall; width derives from aspect ratio.
    /// </summary>
    public float OrthographicSize
    {
        get { var s = Slot(); return s.IsEmpty ? _orthographicSize : s[0].OrthographicSize; }
        set { _orthographicSize = value; var s = Slot(); if (!s.IsEmpty) s[0].OrthographicSize = value; }
    }

    /// <summary>Use orthographic projection instead of perspective.</summary>
    public bool Orthographic
    {
        get { var s = Slot(); return s.IsEmpty ? _orthographic : s[0].Orthographic != 0; }
        set { _orthographic = value; var s = Slot(); if (!s.IsEmpty) s[0].Orthographic = value ? (byte)1 : (byte)0; }
    }

    /// <summary>True when this camera is the one the render system draws from.</summary>
    public bool IsCurrent => World != null && World.ActiveCamera == Entity;

    /// <summary>
    /// Make this the current camera. Deactivates any other camera that was current (last-wins).
    /// </summary>
    public void MakeCurrent()
    {
        if (World != null) World.ActiveCamera = Entity;
    }

    private Span<CameraComponent> Slot() =>
        _componentId == uint.MaxValue ? Span<CameraComponent>.Empty : GetComponent<CameraComponent>(_componentId);

    protected override void Start()
    {
        if (World == null) return;

        // Phase 5.3: pull scene-authored values from the bag (fallback to current
        // backing fields so legacy reflection-set values still take effect).
        _fov              = Properties.GetFloat("Fov",              _fov);
        _near             = Properties.GetFloat("Near",             _near);
        _far              = Properties.GetFloat("Far",              _far);
        _orthographicSize = Properties.GetFloat("OrthographicSize", _orthographicSize);
        _orthographic     = Properties.GetBool ("Orthographic",     _orthographic);

        _componentId = World.GetOrRegisterComponentId<CameraComponent>("CameraComponent");
        var comp = AddComponent<CameraComponent>(_componentId);
        comp[0] = new CameraComponent
        {
            Fov              = _fov * MathF.PI / 180f,
            Near             = _near,
            Far              = _far,
            OrthographicSize = _orthographicSize,
            Orthographic     = _orthographic ? (byte)1 : (byte)0,
        };
        // Auto-activate when no camera is current yet (so a single-camera scene "just works").
        if (World.ActiveCamera == 0) MakeCurrent();
    }
}
