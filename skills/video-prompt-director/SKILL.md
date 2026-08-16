---
name: video-prompt-director
description: 将人工 APPROVED 的分镜图、PASS 的剧情演进与分镜表、原始对白、资产和上一镜状态，忠实整理为单镜头、可追踪、可投喂 Seedance 的 VideoPromptSpec，并处理 VIDEO_PROMPT RepairTicket 与已确认 ChangeSet 的局部更新。用于“开发/生成 S05 视频提示词”“根据确认分镜图写 Seedance Prompt”“修复某镜视频 Prompt”“更新指定镜头且保持锁定字段”等任务；不用于拆剧情、设计或修改分镜、审批分镜图、生成视频、执行视频 QA，亦不得绕过人工分镜确认门禁。
---

# S05 视频提示词导演

## 目标

把一个已确认 `shot_id` 的权威上游资料转成一个 `VideoPromptSpec`。首帧构图、景别、人物位置、核心道具和已确认运镜必须继承上游；动作、对白、摄影、光影、声音与计划镜尾必须可执行、可追踪且相互一致。

S05 只写 `status: DRAFT`。独立 S06 `QA:VIDEO_PROMPT` 才能裁决 `PASS`、`REPAIR` 或 `HUMAN_GATE`。

## 开始前读取

始终读取：

- [公共流水线契约](../_shared/pipeline-contract.md)：规范 ID、多 BEAT 映射、图片审批产物、状态和 QA 信封。
- [input-gates-and-routing.md](references/input-gates-and-routing.md)：输入结构、状态门禁、来源优先级与任务路由。
- [video-prompt-contract.md](references/video-prompt-contract.md)：完整 `VideoPromptSpec`、正文顺序、字段镜像和 QA 交接。
- [prompt-assembly-rules.md](references/prompt-assembly-rules.md)：时长、动作、表演、对白、光影、声音与正文纯净度。
- [optics-and-camera-rules.md](references/optics-and-camera-rules.md)：焦段、f 值、机位距离、焦点、景深及运镜继承。
- [continuity-rules.md](references/continuity-rules.md)：0 秒状态、世界/屏幕位置、道具与计划/实际镜尾。

按目标模型再读取且只读取一个模型文件：

- Seedance 2.0：读取 [seedance-2.0.md](references/seedance-2.0.md)。
- Seedance 2.5：读取 [seedance-2.5.md](references/seedance-2.5.md)，先执行其中的规则可用性门禁。

首次处理某类场景、需要从实测失败中避错或输入含当前素材板时，读取 [examples-and-case-index.md](references/examples-and-case-index.md)。仅在 `REPAIR` 或 `UPDATE` 时读取 [changeset-and-repair-rules.md](references/changeset-and-repair-rules.md)。

不要在运行时整批加载原始 `file/` 知识库。上述 references 已提炼 S05 所需规则；案例只按标签读取。

## 输入门禁

只在以下条件全部成立时生成正式 Prompt：

1. 当前任务唯一定位到一个 `project_id`、`scene_id` 和 `shot_id`。
2. `ApprovedStoryboardSet.status` 为 `APPROVED`，且当前 `shot_id` 对应图片条目有精确 `full_id`、`source_prompt_full_id`、人工状态 `APPROVED`、批准记录和 `stale: false`。
3. 对应 `PlotProgressionSpec`、`StoryboardTable` 与当前 `StoryboardRow` 均为 `PASS`，`source_beat_ids` 完整一致，且不是 `STALE`。
4. 本镜有对白时可按来源定位逐字核对且说话人明确；无对白时上游明确标为 `NO_DIALOGUE`。
5. 人物、场景、关键道具、项目画幅及当前素材槽位映射可追踪。
6. 目标模型和产品模式明确，并存在状态为 `VERIFIED` 的模型规则配置。
7. 上一镜结束状态已提供，或逐字段标为 `UNKNOWN`；不得用猜测补成锁定事实。
8. `REPAIR` 同时提供上一版产物和有效 `RepairTicket`；`UPDATE` 同时提供上一版产物和已确认 `ChangeSet`。

