using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Internal;

/// <summary>
/// The matrix-convention adapter (ADR-10). The engine builds exactly two kinds of matrix itself —
/// the camera/light <b>view</b> and the <b>projection</b> — and both are convention-bound in ways no
/// general-purpose math library targets: projection depends on the backend's NDC (depth range, Y),
/// and the view depends on a fixed handedness. So these builders are the irreducible bridge between
/// "any math library" and "any backend": System.Numerics does the vector/inverse math; this type
/// emits the matrix in the active backend's convention.
/// </summary>
/// <remarks>
/// Everything else (world transforms, view = inverse-of-world, lerps) uses <see cref="Matrix4x4"/>
/// directly. Results here are written into <see cref="Matrix4x4"/> slots so the flat bytes are the
/// column-major <c>ke_mat4</c> layout; <c>FramePacket.ToKeMat4</c> blits them verbatim. Right-handed.
/// </remarks>
internal static class ViewProjection
{
    private static NdcConvention _convention = NdcConvention.Default;

    /// <summary>Set once at startup from the active backend (Application / ke.render init).</summary>
    internal static void SetConvention(NdcConvention convention) => _convention = convention;

    /// <summary>
    /// View matrix in the engine convention (right-handed, forward = +(target - eye)). Differs from
    /// <see cref="Matrix4x4.CreateLookAt"/> (zaxis = eye - target), which would flip handedness and
    /// misalign with the camera view (inverse of the kernel world matrix).
    /// </summary>
    public static Matrix4x4 LookAt(Vector3 eye, Vector3 target, Vector3 up)
    {
        var f = Vector3.Normalize(target - eye);         // forward (toward target)
        var r = Vector3.Normalize(Vector3.Cross(up, f)); // right
        var u = Vector3.Cross(f, r);                     // up
        // Column-major: basis vectors as rows 0..2, translation in column 3.
        return new Matrix4x4(
            r.X, u.X, f.X, 0f,
            r.Y, u.Y, f.Y, 0f,
            r.Z, u.Z, f.Z, 0f,
            -Vector3.Dot(r, eye), -Vector3.Dot(u, eye), -Vector3.Dot(f, eye), 1f);
    }

    public static Matrix4x4 Perspective(float fovY, float aspect, float near, float far)
    {
        var f = 1f / MathF.Tan(fovY * 0.5f);
        var m = new Matrix4x4
        {
            M11 = f / aspect,
            M22 = _convention.YFlip ? -f : f,
            M34 = -1f, // right-handed: w_clip = -z_view
        };
        if (_convention.ZeroToOneDepth)
        {
            m.M33 = -far / (far - near);
            m.M43 = -(far * near) / (far - near);
        }
        else // OpenGL-style depth [-1,1]
        {
            m.M33 = -(far + near) / (far - near);
            m.M43 = -(2f * far * near) / (far - near);
        }
        return m;
    }

    public static Matrix4x4 Ortho(float left, float right, float bottom, float top, float near, float far)
    {
        // Right-handed to match Perspective (camera looks down -Z; view-space Z is negative for
        // content in front). M33/M43 derived so view-z in [-near, -far] maps to NDC z in [0, 1]
        // (D3D-style) or [-1, 1] (GL-style). Earlier this matrix was accidentally LH and any
        // Camera2D placed at +Z saw a blank screen because its content sat outside the frustum.
        var m = new Matrix4x4
        {
            M11 = 2f / (right - left),
            M22 = (_convention.YFlip ? -2f : 2f) / (top - bottom),
            M41 = -(right + left) / (right - left),
            M42 = -(top + bottom) / (top - bottom),
            M44 = 1f,
        };
        if (_convention.ZeroToOneDepth)
        {
            m.M33 = -1f / (far - near);
            m.M43 = -near / (far - near);
        }
        else // OpenGL-style depth [-1,1]
        {
            m.M33 = -2f / (far - near);
            m.M43 = -(far + near) / (far - near);
        }
        return m;
    }
}
