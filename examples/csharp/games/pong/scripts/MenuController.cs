using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// Menu scene root: spawns the title + hint labels (Label needs a Font
/// instance which isn't loadable directly from scene properties yet), and
/// drives the transition to the Main scene on Launch / quit on Quit.
/// </summary>
public sealed class MenuController : Node
{
    private readonly IInputActionMap<PongAction> _actions;
    private readonly ISceneRouter                _router;
    private readonly IFontLoader                 _fontLoader;

    private Font? _font;
    private bool _prevLaunch;
    private bool _prevQuit;

    public MenuController(IInputActionMap<PongAction> actions, ISceneRouter router, IFontLoader fontLoader)
    {
        _actions    = actions;
        _router     = router;
        _fontLoader = fontLoader;
    }

    protected override void OnBind(Tree tree)
    {
        var fontPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), "arial.ttf");
        _font = Font.Load(tree.Renderer, _fontLoader, fontPath, pixelSize: 72f);

        tree.AddNode(new Label
        {
            Text   = "Pong",
            Font   = _font,
            Color  = new Vector4(0.95f, 0.95f, 0.95f, 1f),
            Anchor = new Vector2(0.5f, 0.0f),
            Offset = new Vector2(0f, 140f),
        }, "Title", parent: this);

        tree.AddNode(new Label
        {
            Text   = "Press Space to start",
            Font   = _font,
            Color  = new Vector4(0.7f, 0.7f, 0.7f, 1f),
            Anchor = new Vector2(0.5f, 1.0f),
            Offset = new Vector2(0f, -120f),
        }, "Hint", parent: this);
    }

    protected override void OnUnbind() => _font?.Dispose();

    protected override void OnUpdate(in View view)
    {
        bool launch = _actions.IsPressed(PongAction.Launch, in view);
        bool quit   = _actions.IsPressed(PongAction.Quit,   in view);
        if (launch && !_prevLaunch) _router.LoadScene("Main");
        if (quit   && !_prevQuit)   Environment.Exit(0);
        _prevLaunch = launch;
        _prevQuit   = quit;
    }
}
