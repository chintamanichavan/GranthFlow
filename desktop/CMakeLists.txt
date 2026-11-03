# GranthFlow for Windows and Linux (and macOS, where it is built and tested day to day): Qt 6 and
# QML over the same C++ engine as every other GranthFlow.
#     cmake -S desktop -B desktop/build -DCMAKE_PREFIX_PATH=<Qt> && cmake --build desktop/build
#     ctest --test-dir desktop/build
cmake_minimum_required(VERSION 3.21)
project(granthflow_desktop VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.6 REQUIRED COMPONENTS Quick QuickControls2 Pdf PdfQuick Test)
qt_standard_project_setup(REQUIRES 6.6)

# The engine, without its command-line tool and tests.
add_subdirectory(.. anyfile EXCLUDE_FROM_ALL)

# Everything but main(): the tests link it too.
qt_add_library(granthflow_core STATIC)
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(granthflow_core
  URI GranthFlow
  VERSION 1.0
  SOURCES
    src/Engine.h src/Engine.cpp
    src/Library.h src/Library.cpp
    src/Document.h src/Document.cpp
    src/Typesetter.h src/Typesetter.cpp
    src/ReadingSettings.h src/ReadingSettings.cpp
    src/Cover.h src/Cover.cpp
    src/Faces.h src/Faces.cpp
  QML_FILES
    qml/Main.qml
    qml/Theme.qml
    qml/LibraryView.qml
    qml/ReaderView.qml
    qml/EpubReader.qml
    qml/PdfReader.qml
    qml/TextReader.qml
    qml/HexReader.qml
    qml/TypeSettingsPanel.qml
)
target_include_directories(granthflow_core PUBLIC src)
target_link_libraries(granthflow_core PUBLIC anyfile_core Qt6::Quick Qt6::QuickControls2 Qt6::Pdf Qt6::PdfQuick)
if(NOT MSVC)
  target_compile_options(granthflow_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

qt_add_executable(granthflow src/main.cpp)
target_link_libraries(granthflow PRIVATE granthflow_core granthflow_coreplugin)
set_target_properties(granthflow PROPERTIES OUTPUT_NAME GranthFlow WIN32_EXECUTABLE ON MACOSX_BUNDLE ON)

enable_testing()
foreach(name library typesetter document cover ui)
  qt_add_executable(${name}_test tests/${name}_test.cpp)
  target_link_libraries(${name}_test PRIVATE granthflow_core granthflow_coreplugin Qt6::Test)
  target_include_directories(${name}_test PRIVATE ../tests/unit)        # the engine's own EPUB and PDF fixtures
  add_test(NAME ${name} COMMAND ${name}_test)
  set_tests_properties(${name} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endforeach()
