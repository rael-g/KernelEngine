#include <gtest/gtest.h>
#include <kernel_engine/common/error.h>

#include <cstring>

// A distinct child type to verify the type pointer + hierarchy survive a copy.
static const ke_error_type KE_ERROR_TEST_CHILD = { "ke.error.test.child", &KE_ERROR_INVALID_ARGUMENT };

TEST(ErrorCopy, NullSourceReturnsNull)
{
    EXPECT_EQ(ke_error_copy(nullptr), nullptr);
    ke_error_free(nullptr); // no-op, must not crash
}

TEST(ErrorCopy, SnapshotSurvivesThreadLocalOverwrite)
{
    ke_error* src = nullptr;
    KE_ERROR_SET(&src, &KE_ERROR_TEST_CHILD, "original message");

    ke_error* copy = ke_error_copy(src);
    ASSERT_NE(copy, nullptr);

    // Overwrite the thread-local ring twice — src's message buffer is now clobbered,
    // but the copy owns its own storage and must be untouched.
    ke_error* tmp = nullptr;
    KE_ERROR_SET(&tmp, &KE_ERROR_GENERAL, "clobber one");
    KE_ERROR_SET(&tmp, &KE_ERROR_GENERAL, "clobber two");

    EXPECT_EQ(copy->type, &KE_ERROR_TEST_CHILD);
    EXPECT_STREQ(copy->message, "original message");
    // Type hierarchy still matches via the copied type pointer.
    EXPECT_TRUE(ke_error_is(copy, &KE_ERROR_TEST_CHILD));
    EXPECT_TRUE(ke_error_is(copy, &KE_ERROR_INVALID_ARGUMENT));

    ke_error_free(copy);
}

TEST(ErrorCopy, CopiesCauseChain)
{
    ke_error* inner = nullptr;
    KE_ERROR_SET(&inner, &KE_ERROR_NOT_FOUND, "inner cause");

    ke_error* outer = nullptr;
    KE_ERROR_WRAP(&outer, &KE_ERROR_GENERAL, "outer wrap", inner);

    ke_error* copy = ke_error_copy(outer);
    ASSERT_NE(copy, nullptr);

    // Clobber the ring so any dangling reference to thread-local storage would show.
    ke_error* tmp = nullptr;
    KE_ERROR_SET(&tmp, &KE_ERROR_GENERAL, "x");
    KE_ERROR_SET(&tmp, &KE_ERROR_GENERAL, "y");

    EXPECT_STREQ(copy->message, "outer wrap");
    ASSERT_NE(copy->cause, nullptr);
    EXPECT_EQ(copy->cause->type, &KE_ERROR_NOT_FOUND);
    EXPECT_STREQ(copy->cause->message, "inner cause");
    EXPECT_EQ(copy->cause->cause, nullptr);

    ke_error_free(copy);
}

TEST(ErrorCopy, PreservesFileAndLine)
{
    ke_error* src = nullptr;
    KE_ERROR_SET(&src, &KE_ERROR_GENERAL, "loc");
    uint32_t src_line = src->line;
    const char* src_file = src->file;

    ke_error* copy = ke_error_copy(src);
    ASSERT_NE(copy, nullptr);
    EXPECT_EQ(copy->line, src_line);
    EXPECT_EQ(copy->file, src_file); // __FILE__ literal, same pointer

    ke_error_free(copy);
}
