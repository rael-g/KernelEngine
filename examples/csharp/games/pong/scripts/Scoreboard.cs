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
public sealed partial class Scoreboard : Node
{
    private readonly IFontLoader     _fontLoader;
    private readonly IRenderResources _resources;

    private Font?  _font;
    private Label? _left;
    private Label? _right;
    private Label? _hint;

    private const float DefaultFontSize = 48f;

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
        // Read from the component the scene authored, not from a property on this
        // node: what a scene writes has to be data, or only C# can read it back.
        var path = ExamplePaths.SystemFont;
        var size = DefaultFontSize;
        if (TryGetComponent<ScoreboardComponent>("scoreboard", out var cfg))
        {
            var declared = System.Text.Encoding.UTF8.GetString(
                ((ReadOnlySpan<byte>)cfg.FontPath)[..((ReadOnlySpan<byte>)cfg.FontPath).IndexOf((byte)0)]);
            if (!string.IsNullOrEmpty(declared)) path = declared;
            if (cfg.FontSize > 0f) size = cfg.FontSize;
        }
        _font = Font.Load(_resources, _fontLoader, path, pixelSize: size);

        _left  = AddChild(new Label
        {
            Text   = "0",
            Font   = _font.Handle,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.30f, 0f),
            Offset = new Vector2(0f, 60f),
        }, "ScoreLeft");

        _right = AddChild(new Label
        {
            Text   = "0",
            Font   = _font.Handle,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.70f, 0f),
            Offset = new Vector2(0f, 60f),
        }, "ScoreRight");

        _hint  = AddChild(new Label
        {
            Text   = "",
            Font   = _font.Handle,
            Color  = new Vector4(0.7f, 0.7f, 0.7f, 1f),
            Anchor = new Vector2(0.5f, 1f),
            Offset = new Vector2(0f, -80f),
        }, "ScoreHint");
    }

    /// <summary>Clears the launch hint once play actually starts.</summary>
    void On(in BallLaunched e) => HideHint();

    /// <summary>Reacts to the ball's goal signal: records the point and re-arms the hint.</summary>
    void On(in GoalScored e)
    {
        RecordGoal(e.LeftScored);
        ShowHint("Press Space to launch");
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
