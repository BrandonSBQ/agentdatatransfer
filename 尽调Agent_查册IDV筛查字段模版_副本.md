# 查册、IDV、name Screening 到底要拿到什么信息，作为输入项给到 agent，给出字段模版

## 一、公共字段（三个接口都有的外层）

```json
{
  "company_id": "HKL260522000105",      // 客户标识（幂等键之一）
  "result_type": "registry_search | idv | name_screening",
  "result_source": "api | manual",      // ★ 海外查册是 manual（人工结果）
  "received_at": "2026-08-18T10:00:00Z" // 业务系统回传时间
}
```

---

## 二、查册（Registry Search）字段模版

### 2.1 JSON 模版

```json
{
  "company_id": "HKL260522000105",
  "result_type": "registry_search",
  "result_source": "manual",
  "registry_type": "hong_kong_cr | bvi | cayman | singapore_acra | dnb",
  "searched_at": "2026-08-18T10:00:00Z",

  "company_status": "active | deregistered | dissolved | liquidation | struck_off",
  "company_status_effective_date": "2026-08-01",

  "registration": {
    "registration_number": "78786066",
    "incorporation_date": "2025-09-12",
    "registered_address": "UNIT 2A, 17/F GLENEALY TOWER...",
    "business_nature": "Retail trade"
  },

  "shareholders": [
    {
      "name": "MIYAYAMA, Grigory Yukio",
      "shareholder_type": "natural_person | corporate | trust",
      "percent": 30.0,
      "jurisdiction": "HK",
      "appointment_date": "2025-09-12",
      "cessation_date": null
    }
  ],

  "directors": [
    {
      "name": "MIYAYAMA, Grigory Yukio",
      "appointment_date": "2025-09-12",
      "resignation_date": null
    }
  ],

  "charges": [
    {"charge_type": "mortgage | debenture", "registered_date": "2026-01-01"}
  ],

  "insolvency": {
    "has_winding_up_petition": false,
    "has_liquidation": false,
    "details": ""
  },

  "raw_report": "人工查册报告原文/文件链接"
}
```



---

## 三、IDV（身份核验）字段模版

### 3.1 JSON 模版

```json
{
  "company_id": "HKL260522000105",
  "result_type": "idv",
  "result_source": "api",
  "idv_provider": "provider_name",
  "verified_at": "2026-08-18T10:00:00Z",

  "subjects": [
    {
      "subject_type": "customer | director | shareholder | signatory | ubo",
      "subject_name": "MIYAYAMA, Grigory Yukio",
      "status": "passed | failed",
      "fail_reason": "expired_document | photo_mismatch | number_mismatch | name_mismatch | null",

      "verified_identity": {
        "name": "MIYAYAMA, Grigory Yukio",
        "name_in_chinese": "",
        "dob": "1990-01-01",
        "nationality": "Philippines",
        "id_type": "passport | hkid | national_id",
        "id_number": "P1178244C",
        "gender": "M"
      }
    }
  ]
}
```



---

## 四、Name Screening（名单筛查）字段模版

### 4.1 JSON 模版

```json
{
  "company_id": "HKL260522000105",
  "result_type": "name_screening",
  "result_source": "api",
  "screening_provider": "dow_jones | world_check | lexisnexis",
  "screened_at": "2026-08-18T10:00:00Z",

  "hits": [
    {
      "hit_name": "MIYAYAMA, Grigory Yukio",
      "list_type": "sanctions | pep | adverse_media",
      "list_source": "OFAC | UN | UK | EU | internal",
      "list_name": "SDN | Consolidated | ...",

      "matched_fields": {
        "name": true,
        "dob": true,
        "nationality": true,
        "id_number": true,
        "gender": false
      },

      "hit_details": {
        "list_entry_name": "MIYAYAMA, Grigory Yukio",
        "list_entry_dob": "1990-01-01",
        "list_entry_nationality": "Philippines",
        "list_entry_id_number": "P1178244C"
      }
    }
  ]
}
```


## 一句话总结

三个接口的字段模版核心是：**查册返回「公司状态 + 股东持股比例 + 董事」**（判 UBO 变化）、**IDV 返回「核验对象 + 通过/失败 + 身份特征」**（判身份真实性）、**Name Screening 返回「命中名单 + 多字段匹配度」**（判真命中/误报）。所有字段都能直接映射到 38 个 facts，供规则引擎和 CRA 评分使用。
