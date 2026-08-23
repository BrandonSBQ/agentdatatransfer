cmake_minimum_required(VERSION 3.20)

project(company_oss_file_service LANGUAGES CXX)

include(FetchContent)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(AGENT_BUILD_TESTS "Build unit tests" ON)
if(AGENT_BUILD_TESTS)
  enable_testing()
  include(CTest)
endif()

find_package(Protobuf CONFIG REQUIRED)
find_package(gRPC REQUIRED)
find_package(CURL REQUIRED)
find_package(OpenSSL REQUIRED)

# MySQL client library (libmysqlclient). On Debian/Ubuntu install
# libmysqlclient-dev (or default-libmysqlclient-dev); on macOS use
# mysql-connector-c via Homebrew. The header is included as <mysql.h>.
find_path(MYSQL_INCLUDE_DIR mysql.h PATH_SUFFIXES mysql)
find_library(MYSQL_LIBRARY NAMES mysqlclient)
if(NOT MYSQL_INCLUDE_DIR OR NOT MYSQL_LIBRARY)
  message(FATAL_ERROR "MySQL client library not found. Install libmysqlclient-dev "
    "(Debian/Ubuntu), default-libmysqlclient-dev, or mysql-connector-c (macOS).")
endif()

set(THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/3rd")
set(SPDLOG_DIR "${THIRD_PARTY_DIR}/spdlog")
set(ALIYUN_OSS_SDK_DIR "${THIRD_PARTY_DIR}/aliyun-oss-cpp-sdk")
set(CPP_HTTPLIB_DIR "${THIRD_PARTY_DIR}/cpp-httplib")

if(NOT EXISTS "${SPDLOG_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "spdlog source not found under ${SPDLOG_DIR}")
endif()

if(NOT EXISTS "${CPP_HTTPLIB_DIR}/httplib.h")
  set(CPP_HTTPLIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../cpp-httplib")
endif()

if(NOT EXISTS "${CPP_HTTPLIB_DIR}/httplib.h")
  message(FATAL_ERROR "cpp-httplib source not found under ${THIRD_PARTY_DIR} or ../cpp-httplib")
endif()

set(BUILD_SAMPLE OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

if(EXISTS "${ALIYUN_OSS_SDK_DIR}/CMakeLists.txt")
  set(ALIYUN_OSS_SDK_INCLUDE_DIR "${ALIYUN_OSS_SDK_DIR}/sdk/include")
  add_subdirectory("${ALIYUN_OSS_SDK_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/aliyun-oss-sdk" EXCLUDE_FROM_ALL)
else()
  FetchContent_Declare(
    aliyun_oss_cpp_sdk
    GIT_REPOSITORY https://github.com/aliyun/aliyun-oss-cpp-sdk.git
    GIT_TAG master
    GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(aliyun_oss_cpp_sdk)
  set(ALIYUN_OSS_SDK_INCLUDE_DIR "${aliyun_oss_cpp_sdk_SOURCE_DIR}/sdk/include")
endif()

add_subdirectory("${SPDLOG_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/spdlog" EXCLUDE_FROM_ALL)

# --- Catch2 (only when tests are enabled) ---
if(AGENT_BUILD_TESTS)
  FetchContent_Declare(
    Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG v3.5.4
    GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(Catch2)
endif()

set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")

if(TARGET protobuf::protoc)
  set(PROTOC_EXE "$<TARGET_FILE:protobuf::protoc>")
else()
  set(PROTOC_EXE "${Protobuf_PROTOC_EXECUTABLE}")
endif()

if(TARGET gRPC::grpc_cpp_plugin)
  set(GRPC_CPP_PLUGIN_EXE "$<TARGET_FILE:gRPC::grpc_cpp_plugin>")
else()
  find_program(GRPC_CPP_PLUGIN_EXE grpc_cpp_plugin REQUIRED)
endif()

# --- Risk RPC protos ---
set(RISK_COOP_PROTO "${CMAKE_CURRENT_SOURCE_DIR}/risk_cooperation.proto")
set(RISK_COMP_PROTO "${CMAKE_CURRENT_SOURCE_DIR}/risk_compliance.proto")

set(RISK_COOP_PROTO_SRCS
    "${GENERATED_DIR}/risk_cooperation.pb.cc"
    "${GENERATED_DIR}/risk_cooperation.grpc.pb.cc")
set(RISK_COOP_PROTO_HDRS
    "${GENERATED_DIR}/risk_cooperation.pb.h"
    "${GENERATED_DIR}/risk_cooperation.grpc.pb.h")

set(RISK_COMP_PROTO_SRCS
    "${GENERATED_DIR}/risk_compliance.pb.cc"
    "${GENERATED_DIR}/risk_compliance.grpc.pb.cc")
set(RISK_COMP_PROTO_HDRS
    "${GENERATED_DIR}/risk_compliance.pb.h"
    "${GENERATED_DIR}/risk_compliance.grpc.pb.h")

add_custom_command(
  OUTPUT ${RISK_COOP_PROTO_SRCS} ${RISK_COOP_PROTO_HDRS}
  COMMAND ${PROTOC_EXE}
  ARGS
    --proto_path=${CMAKE_CURRENT_SOURCE_DIR}
    --cpp_out=${GENERATED_DIR}
    --grpc_out=${GENERATED_DIR}
    --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}
    ${RISK_COOP_PROTO}
  DEPENDS "${RISK_COOP_PROTO}"
  VERBATIM)

add_custom_command(
  OUTPUT ${RISK_COMP_PROTO_SRCS} ${RISK_COMP_PROTO_HDRS}
  COMMAND ${PROTOC_EXE}
  ARGS
    --proto_path=${CMAKE_CURRENT_SOURCE_DIR}
    --cpp_out=${GENERATED_DIR}
    --grpc_out=${GENERATED_DIR}
    --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}
    ${RISK_COMP_PROTO}
  DEPENDS "${RISK_COMP_PROTO}"
  VERBATIM)

add_library(risk_rpc_proto
  ${RISK_COOP_PROTO_SRCS} ${RISK_COMP_PROTO_SRCS})
target_include_directories(risk_rpc_proto PUBLIC "${GENERATED_DIR}")
target_link_libraries(risk_rpc_proto PUBLIC gRPC::grpc++ protobuf::libprotobuf)

# --- Cooperation Api proto (RDWT) ---
set(COOP_PROTO "${CMAKE_CURRENT_SOURCE_DIR}/cooperation.proto")
set(COOP_PROTO_SRCS
    "${GENERATED_DIR}/cooperation.pb.cc"
    "${GENERATED_DIR}/cooperation.grpc.pb.cc")
set(COOP_PROTO_HDRS
    "${GENERATED_DIR}/cooperation.pb.h"
    "${GENERATED_DIR}/cooperation.grpc.pb.h")
add_custom_command(
  OUTPUT ${COOP_PROTO_SRCS} ${COOP_PROTO_HDRS}
  COMMAND ${PROTOC_EXE}
  ARGS
    --proto_path=${CMAKE_CURRENT_SOURCE_DIR}
    --cpp_out=${GENERATED_DIR}
    --grpc_out=${GENERATED_DIR}
    --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}
    ${COOP_PROTO}
  DEPENDS "${COOP_PROTO}"
  VERBATIM)
add_library(coop_rpc_proto ${COOP_PROTO_SRCS})
target_include_directories(coop_rpc_proto PUBLIC "${GENERATED_DIR}")
target_link_libraries(coop_rpc_proto PUBLIC gRPC::grpc++ protobuf::libprotobuf)

# --- Foundation Api proto (Item mapping) ---
set(FND_PROTO "${CMAKE_CURRENT_SOURCE_DIR}/foundation.proto")
set(FND_PROTO_SRCS
    "${GENERATED_DIR}/foundation.pb.cc"
    "${GENERATED_DIR}/foundation.grpc.pb.cc")
set(FND_PROTO_HDRS
    "${GENERATED_DIR}/foundation.pb.h"
    "${GENERATED_DIR}/foundation.grpc.pb.h")
add_custom_command(
  OUTPUT ${FND_PROTO_SRCS} ${FND_PROTO_HDRS}
  COMMAND ${PROTOC_EXE}
  ARGS
    --proto_path=${CMAKE_CURRENT_SOURCE_DIR}
    --cpp_out=${GENERATED_DIR}
    --grpc_out=${GENERATED_DIR}
    --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}
    ${FND_PROTO}
  DEPENDS "${FND_PROTO}"
  VERBATIM)
add_library(fnd_rpc_proto ${FND_PROTO_SRCS})
target_include_directories(fnd_rpc_proto PUBLIC "${GENERATED_DIR}")
target_link_libraries(fnd_rpc_proto PUBLIC gRPC::grpc++ protobuf::libprotobuf)

# --- Agent Data Transfer Api proto (gRPC 入口, 监听 9090) ---
set(ADT_PROTO "${CMAKE_CURRENT_SOURCE_DIR}/agent_data_transfer.proto")
set(ADT_PROTO_SRCS
    "${GENERATED_DIR}/agent_data_transfer.pb.cc"
    "${GENERATED_DIR}/agent_data_transfer.grpc.pb.cc")
set(ADT_PROTO_HDRS
    "${GENERATED_DIR}/agent_data_transfer.pb.h"
    "${GENERATED_DIR}/agent_data_transfer.grpc.pb.h")
add_custom_command(
  OUTPUT ${ADT_PROTO_SRCS} ${ADT_PROTO_HDRS}
  COMMAND ${PROTOC_EXE}
  ARGS
    --proto_path=${CMAKE_CURRENT_SOURCE_DIR}
    --cpp_out=${GENERATED_DIR}
    --grpc_out=${GENERATED_DIR}
    --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}
    ${ADT_PROTO}
  DEPENDS "${ADT_PROTO}"
  VERBATIM)
add_library(adt_rpc_proto ${ADT_PROTO_SRCS})
target_include_directories(adt_rpc_proto PUBLIC "${GENERATED_DIR}")
target_link_libraries(adt_rpc_proto PUBLIC gRPC::grpc++ protobuf::libprotobuf)

# --- Name Screening Api proto (screening.api.v1) ---
set(NS_PROTO "${CMAKE_CURRENT_SOURCE_DIR}/name_screening.proto")
set(NS_PROTO_SRCS
    "${GENERATED_DIR}/name_screening.pb.cc"
    "${GENERATED_DIR}/name_screening.grpc.pb.cc")
set(NS_PROTO_HDRS
    "${GENERATED_DIR}/name_screening.pb.h"
    "${GENERATED_DIR}/name_screening.grpc.pb.h")
add_custom_command(
  OUTPUT ${NS_PROTO_SRCS} ${NS_PROTO_HDRS}
  COMMAND ${PROTOC_EXE}
  ARGS
    --proto_path=${CMAKE_CURRENT_SOURCE_DIR}
    --cpp_out=${GENERATED_DIR}
    --grpc_out=${GENERATED_DIR}
    --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}
    ${NS_PROTO}
  DEPENDS "${NS_PROTO}"
  VERBATIM)
