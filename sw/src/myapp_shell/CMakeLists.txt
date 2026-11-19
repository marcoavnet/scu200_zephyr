# Copyright (c) 2026 Marco Höfle, Avnet-Silica
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files to deal in the software
# without restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

cmake_minimum_required(VERSION 3.20.0)


# Alle Environment-Variablen ausgeben
#execute_process(COMMAND ${CMAKE_COMMAND} -E environment)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(mbv_myapp)

# Generate the compilation database for VS Code.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

file(GLOB APP_SOURCES CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c
)

target_sources(app PRIVATE ${APP_SOURCES})

# Application only: disable optimization and include detailed debug information.
# Source-level options follow Zephyr's target-wide compiler options.
set_property(
    SOURCE ${APP_SOURCES}
    APPEND PROPERTY COMPILE_OPTIONS
        -O0
        -g3
)