using KernelEngine.Framework.Nodes;

namespace Pong;

/// <summary>The menu: Launch starts a match, Quit ends the program.</summary>
[NodeType("pong.menu_controller")]
partial class MenuController(Game game) : Node
{
    void Update()
    {
        if (Pressed(game.Launch)) ChangeScene(Scenes.Main);
        else if (Pressed(game.Quit)) Exit();
    }
}
