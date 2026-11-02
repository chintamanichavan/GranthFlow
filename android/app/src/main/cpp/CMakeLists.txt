# The engine for Android: the repository's own build supplies anyfile_core (only that library is
# built, not the command-line tool or its tests), and engine_jni.cpp hands it to Kotlin.
cmake_minimum_required(VERSION 3.22)
project(granthflow_jni LANGUAGES CXX)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../../../.. anyfile EXCLUDE_FROM_ALL)

add_library(anyfile_jni SHARED engine_jni.cpp)
target_link_libraries(anyfile_jni PRIVATE anyfile_core)
target_compile_options(anyfile_jni PRIVATE -Wall -Wextra -Wpedantic)
