# 风控资料聚合服务

这是一个基于 C++ 开发的 HTTP 服务，用于聚合内部风控 gRPC 服务返回的数据，并对返回结果中的 OSS 文件引用进行二次富化：

- 从 OSS 下载文件内容
- 将文件内容转为 Base64
- 内嵌到 HTTP 返回结果中
- 使用 MySQL 缓存部分查询结果，降低重复调用成本

该服务本质上是一个面向风控尽调场景的聚合层，不负责文件导入、解压、落盘归档，只在请求期间按需拉取 OSS 内容并回填到响应中。

## 功能概览

当前已实现：

- HTTP `POST /risk/onboard/detail`
- HTTP `POST /risk/company/search`
- HTTP `POST /risk/idv/info`
- HTTP `POST /risk/name/screening`
- `risk_cooperation.proto` 中 `CompanyRpc` 的 gRPC 调用
- `risk_compliance.proto` 中 `NameScreeningRpc` 的 gRPC 调用
- 针对 `FileDto.fileKey` 的阿里云 OSS 文件下载与 Base64 富化
- 对 CNAME / 自定义域名场景的支持，包括以 `/` 开头的 OSS Key
- 基于 `(endpoint_type, company_id)` 的 MySQL 缓存
- Mock 模式，可直接从本地 JSON 返回而不访问 gRPC
- 基于 `spdlog` 的统一日志输出

当前未实现：

- `ImportCompanyFiles`
- 压缩包解压
- 公司文件永久落盘路径管理
- HTTP `/company/files/query`
- HTTP `/import/task/query`

## 项目结构

```text
.
├── src/
│   ├── grpc/        # gRPC 客户端
│   ├── http/        # HTTP 路由与 JSON 序列化
│   ├── metadata/    # MySQL 元数据与缓存
│   ├── mock/        # Mock 数据读取
│   ├── oss/         # 阿里云 OSS 封装
│   ├── util/        # Base64、JSON 转义、日志等工具
│   └── 3rd/         # 仓内第三方源码（如 spdlog、cpp-httplib）
├── mock-data/       # Mock 测试数据
├── schema.sql       # MySQL 表结构（启动时自动建表）
├── test.http        # VS Code / REST Client 调试文件
├── Dockerfile
└── Makefile
```

## 构建说明

### 本地依赖

macOS 下可先安装以下依赖：

```bash
brew install cmake protobuf grpc mysql-client curl openssl
```

说明：

- 项目使用 CMake 构建
- `spdlog` 和 `cpp-httplib` 走仓内源码
- 阿里云 OSS SDK 如果 `src/3rd/aliyun-oss-cpp-sdk` 不存在，CMake 会尝试自动拉取

### 本地编译

```bash
make
```

或分步执行：

```bash
make configure
make build
```

默认构建目录为 `build/`。

### 直接使用 CMake 编译

如果你不想通过 `Makefile`，也可以直接使用 CMake 进行配置和编译。

示例：

```bash
cmake -S . -B build-local -DCMAKE_PREFIX_PATH='/opt/homebrew;/opt/homebrew/opt/libarchive'
cmake --build build-local -j4
```

说明：

- `-S .` 表示源码目录为当前目录
- `-B build-local` 表示构建输出目录为 `build-local/`
- `CMAKE_PREFIX_PATH` 用于在 macOS / Homebrew 环境下帮助 CMake 找到依赖
- 编译成功后可执行文件默认位于 `build-local/company_oss_file_service`

### 初始化 MySQL

服务启动时会通过 `Initialize()` 自动创建所需的表（DDL 与 `schema.sql` 一致），因此通常无需手动建表。

如需预先在 MySQL/TiDB 上建表，可手动执行：

```bash
mysql -h <MYSQL_HOST> -P <MYSQL_PORT> -u <MYSQL_USER> -p <MYSQL_DATABASE> < schema.sql
```

## 配置说明

项目支持通过 `.env` 文件加载配置，建议直接从 `.env.example` 复制：

```bash
cp .env.example .env
```

默认配置如下：

```text
HTTP_ADDR=127.0.0.1:8080
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=riskcontrol
MYSQL_PASSWORD=
MYSQL_DATABASE=riskcontrol
MYSQL_CHARSET=utf8mb4
MYSQL_SSL=true
RISK_FILE_MAX_BYTES=10485760
RISK_MOCK_ENABLED=false
RISK_MOCK_DIR=./mock-data
RISK_CACHE_TTL_SECONDS=300

COMPANY_RPC_ADDR=127.0.0.1:50051
COMPLIANCE_RPC_ADDR=127.0.0.1:50052

OSS_BUCKET=
OSS_ACCESS_KEY_ID=
OSS_ACCESS_KEY_SECRET=
OSS_ENDPOINT=
OSS_SUPPORT_CNAME=true
OSS_SECURITY_TOKEN=

LOG_LEVEL=info
```

关键配置说明：

- `HTTP_ADDR`：HTTP 服务监听地址
- `MYSQL_HOST` / `MYSQL_PORT`：MySQL 连接地址与端口
- `MYSQL_USER` / `MYSQL_PASSWORD` / `MYSQL_DATABASE`：账号、密码与库名
- `MYSQL_CHARSET`：连接字符集，默认 `utf8mb4`
- `MYSQL_SSL`：是否启用 TLS，默认 `true`（阿里云 RDS 建议开启）
- `RISK_FILE_MAX_BYTES`：单个文件允许回填的最大字节数，超限则不返回 Base64
- `RISK_MOCK_ENABLED`：是否开启 Mock 模式
- `RISK_MOCK_DIR`：Mock 数据目录
- `RISK_CACHE_TTL_SECONDS`：风控查询结果缓存 TTL（秒），按各接口标记表的 `updated_at` 判断是否过期；超时后回源刷新并更新 `updated_at`。默认 `300`（5 分钟），`0` 表示每次回源
- `COMPANY_RPC_ADDR`：公司侧风控 gRPC 服务地址
- `COMPLIANCE_RPC_ADDR`：合规侧风控 gRPC 服务地址
- `OSS_BUCKET`：默认 OSS Bucket
- `OSS_*`：阿里云 OSS 访问参数
- `LOG_LEVEL`：日志级别，支持 `trace`、`debug`、`info`、`warn`、`error`、`critical`、`off`

