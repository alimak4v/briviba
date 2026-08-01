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

add_executable(
  Briviba
  MACOSX_BUNDLE
  src/main.mm
  src/app_paths.cc
  src/bookmark_manager.cc
  src/browser_window.mm
  src/cookie_manager.mm
  src/download_manager.mm
  src/history_manager.cc
  src/settings_manager.cc
  src/sidebar.mm
  src/tab.mm
  src/tab_manager.mm
  src/toolbar.mm
  src/window_manager.cc
  resources/BrivibaIcon.icns
  resources/video_translation_relay.js
  resources/video_translation_shim.js)

target_include_directories(Briviba PRIVATE include)

target_link_libraries(Briviba PRIVATE "-framework AppKit" "-framework WebKit" sqlite3)

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

set_source_files_properties(resources/BrivibaIcon.icns PROPERTIES MACOSX_PACKAGE_LOCATION
                                                                  Resources)
set_source_files_properties(resources/video_translation_shim.js PROPERTIES MACOSX_PACKAGE_LOCATION
                                                                       Resources)
set_source_files_properties(resources/video_translation_relay.js PROPERTIES MACOSX_PACKAGE_LOCATION
                                                                        Resources)

set_source_files_properties(src/main.mm src/browser_window.mm src/cookie_manager.mm
                            src/download_manager.mm src/sidebar.mm src/tab.mm src/tab_manager.mm
                            src/toolbar.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")

enable_testing()
find_program(NODE_EXECUTABLE node)
if(NODE_EXECUTABLE)
  add_test(NAME video_translation_bridge
           COMMAND "${NODE_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/video_translation_bridge_test.js")
  add_test(NAME video_translation_relay
           COMMAND "${NODE_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/video_translation_relay_test.js")
endif()
