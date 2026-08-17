# Video-Drama 集群 V2 改造方案

> 分支：`dev/rework`　基线：`main`（全绿）
> 目标：剖析剧本 → 直接产出"剧情流畅 + 镜头流畅"的镜头表 → 直接产出视频提示词。
> 分镜图模块降级为可选；上下文流畅度检测覆盖跨集（集↔集）与多镜头窗口（±2 镜）；
> 最终提示词结构对齐《参考素材说明.txt》（15 秒段、多镜头、十五节）。
> 最终目的：AI 短剧符合视听语言逻辑、短剧节奏与短剧运镜，接近真人实拍。

---

## 0. 四个关键设计决策

### 决策 1：分镜图轨道从"必经"改为"可选"

现状链路：`S03 分镜表 → S04 图Prompt → P4 生图 → P5 人工 APPROVED → S05 视频Prompt`（S05 硬门禁要求 `ApprovedStoryboardSet APPROVED`）。

改为双轨：

- **VISUAL_TRACK（有图轨）**：与现状完全一致，S04→P4→P5 全部保留。
- **DIRECT_TRACK（无图轨）**：S03 分镜表行 `PASS` 后直接进入 S05；S05 的 0 秒状态来源从"APPROVED 图片 + 锁定上游"改为"锁定上游 + 上一段承接状态"，`start_state.source_status` 新增枚举 `LOCKED_UPSTREAM_PLUS_PREVIOUS_END_STATE`。

轨道选择挂在项目级开关上：

```yaml
# ProjectManifest.constraints
storyboard_image_track: REQUIRED | OPTIONAL | DISABLED   # 默认 OPTIONAL
```

`REQUIRED` = 现状；`DISABLED` = 全项目不走图；`OPTIONAL` = 逐镜头/逐段可选（例如高风险空间镜头仍走图确认）。

### 决策 2：引入"段"（Segment）—— 一个视频 Prompt = 15 秒段 = 段内多镜头

参考文档的结构是"一段 15 秒内含镜头01、02、03…"，与现状"一镜一 Prompt"不同。引入段层：

```text
segment_id = SEG-E{episode}-{序号}      例：SEG-E01-002
```

- S03 分镜表**不改粒度**（仍一镜一行，九列表不变）。
- S05 改为**按段组装**：S01 派工时给出本段覆盖的连续 `shot_ids`；S05 把 1–4 个相邻镜头组织进一条 15 秒（2.0）或 30 秒（2.5）时间轴。
- 段内镜头之间是"切镜"，段间是"承接"（上段终帧 → 本段 0.0 秒直接继承）。
- `VideoPromptSpec` 增加 `segment_id` 与 `covered_shot_ids[]`；`shot_id` 字段保留为段内首镜（兼容）或改为数组（破坏性，倾向新增字段而非改旧字段）。

### 决策 3：跨集连续性 —— 新增集间交接产物 `EpisodeHandoff`

每集 P7 交付时追加产出 `EpisodeHandoff`（集间交接包）：

```yaml
artifact_id: HANDOFF-E01
包含：末段终帧人物/道具/场景/摄影机/声音状态 + 剧情信息状态（谁知道什么）+ 下集开局必须继承项 + 禁止重置项
```

- 下一集 P1 输入门禁：必须登记上一集 `EpisodeHandoff`（首集除外），S02 把它作为权威来源参与第一 BEAT 的 `start_state`。
- S01 `ArtifactIndex.artifact_type` 新增 `EPISODE_HANDOFF`；阶段门禁表加"首集外的 P1 需要上集 HANDOFF"。
- 失效传播加一行：`EpisodeHandoff 变化 → 下一集 PLOT 及下游 STALE`。

### 决策 4：流畅度检测从"相邻 ±1"升级为"窗口 ±2"

现状：`continuity_checks` 只有 `incoming/outgoing`（紧邻两段双向比较）。

升级为窗口检查：

```yaml
continuity_checks:
  window: 2                       # 向前看 2 段、向后看 2 段
  incoming:  ...                  # 保留：与紧邻段的严格双向签名比较
  outgoing:  ...
  window_checks:                  # 新增：隔段弱规则比较
    - neighbor_segment_id: SEG-E01-001   # distance=2
      distance: 2
      checked_fields: [CHARACTER_IDENTITY, PROP_OWNERSHIP, WORLD_ANCHORS, KNOWLEDGE_STATE]
      mismatches: []
```

