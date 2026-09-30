namespace Pong;

/// <summary>
/// The verbs Pong's game logic speaks. Each value must match an
/// <c>[action.X]</c> table in <c>actions.input</c> (case-insensitive).
/// </summary>
public enum PongAction
{
    PaddleLeftMove,
    PaddleRightMove,
    Launch,
    Quit,
}
