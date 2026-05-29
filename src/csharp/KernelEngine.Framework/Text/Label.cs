using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// A screen-space text node — renders <see cref="Text"/> via the UI overlay pass using <see cref="Font"/>.
/// Position is computed from <see cref="Anchor"/> (a normalized [0..1] point in the backbuffer) plus
/// <see cref="Offset"/> (pixels from that anchor). The anchor is also the label's own pivot, so e.g.
/// <c>Anchor = (0.5, 0)</c> + <c>Offset = (0, 50)</c> places the label horizontally centered at the
/// top with 50px of breathing room.
/// </summary>
/// <remarks>
/// MVP scope: single-line text only — newlines are not handled. The label renders at the font's
/// baked size; mid-flight resize is not supported (load a separate font at the desired size).
/// </remarks>
public class Label : Node
{
    // Tree-wide registry. <see cref="LabelRenderSystem"/> iterates this list each frame. Same
    // pattern as <see cref="CollisionBody2D"/>'s body→node map: avoids a per-frame tree walk
    // and survives nodes living anywhere in the tree.
    private static readonly List<Label> s_all = new();
    private static readonly object s_lock = new();

    internal static IReadOnlyList<Label> Snapshot()
    {
        lock (s_lock) return s_all.ToArray();
    }

    private bool _registered;

    public string  Text   { get; set; } = string.Empty;
    public Font?   Font   { get; set; }
    public Vector4 Color  { get; set; } = Vector4.One;

    /// <summary>Normalized [0..1] position in the backbuffer. (0,0)=TL, (0.5,0)=top-center, (1,1)=BR.</summary>
    public Vector2 Anchor { get; set; } = Vector2.Zero;

    /// <summary>Pixels added to the anchor position. The label's own pivot follows <see cref="Anchor"/>.</summary>
    public Vector2 Offset { get; set; } = Vector2.Zero;

    protected override void Start()
    {
        base.Start();
        if (!_registered)
        {
            lock (s_lock) s_all.Add(this);
            _registered = true;
        }
    }

    protected override void OnDestroy()
    {
        if (_registered)
        {
            lock (s_lock) s_all.Remove(this);
            _registered = false;
        }
        base.OnDestroy();
    }
}
