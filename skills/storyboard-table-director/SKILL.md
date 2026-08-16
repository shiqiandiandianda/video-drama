---
name: storyboard-table-director
description: 将已通过 QA 的 PlotProgressionSpec 转换为导演和制作人员可审阅的固定九列横向 StoryboardTable。用于用户要求制作、续做、改写或返修 AI 短剧分镜表、导演分镜、镜头拆分、景别机位运镜设计，或明确提到 S03 分镜表导演时；仅处理分镜表阶段，不生成分镜图、生图提示词或视频提示词。
---

# S03 分镜表导演

## 目标

把已通过的连续剧情 BEAT 转成足够且克制、可拍摄、可追踪的导演分镜。公开正文固定使用九列横向表，一镜一行；把内部 ID、版本、状态和 BEAT 映射放在表外 sidecar。

## 中央流程硬门禁

本 Skill 只能由 S01 `$short-drama-flow-director` 的当前 `CALL_PRODUCER` 或 `ROUTE_REPAIR` 调度进入。开始拆镜前，必须读取完整 S01 状态包并核对 `dispatch.authorization_id` 对应唯一 `ISSUED FlowAuthorization`，其 `project_id`、`stage: P2`、`action`、`target: storyboard-table-director`、范围和 `ticket_id`（返修时）必须与本任务完全一致。

把状态包保存为 UTF-8 JSON，先运行 `..\short-drama-flow-director\scripts\validate_flow_state.ps1 -Path <flow-state.json>`；脚本通过且当前 dispatch 精确指向本 Skill 后才能继续。

缺失或不匹配时立即停止，只输出 `FLOW_DISPATCH_REQUIRED`、不匹配证据和 `return_to: short-drama-flow-director`；不得生成分镜表、分镜行或局部内容。合法产物根级必须原样写入 `flow_authorization_id`。

## 读取规则

正常生成前，读取：

- [公共流水线契约](../_shared/pipeline-contract.md)：规范 ID、版本、状态传播、BEAT 映射和 QA 信封。
- [分镜表标准](references/storyboard-table-standard.md)：输入、字段、编号和交付格式。
- [景别机位规则](references/shot-size-camera-rules.md)：景别、机位、运镜、轴线和空间连续性。
- [动作拆分规则](references/action-splitting-rules.md)：动作链、表演、对白和时长容量。

处理 RepairTicket、局部修改或准备 QA 时，再读取 [QA 与返修](references/qa-and-repair.md)。需要校准格式或失败路由时，读取 [通过样例](references/examples/passing-example.md) 和 [门禁与失败样例](references/examples/gate-and-failure-examples.md)。

## 输入门禁

先执行以下检查，未通过时停止生成正式分镜表：

1. 要求 `PlotProgressionSpec.status == PASS`；拒绝 `DRAFT`、`CHECKING`、`REPAIR`、`HUMAN_GATE`、`STALE` 或状态缺失的输入。
2. 确认每个 BEAT 至少包含 `beat_id`、`source_ranges`、四维 `start_state`、对象型 `trigger`、顺序 `actions`、`reactions`、数组型 `dialogue`、`emotion_change`、四维 `end_state` 和 `continuity`。来源确实没有对白或他人反应时使用空数组；不得把正式 S02 结构降格成旧示例的字符串或单对象形式。
3. 读取人物、场景、道具资产，项目画幅，视觉风格与真实度，已确认的导演镜头约束，以及前后镜连续性状态。
4. 把“个人想法、建议、草稿、暂定、导演构思”视为未锁定来源；若它与已确认事实冲突，返回 `HUMAN_GATE`，不得自行裁决。
5. 禁止使用任何 `STALE` 上游产物。

门禁失败时，只返回：当前状态、可验证证据、缺失或冲突项、需要的最小补充、建议路由。不要用假设补齐后继续生产。

## 执行流程

### 1. 冻结剧情事实

按来源优先级锁定原剧情因果、人物、顺序和原始对白；只允许明确确认的导演决定覆盖原计划。建立内部 BEAT 台账，逐项记录：

- 起点、触发、动作顺序、反应、结果；
- 人物左右、纵深、朝向、视线和距离；
- 服装、发型、伤口、手持物和关键道具状态；
- 门窗、桌椅、通道、光源等场景锚点；
- 前镜镜尾与本镜镜头开端必须继承的状态。

