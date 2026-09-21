#pragma once
// How an input struct is read (stage 5 design 7.8). One function, so every
// struct follows the same rules.

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <type_traits>

namespace NativeToolkitC::Detail {

/// A struct_size above this is taken for an uninitialised value rather than
/// read: the checks below would otherwise walk far past the caller's struct.
constexpr uint32_t kMaxStructSize = 4096;

enum class StructCheck {
    Ok,
    InvalidParameter,  ///< NULL, too small, too large.
    NotSupported,      ///< Longer than this version knows, with something set in the unknown part.
};

/**
 * @brief Copies a caller's input struct into out.
 * @param in      The caller's struct; its first member is uint32_t struct_size.
 * @param out     Receives the fields this version knows, zeroed where the
 *                caller's struct is shorter.
 * @param minSize The size the struct had in the first version that shipped it.
 *                It is sizeof(T) for every struct of 2.0.0; a later version
 *                passes the older size, which is how a test stands in for one.
 * @details The rules: a size below minSize or above kMaxStructSize is
 *          InvalidParameter. A field is read only when the caller's struct
 *          covers it, and a field it does not cover is 0 (the default). A
 *          struct longer than this version knows is accepted when the extra
 *          bytes are all 0 and is NotSupported otherwise. Reserved members
 *          are the caller's to check, because only it knows where they are.
 */
template <class T>
StructCheck ReadInputStruct(const T* in, T& out, uint32_t minSize = sizeof(T)) noexcept
{
    static_assert(std::is_trivially_copyable_v<T>, "input structs are plain C structs");
    out = T{};
    if (!in) return StructCheck::InvalidParameter;

    uint32_t size = 0;
    std::memcpy(&size, in, sizeof(size));
    if (size < minSize || size > kMaxStructSize) return StructCheck::InvalidParameter;

    const size_t known = sizeof(T);
    std::memcpy(&out, in, size < known ? size : known);

    const auto* bytes = reinterpret_cast<const unsigned char*>(in);
    for (size_t i = known; i < size; ++i) {
        if (bytes[i] != 0) return StructCheck::NotSupported;
    }
    return StructCheck::Ok;
}

}  // namespace NativeToolkitC::Detail
