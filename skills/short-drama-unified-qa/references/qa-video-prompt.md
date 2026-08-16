# QA:VIDEO_PROMPT 检查清单

## 依据与对象

检查单镜头 `VideoPromptSpec` 的结构化字段与可投喂 `body`，逐项对照人工 `APPROVED` 的精确分镜图版本、`PASS` 的 Plot/StoryboardRow、原始对白、资产、连续性台账和已验证的目标模型规则。需要字段细节时读取 `../video-prompt-director/references/video-prompt-contract.md`。

## 硬检

| 规则 ID | 检查 | 典型 `issue_type` | 默认所有者 |
|---|---|---|---|
| `VP-GATE-001` | 父分镜集合和当前图像条目均人工 `APPROVED`、精确版本、非 `STALE` | `APPROVED_IMAGE_GATE_FAILED` | 人工确认/流程层 |
| `VP-TRACE-001` | 单产物单 `shot_id`；Plot、分镜行、图片、资产、模型规则可反向追踪 | `VIDEO_PROMPT_TRACE_BROKEN` | `video-prompt-director` |
| `VP-START-001` | 0 秒首帧构图、景别、人物位置、道具和可见状态与确认图一致 | `APPROVED_START_MISMATCH` | `video-prompt-director` |
| `VP-WORLD-001` | 从世界坐标正确换算当前摄影机屏幕左右，不传播镜像错误 | `SCREEN_POSITION_MISMATCH` | `video-prompt-director` |
| `VP-ACTION-001` | 动作按剧情因果与顺序发生，包含准备、执行、接触/反馈、结果和回稳 | `ACTION_FLOW_INCOMPLETE` | `video-prompt-director` |
| `VP-PHYSICS-001` | 重心、惯性、支撑、接触、道具交互和恢复自然可执行 | `ACTION_PHYSICS_INVALID` | `video-prompt-director` |
| `VP-PERFORMANCE-001` | 表演有具体微动作、视线、呼吸和反应，不抽象或机械同步 | `PERFORMANCE_UNEXECUTABLE` | `video-prompt-director` |
| `VP-DIALOGUE-001` | 原台词逐字完整、说话人正确、无改写或新增 | `DIALOGUE_MISMATCH` | `video-prompt-director` 或 S02 |
| `VP-DIALOGUE-002` | 对白绑定合理时间窗、语气/语速/气息和口型，听者有低强度反应 | `DIALOGUE_TIMING_INVALID` | `video-prompt-director` |
| `VP-DURATION-001` | 总时长和时间线连续，足以容纳对白、动作、停顿、运镜与反应 | `DURATION_INSUFFICIENT` | `video-prompt-director` 或 S03 |
| `VP-CAMERA-001` | 景别、机位、主运镜继承分镜；运镜有动作触发、路径、落点和停稳 | `CAMERA_MOVE_MISMATCH` | `video-prompt-director` 或 S03 |
| `VP-OPTICS-001` | 焦段、f 值、距离、焦点和景深单一一致，不改变确认构图信息量 | `OPTICS_CONTRADICTORY` | `video-prompt-director` |
| `VP-LIGHT-001` | 光向、人物分离、实景灯光、色彩和材质在动作中连续可执行 | `LIGHTING_OR_MATERIAL_DRIFT` | `video-prompt-director` |
| `VP-SOUND-001` | 声音只来自画面真实存在的对白、环境、状态和动作，无默认 BGM | `SOUND_UNSUPPORTED` | `video-prompt-director` |
| `VP-CONTINUITY-001` | 人物、视线、伤口、手持道具、环境和镜尾状态支持下一镜 | `END_STATE_DISCONTINUITY` | `video-prompt-director` 或上游 |
| `VP-ADDITION-001` | 无擅增切镜、人物、动作、事件、台词、素材槽位或镜外事实 | `UNSUPPORTED_VIDEO_ADDITION` | `video-prompt-director` |
| `VP-BODY-001` | 结构字段与五段 `body_sections/body` 完整镜像且无冲突 | `BODY_MIRROR_MISMATCH` | `video-prompt-director` |
| `VP-BODY-002` | 正文无 QA 解释、RepairTicket、白模分析、营销话术、未决方案和错误槽位 | `BODY_CONTAMINATION` | `video-prompt-director` |
| `VP-MODEL-001` | 目标模式有 `VERIFIED` 规则；2.5 正文不超过 5000 Unicode code points | `MODEL_RULE_VIOLATION` | `video-prompt-director` |
| `VP-END-001` | `end_state` 明确标为 `PLANNED`，不冒充实际生成末帧 | `PLANNED_END_AS_ACTUAL` | `video-prompt-director` |
| `VP-REGRESSION-001` | ChangeSet/返修只影响开放字段及声明镜像，未污染锁定内容或其他镜头 | `LOCKED_FIELD_CHANGED` | `video-prompt-director` |

## 路由

- 时间线、动作物理、正文、光声或模型表达错误：返回 S05。
- 镜头时长、机位、切镜或动作拆分从根上不可执行：返回 S03，并使同镜头 S04、图片、S05 失效。
- Plot/原台词错误：返回 S02。
- 确认图与剧情/分镜权威来源冲突：`HUMAN_GATE`，S05 不得择一猜测。
- Seedance 2.5 没有已验证规则配置时不能借用 2.0 规则放行。
