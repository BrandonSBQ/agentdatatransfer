#FROM ubuntu:24.04
FROM hk-global-registry-registry-vpc.cn-hongkong.cr.aliyuncs.com/public/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      ca-certificates \
      git \
      libcurl4-openssl-dev \
      libgrpc++-dev \
      libgrpc-dev \
      libprotobuf-dev \
      libmysqlclient-dev \
      libssl-dev \
      ninja-build \
      pkg-config \
      protobuf-compiler \
      protobuf-compiler-grpc \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

# Linux build portability (mirror Dockerfile.local): drop Protobuf CONFIG mode
# (no cmake config in the apt protobuf package) and relax SDK -Werror
# (curl deprecated APIs would otherwise be fatal). The SDK sed is guarded: in CI
# the aliyun-oss-cpp-sdk dir is an empty gitlink (built via FetchContent), so the
# file may not exist at this point.
RUN sed -i 's/find_package(Protobuf CONFIG REQUIRED)/find_package(Protobuf REQUIRED)/' CMakeLists.txt \
 && { [ -f src/3rd/aliyun-oss-cpp-sdk/CMakeLists.txt ] && sed -i 's/"-Werror"/"-Wno-error"/g' src/3rd/aliyun-oss-cpp-sdk/CMakeLists.txt || true; }

RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release

# SDK is fetched via FetchContent at configure time (empty gitlink in the repo).
# Relax its -Werror on the FETCHED copy — curl 8.5 deprecated APIs would
# otherwise be fatal. (The src/3rd sed above is a no-op in CI since the dir is
# empty; this one hits build/_deps. The next cmake --build re-configures.)
RUN sed -i 's/"-Werror"/"-Wno-error"/g' build/_deps/aliyun_oss_cpp_sdk-src/CMakeLists.txt

RUN cmake --build build -j4

ENV HTTP_ADDR=0.0.0.0:8080
ENV HEALTH_ADDR=0.0.0.0:7070
ENV GRPC_ADDR=0.0.0.0:9090
ENV LOG_LEVEL=info

EXPOSE 8080
EXPOSE 7070
EXPOSE 9090

CMD ["./build/company_oss_file_service"]
