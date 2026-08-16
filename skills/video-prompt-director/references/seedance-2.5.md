# Seedance 2.5 路由与正文规则

## 目录

1. 项目锁定配置
2. 时长与字符限制
3. 素材槽位
4. 正文与任务边界
5. 禁止降级伪装

## 1. 项目锁定配置

本仓库按当前项目要求内置 Seedance 2.5 的最小可执行配置，只覆盖“全能参考/多模态参考生成单段视频 Prompt”：

```yaml
rule_id: SD25-PROJECT-V1
model: seedance-2.5
status: VERIFIED
source: CURRENT_PROJECT_REQUIREMENT
supported_product_flows:
  - OMNI_REFERENCE
supported_generation_tasks:
  - MULTIMODAL_REFERENCE
slot_syntax: "{{Mixed x}}"
target_duration_seconds: 30
body_char_limit: 5000
```

`EDIT_VIDEO`、`EXTEND_FORWARD`、`EXTEND_BACKWARD` 和 `COMPOSITE` 不在此最小配置内。调用这些任务时仍须提供覆盖对应能力、产品模式和准确句式的外部 `VERIFIED` 配置；不得从 2.0 推断。

## 2. 时长与字符限制

- `task.model` 固定为 `seedance-2.5`。
- `task.target_duration_seconds` 固定为 `30`，正文时间轴从 0 开始、连续无缝并准确结束在 30 秒。
- `body_char_count <= 5000`。
- 一份 `VideoPromptSpec` 只对应一个 `shot_id` 和一套连续时间轴。
- APPROVED 分镜、PASS 上游、对白保真、计划镜尾、相邻 Prompt 双向连续性和独立 QA 等公共协议继续有效。

5000 字计数口径：只统计 `body`，先把行尾归一化为 LF，再按 Unicode code point 计数；包含标点、空格和换行，不包含宿主展示添加的 Markdown 代码围栏。

正文超过 5000 时先删除规则解释和重复描述；若仍超限且删除会损失锁定内容，返回 S03 重新分段，不删剧情或台词。

## 3. 素材槽位

每条 2.5 Prompt 都必须在首段列出本镜需要的 `{{Mixed x}}`：

1. 根据已确认人物、场景、关键道具、怪物/能量体和分镜/连续性锚点判断必要资产。
2. 每个独立语义对象占一个槽，同一对象不重复占槽，不一槽多物。
3. 从 `{{Mixed 1}}` 开始连续自增，不留空号；正文编号与 `reference_bindings` 完全一致。
4. 调用方已提供资产时写 `slot_source: INPUT_LEDGER`、`availability: PROVIDED`。
5. 调用方未提供资产时仍写槽位，使用 `slot_source: AUTO_PLANNED`、`availability: REQUIRED_NOT_PROVIDED`，并让 `asset_id`/版本保持空值。
6. 自动槽位只是上传计划，不得伪称资产已经存在，也不得借槽位新增剧情对象。

示例：

```text
参考图素材说明：女主{{Mixed 1}}，追兵{{Mixed 2}}，雨夜巷口{{Mixed 3}}，铜钥匙{{Mixed 4}}。
```

## 4. 正文与任务边界

正文沿用公共五段顺序：素材说明；自包含 0 秒状态与计划停点；0–30 秒连续时间轴；摄影光学与光色材质；声音、连续性和稳定性。动作、对白、物理、表演、光学和光影遵守公共 reference，不因 30 秒而增加未确认剧情或切镜。

30 秒内容不足时，只展开已存在事件的准备、惯性、反应、呼吸、环境反馈和回稳；禁止重复动作、无动机慢推或静止填时。内容超载时返回 S03 重新分段。

批量交付前运行 `validate_prompt_sequence.ps1`，确认每个中间段的 incoming/outgoing 均为 `PASS`，相邻 handoff 签名一致且没有 mismatch。

## 5. 禁止降级伪装

- 不把 2.0 的 15 秒时长套给 2.5。
- 不把本最小配置用于编辑、延长或组合任务。
- 不仅凭 `<=5000` 就忽略 30 秒、槽位或连续性规则。
- 不用搜索到的未验证帖子、旧截图或模型推断扩展支持范围。
- 不省略 Mixed 槽位，不使用 `@`、`{{Image x}}`、空号或未登记编号。
