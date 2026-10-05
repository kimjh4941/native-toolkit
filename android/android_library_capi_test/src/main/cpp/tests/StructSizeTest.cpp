// The struct_size rules (C ABI design part 1, 1.1; the Windows C ABI design 7.8).
#include <gtest/gtest.h>

#include <cstdint>
#include <cstring>
#include <vector>

#include "Common/Errors.h"
#include "Common/StructSize.h"

namespace {

struct Options {
    uint32_t struct_size;
    uint32_t reserved0;
    int32_t a;
    int32_t b;
};

// A caller's struct from a newer header: Options followed by more fields.
std::vector<unsigned char> Newer(uint32_t size, unsigned char tail) {
    std::vector<unsigned char> bytes(size, tail);
    Options base{size, 0, 7, 8};
    std::memcpy(bytes.data(), &base, sizeof(base));
    return bytes;
}

using nativetoolkit::structs::Read;

}  // namespace

TEST(StructSize, NullIsTheDefaultsWhenOptional) {
    Options out{99, 99, 99, 99};
    EXPECT_EQ(nativetoolkit::kErrorNone, Read<Options>(nullptr, &out, true));
    EXPECT_EQ(0, out.a);
    EXPECT_EQ(0u, out.struct_size);
    EXPECT_EQ(nativetoolkit::kErrorInvalidParameter, Read<Options>(nullptr, &out, false));
}

TEST(StructSize, TheSizeOfThisVersionIsRead) {
    Options in{sizeof(Options), 0, 3, 4};
    Options out{};
    EXPECT_EQ(nativetoolkit::kErrorNone, Read(&in, &out, false));
    EXPECT_EQ(3, out.a);
    EXPECT_EQ(4, out.b);
}

TEST(StructSize, ASmallerSizeIsRejected) {
    Options in{sizeof(Options) - 8, 0, 3, 4};
    Options out{};
    EXPECT_EQ(nativetoolkit::kErrorInvalidParameter, Read(&in, &out, false));
    in.struct_size = 0;
    EXPECT_EQ(nativetoolkit::kErrorInvalidParameter, Read(&in, &out, false));
}

TEST(StructSize, ASizeAboveTheLimitIsRejected) {
    std::vector<unsigned char> bytes = Newer(4096 + 8, 0);
    Options out{};
    EXPECT_EQ(nativetoolkit::kErrorInvalidParameter, Read(reinterpret_cast<const Options*>(bytes.data()), &out, false));
    bytes = Newer(4096, 0);
    EXPECT_EQ(nativetoolkit::kErrorNone, Read(reinterpret_cast<const Options*>(bytes.data()), &out, false));
}

TEST(StructSize, AReservedValueIsRejected) {
    Options in{sizeof(Options), 1, 3, 4};
    Options out{};
    EXPECT_EQ(nativetoolkit::kErrorInvalidParameter, Read(&in, &out, false));
}

TEST(StructSize, ANewerStructIsAcceptedWhenItsNewPartIsZero) {
    std::vector<unsigned char> bytes = Newer(sizeof(Options) + 16, 0);
    Options out{};
    EXPECT_EQ(nativetoolkit::kErrorNone, Read(reinterpret_cast<const Options*>(bytes.data()), &out, false));
    EXPECT_EQ(7, out.a);
    EXPECT_EQ(8, out.b);
}

TEST(StructSize, ANewerStructWithAValueInItsNewPartIsNotSupported) {
    std::vector<unsigned char> bytes = Newer(sizeof(Options) + 16, 0);
    bytes[sizeof(Options) + 15] = 1;
    Options out{};
    EXPECT_EQ(nativetoolkit::kErrorNotSupported, Read(reinterpret_cast<const Options*>(bytes.data()), &out, false));
}
