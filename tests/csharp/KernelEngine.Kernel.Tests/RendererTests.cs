using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class RendererTests
{
    // Renderer methods assert thread affinity. The xUnit test thread is the de-facto ke.render here
    // since these are unit tests with mock vtables — name it (per-instance, per-thread) so AssertCurrent passes.
    public RendererTests() { KernelThread.SetCurrentName("ke.render"); }

    private static int _initializeCalled = 0;
    private static int _frameCalled = 0;
    private static int _clearColorCalled = 0;
    private static float _lastR, _lastG, _lastB, _lastA;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockOnInitialize(ke_render* self) { _initializeCalled++; return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockFrame(ke_render* self) { _frameCalled++; return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockClearColor(ke_render* self, float r, float g, float b, float a) 
    { 
        _clearColorCalled++; 
        _lastR = r; _lastG = g; _lastB = b; _lastA = a;
        return ke_result.KE_OK; 
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockDestroy(ke_render* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockOnShutdown(ke_render* self) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSubmitPacket(ke_render* self, ke_frame_packet* packet) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockCreateMesh(ke_render* self, ke_vertex* v, uint vc, ushort* i, uint ic, ke_mesh_handle* h) 
    { 
        h->idx = 42; 
        return ke_result.KE_OK; 
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockDestroyMesh(ke_render* self, ke_mesh_handle h) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetDirectionalLight(ke_render* self, ke_directional_light* l) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSubmitMesh(ke_render* self, ke_mesh_handle mesh, ke_material_handle mat, ke_mat4* trans) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetViewTransform(ke_render* self, ke_mat4* view, ke_mat4* proj) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_ndc_convention MockGetNdcConvention(ke_render* self) 
    { 
        return new ke_ndc_convention { z_zero_to_one = 1, y_flip = 0, left_handed = 0 }; 
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockCreateMaterial(ke_render* self, ke_material* mat, ke_material_handle* h)
    {
        h->idx = 123;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetShadowMap(ke_render* self, ke_shadow_map_handle h) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetSsao(ke_render* self, byte e, float r, float b, float s) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetTonemapping(ke_render* self, byte e, float exp, float g) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetBloom(ke_render* self, byte e, float t, float i) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockCreateTexture(ke_render* self, uint w, uint h, byte* d, ke_texture_handle* out_h)
    {
        out_h->idx = 77;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockCreateCubemap(ke_render* self, uint s, byte* d, ke_texture_handle* out_h)
    {
        out_h->idx = 88;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockCreateShadowMap(ke_render* self, uint w, uint h, ke_shadow_map_handle* out_h)
    {
        out_h->idx = 99;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetClusterConfig(ke_render* self, ke_cluster_config* c) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static unsafe sbyte* MockGetLastFatalError(ke_render* self) { return null; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetCameraPos(ke_render* self, float x, float y, float z) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetPointLights(ke_render* self, ke_point_light* l, uint c) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetSpotLights(ke_render* self, ke_spot_light* l, uint c) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSubmitSkybox(ke_render* self, ke_texture_handle h) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockDestroyShadowMap(ke_render* self, ke_shadow_map_handle h) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockBeginShadowPass(ke_render* self, ke_shadow_map_handle h, ke_mat4* v, ke_mat4* p) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSubmitMeshShadow(ke_render* self, ke_mesh_handle m, ke_mat4* t) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockEndShadowPass(ke_render* self) { return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetOrthographic(ke_render* self, byte e) { return ke_result.KE_OK; }

    // Helper to create a mock vtable
    private ke_render* CreateMock()
    {
        var mock = (ke_render*)NativeMemory.AllocZeroed((nuint)sizeof(ke_render));
        mock->on_initialize = &MockOnInitialize;
        mock->frame = &MockFrame;
        mock->clear_color = &MockClearColor;
        mock->destroy = &MockDestroy;
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
        return mock;
    }

    [Fact]
    public void SetCameraPos_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetCameraPos(1, 2, 3);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetPointLights_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetPointLights(new ke_point_light[1]);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetSpotLights_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetSpotLights(new ke_spot_light[1]);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SubmitSkybox_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SubmitSkybox(new TextureHandle(1));
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ShadowPass_CallsMocks()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            Assert.True(renderer.BeginShadowPass(new ShadowMapHandle(1), Matrix4x4.Identity, Matrix4x4.Identity).IsOk);
            Assert.True(renderer.SubmitMeshShadow(new MeshHandle(1), Matrix4x4.Identity).IsOk);
            Assert.True(renderer.EndShadowPass().IsOk);
            Assert.True(renderer.DestroyShadowMap(new ShadowMapHandle(1)).IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetOrthographic_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            Assert.True(renderer.SetOrthographic(true).IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ClearColor_Vector4_CallsClearColor()
    {
        _clearColorCalled = 0;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.ClearColor(new Vector4(1, 0, 0, 1));
            Assert.Equal(1, _clearColorCalled);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void CreateTexture_ReturnsHandle()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.CreateTexture(2, 2, new byte[16]);
            Assert.True(res.IsOk);
            Assert.Equal(77u, res.Value.Value);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void CreateCubemap_ReturnsHandle()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.CreateCubemap(2, new byte[16 * 6]);
            Assert.True(res.IsOk);
            Assert.Equal(88u, res.Value.Value);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void CreateShadowMap_ReturnsHandle()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.CreateShadowMap(1024, 1024);
            Assert.True(res.IsOk);
            Assert.Equal(99u, res.Value.Value);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetClusterConfig_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetClusterConfig(16, 9, 24, 100, 1024);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void GetLastFatalError_ReturnsNull_WhenNoErrorMessage()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            Assert.Null(renderer.GetLastFatalError());
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetShadowMap_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetShadowMap(new ShadowMapHandle(1));
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetSsao_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetSsao(true, 0.5f, 0.02f, 1.0f);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetTonemapping_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetTonemapping(true, 1.0f, 2.2f);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetBloom_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetBloom(true, 1.0f, 0.5f);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetViewTransform_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetViewTransform(Matrix4x4.Identity, Matrix4x4.Identity);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void GetNdcConvention_ReturnsCorrectValues()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var conv = renderer.GetNdcConvention();
            Assert.True(conv.ZeroToOneDepth);
            Assert.False(conv.YFlip);
            Assert.False(conv.LeftHanded);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void CreateMaterial_ReturnsHandle()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.CreateMaterial(1, 1, 1, 1);
            Assert.True(res.IsOk);
            Assert.Equal(123u, res.Value.Value);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void Initialize_IncrementsCounter()
    {
        _initializeCalled = 0;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.Initialize();
            Assert.Equal(1, _initializeCalled);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SubmitPacket_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            // We need a FramePacket instance. Since FramePacket internal constructor
            // needs a ke_frame_packet*, we can pass null for this test as the mock
            // doesn't dereference it.
            var packet = new FramePacket(null, null, true);
            var res = renderer.SubmitPacket(packet);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void CreateMesh_ReturnsHandle()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var vertices = new Vertex[3];
            var indices = new ushort[3];
            var res = renderer.CreateMesh(vertices, indices);
            Assert.True(res.IsOk);
            Assert.Equal(42u, res.Value.Value);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void DestroyMesh_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.DestroyMesh(new MeshHandle(42));
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SetDirectionalLight_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SetDirectionalLight(0, -1, 0, 1, 1, 1, 1);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SubmitMesh_CallsMock()
    {
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            var res = renderer.SubmitMesh(new MeshHandle(1), new MaterialHandle(2), Matrix4x4.Identity);
            Assert.True(res.IsOk);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void Frame_IncrementsCounter()
    {
        _frameCalled = 0;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.Frame();
            Assert.Equal(1, _frameCalled);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ClearColor_IncrementsCounter()
    {
        _clearColorCalled = 0;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.ClearColor(1, 0, 0, 1);
            Assert.Equal(1, _clearColorCalled);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ClearColor_PassesCorrectRed()
    {
        _lastR = -1;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.ClearColor(0.5f, 0, 0, 1);
            Assert.Equal(0.5f, _lastR);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ClearColor_Vector4_PassesCorrectGreen()
    {
        _lastG = -1;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.ClearColor(new Vector4(0, 0.7f, 0, 1));
            Assert.Equal(0.7f, _lastG);
        }
        NativeMemory.Free(mock);
    }
}
