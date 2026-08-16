# STORYBOARD_TABLE QA 与返修

## 目录

1. QA 裁决归属
2. 必查项
3. 默认路由
4. 写权限门禁
5. RepairTicket 最小格式
6. 局部返修与语义回归
7. 机械校验器边界

## 1. QA 裁决归属

S03 只生产和自检 `StoryboardTable`。统一 QA 根据 `qa_mode: STORYBOARD_TABLE` 给出：

- `PASS`：全部硬检通过；
- `REPAIR`：问题可定位并可局部修复；
- `HUMAN_GATE`：来源冲突、审美选择、高风险或无法验证，需要导演决定。

不要由生产 Skill 自行宣布 `PASS`。

## 2. 必查项

- [ ] 上游 `PlotProgressionSpec.status` 为 `PASS`，版本未失效。
- [ ] 每个 BEAT 至少映射到一个镜头，且无无来源镜头。
- [ ] 镜头顺序与剧情演进一致，原始对白未遗漏、改写或错配。
- [ ] 固定九列齐全，一镜一行，镜号在场次内连续。
- [ ] 每镜有唯一画面重点和明确导演目的。
- [ ] 景别承载当前空间、动作、关系、表情或道具信息。
- [ ] 机位、视线、轴线、人物左右和出入方向成立。
- [ ] 动作没有过碎或超载，开始、过程、结果和反馈可读。
- [ ] 2—3 秒镜头没有超过 2—3 个清楚动作拍，并且只有一个主要身体目标。
- [ ] 台词与动作同步，并有说话准备和听话人反应。
- [ ] 时长按对应语气的真实语速估算，能容纳动作、对白、停顿和反应。
- [ ] 不存在“对白自然时长达到 60% 且仍叠复杂动作”等硬拆条件。
- [ ] 2 秒以上近景/特写至少有两类可见微表演。
- [ ] 多人镜头不是全员冻结或全员同步反应。
- [ ] 相邻镜头没有无意义重复或无动机跳切。
- [ ] 人物脸发服装、伤口、道具归属、姿势和场景锚点连续。
- [ ] 动作切镜显式继承速度、重心、手持道具、呼吸和惯性/接触反馈。
- [ ] 每镜最多一个主要运镜，且有触发、路径和落点。
- [ ] 表内没有生图/视频模型参数、素材槽位或 Prompt 教程。
- [ ] 表外 `shot_map` 能沿 `shot_id + storyboard_row_version → source_beat_ids[]` 回溯，且并集覆盖表级全部 BEAT。

任一硬检失败时不得放行。

## 3. 默认路由

| 问题来源 | 返回位置 |
|---|---|
| 镜头拆分、景别、机位、运镜、时长、表演、连续性 | S03 分镜表导演 |
| 剧情因果、事件顺序、人物关系、原始对白、BEAT 衔接 | S02 剧情演进导演 |
| 分镜表到静态图提示词的转译 | S04 分镜图提示词导演 |
| 已生成图片与分镜/Prompt 不一致 | 分镜图生成或图像 QA |
| 视频运动/口型/实际末帧问题 | 视频 Prompt 或视频 QA |

## 4. 写权限门禁

继续已有 `StoryboardTable` 前先按当前状态裁决：

| 当前状态 | S03 写权限 |
|---|---|
| `DRAFT` | 可以继续正常编辑 |
| `CHECKING` | 暂停写入，等待统一 QA |
| `REPAIR` | 只允许按匹配当前版本的 RepairTicket 修改目标镜头/字段 |
| `PASS` / `APPROVED` | 不原地改写；只按已确认 ChangeSet 创建新 `DRAFT` 版本 |
| `HUMAN_GATE` | 停止自动推进，等待人工决定 |
| `STALE` | 禁止直接用于下游；按影响范围重新生成，或对当前有效上游重新检查后再恢复使用 |

## 5. RepairTicket 最小格式

