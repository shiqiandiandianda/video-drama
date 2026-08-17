# VideoPromptSpec 契约（段级，schema 2.0）

## 目录

1. 产物边界
2. 完整字段
3. 标识与来源
4. 状态与时间轴
5. 十五节正文与渲染
6. 字数与纯净度
7. 批量交付
8. QA 交接

## 1. 产物边界

一个 `VideoPromptSpec` 控制**一个段**：15 秒（seedance-2.0）或 30 秒（seedance-2.5）的一条可生成视频，覆盖 2–6 个连续镜头（`covered_shot_ids`），单镜 ≥1.5 秒，各镜时长之和等于段时长。S05 的唯一正式状态是 `DRAFT`；独立 QA 才能产生 `PASS`、`REPAIR` 或 `HUMAN_GATE`。

结构化字段是事实主源；十五节 `body` 是这些字段的**机械渲染产物**，由 `scripts/render_segment_prompt.ps1` 生成，禁止 LLM 手写或改写 body。二者冲突即不合格；body 中任何事实无法指回结构化字段即不合格。

格式图纸（十五节字段 schema、渲染模板、映射表）的唯一出处是 `_shared/segment-format.md`；本契约与其冲突时以图纸为准。

旧 `"1.0"` 单镜产物一律标记 `STALE` 按段重产，不做兼容包装。

## 2. 完整字段

