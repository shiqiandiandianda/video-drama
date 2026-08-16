---
name: short-drama-unified-qa
description: 对 AI 短剧 S02 剧情演进、S03 分镜表、S04 分镜图提示词、实际分镜图和 S05 视频提示词执行独立统一 QA，核对权威上游、项目约束、版本追踪、语义连续性与局部变更，裁决 PASS、REPAIR 或 HUMAN_GATE，并签发可路由、最小范围、带锁定字段的 RepairTicket。用于“运行 S06/统一 QA”“检查阶段产物能否放行”“约束上下游 skill”“给出返修工单”“复检局部修改”“检查分镜图或视频 Prompt”等任务；不用于创作或直接修改生产产物，也不替代分镜图的人工 APPROVED 门禁。
---

# S06 短剧统一 QA

## 目标

独立检查当前阶段产物，阻止错误向下游传播。只读取证据并输出裁决；不要直接改写待检产物、上游产物或生产 Skill。

## 开始前读取

始终读取：

- [公共流水线契约](../_shared/pipeline-contract.md)：规范 ID、版本、状态、QA 请求和失效传播。
- [统一协议](references/common-protocol.md)：输入门禁、问题、裁决、RepairTicket 和 QA 响应格式。
- [返修回归与路由](references/regression-and-routing.md)：错误归属、最小变更、重复失败升级和 `STALE` 范围。

根据 `qa_mode` 只再读取一份清单：

| `qa_mode` | 清单 |
|---|---|
| `PLOT` | [qa-plot.md](references/qa-plot.md) |
| `STORYBOARD_TABLE` | [qa-storyboard-table.md](references/qa-storyboard-table.md) |
| `STORYBOARD_PROMPT` | [qa-storyboard-prompt.md](references/qa-storyboard-prompt.md) |
| `STORYBOARD_IMAGE` | [qa-storyboard-image.md](references/qa-storyboard-image.md) |
| `VIDEO_PROMPT` | [qa-video-prompt.md](references/qa-video-prompt.md) |

不要为一次检查批量加载其余四份模式清单。只有模式规则明确要求时，才读取对应生产 Skill 的详细契约。

## 工作流

### 1. 固定检查范围

只接受完整 `qa_request`：

```yaml
qa_mode: PLOT | STORYBOARD_TABLE | STORYBOARD_PROMPT | STORYBOARD_IMAGE | VIDEO_PROMPT
artifact: <完整当前产物，不是 ID 或摘要>
approved_upstream: [<用于裁决的完整权威来源>]
project_constraints: {}
change_set: null
previous_version: null
flow_control:
  production_authorization_id: FLOW-AUTH-PRJ001-P2-0001
  flow_state: <完整当前 S01 状态包，dispatch 为 CALL_QA>
```

