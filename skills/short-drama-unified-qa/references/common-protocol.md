# S06 统一协议

## 目录

1. 请求门禁
2. Issue 契约
3. RepairTicket 契约
4. QA 响应契约
5. 裁决不变量

## 1. 请求门禁

正式请求必须包含 `qa_mode`、完整 `artifact`、数组 `approved_upstream`、对象 `project_constraints`、`change_set`、`previous_version` 和 `flow_control`。`flow_control` 必须携带 `production_authorization_id` 与完整当前 S01 状态包。只给 ID、摘要、截图说明、下游转述或单独工作 Skill 的产物都不足以裁决来源忠实度。

检查时把以下对象视为不可放行：

- 当前 S01 `dispatch` 不是指向 S06 的 `CALL_QA`，或模式、产物、范围不一致；
- 产物缺少 `flow_authorization_id`，或对应授权不是唯一、`CONSUMED`、与生产目标和 `artifact_full_id` 精确一致；
- 待检产物或直接上游为 `STALE`；
- 权威上游仍为 `DRAFT`、`CHECKING`、`REPAIR` 或 `HUMAN_GATE`；
- `VIDEO_PROMPT`（VISUAL_TRACK）的目标分镜图未人工 `APPROVED`，或父集合虽 `APPROVED` 但目标条目不是当前精确版本、`stale: false`；`VIDEO_PROMPT`（DIRECT_TRACK）`covered_shot_ids` 任一行非当前 `STORYBOARD_TABLE: PASS`，或跨集首段缺当前 `EPISODE_HANDOFF`；
- 当前 dispatch 未携带 S01 签发的 `requirements`（S06 裁决依据之一）；
- `project_id`、范围 ID、稳定 ID、版本或 `source_beat_ids[]` 对不上；
- 返修/更新没有上一完整版本或精确授权范围。

PLOT 的原剧本、确认决定和资产事实不是生产产物，可以没有 `PASS`，但必须带稳定来源、版本、确认状态和可定位内容。

流程授权失败统一使用规则 `FLOW-AUTH-001`，裁决 `HUMAN_GATE` 并返回 S01。QA 不为绕过流程的产物补签授权，也不继续执行模式语义检查。

## 2. Issue 契约

每个问题使用：

```yaml
issue_id: QI-STORYBOARD-TABLE-001
severity: CRITICAL | HIGH | MEDIUM | LOW
rule_id: STB-AXIS-001
issue_type: AXIS_OR_POSITION_CONTINUITY
blocking: true
artifact_path: /shot_map/4/columns/机位
scope: [SHOT-E01-S01-005]
evidence:
  expected: 女主世界左、父亲世界右；摄影机保持互动轴同侧
  actual: 05 镜把女主放到父亲右侧
  source_refs: [STORYBOARD-E01-S01-V1/SHOT-E01-S01-001..004]
owner: storyboard-table-director
repairable: true
message: 05 镜人物关系无动机反转
```

硬规则：

- `rule_id` 必须来自当前模式清单。
- `artifact_path` 使用 JSON Pointer；图像像素问题可用 `/resource#region-name`。
- `evidence` 必须同时给出预期、实际和可定位来源。无法给出预期时通常应进入 `HUMAN_GATE`。
- `owner` 指向制造错误的单元，不一定是当前待检产物的生产者。
- 所有模式清单均为放行硬检；当前版本不保留“有问题但仍 PASS”的 warning。

## 3. RepairTicket 契约

通用字段：

```yaml
ticket_id: RT-STORYBOARD-TABLE-E01-S01-005-002
qa_mode: STORYBOARD_TABLE
artifact_id: STORYBOARD-E01-S01
artifact_version: V1
full_id: STORYBOARD-E01-S01-V1
verdict: REPAIR
severity: HIGH
issue_type: AXIS_OR_POSITION_CONTINUITY
issue_ids: [QI-STORYBOARD-TABLE-001]
evidence: 05 镜与权威站位和前四镜连续性相反
repair_instruction: 仅恢复 05 镜人物世界左右与合法轴侧
locked_fields: [场景, 镜号, 景别, 秒数/s, 原始对白, 服装, 道具, 其余镜头]
repair_type: LOCAL_REPAIR
preserve_scope: 其余镜头与锁定字段全部保留
must_fix:
  - 05 镜人物世界左右与合法轴侧恢复（依据 STORYBOARD-E01-S01-V1 前四镜站位）
return_to: storyboard-table-director
max_attempts_remaining: 1
```

