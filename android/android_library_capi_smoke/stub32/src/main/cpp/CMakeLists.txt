cmake_minimum_required(VERSION 3.22.1)
project(stub32 C)

# The 32-bit code of an app whose C ABI part is 64-bit only (-Pabi32; README chapter 9), built
# apart from the app's own CMake, which uses the 64-bit-only Prefab package.
add_library(stub32 SHARED stub32.c)
