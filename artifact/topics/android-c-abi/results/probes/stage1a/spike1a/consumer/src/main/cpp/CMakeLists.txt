cmake_minimum_required(VERSION 3.22.1)
project(consumer C CXX)
find_package(capi REQUIRED CONFIG)
if(ANDROID_STL STREQUAL "none")
  # A consumer without an STL cannot use <string>; it stays C only.
  add_library(consumer SHARED consumer.c consumer_c_stub.c)
else()
  add_library(consumer SHARED consumer.c consumer_cxx.cpp)
endif()
target_link_libraries(consumer capi::ntk log)

# dlopen-only probe in its own library that does not link libntk.so.
add_library(dlopenprobe SHARED dlopen_probe.c)
target_link_libraries(dlopenprobe dl)
