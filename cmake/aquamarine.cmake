# Builds the embedded aquamarine (subprojects/aquamarine) as a static library.
#
# The system aquamarine requires OpenGL ES 3.0 for its DRM renderer, so Hypoland
# carries its own copy, which uses GLES2 only, and never links the system one.
# aquamarine's own CMakeLists.txt assumes it is the top-level project, which is
# why the target is defined here instead of using add_subdirectory().

set(AQ_DIR ${CMAKE_SOURCE_DIR}/subprojects/aquamarine)
set(AQ_GEN_DIR ${CMAKE_BINARY_DIR}/aquamarine-gen)
file(MAKE_DIRECTORY ${AQ_GEN_DIR})

file(READ "${AQ_DIR}/VERSION" AQ_VER_RAW)
string(STRIP ${AQ_VER_RAW} AQUAMARINE_VERSION)

pkg_check_modules(
  aquamarine_deps
  REQUIRED
  IMPORTED_TARGET
  libseat>=0.8.0
  libinput>=1.26.0
  wayland-client
  wayland-protocols
  hyprutils>=0.8.0
  pixman-1
  libdrm
  gbm
  libudev
  libdisplay-info
  hwdata)

file(GLOB_RECURSE AQ_SRCFILES CONFIGURE_DEPENDS "${AQ_DIR}/src/*.cpp")

add_library(aquamarine STATIC ${AQ_SRCFILES})
set_target_properties(aquamarine PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(aquamarine PRIVATE AQUAMARINE_VERSION="${AQUAMARINE_VERSION}")
if(aquamarine_deps_libinput_VERSION VERSION_GREATER_EQUAL "1.30")
  target_compile_definitions(aquamarine PRIVATE AQUAMARINE_HAS_LIBINPUT_PLUGINS)
endif()
if(CMAKE_BUILD_TYPE MATCHES Debug OR CMAKE_BUILD_TYPE MATCHES DEBUG)
  target_compile_definitions(aquamarine PRIVATE AQUAMARINE_DEBUG)
endif()
# BEFORE: the generated client headers must win over the compositor's
# server-side protocols/ dir, which is in the directory-wide include path.
target_include_directories(
  aquamarine BEFORE
  PUBLIC "${AQ_DIR}/include"
  PRIVATE "${AQ_GEN_DIR}" "${AQ_DIR}/src" "${AQ_DIR}/src/include")
target_link_libraries(aquamarine PUBLIC OpenGL::EGL OpenGL::GLES2 PkgConfig::aquamarine_deps)

# Client-side protocols. Generated into the build dir: the compositor generates
# server-side headers with the same file names in protocols/.
pkg_get_variable(AQ_WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
pkg_get_variable(AQ_WAYLAND_SCANNER_PKGDATA_DIR wayland-scanner pkgdatadir)

function(aquamarine_protocol xml name)
  add_custom_command(
    OUTPUT ${AQ_GEN_DIR}/${name}.cpp ${AQ_GEN_DIR}/${name}.hpp
    COMMAND hyprwayland-scanner ${ARGN} --client ${xml} ${AQ_GEN_DIR}/
    DEPENDS ${xml}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  target_sources(aquamarine PRIVATE ${AQ_GEN_DIR}/${name}.cpp ${AQ_GEN_DIR}/${name}.hpp)
endfunction()

aquamarine_protocol(${AQ_WAYLAND_SCANNER_PKGDATA_DIR}/wayland.xml wayland --wayland-enums)
aquamarine_protocol(${AQ_WAYLAND_PROTOCOLS_DIR}/stable/xdg-shell/xdg-shell.xml xdg-shell)
aquamarine_protocol(${AQ_WAYLAND_PROTOCOLS_DIR}/stable/linux-dmabuf/linux-dmabuf-v1.xml linux-dmabuf-v1)

# hwdata
pkg_get_variable(AQ_HWDATA_DIR hwdata pkgdatadir)
execute_process(
  COMMAND /bin/sh -c "${AQ_DIR}/data/hwdata.sh < ${AQ_HWDATA_DIR}/pnp.ids"
  RESULT_VARIABLE HWDATA_PNP_RESULT
  OUTPUT_VARIABLE HWDATA_PNP_IDS ENCODING UTF8)
if(NOT HWDATA_PNP_RESULT MATCHES 0)
  message(WARNING "hwdata gathering pnps failed")
endif()
configure_file(${AQ_DIR}/data/hwdata.hpp.in ${AQ_GEN_DIR}/hwdata.hpp @ONLY)

message(STATUS "Using embedded aquamarine ${AQUAMARINE_VERSION} (static)")

# The compositor generates the same wl_*/xdg_*/zwp_* interface tables for its
# server side. As a shared library aquamarine's copies were interposed by the
# executable's; weaken them so the static link resolves the same way.
find_program(OBJCOPY NAMES ${CMAKE_OBJCOPY} objcopy REQUIRED)
add_custom_command(
  TARGET aquamarine POST_BUILD
  COMMAND ${OBJCOPY} -w -W "wl_*_interface" -W "xdg_*_interface" -W "zwp_*_interface" $<TARGET_FILE:aquamarine>
  VERBATIM)