## 启动方式

### 本地启动

```bash
make run
```

`Makefile` 会自动读取 `.env` 并启动服务。

### Docker 构建

```bash
docker build -t agentdatatransfer:test .
```

### Docker 运行

```bash
docker run --rm \
  --env-file .env \
  -p 8080:8080 \
  agentdatatransfer:test
```

如果容器内需要访问本地数据库或其他文件，请额外挂载对应目录。

## HTTP 接口示例

所有接口都接受 `company_id` 或 `companyId`，其值必须是正整数形式的字符串。

### 1. 风控开户详情

```bash
curl -sS -X POST http://127.0.0.1:8080/risk/onboard/detail \
  -H 'Content-Type: application/json' \
  -d '{"company_id":"849618571498754048"}'
```

### 2. 企业搜索信息

```bash
curl -sS -X POST http://127.0.0.1:8080/risk/company/search \
  -H 'Content-Type: application/json' \
  -d '{"company_id":"849618571498754048"}'
```

### 3. IDV 信息

```bash
curl -sS -X POST http://127.0.0.1:8080/risk/idv/info \
  -H 'Content-Type: application/json' \
  -d '{"company_id":"849618571498754048"}'
```

### 4. 名称筛查

```bash
curl -sS -X POST http://127.0.0.1:8080/risk/name/screening \
  -H 'Content-Type: application/json' \
  -d '{"company_id":"849618571498754048"}'
```

## 在 VS Code 中调试

仓库中的 `test.http` 已经包含了四个接口的请求示例。

如果你在 VS Code 中安装了 `REST Client` 插件（`humao.rest-client`），可以直接：

1. 打开 `test.http`
2. 点击每个 `###` 块上方的 `Send Request`
3. 直接查看接口响应

示例变量如下：

```text
@host = http://127.0.0.1:8080
@cid  = 849618571498754048
```

如果你需要重新验证最新的 Mock 数据，建议先清空 MySQL 中的缓存表（启动时会按 `schema.sql` 自动补建）：

```bash
mysql -h <MYSQL_HOST> -u <MYSQL_USER> -p <MYSQL_DATABASE> \
  -e "DROP TABLE IF EXISTS risk_entity_detail, risk_entity_detail_file, risk_business_detail, risk_key_people, risk_additional_question, risk_name_screening, risk_name_screening_result, risk_company_search_file, risk_idv_info;"
```

否则接口可能直接返回 MySQL 中缓存的历史结果。

## 文件富化说明

当 gRPC 返回结构中包含类似 `FileDto` 的文件字段时，服务会返回如下扩展字段：

```json
{
  "fileKey": "/849618571498754048/corporate/file.pdf",
  "fileName": "file.pdf",
  "fileSizeBytes": 12345,
  "fileContentBase64": "...",
  "fileContentError": ""
}
```

处理规则如下：

- `fileContentBase64`：文件内容的 Base64 编码
- `fileContentError`：下载或校验失败时的错误信息
- 如果文件大小超过 `RISK_FILE_MAX_BYTES`，不会进行 Base64 回填
- 如果 OSS 下载失败，接口仍会返回业务数据，但对应文件字段会带上错误原因

## Mock 模式

当 `RISK_MOCK_ENABLED=true` 时：

- 不会创建 gRPC 客户端
- 不会访问真实下游服务
- 会从本地 JSON 文件读取响应内容

Mock 文件路径格式为：

```text
${RISK_MOCK_DIR}/${endpoint_type}/${company_id}.json
```

例如：

```text
mock-data/risk_onboard_detail/849618571498754048.json
```

Mock 返回的数据仍会走同样的缓存与 OSS 富化流程，因此更贴近真实调用链路。

## 日志说明

项目已接入统一日志封装，默认输出到标准错误流。

常见日志内容包括：

- 服务启动参数
- HTTP 请求处理开始与结束
- gRPC 调用成功与失败
- 参数错误与运行时异常

可以通过环境变量控制日志级别：

```bash
export LOG_LEVEL=debug
```

## 常见问题

### 1. 启动时报缺少环境变量

如果提示缺少 `OSS_ACCESS_KEY_ID`、`OSS_ACCESS_KEY_SECRET`、`OSS_ENDPOINT` 等变量，请先补全 `.env`。

### 2. Mock 模式为什么还要配置 OSS

因为 Mock 只替代了 gRPC 返回，不替代 OSS 文件下载逻辑。只要返回 JSON 中仍然包含 `fileKey`，服务就会尝试去 OSS 拉取文件。

### 3. 为什么修改了 Mock 数据但接口结果没变

大概率是命中了 MySQL 缓存。按上文清空缓存表后重启即可。

### 4. Docker 构建失败怎么办

优先检查以下几项：

- 基础镜像是否可拉取
- Docker Hub 或内网镜像仓库认证是否有效
- 构建时是否允许访问外网，以便自动拉取阿里云 OSS SDK

## 后续可扩展方向

- 增加接口级单元测试或集成测试
- 为 OSS / gRPC 调用补充超时与重试策略
- 支持更细粒度的缓存策略和失效控制
- 增加健康检查、版本信息和监控指标接口
