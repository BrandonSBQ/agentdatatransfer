# 风控资料聚合服务技术方案

## 1. 定位

本服务是风控资料聚合层，不负责文件导入、解压或永久落盘。它对外暴露
HTTP 查询接口，内部调用已有 gRPC 风控数据源，并在需要时从 OSS 拉取
`FileDto.fileKey` 指向的文件内容，直接在内存中转成 base64 后返回。

目标链路：

```text
客户端提交 company_id
  -> HTTP 风控聚合接口
  -> 查询 SQLite 响应缓存
  -> 命中时读取缓存 JSON
  -> 未命中时调用内部 gRPC 或读取 mock JSON，并写入 SQLite
  -> 对 FileDto 补充 OSS 文件 base64
  -> 返回响应
```

## 2. 上游数据源

当前使用两个 proto：

- `risk_cooperation.proto`
  - `CompanyRpc.riskOnboardDetailData`
  - `CompanyRpc.riskCompanySearchData`
  - `CompanyRpc.riskIDVInfoData`
- `risk_compliance.proto`
  - `NameScreeningRpc.riskNameScreeningResult`

服务启动时通过 `COMPANY_RPC_ADDR` 和 `COMPLIANCE_RPC_ADDR` 创建 gRPC
stub。当前实现使用 insecure channel，生产环境需要接入 TLS 或服务网格侧
mTLS。

`RISK_MOCK_ENABLED=true` 时不创建也不调用 gRPC client，服务改为从
`RISK_MOCK_DIR/<endpoint_type>/<company_id>.json` 读取 mock JSON，并按
相同缓存逻辑写入 SQLite。

## 3. HTTP 接口

请求体统一支持：

```json
{
  "company_id": "849618571498754048"
}
```

兼容 camelCase：

```json
{
  "companyId": "849618571498754048"
}
```

`company_id` 必须是正整数形式的 `int64` 字符串。

### 3.1 开户风控详情

```text
POST /risk/onboard/detail
```

处理流程：

```text
company_id
  -> cache key: risk_onboard_detail
  -> 命中 SQLite 时读取缓存 JSON
  -> 未命中时 CompanyRpc.riskOnboardDetailData 或 mock JSON，并写入 SQLite
  -> 对企业资料中的 FileDto 补充 fileContentBase64
```

### 3.2 公司查册资料

```text
POST /risk/company/search
```

处理流程：

```text
company_id
  -> cache key: risk_company_search
  -> 命中 SQLite 时读取缓存 JSON
  -> 未命中时 CompanyRpc.riskCompanySearchData 或 mock JSON，并写入 SQLite
  -> 对 companySearchFile 中的 FileDto 补充 fileContentBase64
```

### 3.3 IDV 信息

```text
POST /risk/idv/info
```

处理流程：

```text
company_id
  -> cache key: risk_idv_info
  -> 命中 SQLite 时读取缓存 JSON
  -> 未命中时 CompanyRpc.riskIDVInfoData 或 mock JSON，并写入 SQLite
```

当前 IDV 响应没有文件补全逻辑。

### 3.4 Name Screening 结果

```text
POST /risk/name/screening
```

处理流程：

```text
company_id
  -> cache key: risk_name_screening
  -> 命中 SQLite 时读取缓存 JSON
  -> 未命中时 NameScreeningRpc.riskNameScreeningResult 或 mock JSON，并写入 SQLite
```

当前 name screening 响应没有文件补全逻辑。

## 4. OSS 文件补全

上游 `FileDto` 包含：

| 字段 | 说明 |
|---|---|
| `fileKey` | OSS object key |
| `fileName` | 原始文件名或业务文件名 |

服务补充返回：

| 字段 | 说明 |
|---|---|
| `fileSizeBytes` | OSS 文件大小，下载成功后记录 |
| `fileContentBase64` | 文件内容的 base64；失败或超过大小限制时为空 |
| `fileContentError` | 文件补全失败原因；成功时为空 |

OSS 规则：

- bucket 默认来自 `OSS_BUCKET`。
- `OSS_SUPPORT_CNAME=true` 时兼容前导 `/` 的 object key。
- 文件通过内存流读取并 base64 编码，不写入本地临时文件。
- `RISK_FILE_MAX_BYTES` 控制单个文件可嵌入响应的最大原始字节数，默认
  `10485760`。

