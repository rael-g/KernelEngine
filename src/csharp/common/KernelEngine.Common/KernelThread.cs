using System.Runtime.InteropServices;
using KernelEngine.Common.Native;

namespace KernelEngine.Common;

/// <summary>
/// Static helpers around the cross-language thread-name TLS slot in the C kernel
/// (<c>ke_thread_set_current_name</c> / <c>ke_thread_assert_current</c>). Used by
/// C# code to publish the calling thread's identity so C plugins (bgfx renderer,
/// future Lua/Rust bindings) can assert affinity via the same TLS slot.
/// <para>
/// Thread spawning lives in <see cref="System.Threading.Thread"/> directly — there
/// is no longer a managed wrapper for the deleted <c>ke_thread</c> contract.
/// </para>
/// </summary>
public static unsafe class KernelThread
{
    // ke_thread_set_current_name stores the raw pointer in TLS without copying.
    // We keep one allocation alive per thread so the pointer stays valid for the
    // thread's lifetime. Previous allocation is freed when a new name is set.
    [ThreadStatic]
    private static nint _currentNamePtr;

    /// <summary>Sets the kernel-side TLS name of the calling thread.</summary>
    public static void SetCurrentName(string name)
    {
        var prev = _currentNamePtr;
        var nameBytes = Marshal.StringToHGlobalAnsi(name);
        _currentNamePtr = nameBytes;
        NativeMethods.thread_set_current_name((sbyte*)nameBytes);
        if (prev != 0) Marshal.FreeHGlobal(prev);
    }

    /// <summary>Returns the TLS name of the calling thread (or "unknown" if never set).</summary>
    public static string GetCurrentName()
    {
        var ptr = NativeMethods.thread_get_current_name();
        return Marshal.PtrToStringAnsi((IntPtr)ptr) ?? "unknown";
    }

    /// <summary>
    /// Asserts that the calling thread's TLS name matches <paramref name="expectedName"/>.
    /// Throws <see cref="InvalidOperationException"/> in debug builds when the names diverge.
    /// </summary>
    public static void AssertCurrent(string expectedName)
    {
#if DEBUG
        var current = GetCurrentName();
        if (current != expectedName)
            throw new InvalidOperationException(
                $"Thread affinity violation: expected '{expectedName}', current is '{current}'.");
#endif
    }
}
