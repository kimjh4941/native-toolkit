#pragma once

// Build-setting guard for consumers of the static library.
//
// MSVC records the C runtime choice and the iterator debug level in every
// object and fails the link (LNK2038) when they disagree. It records nothing
// about the version of these headers or about the C++/WinRT configuration, so
// a consumer can link headers of one version against a library of another and
// only find out at run time. #pragma detect_mismatch adds those records: the
// linker compares the value the consumer compiled with against the value the
// library was compiled with, and refuses the link when they differ.
//
// Every public and internal header that a consumer can include pulls this in.

// The release these headers and the static library come from. The build script
// refuses to stamp a distributable with any other version, the way NTK_VERSION_*
// works for the C ABI. It is a label, not a link-time guard: what the linker
// compares is NATIVETOOLKIT_ABI_VERSION below.
#define NATIVETOOLKIT_VERSION_MAJOR 2
#define NATIVETOOLKIT_VERSION_MINOR 0
#define NATIVETOOLKIT_VERSION_PATCH 0

#define NATIVETOOLKIT_ABI_VERSION "1"

#pragma detect_mismatch("nativetoolkit_abi_version", NATIVETOOLKIT_ABI_VERSION)

// C++/WinRT's macro configuration has to match across every file that forms one
// binary, including static libraries. Record the settings that change the
// generated code.
#if defined(WINRT_NO_MODULE_LOCK)
#pragma detect_mismatch("nativetoolkit_winrt_module_lock", "none")
#elif defined(WINRT_CUSTOM_MODULE_LOCK)
#pragma detect_mismatch("nativetoolkit_winrt_module_lock", "custom")
#else
#pragma detect_mismatch("nativetoolkit_winrt_module_lock", "default")
#endif

#if defined(WINRT_NO_MAKE_DETECTION)
#pragma detect_mismatch("nativetoolkit_winrt_make_detection", "off")
#else
#pragma detect_mismatch("nativetoolkit_winrt_make_detection", "on")
#endif
