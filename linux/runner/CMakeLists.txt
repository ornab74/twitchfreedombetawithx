cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
apply_standard_settings(${BINARY_NAME})
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE ${CMAKE_DL_LIBS})
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# `flutter build linux` assembles the runtime bundle directly; it does not
# execute the CMake install rules in the parent project. Copy mpv during the
# normal build so the shipped executable has its matching SONAME beside it.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/bundle/lib"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${TWITCH_FREEDOM_LIBMPV}"
    "${CMAKE_BINARY_DIR}/bundle/lib/"
  COMMENT "Bundling libmpv with the Linux runtime"
)
