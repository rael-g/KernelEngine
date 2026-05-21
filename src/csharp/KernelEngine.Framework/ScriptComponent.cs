using System.Runtime.InteropServices;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// ECS component holding the managed script callbacks for a node.
/// Memory layout matches <c>ke_script_component</c> exactly:
/// byte started at offset 0, two function pointers at offsets 8 and 16.
/// </summary>
[StructLayout(LayoutKind.Explicit, Size = 24)]
public unsafe struct ScriptComponent
{
    [FieldOffset(0)] public byte Started;
    [FieldOffset(8)]  public delegate* unmanaged[Cdecl]<ulong, KernelResult> OnStart;
    [FieldOffset(16)] public delegate* unmanaged[Cdecl]<ulong, float, KernelResult> OnUpdate;
}