发现剧情结构断裂、台词冲突或 BEAT 无法连接时，返回 S02，不在 S03 改写剧情。

### 2. 为每个 BEAT 设计镜头

先定观众在这一刻的一个主要情绪，最多加一个辅助情绪，再选择镜头。每个 BEAT 至少对应一镜；镜头数量以观众能看懂“开始—过程—结果”为准，不为术语或覆盖率机械切碎。

逐镜完成内部判断：

1. 指定唯一画面重点和剧情功能。
2. 指定主体构图位置、前中后景、动作空间、视线落点与进出方向。
3. 选择能承载当前信息量的景别。
4. 选择能表达关系且不越轴的实体机位。
5. 优先固定；确有注意力转移时才使用一个主要运镜，并写清动作触发、路径、落点和停顿。
6. 让有动机的光源、明暗分区和色彩气氛服务主情绪；只把影响下游执行或连续性的结论写进表格。
7. 把抽象情绪改写为视线、呼吸、重心、手指、嘴角、喉结、衣料、停顿或听话人反应。
8. 让大动作具备意图、支撑与重心、动力链、接触反馈、惯性和恢复；不要把结果状态冒充完整动作。
9. 估算动作、对白和反应所需时间；明显装不下时延长或拆镜。

内部可以判断焦段、景深、主光方向和生成风险，但公开九列表不新增模型参数列。只有已锁定且影响连续性的摄影限制，才简写进“导演备注”。

### 3. 维护连续性

每次切镜重新锚定当前主体，不写“承接上一镜”来代替初始状态。双人正反打锁定双方左右、朝向、视线、关系轴和各自身后背景；动态对象另锁起点、路径、终点。三人以上、复杂动作、正反打或空间高风险镜头，在导演备注标记需要站位图或白模确认。

### 4. 渲染九列表

严格按以下列序输出，不增删、不改名：

```text
场景｜镜号｜景别｜机位｜运镜｜画面描述｜秒数/s｜人物情绪/细节动作｜导演备注
```

遵守：

- 一镜一行；镜号在场次内连续。
- “画面描述”按“环境或构图位置 → 初始状态 → 触发 → 连续过程 → 结果 → 对白或声音”书写。
- 保留原始对白及说话人；不得润色、补写或改配。
- 不把备选方案、教学解释、检查清单或内部七模块卡塞进单元格。
- 不写生图模型参数、素材槽位、负面提示词、Seedance 时间轴或视频 Prompt。

### 5. 自检并交付 QA

先把包含元数据、规范 `shot_map` 和九列 `columns` 的正式机器产物保存为 UTF-8 JSON，并运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_storyboard_artifact.ps1" -Path <storyboard.json>
```

若同时渲染 Markdown，继续运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_storyboard.ps1" -Path <storyboard.md>
```

先把 `<SKILL_DIR>` 解析为本 `SKILL.md` 所在目录；不要假设当前工作目录就是 Skill 目录。JSON 是正式产物，Markdown 是由 `shot_map[].columns` 渲染的人类视图。两个脚本通过只代表机械结构合格，不能替代轴线、表演和剧情人工判断。随后按 [QA 与返修](references/qa-and-repair.md) 完成语义自检，并提交完整的统一 QA 输入；生产 Skill 不得自行把结果声明为 `PASS`。

## 输出契约

一次性交付当前阶段完整结果，顺序如下：

1. 简短的门禁与来源说明；
2. 表外 `StoryboardTable` 追踪元数据，初始 `status: DRAFT`；
3. 固定九列的人类可读横向表；
4. 表外规范 `shot_map`，每项同时保存九列正文、唯一 `shot_id`、独立 `storyboard_row_version` 和一个或多个 `source_beat_ids`；
5. 总镜数、总时长、场次数和待人工判断项；
6. 完整的统一 QA 请求：`qa_mode`、当前 `artifact`、`approved_upstream`、`project_constraints`、`change_set`、`previous_version` 和 `flow_control`；后者包含本产物的 `production_authorization_id` 与当前 S01 `CALL_QA` 状态包。

当用户明确只要表格正文时，只展示第 3 项，但内部仍完成门禁、连续性、映射和 QA 自检。

