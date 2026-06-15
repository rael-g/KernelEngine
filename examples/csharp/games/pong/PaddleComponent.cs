using System.Runtime.InteropServices;

namespace Pong;

/// <summary>
/// ECS component applied by the scene loader from <c>[entity.components.paddle]</c>.
/// Stores the input action that controls this paddle.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct PaddleComponent
{
    public PongAction MoveAction;
}
