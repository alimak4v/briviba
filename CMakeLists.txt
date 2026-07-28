cmake_minimum_required(VERSION 3.24)

project(
  Briviba
  VERSION 0.1.0
  DESCRIPTION "Native macOS browser"
  LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_EXTENSIONS OFF)

add_executable(Briviba MACOSX_BUNDLE src/main.mm)

target_link_libraries(Briviba PRIVATE "-framework AppKit")

target_compile_options(
  Briviba
  PRIVATE -Wall
          -Wextra
          -Wpedantic
          -Werror)

set_target_properties(
  Briviba
  PROPERTIES OUTPUT_NAME Briviba
             MACOSX_BUNDLE TRUE
             MACOSX_BUNDLE_BUNDLE_NAME Briviba
             MACOSX_BUNDLE_GUI_IDENTIFIER app.briviba.browser
             MACOSX_BUNDLE_INFO_PLIST
             "${CMAKE_CURRENT_SOURCE_DIR}/resources/Info.plist.in")
