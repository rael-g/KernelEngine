namespace KernelEngine.Input;

/// <summary>
/// Thread-local accessor for the input reader of the current simulation frame.
/// </summary>
public static class InputContext
{
    [ThreadStatic]
    private static IInputReader? s_current;

    /// <summary>
    /// The reader bound on the calling thread. Throws <see cref="InvalidOperationException"/> when
    /// none is bound.
    /// </summary>
    public static IInputReader Current =>
        s_current ?? throw new InvalidOperationException("InputContext.Current is only available during the simulation update.");

    /// <summary>Binds the reader for the calling thread, or unbinds it when
    /// <paramref name="reader"/> is null.</summary>
    public static void Set(IInputReader? reader) => s_current = reader;
}
