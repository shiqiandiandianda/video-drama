# VideoPromptSpec 契约

## 目录

1. 产物边界
2. 完整字段
3. 标识与来源
4. 状态与时间轴
5. 正文分区和镜像
6. 字数与纯净度
7. 批量交付
8. QA 交接

## 1. 产物边界

一个 `VideoPromptSpec` 只控制一个已批准 `shot_id` 的一个可生成视频片段。S05 的唯一正式状态是 `DRAFT`；独立 QA 才能产生 `PASS`、`REPAIR` 或 `HUMAN_GATE`。

结构化字段是事实主源；`body` 是这些字段面向目标模型的可投喂渲染。二者不能互相矛盾。

## 2. 完整字段

```yaml
schema_version: "1.0"
project_id: PRJ-001
scene_id: SCENE-E01-S01
shot_id: SHOT-E01-S01-003
source_beat_ids:
  - BEAT-E01-S01-002

artifact_id: VP-E01-S01-003
artifact_version: V1
full_id: VP-E01-S01-003-V1
video_prompt_id: VP-E01-S01-003-V1
status: DRAFT

task:
  task_mode: CREATE
  generation_task: MULTIMODAL_REFERENCE
  model: seedance-2.0
  model_rule_profile: SD20-V3.4
  product_flow: <已验证产品模式>
  output_scope: SINGLE_SHOT
  delivery_mode: PROMPT_ONLY
  aspect_ratio: "9:16"
  target_duration_seconds: 8

approved_storyboard_set_full_id: APPROVED-STORYBOARD-E01-V1
approved_image_full_id: IMG-E01-S01-003-V2
source_artifacts:
  - role: APPROVED_STORYBOARD_SET
    artifact_id: APPROVED-STORYBOARD-E01
    artifact_version: V1
    full_id: APPROVED-STORYBOARD-E01-V1
    status: APPROVED
    stale: false
    scope: E01
  - role: APPROVED_STORYBOARD
    artifact_id: IMG-E01-S01-003
    artifact_version: V2
    full_id: IMG-E01-S01-003-V2
    status: APPROVED
    stale: false
    scope: SHOT-E01-S01-003
    source_beat_ids: [BEAT-E01-S01-002]
    resource: <实际图片路径或可读取资源定位>
    source_prompt_full_id: SP-E01-S01-003-V1
    approval_record:
      approved_by: <Human Director>
      approved_at: <时间>
      locked_fields:
        - 构图
        - 景别
        - 人物位置
        - 核心道具
      allowed_changes:
        - 自然动作细节
  - role: STORYBOARD_PROMPT
    artifact_id: SP-E01-S01-003
    artifact_version: V1
    full_id: SP-E01-S01-003-V1
    status: PASS
    stale: false
    scope: SHOT-E01-S01-003
    source_beat_ids: [BEAT-E01-S01-002]
  - role: PLOT_PROGRESSION
    artifact_id: PLOT-E01
    artifact_version: V1
    full_id: PLOT-E01-V1
    status: PASS
    stale: false
    scope: BEAT-E01-S01-002
    source_beat_ids: [BEAT-E01-S01-002]
  - role: STORYBOARD_TABLE
    artifact_id: STORYBOARD-E01-S01
    artifact_version: V2
    full_id: STORYBOARD-E01-S01-V2
    status: PASS
    stale: false
    scope: SHOT-E01-S01-003
    source_beat_ids: [BEAT-E01-S01-002]
    row_full_id: SHOT-E01-S01-003-V2
    storyboard_row_version: V2
  - role: ORIGINAL_DIALOGUE
    artifact_id: SCRIPT-E01
    artifact_version: V1
    full_id: SCRIPT-E01-V1
    status: APPROVED
    stale: false
    scope: <来源范围>
    dialogue_policy: EXACT_SOURCE_TEXT   # 无对白时为 NO_DIALOGUE
    exact_lines:
      - speaker: 女主
        text: <逐字原台词>
        source_ref: SCRIPT-E01-V1:<来源范围>
  - role: ASSET_LEDGER
    artifact_id: ASSET-LEDGER-PRJ001
    artifact_version: V3
    full_id: ASSET-LEDGER-PRJ001-V3
    status: APPROVED
    stale: false
    scope: SHOT-E01-S01-003
  - role: MODEL_RULES
    artifact_id: SD20-RULES
    artifact_version: V3.4
    full_id: SD20-RULES-V3.4
    status: PASS
    validation_status: VERIFIED
    stale: false
    scope: seedance-2.0
  - role: PREVIOUS_END_STATE
    artifact_id: PE-E01-S01-002
    artifact_version: V1
    full_id: PE-E01-S01-002-V1
    status: PASS
    state_kind: PLANNED
    stale: false
    scope: SHOT-E01-S01-002

reference_bindings:
  - name: 女主
    asset_type: CHARACTER
    asset_id: CHAR-HEROINE-01
    asset_version: V3
    mixed_slot: 1
    reference_role: IDENTITY_APPEARANCE
    inherit:
      - 成年身份、脸发、体型和本场服装
    ignore:
      - 参考姿势、背景、文字、水印和生成瑕疵
  - name: 客厅
    asset_type: SCENE
    asset_id: SCENE-HOME-01
    asset_version: V2
    mixed_slot: 3
    reference_role: SPACE_STYLE
    inherit:
      - 空间结构、门窗、家具和主光方向
    ignore:
      - 参考图人物和错误道具

source_lock:
  locked_fields:
    - /shot_id
    - /approved_image_full_id
    - /task/aspect_ratio
    - /task/target_duration_seconds
    - /start_state/spatial_world
    - /start_state/screen_projection
    - /camera/shot_size
    - /camera/viewpoint
    - /camera/confirmed_movement
    - /dialogue_audio/*/exact_text
  allowed_changes: []
  change_set_id: null
  repair_ticket_id: null

start_state:
  state_id: SS-E01-S01-003-V1
  source_status: APPROVED_STORYBOARD_PLUS_LOCKED_UPSTREAM
  spatial_world:
    - <人物与固定锚点的世界位置>
  screen_projection:
    - <当前机位下左/中/右和前/中/后景>
  characters:
    - name: 女主
      world_position: <世界位置>
      screen_position: <屏幕投影>
      body_orientation: <双脚/骨盆/胸口/头部>
      gaze_target: <明确目标>
      support_and_weight: <支撑脚与重心>
      action_stage: PREPARATION
      hand_and_contact: <双手与接触>
      performance_state: <呼吸、表情与情绪>
      provenance: APPROVED_IMAGE_VISIBLE
  props:
    - name: 通知书
      owner: 女主
      holder_or_contact: 女主右手
      position: <位置>
      orientation: <方向>
      state: <完整/打开/落地等>
      provenance: LOCKED_UPSTREAM
  camera_carryover: <上一镜相机惯性/停稳；未知则 UNKNOWN>
  lighting_carryover: <主光与场景状态>
  sound_carryover: <对白/环境/动作声接口>

action_flow:
  core_emotion: <一个主要情绪，至多一个辅助情绪>
  intended_result: <本镜计划剧情结果>
  timeline:
    - start_seconds: 0
      end_seconds: 2
      camera_start: <镜头起点>
      primary_event: <唯一主要可见事件>
      action_physics: <触发、重心、动作、接触/惯性/恢复>
      performance: <相关微表演与听者反应>
      camera_execution: <已确认运镜的触发、路径、落点>
      light_sound_change: <动作发生时的光影和声音反馈>
    - start_seconds: 2
      end_seconds: 8
      camera_start: <前一段落点>
      primary_event: <唯一主要可见事件>
      action_physics: <过程与结果>
      performance: <可见情绪变化>
      camera_execution: <继续/停稳，不新增运镜>
      light_sound_change: <现场声光>

dialogue_audio:
  - speaker: 女主
    exact_text: "<逐字原台词>"
    source_ref: SCRIPT-E01-V1:<来源范围>
    start_seconds: 2.2
    end_seconds: 5.5
    voice: <成年年龄层、音质、语气、音量、语速、气息>
    mouth_performance: <吸气、开口、重音、停顿、收口>
    listener_reactions:
      - <非说话人闭嘴并做低强度反应>

camera:
  shot_size: 中景
  viewpoint: 正面平视
  camera_height: 1.35m
  axis_side: <互动轴合法侧>
  composition: <批准构图的文字转译>
  confirmed_movement: FIXED
  movement_trigger: NONE
  movement_path: NONE
  movement_landing: <最终构图和停稳状态>
  optics_source: DERIVED_EXECUTION
  focal_length_mm: 50
  aperture_f: 4
  camera_distance_m: 2.4
  focus_target: <主焦平面>
  follow_focus: <移动时路径；固定时 NONE>
  visible_depth_of_field: <谁清楚、谁柔化、背景是否可辨>
  camera_system: PROJECT_UNSPECIFIED
  frame_rate_fps: <项目锁定或 PROJECT_UNSPECIFIED>
  shutter: <项目锁定或 PROJECT_UNSPECIFIED>
  exposure_continuity: <光圈/ND/灯光变化规则>

lighting_color_material:
  motivated_sources: []
  key_and_negative_fill: <主光方向和暗侧负补>
  separation_and_practicals: <轮廓分离和实景灯光池>
  brightness_zones: <前中后景明暗分区>
  highlight_target: <唯一/克制最高亮度>
  color_hierarchy: <环境基底、人物分离、强调/危险色、黑位/中间调/高光>
  material_response: <皮肤、服装、道具、场景材质>

sound:
  dialogue: []
  environment: []
  body_state: []
  action: []
  music_policy: NO_BGM

end_state:
  state_id: PE-E01-S01-003-V1
  state_kind: PLANNED
  recommended_stable_frame_seconds: 7.7
  characters: []
  props: []
  camera: <位置、高度、角度、焦段、f值、焦点、运动/停稳>
  lighting: <主光和场景状态>
  sound_tail: <对白/环境/动作声尾部>
  next_shot_must_inherit: []
  forbidden_resets: []

continuity_constraints:
  - <人物、道具、空间、摄影机与声音连续性>

body_sections:
  reference_materials: <参考图素材说明；编辑/延长任务使用对应句式>
  approved_start_and_spatial_state: <站位来源、自包含0秒状态、核心情绪和停点>
  continuous_timeline: <一套连续时间轴>
  imaging: <摄影光学、光影、色彩和材质>
  sound_continuity_stability: <现场声、无BGM、连续性和简短稳定性>

body: |-
  <按固定顺序拼接 body_sections 的可投喂正文，不含代码围栏>
body_char_count: <实际计数>

unresolved_fields: []
change_log: []
```

