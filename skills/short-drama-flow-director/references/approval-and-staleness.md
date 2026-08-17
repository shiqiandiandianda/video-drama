# 人工确认与局部失效

## 目录

1. 人工确认门禁
2. ApprovedStoryboardSet 写入
3. 局部失效矩阵
4. 变更算法
5. 返修与拒绝路由

## 1. 人工确认门禁（仅 VISUAL_TRACK）

> 本节与 §2 仅在 VISUAL_TRACK 启用；DIRECT_TRACK 不产生图片与人工确认集。

只向导演提交已经 `STORYBOARD_IMAGE: PASS`、资源可访问、版本当前且非 `STALE` 的图片。确认请求逐镜展示 `shot_id`、图片精确 `full_id`、来源 Prompt 精确版本和需要锁定的画面事实。

接受的确认必须能回答“谁在何时确认了哪一个精确版本”。含糊同意、对旧缩略图的回复、只确认父集合或没有 `shot_id` 的批注都不能自动写为 `APPROVED`。

## 2. ApprovedStoryboardSet 写入

沿用 [公共流水线契约](../../_shared/pipeline-contract.md) 的父集合与条目 Schema。额外遵守：

- 父集合 `APPROVED` 只表示本集合版本已锁定，不替代每个条目的 `APPROVED`。
- 条目必须引用当前 StoryboardImage 的稳定 ID、版本、完整 ID和 `source_prompt_full_id`。
- `locked_fields` 至少覆盖构图、景别、人物位置、核心道具和剧情瞬间；可运动项单列在 `allowed_changes`。
- 某镜头更换图片版本时创建新的父集合版本；旧集合保留但不再当前。
- P6 逐镜核对父集合、条目和图片索引三者的精确版本及非失效状态。

## 3. 局部失效矩阵

| 发生变化的上游 | 标记 `STALE` 的最小下游 | 恢复阶段 |
|---|---|---|
| 某个 BEAT | 映射该 BEAT 的 StoryboardRow、同镜头 S04、图片、Approved 条目、覆盖镜头的段级 S05 | P2 |
| 某行 StoryboardRow | 同 `shot_id` 的 S04、图片、Approved 条目、`covered_shot_ids` 含该镜的段级 S05 | P3 |
| 某个 StoryboardPromptSpec | 同 `shot_id` 的图片、Approved 条目、S05 | P4 |
| 图片重新生成/改选版本 | 同 `shot_id` 的 Approved 条目和 S05 | P5 |
| Approved 条目的锁定事实或版本 | 同 `shot_id` 的 S05 | P6 |
| EpisodeHandoff | 下一集 PLOT 及下游全部产物 | 下一集 P1 |
| 项目级画幅/风格锁/人物资产 | 只标记实际依赖该字段的镜头链；无法证明范围时 `HUMAN_GATE` | 最早受影响阶段 |

DIRECT_TRACK 下无 S04/图片/Approved 条目环节：BEAT 或 StoryboardRow 变化直接使覆盖镜头的段级 S05 `STALE`。

不要因一个镜头变化而整集失效；也不要在缺少映射证据时假装能够精确缩小范围。

## 4. 变更算法

1. 定位变化的稳定 ID、旧 `full_id`、新 `full_id`、字段和确认来源。
2. 从 `source_beat_ids[]`、`shot_id`、`source_full_id(s)` 反向查找直接消费者。
3. 只沿实际依赖边向下传播；记录每个失效产物的 `stale_reason` 和 `stale_from_full_id`。
4. 对失效版本同时写 `status: STALE`、`stale: true`；不得改写其历史正文。
5. 如果稳定 ID 有新当前版本，把旧版 `current` 设为 `false`，新版为 `true`。
6. 使包含失效条目的 ApprovedStoryboardSet 创建新版本或进入待重锁定状态；不得保留误导性的全量 `APPROVED`。
7. 将当前阶段回退到最早失效环节，保留不受影响镜头的版本和状态。
8. 写入 `RunLog` 并先调度 `MARK_STALE`；完成写回后再发起重新生产或 QA。

## 5. 返修与拒绝路由

| 证据指向 | 路由 |
|---|---|
| 剧情事实、顺序、人物动机或原始对白错误 | `script-plot-progression` |
| 镜头设计、景别、机位、运镜、动作拆分错误 | `storyboard-table-director` |
| 静态画面 Prompt 转译、素材绑定或负面约束错误 | `storyboard-image-prompt-director` |
| Prompt 正确但实际图片执行失败 | `storyboard-image-generation` |
| 视频 Prompt 转译、时间轴或动作负荷错误 | `video-prompt-director` |

QA 返修必须原样保存 `RepairTicket` 的 `return_to`、范围、证据、`locked_fields` 和剩余尝试次数。人工拒绝不是自动 RepairTicket；先把明确、可执行、范围有限的修改意见正规化为 `ChangeSet`。归属不明、意见互相冲突或修改会越过锁定事实时进入 `HUMAN_GATE`。
