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
| `IMG-STYLE-001` | 画面风格与 Manifest `visual_style_lock` 及对应风格词包一致：真人实景轨不得出现 CG/插画感，国漫 3D 轨不得出现实拍质感 | `STYLE_LOCK_VIOLATION` | 图片生成阶段或 S04 |
| `IMG-PAGE-001` | 页模式：2 列 5 行版式正确，固定编号"图 N"与镜号一一对应，不多格不缺格 | `PAGE_LAYOUT_INVALID` | 图片生成阶段或 S04 |
| `IMG-PAGE-002` | 页模式：同页各格场景、光线、锚点一致，不发生同页场景乱切 | `PAGE_SCENE_JUMP` | 图片生成阶段或 S04 |
| `IMG-PAGE-003` | 页模式：运镜箭头与分镜行 `camera_movement` 一致，不缺失、不全部同向 | `PAGE_ARROW_INVALID` | 图片生成阶段或 S04 |
| `IMG-PAGE-004` | 页模式：人物/道具标签正确、不缺漏、不遮挡脸部 | `PAGE_LABEL_INVALID` | 图片生成阶段或 S04 |
| `IMG-LINEART-001` | LINEART_REVIEW 模式保持线稿/灰阶：无彩色主体、无灰阶写实化漂移 | `LINEART_MODE_DRIFT` | 图片生成阶段 |

## 评级

每张图（或每个页模式产物）在硬检之外给出执行评级，写入 QA 响应：

| 评级 | 含义 | 处置 |
|---|---|---|
| S | 构图、身份、位置、瞬间全部到位，可直接作为视频起始画面 | 送人工确认 |
| A | 剧情/位置/身份正确，仅有不影响信息的轻微执行瑕疵（材质、背景细节轻微漂移） | 可送人工确认，须标注瑕疵点 |
| B | 存在任一硬检问题 | `REPAIR`，不得送人工确认 |

## 一票否决清单

任一命中直接 `REPAIR`（根因冲突时 `HUMAN_GATE`），不进入评级：

- 画面出现对白气泡、说明栏文字或任何非授权文字；
- 线稿评审模式出现彩色主体，或灰阶被写实化；
- 人物屏幕左右反转（违反 `screen_lock`/分镜行）；
- 越轴（互动轴/运动轴方向错误）；
- 场景锚点消失（S02 `spatial_anchors` 登记锚点在应有画面中不可见）；
- 页模式同页场景乱切；
- 页模式运镜箭头缺失或全部同向；
- 页模式标签错漏或遮挡脸部；
- 人物变脸（格间/镜间身份特征不一致）。

## 裁决与路由

- 图像执行偏差且 Prompt 正确：`REPAIR`，返回 `storyboard-image-generation`，工单写 `regeneration_constraints[]`。
- Prompt 已经写错位置、道具、人物或静态瞬间：返回 S04；对应旧图片与 S05 失效。
- 分镜设计本身不可成立：返回 S03。
- 权威分镜、资产或人工决定互相冲突：`HUMAN_GATE`。
- `PASS` 只表示可送人工导演确认；不要把图片或父集合直接写成 `APPROVED`。
