# S02-S05 公共流水线契约

## 1. 规范标识

所有阶段必须原样继承 `project_id`。集号和场号均使用至少两位数字。

```text
scene_id  = SCENE-E{episode}-S{scene}          例：SCENE-E01-S03
beat_id   = BEAT-E{episode}-S{scene}-{beat}    例：BEAT-E01-S03-004
shot_id   = SHOT-E{episode}-S{scene}-{shot}    例：SHOT-E01-S03-005
segment_id = SEG-E{episode}-{序号}             例：SEG-E01-002
```

段（Segment）是一个视频 Prompt 的生成单位：15 秒（seedance-2.0）或 30 秒（seedance-2.5），覆盖 2–6 个连续镜头，单镜 ≥1.5 秒，各镜时长之和等于段时长。段按连续 `shot_ids` 与时长的上限分组，与图轨审片排版单位"页"（2列5行=10格）无关。

`shot_id` 从 `scene_id` 派生时，删除固定前缀 `SCENE-`，再追加三位镜头序号；禁止生成 `SHOT-SCENE-...`，也禁止把 `SCENE-E01-S03` 缩写成无集号的 `S03`。

规范稳定产物 ID：

```text
PLOT-E01
STORYBOARD-E01-S03
SHOT-E01-S03-005
SP-E01-S03-005
IMG-E01-S03-005
APPROVED-STORYBOARD-E01
VP-E01-002                # 段级 VideoPromptSpec，序号与 segment_id 对应
HANDOFF-E01               # 集间交接包
```

所有版本化产物统一携带：

```yaml
schema_version: "1.0"
project_id: PRJ-001
flow_authorization_id: FLOW-AUTH-PRJ001-P2-0001
artifact_id: <不带版本的稳定 ID>
artifact_version: V1
full_id: <artifact_id>-<artifact_version>
status: DRAFT | CHECKING | REPAIR | PASS | HUMAN_GATE | APPROVED | STALE
```

直接上游只有一个时增加 `source_artifact_id`、`source_version`、`source_full_id`；有多个权威上游时使用 `source_artifacts` 数组，每项仍拆分稳定 ID、版本和完整 ID。不得把完整 ID 填入 `artifact_id`。

## 2. 标准链路（双轨）

项目级开关挂在 `ProjectManifest.constraints`：

```yaml
storyboard_image_track: REQUIRED | OPTIONAL | DISABLED   # 默认 OPTIONAL
```

- `REQUIRED` = 全项目走图轨（原单轨行为）；`DISABLED` = 全项目不走图；`OPTIONAL` = 逐镜头/逐段可选（高风险空间镜头仍走图确认）。
- 旧项目续跑缺 `visual_style_lock`（见 `_shared/style-packs.md`）→ HUMAN_GATE 补锁，不得默认猜测。

**VISUAL_TRACK（有图轨）**：

```text
PlotProgressionSpec(PASS)
→ StoryboardTable + StoryboardRow(PASS)
→ StoryboardPromptSpec(PASS)
→ StoryboardImage(PASS)
→ ApprovedStoryboardSet(APPROVED，且当前图片条目 APPROVED)
→ VideoPromptSpec(DRAFT)
```

**DIRECT_TRACK（无图轨）**：

```text
PlotProgressionSpec(PASS)
→ StoryboardTable + StoryboardRow(PASS)
→ VideoPromptSpec(DRAFT)   # start_state.source_status = LOCKED_UPSTREAM_PLUS_PREVIOUS_END_STATE
```

两条轨道的 VideoPromptSpec 均为**段级产物**（`segment_id` + `covered_shot_ids[]`），十五节 body 由 `render_segment_prompt.ps1` 机械渲染，禁止 LLM 手写 body（图纸与纪律见 `_shared/segment-format.md`）。

生产 Skill 只写 `DRAFT` 或门禁失败时的 `HUMAN_GATE`。独立 QA 写 `CHECKING/PASS/REPAIR/HUMAN_GATE`；人工确认阶段写 `APPROVED`。

S01 是唯一入口。S02-S05 及外部生图阶段必须收到 S01 签发、与当前阶段/目标/范围完全匹配的 `ISSUED FlowAuthorization` 才能生产；否则只返回 `FLOW_DISPATCH_REQUIRED` 并路由 S01，不得输出阶段产物。产物必须镜像该授权的 `authorization_id`。S01 登记结果时把授权改为 `CONSUMED` 并绑定精确 `artifact_full_id`。

