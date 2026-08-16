# 输入门禁与任务路由

## 目录

1. 输入包
2. 状态门禁
3. 来源优先级
4. 任务模式
5. 生成任务类型
6. 单镜头范围
7. 阻断与返回路由
8. 控制层兼容

## 1. 输入包

S05 的正式输入至少包含：

```yaml
project_id: PRJ-001
scene_id: SCENE-E01-S01
shot_id: SHOT-E01-S01-003
task_mode: CREATE                # CREATE | REPAIR | UPDATE

target:
  model: seedance-2.0
  model_rule_profile:
    rule_id: SD20-V3.4
    status: VERIFIED
    source: <锁定规则来源>
  product_flow: <当前产品模式>
  generation_task: MULTIMODAL_REFERENCE
  aspect_ratio: "9:16"
  duration_seconds: 8
  delivery_mode: PROMPT_ONLY

approved_storyboard_set:
  artifact_id: APPROVED-STORYBOARD-E01
  artifact_version: V1
  full_id: APPROVED-STORYBOARD-E01-V1
  status: APPROVED
  items:
    - scene_id: SCENE-E01-S01
      shot_id: SHOT-E01-S01-003
      source_beat_ids: [BEAT-E01-S01-002]
      artifact_id: IMG-E01-S01-003
      artifact_version: V2
      full_id: IMG-E01-S01-003-V2
      status: APPROVED
      stale: false
      resource: <实际图片路径或可读取资源>
      source_prompt_full_id: SP-E01-S01-003-V1
      approved_by: <Human Director>
      approved_at: <时间>
      locked_fields: [构图, 景别, 人物位置, 核心道具, 剧情瞬间]
      allowed_changes: [自然动作细节]

plot_progression:
  full_id: PLOT-E01-V1
  status: PASS
  stale: false
  source_beat_ids:
    - BEAT-E01-S01-002

storyboard_row:
  parent_full_id: STORYBOARD-E01-S01-V2
  scene_id: SCENE-E01-S01
  shot_id: SHOT-E01-S01-003
  source_beat_ids: [BEAT-E01-S01-002]
  storyboard_row_version: V2
  row_full_id: SHOT-E01-S01-003-V2
  status: PASS
  stale: false

dialogue_source:
  source_id: SCRIPT-E01-V1
  source_range: <行号/页码/段落号>
  dialogue_policy: EXACT_SOURCE_TEXT   # 无对白时为 NO_DIALOGUE
  exact_lines: []

asset_ledger:
  version: V3
  bindings: []

previous_end_state:
  state_id: PE-E01-S01-002-V1
  state_kind: PLANNED
  source_status: LOCKED_UPSTREAM
  fields: {}

project_constraints: {}
previous_artifact: null
repair_ticket: null
change_set: null
```

输入可以采用 YAML、JSON 或宿主系统对象，但字段语义必须稳定。不得仅提供“用上一版”“按确认图”而缺少精确 ID 和版本。

## 2. 状态门禁

正式生产需同时满足：

| 输入 | 必需状态 | 其他要求 |
|---|---|---|
| `ApprovedStoryboardSet` 当前图片条目 | `APPROVED` | 父集合与条目均已批准；精确版本、可读取、非 `STALE`、范围等于当前 `shot_id` |
| 剧情演进 | `PASS` | 包含当前 `beat_id`、非 `STALE` |
| 分镜表行 | `PASS` | 唯一映射当前 `shot_id`、非 `STALE` |
| 原始对白 | 可定位 | 有对白时逐字文本、说话人和范围明确；无对白明确写 `NO_DIALOGUE` |
| 资产台账 | 有版本 | 人物/场景/关键道具和 Mixed 映射可追踪 |
| 模型规则 | `VERIFIED` | 模型、产品模式和任务类型在支持范围内 |
| 上一镜状态 | 有来源标签 | 未知字段显式写 `UNKNOWN`，不得补猜 |

`ApprovedStoryboardSet.status: APPROVED` 不能只写在父集合上；当前图片条目必须带自己的 `full_id`、`source_beat_ids`、来源分镜 Prompt 版本和批准记录。

以下任一情况禁止输出可投喂 `body`：

- 图片是 `DRAFT`、`PASS`、`HUMAN_GATE`、`STALE` 或仅“看起来确认过”。
- 图片、剧情或分镜表的 `shot_id` 不一致。
- 模型规则只写模型名，没有已验证规则版本。
- 原始对白缺字、说话人不明或两份锁定来源互斥。
- 关键人物/道具缺资产事实，或槽位号是推测的。
- 当前动作必须改变已确认构图、镜头数或时长才可执行。

## 3. 来源优先级

对不同事实分别裁决，不使用单一来源覆盖全部字段：

