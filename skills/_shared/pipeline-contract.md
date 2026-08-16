# S02-S05 公共流水线契约

## 1. 规范标识

所有阶段必须原样继承 `project_id`。集号和场号均使用至少两位数字。

```text
scene_id  = SCENE-E{episode}-S{scene}          例：SCENE-E01-S03
beat_id   = BEAT-E{episode}-S{scene}-{beat}    例：BEAT-E01-S03-004
shot_id   = SHOT-E{episode}-S{scene}-{shot}    例：SHOT-E01-S03-005
```

`shot_id` 从 `scene_id` 派生时，删除固定前缀 `SCENE-`，再追加三位镜头序号；禁止生成 `SHOT-SCENE-...`，也禁止把 `SCENE-E01-S03` 缩写成无集号的 `S03`。

规范稳定产物 ID：

```text
PLOT-E01
STORYBOARD-E01-S03
SHOT-E01-S03-005
SP-E01-S03-005
IMG-E01-S03-005
APPROVED-STORYBOARD-E01
VP-E01-S03-005
```

所有版本化产物统一携带：

```yaml
schema_version: "1.0"
project_id: PRJ-001
artifact_id: <不带版本的稳定 ID>
artifact_version: V1
full_id: <artifact_id>-<artifact_version>
status: DRAFT | CHECKING | REPAIR | PASS | HUMAN_GATE | APPROVED | STALE
```

直接上游只有一个时增加 `source_artifact_id`、`source_version`、`source_full_id`；有多个权威上游时使用 `source_artifacts` 数组，每项仍拆分稳定 ID、版本和完整 ID。不得把完整 ID 填入 `artifact_id`。

## 2. 标准链路

```text
PlotProgressionSpec(PASS)
→ StoryboardTable + StoryboardRow(PASS)
→ StoryboardPromptSpec(PASS)
→ StoryboardImage(PASS)
→ ApprovedStoryboardSet(APPROVED，且当前图片条目 APPROVED)
→ VideoPromptSpec(DRAFT)
```

生产 Skill 只写 `DRAFT` 或门禁失败时的 `HUMAN_GATE`。独立 QA 写 `CHECKING/PASS/REPAIR/HUMAN_GATE`；人工确认阶段写 `APPROVED`。

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
```

首次创建时 `change_set`、`previous_version` 为 `null`。`REPAIR`/`UPDATE` 必须提供上一版；`UPDATE` 还必须提供已确认 `ChangeSet`，`REPAIR` 必须提供有效 `RepairTicket` 并在内部正规化为最小变更范围。

将信封保存为 UTF-8 JSON 后运行 `skills/_shared/validate_qa_request.ps1 -Path <qa-request.json>`；任何生产 Skill 的 `approved_upstream` 都必须保持数组类型，即使只有一个上游。

## 5. StoryboardImage 与人工确认

图片生成阶段输出单镜头 `StoryboardImage`：

```yaml
schema_version: "1.0"
project_id: PRJ-001
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
- StoryboardRow 变化：只使同 `shot_id` 的 S04、图片、S05 产物 `STALE`。
- StoryboardPromptSpec 变化：只使同 `shot_id` 的图片与 S05 产物 `STALE`。
- 图片重新生成或重新选择版本：只使同 `shot_id` 的 S05 产物 `STALE`。
- 任一直接上游为 `STALE` 时，下游正式生产必须停止。
