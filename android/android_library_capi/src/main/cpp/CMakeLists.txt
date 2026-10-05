cmake_minimum_required(VERSION 3.22.1)
project(ntk CXX)

# libntk.so, the C ABI (C ABI design part 1, 5.1 and 5.4, AC-12).
add_library(ntk SHARED
    src/Clipboard/Clipboard.cpp
    src/Dialog/Dialog.cpp
    src/Notification/Builders.cpp
    src/Notification/Notification.cpp
    src/Share/Share.cpp
    src/Common/Classes.cpp
    src/Common/Handles.cpp
    src/Common/Jni.cpp
    src/Common/Registry.cpp
    src/Common/Runtime.cpp
    src/Common/Utf8.cpp)
# Debug builds only: the probe operation of the C ABI tests (src/Debug/Probe.h). A release build
# has none of it, and Classes.cpp leaves its class out (NDEBUG).
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_sources(ntk PRIVATE src/Debug/Probe.cpp)
endif()
target_include_directories(ntk PUBLIC include)
target_include_directories(ntk PRIVATE src)
target_compile_features(ntk PRIVATE cxx_std_20)
target_compile_options(ntk PRIVATE -Wall -Wextra -Werror -fvisibility=hidden -fvisibility-inlines-hidden)
target_link_options(ntk PRIVATE
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/libntk.map"
    "-Wl,-z,max-page-size=16384")
set_target_properties(ntk PROPERTIES LINK_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/libntk.map")

# ANDROID_STL=none removes the libc++ headers and libraries; add them back so that libc++ is
# linked statically and hidden by the version script (stage 1a 3.3). The triple comes from
# ANDROID_ABI because the newer toolchain file leaves ANDROID_TOOLCHAIN_NAME unset.
set(NTK_SYSROOT "${ANDROID_TOOLCHAIN_ROOT}/sysroot")
target_include_directories(ntk SYSTEM PRIVATE "${NTK_SYSROOT}/usr/include/c++/v1")
if(ANDROID_ABI STREQUAL "arm64-v8a")
  set(NTK_TRIPLE aarch64-linux-android)
elseif(ANDROID_ABI STREQUAL "x86_64")
  set(NTK_TRIPLE x86_64-linux-android)
else()
  message(FATAL_ERROR "unsupported ABI ${ANDROID_ABI}")
endif()
set(NTK_LIBDIR "${NTK_SYSROOT}/usr/lib/${NTK_TRIPLE}")
# JNI_GetCreatedJavaVMs is in libnativehelper from API 31.
target_link_libraries(ntk PRIVATE
    "${NTK_LIBDIR}/libc++_static.a" "${NTK_LIBDIR}/libc++abi.a" log nativehelper)
