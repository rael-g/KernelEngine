namespace KernelEngine.Kernel;

/// <summary>
/// Thread-local accessor for the input reader of the current simulation frame.
/// The Framework sets this once at the start of every ke.sim tick; game code (typically
/// <c>Node.Update</c>) reads <see cref="Current"/> to poll keys/buttons/mouse.
/// Lives in Abstractions so any layer can read it without referencing the Kernel concrete.
/// </summary>
public static class InputContext
{
    [ThreadStatic]
    private static IInputReader? s_current;

    /// <summary>
    /// The input snapshot for the current frame. Throws when called outside the sim tick
    /// (i.e. from <c>OnReady</c> or arbitrary threads).
    /// </summary>
    public static IInputReader Current =>
        s_current ?? throw new InvalidOperationException("InputContext.Current is only available during the simulation update.");

    /// <summary>Engine-internal: bind/unbind the per-frame reader. Game code does not call this.</summary>
    public static void Set(IInputReader? reader) => s_current = reader;
}
