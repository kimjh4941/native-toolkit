// Common.h: the version, the system code and the output handles (C ABI design part 1, 1.1 and
// AC-10). Handles made by the features are tested with them; here, what holds for any handle.
#include <gtest/gtest.h>

#include <NativeToolkitC/Common.h>

TEST(Common, VersionIsTheHeaderVersion) {
    EXPECT_EQ(static_cast<uint32_t>(NTK_VERSION), ntk_version());
    EXPECT_EQ(static_cast<uint32_t>((NTK_VERSION_MAJOR << 16) | (NTK_VERSION_MINOR << 8) | NTK_VERSION_PATCH),
              ntk_version());
}

TEST(Common, LastSystemCodeIsAlwaysZero) {
    EXPECT_EQ(0u, ntk_last_system_code());
}

TEST(Common, ReadingANullHandleGivesNothing) {
    EXPECT_EQ(nullptr, ntk_string_data(nullptr));
    EXPECT_EQ(0u, ntk_string_size(nullptr));
    EXPECT_EQ(nullptr, ntk_bytes_data(nullptr));
    EXPECT_EQ(0u, ntk_bytes_size(nullptr));
    EXPECT_EQ(0u, ntk_string_list_count(nullptr));
    size_t size = 99;
    EXPECT_EQ(nullptr, ntk_string_list_at(nullptr, 0, &size));
    EXPECT_EQ(0u, size);
    EXPECT_EQ(nullptr, ntk_string_list_at(nullptr, 0, nullptr));
}

TEST(Common, FreeingNullDoesNothing) {
    ntk_string_free(nullptr);
    ntk_bytes_free(nullptr);
    ntk_string_list_free(nullptr);
    SUCCEED();
}