add_library(ns_rpc_proto ${NS_PROTO_SRCS})
target_include_directories(ns_rpc_proto PUBLIC "${GENERATED_DIR}")
target_link_libraries(ns_rpc_proto PUBLIC gRPC::grpc++ protobuf::libprotobuf)

set(SERVICE_SRCS
  src/main.cc
  src/util/base64.cc
  src/util/json_escape.cc
  src/util/logger.cc
  src/http/http_query_server.cc
  src/http/health_server.cc
  src/http/risk_json_serializer.cc
  src/grpc/risk_rpc_client.cc
  src/grpc/cooperation_client.cc
  src/grpc/foundation_client.cc
  src/grpc/name_screening_client.cc
  src/grpc/agent_data_transfer_service.cc
  src/cooperation/cooperation_query_service.cc
  src/mock/mock_risk_data_repository.cc
  src/metadata/mysql_metadata_repository.cc
  src/oss/aliyun_oss_client.cc)

add_executable(company_oss_file_service ${SERVICE_SRCS})
target_include_directories(company_oss_file_service PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${GENERATED_DIR}"
  "${ALIYUN_OSS_SDK_INCLUDE_DIR}"
  "${CPP_HTTPLIB_DIR}"
  "${MYSQL_INCLUDE_DIR}")
target_link_libraries(company_oss_file_service PRIVATE
  risk_rpc_proto
  coop_rpc_proto
  fnd_rpc_proto
  adt_rpc_proto
  ns_rpc_proto
  gRPC::grpc++
  gRPC::grpc++_reflection
  protobuf::libprotobuf
  ${MYSQL_LIBRARY}
  cpp-sdk
  spdlog::spdlog_header_only
  ${CURL_LIBRARIES}
  ${OPENSSL_LIBRARIES})

if(AGENT_BUILD_TESTS)
  add_subdirectory(tests)
endif()
