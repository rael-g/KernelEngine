using KernelEngine.Input.Native;

namespace KernelEngine.Input;

/// <summary>
/// Exposes the raw <c>ke_input_snapshot</c> value backing an <see cref="IInputReader"/>.
/// Implemented by the snapshot reader <see cref="Input.CaptureSnapshot"/> returns, so a
/// consumer that needs to hand the snapshot to another native vtable (e.g.
/// <c>ke_input_actions.evaluate</c>) can reach it without depending on a specific
/// <see cref="IInputReader"/> implementation.
/// </summary>
public interface INativeInputReader
{
    ke_input_snapshot Native { get; }
}
