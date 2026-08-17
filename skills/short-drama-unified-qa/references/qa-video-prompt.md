# QA:VIDEO_PROMPT 检查清单（段级，schema 2.0）

## 依据与对象

检查段级 `VideoPromptSpec`（一段 = 15/30 秒、覆盖 2–6 个连续镜头）的结构化字段与机械渲染 `body`，逐项对照：`PASS` 的 Plot/StoryboardRow、原始对白、资产台账、连续性台账、已验证模型规则、S01 随派工签发的 `requirements`；VISUAL_TRACK 额外对照人工 `APPROVED` 的精确分镜图版本；跨集首段额外对照上集 `EpisodeHandoff`。字段细节以 `../video-prompt-director/references/video-prompt-contract.md` 与 `_shared/segment-format.md` 为准。

质检只对照"已签发要求 + 权威上游 + 已有事实"，不替生产单元创作。

## 硬检

| 规则 ID | 检查 | 典型 `issue_type` | 默认所有者 |
|---|---|---|---|
| `VP-GATE-001` | 双轨门禁：VISUAL_TRACK 父集合与段内各镜图片条目均人工 `APPROVED`、精确版本、非 `STALE`；DIRECT_TRACK `covered_shot_ids` 各行 `STORYBOARD_TABLE: PASS`、非 `STALE`；跨集首段另有当前 `EPISODE_HANDOFF` | `UPSTREAM_GATE_FAILED` | 流程层 |
| `VP-TRACE-001` | `segment_id=SEG-E##-###` 与 `artifact_id=VP-E##-###` 序号一致；`covered_shot_ids` 2–6 个、同场、镜号连续；`source_beat_ids` 为段内各镜 BEAT 并集；`source_artifacts` 全量可反向追踪 | `VIDEO_PROMPT_TRACE_BROKEN` | `video-prompt-director` |
| `VP-CONTEXT-001` | `segment_context` 全项与 S02（scene_sub/spatial_anchors/scene_tone/light_base）、S03（screen_lock）、Manifest（visual_style_lock）、风格词包镜像一致，无上游不存在的内容 | `SEGMENT_CONTEXT_MISMATCH` | `video-prompt-director` |
| `VP-SLOT-001` | Mixed 槽位：对象去重、一槽一物、从 1 连续自增，正文与绑定完全一致；分镜图槽位仅 VISUAL_TRACK 存在 | `MIXED_SLOT_PLAN_INVALID` | `video-prompt-director` |
| `VP-START-001` | 段 0.0 秒状态：VISUAL_TRACK 与确认图一致；DIRECT_TRACK 与锁定上游 + 上一段 `final_state` 一致；跨集首段与 HANDOFF `final_frame_state` 一致 | `START_STATE_MISMATCH` | `video-prompt-director` |
| `VP-WORLD-001` | 从世界坐标正确换算当前摄影机屏幕左右，不传播镜像错误 | `SCREEN_POSITION_MISMATCH` | `video-prompt-director` |
| `VP-POSITION-001` | 每个可见人物在 `start_state` 与逐镜 `spatial_frame` 中明确世界锚点、屏幕左/中/右、前/中/后景、身体朝向、视线及相互关系；与 S03 `screen_lock` 一致，无理由不互换不镜像 | `CHARACTER_POSITION_RELATION_MISSING` | `video-prompt-director` |
| `VP-PROP-001` | 道具位置按推导规则生成：持有人位置 × `screen_lock`；无持有人读 BEAT `props` 位置状态；归属与状态全段可追踪 | `PROP_POSITION_UNTRACKABLE` | `video-prompt-director` |
| `VP-TIMELINE-001` | 首镜 `start_s=0.0`；相邻镜首尾相接无重叠无空隙；末镜 `end_s` 等于段时长（2.0→15s / 2.5→30s）；各镜时长 ≥1.5s | `TIMELINE_STRUCTURE_INVALID` | `video-prompt-director` |
| `VP-CAMERA-001` | 逐镜 `shot_size/viewpoint/confirmed_movement` 镜像 S03 行不改写；非固定运镜有 `movement_trigger`（动作/视线/信息揭示/情绪爆点）与 `movement_landing`，到达落点恢复清晰 | `CAMERA_MOVE_MISMATCH` | `video-prompt-director` 或 S03 |
| `VP-OPTICS-001` | 逐镜 `focal_length_mm/aperture_f` 落在图纸 §5 映射表对应该景别范围内；焦点与景深单一一致 | `OPTICS_CONTRADICTORY` | `video-prompt-director` |
| `VP-CUT-001` | 镜内连续：上一镜 `shot_end_state` → 下一镜 `spatial_frame` 直接继承，禁止切镜重置人物姿势、位置、道具或伤势 | `CUT_RESET_DETECTED` | `video-prompt-director` 或 S03 |
| `VP-ACTION-001` | 动作按剧情因果与顺序发生，包含准备、执行、接触/反馈、结果和回稳 | `ACTION_FLOW_INCOMPLETE` | `video-prompt-director` |
| `VP-PHYSICS-001` | 重心、惯性、支撑、接触、道具交互和恢复自然可执行 | `ACTION_PHYSICS_INVALID` | `video-prompt-director` |
| `VP-PERFORMANCE-001` | 表演有具体微动作、视线、呼吸和反应，不抽象或机械同步 | `PERFORMANCE_UNEXECUTABLE` | `video-prompt-director` |
| `VP-DIALOGUE-001` | 原台词逐字完整、说话人正确、无改写或新增；`dialogue_policy` 与全段对白块一致 | `DIALOGUE_MISMATCH` | `video-prompt-director` 或 S02 |
| `VP-DIALOGUE-002` | 每个对白块位于所属镜头时间范围内，禁止统一堆到段尾；语气/语速/气息和口型齐备，听者有低强度反应 | `DIALOGUE_TIMING_INVALID` | `video-prompt-director` |
| `VP-LIGHT-001` | `segment_light_color` 默认镜像 S02 `light_base`；光向、人物分离、色彩和材质在动作中连续可执行 | `LIGHTING_OR_MATERIAL_DRIFT` | `video-prompt-director` |
| `VP-SOUND-001` | 声音只来自画面真实存在的对白、环境、状态和动作，无默认 BGM | `SOUND_UNSUPPORTED` | `video-prompt-director` |
| `VP-CONTINUITY-001` | 段间连续：`incoming/outgoing` 均 `PASS`（仅批次首尾可 `BOUNDARY`）、邻居 ID 互指、两个 `state_id` 同时比较、`handoff_signature` 两侧完全相同、`mismatches` 为空 | `END_STATE_DISCONTINUITY` | `video-prompt-director` 或上游 |
| `VP-WINDOW-001` | `window: 2` 弱规则比较存在：distance=2 段间允许合理演化，禁止人物身份/伤势自愈/道具瞬移/锚点跳变/信息状态倒退等矛盾 | `WINDOW_CONTRADICTION` | `video-prompt-director` 或上游 |
| `VP-XEP-001` | 跨集首段：`PREVIOUS_END_STATE` 指向上集 `HANDOFF-E##`，`start_state.source_status=EPISODE_HANDOFF`，`inherit_required`/`reset_forbidden` 逐项落实 | `EPISODE_HANDOFF_IGNORED` | `video-prompt-director` 或流程层 |
| `VP-ADDITION-001` | 无擅增切镜、人物、动作、事件、台词或镜外事实；为已确认对象自动规划槽位不算新增剧情 | `UNSUPPORTED_VIDEO_ADDITION` | `video-prompt-director` |
| `VP-BODY-001` | `body` 由 `render_segment_prompt.ps1` 渲染（`body_rendered_by` 在案）；十五节标题齐全且顺序固定；结构字段与正文完整镜像无冲突；正文任何事实可指回结构化字段 | `BODY_MIRROR_MISMATCH` | `video-prompt-director` |
| `VP-BODY-002` | 正文无 QA 解释、RepairTicket、白模分析、营销话术、未决方案和错误槽位 | `BODY_CONTAMINATION` | `video-prompt-director` |
| `VP-MODEL-001` | 目标模式有 `VERIFIED` 规则；2.0 恰 15 秒、2.5 恰 30 秒且正文 ≤5000 code points | `MODEL_RULE_VIOLATION` | `video-prompt-director` |
| `VP-END-001` | `final_state.state_kind` 固定 `PLANNED`，不冒充实际生成末帧 | `PLANNED_END_AS_ACTUAL` | `video-prompt-director` |
| `VP-REGRESSION-001` | ChangeSet/返修只影响开放字段及声明镜像，未污染锁定内容或其他段 | `LOCKED_FIELD_CHANGED` | `video-prompt-director` |

