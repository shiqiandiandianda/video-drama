---
name: storyboard-image-prompt-director
description: 将 QA 已通过的横向分镜表逐镜转译为单张静态分镜图生图提示词，并维护资产绑定、构图与机位、人物/道具位置、静态动作瞬间、连续性、版本和局部返修。用于“开发/生成 S04 分镜图提示词”“把分镜表变成逐镜生图 Prompt”“按 STORYBOARD_PROMPT RepairTicket 修复某镜 Prompt”等任务；不用于设计分镜表、直接生成图片或编写视频提示词。
---

# S04 分镜图提示词导演

## 目标

把一行已通过的分镜表忠实转译成一个 `StoryboardPromptSpec`。一条 Prompt 只对应一个 `shot_id`、一个静态画面和一个版本，同时完整继承该行的 `source_beat_ids`；不得补写上游没有的人物、道具、台词或剧情。

## 中央流程硬门禁

本 Skill 只能由 S01 `$short-drama-flow-director` 的当前 `CALL_PRODUCER` 或 `ROUTE_REPAIR` 调度进入。开始编写生图 Prompt 前，必须读取完整 S01 状态包并核对 `dispatch.authorization_id` 对应唯一 `ISSUED FlowAuthorization`，其 `project_id`、`stage: P3`、`action`、`target: storyboard-image-prompt-director`、范围和 `ticket_id`（返修时）必须与本任务完全一致。

把状态包保存为 UTF-8 JSON，先运行 `..\short-drama-flow-director\scripts\validate_flow_state.ps1 -Path <flow-state.json>`；脚本通过且当前 dispatch 精确指向本 Skill 后才能继续。

缺失或不匹配时立即停止，只输出 `FLOW_DISPATCH_REQUIRED`、不匹配证据和 `return_to: short-drama-flow-director`；不得生成 Prompt、正负面片段或替代内容。合法产物根级必须原样写入 `flow_authorization_id`。

## 开始前读取

始终读取：

- [公共流水线契约](../_shared/pipeline-contract.md)：规范 ID、多 BEAT 映射、状态、图片审批桥接和 QA 信封。
- [image-prompt-contract.md](references/image-prompt-contract.md)：产物字段、正文顺序和交付格式。
- [asset-binding-rules.md](references/asset-binding-rules.md)：资产、空间投影、文字和连续性规则。
- [static-moment-rules.md](references/static-moment-rules.md)：静态瞬间选择与电影语言转译。

首次使用、遇到动作过载或处理返修时，再读取 [examples.md](references/examples.md)。

## 输入门禁

只在以下条件全部成立时生产 Prompt：

1. `StoryboardTable.status` 为 `PASS`。
2. 当前规范 `StoryboardRow` 的 `status` 为 `PASS`，并有唯一 `shot_id`、行版本和非空 `source_beat_ids`。
3. 人物身份与外观、场景结构、关键道具、画幅和视觉风格有可追踪来源。
4. 当前产物及直接上游均不是 `STALE`。

门禁失败时只输出阻断原因和所需输入，不输出“可投喂 Prompt”。来源冲突、轴线无法还原、人物/道具身份无法确认时返回 `HUMAN_GATE`。若一行分镜包含无法由单张图表达的多个必要状态，返回 S03，不自行拆镜。

项目未覆盖的通用默认：真人写实电影剧照、竖屏 `9:16`、无字幕/标题/logo/水印。项目或用户的已确认规则优先于默认。

## 工作流

### 1. 建立来源锁

逐项摘录而非改写以下事实：剧情瞬间、景别、机位、镜头高度、构图目的、人物数量、人物身份、服装状态、世界位置、轴线侧、道具归属、画幅、风格及导演备注。把不能改变的项目写入 `locked_fields`。

不得把分镜表中的运镜直接写成静态图时间轴。保留其来源记录，只描述所选瞬间对应的摄影机位置、视角和最终构图。

### 2. 选择唯一静态瞬间

从上游动作中只冻结一个阶段：准备、接触前、首次接触、结果刚成立或回稳。优先选择同时满足以下条件的瞬间：

- 一眼能读懂当前镜头的导演目的；
- 人物意图、重心、手部接触和道具归属可见；
- 不依赖“随后、接着、然后、逐渐”等时间词；
- 能与前后镜状态连续。

在 `selected_moment` 中记录选中阶段和上游原句。若需要同时画出过去与未来动作才成立，停止并路由 S03。

### 3. 转译静态电影语言

