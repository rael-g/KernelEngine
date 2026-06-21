

namespace Pong;

/// <summary>
/// The verbs Pong's game logic speaks. Binding-to-key wiring lives in <c>actions.input</c>;
/// the <c>[GameActions]</c> attribute makes the engine pick this enum up on startup — no
/// explicit registration in Program.cs.
/// </summary>
[GameActions]
public enum PongAction
{
    PaddleLeftMove,    // Axis1D: -1 = down, +1 = up
    PaddleRightMove,   // Axis1D
    Launch,            // Button
    Quit,              // Button
}
