cmake_minimum_required(VERSION 3.16)
project(anyfile VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(ZLIB REQUIRED)

add_library(anyfile_core STATIC
  src/core/util.cpp
  src/core/registry.cpp
  src/pdf/object.cpp
  src/pdf/lexer.cpp
  src/pdf/parser.cpp
  src/pdf/filters.cpp
  src/pdf/document.cpp
  src/pdf/text.cpp
  src/epub/zip.cpp
  src/epub/xml.cpp
  src/epub/book.cpp
  src/handlers/byte_handler.cpp
  src/handlers/text_handler.cpp
  src/handlers/markdown_handler.cpp
  src/handlers/pdf_handler.cpp
  src/handlers/epub_handler.cpp
)
target_include_directories(anyfile_core PUBLIC src)
target_link_libraries(anyfile_core PUBLIC ZLIB::ZLIB)
target_compile_options(anyfile_core PRIVATE -Wall -Wextra -Wpedantic)

add_executable(anyfile src/main.cpp)
target_link_libraries(anyfile PRIVATE anyfile_core)
target_compile_options(anyfile PRIVATE -Wall -Wextra -Wpedantic)

install(TARGETS anyfile RUNTIME DESTINATION bin)

enable_testing()
add_test(NAME smoke COMMAND ${CMAKE_SOURCE_DIR}/tests/run_tests.sh $<TARGET_FILE:anyfile>)

# Unit tests: one executable per module, all registered with CTest.
foreach(mod lexer parser filters util document text handlers zip xml book)
  add_executable(${mod}_test tests/unit/${mod}_test.cpp)
  target_link_libraries(${mod}_test PRIVATE anyfile_core)
  target_include_directories(${mod}_test PRIVATE tests/unit)
  target_compile_options(${mod}_test PRIVATE -Wall -Wextra)
  add_test(NAME unit_${mod} COMMAND ${mod}_test)
endforeach()
