using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;

namespace Pong;

/// <summary>What Pong's node types share: the actions every one of them reads.</summary>
sealed class Game
{
    /// <summary>Serves the ball, and starts a match from the menu.</summary>
    public ActionRef Launch = NodeWorld.Action("Launch");

    /// <summary>Leaves a match for the menu, and the menu for the desktop.</summary>
    public ActionRef Quit = NodeWorld.Action("Quit");
}

/// <summary>A ball reached a goal line.</summary>
struct GoalScored
{
    public bool LeftScored;
}

/// <summary>The ball was served.</summary>
struct BallLaunched
{
    public bool Launched;
}
