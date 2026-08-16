---
name: script-plot-progression
description: 将原剧本、人物关系、场景事实和已确认导演决定拆解为可追踪、因果连续的 PlotProgressionSpec，按场次生成包含起始状态、触发、行动、反应、原始对白、情绪变化、结束状态和连续性要求的剧情 BEAT。用于剧本拆解、剧情演进整理、QA:PLOT 返修和上游剧情变更后的局部重建；不得设计镜头、改写台词或无依据扩写剧情。
---

# 剧本剧情演进导演

## 目标

将已提供的剧本事实整理成可追踪、可检查、可供分镜设计直接使用的 `PlotProgressionSpec`。保持剧情事件、人物关系、发生顺序和原始对白忠实，不用镜头语言替代剧情结构。

## 中央流程硬门禁

本 Skill 只能由 S01 `$short-drama-flow-director` 的当前 `CALL_PRODUCER` 或 `ROUTE_REPAIR` 调度进入。开始任何剧情整理前，必须读取完整 S01 状态包并核对 `dispatch.authorization_id` 对应唯一 `ISSUED FlowAuthorization`，其 `project_id`、`stage: P1`、`action`、`target: script-plot-progression`、范围和 `ticket_id`（返修时）必须与本任务完全一致。

把状态包保存为 UTF-8 JSON，先运行 `..\short-drama-flow-director\scripts\validate_flow_state.ps1 -Path <flow-state.json>`；脚本通过且当前 dispatch 精确指向本 Skill 后才能继续。

缺失或不匹配时立即停止，只输出 `FLOW_DISPATCH_REQUIRED`、不匹配证据和 `return_to: short-drama-flow-director`；不得生成 Plot 草稿、正文片段或替代产物。合法产物根级必须原样写入 `flow_authorization_id`。

## 严守职责边界

- 只生成或修复 `PlotProgressionSpec`。
- 不设计景别、机位、构图、轴线、运镜、焦段、光影或镜头时长。
- 不生成分镜表、图像提示词、分镜图或视频提示词。
- 不把常识、类型套路或审美偏好写成剧情事实。
- 不执行创意改编、扩写、润色或新增台词；将这类请求交回流程导演确认范围或路由至独立改编能力。
- 不自行判定 `PASS`；产物完成后请求 `QA:PLOT`。

## 按需读取资源

开始任何生产任务前：

1. 读取 [公共流水线契约](../_shared/pipeline-contract.md)，统一 ID、版本、状态和 QA 信封。
2. 读取 [references/source-decision-rules.md](references/source-decision-rules.md)，裁决来源、确认状态和冲突。
3. 读取 [references/scene-and-beat-rules.md](references/scene-and-beat-rules.md)，划分场次和 BEAT。
4. 读取 [references/plot-progression-schema.md](references/plot-progression-schema.md)，按固定契约输出。

满足以下条件时再读取额外资源：

- 涉及多场、跨场、道具交接、伤势、能力、人物信息变化或上游更新时，读取 [references/continuity-rules.md](references/continuity-rules.md)。
- 任务模式为 `REPAIR` 或 `UPDATE`，或收到 QA 裁决时，读取 [references/repair-rules.md](references/repair-rules.md)。
- BEAT 粒度不明确或首次应用本 Skill 时，读取 [references/examples.md](references/examples.md)。示例是合成示范，不得当作当前项目事实。

只加载与当前任务有关的项目资料。不要加载 Seedance、摄影、光影或图像生成知识库。

## 接收输入

优先读取由流程导演提供的结构化输入：

```yaml
project_id: <项目 ID>
task_mode: CREATE | REPAIR | UPDATE
script_sources: <带 source_id、version、scope 和定位方式的原剧本>
confirmed_decisions: <已确认导演决定>
character_relations: <人物关系>
scene_facts: <场景事实>
asset_constraints: <影响剧情连续性的资产事实>
source_conflicts: <已知来源冲突>
previous_artifact: <REPAIR/UPDATE 时提供>
repair_ticket: <REPAIR 时提供>
change_set: <UPDATE 时提供>
```

