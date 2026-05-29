using KernelEngine.Framework;

namespace Pong;

/// <summary>
/// On-screen scoreboard: owns the score counters + hint <see cref="Label"/> children declared
/// in <c>scenes/Main.scene</c>, loads the font once via <see cref="Assets"/>, and applies it to
/// each child label so they start rendering. <see cref="Ball"/> finds this node by path and
/// calls <see cref="SetScore"/> / <see cref="HideHint"/> instead of writing to the console.
/// </summary>
public sealed class Scoreboard : Node
{
    private readonly Assets _assets;

    public Scoreboard(Assets assets) { _assets = assets; }

    /// <summary>Path to the TTF/OTF file. Empty = no font load (labels stay invisible).</summary>
    public string FontPath { get; set; } = "";
    public float  FontSize { get; set; } = 48f;

    private Label? _left;
    private Label? _right;
    private Label? _hint;

    protected override async void Start()
    {
        base.Start();
        _left  = GetNode<Label>("Left");
        _right = GetNode<Label>("Right");
        _hint  = GetNode<Label>("Hint");

        if (!string.IsNullOrEmpty(FontPath))
        {
            var font = await _assets.LoadFontAsync(FontPath, FontSize);
            if (_left  != null) _left.Font  = font;
            if (_right != null) _right.Font = font;
            if (_hint  != null) _hint.Font  = font;
        }
    }

    public void SetScore(int left, int right)
    {
        if (_left  != null) _left.Text  = left.ToString();
        if (_right != null) _right.Text = right.ToString();
    }

    public void ShowHint(string text) { if (_hint != null) _hint.Text = text; }
    public void HideHint()            { if (_hint != null) _hint.Text = ""; }
}
