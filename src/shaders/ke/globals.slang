struct KeFrame {
    float4x4 view;
    float4x4 proj;
    float4x4 view_proj;
    float4x4 inv_view_proj;
    float4x4 inv_proj;
    float4   camera_pos;
    float4   viewport;
    float    time;
    float    dt;
    float    near_plane;
    float    far_plane;
};
ConstantBuffer<KeFrame> ke_frame;