```yaml
schema_version: "2.0"
project_id: PRJ-001
flow_authorization_id: FLOW-AUTH-PRJ001-P6-0001
requirements_ref: FLOW-AUTH-PRJ001-P6-0001   # 镜像 S01 签发要求所属授权
scene_id: SCENE-E01-S01
segment_id: SEG-E01-002
shot_id: SHOT-E01-S01-003                    # 段内首镜（兼容字段）
covered_shot_ids:
  - SHOT-E01-S01-003
  - SHOT-E01-S01-004
  - SHOT-E01-S01-005
source_beat_ids:
  - BEAT-E01-S01-002

artifact_id: VP-E01-002
artifact_version: V1
full_id: VP-E01-002-V1
video_prompt_id: VP-E01-002-V1
status: DRAFT

task:
  task_mode: CREATE
  generation_task: MULTIMODAL_REFERENCE
  model: seedance-2.0
  model_rule_profile: SD20-V3.4
  product_flow: <已验证产品模式>
  output_scope: SEGMENT                      # 2.0 起固定为 SEGMENT
  delivery_mode: PROMPT_ONLY
  aspect_ratio: "9:16"
  target_duration_seconds: 15                # 段时长：2.0→15；2.5→30

# —— 上游镜像块：渲染器只读本规格，不回读上游文件 ——
segment_context:
  scene_sub: 住宅-餐厅                        # 镜像 S02
  spatial_anchors:                            # 镜像 S02（含 CAMERA_ANCHOR）
    - {kind: FIXTURE, name: 餐桌, screen_position: 画面中央偏右, description: 长方形木桌}
    - {kind: CAMERA_ANCHOR, name: 主机位, screen_position: 餐厅门侧, description: 朝餐桌方向拍摄}
  screen_lock:                                # 镜像 S03 场级锁（各镜一致部分）
    characters:
      - {name: 女主, screen_side: LEFT, vertical: EYE_LEVEL}
      - {name: 父亲, screen_side: RIGHT, vertical: EYE_LEVEL}
    main_axis: 左→右
  scene_tone:                                 # 镜像 S02
    style: 现实都市家庭悬疑
    color_palette: 暖黄主调 + 冷灰辅助
    rhythm: 克制压迫，情绪递进
  light_base:                                 # 镜像 S02
    key_direction: 右侧窗外
    color_temperature: 暖黄
  visual_style_lock: LIVE_ACTION_REALISM      # 镜像 ProjectManifest
  style_pack_positive: <镜像 _shared/style-packs.md 对应风格正词包全文>
  style_pack_negative: <镜像 _shared/style-packs.md 对应风格负词包全文>

# —— VISUAL_TRACK 专有（DIRECT_TRACK 省略）——
approved_storyboard_set_full_id: APPROVED-STORYBOARD-E01-V1
approved_image_full_id: IMG-E01-S01-003-V2   # 段内首镜的批准图

source_artifacts:
  - role: STORYBOARD_TABLE
    artifact_id: STORYBOARD-E01-S01
    artifact_version: V2
    full_id: STORYBOARD-E01-S01-V2
    status: PASS
    stale: false
    scope: SEG-E01-002
    covered_row_full_ids: [SHOT-E01-S01-003-V2, SHOT-E01-S01-004-V2, SHOT-E01-S01-005-V2]
  - role: PLOT_PROGRESSION
    artifact_id: PLOT-E01
    artifact_version: V1
    full_id: PLOT-E01-V1
    status: PASS
    stale: false
    scope: BEAT-E01-S01-002
    source_beat_ids: [BEAT-E01-S01-002]
  # —— VISUAL_TRACK 额外携带 ——
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
    resource: <实际图片路径或可读取资源定位>
    source_prompt_full_id: SP-E01-S01-003-V1
    approval_record:
      approved_by: <Human Director>
      approved_at: <时间>
      locked_fields: [构图, 景别, 人物位置, 核心道具]
      allowed_changes: [自然动作细节]
  - role: STORYBOARD_PROMPT
    artifact_id: SP-E01-S01-003
    artifact_version: V1
    full_id: SP-E01-S01-003-V1
    status: PASS
    stale: false
    scope: SHOT-E01-S01-003
  # —— 公共来源 ——
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
  - role: ASSET_LEDGER                  # 仅调用方实际提供时列入
    artifact_id: ASSET-LEDGER-PRJ001
    artifact_version: V3
    full_id: ASSET-LEDGER-PRJ001-V3
    status: APPROVED
    stale: false
    scope: PRJ-001
  - role: MODEL_RULES
    artifact_id: SD20-RULES
    artifact_version: V3.4
    full_id: SD20-RULES-V3.4
    status: PASS
    validation_status: VERIFIED
    stale: false
    scope: seedance-2.0
  - role: PREVIOUS_END_STATE
    artifact_id: VP-E01-001              # 上一段；跨集首段为 HANDOFF-E00 类 EpisodeHandoff
    artifact_version: V1
    full_id: VP-E01-001-V1
    status: PASS
    state_kind: PLANNED
    stale: false
    scope: SEG-E01-001

reference_bindings:
  - name: 女主
    asset_type: CHARACTER
    asset_id: CHAR-HEROINE-01
    asset_version: V3
    mixed_slot: 1
    slot_source: INPUT_LEDGER
    availability: PROVIDED
    reference_role: IDENTITY_APPEARANCE
    inherit: [成年身份、脸发、体型和本场服装]
    ignore: [参考姿势、背景、文字、水印和生成瑕疵]
  - name: 客厅
    asset_type: SCENE
    asset_id: null
    asset_version: null
    mixed_slot: 2
    slot_source: AUTO_PLANNED
    availability: REQUIRED_NOT_PROVIDED
    reference_role: SPACE_STYLE
    inherit: [空间结构、门窗、家具和主光方向]
    ignore: [参考图人物和错误道具]

source_lock:
  locked_fields:
    - /segment_id
    - /covered_shot_ids
    - /task/aspect_ratio
    - /task/target_duration_seconds
    - /start_state
    - /timeline/*/shot_id
    - /timeline/*/dialogue_blocks/*/exact_text
    - /final_state
  allowed_changes: []
  change_set_id: null
  repair_ticket_id: null

# —— 段 0.0 秒状态（图纸第五节）——
start_state:
  state_id: SS-E01-002-V1
  source_status: LOCKED_UPSTREAM_PLUS_PREVIOUS_END_STATE
  # 枚举：APPROVED_STORYBOARD_PLUS_LOCKED_UPSTREAM（VISUAL_TRACK）
  #       LOCKED_UPSTREAM_PLUS_PREVIOUS_END_STATE（DIRECT_TRACK）
  #       EPISODE_HANDOFF（跨集首段）
  spatial_world: [<人物与固定锚点的世界位置>]
  screen_projection: [<当前机位下左/中/右和前/中/后景>]
  characters:
    - name: 女主
      world_position: <世界位置>
      screen_position: SCREEN_LEFT       # SCREEN_LEFT | SCREEN_CENTER | SCREEN_RIGHT
      depth_plane: MIDGROUND             # FOREGROUND | MIDGROUND | BACKGROUND
      body_orientation: <双脚/骨盆/胸口/头部>
      gaze_target: <明确目标>
      nearest_anchor: <最近固定锚点>
      relative_to:
        - target: <另一个可见人物名>
          target_type: CHARACTER
          horizontal_relation: LEFT_OF
          depth_relation: SAME_DEPTH
          distance_relation: NEAR
      support_and_weight: <支撑脚与重心>
      action_stage: PREPARATION
      hand_and_contact: <双手与接触>
      performance_state: <呼吸、表情与情绪>
      injury_and_wardrobe: <伤势与服装状态>
      provenance: PREVIOUS_SEGMENT_FINAL_STATE
  props:
    - name: 通知书
      owner: 女主
      holder_or_contact: 女主右手
      position: <位置>
      orientation: <方向>
      state: <完整/打开/落地等>
      provenance: LOCKED_UPSTREAM
  foreground: <前景物体 + 焦态>
  midground: <人物关系 + 焦态>
  background: <场景内容 + 焦态>
  camera_carryover: <上一段相机停点；未知则 UNKNOWN>
  lighting_carryover: <主光与场景状态>
  sound_carryover: <对白/环境/动作声接口>
  action_carryover: <上一段结束时动作进行到哪一步>

# —— 段内镜头时间轴（图纸第六/七/八节）——
timeline:
  - shot_seq: 1
    shot_id: SHOT-E01-S01-003
    row_full_id: SHOT-E01-S01-003-V2
    start_s: 0.0
    end_s: 4.5
    camera:
      shot_size: 全景                     # 镜像 S03 columns.shot_size
      viewpoint: 正面平视                 # 镜像 S03 columns.camera_position
      confirmed_movement: FIXED           # 镜像 S03 columns.camera_movement
      movement_trigger: NONE              # 非固定时必填触发点（动作/视线/信息揭示/情绪爆点）
      movement_landing: <焦点落点>
      focal_length_mm: 28                 # 必须在图纸 §5 映射表该景别范围内
      aperture_f: 5.0                     # 同上
      focus_target: <主焦平面>
    spatial_frame:
      characters:
        - {name: 女主, screen_position: SCREEN_LEFT, depth_plane: MIDGROUND, focus_state: SHARP, body_orientation: 朝右}
        - {name: 父亲, screen_position: SCREEN_RIGHT, depth_plane: MIDGROUND, focus_state: SHARP, body_orientation: 朝左}
      props:
        - {name: 通知书, screen_area: 画面中央, held_by: 女主右手}
      foreground: <前景 + 焦态>
      midground: <中景 + 焦态>
      background: <背景 + 焦态>
      camera_anchor: <摄影机位于何处朝何处；镜像 S02 CAMERA_ANCHOR>
    action_performance:
      beats_description: <镜像 S03 visual_description：起点→核心动作→结果>
      performance: <镜像 S03 performance：眼神/面部/呼吸/重心/情绪>
    dialogue_blocks:
      - block_type: LIP_SYNC              # LIP_SYNC | INNER_OS | NO_DIALOGUE
        speaker: 女主
        start_s: 1.2
        end_s: 3.8
        exact_text: <逐字原台词>
        source_ref: SCRIPT-E01-V1:<来源范围>
        voice: <成年年龄层、音质、语气、情绪、音量、语速、气息>
        pause_before_keywords: ["考上了"]
        pause_seconds: 0.3
        stress_keywords: ["考上了"]
        primary_gesture: 右手轻推通知书
        after_hold_s: 0.5
    shot_end_state:                        # 镜尾状态：镜像 S03 shot_map[].end_state
      characters: {女主: 站在餐桌旁等待, 父亲: 抬头看向女主}
      props: {通知书: 平放在父亲面前}
      camera: {position: 门侧平视, focus: 父亲眼睛}
      action_stop: 父亲抬头动作完成瞬间

# —— 全段光线与色彩（图纸第十节，S05 段级生产决策）——
segment_light_color:
  key_direction: <主光方向；默认镜像 S02 light_base.key_direction>
  color_temperature: <色温；默认镜像 S02 light_base.color_temperature>
  face_lit_side: <人物亮面>
  face_shadow_side: <人物暗面>
  rim_light: <轮廓光来源>
  background_brightness: <背景亮度相对人物>
  prop_highlight: <关键道具高光>

# —— 声音设计（图纸第十二节）——
sound_design:
  ambient: [<固定环境声：风/雨/室内底噪/衣料/脚步/呼吸/场景机械声>]
  action_sfx:
    - {shot_seq: 1, sfx: <撞击/泥水/破空/门/金属等>}
  music_policy: NO_BGM
  dialogue_priority: 对白清晰优先，环境声与特效声不得覆盖台词
  spatial_rule: 所有声音方向与画面空间一致

# —— 本段最终承接状态（图纸第十五节，S05 段级生产，QA 检）——
final_state:
  state_id: PE-E01-002-V1
  state_kind: PLANNED
  characters:
    - name: 女主
      screen_position: SCREEN_LEFT
      depth_plane: MIDGROUND
      focus_state: SHARP
      posture: <站立/跪地/躺下等>
      body_orientation: <方向>
      gaze_target: <方向>
      hands: <正在拿什么>
      injury: <状态>
      emotion: <当前落点>
  props:
    - {name: 通知书, position: <位置+状态>, held_by: <谁持有或 null>}
  foreground: <内容 + 焦点>
  midground: <内容 + 焦点>
  background: <内容 + 焦点>
  camera_anchor: <摄影机在哪里 + 朝哪里>
  camera:
    focal_length_mm: 28
    viewpoint: <高/低/平/过肩等>
    movement_state: STOPPED               # STOPPED | MOVING
    final_focus: <人物眼睛/道具/远处目标>
  action_stop: <最后动作停在哪一步>
  next_segment_must_inherit: []
  forbidden_resets: []

continuity_constraints:
  - <人物、道具、空间、摄影机与声音连续性>

continuity_checks:
  window: 2
  incoming:
    status: PASS                          # 首段可为 BOUNDARY
    neighbor_segment_id: SEG-E01-001
    compared_state_ids: [PE-E01-001-V1, SS-E01-002-V1]
    checked_fields: [CHARACTERS, PROPS, SPATIAL_WORLD, CAMERA, LIGHTING, SOUND]
    mismatches: []
    handoff_signature:
      characters: []
      props: []
      spatial_world: []
      camera: <共同摄影机接口>
      lighting: <共同光线接口>
      sound: <共同声音接口>
    boundary_reason: null
  outgoing:
    status: PASS                          # 末段可为 BOUNDARY
    neighbor_segment_id: SEG-E01-003
    compared_state_ids: [PE-E01-002-V1, SS-E01-003-V1]
    checked_fields: [CHARACTERS, PROPS, SPATIAL_WORLD, CAMERA, LIGHTING, SOUND]
    mismatches: []
    handoff_signature:
      characters: []
      props: []
      spatial_world: []
      camera: <共同摄影机接口>
      lighting: <共同光线接口>
      sound: <共同声音接口>
    boundary_reason: null
  window_checks:                          # distance=2 弱规则：允许合理演化，禁止矛盾
    - neighbor_segment_id: SEG-E01-004
      distance: 2
      checked_fields: [CHARACTER_IDENTITY, PROP_OWNERSHIP, WORLD_ANCHORS, KNOWLEDGE_STATE]
      mismatches: []

body: |-
  <由 render_segment_prompt.ps1 按图纸十五节机械渲染的正文，不含代码围栏>
body_char_count: <实际计数>
body_rendered_by: render_segment_prompt.ps1
body_rendered_at: <ISO-8601 时间>

unresolved_fields: []
change_log: []
```