- distance=1 维持严格签名一致；distance=2 用**弱规则**：允许中间段合理演化，禁止矛盾（人物身份/伤势自愈/道具瞬移/场景锚点跳变/信息状态倒退）。
- S03 层同样加窗口自检：连续 3 镜内不得无理由越轴、不得重复信息、节奏不得失控。
- QA 两份清单（`qa-storyboard-table.md`、`qa-video-prompt.md`）各加窗口流畅度硬检规则族。

---

## 1. 分文件改动清单

### 1.1 `_shared/`（公共契约与校验器）

| 文件 | 改动 |
|---|---|
| `pipeline-contract.md` | §2 标准链路改双轨（图轨可选）；新增 `segment_id`、`HANDOFF-E##` 规范 ID；§5 图片章节标注"仅 VISUAL_TRACK"；§6 失效矩阵加无图链行（BEAT/Row 变化直接 STALE S05）与跨集行 |
| `validate_qa_request.ps1` | `VIDEO_PROMPT` 模式下：无图轨不再强制 `APPROVED` 分镜图；校验 `segment_id` 与 `covered_shot_ids` |
| `validate_approved_storyboard.ps1` | 不变（图轨仍用） |

### 1.2 S01 `short-drama-flow-director`

| 文件 | 改动 |
|---|---|
| `references/state-and-routing-contract.md` | P6 门禁改双轨（VISUAL：原三层核对；DIRECT：`STORYBOARD_TABLE PASS + 行 PASS + 上段承接状态`）；`artifact_type` 加 `EPISODE_HANDOFF`；P1 门禁加"非首集需上集 HANDOFF"；dispatch target 表不变 |
| `references/approval-and-staleness.md` | 人工确认章节标注"仅 VISUAL_TRACK"；失效矩阵同步契约改动 |
| `scripts/validate_flow_state.ps1` | 支持双轨门禁判定与 EPISODE_HANDOFF 索引项 |

### 1.3 S02 `script-plot-progression`

| 文件 | 改动 |
|---|---|
| `references/continuity-rules.md` | 增加跨集连续：首 BEAT 的 `start_state` 必须可追溯到上集 `EpisodeHandoff` 或显式标记时间跳跃 |
| `references/source-decision-rules.md` | `source_type` 增加 `EPISODE_HANDOFF` 为合法权威来源 |
| `scripts/validate_plot_progression.ps1` | 放行 `EPISODE_HANDOFF` 来源类型 |

### 1.4 S03 `storyboard-table-director`（视听语言与短剧节奏强化的主战场）

| 文件 | 改动 |
|---|---|
| `references/shot-size-camera-rules.md` | 运镜动机硬规则："摄影机运动只在人物动作、视线变化、信息揭示或情绪爆点触发；快速运镜结束立即恢复稳定"；景别→焦段→光圈联动表（对齐参考文档§11） |
| `references/action-splitting-rules.md` | 短剧节奏规则：开场 hook 时限、反转密度、单镜信息容量；窗口自检（连续 3 镜不重复信息、不无理由越轴） |
| `references/storyboard-table-standard.md` | `shot_map` 增加可选 `segment_hint`（建议分段边界），供 S01/S05 组段参考 |
| 校验器 | `validate_storyboard_artifact.ps1` 放行 `segment_hint` |

### 1.5 S04 / P4 / P5（图轨）

不改规则本体，全部标注"仅 VISUAL_TRACK 启用"。S04 产物在 DIRECT_TRACK 下不生成。

### 1.6 S05 `video-prompt-director`（改动最大）

