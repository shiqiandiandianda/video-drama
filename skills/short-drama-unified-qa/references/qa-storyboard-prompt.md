# QA:STORYBOARD_PROMPT 检查清单

## 依据与对象

检查单镜头 `StoryboardPromptSpec`，逐项对照当前 `PASS` 的 StoryboardTable/StoryboardRow、实际资产版本、项目画幅、风格与真实度。需要字段细节时读取 `../storyboard-image-prompt-director/references/image-prompt-contract.md`。

## 硬检

| 规则 ID | 检查 | 典型 `issue_type` | 默认所有者 |
|---|---|---|---|
| `SP-GATE-001` | 直接分镜表与目标行均为当前 `PASS`、非 `STALE` | `UPSTREAM_GATE_FAILED` | `storyboard-image-prompt-director` |
| `SP-TRACE-001` | 一份 Prompt 只对应一个 `shot_id`；版本、行版本、`source_beat_ids[]` 一致 | `PROMPT_TRACE_BROKEN` | `storyboard-image-prompt-director` |
| `SP-FRAME-001` | 景别、机位、视角、画幅和构图忠实于分镜表 | `FRAME_TRANSLATION_MISMATCH` | `storyboard-image-prompt-director` |
| `SP-MOMENT-001` | `selected_moment` 是单一、准确、最有叙事价值的静态停点 | `STATIC_MOMENT_INVALID` | `storyboard-image-prompt-director` |
| `SP-ACTION-001` | 不把动作准备—执行—结果全部塞进一张图 | `CONTINUOUS_ACTION_IN_STATIC_PROMPT` | `storyboard-image-prompt-director` |
| `SP-TIME-001` | 不混入秒数时间轴、口型过程、连续运镜或多阶段变化 | `TEMPORAL_LANGUAGE_IN_STATIC_PROMPT` | `storyboard-image-prompt-director` |
| `SP-CHARACTER-001` | 人数、身份、年龄、外貌、发型、服装和伤口匹配真实资产 | `CHARACTER_BINDING_MISMATCH` | `storyboard-image-prompt-director` |
| `SP-SPATIAL-001` | 人物世界位置、屏幕位置、朝向、视线和遮挡明确且连续 | `CHARACTER_POSITION_REVERSED` | `storyboard-image-prompt-director` |
| `SP-PROP-001` | 道具外观、所有者、持握手、位置、方向和状态正确 | `PROP_STATE_MISMATCH` | `storyboard-image-prompt-director` |
| `SP-SCENE-001` | 场景结构、入口、家具、前中后景和空间锚点不漂移 | `SCENE_ANCHOR_DRIFT` | `storyboard-image-prompt-director` |
| `SP-ASSET-001` | 资产 ID/版本真实可用，槽位不重排、不补号、不伪造 | `ASSET_BINDING_INVALID` | 资产阶段或 S04 |
| `SP-PERFORMANCE-001` | 情绪转为姿势、视线、手部、呼吸等可见表演 | `EMOTION_NOT_VISUALIZED` | `storyboard-image-prompt-director` |
| `SP-ADDITION-001` | 无上游之外的新人物、道具、事件、文字或构图事实 | `UNSUPPORTED_VISUAL_ADDITION` | `storyboard-image-prompt-director` |
| `SP-NEGATIVE-001` | 负面约束可观察、相关、不互相矛盾，不替代正向构图 | `NEGATIVE_CONSTRAINT_INVALID` | `storyboard-image-prompt-director` |
| `SP-TEXT-001` | 默认禁字；只有分镜明确要求才保留精确源文字 | `TEXT_POLICY_VIOLATION` | `storyboard-image-prompt-director` |
| `SP-STYLE-001` | 输出比例、真实度、风格和材质符合项目锁定设置 | `PROJECT_STYLE_MISMATCH` | `storyboard-image-prompt-director` |
| `SP-REGRESSION-001` | 局部修改只触达开放路径及必要镜像，锁定构图和来源不变 | `LOCKED_FIELD_CHANGED` | `storyboard-image-prompt-director` |

## 路由

- Prompt 转译或资产绑定表达错误：返回 S04。
- 分镜表本身的构图、机位、站位、动作拆分或画幅要求错误：返回 S03，并报告同镜头下游失效。
- 资产来源缺失/冲突且无法确认正确版本：`HUMAN_GATE` 或返回资产阶段，不伪造资产编号。
