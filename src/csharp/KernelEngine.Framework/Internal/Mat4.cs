namespace KernelEngine.Framework.Internal;

/// <summary>
/// Column-major 4x4 matrix helpers that mirror the conventions of <c>ke_mat4_*</c>
/// (right-handed, Vulkan depth [0,1]). Internal — exposed only to other Framework
/// render systems that build matrices for the frame packet.
/// </summary>
internal static unsafe class Mat4
{
    /// <summary>Inverse of a TRS (translation + rotation + scale) matrix. Assumes orthonormal rotation.</summary>
    public static void InvertTrs(float* m, float* o)
    {
        o[0] = m[0]; o[1] = m[4]; o[2] = m[8];   o[3] = 0f;
        o[4] = m[1]; o[5] = m[5]; o[6] = m[9];   o[7] = 0f;
        o[8] = m[2]; o[9] = m[6]; o[10] = m[10]; o[11] = 0f;
        o[12] = -(o[0] * m[12] + o[4] * m[13] + o[8]  * m[14]);
        o[13] = -(o[1] * m[12] + o[5] * m[13] + o[9]  * m[14]);
        o[14] = -(o[2] * m[12] + o[6] * m[13] + o[10] * m[14]);
        o[15] = 1f;
    }

    public static void Perspective(float* m, float fov, float aspect, float near, float far)
    {
        var f = 1f / MathF.Tan(fov * 0.5f);
        for (int i = 0; i < 16; i++) m[i] = 0f;
        m[0] = f / aspect;
        m[5] = f;
        m[10] = -far / (far - near);
        m[11] = -1f;
        m[14] = -(far * near) / (far - near);
    }

    public static void Ortho(float* m, float left, float right, float bottom, float top, float near, float far)
    {
        for (int i = 0; i < 16; i++) m[i] = 0f;
        m[0] = 2f / (right - left);
        m[5] = 2f / (top - bottom);
        m[10] = 1f / (far - near);
        m[12] = -(right + left) / (right - left);
        m[13] = -(top + bottom) / (top - bottom);
        m[14] = -near / (far - near);
        m[15] = 1f;
    }

    public static void LookAt(float* m, float eyeX, float eyeY, float eyeZ, float atX, float atY, float atZ, float upX, float upY, float upZ)
    {
        // Forward (z)
        float zx = atX - eyeX, zy = atY - eyeY, zz = atZ - eyeZ;
        var len = MathF.Sqrt(zx*zx + zy*zy + zz*zz);
        zx /= len; zy /= len; zz /= len;

        // Right (x) = up × z
        float xx = upY * zz - upZ * zy;
        float xy = upZ * zx - upX * zz;
        float xz = upX * zy - upY * zx;
        len = MathF.Sqrt(xx*xx + xy*xy + xz*xz);
        xx /= len; xy /= len; xz /= len;

        // Up (y) = z × x
        float yx = zy * xz - zz * xy;
        float yy = zz * xx - zx * xz;
        float yz = zx * xy - zy * xx;

        for (int i = 0; i < 16; i++) m[i] = 0f;
        m[0] = xx; m[4] = xy; m[8]  = xz;
        m[1] = yx; m[5] = yy; m[9]  = yz;
        m[2] = zx; m[6] = zy; m[10] = zz;
        m[12] = -(xx * eyeX + xy * eyeY + xz * eyeZ);
        m[13] = -(yx * eyeX + yy * eyeY + yz * eyeZ);
        m[14] = -(zx * eyeX + zy * eyeY + zz * eyeZ);
        m[15] = 1f;
    }
}
