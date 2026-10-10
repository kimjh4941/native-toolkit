cmake_minimum_required(VERSION 3.22.1)
project(smoke C CXX)

# A consumer as the manual describes it: the C ABI from the AAR's Prefab package (AC-13).
find_package(ntk REQUIRED CONFIG)

add_library(smoke SHARED smoke.c)
# With an STL, the app's own C++ uses std::string next to libntk.so's hidden libc++ (stage 1a 3.3).
if(NOT ANDROID_STL STREQUAL "none")
  target_sources(smoke PRIVATE smoke_cxx.cpp)
endif()
target_compile_options(smoke PRIVATE -Wall -Wextra -Werror)
target_link_libraries(smoke PRIVATE ntk::ntk log)
