using System.Runtime.InteropServices;

namespace KernelEngine.Kernel;

/// <summary>
/// ECS component that stores a UTF-8 entity name (up to 63 bytes).
/// Memory layout matches <c>ke_name_component</c> exactly.
/// </summary>
[StructLayout(LayoutKind.Sequential, Size = 64)]
public unsafe struct NameComponent
{
    public fixed byte name[64];
}
