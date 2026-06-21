using System.Numerics;
using KernelEngine.Render;

namespace KernelEngine.Framework.Legacy.Internal;

/// <summary>
/// The matrix-convention adapter (ADR-10). The engine frontend commits to one convention for the
/// matrices it builds itself — view and projection — and adapts the projection to the active
/// backend's NDC via <see cref="NdcConvention"/>.
/// </summary>
/// <remarks>
/// <para>
/// <b>Frontend convention:</b> view-space is right-handed (camera looks down -Z, forward =
/// <c>target - eye</c>). Projection emits Vulkan-canonical output by default (Y-flip true,
/// Z ∈ [0, 1]); GL and D3D NDCs are reached by toggling <see cref="NdcConvention.YFlip"/> and
/// <see cref="NdcConvention.ZeroToOneDepth"/>. The backend reports its NDC at startup via
/// <see cref="SetConvention"/> — the frontend never assumes one.
/// </para>
/// <para>
/// <b>Why this class exists (instead of <see cref="Matrix4x4.CreateOrthographic"/> /
/// <see cref="Matrix4x4.CreatePerspectiveFieldOfView"/>):</b> System.Numerics' builders are fixed
/// at RH + Y-up + Z ∈ [0, 1] — D3D11+ only. There are no <c>...LH</c> overloads, no depth-range
/// parameter, no Y-flip. They cannot target Vulkan (needs Y-flip) or OpenGL (needs Z ∈ [-1, 1]).
/// This class is the irreducible bridge: System.Numerics still does the vector/inverse math
/// everywhere else; only view+projection require convention-aware builders.
/// </para>
/// <para>
/// Results are written into <see cref="Matrix4x4"/> slots so the flat bytes match the column-major
/// <c>ke_mat4</c> layout; <c>FramePacket.ToKeMat4</c> blits them verbatim.
/// </para>
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
        // Right-handed view: forward (toward target) is built then negated into the matrix's
        // z-row so that view-space z is NEGATIVE for content in front of the camera — matching
        // the frustum Ortho/Perspective produce (which map view-z in [-near, -far] to NDC).
        // The earlier '+f' layout was silently left-handed and only worked while Ortho was
        // also LH (positive M33). The 16957b2 Ortho fix exposed the mismatch (OBS.7): shadow
        // camera placed origin at view-z=+25 (outside RH frustum) → ComputeShadow saw empty.
        var f = Vector3.Normalize(target - eye);
        var r = Vector3.Normalize(Vector3.Cross(up, f));
        var u = Vector3.Cross(f, r);
        return new Matrix4x4(
            r.X, u.X, -f.X, 0f,
            r.Y, u.Y, -f.Y, 0f,
            r.Z, u.Z, -f.Z, 0f,
            -Vector3.Dot(r, eye), -Vector3.Dot(u, eye), Vector3.Dot(f, eye), 1f);
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
