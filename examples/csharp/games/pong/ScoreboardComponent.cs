using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Pong;

/// <summary>
/// ECS component the scene loader applies from <c>[entity.scoreboard]</c>. Holds
/// the font the scoreboard draws its labels with.
/// </summary>
/// <remarks>
/// A component rather than plain properties on the node: what a scene authors has
/// to be data the engine can read, or it reaches only the language the node
/// happens to be written in.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
public struct ScoreboardComponent
{
    /// <summary>Empty falls back to the system font.</summary>
    public FontPathBuffer FontPath;
    public float          FontSize;
}

/// <summary>Fixed-size UTF-8 buffer for the font path.</summary>
[InlineArray(128)]
public struct FontPathBuffer
{
    private byte _first;
}