门禁失败时只输出阻断字段、证据、返回阶段和 `HUMAN_GATE`/上游路由，不输出伪装成最终版的 `body`。当前资料只完整支持 Seedance 2.0；未提供外部已验证 2.5 规则配置时必须阻断 2.5。

## 工作流

### 1. 固定任务范围

确定 `CREATE | REPAIR | UPDATE`、目标模型、产品模式、生成任务类型、时长和画幅。一次产物只对应一个 `shot_id` 和一套从 0 秒开始的连续时间轴。

整集、多场或未选镜号的请求返回 S01/S03 先完成分段与镜头选择。批量请求拆成多个相互独立的 S05 作业；不得合并成一条超长 Prompt。

### 2. 校验来源链

核对以下精确版本并写入 `source_artifacts`：人工确认分镜图、剧情演进、分镜表行、原始对白、资产台账、模型规则和上一镜状态。任一直接来源为 `STALE`、缺版本或范围不匹配时停止。

分镜图与剧情、分镜表或连续性事实互相冲突时不得择一猜测：构图/人物位置冲突进入 `HUMAN_GATE`；分镜设计错误返回 S03；图片生成错误返回分镜图生成/确认阶段。

### 3. 建立来源锁

逐项登记并锁定：剧情顺序、原始台词、人物数量与身份、首帧构图、景别、机位、人物世界位置与当前屏幕投影、视线、持物手、核心道具、画幅、时长和已确认运镜。

未在上游锁定但为模型执行所需的焦段、f 值、机位距离、焦点和景深可以选择单一保守值，必须标为 `DERIVED_EXECUTION`，且不得改变确认构图或信息量。

### 4. 重建 0 秒状态

先锁世界锚点，再按当前摄影机重算屏幕左右。逐人记录位置、朝向、视线、支撑脚、重心、动作阶段、呼吸、伤势和道具接触；逐道具记录所有者、持物手、方向、状态和落点。

已验收上一段的清洁稳定末帧可提供实际可见状态，但不能传播镜像、错手、变形或错误道具。单帧不能证明速度、精确距离、焦段、f 值或画外人物；这些字段必须继承锁定资料或标为未知。

### 5. 检查时长与负荷

计算台词自然时长、动作准备—执行—接触/结果—回稳所需时间、镜头移动和听者反应。若当前时长无法容纳上游已确认内容，返回 S03 或 `HUMAN_GATE`；S05 不得删台词、加速全部动作、偷偷加切镜或自行拆出新 `shot_id`。

### 6. 组织动作与对白

按剧情演进保留动作因果与顺序。每个时间段写镜头起点、唯一主动作、可见微表演、情绪变化、已确认运镜的触发与落点、声音反馈。动作遵守意图、重心、动力链、接触、惯性和恢复。

原始对白逐字保留并绑定唯一说话人、时间窗、音色、语气、音量、语速、气息和口型。非说话人闭嘴但有错时、低强度听者反应。对白容量不足时停止，不通过改写原句解决。

### 7. 落实摄影、光影和声音

继承分镜表的景别、机位和主运镜。连续一镜保持同一焦段与 f 值；为移动主体写跟焦路径。每个运镜必须有动作触发、路径、落点和停稳状态，不得为“电影感”叠加运动。

在人物动作发生时嵌入主光方向、暗侧负补、轮廓分离、实景灯光池、明暗分区和高光落点。明确环境基底、人物分离色、强调/危险色、黑位、中间调与高光滚降。声音只保留画面中实际存在的对白、环境声、状态声和动作声。

### 8. 组装产物

按 [video-prompt-contract.md](references/video-prompt-contract.md) 先完成结构化字段，再按固定顺序生成 `body_sections` 和 `body`：

```text
参考素材说明
→ 已确认站位来源与自包含 0 秒状态
→ 核心情绪、动作结果与连续时间轴
→ 摄影光学、光影、色彩和材质
→ 声音、连续性与简短稳定性约束
```

`body` 内不得出现 QA 解释、白模分析、截图解析、镜尾卡、RepairTicket、Emoji 标题、营销话术或下一步建议。只使用真实 `{{Mixed x}}`，禁止 `@`、`{{Image x}}` 和伪造编号。

