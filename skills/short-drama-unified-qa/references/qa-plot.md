# QA:PLOT 检查清单

## 依据与对象

检查完整 `PlotProgressionSpec`，逐项对照原剧本、确认导演决定、人物关系、场景事实和资产约束。需要字段细节时读取 `../script-plot-progression/references/plot-progression-schema.md`。

## 硬检

| 规则 ID | 检查 | 典型 `issue_type` | 默认所有者 |
|---|---|---|---|
| `PLOT-GATE-001` | 待检对象类型、ID、版本和状态有效；S02 产物不含 `shot_id` | `ARTIFACT_CONTRACT_INVALID` | `script-plot-progression` |
| `PLOT-SOURCE-001` | 每个事件、对白、确认覆盖决定均可定位到精确来源 | `SOURCE_TRACE_MISSING` | `script-plot-progression` |
| `PLOT-COVERAGE-001` | 原剧本事件全部进入 `source_coverage` 且正式放行项均为 `FULL` | `SCRIPT_EVENT_OMITTED` | `script-plot-progression` |
| `PLOT-COVERAGE-002` | 覆盖计数与实际 coverage 项一致，不能靠漏记降低分母 | `COVERAGE_COUNT_MISMATCH` | `script-plot-progression` |
| `PLOT-DIALOGUE-001` | 台词逐字保留，标点与称呼不被擅自规范化 | `DIALOGUE_CHANGED` | `script-plot-progression` |
| `PLOT-DIALOGUE-002` | 说话人、台词顺序和来源范围正确 | `SPEAKER_OR_ORDER_MISMATCH` | `script-plot-progression` |
| `PLOT-ORDER-001` | 场次、人物出场、事件和 BEAT 顺序符合权威来源 | `EVENT_ORDER_CHANGED` | `script-plot-progression` |
| `PLOT-CAUSAL-001` | 触发、行动、反应和结果构成完整因果；无跳步 | `CAUSE_EFFECT_BROKEN` | `script-plot-progression` |
| `PLOT-STATE-001` | 每个 BEAT 同时有起始、触发、结束和连续性对象 | `BEAT_STATE_INCOMPLETE` | `script-plot-progression` |
| `PLOT-STATE-002` | 前一 BEAT 结束可接入下一 BEAT 起始；人物、道具、环境、认知不漂移 | `STATE_DISCONTINUITY` | `script-plot-progression` |
| `PLOT-EMOTION-001` | 情绪变化由具体事件/动作和来源证据支撑 | `EMOTION_UNSUPPORTED` | `script-plot-progression` |
| `PLOT-DECISION-001` | 只有明确 `CONFIRMED` 的导演决定覆盖剧本，且覆盖范围不扩大 | `DECISION_OVERRIDE_INVALID` | `script-plot-progression` |
| `PLOT-ADDITION-001` | 无无依据的新剧情、人物、动作、动机、台词或结果 | `UNSUPPORTED_PLOT_ADDITION` | `script-plot-progression` |
| `PLOT-DUPLICATE-001` | 无剧情重复、提前泄露或同一事件在多个 BEAT 无理由重演 | `BEAT_DUPLICATED` | `script-plot-progression` |
| `PLOT-CONFLICT-001` | 未解决来源冲突和阻断 unknown 与 `HUMAN_GATE` 状态一致 | `UNRESOLVED_SOURCE_CONFLICT` | 人工导演 |
| `PLOT-REGRESSION-001` | 局部修改只影响授权路径，未污染其余剧情与覆盖 | `LOCKED_FIELD_CHANGED` | `script-plot-progression` |

## 裁决提示

- 可从明确原文恢复的遗漏、错序、错说话人、覆盖错误和状态断裂：`REPAIR`，返回 S02。
- 两个确认来源互斥、剧本缺页或导演决定确认状态不明：`HUMAN_GATE`。
- `PASS` 前逐句比对所有对白，并检查每个 coverage 项，不进行抽样。

PLOT 错误导致已存在下游需要失效时，按受影响 BEAT 报告最小 `stale_downstream`。