## 一票否决（任一命中直接 `REPAIR`/`HUMAN_GATE`，不进入分项评分）

- 任一直接上游 `STALE` 或非 `PASS`/`APPROVED`；
- `body` 非渲染器产物或十五节缺节/乱序；
- 对白被改写、新增或丢失；
- 切镜重置（`VP-CUT-001`）或段间签名不一致（`VP-CONTINUITY-001`）；
- 人物屏幕位置违反 `screen_lock` 且无剧情理由；
- 跨集首段未承接 HANDOFF；
- 正文出现上游不存在的人物/道具/事件。

## 路由

- 时间线结构、动作物理、正文渲染、光声、模型表达、段内位置/道具推导错误：返回 S05，RepairTicket 填 `target_segment_ids`。
- 人物位置关系缺失、含糊或未镜像到正文：裁决 `REPAIR` 返回 S05，票据至少开放 `/start_state/characters`、`/timeline/*/spatial_frame`、`/final_state/characters` 与 `/body`；权威上游本身无法确定或互相冲突时裁决 `HUMAN_GATE`，不得由 QA/S05 猜测站位。
- 镜头时长、机位、切镜或动作拆分从根上不可执行（含单镜 <1.5s 无法修复）：返回 S03，并使覆盖行下游产物失效。
- Plot/原台词错误：返回 S02。
- 确认图与剧情/分镜权威来源冲突，或 HANDOFF 与上集事实冲突：`HUMAN_GATE`，S05 不得择一猜测。
- 段间/窗口矛盾根因在邻居段：票据 `target_segment_ids` 同时列出两侧段号，返回 S05 统筹修复；根因在上游分镜首尾互斥则返回真实上游。
- Seedance 2.5 的多模态参考可使用仓库内 `SD25-PROJECT-V1`；其他 2.5 任务没有额外已验证配置时不能借用 2.0 规则放行。
