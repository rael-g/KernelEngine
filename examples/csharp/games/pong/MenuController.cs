using KernelEngine.Framework.Nodes;

namespace Pong;

/// <summary>The menu: Launch starts a match, Quit ends the program.</summary>
[NodeType("pong.menu_controller")]
partial class MenuController : Node
{
    void Update()
    {
        if (Pressed("Launch")) ChangeScene(Scenes.Main);
        else if (Pressed("Quit")) Exit();
    }
}
