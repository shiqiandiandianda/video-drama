# PLOT 返修、更新与 QA 协议

## 目录

- [模式选择](#模式选择)
- [RepairTicket 契约](#repairticket-契约)
- [ChangeSet 契约](#changeset-契约)
- [局部修改流程](#局部修改流程)
- [锁定字段](#锁定字段)
- [版本与影响范围](#版本与影响范围)
- [QA 调用](#qa-调用)
- [失败升级](#失败升级)

## 模式选择

- 使用 `CREATE` 从原剧本产生第一版。
- 使用 `UPDATE` 应用新的已确认导演决定或上游事实变化。
- 使用 `REPAIR` 响应 `QA:PLOT` 的可定位问题。

不要用 `REPAIR` 承接新创作要求。不要用 `UPDATE` 绕过确认状态。

## RepairTicket 契约

```json
{
  "ticket_id": "RT-PLOT-E01-002",
  "qa_mode": "PLOT",
  "artifact_id": "PLOT-E01-V1",
  "verdict": "REPAIR",
  "severity": "HIGH",
  "issue_type": "DIALOGUE_MISSING",
  "evidence": "SCRIPT-E01-V1:L22 的台词未进入 BEAT-E01-S01-001",
  "repair_instruction": "补回该句原始台词及其来源覆盖",
  "affected_scope": ["BEAT-E01-S01-001"],
  "allowed_paths": [
    "/scenes/0/beats/0/dialogue",
    "/source_coverage",
    "/coverage_summary"
  ],
  "locked_fields": [
    "/scenes/0/beats/0/actions",
    "/scenes/0/beats/0/reactions",
    "/scenes/0/beats/0/end_state"
  ],
  "return_to": "script-plot-progression",
  "max_attempts_remaining": 1
}
```

要求：

- 一张票据只聚合同一受影响范围内可以共同修复的问题。
- 提供明确来源证据和最小修复指令。
- 使用 JSON Pointer 表示 `allowed_paths` 和 `locked_fields`。
- 不允许 S02 扩大票据范围。

常用 `issue_type`：

- `SCRIPT_EVENT_OMITTED`
- `DIALOGUE_MISSING`
- `DIALOGUE_CHANGED`
- `SPEAKER_MISMATCH`
- `EVENT_ORDER_CHANGED`
- `UNSUPPORTED_PLOT_ADDITION`
- `CAUSE_EFFECT_BROKEN`
- `STATE_DISCONTINUITY`
- `DECISION_OVERRIDE_INVALID`
- `BEAT_DUPLICATED`

## ChangeSet 契约

```json
{
  "change_id": "CS-PLOT-E01-003",
  "source": "HUMAN_DIRECTOR",
  "source_ref": "DEC-017",
  "status": "CONFIRMED",
  "affected_scope": ["BEAT-E01-S03-004"],
  "allowed_paths": [
    "/scenes/2/beats/3/actions",
    "/scenes/2/beats/3/end_state",
    "/decision_overrides",
    "/source_coverage"
  ],
  "locked_fields": [
    "/scenes/0",
    "/scenes/1"
  ],
  "instruction": "采用已确认决定 DEC-017，让父亲拿起通知书查看"
}
```

只有 `status: CONFIRMED` 的 ChangeSet 可以进入正式更新。

## 局部修改流程

1. 读取上一版产物。
2. 验证票据或 ChangeSet 指向当前 `full_id` 或明确的受影响版本。
3. 定位 `affected_scope`。
4. 只开放 `allowed_paths`。
5. 保留所有 `locked_fields`。
6. 应用最小变更。
7. 更新来源覆盖、决定覆盖和连续性。
8. 递增 `artifact_version` 和 `full_id`。
9. 计算最小 `impact_scope`。
10. 运行锁定字段比较脚本。
11. 请求相同 `QA:PLOT` 回归。

## 锁定字段

将未开放字段默认视为锁定。以下元数据允许随合法版本更新自动改变：

- `/artifact_version`
- `/full_id`
- `/status`
- `/impact_scope`

如果变更影响一个 BEAT 的结束状态，允许检查并修改紧邻下一 BEAT 的 `start_state`，但必须把该路径显式加入 `allowed_paths`；不要静默扩大修改。

如果最小修复无法在锁定范围内完成，返回 `HUMAN_GATE` 或请求 QA 重开票据，不要破坏锁定字段。

## 版本与影响范围

保持 `artifact_id` 不变，递增版本：

```text
PLOT-E01-V1 → PLOT-E01-V2
```

返回：

```json
{
  "impact_scope": {
    "changed_beats": ["BEAT-E01-S03-004"],
    "stale_downstream": [
      {
        "artifact_type": "STORYBOARD_ROW",
        "selector": "source_beat_ids contains BEAT-E01-S03-004"
      }
    ]
  }
}
```

S02 只报告影响范围。由流程导演或公共状态管理层实际标记下游 `STALE`。

## QA 调用

提交：

```json
{
  "qa_mode": "PLOT",
  "artifact": "PLOT-E01-V2",
  "approved_upstream": [
    "SCRIPT-E01-V1",
    "DEC-017"
  ],
  "previous_version": "PLOT-E01-V1",
  "change_set": "CS-PLOT-E01-003"
}
```

QA 必查：

- 全部剧情事件覆盖。
- 人物出场和事件顺序。
- 因果完整。
- 原始台词及说话人。
- 导演决定的确认状态和覆盖范围。
- 无依据新增内容。
- 每个 BEAT 的起止状态。
- 相邻 BEAT 连续性。
- 情绪变化证据。
- 重复、提前泄露和顺序颠倒。
- 局部修改是否污染未指定内容。

## 失败升级

- QA `PASS`：由流程导演推进 S03；S02 不自行推进。
- QA `REPAIR`：按票据局部修改并重检。
- QA `HUMAN_GATE`：停止受影响范围。
- 同一 `issue_type` 在同一范围连续两轮仍失败：升级 `HUMAN_GATE`。
- 来源无法验证或修复必须改动锁定字段：升级 `HUMAN_GATE`。

提出确认问题时，包含冲突来源、受影响范围和互斥选项；不要提出泛泛的创作问题。
