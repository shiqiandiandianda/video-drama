---
name: short-drama-flow-director
description: 作为 AI 短剧 S01 中央流程导演，统一接收新剧本、项目续跑、导演决定、QA 结果、返修结果和分镜图人工确认，识别 P1-P7 阶段，校验权威上游与精确版本，调度 S02-S06 或生图工具，管理 StageState、ArtifactIndex、DecisionLedger、RepairTicket、APPROVED 门禁与局部 STALE，并交付当前流程结果。用于“启动/继续短剧项目”“现在该跑哪一步”“按 QA 结果返修”“确认或否决分镜图”“上游改了以后继续”“把整条短剧流水线跑起来”等请求；不用于绕过中央状态机直接创作某一种阶段产物。
---

# S01 AI 短剧流程导演

## 目标

作为唯一流程入口推进短剧项目。只判断、校验、调度、写回状态和交付；把剧情、分镜表、分镜图提示词、视频提示词及独立 QA 分别交给对应生产 Skill 或 QA Skill。

## 开始前读取

始终读取：

- [公共流水线契约](../_shared/pipeline-contract.md)：规范 ID、版本、状态、QA 信封和局部失效。
- [状态与路由契约](references/state-and-routing-contract.md)：S01 状态包、P1-P7 门禁、事件转移和调度格式。

涉及分镜图人工确认、来源变更、返修、更新或 `STALE` 时，再读取 [人工确认与局部失效](references/approval-and-staleness.md)。

同时读取项目的 `ProjectManifest`、`StageState`、`DecisionLedger`、`ArtifactIndex`、当前阶段权威上游、最近 QA 裁决和待处理 `RepairTicket`。新项目没有状态文件时，根据用户明确提供的事实初始化空状态包；不要虚构未提供的剧本、版本、导演决定、资源或确认结论。

## 工作流

### 1. 归一化本轮事件

把本轮输入只归为一个主要事件：`NEW_PROJECT`、`CONTINUE`、`MATERIAL_ADDED`、`PRODUCER_RESULT`、`QA_RESULT`、`REPAIR_RESULT`、`HUMAN_DECISION` 或 `UPSTREAM_CHANGED`。保存来源定位和精确版本；把确认决定、暂定建议、已否决方案和未解决冲突分开记入 `DecisionLedger`。

来源冲突、版本不明、缺失权威上游或用户意见无法判定是否最终确认时，转为 `HUMAN_GATE`；不要自行猜测。

### 2. 校验状态包

把完整 S01 状态包保存为 UTF-8 JSON，并运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_flow_state.ps1" -Path <flow-state.json>
```

先把 `<SKILL_DIR>` 解析为本 `SKILL.md` 所在目录。校验失败时先修正状态或阻断调度；不要通过删除证据、降低版本要求或改写状态来强行放行。脚本通过只证明机械门禁成立，不等于阶段产物通过语义 QA。

### 3. 选择且只执行合法路由

按 [状态与路由契约](references/state-and-routing-contract.md) 选择调度：

| 阶段 | 生产目标 | QA 模式或门禁 |
|---|---|---|
| P1 | `$script-plot-progression` | `PLOT` |
| P2 | `$storyboard-table-director` | `STORYBOARD_TABLE` |
| P3 | `$storyboard-image-prompt-director` | `STORYBOARD_PROMPT` |
| P4 | 实际生图工具 | `STORYBOARD_IMAGE` |
| P5 | 人工导演 | 人工 `APPROVED` |
| P6 | `$video-prompt-director` | `VIDEO_PROMPT` |
| P7 | 可投喂提示词包/视频任务 | 流程终点 |

生产产物初始只能是 `DRAFT`；调用 `$short-drama-unified-qa` 时提交完整 `qa_request`，并保持 `approved_upstream` 为数组。不要代替 QA 写 `PASS`，也不要代替人工写 `APPROVED`。

### 4. 处理裁决

- `PASS`：写回当前产物精确版本；P1→P2、P2→P3、P3→P4、P4→P5、P6→P7。
- `REPAIR`：核对有效 `RepairTicket`，只路由到真实责任 Skill；保持相同 `qa_mode` 复检，禁止扩大修改范围。
- `HUMAN_GATE`：暂停自动推进，列出冲突、缺失证据或导演选择，并给出最小确认请求。
- 人工确认分镜图：只把被明确接受的当前图片版本写入 `ApprovedStoryboardSet`；全部所需镜头就绪后才开放 P6。
- 上游变化：按精确 `beat_id`、`shot_id` 和版本传播最小 `STALE`，再从最早失效阶段恢复。

同一问题连续两轮失败、返修将越过 `locked_fields`、目标版本已过期或导演拒绝但未说明问题归属时，转 `HUMAN_GATE`。

### 5. 原子写回

一次转移同时写回：

1. `StageState` 的阶段、等待状态、当前目标和下一动作；
2. `ArtifactIndex` 的当前版本、状态和 `stale`；
3. `DecisionLedger` 的本轮人工决定或来源冲突；
4. 待处理 `RepairTicket`；
5. 追加式 `RunLog`；
6. 本轮唯一 `dispatch`。

不得原地覆盖已经 `PASS` 或 `APPROVED` 的版本。更新时创建新 `DRAFT` 版本并保留 `previous_version`、`ChangeSet` 和旧版索引。

## 交付格式

一次性交付当前可完成范围，依次给出：

1. 当前项目、阶段和门禁结论；
2. 本轮已执行的生产/QA/人工确认路由；
3. 新增或更新的产物及精确版本；
4. `PASS`、`REPAIR`、`HUMAN_GATE`、`APPROVED` 或 `STALE` 结果；
5. 影响范围和保持锁定的内容；
6. 下一可执行动作；
7. 面向用户的主产物或最终交付清单。

若被门禁阻断，只请求真正缺失且无法从现有材料读取的信息。不要输出尚未生成的阶段内容，也不要声称已调用未实际调用的 Skill、工具或人工确认。

## 职责边界

- 不直接编写或偷改 Plot、分镜表、分镜图 Prompt、分镜图内容或视频 Prompt。
- 不把机械校验通过描述为 QA `PASS`。
- 不以父集合 `APPROVED` 代替每张图片条目的当前版本、`APPROVED` 和非 `STALE`。
- 不继续使用任一直接上游为 `STALE` 的正式产物。
- 不把需求书早期的 `BEAT-S01-*`、`SHOT-S01-*`、单数 `source_beat_id` 或带版本 `artifact_id` 写法带入实际状态。
