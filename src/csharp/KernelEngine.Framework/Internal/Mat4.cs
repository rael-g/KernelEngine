using System.Numerics;

namespace KernelEngine.Framework.Internal;

/// <summary>
/// Column-major 4x4 matrix helpers that mirror the conventions of <c>ke_mat4_*</c>
/// (right-handed, Vulkan depth [0,1]). Internal — exposed only to other Framework
/// render systems that build matrices for the frame packet.
/// </summary>
/// <remarks>
/// The values are written into the <see cref="Matrix4x4"/> field slots so that the flat
/// 16-float index <c>i*4+j</c> maps to <c>M(i+1)(j+1)</c> — i.e. the same column-major slot
/// order as <c>ke_mat4.m[i*4+j]</c>. The concrete <c>FramePacket.ToKeMat4</c> blits these
/// bytes verbatim, so the result lands in ke_mat4 layout with no transpose.
/// </remarks>
internal static class Mat4
{
    public static Matrix4x4 Perspective(float fov, float aspect, float near, float far)
    {
        var f = 1f / MathF.Tan(fov * 0.5f);
        return new Matrix4x4
        {
            M11 = f / aspect,
            M22 = f,
            M33 = -far / (far - near),
            M34 = -1f,
            M43 = -(far * near) / (far - near),
        };
    }

    public static Matrix4x4 Ortho(float left, float right, float bottom, float top, float near, float far) =>
        new()
        {
            M11 = 2f / (right - left),
            M22 = 2f / (top - bottom),
            M33 = 1f / (far - near),
            M41 = -(right + left) / (right - left),
            M42 = -(top + bottom) / (top - bottom),
            M43 = -near / (far - near),
            M44 = 1f,
        };

    /// <summary>
    /// Inverse of a TRS (translation + rotation + scale) matrix in column-major layout.
    /// Assumes orthonormal rotation: transpose the 3x3 basis and negate the rotated translation.
    /// </summary>
    public static Matrix4x4 InvertTrs(Matrix4x4 w)
    {
        Matrix4x4 r = default;
        // Transpose the 3x3 rotation block (column-major slots).
        r.M11 = w.M11; r.M12 = w.M21; r.M13 = w.M31; r.M14 = 0f;
        r.M21 = w.M12; r.M22 = w.M22; r.M23 = w.M32; r.M24 = 0f;
        r.M31 = w.M13; r.M32 = w.M23; r.M33 = w.M33; r.M34 = 0f;
        // Inverse translation: -(R^T · t), with t in slots M41..M43.
        r.M41 = -(r.M11 * w.M41 + r.M21 * w.M42 + r.M31 * w.M43);
        r.M42 = -(r.M12 * w.M41 + r.M22 * w.M42 + r.M32 * w.M43);
        r.M43 = -(r.M13 * w.M41 + r.M23 * w.M42 + r.M33 * w.M43);
        r.M44 = 1f;
        return r;
    }

    /// <summary>Right-handed look-at view matrix in column-major layout.</summary>
    public static Matrix4x4 LookAt(Vector3 eye, Vector3 at, Vector3 up)
    {
        var z = Vector3.Normalize(at - eye);          // forward
        var x = Vector3.Normalize(Vector3.Cross(up, z)); // right = up × forward
        var y = Vector3.Cross(z, x);                  // up = forward × right

        Matrix4x4 r = default;
        r.M11 = x.X; r.M21 = x.Y; r.M31 = x.Z;
        r.M12 = y.X; r.M22 = y.Y; r.M32 = y.Z;
        r.M13 = z.X; r.M23 = z.Y; r.M33 = z.Z;
        r.M41 = -Vector3.Dot(x, eye);
        r.M42 = -Vector3.Dot(y, eye);
        r.M43 = -Vector3.Dot(z, eye);
        r.M44 = 1f;
        return r;
    }
}
