# KYB 页面字段结构整理汇总 (Entity Field Structure)

本文档整理了 KYB 审核系统页面中 **Entity details**、**Business details**、**Authorizations & controller** 以及 **Shareholding Structure** 四个核心模块（Basic profile 标签页）的全部字段名称。

---

## 1. Entity details (主体详细信息)

### 1.1 基本信息 (Basic Information)
* `Name of business/corporation in English` — 企业英文名称
* `Name of business/corporation in Chinese` — 企业中文名称
* `Business entity type` — 业务实体类型
* `Certificate of Incorporation number` — 公司注册证书编号
* `Business registration number` — 商业登记证号码
* `Date of incorporation/establishment` — 成立/注册日期
* `Place of incorporation` — 注册地
* `Registration place` — 登记地点
* `Active status` — 运营状态
* `Registered address` — 注册地址
* `Primary operating address` — 主要经营地址
* `Business website` — 企业官网地址

### 1.2 金融监管信息 (Financial Regulation)
* `Is it a regulated organisation?` — 是否为受监管机构
* `Place of financial regulatory authority` — 金融监管机构所在地
* `Name of regulator` — 监管机构名称
* `Type of license` — 牌照类型

### 1.3 上市信息 (Listing Information)
* `Is it a listed business?` — 是否为上市公司
* `Place of listing` — 上市地点
* `Name of exchange` — 交易所名称
* `Stock code` — 股票代码

### 1.4 国有背景及其他 (Government Ownership & Other)
* `Is it a government-owned business?` — 是否为国有企业
* `Place of government owner` — 国有所有者所在地
* `Invite code` — 邀请码

---

## 2. Business details (业务详细信息)

### 2.1 行业分类与运营 (Industry - 1)
* `Main category` — 主行业分类
* `Sub-category` — 子行业分类
* `Industry details` — 行业补充说明/详细描述
* `Year(s) in business` — 经营年限
* `Location(s) of business` — 业务开展地区/国家
* `Sales turnover of last year` — 去年营业额

---

## 3. Authorizations & controller (授权与控制人)

### 3.1 概览统计字段 (Overview / Counts)
* `Quorum` — 法定人数/最低签决人数
* `Number of directors (actual)` — 实际董事人数
* `Number of directors (customer declared)` — 客户申报董事人数
* `Number of UBOs` — 最终受益人 (UBO) 人数
* `Number of profile controllers` — 档案控制人人数

### 3.2 授权规范 (Mandate)
* **Assigned Profile Controllers (指定档案控制人)**
  * `Profile controller` — 档案控制人
* **Directors signing mandate (董事签署授权)**
  * `Signed director` — 签署董事
* **Signing Details (签署详情)**
  * `No. of quorum at the time of sign` — 签署时的法定人数
  * `Date when quorum was met` — 满足法定人数的日期
  * `Agreement file` — 协议文件

### 3.3 关键人员关联状态 (Key people association binding status)
* `Linked to business` — 已关联至企业的人员
* `Not yet linked to business` — 尚未关联至企业的人员
* `Not needed to link` — 无需关联的人员

---

## 4. Shareholding Structure (股权结构)

### 4.1 股权与受益人分类 (Shareholding & Control Categories)
* `Shareholder` — 股东
* `UBO` — 最终受益人 (Ultimate Beneficial Owner)

---

## 统计汇总

| 模块名称 (Module) | 包含子区域/分类 | 字段数量 (Field Count) |
| :--- | :--- | :---: |
| **Entity details** | Basic Info, Financial Regulation, Listing Info, Government Ownership | 23 |
| **Business details** | Industry - 1 | 6 |
| **Authorizations & controller** | Overview, Mandate, Key People Binding Status | 11 |
| **Shareholding Structure** | Shareholder, UBO Categories | 2 |
| **总计** | — | **42** |