大文件不适合直接塞进 JSON 响应。后续如果需要支持大文件，应改为分页、
分块响应、短期签名 URL，或由调用方明确选择需要补全的文件。

## 5. 缓存设计

MVP 使用 SQLite：

```sql
CREATE TABLE IF NOT EXISTS risk_data_cache (
  endpoint_type TEXT NOT NULL,
  company_id TEXT NOT NULL,
  response_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (endpoint_type, company_id)
);
```

缓存命中条件：

```text
存在 (endpoint_type, company_id) 对应记录
```

缓存永不过期。只要 SQLite 中存在记录，服务就直接使用缓存中的业务 JSON，
不会再次调用 gRPC 或读取 mock 数据。缓存内容是未补全 OSS 文件内容的业务
JSON，会保留 `FileDto.fileKey` 和 `fileName`，但不保存 `fileContentBase64`。
每次 HTTP 响应前都会根据缓存中的 fileKey 重新调用 OSS，并把文件内容以内存
base64 形式补到响应里。

缓存仍包含风控敏感字段。生产环境需要评估加密、脱敏、清理策略和审计要求。

## 6. 模块拆分

```text
src/
  main.cc
  grpc/
    risk_rpc_client.h
    risk_rpc_client.cc
  http/
    http_query_server.h
    http_query_server.cc
    risk_json_serializer.h
    risk_json_serializer.cc
  metadata/
    mysql_metadata_repository.h
    mysql_metadata_repository.cc
  mock/
    mock_risk_data_repository.h
    mock_risk_data_repository.cc
  oss/
    oss_client.h
    aliyun_oss_client.h
    aliyun_oss_client.cc
  util/
    base64.h
    base64.cc
    json_escape.h
    json_escape.cc
```

职责：

- `main.cc`：读取配置，组装依赖，启动 HTTP server。
- `http_query_server`：请求解析、缓存命中判断、错误响应。
- `risk_json_serializer`：protobuf 到 JSON 的业务序列化，以及 OSS 文件补全。
- `risk_rpc_client`：封装内部 gRPC 调用和 deadline。
- `mysql_metadata_repository`：缓存表初始化、读取、upsert（MySQL / Aliyun RDS）。
- `mock_risk_data_repository`：mock 模式下按 endpoint/company_id 读取本地 JSON。
- `aliyun_oss_client`：封装 Aliyun OSS SDK 和 CNAME 前导 `/` 特殊下载逻辑。

## 7. 错误处理

HTTP 层：

| 场景 | HTTP 状态 |
|---|---|
| 请求缺少 `company_id` | `400` |
| `company_id` 非法或溢出 | `400` |
| 上游 gRPC 调用失败 | `500` |
| SQLite/OSS 客户端内部异常 | `500` |

文件补全：

- 单个文件下载失败不导致整个 HTTP 请求失败。
- 对应 `FileDto` 的 `fileContentBase64` 返回空字符串。
- `fileContentError` 返回可观测错误原因。

## 8. 配置项

```text
HTTP_ADDR=127.0.0.1:8080
METADATA_DB=./data/company-files/metadata.db
RISK_FILE_MAX_BYTES=10485760
RISK_MOCK_ENABLED=false
RISK_MOCK_DIR=./mock-data
RISK_CACHE_TTL_SECONDS=300

COMPANY_RPC_ADDR=127.0.0.1:50051
COMPLIANCE_RPC_ADDR=127.0.0.1:50052

OSS_ENDPOINT=https://...
OSS_BUCKET=...
OSS_ACCESS_KEY_ID=...
OSS_ACCESS_KEY_SECRET=...
OSS_SUPPORT_CNAME=true
OSS_SECURITY_TOKEN=
```

## 9. 生产化待办

- HTTP 鉴权、TLS、调用方身份审计。
- gRPC TLS 或 mTLS。
- 使用成熟 JSON parser 替换轻量字符串解析。
- 针对响应缓存做敏感数据加密和手动清理策略。
- 给 gRPC、OSS、SQLite 增加结构化日志和指标。
- 按 endpoint 配置是否补全 OSS 文件内容。
- 大文件改为分块、分页或短期签名 URL。
- 增加单元测试和集成测试，覆盖缓存命中、OSS 失败和非法输入。
