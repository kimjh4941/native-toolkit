cmake_minimum_required(VERSION 3.22.1)
project(ntk CXX)

add_library(ntk SHARED ntk.cpp)
target_include_directories(ntk PUBLIC include)
target_compile_features(ntk PRIVATE cxx_std_20)
target_compile_options(ntk PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)
target_link_options(ntk PRIVATE
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/libntk.map"
    "-Wl,-z,max-page-size=16384")
# ANDROID_STL=none removes the libc++ headers and libraries; add them back so that libc++ is
# linked statically and hidden by the version script.
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
