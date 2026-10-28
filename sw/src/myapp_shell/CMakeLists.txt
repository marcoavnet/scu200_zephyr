cmake_minimum_required(VERSION 3.20.0)


# Alle Environment-Variablen ausgeben
execute_process(COMMAND ${CMAKE_COMMAND} -E environment)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(mbv_myapp)

file(GLOB APP_SOURCES CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c
)

target_sources(app PRIVATE ${APP_SOURCES})

