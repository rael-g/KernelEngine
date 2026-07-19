using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Text;
using KernelEngine.Render;

namespace Pong;

/// <summary>
/// On-screen scoreboard. Owns three Label children + score counters. The
/// font is loaded once in <see cref="OnBind"/> (which runs on the render
/// worker) and shared across the three labels.
/// </summary>
public sealed class Scoreboard : Node
{
    private readonly IFontLoader     _fontLoader;
    private readonly IRenderResources _resources;

    private Font?  _font;
    private Label? _left;
    private Label? _right;
    private Label? _hint;

    /// <summary>Set by SceneLoader from <c>[entity.properties] FontPath</c>.</summary>
    public string FontPath { get; set; } = "";
    public float  FontSize { get; set; } = 48f;

    public int Left  { get; private set; }
    public int Right { get; private set; }
    public int Total => Left + Right;

    public Scoreboard(IFontLoader fontLoader, IRenderResources resources)
    {
        _fontLoader = fontLoader;
        _resources  = resources;
    }

    protected override void OnBind(NodeWorld nodeWorld)
    {
        var path = string.IsNullOrEmpty(FontPath)
            ? ExamplePaths.SystemFont
            : FontPath;
        _font = Font.Load(_resources, _fontLoader, path, pixelSize: FontSize);

        _left  = nodeWorld.AddNode(new Label
        {
            Text   = "0",
            Font   = _font,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.30f, 0f),
            Offset = new Vector2(0f, 60f),
        }, "ScoreLeft", parent: this);

        _right = nodeWorld.AddNode(new Label
        {
            Text   = "0",
            Font   = _font,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.70f, 0f),
            Offset = new Vector2(0f, 60f),
        }, "ScoreRight", parent: this);

        _hint  = nodeWorld.AddNode(new Label
        {
            Text   = "",
            Font   = _font,
            Color  = new Vector4(0.7f, 0.7f, 0.7f, 1f),
            Anchor = new Vector2(0.5f, 1f),
            Offset = new Vector2(0f, -80f),
        }, "ScoreHint", parent: this);
    }

    public void RecordGoal(bool leftScored)
    {
        if (leftScored) Left++; else Right++;
        if (_left  is not null) _left.Text  = Left.ToString();
        if (_right is not null) _right.Text = Right.ToString();
    }

    public void ShowHint(string text) { if (_hint is not null) _hint.Text = text; }
    public void HideHint()             { if (_hint is not null) _hint.Text = ""; }
}
