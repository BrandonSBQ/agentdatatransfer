-- 风控资料聚合服务 — MySQL schema（后端为 MySQL / Aliyun RDS）
--
-- 设计：每个接口的响应拆成「规范化表」存储，作为唯一可信源：
--   - 多数接口一张父表（按 company_id 或 (company_id, screening_id) 等唯一，存在且 updated_at 在 TTL 内即视为缓存命中）
--   - 重复字段（数组）落到 1:N 子表，按 seq 保持顺序
--   - 每张表统一含自增主键 id、created_at、updated_at（Unix 秒，应用层写入）
--
-- 约定：
--   - id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY；created_at/updated_at 由应用层维护。
--   - 文本字段默认 VARCHAR(512)；JSON 数组列表（如 *_list）用 TEXT。
--   - TEXT 列不带 DEFAULT（MySQL/TiDB 限制）；应用层（EncodeStringArray）总会写入合法 JSON 数组。
--   - 多列 VARCHAR(512) 的复合唯一键在 utf8mb4 下可能超过 3072 字节上限，文件表用缩短的键。
--
-- 用法：
--   A) 手动:  mysql -h <MYSQL_HOST> -P <MYSQL_PORT> -u <MYSQL_USER> -p <MYSQL_DATABASE> < schema.sql
--   B) 自动:  服务启动时 MysqlMetadataRepository::Initialize() 会以
--             CREATE TABLE IF NOT EXISTS 幂等地建一次，与本文件保持一致。
--             修改本文件时，务必同步修改 Initialize() 内的内联 DDL
--             （src/metadata/mysql_metadata_repository.cc）。
--
-- ============================================================================
-- 迁移（仅对「已存在」的库执行；全新库走上面的 CREATE TABLE 即可）
--   Initialize() 用的是 CREATE TABLE IF NOT EXISTS，表已存在时不会新增列，
--   所以给既有库加字段必须手动 ALTER，否则 INSERT 会因列不匹配而失败。
-- ============================================================================
-- 2026-06-24: risk_business_detail 新增 sub_industry（子行业）字段。
ALTER TABLE risk_business_detail
  ADD COLUMN sub_industry VARCHAR(512) NOT NULL DEFAULT '' AFTER sales_turnover_previous_year;

-- 2026-08-07: risk_entity_detail 新增 shareholder_list（股东列表）字段。
-- TEXT 列不带 DEFAULT，若表已有数据需先加 NULL 列再回填。
ALTER TABLE risk_entity_detail
  ADD COLUMN shareholder_list TEXT NULL AFTER email_address;
UPDATE risk_entity_detail SET shareholder_list = '' WHERE shareholder_list IS NULL;

-- 2026-08-07: risk_idv_info 新增 pass_status（通过状态）字段。
ALTER TABLE risk_idv_info
  ADD COLUMN pass_status BIGINT NOT NULL DEFAULT 0 AFTER hkid_earliest_issue_date;


-- ============================================================================
-- /risk/onboard/detail  (proto: RiskOnboardDetail)
--   - RiskEntityDetail: 企业主体资料（1:1）
--   - RiskAdditionalQuestion: 补充问卷（1:1），emailAddress 是 RiskOnboardDetail
--     的顶层字段，落在主体行上
-- ============================================================================

