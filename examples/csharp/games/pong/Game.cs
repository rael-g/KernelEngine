using System.Runtime.CompilerServices;

using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;

namespace Pong;

/// <summary>What Pong's node types share: the actions every one of them reads.</summary>
sealed class Game
{
    /// <summary>Serves the ball, and starts a match from the menu.</summary>
    public ActionRef Launch;

    /// <summary>Leaves a match for the menu, and the menu for the desktop.</summary>
    public ActionRef Quit;

    /// <summary>The actions named as the project's input maps name them.</summary>
    public Game()
    {
        Launch.NameText = "Launch";
        Quit.NameText = "Quit";
    }
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

/// <summary>The path of a sound file, as a scene writes it.</summary>
[InlineArray(256)]
struct SoundPath
{
    byte _first;
}
