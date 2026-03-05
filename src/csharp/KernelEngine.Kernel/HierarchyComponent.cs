using System.Runtime.InteropServices;

namespace KernelEngine;

/// <summary>
/// ECS component that stores scene-graph hierarchy links as entity IDs.
/// Memory layout matches <c>ke_hierarchy_component</c> exactly.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct HierarchyComponent
{
    public ulong Parent;
    public ulong FirstChild;
    public ulong NextSibling;
    public ulong PrevSibling;
}
