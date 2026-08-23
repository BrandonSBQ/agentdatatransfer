# Test target — Catch2 v3, characterization tests for the production source tree.
#
# Keep this list small and explicit. Add a new executable per logical group
# (e.g. health_server, http_query_server) instead of one monolithic runner.

find_package(Threads REQUIRED)

# cpp-httplib needs pthreads on POSIX; Catch2 with the default main does too.
add_executable(health_server_test
  health_server_test.cpp
  ../src/http/health_server.cc
  ../src/util/logger.cc)
target_include_directories(health_server_test PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
  "${CPP_HTTPLIB_DIR}")
target_link_libraries(health_server_test PRIVATE
  Catch2::Catch2WithMain
  Threads::Threads
  spdlog::spdlog_header_only)

# Surface assertion failures as test failures in CTest output.
include(Catch)
catch_discover_tests(health_server_test)
