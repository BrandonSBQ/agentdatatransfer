# queryShareHolderStructure｜股东/UBO 实体类型名称（Type Text）

用于获取股东和 UBO 列表，并根据返回字段生成实体类型名称（Type Text）。调用分两步：先取得最新历史记录的 `objId`，再把它作为 `hisId` 查询股东结构。

## 调用流程

1. 使用 `corpId` 调用 `cooperation.api.v1.CorpoManagerRpc.queryProfileHistories`。

2. 从响应的 `histories` 中选取 `objId` 最大的一项。

3. 把该最大 `objId` 作为 `CorpoManagerShareHolderReq.hisId`，同时传入原始 `corpId`。

4. 调用 `cooperation.api.v1.CorpoManagerRpc.queryShareHolderStructure`，分别读取 `shareholders` 和 `ubos`。

## 第一步：查询历史版本

```Java
CorpoManagerReq historyReq = CorpoManagerReq.newBuilder()
    .setCorpId(corpId)
    .build();

CorpoRpcServiceResp historyResp = stub.queryProfileHistories(historyReq);
CorpHistoriesList historyData = historyResp.getData().unpack(CorpHistoriesList.class);

long hisId = historyData.getHistoriesList().stream()
    .mapToLong(CorpHistoriesProto::getObjId)
    .max()
    .orElseThrow(() -> new IllegalStateException("企业没有历史档案"));
```

> **字段映射：**`CorpHistoriesProto.objId` → 下一步请求的 `CorpoManagerShareHolderReq.hisId`。这里不是传 `version`，也不是传企业 `corpId`。
> 
> 

## 第二步：查询股东 / UBO 结构

```Java
CorpoManagerShareHolderReq structureReq = CorpoManagerShareHolderReq.newBuilder()
    .setCorpId(corpId)
    .setHisId(hisId)
    .build();

CorpoManagerSHStuctureResp structure =
    stub.queryShareHolderStructure(structureReq);

List<StockStructureProto> shareholders = structure.getShareholdersList();
List<StockStructureProto> ubos = structure.getUbosList();
```

## Type Text 生成规则

接口不会直接返回名为 `typeText` 的字段。调用方应根据 `StockStructureProto.type` 映射：

```Java
String typeText = switch (item.getType()) {
    case 1 -> "Individual";
    case 2 -> "Non-individual";
    default -> "";
};
```

`shareholderType` 是另一个字段，Proto 注释为股票类型（1 Natural Person、2 Body Corporate）。当前需求的股东 / UBO 实体类型名称，应优先依据 `type` 字段。

## 响应结构

历史查询只处理 `level == 1` 的记录，并按服务端 UBO 规则拆分到两个集合。子层级数据仍可通过每项的 `subList` 继续读取。

## 完整示例

```JSON
{
  "shareholders": [
    {
      "objId": "475363257700478976",
      "type": 2,
      "lastNameEn": "Example Holdings Limited",
      "nameCn": "示例控股有限公司",
      "level": 1,
      "bizEntityType": 1
    }
  ],
  "ubos": [
    {
      "objId": "475363257700478977",
      "type": 1,
      "firstNameEn": "Wei Bin",
      "lastNameEn": "Qiu",
      "nameCn": "邱炜斌",
      "level": 1
    }
  ]
}
```

## 调用注意事项

- `queryProfileHistories` 的响应需先从 `Any` 解包为 `CorpHistoriesList`。

- 历史列表为空时不要继续调用股东结构接口，应返回“企业没有历史档案”。

- `hisId == 1` 在实现中代表查询最新股权结构；按本需求应使用历史列表最大 `objId`，从历史快照读取。

- `queryShareHolderStructure` 失败时使用 gRPC Status 返回错误，不是统一的业务响应包装。

- 不要用 `bizEntityType` 替代 `type`：前者表示公司商业实体类型（有限公司、合伙、独资等），后者才区分个人与非个人股东。

## 代码依据

- `CorpoManagerGpcService#queryProfileHistories`

- `CorpoManagerGpcService#queryShareHolderStructure`

- `CorpHistoriesService#getCorpHistoryVersionList`

- `CorpHistoriesService#getShareHolderStructure`

- `cooperation/api/v1/api-manager.proto`

- `cooperation/api/v1/api-corpo.proto`

