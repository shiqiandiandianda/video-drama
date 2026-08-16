# QA:STORYBOARD_IMAGE 检查清单

## 依据与对象

检查单镜头 `StoryboardImage` 元数据和实际原图，逐项对照当前 `PASS` 的 StoryboardPromptSpec、对应分镜行、真实人物/场景/道具资产和相邻镜连续性。不要只检查 Prompt，也不要用 Prompt 代替看图。

## 检查步骤

1. 校验 `artifact_id`、版本、`shot_id`、`source_beat_ids[]`、`source_prompt_full_id`、资源位置和 `stale: false`。
2. 打开原始分辨率图像；必要时放大手、脸、道具、文字和空间交界处。
3. 同时对照 Prompt 与更高权威的分镜/资产。若 Prompt 自身错误，不要靠重生成掩盖。
4. 记录可定位到画面区域的证据。

## 硬检

| 规则 ID | 检查 | 典型 `issue_type` | 默认所有者 |
|---|---|---|---|
| `IMG-GATE-001` | 资源可打开、版本当前、元数据完整且来源 Prompt 为当前 `PASS` | `IMAGE_GATE_FAILED` | 图片生成阶段 |
| `IMG-PLOT-001` | 画面表现规定的剧情瞬间，没有前移或后移事件 | `STORY_MOMENT_MISMATCH` | 图片生成阶段或 S04 |
| `IMG-SIZE-001` | 实际景别与分镜/Prompt 一致，信息量没有被裁切改变 | `SHOT_SIZE_MISMATCH` | 图片生成阶段 |
| `IMG-CAMERA-001` | 正侧背、俯仰、过肩和视角关系符合锁定机位 | `CAMERA_ANGLE_MISMATCH` | 图片生成阶段 |
| `IMG-COMP-001` | 主体位置、画面重点、前中后景和留白符合构图 | `COMPOSITION_MISMATCH` | 图片生成阶段 |
| `IMG-IDENTITY-001` | 人脸、年龄、发型、服装、伤口等身份特征匹配资产 | `CHARACTER_IDENTITY_MISMATCH` | 图片生成阶段 |
| `IMG-COUNT-001` | 人物无多生、漏生、复制或融合 | `CHARACTER_COUNT_ERROR` | 图片生成阶段 |
| `IMG-SPATIAL-001` | 人物左右、距离、朝向、视线、遮挡和轴线关系正确 | `CHARACTER_POSITION_REVERSED` | 图片生成阶段 |
| `IMG-ACTION-001` | 姿态与指定静态动作瞬间一致，受力和接触可读 | `ACTION_POSE_MISMATCH` | 图片生成阶段 |
| `IMG-PROP-001` | 道具外观、数量、位置、持握手、方向和状态正确 | `PROP_HAND_OR_STATE_MISMATCH` | 图片生成阶段 |
| `IMG-SCENE-001` | 建筑、家具、入口、空间锚点和环境状态无漂移 | `SCENE_STRUCTURE_DRIFT` | 图片生成阶段 |
| `IMG-CONTINUITY-001` | 与前后镜人物、姿势、伤口、道具、环境和光线连续 | `IMAGE_CONTINUITY_BROKEN` | 图片生成阶段或上游 |
| `IMG-QUALITY-001` | 手指、肢体、五官、透视、接触和物体结构无畸变 | `GENERATION_ARTIFACT` | 图片生成阶段 |
| `IMG-TEXT-001` | 无不允许的文字、水印、logo、拼版边框或镜号污染 | `UNWANTED_TEXT_OR_LAYOUT` | 图片生成阶段 |
| `IMG-VIDEO-001` | 作为视频起始画面可用：主体清楚、动作起点稳定、无遮挡性错误 | `NOT_VIDEO_READY` | 图片生成阶段或 S04 |

## 裁决与路由

- 图像执行偏差且 Prompt 正确：`REPAIR`，返回 `storyboard-image-generation`，工单写 `regeneration_constraints[]`。
- Prompt 已经写错位置、道具、人物或静态瞬间：返回 S04；对应旧图片与 S05 失效。
- 分镜设计本身不可成立：返回 S03。
- 权威分镜、资产或人工决定互相冲突：`HUMAN_GATE`。
- `PASS` 只表示可送人工导演确认；不要把图片或父集合直接写成 `APPROVED`。
