# S01 状态与路由契约

## 目录

1. 状态包
2. 核心对象
3. 阶段门禁
4. 状态转移
5. 调度格式
6. 初始化与交付

## 1. 状态包

S01 每次决策读取并写回一个完整状态包。`dispatch` 表示本轮唯一下一动作，不表示尚未实际发生的结果。

```yaml
schema_version: "1.0"
project_manifest: {}
stage_state: {}
decision_ledger: []
artifact_index: []
flow_authorizations: []
pending_repair_tickets: []
run_log: []
dispatch: {}
delivery: []
```

状态包中的所有 `project_id` 必须一致。数组为空时仍保留数组类型。

## 2. 核心对象

### ProjectManifest

```yaml
project_id: PRJ-001
manifest_version: V1
status: ACTIVE # ACTIVE | ON_HOLD | COMPLETE
episode_ids: [E01]
required_scene_ids: [SCENE-E01-S01]
visual_style_lock: LIVE_ACTION_REALISM # LIVE_ACTION_REALISM | GUOMAN_3D_CG；必填，词包见 _shared/style-packs.md
source_materials:
  - source_id: SCRIPT-E01
    source_type: SCRIPT # SCRIPT | DIRECTOR_DECISION | ASSET | CONSTRAINT | OTHER
    version: V1
    status: CURRENT # CURRENT | SUPERSEDED
    locator: file/episode-01.txt
constraints:
  storyboard_image_track: OPTIONAL # REQUIRED | OPTIONAL | DISABLED；默认 OPTIONAL
```

同一 `source_id` 只能有一个 `CURRENT` 版本。P1 至少需要一个可读取的当前 `SCRIPT`；非标准故事材料可先保留真实 `source_type`，由 S02 门禁决定是否需要确认转换。

`visual_style_lock` 必填；旧项目续跑缺锁时进入 `WAITING_HUMAN` 补锁，不得默认猜测。`storyboard_image_track`：`REQUIRED` = 全项目走图轨；`DISABLED` = 全项目 DIRECT_TRACK；`OPTIONAL` = 逐镜头/逐段可选（高风险空间镜头仍走图确认）。

### StageState

```yaml
project_id: PRJ-001
current_stage: P1 # P1..P7
state: READY # READY | WAITING_PRODUCER | WAITING_QA | REPAIRING | WAITING_HUMAN | BLOCKED | COMPLETE
current_artifact_full_id: null
last_qa_verdict: null # null | PASS | REPAIR | HUMAN_GATE
blocking_reasons: []
next_action: CALL_PRODUCER
```

`READY` 表示门禁满足且可发起下一动作；`BLOCKED` 必须有 `blocking_reasons`；`WAITING_HUMAN` 只能调度人工确认或阻断；P7 完成交付后使用 `COMPLETE`。

### DecisionLedger

每项至少包含 `decision_id`、`status`、`source_id`、`scope` 和 `summary`。`status` 只能是 `CONFIRMED`、`PROVISIONAL`、`REJECTED` 或 `CONFLICT`。只有 `CONFIRMED` 可覆盖原剧本计划；`CONFLICT` 必须阻断受影响范围。

### ArtifactIndex

```yaml
- project_id: PRJ-001
  artifact_type: PLOT
  flow_authorization_id: FLOW-AUTH-PRJ001-P1-0001
  artifact_id: PLOT-E01
  artifact_version: V1
  full_id: PLOT-E01-V1
  status: PASS
  current: true
  stale: false
  scene_id: null
  shot_id: null
  source_beat_ids: []
  source_full_ids: [SCRIPT-E01-V1]
  resource: outputs/plot-e01-v1.json
```

`artifact_type` 使用 `PLOT`、`STORYBOARD_TABLE`、`STORYBOARD_PROMPT`、`STORYBOARD_IMAGE`、`APPROVED_STORYBOARD_SET`、`VIDEO_PROMPT`、`EPISODE_HANDOFF` 或 `DELIVERY_PACKAGE`。同一稳定 `artifact_id` 只能有一个 `current: true` 的版本。`full_id` 必须等于稳定 ID 加版本；`STALE` 与 `stale: true` 必须一致。

`EPISODE_HANDOFF` 索引项登记集间交接包（`HANDOFF-E##`），由本集 P7 交付时追加产出；`EpisodeHandoff` 变化使下一集 PLOT 及下游 `STALE`。

`APPROVED_STORYBOARD_SET` 的索引项还要保存逐镜确认索引，不能只登记父集合状态：

