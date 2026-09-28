cmake_minimum_required(VERSION 3.19)

project(start-hypoland DESCRIPTION "Hypoland watchdog binary")

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

find_package(PkgConfig REQUIRED)

pkg_check_modules(starthyprland_deps REQUIRED IMPORTED_TARGET hyprutils>=0.10.3)

file(GLOB_RECURSE SRCFILES CONFIGURE_DEPENDS "src/*.cpp")

add_executable(start-hyprland ${SRCFILES})

target_link_libraries(start-hyprland PUBLIC PkgConfig::starthyprland_deps)

set_target_properties(start-hyprland PROPERTIES OUTPUT_NAME start-hypoland)

install(TARGETS start-hyprland)

# start-hyprland is kept as a symlink, so existing session files keep working
install(
  CODE "execute_process( \
        COMMAND ${CMAKE_COMMAND} -E create_symlink \
        start-hypoland \
        \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_BINDIR}/start-hyprland\" \
        )")

if(CMAKE_BUILD_TYPE MATCHES Debug OR CMAKE_BUILD_TYPE MATCHES DEBUG)
  set(CMAKE_EXECUTABLE_ENABLE_EXPORTS TRUE)
endif()
