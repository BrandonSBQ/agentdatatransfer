# queryBoardResolution｜授权明细列表（Mandate list）

用于查询企业授权签署明细（Mandate list），包括控制人、董事 / 合伙人 / 独资经营者以及签署详情。

## 接口信息

## 请求参数

调用方只需要传 `corpId`：

```ProtoBuf
CorpoManagerReq.newBuilder()
    .setCorpId(corpId)
    .build();
```

如果当前系统没有 `corpId`，可先调用 `cooperation.api.v1.CorpoManagerRpc.queryCorpProfile` 获取。

**注意：**`hisId` 未传时 Proto 默认值为 `0`，实现会按该值读取企业档案；`isMask` 默认是 `false`。接口仅在企业授权状态为 `POST_BOARDING` 时返回授权明细，否则 `groups` 为空字符串。

## 响应读取

`CorpoRpcServiceResp.data` 是 `google.protobuf.Any`，实际封装 `BankRespProto`。解包后读取 `BankRespProto.groups`；该字段是 JSON 字符串，反序列化后为 `CorpGroup[]`。

```Java
CorpoRpcServiceResp resp = stub.queryBoardResolution(request);
BankRespProto data = resp.getData().unpack(BankRespProto.class);
List<CorpGroup> groups = gson.fromJson(
    data.getGroups(),
    new TypeToken<List<CorpGroup>>() {}.getType()
);
```

## 按企业类型读取签署人

三个企业类型都会额外返回 `controllersSigning`（Assigned Profile Controllers）和 `details`（Signing Details）。

> **修正说明：**有限公司应读取 `directorsSigning`。原示例把有限公司 JSON 写成了 `ownersSigning`，与实际代码不一致。
> 
> 

## 签署人字段

## 响应结构示例

```JSON
[
  {
    "key": "boardResolution",
    "title": "Mandate",
    "subGroups": [
      {
        "subKey": "directorsSigning",
        "subTitle": "Directors signing mandate",
        "fields": [
          {
            "key": "475363257700478976",
            "title": "Signed director",
            "value": "邱炜斌",
            "verified": 1,
            "historyChange": 2,
            "code": ""
          }
        ]
      }
    ]
  }
]
```

## 调用注意事项

- 先判断 `resp.code`，成功时再解包 `data`。

- `groups` 是 JSON 字符串，不是 Proto 的 repeated 字段。

- 授权未完成时 `groups` 为空字符串，调用方应按“无可展示授权明细”处理，不要直接反序列化空串。

- 需要脱敏展示时可以显式传 `isMask=true`；只传 `corpId` 时默认不脱敏。

## 代码依据

- `CorpoManagerGpcService#queryBoardResolution`

- `BasicProfileService#getBoardResolution`

- `cooperation/api/v1/api-manager.proto`

- `cooperation/api/v1/corpo.proto`