-- 企业主体资料（1:1，父表；命中标记 = 该 company_id 行存在且 updated_at 在 TTL 内未过期）
CREATE TABLE IF NOT EXISTS risk_entity_detail (
  id                                  BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id                          VARCHAR(512) NOT NULL,                   -- 企业ID（正整数字符串）
  business_english_name               VARCHAR(512) NOT NULL DEFAULT '',        -- 商业英文名
  business_chinese_name               VARCHAR(512) NOT NULL DEFAULT '',        -- 商业中文名
  register_business_number            VARCHAR(512) NOT NULL DEFAULT '',        -- 商业登记号
  place_of_incorporation              VARCHAR(512) NOT NULL DEFAULT '',        -- 注册成立地
  business_type                       VARCHAR(512) NOT NULL DEFAULT '',        -- 业务类型
  company_incorporation_date          VARCHAR(512) NOT NULL DEFAULT '',        -- 公司成立日期
  registered_country_region           VARCHAR(512) NOT NULL DEFAULT '',        -- 注册国家/地区
  registered_address                  VARCHAR(512) NOT NULL DEFAULT '',        -- 注册地址
  primary_operating_place             VARCHAR(512) NOT NULL DEFAULT '',        -- 主要经营地
  primary_operating_address           VARCHAR(512) NOT NULL DEFAULT '',        -- 主要经营地址
  is_regulated_financial_institution  BIGINT      NOT NULL DEFAULT 0,         -- 是否受监管金融机构 (0/1)
  is_listed_company                   BIGINT      NOT NULL DEFAULT 0,         -- 是否上市公司 (0/1)
  is_government_owned_enterprise      BIGINT      NOT NULL DEFAULT 0,         -- 是否政府控股企业 (0/1)
  certificate_of_incorporation_number VARCHAR(512) NOT NULL DEFAULT '',        -- 公司注册证书编号
  email_address                       VARCHAR(512) NOT NULL DEFAULT '',        -- 邮箱（RiskOnboardDetail 顶层字段）
  shareholder_list                    TEXT         NOT NULL,                  -- 股东列表（RiskOnboardDetail 顶层字段）
  created_at                          BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at                          BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_entity_company UNIQUE (company_id)
);

-- 企业主体资料中的文件引用（1:N）—— 对应 RiskEntityDetail 的 4 个 FileDto 数组
-- field_name 取值: businessRegistrationCertificate | certificateOfIncorporation
--                | memorandumAndArticlesOfAssociation | shareholderStructureDocument
CREATE TABLE IF NOT EXISTS risk_entity_detail_file (
  id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id VARCHAR(64)  NOT NULL,                   -- 企业ID
  field_name VARCHAR(512) NOT NULL,                   -- 归属的 FileDto 数组名（见上）
  file_key   VARCHAR(512) NOT NULL,                   -- OSS 文件 key
  file_name  VARCHAR(512) NOT NULL DEFAULT '',        -- 原始文件名
  created_at BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_entity_file UNIQUE (company_id, file_key)
);

-- 经营详情（1:N）
CREATE TABLE IF NOT EXISTS risk_business_detail (
  id                           BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id                   VARCHAR(512) NOT NULL,                   -- 企业ID
  seq                          BIGINT      NOT NULL,                   -- 数组下标，保持顺序
  location_of_business         VARCHAR(512) NOT NULL DEFAULT '',        -- 经营地点
  industry_details             VARCHAR(512) NOT NULL DEFAULT '',        -- 行业详情
  years_in_business            VARCHAR(512) NOT NULL DEFAULT '',        -- 经营年限
  sales_turnover_previous_year VARCHAR(512) NOT NULL DEFAULT '',        -- 上一年营业额
  sub_industry                 VARCHAR(512) NOT NULL DEFAULT '',        -- 子行业
  created_at                   BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at                   BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_business_company_seq UNIQUE (company_id, seq)
);

-- 关键人员（1:N）
CREATE TABLE IF NOT EXISTS risk_key_people (
  id                           BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id                   VARCHAR(512) NOT NULL,                   -- 企业ID
  seq                          BIGINT      NOT NULL,                   -- 数组下标，保持顺序
  last_name_in_english         VARCHAR(512) NOT NULL DEFAULT '',        -- 英文姓
  first_name_in_english        VARCHAR(512) NOT NULL DEFAULT '',        -- 英文名
  name_in_chinese              VARCHAR(512) NOT NULL DEFAULT '',        -- 中文名
  id_issuing_country_or_region VARCHAR(512) NOT NULL DEFAULT '',        -- 证件签发国家/地区
  id_type                      VARCHAR(512) NOT NULL DEFAULT '',        -- 证件类型
  id_number                    VARCHAR(512) NOT NULL DEFAULT '',        -- 证件号码
  is_director                  BIGINT      NOT NULL DEFAULT 0,         -- 是否董事 (0/1)
  is_authorized_signatory      BIGINT      NOT NULL DEFAULT 0,         -- 是否授权签字人 (0/1)
  is_ultimate_beneficial_owner BIGINT      NOT NULL DEFAULT 0,         -- 是否最终受益人 (0/1)
  actual_owned_shares          VARCHAR(512) NOT NULL DEFAULT '',        -- 实际持股
  created_at                   BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at                   BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_key_people_company_seq UNIQUE (company_id, seq)
);

