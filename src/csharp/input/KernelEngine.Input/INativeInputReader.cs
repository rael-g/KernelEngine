using KernelEngine.Input.Native;

namespace KernelEngine.Input;

/// <summary>
/// Exposes the raw <c>ke_input_snapshot</c> value backing an <see cref="IInputReader"/>.
/// Implemented by the snapshot reader <see cref="Input.CaptureSnapshot"/> returns, so the
/// snapshot can be handed to another native vtable without depending on a specific
/// <see cref="IInputReader"/> implementation.
/// </summary>
public interface INativeInputReader
{
    /// <summary>A copy of the snapshot the reader was captured from.</summary>
    ke_input_snapshot Native { get; }
}