`qa_request` 是调用独立 QA 时的外层信封，不嵌入 `VideoPromptSpec`，避免产物递归包含自身。见第 8 节。

## 3. 标识与来源

- `artifact_id` 不含版本；`full_id` 与兼容别名 `video_prompt_id` 均等于 `artifact_id + "-" + artifact_version`。
- `scene_id`、`shot_id` 和 `source_beat_ids` 必须使用公共流水线规范，并与剧情、分镜行、图片条目完全一致。
- `approved_storyboard_set_full_id` 必须指向父级 `ApprovedStoryboardSet.full_id`；父集合与当前图片条目均须为 `APPROVED`。
- `approved_image_full_id` 必须等于 `source_artifacts[role=APPROVED_STORYBOARD].full_id`。
- `source_artifacts` 必须列出父级 `APPROVED_STORYBOARD_SET`、当前 `APPROVED_STORYBOARD` 图片条目、图片对应的 `STORYBOARD_PROMPT` 及其余全部直接权威来源，不使用单数 `source_artifact_id` 隐藏多来源关系。
- 每个来源的 `scope` 必须能映射当前 `shot_id` 或其 `beat_id`。
- `ORIGINAL_DIALOGUE.dialogue_policy` 只能为 `EXACT_SOURCE_TEXT` 或 `NO_DIALOGUE`。前者要求 `exact_lines` 与 `dialogue_audio` 的说话人、逐字文本和来源一一匹配；后者要求两个数组均为空。
- `reference_bindings.mixed_slot` 使用整数存储，正文渲染为 `{{Mixed x}}`；编号不连续仍原样保留。
- 没有真实槽位的资产可以保留稳定文字描述，但 `mixed_slot` 写 `null`，正文不得伪造编号。

