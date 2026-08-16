# 返修回归与路由

## 目录

1. 错误归属
2. 最小返修
3. 语义回归
4. 重复失败升级
5. 失效传播

## 1. 错误归属

| 错误来源 | `return_to` | 说明 |
|---|---|---|
| 剧情事件、因果、人物关系、原台词、BEAT 状态 | `script-plot-progression` | S02 |
| 镜头拆分、景别、机位、轴线、运镜、时长、表演调度 | `storyboard-table-director` | S03 |
| 静态瞬间转译、资产绑定、构图文字、负面约束 | `storyboard-image-prompt-director` | S04 |
| 图像多生漏生、错脸错手、畸变、画面不符 Prompt | `storyboard-image-generation` | 图片生成阶段 |
| 视频时间轴、动作物理、对白音频、Seedance 正文 | `video-prompt-director` | S05 |
| 两个权威来源冲突、人工审美或授权范围不明 | 无自动路由 | `HUMAN_GATE` |
| 缺少、伪造、未消费或不匹配的 S01 流程授权 | `short-drama-flow-director` | `FLOW-AUTH-001`，`HUMAN_GATE`，禁止内容返修 |

下游检查发现上游设计错误时，路由真正所有者。不要让 S04 改分镜、让 S05 改确认图片，或让图片重生成掩盖错误 Prompt。

## 2. 最小返修

1. 精确绑定当前 `artifact_id`、`artifact_version` 和 `full_id`。
2. 按 `shot_id`、`beat_id` 和 JSON Pointer 定位最小范围。
3. 只开放修复必需字段及其声明过的镜像闭包。
4. 把未开放字段、无关镜头和权威来源列为锁定。
5. 若修复必须改变锁定事实，停止并返回真正上游或进入 `HUMAN_GATE`。
6. 生产 Skill 创建递增版本并恢复 `DRAFT`；不得原地覆盖已检查版本。
7. 返修后重新调用相同 `qa_mode`，旧裁决不得沿用。

## 3. 语义回归

比较 `previous_version`、`change_set` 与当前 `artifact`：

- 目标问题或确认变更已生效；
- 稳定 `artifact_id` 不变，版本只按协议递增，`full_id` 一致；
- `allowed_paths`、`target_fields` 或 `allowed_changes` 以外的值和语义不变；
- 未修改行的行版本不变，目标行版本正确更新；
- 结构字段与 Markdown/body 等派生镜像一致；
- 没有新增剧情、人物、道具、台词、镜头、切镜或无授权运镜；
- 前一单元结束、本单元起止和后一单元起点仍可衔接；
- `source_beat_ids[]`、素材槽位和上游精确版本没有重排或漂移；
- 最小下游 `STALE` 范围已报告。

如果只提供 diff 或摘要而没有两份完整版本，不能完成回归，裁决 `HUMAN_GATE`。

## 4. 重复失败升级

使用 `issue_type + affected_scope/target_shot_ids + owner` 识别同类问题。满足任一条件时裁决 `HUMAN_GATE`：

- 同一问题在同一范围连续两次返修后仍失败；
- 当前票据 `max_attempts_remaining` 已为 0；
- 新问题是前一次返修造成的锁定字段污染，且安全修复需要扩权；
- 证据与人工 `APPROVED` 或确认决定冲突；
- 目标工单指向旧版或 `STALE` 版本。

若复检已经通过，不因剩余次数变为 0 而误拦。

## 5. 失效传播

| 真实变更位置 | 最小 `STALE` 下游 |
|---|---|
| 某 BEAT | 映射该 BEAT 的分镜行，以及对应 S04、图片、S05 |
| 某 StoryboardRow | 同 `shot_id` 的 S04、图片、S05 |
| 某 StoryboardPromptSpec | 同 `shot_id` 的图片与 S05 |
| 某分镜图版本 | 同 `shot_id` 的 S05 |
| 某 VideoPromptSpec | 当前 VP 检查状态；必要时回归相邻镜连续性 |

只报告受影响选择器，不把整集全部标为失效，除非权威证据证明影响确实覆盖整集。