按以下顺序写 `positive_prompt`：

1. 单张任务、画幅、真实度和项目视觉风格；
2. 场景锚点、时间、天气、前中后景和可拍空间；
3. 景别、摄影机实体位置/高度/朝向、视角、构图与光学执行；
4. 逐人物身份、画面投影位置、身体朝向、视线、重心、双手和遮挡关系；
5. 唯一冻结动作、接触点、道具状态；
6. 可见微表演；
7. 有动机的光影、色彩层级、材质和空气；
8. 需要保持的连续性事实。

把抽象情绪转成眉眼、呼吸、嘴角、肩线、手指、衣料、支撑脚和视线落点。只写这一帧可见的结果，不写镜头运动、声音、台词朗读过程或视频时长。

### 4. 绑定资产

为每个独立语义对象绑定唯一资产 ID 与版本，明确 `inherit` 和 `ignore`。只继承当前镜头需要的身份、外观、空间或道具事实；忽略参考图中的文字、水印、拼版编号、压缩瑕疵和错误生成结果。

沿用用户提供的槽位或 ID，不重排、不补号、不猜号。未提供真实资产 ID 时写入 `unresolved_fields` 并触发门禁，不伪造 `Mixed`、`Image` 或其他编号。

### 5. 写禁止项

`negative_constraints` 只放可观察、与当前镜头相关的失败模式：多生/漏生人物、左右反转、错手、道具替换、场景锚点漂移、肢体融合、海报式摆拍、文字污染等。不得用互相矛盾的否定词，也不得靠否定项补足正向构图。

默认禁止文字；只有分镜表明确要求的手机屏幕、招牌、时间卡或字幕卡才允许精确源文本。分镜编号和多格边框永远属于后期拼版层，不进入单张 Prompt。

### 6. 产出与 QA 交接

按 [image-prompt-contract.md](references/image-prompt-contract.md) 输出完整 `StoryboardPromptSpec`。新产物和返修产物均设为 `DRAFT`，不得自行宣称 `PASS`。

把正式产物保存为 UTF-8 JSON 后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_storyboard_prompt.ps1" -Path <storyboard-prompt.json>
```

脚本只检查结构、ID、版本、数组映射和门禁字段；静态瞬间、构图和资产语义仍交给独立 QA。

生成后提交：

```yaml
qa_mode: STORYBOARD_PROMPT
artifact: <StoryboardPromptSpec>
approved_upstream:
  - <对应 PASS 分镜表>
  - <对应 PASS 规范 StoryboardRow>
  - <实际使用的资产版本>
project_constraints: <当前项目锁定规则>
change_set: <UPDATE 时提供；首次 CREATE 为 null>
previous_version: <REPAIR/UPDATE 时提供；首次 CREATE 为 null>
flow_control:
  production_authorization_id: <本产物的 flow_authorization_id>
  flow_state: <完整当前 S01 状态包，dispatch 为 CALL_QA>
```

只有独立 QA 返回 `PASS` 后，才允许进入分镜图生成。

## RepairTicket 处理

1. 校验 `qa_mode: STORYBOARD_PROMPT`、目标 `artifact_id`、证据、最小修复要求和 `locked_fields`。
2. 复制上一版本，只修改工单点名字段；保留未开放字段的语义和顺序。
3. 当前产物版本递增，直接上游行版本不变，状态回到 `DRAFT`。
4. 输出 `change_log`，逐项说明旧值、工单要求和新值。
5. 重新提交同一 QA 模式；同类问题连续两次失败或无法验证时升级 `HUMAN_GATE`。

若工单暴露的是分镜设计问题，返回 S03；资产源错误返回资产阶段；不得在 S04 偷偷改上游。

## 职责边界

- 只生成或修复 `StoryboardPromptSpec`，不生成实际图片。
- 不改变已通过的剧情顺序、镜头数量、景别、机位、人物位置和核心道具。
- 不用连续动作、视频时间轴、运镜过程或声音代替静态构图。
- 不把 16/26 格拼版模板当成单张生图画面。
- 不生成 S05 的 `VideoPromptSpec`。
- 不把计划画面或未审核图片冒充已确认分镜。

## 完成判定

交付前确认：一镜一 Prompt；来源和版本可追溯；唯一静态瞬间成立；人物、道具和空间位置明确；资产 ID 真实；画幅与风格一致；无无依据新增；无时间轴语言；`status: DRAFT`；QA 交接字段齐全。
