# QA:STORYBOARD_TABLE 检查清单

## 依据与对象

检查完整 `StoryboardTable` 及每条规范 `shot_map`，逐项对照 `PASS` 的 `PlotProgressionSpec`、资产、项目画幅/导演约束和相邻镜头。需要字段标准时读取 `../storyboard-table-director/references/storyboard-table-standard.md`。

## 硬检

| 规则 ID | 检查 | 典型 `issue_type` |
|---|---|---|
| `STB-GATE-001` | 上游 Plot 为当前 `PASS` 版本，范围和项目一致 | `UPSTREAM_GATE_FAILED` |
| `STB-SCHEMA-001` | 固定九列齐全，一镜一行，镜号连续，表与 `shot_map` 镜像一致 | `NINE_COLUMN_CONTRACT_INVALID` |
| `STB-TRACE-001` | `shot_id + storyboard_row_version → source_beat_ids[]` 可回溯 | `SHOT_TRACE_BROKEN` |
| `STB-COVERAGE-001` | 所有 BEAT 至少映射一镜，且没有无来源镜头 | `BEAT_COVERAGE_MISSING` |
| `STB-ORDER-001` | 镜头顺序保持剧情事件、人物出场和原台词顺序 | `SHOT_ORDER_CHANGED` |
| `STB-FOCUS-001` | 每镜只有一个清楚画面重点和可解释导演目的 | `SHOT_FOCUS_AMBIGUOUS` |
| `STB-SIZE-001` | 景别能承载空间、关系、动作、表情或关键道具信息 | `SHOT_SIZE_UNFIT` |
| `STB-CAMERA-001` | 机位可执行，能定位摄影机相对主体的位置和角度 | `CAMERA_POSITION_UNCLEAR` |
| `STB-AXIS-001` | 互动轴、运动轴、视线、世界左右和出入方向成立 | `AXIS_OR_POSITION_CONTINUITY` |
| `STB-ACTION-001` | 动作起点、过程、接触反馈、结果与停点完整 | `ACTION_PHASE_MISSING` |
| `STB-ACTION-002` | 动作既不过碎也不超载；短镜主目标和动作拍数量受控 | `ACTION_LOAD_INVALID` |
| `STB-DIALOGUE-001` | 原台词逐字保留、说话人正确，并与动作/听者反应同步 | `DIALOGUE_STAGING_INVALID` |
| `STB-DURATION-001` | 秒数可容纳真实语速、动作、停顿和反应 | `DURATION_INSUFFICIENT` |
| `STB-PERFORMANCE-001` | 情绪转成可见微表演；长近景/特写不空转 | `PERFORMANCE_NOT_VISIBLE` |
| `STB-ENSEMBLE-001` | 多人镜头主次明确，不全员冻结或机械同步反应 | `ENSEMBLE_STAGING_FLAT` |
| `STB-CONTINUITY-001` | 人脸、发型、服装、伤口、姿势、道具归属和场景锚点连续 | `ASSET_STATE_DISCONTINUITY` |
| `STB-CONTINUITY-002` | 动作切镜继承速度、重心、呼吸、持物手、惯性与接触 | `ACTION_CUT_DISCONTINUITY` |
| `STB-MOTION-001` | 每镜最多一个主要运镜，且有动作触发、路径、落点 | `CAMERA_MOVE_INVALID` |
| `STB-REDUNDANCY-001` | 相邻镜头无无意义重复、无动机跳切或信息量倒退 | `SHOT_REDUNDANT` |
| `STB-BOUNDARY-001` | 表内不含 Prompt 教程、模型参数、素材槽位或内部 QA 解释 | `STAGE_BOUNDARY_VIOLATION` |
| `STB-REGRESSION-001` | 返修只改目标镜头/字段；无关行与其版本保持不变 | `LOCKED_FIELD_CHANGED` |

## 时长判断

参考范围只用于发现明显不足：简单动作约 1.5–2 秒，完整位移动作 2–4 秒，短台词 2–3 秒，动作加台词 3–5 秒，多人连续反应 4–6 秒，特写反应 1–2.5 秒。必须结合真实台词和动作负荷判断，不机械统一镜长。

## 路由与表级裁决

- 镜头设计、机位、轴线、运镜、时长、表演：`storyboard-table-director`。
- Plot 已经遗漏/错序/改台词：`script-plot-progression`，并使相关镜头链失效。
- 任一行失败时父表不得 `PASS`。
- 仅当全部行通过时输出 `PASS`；流程写回必须同时将父表和全部 `shot_map[].status` 设为 `PASS`。
