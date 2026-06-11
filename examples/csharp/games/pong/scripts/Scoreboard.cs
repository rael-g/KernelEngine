using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// On-screen scoreboard: three Labels (left score, right score, hint) and
/// the score counters. The board owns the Font (loaded once at construction)
/// and disposes it when the scene tears down — sharing it across all three
/// labels avoids three separate atlas uploads.
/// </summary>
public sealed class Scoreboard : Node
{
    private readonly Tree   _tree;
    private readonly Font   _font;
    private readonly Label  _left;
    private readonly Label  _right;
    private readonly Label  _hint;

    public int Left  { get; private set; }
    public int Right { get; private set; }
    public int Total => Left + Right;

    public Scoreboard(Tree tree, IFontLoader fontLoader, float fontSize)
    {
        _tree  = tree;
        var fontPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), "arial.ttf");
        _font  = Font.Load(tree.Renderer, fontLoader, fontPath, pixelSize: fontSize);

        _left  = tree.AddNode(new Label
        {
            Text   = "0",
            Font   = _font,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.30f, 0f),
            Offset = new Vector2(0f, 60f),
        }, "ScoreLeft");

        _right = tree.AddNode(new Label
        {
            Text   = "0",
            Font   = _font,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.70f, 0f),
            Offset = new Vector2(0f, 60f),
        }, "ScoreRight");

        _hint  = tree.AddNode(new Label
        {
            Text   = "",
            Font   = _font,
            Color  = new Vector4(0.7f, 0.7f, 0.7f, 1f),
            Anchor = new Vector2(0.5f, 1f),
            Offset = new Vector2(0f, -80f),
        }, "ScoreHint");
    }

    protected override void OnBind(Tree tree) { }

    public void RecordGoal(bool leftScored)
    {
        if (leftScored) Left++; else Right++;
        _left.Text  = Left.ToString();
        _right.Text = Right.ToString();
    }

    public void ShowHint(string text) => _hint.Text = text;
    public void HideHint()             => _hint.Text = "";
}
