# ChangeSet 与 RepairTicket 规则

## 目录

1. 模式边界
2. RepairTicket
3. ChangeSet
4. 字段镜像闭包
5. 版本与状态
6. 回归检查
7. 失败升级

## 1. 模式边界

- `REPAIR`：只响应独立 `QA:VIDEO_PROMPT` 的定位问题。
- `UPDATE`：只响应人类状态为 `CONFIRMED` 的局部变更。
- `CREATE`：不得携带旧工单假装新建，也不得覆盖已有同版本产物。

REPAIR/UPDATE 都从上一完整版本复制，禁止从摘要或自由文本重新生成整份规格。

## 2. RepairTicket

有效工单示例：

```yaml
ticket_id: RT-S01-003-002
qa_mode: VIDEO_PROMPT
artifact_id: VP-E01-S01-003
artifact_version: V1
full_id: VP-E01-S01-003-V1
verdict: REPAIR
severity: HIGH
issue_type: PROP_HAND_MISMATCH
evidence: <分镜图和连续性台账均锁定右手，当前 Prompt 写成左手>
repair_instruction: <仅把持物手恢复为右手>
allowed_changes:
  - /start_state/props/0/holder_or_contact
  - /action_flow/timeline/0/action_physics
locked_fields:
  - /camera
  - /dialogue_audio
  - /task/target_duration_seconds
return_to: video-prompt-director
max_attempts_remaining: 1
```

校验：

1. `qa_mode` 必须是 `VIDEO_PROMPT`。
2. `artifact_id` 必须精确等于上一版 `video_prompt_id`/完整 ID。
3. 必须有证据、最小修复指令、开放字段和锁定字段。
4. 工单不得要求 S05 修改 APPROVED 分镜、剧情演进、分镜表或原始对白。
5. 返修后重新调用同一 QA，不沿用旧 PASS/REPAIR 结论。

## 3. ChangeSet

有效更新示例：

```yaml
change_id: CS-VP-E01-S01-003-001
source: HUMAN_DIRECTOR
status: CONFIRMED
target_artifact_id: VP-E01-S01-003
target_full_id: VP-E01-S01-003-V1
affected_scope:
  - SHOT-E01-S01-003
allowed_changes:
  - /dialogue_audio/0/voice
  - /action_flow/timeline/1/performance
locked_fields:
  - /approved_image_full_id
  - /start_state
  - /camera
  - /dialogue_audio/0/exact_text
decision_ref: DEC-024
```

`TENTATIVE`、`DRAFT`、口头建议或“顺便优化”不能进入正式更新。ChangeSet 影响多个镜头时，按 `shot_id` 分解，每个 S05 产物独立递增版本。

若 ChangeSet 开放的字段需要改变锁定时长、景别、机位、人物位置或原台词才可执行，停止并请求扩大明确授权/返回上游，不自行扩权。

## 4. 字段镜像闭包

结构化字段会镜像到 `body_sections/body`。修复一个事实时，允许同步修改它的文字镜像；这种依赖修改必须写入 `change_log`，不算新的创意授权。

| 开放结构字段 | 允许同步的正文镜像 |
|---|---|
| `/reference_bindings` | `body_sections.reference_materials` 和对应 body 段 |
| `/start_state` | `body_sections.approved_start_and_spatial_state` 和必要的时间轴起点 |
| `/start_state/characters` 人物位置关系 | 相关 `action_flow.timeline[*].spatial_execution`、`end_state.characters`、`body_sections.approved_start_and_spatial_state` 和 `body` |
| `/action_flow/timeline` | `body_sections.continuous_timeline` |
| `/dialogue_audio` | 对应时间段文字；不得改 `exact_text`，除非其路径明确开放且有上游确认 |
| `/camera` | 对应时间段的运镜执行与 `body_sections.imaging` |
| `/lighting_color_material` | 动作点中的声光镜像和 `body_sections.imaging` |
| `/sound` | 时间轴声音镜像和 `body_sections.sound_continuity_stability` |
| `/end_state` | 时间轴停点和连续性约束；不得改成 ACTUAL |

禁止利用“body 需要同步”重写无关句子、加强情绪、更换焦段或调整其他时间段。

## 5. 版本与状态

每次有效 REPAIR/UPDATE：

- `artifact_id` 保持不变；
- `artifact_version` 递增 1；
- `video_prompt_id` 更新为新完整 ID；
- 直接上游 ID/版本保持不变，除非 ChangeSet 本身由新上游版本触发；
- `status` 重置为 `DRAFT`；
- `qa_request` 指向全部当前有效来源；
- `change_log` 记录旧值、请求、实际新值、镜像字段和未变项。

上游版本变化不是普通 REPAIR。先按影响范围把旧 VP 标记 `STALE`，再以 UPDATE/重建流程引用新上游。

## 6. 回归检查

比较：上一版本 + RepairTicket/ChangeSet + 新版本。

必须确认：

1. 点名问题已修复/变更已生效。
2. 所有 `locked_fields` 值和语义完全不变。
3. 未开放时间段、对白、人物、道具、机位、槽位和模型设置不变。
4. 字段镜像只发生在第 4 节允许的依赖闭包。
5. `video_prompt_id` 正确递增，`status` 为 `DRAFT`。
6. 时间轴仍连续，总长未漂移。
7. 未开放的 Mixed 对象没有换槽；全部槽位仍从 1 连续自增，正文与绑定一致；原始对白仍逐字匹配。
8. 2.0 仍为 15 秒；2.5 仍为 30 秒且不超过 5000 字。
9. 当前镜头与上一镜、下一镜的两侧 handoff 签名均已重新检查且一致。
10. 修改未引入新人物、道具、剧情、切镜或运镜。

## 7. 失败升级

- 同类问题连续两次返修失败：`HUMAN_GATE`。
- 工单证据与 APPROVED 图片/锁定上游冲突：`HUMAN_GATE`。
- 最小修复需要改变镜头设计：返回 S03 并传播相关 `STALE`。
- 最小修复需要改剧情或台词：返回 S02。
- 工单目标版本已过期或 `STALE`：拒绝在旧版上返修，先重新定位当前版本。
- 允许范围不清楚：只报告冲突路径和需要确认的授权，不自行猜测。
