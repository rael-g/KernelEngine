using System.Numerics;
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class RendererTests
{
    public RendererTests() { KernelThread.SetCurrentName("ke.render"); }

    private static int _initializeCalled = 0;
    private static int _frameCalled = 0;
    private static int _clearColorCalled = 0;
    private static float _lastR, _lastG, _lastB, _lastA;
    private static sbyte* _fatalErrorPtr = null;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockOnInitialize(ke_render* self, ke_error** out_error) { _initializeCalled++; return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockFrame(ke_render* self, ke_error** out_error) { _frameCalled++; return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockClearColor(ke_render* self, float r, float g, float b, float a, ke_error** out_error)
    {
        _clearColorCalled++;
        _lastR = r; _lastG = g; _lastB = b; _lastA = a;
        return true;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void MockDestroy(ke_render* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockOnShutdown(ke_render* self, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSubmitPacket(ke_render* self, ke_frame_packet* packet, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_mesh_handle MockCreateMesh(ke_render* self, ke_vertex* v, uint vc, ushort* i, uint ic, ke_error** out_error)
    {
        return new ke_mesh_handle { idx = 42 };
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockDestroyMesh(ke_render* self, ke_mesh_handle h, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetDirectionalLight(ke_render* self, ke_directional_light* l, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSubmitMesh(ke_render* self, ke_mesh_handle mesh, ke_material_handle mat, ke_mat4* trans, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetViewTransform(ke_render* self, ke_mat4* view, ke_mat4* proj, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_ndc_convention MockGetNdcConvention(ke_render* self)
    {
        return new ke_ndc_convention { z_zero_to_one = 1, y_flip = 0, left_handed = 0 };
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_material_handle MockCreateMaterial(ke_render* self, ke_material* mat, ke_error** out_error)
    {
        return new ke_material_handle { idx = 123 };
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetShadowMap(ke_render* self, ke_shadow_map_handle h, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetSsao(ke_render* self, byte e, float r, float b, float s, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetTonemapping(ke_render* self, byte e, float exp, float g, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetBloom(ke_render* self, byte e, float t, float i, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_texture_handle MockCreateTexture(ke_render* self, uint w, uint h, byte* d, ke_error** out_error)
    {
        return new ke_texture_handle { idx = 77 };
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_texture_handle MockCreateCubemap(ke_render* self, uint s, byte* d, ke_error** out_error)
    {
        return new ke_texture_handle { idx = 88 };
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_shadow_map_handle MockCreateShadowMap(ke_render* self, uint w, uint h, ke_error** out_error)
    {
        return new ke_shadow_map_handle { idx = 99 };
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetClusterConfig(ke_render* self, ke_cluster_config* c, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static sbyte* MockGetLastFatalError(ke_render* self) { return _fatalErrorPtr; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetCameraPos(ke_render* self, float x, float y, float z, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetPointLights(ke_render* self, ke_point_light* l, uint c, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetSpotLights(ke_render* self, ke_spot_light* l, uint c, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSubmitSkybox(ke_render* self, ke_texture_handle h, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockDestroyShadowMap(ke_render* self, ke_shadow_map_handle h, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockBeginShadowPass(ke_render* self, ke_shadow_map_handle h, ke_mat4* v, ke_mat4* p, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSubmitMeshShadow(ke_render* self, ke_mesh_handle m, ke_mat4* t, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockEndShadowPass(ke_render* self, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetOrthographic(ke_render* self, byte e, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockSetAmbientLight(ke_render* self, float r, float g, float b, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockDestroyTexture(ke_render* self, ke_texture_handle h, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockDestroyMaterial(ke_render* self, ke_material_handle h, ke_error** out_error) { return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_render_graph* MockGetRenderGraph(ke_render* self) { return null; }

    private ke_render_handle CreateMock()
    {
        var mock = (ke_render*)NativeMemory.AllocZeroed((nuint)sizeof(ke_render));
        mock->on_initialize = &MockOnInitialize;
        mock->frame = &MockFrame;
        mock->clear_color = &MockClearColor;
        mock->on_shutdown = &MockOnShutdown;
        mock->submit_packet = &MockSubmitPacket;
        mock->create_mesh = &MockCreateMesh;
        mock->destroy_mesh = &MockDestroyMesh;
        mock->set_directional_light = &MockSetDirectionalLight;
        mock->submit_mesh = &MockSubmitMesh;
        mock->set_view_transform = &MockSetViewTransform;
        mock->get_ndc_convention = &MockGetNdcConvention;
        mock->create_material = &MockCreateMaterial;
        mock->set_shadow_map = &MockSetShadowMap;
        mock->set_ssao = &MockSetSsao;
        mock->set_tonemapping = &MockSetTonemapping;
        mock->set_bloom = &MockSetBloom;
        mock->create_texture_rgba = &MockCreateTexture;
        mock->create_cubemap_rgba = &MockCreateCubemap;
        mock->create_shadow_map = &MockCreateShadowMap;
        mock->set_cluster_config = &MockSetClusterConfig;
        mock->get_last_fatal_error = &MockGetLastFatalError;
        mock->set_camera_pos = &MockSetCameraPos;
        mock->set_point_lights = &MockSetPointLights;
        mock->set_spot_lights = &MockSetSpotLights;
        mock->submit_skybox = &MockSubmitSkybox;
        mock->destroy_shadow_map = &MockDestroyShadowMap;
        mock->begin_shadow_pass = &MockBeginShadowPass;
        mock->submit_mesh_shadow = &MockSubmitMeshShadow;
        mock->end_shadow_pass = &MockEndShadowPass;
        mock->set_orthographic = &MockSetOrthographic;
        mock->set_ambient_light = &MockSetAmbientLight;
        mock->destroy_texture = &MockDestroyTexture;
        mock->destroy_material = &MockDestroyMaterial;
        mock->get_render_graph = &MockGetRenderGraph;
        return new ke_render_handle { @ref = mock, destroy = &MockDestroy };
    }

    [Fact]
    public void Initialize_CallsMock()
    {
        _initializeCalled = 0;
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.Initialize();
            Assert.Equal(1, _initializeCalled);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void Frame_CallsMock()
    {
        _frameCalled = 0;
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.Frame();
            Assert.Equal(1, _frameCalled);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void ClearColor_CallsMock()
    {
        _clearColorCalled = 0;
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.ClearColor(1, 0, 0, 1);
            Assert.Equal(1, _clearColorCalled);
            Assert.Equal(1f, _lastR);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void ClearColor_Vector4_CallsMock()
    {
        _clearColorCalled = 0;
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.ClearColor(new Vector4(0, 1, 0, 1));
            Assert.Equal(1, _clearColorCalled);
            Assert.Equal(1f, _lastG);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetOrthographic_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetOrthographic(true);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetViewTransform_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetViewTransform(Matrix4x4.Identity, Matrix4x4.Identity);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void GetNdcConvention_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            var c = renderer.GetNdcConvention();
            Assert.True(c.ZeroToOneDepth);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void CreateMesh_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            var handle = renderer.CreateMesh(new Vertex[3], new ushort[3]);
            Assert.Equal(42u, handle.Value);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void DestroyMesh_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.DestroyMesh(new MeshHandle(1));
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void CreateTexture_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            var handle = renderer.CreateTexture(2, 2, new byte[16]);
            Assert.Equal(77u, handle.Value);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void DestroyTexture_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.DestroyTexture(new TextureHandle(1));
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void CreateMaterial_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            var handle = renderer.CreateMaterial(1, 1, 1, 1);
            Assert.Equal(123u, handle.Value);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void CreateMaterial_Vector4_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.CreateMaterial(Vector4.One);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void DestroyMaterial_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.DestroyMaterial(new MaterialHandle(1));
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetDirectionalLight_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetDirectionalLight(0, -1, 0, 1, 1, 1, 1);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetAmbientLight_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetAmbientLight(1, 1, 1);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetCameraPos_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetCameraPos(1, 2, 3);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetPointLights_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetPointLights(new ke_point_light[1]);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetSpotLights_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetSpotLights(new ke_spot_light[1]);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetSsao_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetSsao(true);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetClusterConfig_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetClusterConfig(1, 1, 1, 1, 1);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void CreateCubemap_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            var handle = renderer.CreateCubemap(2, new byte[16 * 6]);
            Assert.Equal(88u, handle.Value);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SubmitSkybox_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SubmitSkybox(new TextureHandle(1));
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SubmitMesh_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SubmitMesh(new MeshHandle(1), new MaterialHandle(2), Matrix4x4.Identity);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void CreateShadowMap_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            var handle = renderer.CreateShadowMap(1024, 1024);
            Assert.Equal(99u, handle.Value);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void BeginShadowPass_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.BeginShadowPass(new ShadowMapHandle(1), Matrix4x4.Identity, Matrix4x4.Identity);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SubmitMeshShadow_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SubmitMeshShadow(new MeshHandle(1), Matrix4x4.Identity);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void EndShadowPass_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.EndShadowPass();
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetShadowMap_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetShadowMap(new ShadowMapHandle(1));
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetTonemapping_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetTonemapping(true);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void SetBloom_CallsMock()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            renderer.SetBloom(true);
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void GetLastFatalError_ReturnsNull_WhenNoErrorMessage()
    {
        _fatalErrorPtr = null;
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            Assert.Null(renderer.GetLastFatalError());
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void GetLastFatalError_ReturnsMessage_WhenNativeHasError()
    {
        var h = CreateMock();
        var msg = "Fatal GPU Error";
        var ptr = Marshal.StringToCoTaskMemAnsi(msg);
        _fatalErrorPtr = (sbyte*)ptr;
        try
        {
            using (var renderer = new Renderer(h))
            {
                Assert.Equal(msg, renderer.GetLastFatalError());
            }
        }
        finally
        {
            Marshal.FreeCoTaskMem(ptr);
            _fatalErrorPtr = null;
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void GetRenderGraph_ReturnsNull_WhenVtableIsNull()
    {
        var h = CreateMock();
        h.@ref->get_render_graph = null;
        using (var renderer = new Renderer(h))
        {
            Assert.Null(renderer.GetRenderGraph());
        }
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public void FramePacket_AddPointLight_RespectsCapacity()
    {
        var nativePacket = new ke_frame_packet {
            point_light_capacity = 1,
            point_lights = (ke_point_light*)NativeMemory.Alloc(1, (nuint)sizeof(ke_point_light))
        };
        var packet = new FramePacket(&nativePacket, null, true);

        var light = new PointLightData { Radius = 10f, Intensity = 1f };
        packet.AddPointLight(light);
        Assert.Equal(1u, nativePacket.point_light_count);

        packet.AddPointLight(light); // Should be ignored
        Assert.Equal(1u, nativePacket.point_light_count);

        NativeMemory.Free(nativePacket.point_lights);
    }

    [Fact]
    public void FramePacket_AddSpotLight_RespectsCapacity()
    {
        var nativePacket = new ke_frame_packet {
            spot_light_capacity = 1,
            spot_lights = (ke_spot_light*)NativeMemory.Alloc(1, (nuint)sizeof(ke_spot_light))
        };
        var packet = new FramePacket(&nativePacket, null, true);

        var light = new SpotLightData { Range = 10f, Intensity = 1f };
        packet.AddSpotLight(light);
        Assert.Equal(1u, nativePacket.spot_light_count);

        packet.AddSpotLight(light); // Should be ignored
        Assert.Equal(1u, nativePacket.spot_light_count);

        NativeMemory.Free(nativePacket.spot_lights);
    }

    [Fact]
    public void SubmitPacket_Succeeds()
    {
        var h = CreateMock();
        using (var renderer = new Renderer(h))
        {
            var packet = new FramePacket(null, null, true);
            renderer.SubmitPacket(packet);
        }
        NativeMemory.Free(h.@ref);
    }
}
