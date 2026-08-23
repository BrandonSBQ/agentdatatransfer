# queryCorpProfile｜历史企业档案查询接口

## 接口概览

**Proto 定义：**`porto/cooperation/proto/cooperation/api/v1/api-manager.proto`

**与 queryCorpoProfile 的区别：**`queryCorpProfile` 面向已验证的版本化历史档案；`queryCorpoProfile` 查询当前最新档案并聚合钱包、当前股东、当前关键人物等实时信息。

## 方法定义

rpc queryCorpProfile\(CorpProfileManagerReq\) returns \(CorpProfileManagerResp\);

## 请求参数

**条件必填规则：**`corpId` 与 `ecirCode` 至少提供一个。若 `corpId > 0`，不会校验 `ecirCode` 是否与之匹配。

### 3\.1 version 语义

### 3\.2 请求示例

按企业 ID 查询最新已验证版本：

\{

"corpId": "10000001",

"version": 0

\}

按 ECIR Code 查询首个已验证版本：

\{

"ecirCode": "ECIR123456789",

"version": \-1

\}

查询指定版本：

\{

"corpId": "10000001",

"version": 3

\}

## 响应结构

### 4\.1 CorpProfileManagerResp

### 4\.2 data：本接口实际填充字段

**本接口不会主动填充的当前态字段：**`registeredPlace`、`registeredAddress`、`operatingPlace`、`operatingAddress`、`website`、`remark`、`reason`、`shareholders`、`boardStatus`、`bizDto`、`auditStatus`、`fiatAccount` 等。它们按 Proto 默认值返回，不应作为该接口的稳定输出使用。

### 4\.3 AMLQ 问题返回（fromAnswer）

**版本注意：**`queryCorpProfile` 的企业档案主体会按 `version` 查询，但 AMLQ 问卷只按 `corpId` 查询，不与档案版本绑定。因此 `fromAnswer` 不能用于还原某个历史版本当时的 AMLQ 快照。

|字段|类型|说明|
|---|---|---|
|`purposeOfAccountOpening`|string|开户目的；由问卷选项映射为英文标题 `titleEn`。|
|`expectedBusinessCounterparties`|string|预期交易对手方；直接返回问卷填写内容。|
|`expectedVolumeOfTransactionsPerMonth`|string|预期每月交易量；由问卷选项映射为英文标题 `titleEn`。|
|`handlesCustomerMoney`|bool|是否处理客户资金，例如货币兑换、投资管理或全权委托账户。|

**返回条件：**响应位置为 `data.fromAnswer`，类型为 `BankShareAnswer`。仅查询 `bankId = 1009` 且状态为 `FINISHED` 的回答记录；若没有符合条件的记录，服务端不会主动设置该字段。若存在多条匹配记录，当前实现使用查询结果中的第一条。

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

## 嵌套对象说明

### 5\.1 CorpoUserManagerProto

本接口主要填充 `objId`、`nameCn`、`firstName`、`lastName`、`idNumber`、`roles`。历史兼容字段 `parters` 只返回 Partner 角色的子集；调用方应优先使用 `peoples.roles`。

### 5\.2 CorpShareHolderManagerProto

`specialShareholders` 通过历史扩展股本结构递归提取，只保留金融机构、国有企业或上市公司等特殊股东，包含名称、类型、注册地、监管、上市及国有属性。该接口不填充完整的 `shareholders` 列表。

### 5\.3 CorpElaborativeManageProto

### 5\.4 CorpoFileManagerProto

当前主要填充 `fileKey`、`fileType`、`fileName`，进一步说明内的文件还可能填充 `fileFormat`。

## 响应示例

\{

"code": 0,

"msg": "Success",

"data": \{

"corpId": "10000001",

"ecirCode": "ECIR123456789",

"ciNumber": "1234567",

"brNumber": "12345678",

"companyNameEn": "Example Company Limited",

"companyNameLocal": "示例有限公司",

"incorporationPlace": "HK",

"incorporationDate": "20240101",

"bizEntityType": 1,

"quorum": 2,

"peoples": \[\],

"specialShareholders": \[\],

"entityElaboratives": \[\],

"shElaboratives": \[\],

"biz": \[\],

"files": \[\]

\}

\}

注：Proto JSON 中 `int64` 通常序列化为字符串；成功码数值仅作结构示意，实际以 `core.api.v1.StatesCode` 定义为准。

## 错误处理

## 服务端处理流程

1. 若 `corpId <= 0`，根据 `ecirCode` 反查企业 ID。

2. 根据 `version` 选择最新已验证、首个已验证或指定版本实体。

3. 按该实体版本查询实体扩展、商业活动、商业扩展及企业文件。

4. 从历史扩展 JSON 组装关键人物、特殊股东、企业/股东/商业进一步说明。

5. 合并企业文件和进一步说明引用的文件，构建 `CorpEntityManagerProto`。

6. 成功返回 `StatesCode.Success_VALUE / Success`；业务异常返回业务码；系统异常通过 gRPC Status 返回。

## 调用注意事项

- `version = 0` 指最新“已验证”版本，并不等于当前实时档案。

- `version = -1` 是首个已验证版本，不是 Proto 默认值；调用方必须显式传入。

- `fiatWalletId` 与 `dgWalletId` 在本接口中无效。

- `corpId` 与 `ecirCode` 同时传入时，以 `corpId` 为准，不做一致性校验。

- 历史档案中的注册日期必须能被解析为 `long`，否则会进入系统异常分支。

- 该接口返回的是较早的历史快照结构，完整当前态字段请使用 `queryCorpoProfile`。

## 代码依据

- `ecir/app/cooperation/src/main/java/com/rd/ecir/app/cooperation/grpc/CorpoManagerGpcService.java`

- `ecir/app/cooperation/src/main/java/group/rd/ecir/app/cooperation/handler/CorpHandler.java`

- `porto/cooperation/proto/cooperation/api/v1/api-manager.proto`

- `porto/cooperation/proto/cooperation/api/v1/api-corpo.proto`