多场输入时按 [分镜表标准](references/storyboard-table-standard.md) 的 `StoryboardTableSet` schema 包装；每个场次仍是独立子表、独立 `scene_id` 和独立 QA 请求。若在一个 Markdown 文件中渲染多张表，校验器必须返回与子表数量一致的 `table_count`。

## 状态、版本与局部失效

- 每个 `StoryboardTable` 只对应一个 `scene_id`；多场请求输出按场次排序的 `StoryboardTableSet`，不要用 `scene_ids` 取代子产物必需的单值 `scene_id`。
- 使用稳定 `artifact_id: STORYBOARD-<scene_id>`、独立 `artifact_version: V<n>` 和派生 `full_id: STORYBOARD-<scene_id>-V<n>`；上游同样分开保存稳定 ID、版本和完整 ID。
- `scene_id` 原样继承 S02 的 `SCENE-E##-S##`。`shot_id` 删除 `scene_id` 的固定 `SCENE-` 前缀后生成 `SHOT-E##-S##-<三位序号>`；禁止生成 `SHOT-SCENE-...` 或丢失集号。每条 `shot_map` 保存自己的 `storyboard_row_version`。正常整表修订递增表版本，局部修改只递增目标行版本，未修改行保留原行版本。
- 统一 QA 只有在全部行合格时才能把表和每条 `shot_map.status` 原子地写为 `PASS`。S04/S05 不接受父表 `PASS` 但目标行仍为 `DRAFT` 的输入。
- 新产物以 `DRAFT` 写入；交给统一 QA 后由流程管理器切换 `CHECKING`。
- 继续已有表前执行写权限门禁：`DRAFT` 可编辑；`CHECKING` 暂停写入；`REPAIR` 仅按匹配 RepairTicket 局部写；`PASS`/`APPROVED` 只允许通过已确认 ChangeSet 创建新 `DRAFT` 版本，不原地改写；`HUMAN_GATE` 等待人工；`STALE` 禁止直接用于下游，按影响范围从当前有效上游重新生成，或在内容仍可能有效时重新检查后再恢复使用。
- 某个 BEAT 变化时，只把对应分镜行及其下游标为 `STALE`。
- 某行分镜变化时，只把对应 `shot_id` 的分镜 Prompt、图片和视频 Prompt 标为 `STALE`。
- 不继续使用任何 `STALE` 产物。

## RepairTicket

仅依据指向 S03/StoryboardTable 的有效 RepairTicket 修改：

1. 要求当前表状态为 `REPAIR`，并核对稳定 `artifact_id`、版本/`full_id`、问题证据、最小修复要求和 `locked_fields`。
2. 保存 `previous_version`，把票据正规化为精确 `change_set`。
3. 只修改被点名的镜头和字段，逐字保留其余行和锁定字段。
4. 回归检查相邻镜头连续性与未指定内容不变。
5. 递增表版本和目标 `storyboard_row_version`，未修改行保持原行版本；递减 `max_attempts_remaining`。
6. 向统一 QA 传入修改后完整 `artifact`、已通过上游、项目约束、`change_set` 和 `previous_version`，重新提交相同 QA 模式。
7. 若本次复检仍失败，且同一问题已连续两轮失败或剩余尝试为 0，返回 `HUMAN_GATE`。

若问题源于剧情结构，路由 S02；若只是分镜图或下游 Prompt 转译错误，不在 S03 改表。

导演明确提出非 QA 的局部修改时，先把它正规化为 ChangeSet：记录目标 `shot_id`、允许修改的字段、确认后的新值、原因和 `locked_fields`。保存 `previous_version`，只开放 ChangeSet 指定字段，保持其余内容和行版本不变，递增表版本与目标行版本、局部标记下游 `STALE`，并把 `change_set + previous_version` 一并提交 QA。含糊建议、备选方案或会改变已通过剧情的修改不得直接执行。

## 职责边界

- 不修改已通过剧情的事件、顺序、人物关系、动机或原始对白。
- 不添加无来源的新人物、新道具、新场景或新结果。
- 不生成分镜图，不调用生图工具。
- 不编写分镜图提示词或视频提示词。
- 不把《指令.txt》中的 B1“导演分析版白模”误作 S03 分镜表。
- 不以“电影感、压迫、震惊、内心复杂”等术语代替可见执行细节。
- 不为追求镜头丰富而越轴、重复信息、叠加运镜或制造无意义碎镜。