```text
用户当前明确要求与最新确认
→ 项目锁定事实和 CONFIRMED ChangeSet
→ 人工 APPROVED 分镜图的可见首帧事实
→ PASS 分镜表的景别、机位、时长与运镜
→ PASS 剧情演进和原始对白的事件因果与文本
→ 已验收视频的实际清洁末帧可见事实
→ 资产/连续性台账与计划镜尾
→ 目标模型已验证规则
→ 标为 DERIVED_EXECUTION 的执行参数
→ UNKNOWN
```

适用限制：

- 人工分镜图锁定当前首帧构图，但不能改写原始对白或剧情因果。
- 分镜表锁定拍法，但不能推翻图片已批准的实际首帧位置；两者冲突时进入 `HUMAN_GATE`。
- 已验收上一段末帧只覆盖可见的实际状态；若它含已识别生成错误，不把错误升级为事实。
- 模型规则只约束表达格式和能力，不生成项目剧情事实。
- `DERIVED_EXECUTION` 只允许补齐不改变上游语义的光学/执行参数。

## 4. 任务模式

### CREATE

从有效上游生成 `V1`。`previous_artifact`、`RepairTicket` 和 `ChangeSet` 应为空。

### REPAIR

根据 `QA:VIDEO_PROMPT` 的 `RepairTicket` 修复已有产物。必须提供目标上一版本，且 `ticket.artifact_id` 与其 `video_prompt_id/full_id` 一致。

### UPDATE

根据状态为 `CONFIRMED` 的 `ChangeSet` 更新已有产物。必须提供影响范围、开放字段、锁定字段和来源决定 ID。

不得把普通“优化一下”自动当作 UPDATE。若用户没有明确开放已锁字段，先确认范围或保持原锁。

## 5. 生成任务类型

使用枚举并根据模型 reference 组装正文：

| 类型 | 条件 | S05 行为 |
|---|---|---|
| `MULTIMODAL_REFERENCE` | 图/音/视频作为参考生成新视频 | 常规已确认分镜图生视频流程 |
| `EDIT_VIDEO` | 有真实源视频及允许编辑范围 | 明确“严格编辑视频1”，未点名内容保持不变 |
| `EXTEND_FORWARD` | 模型实际收到源视频 | 明确“向后延长视频1”，0 秒状态来自源视频尾部 |
| `EXTEND_BACKWARD` | 模型实际收到源视频 | 明确“向前延长视频1”，目标接点来自源视频开头 |
| `COMPOSITE` | 同时参考一个素材并编辑另一个视频 | 分别声明参考对象与被编辑对象，禁止角色/槽位串绑 |

编辑、延长和组合任务仍不能绕过当前镜头的上游批准与模型能力门禁。没有实际源视频时不得使用延长句式。

## 6. 单镜头范围

`VideoPromptSpec.shot_id` 为单数，因此 V1 采用硬规则：

- 一份规格只对应一行 PASS 分镜表、一个 APPROVED 图片版本和一个 `shot_id`。
- 时间轴可以分成若干连续区间，但不能新增切镜；主运镜继承该分镜行。
- 批量交付只是多个完整规格的有序集合，不是一个 body。
- 整集/整场未拆镜时返回 S01/S03，不在 S05 输出分段制作清单。

若未来产品决定“一 Prompt 对多个镜头”，必须先升级 schema；不得在 V1 里偷偷加入 `shot_ids`。

## 7. 阻断与返回路由

| 问题 | 结果/返回位置 |
|---|---|
| 分镜图未人工批准、图片版本错误 | 分镜图人工确认阶段 |
| 图片畸形、错人、错手、道具错误 | 分镜图生成/QA 阶段 |
| 图片与剧情/分镜表互斥 | `HUMAN_GATE` |
| 镜头设计、时长或动作容量错误 | S03 分镜表导演，并使相关下游 `STALE` |
| 剧情、台词或因果错误 | S02，并按影响范围传播 `STALE` |
| 资产/槽位缺失 | 资产台账阶段 |
| 模型/产品模式规则缺失 | `HUMAN_GATE`，补充已验证模型配置 |
| Prompt 表达或连续性错误 | S05 通过 RepairTicket 修复 |
| 同类修复连续两次失败 | `HUMAN_GATE` |

阻断输出至少包含：`status`、`shot_id`、`blocked_fields`、`evidence`、`return_to` 和 `required_input`。

## 8. 控制层兼容

V3.6 的 A 颜色映射、B1/B2 白模和实际末帧状态卡是控制层，不是 S05 的第二主产物。

- `PROMPT_ONLY`：集群默认；读取已批准图片和有效连续性资料，输出 `VideoPromptSpec`。
- `QUICK_PREFLIGHT`：上游可在同轮提供已完成控制层；S05 只读取其 ID/状态。
- `STRICT_PREFLIGHT`：上游白模尚未复核时 S05 暂停；复核通过后才继续。

B1 不得绑定 Seedance。B2 只有实际生成、检查通过、绑定并取得真实 Mixed 编号后才可进入 `reference_bindings`。白模身份色、低模脸、摄影机代理、箭头、文字和白盒材质永不进入真人视频正文。