```yaml
ticket_id: RT-S01-005-002
qa_mode: STORYBOARD_TABLE
artifact_id: STORYBOARD-E01-S01
artifact_version: V1
full_id: STORYBOARD-E01-S01-V1
verdict: REPAIR
severity: HIGH
issue_type: AXIS_OR_POSITION_CONTINUITY
evidence: 05 镜女主被改到父亲右侧，与 01—04 镜世界站位相反
repair_instruction: 保持摄影机在互动轴合法侧，将 05 镜恢复为女主世界左、父亲世界右
target_shot_ids: [SHOT-E01-S01-005]
target_fields: [机位, 画面描述, 导演备注]
locked_fields: [场景, 镜号, 景别, 秒数/s, 原始对白, 服装, 道具]
return_to: storyboard-table-director
max_attempts_remaining: 1
```

一张票只描述同一镜头内可共同修复的问题。必须提供版本、证据、最小修复、目标镜头/字段和锁定字段。

## 6. 局部返修与语义回归

1. 要求当前状态为 `REPAIR`，验证票据的稳定 ID、版本和 `full_id` 均指向当前版本。
2. 保存修改前的完整 `previous_version`，定位 `target_shot_ids`。
3. 把 RepairTicket 正规化为 `change_set`，记录目标字段、修改前值、修改后值、理由和锁定字段。
4. 只修改 `target_fields`，逐字保留 `locked_fields` 和无关行。
5. 检查前一镜镜尾、本镜动作和后一镜起点。
6. 确认没有引入新剧情、人物、道具、台词或无关镜头变化。
7. 增加表格版本和目标 `storyboard_row_version`；未修改行保留原行版本，并只把目标镜头下游标为 `STALE`。
8. 递减 `max_attempts_remaining`，用完整统一 QA 输入重新调用 `STORYBOARD_TABLE`。

若本次复检仍失败，且同一问题已连续两轮失败或剩余尝试为 0，升级 `HUMAN_GATE`；复检通过则正常放行，不要因计数归零而误拦已修复结果。

导演主动提出且已明确确认的局部改动不是 QA RepairTicket；将其正规化为 ChangeSet，至少记录 `target_shot_ids`、`target_fields`、确认后的值、修改原因和 `locked_fields`。同样执行最小修改、版本递增、相邻镜回归和局部 `STALE` 传播。未确认的建议或备选方案不能成为 ChangeSet。

```yaml
change_set_id: CS-S04-002-001
artifact_id: STORYBOARD-E01-S04
artifact_version: V1
full_id: STORYBOARD-E01-S04-V1
confirmed: true
target_shot_ids: [SHOT-E01-S04-002]
target_fields: [运镜, 导演备注]
changes:
  运镜: 固定
  导演备注: 保持轴线，固定观察台词后的视线回避
reason: 导演确认取消无触发慢推
locked_fields: [剧情, 原始对白, 景别, 机位, 秒数/s, 其余镜头]
```

返修后的 QA 输入必须包含：

```yaml
qa_mode: STORYBOARD_TABLE
artifact: <完整修改后版本>
approved_upstream:
  - <status: PASS 的完整 PlotProgressionSpec>
project_constraints: <画幅、视觉风格、真实度、导演约束>
change_set: <上述精确 ChangeSet；RepairTicket 返修时注明来源 ticket_id>
previous_version: <完整修改前版本>
```

统一 QA 必须比较“修改前版本＋ChangeSet＋修改后版本”，确认指定修改生效、未指定字段/行和行版本不变、没有新增剧情/人物/道具/镜头变化，并且相邻镜连续性仍成立。

## 7. 机械校验器边界

`scripts/validate_storyboard.ps1` 可以检查表头、九列、空字段、镜号、数值时长、明显运镜叠加、Prompt 越界词和部分抽象情绪。它不能可靠判断：

- 剧情是否完整；
- 镜头是否越轴；
- 表演是否真正成立；
- 时长是否足够容纳具体动作和真实语速；
- 景别和机位是否具有最佳叙事效果。

因此脚本零错误不等于 QA `PASS`。
