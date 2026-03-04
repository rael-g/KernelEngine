using System;

namespace KernelEngine.Core;

/// @brief Internal-use interface to access native handles from managed wrappers.
/// This is implemented explicitly to hide native pointers from end-users.
public interface INativeHandle
{
    /// @brief Gets the raw native pointer.
    IntPtr Handle { get; }
}
