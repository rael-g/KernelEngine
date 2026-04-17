#include <gtest/gtest.h>
#include <kernel_engine/kernel/common/hash.h>

TEST(HashTest, NullStringReturnsZero) {
    ASSERT_EQ(ke_hash_string(nullptr), 0);
}

TEST(HashTest, EmptyStringReturnsInitialFnvHash) {
    ASSERT_EQ(ke_hash_string(""), 0xcbf29ce484222325ULL);
}

TEST(HashTest, SameStringsProduceSameHash) {
    ASSERT_EQ(ke_hash_string("kernel"), ke_hash_string("kernel"));
}

TEST(HashTest, DifferentStringsProduceDifferentHash) {
    ASSERT_NE(ke_hash_string("abc"), ke_hash_string("def"));
}

TEST(HashTest, HashIsConsistentAcrossCalls) {
    uint64_t h1 = ke_hash_string("engine");
    uint64_t h2 = ke_hash_string("engine");
    ASSERT_EQ(h1, h2);
}