```yaml
approved_items:
  - shot_id: SHOT-E01-S01-001
    image_full_id: IMG-E01-S01-001-V2
    status: APPROVED
    stale: false
```

图片本体仍保持自动 QA 的 `PASS`；人工状态写在父集合的逐镜条目中。P6 必须同时核对当前图片 `PASS` 和对应条目 `APPROVED`。

### FlowAuthorization

S01 是唯一可以签发流程授权的单元。每次 `CALL_PRODUCER` 或 `ROUTE_REPAIR` 都创建一个不可复用的授权记录：

```yaml
authorization_id: FLOW-AUTH-PRJ001-P2-0001
project_id: PRJ-001
stage: P2
action: CALL_PRODUCER # CALL_PRODUCER | ROUTE_REPAIR
target: storyboard-table-director
status: ISSUED # ISSUED | CONSUMED | REVOKED
scope:
  episode_ids: [E01]
  scene_ids: [SCENE-E01-S01]
  shot_ids: []
  beat_ids: []
requirements:
  quality_bar: [九列齐备, 运镜必须有触发与落点, 窗口内不重复信息]
  project_constraints: {aspect_ratio: "9:16", model: seedance-2.0, visual_style_lock: LIVE_ACTION_REALISM}
  focus: [跨集承接, 邻镜流畅]
artifact_full_id: null
ticket_id: null
issued_at: 2026-08-16T00:00:00+08:00
```

生产单元只能消费与当前项目、阶段、动作、目标、范围和票据完全一致的 `ISSUED` 授权。产出后 S01 原子地把授权改为 `CONSUMED`，写入精确 `artifact_full_id`，并让产物及 `ArtifactIndex` 都携带相同 `flow_authorization_id`。授权不得跨产物、跨范围或跨版本复用；取消的派工标为 `REVOKED`。

`requirements` 是 S01 随派工显式签发的质量要求与本轮验收标准：`quality_bar`（硬性质量项）、`project_constraints`（项目锁定约束，含风格锁与机型）、`focus`（本轮特别强调项）。生产 skill 开工前读取 `dispatch.requirements`，产物根级以 `requirements_ref` 镜像签发授权 ID；S06 从 `flow_control` 的当前 dispatch 读取同一份 `requirements` 作为裁决依据之一。能力是生产 skill 的（常驻 references），要求是 S01 的（随派工下发），质检只对照"已签发要求 + 权威上游 + 已有事实"。

S06 只接受 S01 的 `CALL_QA`。该调度的 `authorization_id` 必须指向待检产物对应的 `CONSUMED` 生产授权，而不是另行签发一个 QA 授权。

## 3. 阶段门禁

| 阶段 | 允许生产/提交的目标 | 必需权威上游 |
|---|---|---|
| P1 | `PLOT` | 当前可读取剧本；受影响范围无未解决来源冲突；**非首集还需上集当前 `EPISODE_HANDOFF`** |
| P2 | `STORYBOARD_TABLE` | 当前 `PLOT: PASS` |
| P3 | `STORYBOARD_PROMPT`（仅 VISUAL_TRACK） | 目标场次当前 `STORYBOARD_TABLE: PASS`，且所用行均 `PASS` |
| P4 | `STORYBOARD_IMAGE`（仅 VISUAL_TRACK） | 同镜头当前 `STORYBOARD_PROMPT: PASS` |
| P5 | `APPROVED_STORYBOARD_SET`（仅 VISUAL_TRACK） | 所需镜头当前 `STORYBOARD_IMAGE: PASS` |
| P6 | `VIDEO_PROMPT` | **VISUAL_TRACK**：同镜头当前图片本体 `PASS`；父集合逐镜条目 `APPROVED`、非 `STALE`，且精确图片版本一致。**DIRECT_TRACK**：目标段 `covered_shot_ids` 各行 `STORYBOARD_TABLE: PASS`、非 `STALE`，且有上段承接状态（跨集首段为上集 `EPISODE_HANDOFF`） |
| P7 | `DELIVERY_PACKAGE` 或视频任务 | 所需当前 `VIDEO_PROMPT: PASS` |

“当前”同时要求 `current: true`、`stale: false`、状态非 `STALE`，并与生产产物引用的 `source_full_id` 或 `source_full_ids[]` 精确一致。若只满足部分镜头，只调度已满足门禁的镜头；不得用父级 PASS/APPROVED 掩盖行级或条目级失败。

## 4. 状态转移