## 3. BEAT 与镜头映射

跨 S03-S05 一律使用数组字段：

```yaml
source_beat_ids:
  - BEAT-E01-S03-004
```

一个镜头可覆盖多个相邻 BEAT，一个 BEAT 也可拆成多个镜头。任何阶段不得把 `source_beat_ids` 降格为单数后丢失映射。

S03 的 `shot_map` 每项就是规范 `StoryboardRow`，同时包含九列正文和追踪字段。表级 QA 裁决 `PASS` 时，必须在同一裁决中把所有合格行的 `status` 写为 `PASS`；存在失败行时表不得为 `PASS`。

## 4. 统一 QA 请求

所有生产 Skill 只提交以下信封；`verdict`、`issues`、`repair_ticket` 和 `checked_at` 只属于 QA 响应：

```yaml
qa_request:
  qa_mode: PLOT | STORYBOARD_TABLE | STORYBOARD_PROMPT | STORYBOARD_IMAGE | VIDEO_PROMPT
  artifact: <完整当前产物，不是仅 ID>
  approved_upstream: []
  project_constraints: {}
  change_set: null
  previous_version: null
  flow_control:
    production_authorization_id: FLOW-AUTH-PRJ001-P2-0001
    flow_state: <完整当前 S01 状态包，dispatch 为 CALL_QA>
```

首次创建时 `change_set`、`previous_version` 为 `null`。`REPAIR`/`UPDATE` 必须提供上一版；`UPDATE` 还必须提供已确认 `ChangeSet`，`REPAIR` 必须提供有效 `RepairTicket` 并在内部正规化为最小变更范围。

将信封保存为 UTF-8 JSON 后运行 `skills/_shared/validate_qa_request.ps1 -Path <qa-request.json>`；任何生产 Skill 的 `approved_upstream` 都必须保持数组类型，即使只有一个上游。校验器同时执行 S01 状态校验，并核对当前 `CALL_QA`、待检产物、ArtifactIndex 与已消费生产授权；任何一项不一致都不得进入语义 QA。

## 5. StoryboardImage 与人工确认（仅 VISUAL_TRACK）

> 本节全部内容仅在 VISUAL_TRACK 启用；DIRECT_TRACK 不产生 StoryboardImage 与 ApprovedStoryboardSet。

图片生成阶段输出单镜头 `StoryboardImage`：

```yaml
schema_version: "1.0"
project_id: PRJ-001
flow_authorization_id: FLOW-AUTH-PRJ001-P4-0001
scene_id: SCENE-E01-S03
shot_id: SHOT-E01-S03-005
source_beat_ids: [BEAT-E01-S03-004]
artifact_id: IMG-E01-S03-005
artifact_version: V2
full_id: IMG-E01-S03-005-V2
source_artifact_id: SP-E01-S03-005
source_version: V1
source_full_id: SP-E01-S03-005-V1
status: PASS
stale: false
resource: <实际图片路径或资源定位>
auto_qa:
  qa_mode: STORYBOARD_IMAGE
  verdict: PASS
```

人工确认形成 `ApprovedStoryboardSet`。父集合 `APPROVED` 不能替代条目状态；S05 只接受当前镜头对应、精确版本且非 `STALE` 的 `APPROVED` 条目：

```yaml
schema_version: "1.0"
project_id: PRJ-001
artifact_id: APPROVED-STORYBOARD-E01
artifact_version: V1
full_id: APPROVED-STORYBOARD-E01-V1
status: APPROVED
items:
  - scene_id: SCENE-E01-S03
    shot_id: SHOT-E01-S03-005
    source_beat_ids: [BEAT-E01-S03-004]
    artifact_id: IMG-E01-S03-005
    artifact_version: V2
    full_id: IMG-E01-S03-005-V2
    source_prompt_full_id: SP-E01-S03-005-V1
    status: APPROVED
    stale: false
    resource: <实际图片路径或资源定位>
    approved_by: <Human Director>
    approved_at: <ISO-8601 时间>
    locked_fields: [构图, 景别, 人物位置, 核心道具, 剧情瞬间]
    allowed_changes: [自然动作细节]
```

## 6. 局部失效