接受普通文件或聊天文本作为输入时，先在内部补齐等价的来源登记。不得因为调用方没有使用上述字段名而丢弃有效资料。

## 执行输入门禁

确认以下条件：

- 至少一份原剧本可读取，并有稳定的来源标识和版本。
- 当前任务范围可定位到项目、集、场或明确文段。
- 导演资料可区分 `CONFIRMED`、`TENTATIVE` 和 `REJECTED`。
- 人物标准名和别名足以避免身份误合并或重复。
- `REPAIR` 同时提供上一版产物和有效 `RepairTicket`。
- `UPDATE` 同时提供上一版产物和已确认 `ChangeSet`。
- 正式输入不引用 `STALE` 上游；若只能读取 `STALE` 资料，停止正式生产。

门禁不通过时：

1. 不生成貌似完整的正式产物。
2. 保留能够确认的范围。
3. 将阻断项写入 `conflicts` 或 `unknowns`。
4. 将状态设为 `HUMAN_GATE`。
5. 只提出能够解除阻断的最少确认问题。

不要把缺少视觉风格、画幅、镜头参数视为 S02 阻断项。

## 生产 PlotProgressionSpec

### 1. 登记来源

- 为每个输入记录 `source_id`、`source_type`、`version` 和 `scope`。
- 保留剧本的行号、页码、段落号或时间码。
- 选择一份原剧本作为剧情基线，不把整理后的文字冒充原始来源。

### 2. 建立事实清单

逐场提取人物、别名、关系、场景、事件、行动、反应、结果、原始对白、道具和连续性状态。对每项事实保留来源定位。

### 3. 应用来源裁决

- 只应用已确认且可定位的导演决定。
- 保存被覆盖的剧本内容、确认内容、决定 ID 和受影响范围。
- 隔离建议、备选与否决方案。
- 遇到两个同级锁定来源互斥时，将受影响范围设为 `HUMAN_GATE`，不要以推断裁决。

### 4. 划分场次

- 优先继承剧本中的明确场次标题。
- 没有标准标题时，根据地点、时间、连续行动和主要人物组合的重大变化划分。
- 生成 `SCENE-E{集号}-S{场号}`；缺少集号时使用流程导演提供的作用域，不自行猜集号。

### 5. 划分 BEAT

- 先识别剧情状态变化，再决定边界。
- 让每个 BEAT 表达一个主要剧情变化。
- 保持原事件、行动和对白顺序。
- 合并同一动作的自然准备、执行和结果；拆开拥有不同触发或不同结果的连续事件。
- 生成 `BEAT-E{集号}-S{场号}-{场内序号}`。

### 6. 建立状态链

为每个 BEAT 填写：

- `start_state`
- `trigger`
- `actions`
- `reactions`
- `dialogue`
- `emotion_change`
- `end_state`
- `continuity`

只写原文或已确认决定支持的行动和情绪变化。把情绪变化绑定到事件、动作或对白证据，不补写隐藏动机。

### 7. 保持对白原文

- 逐字复制台词内容，包括原有标点和称呼。
- 记录唯一说话人、发生顺序、来源定位及原文明确的时机。
- 不做润色、纠错、同义替换或口语化改写。
- 原文疑似错字仍按原文保存；只有已确认决定才允许更改，并记录覆盖关系。

### 8. 建立来源覆盖

- 为每个剧情事件和每句对白建立 `source_coverage` 项。
- 将覆盖标记为 `FULL`、`PARTIAL` 或 `OMITTED`。
- 正常完成的正式产物不得保留 `PARTIAL` 或 `OMITTED`。
- 即使某段原文因冲突被阻断，也必须以 `PARTIAL` 或 `OMITTED` 登记并计入总数；不得通过不登记来制造虚假的完整覆盖率。
- `HUMAN_GATE` 产物中，尚未进入任何 BEAT 的阻断内容可以使用空 `covered_by`，并在 `note` 中引用对应冲突或未知项。
- 不要求把页眉、页脚、场次编号和纯排版标记写成剧情 BEAT。