## 4. 状态与时间轴

- `status` 只能由 S05 写为 `DRAFT`。
- `action_flow.timeline` 第一段从 `0` 开始；相邻段必须首尾相接，无重叠、无空隙；最后一段等于 `target_duration_seconds`。
- 一个时间段只承载一个主要事件；允许包含支撑该事件的表演、光影和声音。
- 时间值使用数字秒，不在结构化字段中写“约”“左右”。
- `end_state.state_kind` 固定为 `PLANNED`。实际视频验收后由外部流程生成 `ACTUAL` 状态，不覆盖历史计划记录。
- `unresolved_fields` 若涉及身份、首帧位置、核心道具、原台词、画幅、时长、模型模式或运镜，必须阻断正式 body。

## 5. 正文分区和镜像

`body_sections` 固定顺序：

1. `reference_materials`
2. `approved_start_and_spatial_state`
3. `continuous_timeline`
4. `imaging`
5. `sound_continuity_stability`

用空行连接五个非空分区得到 `body`。结构化事实必须镜像到对应分区：

| 结构化字段 | 正文镜像位置 |
|---|---|
| `reference_bindings` | `reference_materials` |
| `start_state`、核心情绪、结果 | `approved_start_and_spatial_state` |
| `action_flow.timeline`、`dialogue_audio`、运镜触发 | `continuous_timeline` |
| `camera`、`lighting_color_material` | `imaging`，必要时也嵌入时间轴动作点 |
| `sound`、`continuity_constraints` | `sound_continuity_stability` |

