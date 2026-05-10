file(GLOB util_SRC *.cpp 3rdparty/*.cpp log/*.cpp)
add_library(pb_util ${util_SRC})
target_include_directories(pb_util PUBLIC
)

file(GLOB_RECURSE util_geoSRC geo/*.cpp)
add_library(pb_util_geo ${util_geoSRC})
target_include_directories(pb_util_geo PUBLIC
)

file(GLOB_RECURSE util_jsonSRC json/*.cpp)
add_library(pb_util_json ${util_jsonSRC})
target_include_directories(pb_util_json PUBLIC
)

file(GLOB_RECURSE util_xmlSRC xml/*.cpp)
add_library(pb_util_xml ${util_xmlSRC})
target_include_directories(pb_util_xml PUBLIC
)

file(GLOB_RECURSE util_graphSRC graph/*.cpp)
add_library(pb_util_graph ${util_graphSRC})
target_include_directories(pb_util_graph PUBLIC
)

file(GLOB_RECURSE util_httpSRC http/*.cpp)
add_library(pb_util_http ${util_httpSRC})
target_include_directories(pb_util_http PUBLIC
)

if (NOT BZIP2_FOUND)
    find_package(BZip2)
endif()

if (BZIP2_FOUND)
	target_compile_definitions(pb_util PUBLIC PBUTIL_BZLIB_FOUND=1 )
	target_include_directories(pb_util PUBLIC ${BZIP2_INCLUDE_DIR} )
	target_link_libraries( pb_util ${BZIP2_LIBRARIES} )

	target_compile_definitions(pb_util_http PUBLIC PBUTIL_BZLIB_FOUND=1 )
	target_include_directories(pb_util_http PUBLIC ${BZIP2_INCLUDE_DIR} )
	target_link_libraries(pb_util_http ${BZIP2_LIBRARIES})

	target_compile_definitions(pb_util_xml PUBLIC PBUTIL_BZLIB_FOUND=1 )
	target_include_directories(pb_util_xml PUBLIC ${BZIP2_INCLUDE_DIR} )
	target_link_libraries(pb_util_xml ${BZIP2_LIBRARIES})
endif(BZIP2_FOUND)

if (NOT ZLIB_FOUND)
    find_package(ZLIB)
endif()

if (ZLIB_FOUND)
	target_compile_definitions(pb_util PUBLIC PBUTIL_ZLIB_FOUND=1 )
	target_include_directories(pb_util PUBLIC ${ZLIB_INCLUDE_DIRS} )
	target_link_libraries(pb_util ${ZLIB_LIBRARIES})

	target_compile_definitions(pb_util_http PUBLIC PBUTIL_ZLIB_FOUND=1 )
	target_include_directories(pb_util_http PUBLIC ${ZLIB_INCLUDE_DIRS} )
	target_link_libraries(pb_util_http ${ZLIB_LIBRARIES})

	target_compile_definitions(pb_util_http PUBLIC PBUTIL_ZLIB_FOUND=1 )
	target_include_directories(pb_util_http PUBLIC ${ZLIB_INCLUDE_DIRS} )
	target_link_libraries(pb_util_http ${ZLIB_LIBRARIES})

	target_compile_definitions(pb_util_xml PUBLIC PBUTIL_ZLIB_FOUND=1 )
	target_include_directories(pb_util_xml PUBLIC ${ZLIB_INCLUDE_DIRS} )
	target_link_libraries(pb_util_xml ${ZLIB_LIBRARIES})
endif(ZLIB_FOUND)

if(CMAKE_TESTING_ENABLED)
    add_subdirectory(tests)
endif()
