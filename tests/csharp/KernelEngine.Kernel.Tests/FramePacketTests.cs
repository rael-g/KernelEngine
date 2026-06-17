using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class FramePacketTests
{
    private ke_frame_packet* CreateNativePacket(uint drawCap = 10, uint pointLightCap = 8, uint spotLightCap = 8, uint shadowDrawCap = 8)
    {
        var packet = (ke_frame_packet*)NativeMemory.AllocZeroed((nuint)sizeof(ke_frame_packet));
        packet->draw_capacity = drawCap;
        packet->draw_commands = (ke_draw_command*)NativeMemory.AllocZeroed((nuint)(sizeof(ke_draw_command) * drawCap));
        packet->point_light_capacity = pointLightCap;
        packet->point_lights = (ke_point_light*)NativeMemory.AllocZeroed((nuint)(sizeof(ke_point_light) * pointLightCap));
        packet->spot_light_capacity = spotLightCap;
        packet->spot_lights = (ke_spot_light*)NativeMemory.AllocZeroed((nuint)(sizeof(ke_spot_light) * spotLightCap));
        packet->shadow_draw_capacity = shadowDrawCap;
        packet->shadow_draw_commands = (ke_draw_command*)NativeMemory.AllocZeroed((nuint)(sizeof(ke_draw_command) * shadowDrawCap));
        return packet;
    }

    private void FreeNativePacket(ke_frame_packet* packet)
    {
        NativeMemory.Free(packet->draw_commands);
        NativeMemory.Free(packet->point_lights);
        NativeMemory.Free(packet->spot_lights);
        NativeMemory.Free(packet->shadow_draw_commands);
        NativeMemory.Free(packet);
    }

    [Fact]
    public void SetCamera_PopulatesNativeStruct()
    {
        var native = CreateNativePacket();
        var packet = new FramePacket(native, null, true);
        
        var view = Matrix4x4.CreateTranslation(1, 2, 3);
        var proj = Matrix4x4.CreatePerspectiveFieldOfView(1, 1, 0.1f, 100f);
        var pos = new Vector3(10, 20, 30);
        
        packet.SetCamera(view, proj, pos);
        
        Assert.Equal(1, native->camera.view.m[12]); // M41 translation X
        Assert.Equal(10, native->camera.pos_x);
        
        FreeNativePacket(native);
    }

    [Fact]
    public void AddDrawCommand_IncrementsCountAndPopulates()
    {
        var native = CreateNativePacket(drawCap: 5);
        var packet = new FramePacket(native, null, true);
        
        packet.AddDrawCommand(new MeshHandle(1), new MaterialHandle(2), Matrix4x4.Identity);
        
        Assert.Equal(1u, native->draw_count);
        Assert.Equal(1u, native->draw_commands[0].mesh_handle.idx);
        Assert.Equal(2u, native->draw_commands[0].material_handle.idx);
        
        FreeNativePacket(native);
    }

    [Fact]
    public void AddDrawCommand_AtCapacity_IsIgnored()
    {
        var native = CreateNativePacket(drawCap: 1);
        var packet = new FramePacket(native, null, true);
        
        packet.AddDrawCommand(new MeshHandle(1), new MaterialHandle(1), Matrix4x4.Identity);
        packet.AddDrawCommand(new MeshHandle(2), new MaterialHandle(2), Matrix4x4.Identity);
        
        Assert.Equal(1u, native->draw_count);
        Assert.Equal(1u, native->draw_commands[0].mesh_handle.idx);
        
        FreeNativePacket(native);
    }

    [Fact]
    public void SetClearColor_PopulatesNative()
    {
        var native = CreateNativePacket();
        var packet = new FramePacket(native, null, true);
        
        packet.SetClearColor(1.0f, 0.5f, 0.2f, 1.0f);
        
        Assert.Equal(1.0f, native->clear_color[0]);
        Assert.Equal(0.5f, native->clear_color[1]);
        
        FreeNativePacket(native);
    }

    [Fact]
    public void AddSpotLight_PopulatesNative()
    {
        var native = CreateNativePacket(spotLightCap: 8);
        var packet = new FramePacket(native, null, true);
        
        packet.AddSpotLight(new SpotLightData { Range = 10, Intensity = 2 });
        
        Assert.Equal(1u, native->spot_light_count);
        Assert.Equal(10, native->spot_lights[0].range);
        
        FreeNativePacket(native);
    }

    [Fact]
    public void AddShadowDrawCommand_PopulatesNative()
    {
        var native = CreateNativePacket(shadowDrawCap: 10);
        var packet = new FramePacket(native, null, true);
        packet.AddShadowDrawCommand(new MeshHandle(5), Matrix4x4.Identity);
        
        Assert.Equal(1u, native->shadow_draw_count);
        Assert.Equal(5u, native->shadow_draw_commands[0].mesh_handle.idx);
        
        FreeNativePacket(native);
    }

    [Fact]
    public void SetPostProcessing_PopulatesNative()
    {
        var native = CreateNativePacket();
        var packet = new FramePacket(native, null, true);
        
        packet.SetSsao(true, 0.5f, 0.1f, 1.0f);
        packet.SetTonemapping(true, 1.2f, 2.0f);
        packet.SetBloom(true, 0.8f, 0.3f);
        
        Assert.Equal(1, native->ssao_enabled);
        Assert.Equal(0.5f, native->ssao_radius);
        Assert.Equal(1, native->tonemapping_enabled);
        Assert.Equal(1.2f, native->exposure);
        Assert.Equal(1, native->bloom_enabled);
        Assert.Equal(0.8f, native->bloom_threshold);
        
        FreeNativePacket(native);
    }

    [Fact]
    public void ReadAPI_ReturnsCorrectValues()
    {
        var native = CreateNativePacket(drawCap: 1, pointLightCap: 1, spotLightCap: 1, shadowDrawCap: 1);
        native->frame_number = 123;
        native->has_skybox = 1;
        native->skybox_handle.idx = 55;
        native->draw_count = 1;
        native->draw_commands[0].mesh_handle.idx = 10;
        native->point_light_count = 1;
        native->spot_light_count = 1;
        native->shadow_draw_count = 1;
        native->has_dir_light = 1;
        native->dir_light.intensity = 5.0f;

        var packet = new FramePacket(native, null, false);

        Assert.Equal(123u, packet.FrameNumber);
        Assert.True(packet.HasSkybox);
        Assert.Equal(55u, packet.SkyboxHandle.Value);
        Assert.Equal(1, packet.DrawCommands.Length);
        Assert.Equal(10u, packet.DrawCommands[0].mesh_handle.idx);
        Assert.Equal(1, packet.PointLights.Length);
        Assert.Equal(1, packet.SpotLights.Length);
        Assert.Equal(1, packet.ShadowDrawCommands.Length);
        Assert.NotNull(packet.DirectionalLightData);
        Assert.Equal(5.0f, packet.DirectionalLightData.Value.intensity);
        Assert.Equal((nint)native, (nint)packet.NativePointer);

        FreeNativePacket(native);
    }

    [Fact]
    public void DirectionalLightData_ReturnsNull_WhenAbsent()
    {
        var native = CreateNativePacket();
        native->has_dir_light = 0;
        var packet = new FramePacket(native, null, false);
        Assert.Null(packet.DirectionalLightData);
        FreeNativePacket(native);
    }

    [Fact]
    public void Lifecycle_EndMethods_HandleNullPacketGracefully()
    {
        var packet = new FramePacket(null, null, true);
        packet.EndWrite();
        packet.EndRead();
        // Should not crash
    }

    [Fact]
    public void SetAmbientLight_PopulatesNative()
    {
        var native = CreateNativePacket();
        var packet = new FramePacket(native, null, true);
        
        packet.SetAmbientLight(0.1f, 0.2f, 0.3f);
        
        Assert.Equal(0.1f, native->ambient_light[0]);
        Assert.Equal(0.2f, native->ambient_light[1]);
        Assert.Equal(0.3f, native->ambient_light[2]);
        
        FreeNativePacket(native);
    }
}
