include_directories(
        ${LOOM_INCLUDE_DIR}
)
add_executable(dotTest TestMain.cpp)
target_link_libraries(dotTest dot_dep ad_cppgtfs)