-- 补充问卷（1:1）
CREATE TABLE IF NOT EXISTS risk_additional_question (
  id                                        BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id                                VARCHAR(512) NOT NULL,                   -- 企业ID
  purpose_of_account_opening                VARCHAR(512) NOT NULL DEFAULT '',        -- 开户目的
  expected_business_counterparties          VARCHAR(512) NOT NULL DEFAULT '',        -- 预期交易对手
  expected_volume_of_transactions_per_month VARCHAR(512) NOT NULL DEFAULT '',        -- 预期每月交易量
  handles_customer_money                    BIGINT      NOT NULL DEFAULT 0,         -- 是否经手客户资金 (0/1)
  created_at                                BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at                                BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_aq_company UNIQUE (company_id)
);


-- ============================================================================
-- /risk/name/screening  (proto: RiskNameScreeningResultResp -> repeated RiskNameScreeningResultInfoDto)
--   - 筛查结果 1:N（按 screening_id 区分），每条的命中明细 1:N
-- ============================================================================

-- 姓名筛查结果（1:N，父表；每个 screening_id 一行）。type 为 CoopType 枚举，按其 int 值存储。
CREATE TABLE IF NOT EXISTS risk_name_screening (
  id                  BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id          VARCHAR(512) NOT NULL,                   -- 企业ID
  screening_id        BIGINT      NOT NULL DEFAULT 0,         -- 上游筛查记录ID（proto id，int64）；与 company_id 共同唯一
  chinese_name        VARCHAR(512) NOT NULL DEFAULT '',        -- 中文名
  english_name        VARCHAR(512) NOT NULL DEFAULT '',        -- 英文名
  gender              BIGINT      NOT NULL DEFAULT 0,         -- 性别（上游 int 原值）
  date                VARCHAR(512) NOT NULL DEFAULT '',        -- 日期
  id_number           VARCHAR(512) NOT NULL DEFAULT '',        -- 证件号
  citizenship         VARCHAR(512) NOT NULL DEFAULT '',        -- 国籍
  permanent_residence VARCHAR(512) NOT NULL DEFAULT '',        -- 永久居留地
  remark              VARCHAR(512) NOT NULL DEFAULT '',        -- 备注
  type                BIGINT      NOT NULL DEFAULT 0,         -- 合作类型 CoopType 的 int 值
  result_total_count  BIGINT      NOT NULL DEFAULT 0,         -- 命中总数（result.totalCount）
  update_time         BIGINT      NOT NULL DEFAULT 0,         -- 上游更新时间（int64）
  created_at          BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at          BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_ns_company UNIQUE (company_id, screening_id)
);

-- 姓名筛查命中明细（1:N）。RiskNameScreeningResultDataDto 的 6 个 repeated string
-- 字段（date/idNumber/citizenship/permanentResidence/hitTag/address）以 JSON 数组文本存储。
CREATE TABLE IF NOT EXISTS risk_name_screening_result (
  id                       BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id               VARCHAR(512) NOT NULL,                   -- 企业ID
  screening_id             BIGINT      NOT NULL,                   -- 归属的筛查结果（risk_name_screening.screening_id）
  seq                      BIGINT      NOT NULL,                   -- 数组下标，保持顺序
  hit_id                   BIGINT      NOT NULL DEFAULT 0,         -- 命中记录ID（proto id，int64）
  chinese_name             VARCHAR(512) NOT NULL DEFAULT '',        -- 中文名
  english_name             VARCHAR(512) NOT NULL DEFAULT '',        -- 英文名
  gender                   BIGINT      NOT NULL DEFAULT 0,         -- 性别（上游 int 原值）
  date_list                TEXT         NOT NULL,      -- 日期列表（JSON 数组）
  id_number_list           TEXT         NOT NULL,      -- 证件号列表（JSON 数组）
  citizenship_list         TEXT         NOT NULL,      -- 国籍列表（JSON 数组）
  permanent_residence_list TEXT         NOT NULL,      -- 永久居留地列表（JSON 数组）
  hit_tag_list             TEXT         NOT NULL,      -- 命中标签列表（JSON 数组）
  address_list             TEXT         NOT NULL,      -- 地址列表（JSON 数组）
  hit_remark               VARCHAR(512) NOT NULL DEFAULT '',        -- 命中备注
  hit_result               VARCHAR(512) NOT NULL DEFAULT '',        -- 命中结果
  profile_id               VARCHAR(512) NOT NULL DEFAULT '',        -- 档案ID
  score                    VARCHAR(512) NOT NULL DEFAULT '',        -- 命中评分
  title                    VARCHAR(512) NOT NULL DEFAULT '',        -- 标题
  created_at               BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at               BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_nsr_company_seq UNIQUE (company_id, screening_id, seq)
);