### 9. 检查连续性

逐相邻 BEAT 比较人物在场状态、已知信息、位置、伤势、服装、能力和道具归属。确认前一 `end_state` 能够进入后一 `start_state`。对资料没有说明的维度标记 `UNKNOWN`，不要补全。

### 10. 组装产物

- 使用 JSON 作为规范机器格式；需要展示时可以附人类可读摘要，但 JSON 是正式产物。
- 按 Schema 输出顶层、场次、BEAT、覆盖、冲突和影响范围。
- 将新产物状态设为 `DRAFT`；存在阻断冲突时设为 `HUMAN_GATE`。
- 不创建 `shot_id`。镜头 ID 从 S03 开始生成。
- 不把调用说明、推理过程或知识库规则写入正式 JSON。

## 处理任务模式

### CREATE

从已登记来源生成新的 `PlotProgressionSpec`，版本从 `V1` 开始。不要覆盖同 ID 已存在的版本。

### UPDATE

读取上一版和已确认 `ChangeSet`。只更新 `allowed_paths` 或 `affected_scope` 指定内容，递增产物版本，返回最小 `impact_scope`。保持未开放内容不变。

### REPAIR

读取上一版和 `RepairTicket`。只修复票据点名的问题，保持 `locked_fields` 不变，递增版本，并请求相同的 `QA:PLOT` 复检。同类问题连续两轮仍失败时升级 `HUMAN_GATE`。

## 执行机械验证

产出 JSON 文件后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_plot_progression.ps1" -Path <artifact.json>
```

在 `UPDATE` 或 `REPAIR` 后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\compare_locked_fields.ps1" -BeforePath <before.json> -AfterPath <after.json> -ChangeSetPath <changeset.json>
```

先把 `<SKILL_DIR>` 解析为本 `SKILL.md` 所在目录，不假设当前工作目录。将机械验证错误修复后再请求 QA。不要把脚本通过当作剧情语义已经通过。

## 请求 QA:PLOT

返回或写入以下调用对象：

```yaml
qa_mode: PLOT
artifact: <当前 PlotProgressionSpec>
approved_upstream:
  - <原剧本及版本>
  - <已确认导演决定>
  - <人物关系、场景和资产事实>
project_constraints: <项目锁定剧情与来源规则>
change_set: <UPDATE 时提供；首次 CREATE 为 null>
previous_version: <REPAIR/UPDATE 时提供；首次 CREATE 为 null>
flow_control:
  production_authorization_id: <本产物的 flow_authorization_id>
  flow_state: <完整当前 S01 状态包，dispatch 为 CALL_QA>
```

等待 QA 返回：

- `PASS`：允许流程导演推进 S03。
- `REPAIR`：按最小 RepairTicket 局部返修。
- `HUMAN_GATE`：停止受影响范围并提交导演判断。

## 返回调用结果

向流程导演返回：

```yaml
producer_skill: script-plot-progression
artifact_id: <产物 ID>
artifact_version: <版本>
status: DRAFT | HUMAN_GATE
artifact_location: <路径或内联>
qa_request:
  qa_mode: PLOT
impact_scope: <CREATE 时可为空>
blocking_questions: <仅 HUMAN_GATE 时提供>
```

始终把 `impact_scope` 输出为包含 `changed_beats` 和 `stale_downstream` 的对象，不要输出空列表替代对象。

保持人类摘要简洁。不要在摘要中省略或改写正式产物内的台词。

## 禁止事项

- 禁止新增原文不存在的剧情、动机、人物、道具、能力或台词。
- 禁止把人物类型常识推断成该人物的真实意图。
- 禁止为了更好拍摄而调整剧情顺序或提前揭露信息。
- 禁止按镜头粒度过度切碎 BEAT。
- 禁止把多个独立状态变化挤入一个 BEAT。
- 禁止传播已否决、未确认或互相冲突的方案。
- 禁止伪造来源范围、版本、确认记录或镜头 ID。
- 禁止在 QA 之前把自己的产物标为 `PASS`。