### 生产与 QA

```text
READY + CALL_PRODUCER
→ WAITING_PRODUCER
→ PRODUCER_RESULT(DRAFT)
→ WAITING_QA + CALL_QA
→ QA_RESULT
```

QA `PASS` 后：P1→P2、P2→P3、P3→P4、P4→P5、P6→P7；DIRECT_TRACK 下 P2 的 QA `PASS` 后直接进 P6。P4 的自动 QA `PASS` 只进入 P5，绝不直接产生 `APPROVED`。

QA `REPAIR` 后进入 `REPAIRING`，保存票据并将 `ROUTE_REPAIR` 指向票据的真实 `return_to`；修复产物必须创建新版本或按目标 Skill 契约递增局部版本，然后用同一 `qa_mode` 复检。

QA `HUMAN_GATE` 后进入 `WAITING_HUMAN`。只有用户提供可追踪的确认结论后才恢复，不把“继续”“可以”“优化一下”等含糊表达解释为具体字段授权。

### 人工确认

P5 接受逐镜 `APPROVE` 或 `REJECT`。`APPROVE` 锁定精确图片版本；`REJECT` 必须记录可核查原因，并根据真实归属回到 P4 生图、P3 Prompt、P2 分镜或 P1 剧情。所需镜头全部为当前 `APPROVED` 后进入 P6。

### 上游变化

收到 `UPSTREAM_CHANGED` 时先创建新上游版本，再执行局部失效；把 `current_stage` 回退到最早需要重新生产或 QA 的阶段。旧版本保留在索引中但不得作为当前权威上游。

## 5. 调度格式

```yaml
dispatch:
  action: CALL_PRODUCER # CALL_PRODUCER | CALL_QA | ROUTE_REPAIR | REQUEST_HUMAN_APPROVAL | MARK_STALE | DELIVER | BLOCK | NONE
  target: script-plot-progression
  qa_mode: null
  artifact_full_id: null
  ticket_id: null
  authorization_id: FLOW-AUTH-PRJ001-P1-0001
  scope:
    episode_ids: [E01]
    scene_ids: []
    shot_ids: []
    beat_ids: []
  reason: 当前剧本已可读取，P1 门禁满足
```

固定目标：

| 动作/阶段 | `target` | `qa_mode` |
|---|---|---|
| P1 生产 | `script-plot-progression` | `null` |
| P2 生产 | `storyboard-table-director` | `null` |
| P3 生产 | `storyboard-image-prompt-director` | `null` |
| P4 生产 | `storyboard-image-generation` | `null` |
| P1/P2/P3/P4/P6 QA | `short-drama-unified-qa` | 对应模式 |
| P5 | `human-director` | `null` |
| P6 生产 | `video-prompt-director` | `null` |
| P7 | `delivery` 或明确视频平台 | `null` |

`CALL_PRODUCER` 和 `ROUTE_REPAIR` 必须携带匹配的 `ISSUED authorization_id`；`CALL_QA` 必须携带待检 `artifact_full_id` 和该产物的 `CONSUMED authorization_id`；`MARK_STALE` 必须有非空受影响范围；`BLOCK` 必须说明缺失证据或冲突。生产或 QA 请求缺少合法授权时，固定返回 `FLOW_DISPATCH_REQUIRED`，不得继续到内容生成或裁决。

## 6. 初始化与交付

新项目初始化为 P1。只登记用户实际提供的源材料、约束和确认决定；若没有可读取故事源，设为 `BLOCKED` 并请求材料。每次状态转移追加 `RunLog`，至少记录 `event_id`、时间、输入事件、旧阶段/状态、新阶段/状态、dispatch 和影响的 `full_id`。

P7 交付包只引用已经 `PASS` 的当前 VideoPromptSpec，并保留从视频 Prompt →（VISUAL_TRACK：人工确认图片 → 分镜 Prompt →）StoryboardRow → BEAT 的可追踪链。外部视频平台执行不在当前 Skill 集群的自动能力内时，交付可投喂提示词包并明确停点。

P7 交付时追加产出本集 `EpisodeHandoff`（`HANDOFF-E##`，`artifact_type: EPISODE_HANDOFF`）：末段终帧人物/道具/场景/摄影机/声音状态 + 剧情信息状态（谁知道什么）+ 下集开局必须继承项 + 禁止重置项。非首集项目的 P1 门禁必须登记上集 Handoff（首集除外）；Handoff 变化使下一集 PLOT 及下游 `STALE`。
