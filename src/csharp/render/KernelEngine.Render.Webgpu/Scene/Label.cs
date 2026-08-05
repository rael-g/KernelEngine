using System.Numerics;
using System.Text;
using KernelEngine.Render.Webgpu.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Screen-space text node. Position is computed each frame as
/// <c>Anchor × backbufferSize + Offset</c>, then pivoted by <see cref="Anchor"/>
/// applied to the measured text size. Every property write-through updates the
/// native "label" component; the "render.ui" pass (src/zig/render/ui) shapes
/// the text into glyph quads and draws them itself — no per-glyph entity, no
/// CPU-side accumulator, no C# system involved.
/// </summary>
public class Label : Node3D
{
    private ke_label_component _state;
    private string _text = string.Empty;
    private Font?  _font;

    public string Text
    {
        get => _text;
        set { _text = value; WriteText(value); WriteIfBound(); }
    }

    public Font? Font
    {
        get => _font;
        set { _font = value; _state.font = value?.Handle is { } h ? new ke_ui_font_handle { bits = h.Value } : default; WriteIfBound(); }
    }

    public Vector4 Color
    {
        get => new(_state.color[0], _state.color[1], _state.color[2], _state.color[3]);
        set { _state.color[0] = value.X; _state.color[1] = value.Y; _state.color[2] = value.Z; _state.color[3] = value.W; WriteIfBound(); }
    }

    /// <summary>Anchor in normalized [0..1] of the backbuffer. (0,0) = top-left, (1,1) = bottom-right.</summary>
    public Vector2 Anchor
    {
        get => new(_state.anchor[0], _state.anchor[1]);
        set { _state.anchor[0] = value.X; _state.anchor[1] = value.Y; WriteIfBound(); }
    }

    /// <summary>Pixel offset applied AFTER anchor positioning.</summary>
    public Vector2 Offset
    {
        get => new(_state.offset[0], _state.offset[1]);
        set { _state.offset[0] = value.X; _state.offset[1] = value.Y; WriteIfBound(); }
    }

    public Label() => Color = Vector4.One;

    // Matches KE_LABEL_MAX_TEXT (ui_create.h) — the native "label" component's
    // text field is a fixed-size C ABI buffer, same tradeoff as ke_name_component.
    private const int MaxTextBytes = 256;

    private void WriteText(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        var n = Math.Min(bytes.Length, MaxTextBytes - 1);
        for (int i = 0; i < n; i++) _state.text[i] = (sbyte)bytes[i];
        for (int i = n; i < MaxTextBytes; i++) _state.text[i] = 0;
    }

    private uint _labelCid;

    private void WriteIfBound()
    {
        if (!IsBound) return;
        if (_labelCid == 0) _labelCid = NodeWorld!.CidOfName("label");
        NodeWorld!.SetByCid(Entity, _labelCid, _state);
    }

    protected override void OnBind(NodeWorld nodeWorld)
    {
        _labelCid = nodeWorld.CidOfName("label");
        nodeWorld.SetByCid(Entity, _labelCid, _state);
    }
}
