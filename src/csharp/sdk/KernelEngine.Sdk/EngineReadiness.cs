using KernelEngine.Completion.Native;

namespace KernelEngine;

/// <summary>
/// The completion a part finishes when it is ready, which the engine waits on before it attaches the modules and
/// starts the loop, and then releases. Registering one is what makes the engine wait on it.
/// </summary>
public sealed unsafe class EngineReadiness
{
    ke_completion* _completion;

    /// <summary>Waits on <paramref name="completion"/>, a <c>ke_completion*</c> the engine takes over; zero waits on nothing.</summary>
    /// <param name="completion">The completion's address, as a factory wrote it.</param>
    public EngineReadiness(nint completion) => _completion = (ke_completion*)completion;

    /// <summary>Whether the part is ready; once it is, the completion is released and the call throws when the part failed.</summary>
    /// <exception cref="Exception">The part finished with a failure.</exception>
    internal bool Ready()
    {
        if (_completion == null) return true;
        var result = KernelEngine.Result.Native.Result.Ok;
        if (!_completion->poll(_completion, &result)) return false;
        _completion->release(_completion);
        _completion = null;
        NativeCall.ThrowIfFailed(result, "ke_completion.poll");
        return true;
    }
}
