cmake_minimum_required(VERSION 3.22.1)
project(ntk_test CXX)

include(FetchContent)
FetchContent_Declare(googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.18.0.tar.gz
    URL_HASH SHA256=6e3191c1455468b3fc35a417fb565c1c5071aee1b7e7f85e30cf48a98d37d8b5)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

find_package(capi REQUIRED CONFIG)
add_library(ntk_test SHARED ntk_test.cpp)
target_compile_features(ntk_test PRIVATE cxx_std_17)
target_link_libraries(ntk_test PRIVATE capi::ntk GTest::gtest log)