将请求保存为 UTF-8 JSON，先运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\..\_shared\validate_qa_request.ps1" -Path <qa-request.json>
```

把 `<SKILL_DIR>` 解析为本 `SKILL.md` 所在目录，不假设当前工作目录。若用户只给产物而未封装请求，可以代为封装已提供内容；不得猜测缺失的权威上游、版本、确认状态或约束。

### 2. 执行输入门禁

逐项确认：

1. 请求来自 S01：`flow_state` 通过 S01 校验，当前 `dispatch` 是指向本 Skill 的 `CALL_QA`，且模式、产物、范围和 `production_authorization_id` 一致。
2. 待检产物根级 `flow_authorization_id` 指向唯一 `CONSUMED FlowAuthorization`，其项目、阶段、生产目标、范围和 `artifact_full_id` 与当前产物完全一致。
3. `qa_mode` 与产物类型一致。
4. `artifact_id` 是不带版本的稳定 ID，`full_id == artifact_id + "-" + artifact_version`。
5. 待检版本是当前版本，未标记 `STALE`；生产产物通常为 `DRAFT`，流程可在检查期间记录 `CHECKING`，但不要为此原地改文件。
6. 直接权威上游以完整对象提供，状态、版本、`project_id`、`scene_id`、`shot_id` 和 `source_beat_ids[]` 在适用处精确一致。
7. `approved_upstream` 中没有被当作正式证据的 `DRAFT`、`REPAIR`、`HUMAN_GATE` 或 `STALE` 产物；`VIDEO_PROMPT` 必须引用人工 `APPROVED` 且条目非失效的分镜图。
8. 返修或更新请求同时给出完整 `previous_version` 与精确 `change_set`；首次检查两者均为 `null`。

缺少可补交的请求字段或权威证据时，不伪造 `PASS` 或返修内容。流程授权缺失、伪造、未消费或不匹配时使用 `FLOW-AUTH-001`，裁决 `HUMAN_GATE` 并 `return_to: short-drama-flow-director`；不得把它当成普通内容返修。其他无法验证项列为阻断问题并裁决 `HUMAN_GATE`；若证据明确显示错误由某个生产单元造成，则按真实归属裁决 `REPAIR` 并路由该单元。

### 3. 运行机械校验

将 `artifact` 另存为 UTF-8 JSON，按模式运行现有校验器：

| 模式 | 机械校验器 |
|---|---|
| `PLOT` | `../script-plot-progression/scripts/validate_plot_progression.ps1 -Path <artifact.json>` |
| `STORYBOARD_TABLE` | `../storyboard-table-director/scripts/validate_storyboard_artifact.ps1 -Path <artifact.json>` |
| `STORYBOARD_PROMPT` | `../storyboard-image-prompt-director/scripts/validate_storyboard_prompt.ps1 -Path <artifact.json>` |
| `VIDEO_PROMPT` | `../video-prompt-director/scripts/validate_video_prompt.ps1 -Path <artifact.json>`，并把 `body` 单独保存后运行 `validate_body.ps1 -BodyPath <body.txt> -MaxChars <0或5000> -ExpectedDurationSeconds <15或30>`；2.0 用 `0/15`，2.5 用 `5000/30`。批量请求再运行 `validate_prompt_sequence.ps1 -Path <有序规格数组.json>` |

`STORYBOARD_IMAGE` 先校验元数据、资源可访问性和来源链，再实际查看原图。无法打开原图时不得用文件名、缩略图描述或 Prompt 猜测画面。

脚本通过只代表机械结构合格，不等于语义 `PASS`。脚本失败必须转换为带字段路径和实际输出的 QA issue。

### 4. 核对来源链与语义

先从待检字段反向追踪到精确上游版本，再按当前模式清单逐项检查。对每个失败项记录：规则 ID、产物路径或镜头范围、权威预期、当前实际值和可复查证据。不要用“感觉不对”“优化一下”或没有来源定位的结论。

`VIDEO_PROMPT` 中任何可见人物缺少明确位置关系时不得 `PASS`：使用 `VP-POSITION-001`。上游位置事实明确但 S05 未写全或正文未镜像时裁决 `REPAIR`；上游位置事实缺失或冲突时裁决 `HUMAN_GATE`，不得自行补站位。

### 5. 执行变更回归

只要 `change_set` 或 `previous_version` 非空，就比较“上一完整版本＋授权范围＋当前完整版本”。确认指定修改生效，未开放字段和无关镜头保持不变，版本正确递增，字段的必要正文镜像同步，并且相邻 BEAT/镜头连续性仍成立。

### 6. 裁决并路由

- `PASS`：输入门禁、机械结构和全部硬检都通过，所有要求均可验证，`issues` 为空。
- `REPAIR`：每个阻断问题都有明确权威预期、真实责任单元和可执行的最小修复范围，且没有来源冲突或重复失败升级条件。
- `HUMAN_GATE`：权威来源互斥、关键证据缺失、审美或高风险选择无法客观裁决、目标版本过期、最小修复必须越过锁定边界，或同类问题在同一范围连续两轮失败。

下游暴露上游错误时，把 `return_to` 指向真正产生错误的 Skill，并报告最小 `stale_downstream`；不要要求当前 Skill 偷改上游事实。

### 7. 输出与校验

按 [统一协议](references/common-protocol.md) 输出完整 QA 响应。`REPAIR` 必须带最小 RepairTicket；`PASS` 和 `HUMAN_GATE` 的 `repair_ticket` 必须为 `null`。一个对象存在多个互不相干的返修范围时，`repair_ticket` 使用数组，每张票仍只处理一个可共同修复的范围。

将响应保存为 UTF-8 JSON 后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\validate_qa_response.ps1" -Path <qa-response.json>
```

校验失败时先修正 QA 响应，不把无效工单交给生产 Skill。

## 状态与写回边界

- 不直接修改 `artifact`。流程管理器依据裁决写回 `PASS`、`REPAIR` 或 `HUMAN_GATE`。
- `STORYBOARD_TABLE` 只有全部行合格时才 `PASS`；流程管理器必须在同一写回中把父表和全部合格 `shot_map[].status` 原子地设为 `PASS`。
- `STORYBOARD_IMAGE: PASS` 只允许进入人工确认，不等于 `APPROVED`。
- 任一直接上游失效时停止正式放行，并按最小影响范围传播 `STALE`。
- QA 不生成 Plot、分镜表、生图 Prompt、图片、视频 Prompt 或视频，也不代替人工导演确认。

## 完成判定

只有在 S01 流程授权通过、模式正确、权威来源齐全、证据可复查、五选一清单执行完毕、回归范围闭合、裁决符合规则、路由指向真实责任单元，并且 QA 响应通过校验器时完成检查。
