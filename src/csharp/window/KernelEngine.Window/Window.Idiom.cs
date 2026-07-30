namespace KernelEngine.Window;

/// <summary>
/// Declares <see cref="Window"/>'s conformance to the game-facing <see cref="IWindow"/>
/// abstraction. No logic: the generated members in <c>Generated/Window.g.cs</c> already
/// match the interface's shape 1:1 (ShouldClose/PollEvents/GetSize/GetNativeHandle) —
/// kabic doesn't know about this hand-authored interface, so a partial class
/// declaration is enough to attach it.
/// </summary>
public sealed unsafe partial class Window : IWindow
{
}
