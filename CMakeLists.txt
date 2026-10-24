cmake_minimum_required(VERSION 3.16)
project(anyfile VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# zlib comes from the system natively, and from Emscripten's ports for the WebAssembly build.
if(NOT EMSCRIPTEN)
  find_package(ZLIB REQUIRED)
endif()

add_library(anyfile_core STATIC
  src/core/util.cpp
  src/core/registry.cpp
  src/core/engine.cpp
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
target_compile_options(anyfile_core PRIVATE -Wall -Wextra -Wpedantic)
if(EMSCRIPTEN)
  target_compile_options(anyfile_core PUBLIC -sUSE_ZLIB=1)
  target_link_options(anyfile_core PUBLIC -sUSE_ZLIB=1)
else()
  target_link_libraries(anyfile_core PUBLIC ZLIB::ZLIB)
endif()

if(EMSCRIPTEN)
  # The engine as an ES module for the PWA: web/app/engine.js wraps it the way Engine.swift
  # wraps the Objective-C++ bridge. Output lands in web/vendor/ next to the page that loads it.
  add_executable(anyfile_wasm src/wasm/engine_wasm.cpp)
  target_link_libraries(anyfile_wasm PRIVATE anyfile_core)
  target_compile_options(anyfile_wasm PRIVATE -Wall -Wextra -Wpedantic)
  set_target_properties(anyfile_wasm PROPERTIES
    OUTPUT_NAME anyfile
    SUFFIX ".mjs"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/web/vendor")
  target_link_options(anyfile_wasm PRIVATE
    --bind
    -O3
    -sMODULARIZE=1
    -sEXPORT_ES6=1
    -sEXPORT_NAME=createAnyfileEngine
    -sENVIRONMENT=web,worker,node   # node too, so the binding can be smoke-tested without a browser
    -sALLOW_MEMORY_GROWTH=1        # a 400-page PDF is far larger than the default heap
    -sSTACK_SIZE=4194304           # the PDF and XML parsers recurse through nested structures
    -sEXIT_RUNTIME=0)
else()
  add_executable(anyfile src/main.cpp)
  target_link_libraries(anyfile PRIVATE anyfile_core)
  target_compile_options(anyfile PRIVATE -Wall -Wextra -Wpedantic)

  install(TARGETS anyfile RUNTIME DESTINATION bin)

  enable_testing()
  add_test(NAME smoke COMMAND ${CMAKE_SOURCE_DIR}/tests/run_tests.sh $<TARGET_FILE:anyfile>)

  # Unit tests: one executable per module, all registered with CTest.
  foreach(mod lexer parser filters util document text handlers zip xml book engine)
    add_executable(${mod}_test tests/unit/${mod}_test.cpp)
    target_link_libraries(${mod}_test PRIVATE anyfile_core)
    target_include_directories(${mod}_test PRIVATE tests/unit)
    target_compile_options(${mod}_test PRIVATE -Wall -Wextra)
    add_test(NAME unit_${mod} COMMAND ${mod}_test)
  endforeach()
endif()