`qa_request` 是调用独立 QA 时的外层信封，不嵌入 `VideoPromptSpec`，避免产物递归包含自身。见第 8 节。

## 3. 标识与来源

- `segment_id` 使用 `SEG-E##-###`；`artifact_id` 使用 `VP-E##-###` 且序号与 `segment_id` 一致；`full_id` 与兼容别名 `video_prompt_id` 均等于 `artifact_id + "-" + artifact_version`。
- `shot_id` 保留为段内首镜（兼容）；`covered_shot_ids` 是段覆盖的完整连续镜头集合，必须 2–6 个、同场、按镜号连续。
- `scene_id`、`shot_id`、`source_beat_ids` 必须使用公共流水线规范，并与剧情、分镜行完全一致；`source_beat_ids` 为段内全部镜头覆盖 BEAT 的并集。
- VISUAL_TRACK：`approved_storyboard_set_full_id` 必须指向父级 `ApprovedStoryboardSet.full_id`，父集合与段内各镜图片条目均须 `APPROVED`；`approved_image_full_id` 等于 `source_artifacts[role=APPROVED_STORYBOARD].full_id`。DIRECT_TRACK：这两个字段及 `APPROVED_*`/`STORYBOARD_PROMPT` 来源角色整体省略。
- `source_artifacts` 必须列出全部直接权威来源，不使用单数 `source_artifact_id` 隐藏多来源关系。
- `ASSET_LEDGER` 只在调用方实际提供资产台账时列入；未提供时省略，并让全部 `reference_bindings` 使用 `AUTO_PLANNED`。不得创建假的资产台账版本。
- `PREVIOUS_END_STATE`：本集首段为首个段时可省略或标记批次边界；跨集首段必须指向上一集 `EpisodeHandoff`（`HANDOFF-E##`），此时 `start_state.source_status` 为 `EPISODE_HANDOFF`。
- `ORIGINAL_DIALOGUE.dialogue_policy` 只能为 `EXACT_SOURCE_TEXT` 或 `NO_DIALOGUE`。前者要求 `exact_lines` 与全段 `dialogue_blocks` 的说话人、逐字文本和来源一一匹配；后者要求段内全部镜头为 `NO_DIALOGUE` 块。
- `reference_bindings` 至少一项；`mixed_slot` 使用正整数存储，正文渲染为 `{{Mixed x}}`，每条 Prompt 必须从 1 连续自增且无空号。分镜图/站位图槽位仅 VISUAL_TRACK 存在。
- 已提供资产使用 `slot_source: INPUT_LEDGER`、`availability: PROVIDED`；未提供资产使用 `AUTO_PLANNED`、`REQUIRED_NOT_PROVIDED`，`asset_id/asset_version` 为 `null`。自动槽位是待上传计划，不是伪造已存在资产。
- 不同对象不得共用槽位，同一对象不得重复分配；正文出现的槽位集合必须与 `reference_bindings.mixed_slot` 完全一致。