`repair_type`（`FULL_REDO` / `LOCAL_REPAIR` / `REINFORCE_CONSTRAINT`）、`preserve_scope`、`must_fix` 为必填；`must_fix` 逐条落到具体镜号/格号/段号并写明修正依据，优先使用 `_shared/repair-phrases.md` 登记短语，禁止"修好感觉"式写法。

按模式再提供：

| 模式 | 必需范围字段 |
|---|---|
| `PLOT` | `affected_scope[]`、`allowed_paths[]` |
| `STORYBOARD_TABLE` | `target_shot_ids[]`、`target_fields[]` |
| `STORYBOARD_PROMPT` | `target_shot_ids[]`、`allowed_paths[]` |
| `STORYBOARD_IMAGE` | `target_shot_ids[]`、`regeneration_constraints[]` |
| `VIDEO_PROMPT` | `target_segment_ids[]`、`affected_scope[]`、`allowed_changes[]` |

段级选择器 `target_segment_ids[]` 与镜级选择器并存：段间/窗口矛盾根因涉及邻居段时，两侧段号都列入。

保持这些不变量：

- 工单必须精确指向待检稳定 ID、版本和完整 ID。
- 一张工单只聚合同一镜头或同一连续范围内能共同修复的问题。
- `repair_instruction` 只描述目标结果，不重写完整产物。
- `locked_fields` 非空；未开放字段默认也视为锁定。
- `max_attempts_remaining` 在 `REPAIR` 时至少为 1；归零或同类两轮失败应裁决 `HUMAN_GATE`。
- 图像工单只给重生成约束，不声称 QA 直接修改像素。

若一个产物有多个互不相干的可修范围，把 `repair_ticket` 设为票据数组。生产单元逐票局部返修，所有票完成后用完整新版本复检同一 `qa_mode`。

## 4. QA 响应契约

```yaml
schema_version: "1.0"
qa_mode: STORYBOARD_TABLE
artifact_id: STORYBOARD-E01-S01
artifact_version: V1
full_id: STORYBOARD-E01-S01-V1
flow_authorization_id: FLOW-AUTH-PRJ001-P2-0001
verdict: REPAIR
checked_against:
  - PLOT-E01-V1
  - STORYBOARD-E01-S01-V1
  - FLOW-AUTH-PRJ001-P2-0001
issues: [<Issue>]
repair_ticket: <RepairTicket、RepairTicket 数组或 null>
grade: null
stale_downstream: []
checked_at: 2026-08-16T12:00:00+08:00
```

`grade` 仅 `STORYBOARD_IMAGE` 模式必填（`S` / `A` / `B`，见 qa-storyboard-image.md 评级表）；其余模式为 `null`。

`checked_against` 列出待检版本、实际参与裁决的精确权威版本和已核验的 `flow_authorization_id`。没有稳定 ID 的源剧本使用其来源 ID 和版本；不得只写类型名。

`stale_downstream` 只报告因上游错误或版本变化需要失效的最小选择器，例如：

```yaml
- artifact_type: STORYBOARD_PROMPT
  selector: shot_id == SHOT-E01-S01-005
```

流程管理器负责状态写回与实际失效标记，S06 不改原对象。

## 5. 裁决不变量

| 裁决 | `issues` | `repair_ticket` | 条件 |
|---|---|---|---|
| `PASS` | 空数组 | `null` | 全部硬检通过且可验证 |
| `REPAIR` | 至少一个阻断问题 | 一张或多张有效票据 | 问题可定位、可最小修复、未触发升级 |
| `HUMAN_GATE` | 至少一个阻断问题 | `null` | 需要人工裁决或不能安全自动返修 |

不要把“资料不足”伪装成可修生产错误，不要给 `HUMAN_GATE` 附自动返修票据，也不要因低严重度问题跳过硬检。
