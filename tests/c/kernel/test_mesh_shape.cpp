#include <gtest/gtest.h>
#include <kernel_engine/asset/mesh_shape.h>
#include "mesh_shape_internal.h"

#include <cmath>

TEST(MeshShapeTest, Bake_Quad_HasFourVerticesAndSixIndices)
{
    ke_mesh_shape_data data{};
    ASSERT_EQ(ke_mesh_shape_bake_internal(KE_MESH_PRIMITIVE_QUAD, 0, &data), KE_OK);
    EXPECT_EQ(data.vertex_count, 4u);
    EXPECT_EQ(data.index_count,  6u);
    // First vertex sits at (-0.5, -0.5, 0) with normal +Z, UV (0,0).
    EXPECT_FLOAT_EQ(data.vertices[0].x,  -0.5f);
    EXPECT_FLOAT_EQ(data.vertices[0].y,  -0.5f);
    EXPECT_FLOAT_EQ(data.vertices[0].z,   0.0f);
    EXPECT_FLOAT_EQ(data.vertices[0].nz,  1.0f);
    EXPECT_FLOAT_EQ(data.vertices[0].u,   0.0f);
    EXPECT_FLOAT_EQ(data.vertices[0].v,   0.0f);
    ke_mesh_shape_free_internal(&data);
    EXPECT_EQ(data.vertices, nullptr);
}

TEST(MeshShapeTest, Bake_Plane_NormalIsPlusY)
{
    ke_mesh_shape_data data{};
    ASSERT_EQ(ke_mesh_shape_bake_internal(KE_MESH_PRIMITIVE_PLANE, 0, &data), KE_OK);
    EXPECT_FLOAT_EQ(data.vertices[0].ny, 1.0f);
    ke_mesh_shape_free_internal(&data);
}

TEST(MeshShapeTest, Bake_Cube_Has24VerticesAnd36Indices)
{
    ke_mesh_shape_data data{};
    ASSERT_EQ(ke_mesh_shape_bake_internal(KE_MESH_PRIMITIVE_CUBE, 0, &data), KE_OK);
    EXPECT_EQ(data.vertex_count, 24u);
    EXPECT_EQ(data.index_count,  36u);
    ke_mesh_shape_free_internal(&data);
}

TEST(MeshShapeTest, Bake_Sphere_DefaultSegmentsCountsMatchFormula)
{
    ke_mesh_shape_data data{};
    ASSERT_EQ(ke_mesh_shape_bake_internal(KE_MESH_PRIMITIVE_SPHERE, 0, &data), KE_OK);
    // segments = 32 default → rings = 16
    EXPECT_EQ(data.vertex_count, (16u + 1u) * (32u + 1u));
    EXPECT_EQ(data.index_count,  16u * 32u * 6u);
    // Every sphere vertex sits at radius 0.5.
    for (uint32_t i = 0; i < data.vertex_count; ++i) {
        float r = std::sqrt(data.vertices[i].x * data.vertices[i].x +
                            data.vertices[i].y * data.vertices[i].y +
                            data.vertices[i].z * data.vertices[i].z);
        EXPECT_NEAR(r, 0.5f, 1e-5);
    }
    ke_mesh_shape_free_internal(&data);
}

TEST(MeshShapeTest, Bake_Sphere_SegmentsClampedToMin3)
{
    ke_mesh_shape_data data{};
    ASSERT_EQ(ke_mesh_shape_bake_internal(KE_MESH_PRIMITIVE_SPHERE, 1, &data), KE_OK);
    EXPECT_GT(data.vertex_count, 0u);
    ke_mesh_shape_free_internal(&data);
}

TEST(MeshShapeTest, Bake_NullOut_ReturnsInvalidArgument)
{
    EXPECT_EQ(ke_mesh_shape_bake_internal(KE_MESH_PRIMITIVE_QUAD, 0, nullptr), KE_ERROR);
}

TEST(MeshShapeTest, Free_NullArgs_IsSafe)
{
    ke_mesh_shape_free_internal(nullptr);
    ke_mesh_shape_data data{};
    ke_mesh_shape_free_internal(&data);
}
