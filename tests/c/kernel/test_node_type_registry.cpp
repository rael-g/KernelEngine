#include <gtest/gtest.h>
#include <kernel_engine/framework/node_type_registry.h>
#include <kernel_engine/kernel/context/allocator.h>

class NodeTypeRegistryCTest : public ::testing::Test {
protected:
    ke_allocator* allocator = nullptr;
    ke_node_type_registry* registry = nullptr;

    void SetUp() override {
        allocator = ke_allocator_malloc_create();
        ke_result res = ke_node_type_registry_create(allocator, &registry);
        ASSERT_EQ(res, KE_OK);
        ASSERT_NE(registry, nullptr);
    }

    void TearDown() override {
        if (registry) {
            registry->destroy(registry);
        }
        if (allocator) {
            allocator->destroy(allocator);
        }
    }
};

TEST_F(NodeTypeRegistryCTest, Create_Works) {
    ASSERT_NE(registry, nullptr);
}

TEST_F(NodeTypeRegistryCTest, Register_Works) {
    ke_node_type type{};
    type.name = "TestType";
    type.create = [](void*, uint64_t, const char*) { return KE_OK; };
    
    ke_result res = registry->register_type(registry, &type);
    ASSERT_EQ(res, KE_OK);
}

TEST_F(NodeTypeRegistryCTest, Register_FailsOnNullName) {
    ke_node_type type{};
    type.name = nullptr;
    type.create = [](void*, uint64_t, const char*) { return KE_OK; };
    
    ke_result res = registry->register_type(registry, &type);
    ASSERT_EQ(res, KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(NodeTypeRegistryCTest, Lookup_Works) {
    ke_node_type type{};
    type.name = "TestType";
    type.create = [](void*, uint64_t, const char*) { return KE_OK; };
    registry->register_type(registry, &type);

    const ke_node_type* found = nullptr;
    ke_result res = registry->lookup(registry, "TestType", &found);
    
    ASSERT_EQ(res, KE_OK);
    ASSERT_NE(found, nullptr);
    ASSERT_STREQ(found->name, "TestType");
}

TEST_F(NodeTypeRegistryCTest, Lookup_ReturnsNotFound_WhenMissing) {
    const ke_node_type* found = nullptr;
    ke_result res = registry->lookup(registry, "Unknown", &found);
    ASSERT_EQ(res, KE_ERROR_NOT_FOUND);
}

TEST_F(NodeTypeRegistryCTest, Register_NullArgs_ReturnsInvalidArgument) {
    ASSERT_EQ(registry->register_type(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(NodeTypeRegistryCTest, Lookup_NullArgs_ReturnsInvalidArgument) {
    ASSERT_EQ(registry->lookup(nullptr, nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}