## 4. 状态与时间轴

- `status` 只能由 S05 写为 `DRAFT`。
- `segment_context` 全项为上游镜像：与 S02/S03/Manifest/风格词包不一致即不合格；S05 不得在其中写入上游不存在的内容。
- `seedance-2.0` 的 `target_duration_seconds` 只能为 `15`；`seedance-2.5` 只能为 `30`。
- `timeline` 首镜 `start_s` 从 `0.0` 开始；相邻镜首尾相接，无重叠、无空隙；末镜 `end_s` 等于 `target_duration_seconds`；各镜时长 ≥1.5。
- `timeline[].camera.shot_size/viewpoint/confirmed_movement` 镜像 S03 行内容，不得改写；`focal_length_mm/aperture_f` 必须落在图纸 §5 映射表对应该景别的范围内。
- 非固定运镜必须填 `movement_trigger`（人物动作/视线变化/信息揭示/情绪爆点之一）与 `movement_landing`；快速运镜到达落点后立即恢复清晰。
- `spatial_frame` 逐人给出屏幕位置、景深层、焦态与朝向；人物屏幕位置与 S03 `screen_lock` 一致，无理由不得互换或镜像。道具行按道具推导规则生成：持有人位置 × `screen_lock`；无持有人读 BEAT `props` 位置状态。
- `dialogue_blocks` 必须位于所属镜头的时间范围内（`start_s/end_s` 落在该镜 `[start_s, end_s]` 内）；禁止把对白统一放到段尾。`NO_DIALOGUE` 块无 `exact_text` 等台词字段。
- `shot_end_state` 镜像 S03 `shot_map[].end_state`；下一镜 `spatial_frame` 必须与之直接继承，禁止切镜重置人物姿势、位置、道具或伤势。
- `start_state` 与上一段 `final_state` 签名一致（`continuity_checks.incoming`）；`final_state` 字段齐备，是下一段 `start_state` 的事实源。
- `continuity_checks` 必须同时含 `incoming/outgoing` 与 `window: 2`；真实相邻段使用 `PASS` 并比较两个 `state_id`；只有整个批次首尾可用 `BOUNDARY`。相邻两侧的 `handoff_signature` 必须完全相同，`mismatches` 必须为空。`window_checks` 对 distance=2 的段执行弱规则比较：允许中间段合理演化，禁止矛盾（人物身份/伤势自愈/道具瞬移/场景锚点跳变/信息状态倒退）。
- 时间值使用数字秒，不在结构化字段中写"约""左右"。
- `final_state.state_kind` 固定为 `PLANNED`。实际视频验收后由外部流程生成 `ACTUAL` 状态，不覆盖历史计划记录。
- `unresolved_fields` 若涉及身份、首帧位置、核心道具、原台词、画幅、时长、模型模式、运镜、空间锚点、站位锁或十五节任一 schema 字段，必须阻断正式 body——缺字段即阻断，禁止编造。

