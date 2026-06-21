using System.Runtime.InteropServices;

namespace KernelEngine.Common;

/// <summary>
/// Static-mesh vertex format. Layout matches the engine's standard vertex
/// (Position + Normal + UV + Tangent) and is marshaled to the renderer's
/// native vertex buffer by the concrete Renderer implementation.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct Vertex
{
    public float X, Y, Z;
    public float Nx, Ny, Nz;
    public float U, V;
    public float Tx, Ty, Tz, Tw;
}
