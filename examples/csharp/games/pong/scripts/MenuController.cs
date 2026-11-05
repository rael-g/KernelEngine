using System.Numerics;

using KernelEngine.Framework;
using KernelEngine.Render;
using KernelEngine.Text;

namespace Pong;

/// <summary>
/// Menu scene root: spawns the title + hint labels (Label needs a Font
/// instance which isn't loadable directly from scene properties yet), and
/// drives the transition to the Main scene on Launch / quit on Quit.
/// </summary>
public sealed partial class MenuController : Node
{
    private readonly ISceneRouter _router;
    private readonly IFontLoader _fontLoader;
    private readonly IRenderResources _resources;

    private Font? _font;

    /// <summary>The action that starts a match.</summary>
    public partial InputAction Launch { get; set; }

    /// <summary>The action that closes the game.</summary>
    public partial InputAction Quit { get; set; }

    public MenuController(ISceneRouter router, IFontLoader fontLoader, IRenderResources resources)
    {
        Launch = "Launch";
        Quit = "Quit";
        _router = router;
        _fontLoader = fontLoader;
        _resources = resources;
    }

    protected override void OnBind(ScriptHost scriptHost)
    {
        var fontPath = ExamplePaths.SystemFont;
        _font = Font.Load(_resources, _fontLoader, fontPath, pixelSize: 72f);

        AddChild(new Label
        {
            Text = "Pong",
            Font = fontPath,
            FontSize = 72f,
            Color = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.5f, 0.0f),
            Offset = new Vector2(0f, 140f),
        }, "Title");

        AddChild(new Label
        {
            Text = "Press Space to start",
            Font = fontPath,
            FontSize = 72f,
            Color = new Vector4(0.7f, 0.7f, 0.7f, 1f),
            Anchor = new Vector2(0.5f, 1.0f),
            Offset = new Vector2(0f, -120f),
        }, "Hint");
    }

    void Update(in View view)
    {
        if (Launch.JustPressed) _router.LoadScene<Scenes.Main>();
        if (Quit.JustPressed) Environment.Exit(0);
    }
}