## 5. 十五节正文与渲染

`body` 固定为图纸十五节，由 `render_segment_prompt.ps1` 机械渲染：

1. 参考素材说明（`reference_bindings` + `{{Mixed x}}` 槽位）
2. 参考素材使用规则（静态）
3. 统一视觉与摄影基准（Manifest 风格锁 + 机型规则 + S02 `scene_tone`）
4. 场景空间锚点（S02 `spatial_anchors` + S03 `screen_lock`）
5. 承接上一段 15 秒（`start_state`）
6. 镜头时间轴（`timeline` 逐镜：摄影参数→画面空间→视角锚点→动作表演→运镜焦点）
7. 时间轴内对白（`dialogue_blocks`，写在对应镜头块内）
8. 镜尾状态（`shot_end_state` 逐镜）
9. 后续镜头重复结构（静态）
10. 全段光线与色彩（`segment_light_color`）
11. 全段摄影规格（映射表逐镜列出）
12. 声音设计（`sound_design`）
13. 全段连续性约束（静态 + 段内锁）
14. 负面约束（静态 + 风格负词包）
15. 本段最终承接状态（`final_state`）

- S05 不得手写、改写、润色 body；发现字段不足以渲染时补字段或阻断，不在文本层弥补。
- 渲染器前置机械检查：任一 `covered_shot_ids` 行非 `PASS` 或任一直接上游 `STALE` → 拒绝渲染。
- `body_rendered_by`/`body_rendered_at` 记录渲染来源；手工编辑 body 后未重跑渲染器即不合格。

