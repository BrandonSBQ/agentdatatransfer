# queryCorpoProfile｜最新企业档案查询接口

## 接口概览

**Proto 定义：**`porto/cooperation/proto/cooperation/api/v1/api-manager.proto`

**实现说明：**本接口读取当前数据表中的最新企业档案。请求中的 `version` 字段不会参与查询；需要按历史版本查询时，请使用 `queryCorpProfile`。

## 方法定义

rpc queryCorpoProfile\(CorpProfileManagerReq\) returns \(CorpProfileManagerResp\);

## 请求参数

**条件必填规则：**`dgWalletId`、`fiatWalletId`、`ecirCode`、`corpId` 至少提供一个。

### 3\.1 企业定位优先级

1. `dgWalletId`

2. `fiatWalletId`

3. `ecirCode`

4. `corpId`

若同时传多个字段，只按上述优先级最高的字段定位企业，其余字段不会做一致性校验。调用方应避免混传互相冲突的标识。

### 3\.2 请求示例（Proto JSON 示意）

\{

"ecirCode": "ECIR123456789",

"version": 0

\}

\{

"fiatWalletId": "FW123456789"

\}

## 响应结构

### 4\.1 响应包络 CorpProfileManagerResp

### 4\.2 data：企业档案字段

**Proto 中存在但本实现未主动赋值的兼容字段：**`userId`、`brKey`、`ciKey`、`logoUrl`、`isSameAddress`、`isProfileCtrl`、`isDirector`、`isUbo`、`status`、`number`、`elaborativeDescription`、`ip`、`userAgent`、`blNumber`、`registeredCapital`、`active`、`chnRegisteredAddressEn`。这些字段按 Proto 默认值返回，调用方不应依赖。

### 4\.3 AMLQ 问题返回（fromAnswer）

两个企业档案接口均会尝试返回 AMLQ 问卷结果。响应位置为 `data.fromAnswer`，Proto 类型为 `BankShareAnswer`。

|字段|类型|说明|
|---|---|---|
|`purposeOfAccountOpening`|string|开户目的；由问卷选项映射为英文标题 `titleEn`。|
|`expectedBusinessCounterparties`|string|预期交易对手方；直接返回问卷填写内容。|
|`expectedVolumeOfTransactionsPerMonth`|string|预期每月交易量；由问卷选项映射为英文标题 `titleEn`。|
|`handlesCustomerMoney`|bool|是否处理客户资金，例如货币兑换、投资管理或全权委托账户。|

**返回条件：**仅查询 `bankId = 1009` 且状态为 `FINISHED` 的回答记录；若没有符合条件的记录，服务端不会主动设置 `fromAnswer`。若存在多条匹配记录，当前实现使用查询结果中的第一条。

```json
{
  "data": {
    "fromAnswer": {
      "purposeOfAccountOpening": "Business operations",
      "expectedBusinessCounterparties": "Suppliers and customers",
      "expectedVolumeOfTransactionsPerMonth": "HKD 1,000,000 - 5,000,000",
      "handlesCustomerMoney": false
    }
  }
}
```

## 嵌套对象

### 5\.1 FiatAccountProto

### 5\.2 CorpBizDtoManageProto

### 5\.3 CorpoUserManagerProto（关键人物）

### 5\.4 CorpShareHolderManagerProto（股东）

### 5\.5 CorpElaborativeManageProto（进一步说明）

### 5\.6 CorpoFileManagerProto（文件）

字段包括：`corpId`、`userId`、`fileName`、`fileType`、`fileFormat`、`filePath`、`fileDesc`、`fileId`、`fileUrl`、`fileKey`、`objId`。当前接口主要填充 `fileKey`、`fileType`、`fileName`；进一步说明中的文件也按该对象返回。

## 响应示例（Proto JSON 示意）

\{

"code": 0,

"msg": "Success",

"data": \{

"corpId": "10000001",

"ecirCode": "ECIR123456789",

"companyNameEn": "Example Company Limited",

"companyNameLocal": "示例有限公司",

"ciNumber": "1234567",

"brNumber": "12345678",

"incorporationPlace": "HK",

"bizEntityType": 1,

"registeredPlace": "HK",

"registeredAddress": "Hong Kong",

"operatingPlace": "HK",

"operatingAddress": "Hong Kong",

"quorum": 2,

"directorNum": 2,

"boardStatus": 1,

"auditStatus": 1,

"peoples": \[\],

"shareholders": \[\],

"specialShareholders": \[\],

"entityElaboratives": \[\],

"shElaboratives": \[\],

"biz": \[\],

"bizDto": \[\],

"files": \[\],

"fiatAccount": \[\]

\}

\}

注：Proto JSON 中 `int64` 通常序列化为字符串；示例中的成功码数值仅作结构示意，实际以 `core.api.v1.StatesCode` 定义为准。

## 错误处理

## 服务端处理流程

1. 按定位优先级解析 `corpId`，并尝试查询首个法币账户。

2. 查询当前企业实体；不存在时抛出 `QUERY_NOT_FIND`。

3. 并行/顺序聚合企业基础信息、商业活动、关键人物、邀请信息、董事会决议、股东、文件、进一步说明、IDV 状态及高风险标识。

4. 组装 `CorpEntityManagerProto`。

5. 成功返回 `StatesCode.Success_VALUE / Success`；业务异常返回业务码；系统异常通过 gRPC Status 返回。

## 调用注意事项

- 该接口返回信息范围较大，服务端注释标明为“最新企业档案”；调用方应避免高频轮询。

- `version` 不生效，不要用它请求历史版本。

- `parters` 已废弃，请使用 `peoples.roles` 做角色过滤。

- 多个定位字段同时传入时不会校验一致性；建议每次只传一种标识。

- 数字资产钱包仅用于定位企业；当前 Proto 未返回 `dgAccount`。

- 列表字段为空时按 Proto 语义返回空列表；未主动赋值的标量字段为默认值。

## 代码依据

- `ecir/app/cooperation/src/main/java/com/rd/ecir/app/cooperation/grpc/CorpoManagerGpcService.java`

- `ecir/app/cooperation/src/main/java/group/rd/ecir/app/cooperation/handler/CorpHandler.java`

- `porto/cooperation/proto/cooperation/api/v1/api-manager.proto`

- `porto/cooperation/proto/cooperation/api/v1/api-corpo.proto`