-- ============================================================================
-- /risk/company/search  (proto: RiskCompanySearchData)
--   - 仅缓存查册文件（1:N）。无父表：文件行存在且 updated_at 在 TTL 内即缓存命中标记
--     （空文件结果不缓存，下次访问回源重取）。
-- ============================================================================

CREATE TABLE IF NOT EXISTS risk_company_search_file (
  id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id VARCHAR(64)  NOT NULL,                   -- 企业ID
  file_key   VARCHAR(512) NOT NULL,                   -- OSS 文件 key
  file_name  VARCHAR(512) NOT NULL DEFAULT '',        -- 原始文件名
  created_at BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_csf_company_key_name UNIQUE (company_id, file_key)
);


-- ============================================================================
-- /risk/idv/info  (proto: RiskIDVInfoResp)
--   - 单张 1:N 表：RiskIDVInfoResp 没有标量字段，直接把 repeated RiskIDVInfo
--     落到明细表；该 company_id 存在任意行且 updated_at 在 TTL 内即视为缓存命中。
--   - 注意：空结果不缓存（无行可作命中标记），下次访问将回源重取。
-- ============================================================================

-- IDV 条目（1:N，对应 repeated RiskIDVInfo）。单表即缓存命中标记。
CREATE TABLE IF NOT EXISTS risk_idv_info (
  id                             BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- 自增主键
  company_id                     VARCHAR(512) NOT NULL,                   -- 企业ID
  seq                            BIGINT      NOT NULL,                   -- 数组下标，保持顺序
  sub_id                         VARCHAR(512) NOT NULL DEFAULT '',        -- Sub ID
  sub_id_type                    VARCHAR(512) NOT NULL DEFAULT '',        -- Sub ID 类型
  english_first_name             VARCHAR(512) NOT NULL DEFAULT '',        -- 英文名（名）
  english_last_name              VARCHAR(512) NOT NULL DEFAULT '',        -- 英文名（姓）
  chinese_name                   VARCHAR(512) NOT NULL DEFAULT '',        -- 中文名
  gender                         VARCHAR(512) NOT NULL DEFAULT '',        -- 性别
  date_of_birth                  VARCHAR(512) NOT NULL DEFAULT '',        -- 出生日期
  id_type                        VARCHAR(512) NOT NULL DEFAULT '',        -- 证件类型
  id_number                      VARCHAR(512) NOT NULL DEFAULT '',        -- 证件号码
  id_issuing_jurisdiction        VARCHAR(512) NOT NULL DEFAULT '',        -- 证件签发地
  id_issuing_authority           VARCHAR(512) NOT NULL DEFAULT '',        -- 证件签发机关
  id_date_of_issuing             VARCHAR(512) NOT NULL DEFAULT '',        -- 证件签发日期
  id_date_of_expiry              VARCHAR(512) NOT NULL DEFAULT '',        -- 证件有效期
  hkid_symbols                   VARCHAR(512) NOT NULL DEFAULT '',        -- （仅 HKID）符号
  hkid_chinese_commercial_code   VARCHAR(512) NOT NULL DEFAULT '',        -- （仅 HKID）中文电码
  hkid_permanent_resident_status VARCHAR(512) NOT NULL DEFAULT '',        -- （仅 HKID）永久性居民身份
  hkid_earliest_issue_date       VARCHAR(512) NOT NULL DEFAULT '',        -- （仅 HKID）最早签发日期
  pass_status                    BIGINT      NOT NULL DEFAULT 0,         -- 通过状态
  created_at                     BIGINT      NOT NULL,                   -- 首次写入时间（Unix 秒）
  updated_at                     BIGINT      NOT NULL,                   -- 最近更新时间（Unix 秒）
  CONSTRAINT uniq_idv_company_seq UNIQUE (company_id, seq)
);