## 6. 字数与纯净度

`body_char_count` 只统计 `body`：先把 `CRLF/CR` 归一化为 `LF`，再按 Unicode code point 计数；包含标点、空格和换行，不包含宿主展示时额外添加的 Markdown 代码围栏。

- Seedance 2.5：固定 30 秒，必须 `body_char_count <= 5000`。
- Seedance 2.0：固定 15 秒；当前资料未给出统一字符上限，不自行编造；渲染器在 `body_char_count > 5000` 时给出警告（不断言超限）。

正文禁止：

- `@素材名`、`{{Image x}}`、缺少 Mixed 槽位、空号、未登记编号或一槽多物；
- 多个片段标题或多次从 0 秒开始；
- `END FREEZE`、Emoji 标题、营销标签和"下一步我可以"；
- QA 结论、规则讲解、白模/截图解析、RepairTicket、镜尾卡正文；
- "或、任选、A/B、可能"等未决生成方案；
- 默认字幕、标题、logo、水印或 BGM；
- 内心 OS 生成字幕或显示内心文字。

## 7. 批量交付

批量时按段号输出多个完整 `VideoPromptSpec`：

```text
SEG-E01-002 / VP-E01-002-V1
<完整规格>

SEG-E01-003 / VP-E01-003-V1
<完整规格>
```

每个规格独立校验、独立 QA、独立版本；然后把完整规格按剧情顺序组成 JSON 数组并运行 `scripts/validate_prompt_sequence.ps1`（段序列校验：段间承接签名 + 窗口 ±2 弱规则）。相邻对任一侧不是 `PASS`、邻居 ID 不互指、状态 ID 未同时比较或 handoff 签名不同，都不得批量交付。一个段失败只阻断其相邻接口，不得自动污染不相邻段。

## 8. QA 交接

```yaml
qa_request:
  qa_mode: VIDEO_PROMPT
  artifact: <完整 VideoPromptSpec DRAFT>
  approved_upstream:
    - STORYBOARD-E01-S01-V2（含覆盖行）
    - PLOT-E01-V1
    - SCRIPT-E01-V1
    - ASSET-LEDGER-PRJ001-V3（仅调用方实际提供时）
    - SD20-RULES-V3.4
    - APPROVED-STORYBOARD-E01-V1 / IMG-E01-S01-003-V2（仅 VISUAL_TRACK）
    - HANDOFF-E00-V1（仅跨集首段）
  project_constraints: <项目锁定事实与模型规则>
  change_set: null
  previous_version: null
  flow_control:
    production_authorization_id: <artifact.flow_authorization_id>
    flow_state: <完整当前 S01 状态包，dispatch 为 CALL_QA>
```