结构化字段和正文出现冲突时，产物不合格；不得让自由文本 body 暗改锁定字段。

## 6. 字数与纯净度

`body_char_count` 只统计 `body`：先把 `CRLF/CR` 归一化为 `LF`，再按 Unicode code point 计数；包含标点、空格和换行，不包含宿主展示时额外添加的 Markdown 代码围栏。

- Seedance 2.5：必须 `body_char_count <= 5000`，同时仍需通过模型规则可用性门禁。
- Seedance 2.0：当前资料未给出统一字符上限，不自行编造；仍应保持单镜头、动作驱动和必要信息密度。

正文禁止：

- `@素材名`、`{{Image x}}`、不存在的 Mixed 编号；
- 多个片段标题或多次从 0 秒开始；
- `END FREEZE`、`OS`、Emoji 标题、营销标签和“下一步我可以”；
- QA 结论、规则讲解、白模/截图解析、RepairTicket、镜尾卡正文；
- “或、任选、A/B、可能”等未决生成方案；
- 默认字幕、标题、logo、水印或 BGM。

## 7. 批量交付

批量时按镜号输出多个完整 `VideoPromptSpec`：

```text
SHOT-E01-S01-003 / VP-E01-S01-003-V1
<完整规格>

SHOT-E01-S01-004 / VP-E01-S01-004-V1
<完整规格>
```

每个规格独立校验、独立 QA、独立版本。一个镜头失败不得自动污染未受影响镜头。

## 8. QA 交接

```yaml
qa_request:
  qa_mode: VIDEO_PROMPT
  artifact: <完整 VideoPromptSpec DRAFT>
  approved_upstream:
    - APPROVED-STORYBOARD-E01-V1 / IMG-E01-S01-003-V2
    - PLOT-E01-V1
    - STORYBOARD-E01-S01-V2 / SHOT-E01-S01-003-V2
    - SCRIPT-E01-V1
    - ASSET-LEDGER-PRJ001-V3
    - SD20-RULES-V3.4
  project_constraints: <项目锁定事实与模型规则>
  change_set: null
  previous_version: null
```

S05 不填写实际 `verdict`。QA 必须同时检查结构化规格与可投喂 `body`，并以 `full_id` 标识被检版本。
