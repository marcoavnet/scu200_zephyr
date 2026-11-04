cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(mbv_myapp_httpd)

file(GLOB APP_SOURCES CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c
)

target_sources(app PRIVATE ${APP_SOURCES})


# Zephyr 4.3 HTTP resources are discovered through this linker section.
zephyr_linker_sources(SECTIONS sections-rom.ld)
zephyr_linker_section(NAME http_resource_desc_dashboard
                      KVMA RAM_REGION GROUP RODATA_REGION)

# Serve immutable gzip resources directly from ROM. No filesystem or CDN.
set(web_gen_root "${CMAKE_CURRENT_BINARY_DIR}/dashboard_generated")
set(web_gen_dir "${web_gen_root}/dashboard")
file(MAKE_DIRECTORY "${web_gen_dir}")
target_include_directories(app PRIVATE "${web_gen_root}")
set(web_generated_headers)
foreach(resource index.html app.css dsp.js app.js)
    set(generated_header "${web_gen_dir}/${resource}.gz.inc")
    generate_inc_file_for_target(app
        "${CMAKE_CURRENT_SOURCE_DIR}/web/${resource}"
        "${generated_header}"
        --gzip)
    list(APPEND web_generated_headers "${generated_header}")
endforeach()

# Explicit file dependencies also protect direct object builds and generators
# which do not order compilation solely through the app target dependencies.
set_property(SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/src/webserver.c"
    APPEND PROPERTY OBJECT_DEPENDS "${web_generated_headers}")

# Zephyr 4.3 omits lib/posix when native_sim uses the host libc. Its HTTP
# server still needs eventfd descriptors from the ZEPHYR fd table, not glibc's.
# This branch is for host validation only; embedded targets already link it.
if(CONFIG_ARCH_POSIX AND CONFIG_NATIVE_LIBC AND CONFIG_EVENTFD)
    target_sources(app PRIVATE ${ZEPHYR_BASE}/lib/posix/eventfd/eventfd.c)
endif()
