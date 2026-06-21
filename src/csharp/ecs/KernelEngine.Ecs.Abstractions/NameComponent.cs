using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace KernelEngine.Ecs;

/// <summary>
/// ECS component that stores a UTF-8 entity name (up to 63 bytes plus terminator).
/// Layout matches the native <c>ke_name_component</c>.
/// </summary>
[StructLayout(LayoutKind.Sequential, Size = 64)]
public struct NameComponent
{
    public NameBuffer Name;
}

/// <summary>Fixed-size 64-byte buffer for entity name bytes.</summary>
[InlineArray(64)]
public struct NameBuffer
{
    private byte _first;
}