### 9. 标记计划镜尾

`end_state.state_kind` 固定为 `PLANNED`，记录每个人物、道具、摄影机、焦点、主光和声音在计划停点的状态，并给出下一镜必须继承项。不得把计划状态写成实际成片事实；视频生成并验收后由实际末帧状态覆盖。

### 10. 提交独立 QA

输出前做确定性检查：ID/版本、状态门禁、时长连续性、Mixed 映射、对白逐字匹配、模型限制、字段镜像、禁止格式和锁定字段。先把正式 `VideoPromptSpec` 保存为 UTF-8 JSON 并运行 `scripts/validate_video_prompt.ps1 -Path <artifact.json>`；再将纯正文保存为 UTF-8 临时文件并运行 `scripts/validate_body.ps1` 检查 Unicode 字数、槽位格式、重复 0 秒时间轴和污染词。Windows 执行策略阻止本地脚本时使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_video_prompt.ps1" -Path <artifact.json>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_body.ps1" -BodyPath <正文文件> -MaxChars 5000
```

先把 `<SKILL_DIR>` 解析为本 `SKILL.md` 所在目录，不假设当前工作目录。Seedance 2.0 未知统一上限时把 `-MaxChars` 设为 `0`；2.5 使用 `5000`。语义质量仍交给独立 QA，不自行裁决。

提交：

```yaml
qa_mode: VIDEO_PROMPT
artifact: <VideoPromptSpec DRAFT>
approved_upstream:
  - <ApprovedStoryboardSet 精确版本>
  - <PASS PlotProgressionSpec 精确版本>
  - <PASS 分镜表行精确版本>
project_constraints: <项目锁定事实与模型规则>
change_set: <UPDATE 时提供>
previous_version: <REPAIR/UPDATE 时提供>
```

## V3.6 控制层边界

集群流程中 `ApprovedStoryboardSet(APPROVED)` 是 S05 的硬门禁，`VideoPromptSpec` 是唯一主产物。0 秒 B1/B2 白模、图外颜色映射和实际末帧解析属于上游/伴随控制层，不得由 S05 生成后绕过既有人工确认，也不得混入 `body`。

若项目明确启用 `QUICK_PREFLIGHT` 或 `STRICT_PREFLIGHT`，先由 S01/对应控制层完成白模生成、复核和真实槽位绑定；S05 只读取其有效版本。复杂空间仍有歧义时暂停进入 `HUMAN_GATE`，不在 S05 重做确认构图。

## RepairTicket 与 ChangeSet

遵守 [changeset-and-repair-rules.md](references/changeset-and-repair-rules.md)：验证目标与允许范围，复制上一版本，只改开放字段及其声明过的正文镜像，版本递增，状态回到 `DRAFT`，记录 `change_log`，再次调用相同 QA。

同类问题连续两次失败、工单要求会破坏上游锁定项、或最小修复需要改变镜头设计时升级 `HUMAN_GATE`/返回 S03。

## 职责边界

- 只创建或修复 `VideoPromptSpec`；不生成视频、不验收视频。
- 不修改剧情演进、分镜表、已确认分镜图或资产事实。
- 不增加未经确认的切镜、人物、道具、台词、剧情或模型能力。
- 不把整集分段清单冒充单镜头最终 Prompt。
- 不引用未确认、`STALE`、无版本或错范围的分镜图片。
- 不用计划镜尾冒充实际末帧，不用单帧编造不可见事实。
- 不复制失败案例的 Prompt；只继承已确认的避错结论。
- 不因缺少 Seedance 2.5 规则而把 2.0 规则改名套用。

## 完成判定

交付前确认：一产物一 `shot_id`；全部权威来源和版本可追溯；首帧与确认图一致；剧情、对白、人物、道具和运镜无新增或漂移；时间轴连续且负荷可执行；光学字段明确且来源标注；计划镜尾可承接；正文可直接投喂且无控制层污染；状态为 `DRAFT`；QA 交接完整。
