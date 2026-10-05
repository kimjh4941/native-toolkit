cmake_minimum_required(VERSION 3.22.1)
project(ntk_test CXX)

# GoogleTest v1.18.0 from source, pinned by URL and SHA-256 (AC-14). For an offline build, point
# FETCHCONTENT_SOURCE_DIR_GOOGLETEST at a local copy of the same release.
include(FetchContent)
FetchContent_Declare(googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.18.0.tar.gz
    URL_HASH SHA256=6e3191c1455468b3fc35a417fb565c1c5071aee1b7e7f85e30cf48a98d37d8b5)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

find_package(ntk REQUIRED CONFIG)

# The GoogleTest cases and the JNI helpers the instrumented tests call.
add_library(ntk_test SHARED
    ntk_test_jni.cpp
    tests/CommonTest.cpp)
target_compile_features(ntk_test PRIVATE cxx_std_20)
target_compile_options(ntk_test PRIVATE -Wall -Wextra -Werror)
target_link_libraries(ntk_test PRIVATE ntk::ntk GTest::gtest log)

# A library that depends on libntk.so and has no JNI_OnLoad of its own, as an app's .so may be:
# loading it runs libntk.so's JNI_OnLoad again (design part 1, chapter 6; stage 1a 3.2).
add_library(ntk_second SHARED second.cpp)
target_link_libraries(ntk_second PRIVATE ntk::ntk)
