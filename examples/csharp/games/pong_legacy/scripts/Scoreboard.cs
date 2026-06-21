

namespace Pong;

/// <summary>
/// On-screen scoreboard. Owns score counters + hint <see cref="Label"/> children declared in
/// <c>scenes/Main.scene</c>, loads the font once via <see cref="Assets"/>, applies it to each
/// child label, and exposes the gameplay-facing API (<see cref="RecordGoal"/>, <see cref="ShowHint"/>).
/// Score state lives here, not on <see cref="Ball"/> — multi-ball variants reuse this same scoreboard.
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

    /// <summary>Goals scored by the left side. Read-only to consumers.</summary>
    public int Left  { get; private set; }
    /// <summary>Goals scored by the right side.</summary>
    public int Right { get; private set; }
    /// <summary>Total goals (used by <see cref="Ball"/> to alternate the launch direction).</summary>
    public int Total => Left + Right;

    protected override async void Start()
    {
        base.Start();

        // New scene format ([entity.properties] FontPath/FontSize): pull from the bag with the
        // current field as fallback so the legacy reflection-set path still works.
        FontPath = Properties.GetString("FontPath", FontPath);
        FontSize = Properties.GetFloat ("FontSize", FontSize);

        try
        {
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
        catch (Exception ex)
        {
            // async void swallows exceptions silently into the scheduler's state machine;
            // surface to stderr so a missing font / bad path is debuggable instead of
            // 'labels just don't render and I have no idea why'.
            Console.Error.WriteLine($"Scoreboard.Start failed: {ex}");
        }
    }

    /// <summary>Records a goal for one side, updates the displayed counter, and returns the new total.</summary>
    public int RecordGoal(bool leftSide)
    {
        if (leftSide) Left++; else Right++;
        if (_left  != null) _left.Text  = Left.ToString();
        if (_right != null) _right.Text = Right.ToString();
        return Total;
    }

    public void ShowHint(string text) { if (_hint != null) _hint.Text = text; }
    public void HideHint()            { if (_hint != null) _hint.Text = ""; }
}