| 文件 | 改动 |
|---|---|
| `references/input-gates-and-routing.md` | 输入门禁双轨化；段范围输入（`covered_shot_ids`）；跨集首段的 `PREVIOUS_END_STATE` 允许来自上集 `EpisodeHandoff` |
| `references/video-prompt-contract.md` | **重构**：`segment_id` + `covered_shot_ids[]`；`start_state.source_status` 加枚举；`continuity_checks` 加 `window/window_checks`；`body_sections` 从 5 区改为对齐参考文档的十五节（见 §2）；对白节支持有口型对白/内心OS/无对白三种块 |
| `references/prompt-assembly-rules.md` | 段内多镜头时间轴规则（每镜头：摄影参数→画面空间→锚点→动作表演→运镜焦点）；对白必须写在对应镜头时间轴内，禁止统一放文末 |
| `references/continuity-rules.md` | 窗口 ±2 规则与弱规则判定标准 |
| `references/optics-and-camera-rules.md` | 对齐参考文档§11 焦段/光圈范围表 |
| `scripts/validate_video_prompt.ps1` | 段结构、窗口字段、十五节镜像检查 |
| `scripts/validate_body.ps1` | 新分区顺序与纯净度（保留 Mixed 槽位、禁字幕/BGM、污染词检查） |
| `scripts/validate_prompt_sequence.ps1` | **序列校验改为段序列**：段间承接签名 + 窗口 ±2 弱规则比较 |

### 1.7 S06 `short-drama-unified-qa`

| 文件 | 改动 |
|---|---|
| `references/qa-video-prompt.md` | 重写：段结构检查、段内多镜头时间轴、窗口流畅度硬检、跨集承接检查、十五节纯净度、对白时间轴位置 |
| `references/qa-storyboard-table.md` | 加窗口流畅度（3 镜窗口）与节奏/视听语言规则族 |
| `references/common-protocol.md` | RepairTicket 范围字段表加段级选择器（`target_segment_ids`） |
| `references/regression-and-routing.md` | 失效传播表加段级与跨集行 |
| `scripts/validate_qa_response.ps1` | 放行段级工单字段 |

### 1.8 测试

- 六个既有测试脚本全部更新（双轨、段结构、窗口）。
- 新增用例：无图轨全流程 PASS；跨集 HANDOFF 缺失时 P1 阻断；窗口 distance=2 矛盾被拒；段内多镜头时间轴非法被拒。

---

## 2. S05 `body` 新结构（对齐参考文档十五节）

```text
一、参考素材说明（{{Mixed x}} 槽位；分镜图/站位图仅 VISUAL_TRACK）
二、参考素材使用规则
三、统一视觉与摄影基准（9:16、ARRI Alexa 35、24fps、180°快门、无字幕/BGM）
四、场景空间锚点（Scene ID、左右前后固定关系、人物始终位置、主关系轴、摄影机锚点）
五、承接上一段 15 秒（上段终帧 → 本段 0.0 秒直接继承；跨集首段读 EpisodeHandoff）
六、镜头时间轴（镜头01｜0.0—X.X秒：摄影参数→画面空间→视角锚点→动作与表演→运镜与焦点）
七、时间轴内对白（有口型对白 / 内心OS / 无对白 三种块；含停顿、重音、手势、留白）
八、镜尾状态（段内每镜终帧；下一镜直接继承，禁止重置）
九、段内后续镜头重复结构（直到 15/30 秒结束）
十、全段光线与色彩
十一、全段摄影规格（焦段/光圈按镜头类型）
十二、声音设计（无 BGM；方向与画面空间一致）
十三、全段连续性约束
十四、负面约束
十五、本段最终承接状态（供下一段读取）
```

结构化字段仍是事实主源，十五节 `body` 是渲染镜像；二者冲突即不合格（沿用现有不变量）。

---

## 3. 优先级与实施顺序

1. **P0 双轨化**（决策 1）：契约 + S01 + S05 门禁 + QA 门禁 + 校验器。改动面可控，立即解锁"无图直出"。
2. **P0 段结构**（决策 2）：S05 契约重构 + 三个校验器 + QA 清单。这是参考文档落地的核心。
3. **P1 窗口检测**（决策 4）：sequence 校验器 + S03/S05 规则 + QA 规则族。
4. **P1 跨集**（决策 3）：EpisodeHandoff 产物 + S01 索引/门禁 + S02 来源。
5. **P2 视听语言强化**：S03 规则文件细化（不影响结构，随时可做）。

每一步完成都跑六个回归脚本保持绿色。

## 4. 明确不动的部分

- 九列分镜表列序、`shot_map` 结构、`storyboard_row_version` 语义。
- FlowAuthorization 签发/消费/复核链条（架构核心，不动）。
- `source_beat_ids` 数组、`full_id` 不变量、状态枚举。
- S04 图轨全部能力（只是不再必经）。