- BEAT 变化：只使映射到该 BEAT 的 StoryboardRow 及其 S04、图片、S05 产物 `STALE`。
- StoryboardRow 变化：只使同 `shot_id` 的 S04、图片产物，以及 `covered_shot_ids` 含该 `shot_id` 的段级 S05 产物 `STALE`。
- StoryboardPromptSpec 变化：只使同 `shot_id` 的图片与 S05 产物 `STALE`。
- 图片重新生成或重新选择版本：只使同 `shot_id` 的 S05 产物 `STALE`。
- 无图轨（DIRECT_TRACK）：BEAT/StoryboardRow 变化直接使覆盖镜头的段级 S05 产物 `STALE`。
- EpisodeHandoff 变化：使下一集 PLOT 及下游全部产物 `STALE`。
- 任一直接上游为 `STALE` 时，下游正式生产必须停止。

## 7. RepairTicket 返修票据

票据在既有字段上增加（措辞库见 `_shared/repair-phrases.md`，唯一出处）：

```yaml
repair_type: FULL_REDO | LOCAL_REPAIR | REINFORCE_CONSTRAINT
preserve_scope: <保留内容；并入 locked_fields 语义，返修时不得改动>
must_fix: <必须修正项；逐条落到具体镜号/格号/段号，禁止"修好感觉"式写法>
target_segment_ids: [SEG-E01-002]   # 段级选择器，与镜级选择器并存
```

- `FULL_REDO`：整页/整段重做；`LOCAL_REPAIR`：1–2 镜/格局部返修；`REINFORCE_CONSTRAINT`：方向正确但约束强度不足。
- `must_fix` 每条必须含：定位 + 错误模式 + 修正依据（字段名或上游产物），优先使用 `_shared/repair-phrases.md` 登记短语。

## 8. 版本迁移

- 段级重构后 `VideoPromptSpec` 的 `schema_version` 为 `"2.0"`；旧 `"1.0"` 单镜产物一律标记 `STALE`，按段重产，不做兼容包装。

## 9. EpisodeHandoff 集间交接包

由本集 P7 交付时追加产出，是下一集 P1 的权威上游之一（首集无 HANDOFF）。全部字段必填，禁止按需省略：

```yaml
schema_version: "1.0"
project_id: PRJ-001
artifact_id: HANDOFF-E01
artifact_version: V1
full_id: HANDOFF-E01-V1
episode_id: E01            # 产出方（本集）
next_episode_id: E02
status: PASS
final_frame_state:         # 末段终帧状态
  characters:              # 人物终态：位置/姿态/情绪/外观
    - name: 林晚
      position: 天台边缘，面朝城市
      posture: 站立，右手握手机垂下
      emotion: 强压平静
      appearance_notes: 左袖撕裂，无血迹
  props:                   # 道具终态与归属
    - name: 银色打火机
      location: 林晚右手口袋
      state: 已点燃过一次，油量正常
  scene:                   # 场景终态
    scene_id: SCENE-E01-S06
    scene_main: 天台
    light_base: 夜景冷蓝
    environment_notes: 雨刚停，地面积水
  camera:                  # 摄影机终态（末镜落点）
    final_shot_size: 大远景
    final_position: 天台对面楼体机位
    movement_end: 缓推后静止
  sound:                   # 声音终态
    ambience: 城市低频 + 滴水
    music_state: 主题动机渐弱收尾
    last_line: {speaker: 林晚, text: "……这次我不会再回头。", delivery: 气声自语}
plot_info_state:           # 剧情信息状态：谁知道什么
  - fact: 沈屹已经知道账本在林晚手里
    known_by: [沈屹]
    unknown_by: [林晚]
inherit_required:          # 下集开局必须继承项
  - 林晚的撕裂左袖与天台情绪余韵
  - 打火机在林晚身上
  - 时间紧接：当夜，无时间跳跃
reset_forbidden:           # 禁止重置项
  - 禁止林晚情绪无理由重置为轻松
  - 禁止服装/伤情无交代复原
source_segment_id: SEG-E01-006   # 本集末段
produced_at_stage: P7
```

- `final_frame_state` 的五个子块（characters/props/scene/camera/sound）属性必须存在；无内容时用空数组，不得缺省。
- `inherit_required` / `reset_forbidden` 为数组，至少一条；写"无"视为未填。
- `plot_info_state.known_by` / `unknown_by` 使用角色名，与剧本/PLOT 命名一致。
- EpisodeHandoff 变化：使下一集 PLOT 及下游全部产物 `STALE`（见 §6）。
