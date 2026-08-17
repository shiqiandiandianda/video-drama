# StoryboardPromptSpec 契约

## 目录

1. 产物边界
2. 完整字段
3. 字段约束
4. Positive Prompt 顺序
5. 批量交付
6. QA 交接

## 1. 产物边界

一个 `StoryboardPromptSpec` 只描述一个 `shot_id` 的一张静态图。它是 S04 的唯一主产物，状态由 S04 写为 `DRAFT`，由独立 QA 裁决为 `PASS`、`REPAIR` 或 `HUMAN_GATE`。

## 2. 完整字段

```yaml
schema_version: "1.0"
project_id: PRJ-001
scene_id: SCENE-E01-S01
shot_id: SHOT-E01-S01-003
source_beat_ids:
  - BEAT-E01-S01-002
artifact_id: SP-E01-S01-003
artifact_version: V1
full_id: SP-E01-S01-003-V1
prompt_id: SP-E01-S01-003-V1
source_artifact_id: STORYBOARD-E01-S01
source_version: V2
source_full_id: STORYBOARD-E01-S01-V2
source_status: PASS
source_stale: false
storyboard_row_version: V2
source_row_full_id: SHOT-E01-S01-003-V2
source_row_status: PASS
source_row_stale: false
status: DRAFT

frame_role: STORYBOARD_KEYFRAME
selected_moment:
  phase: FIRST_CONTACT
  source_evidence: "女主将通知书放到父亲面前。"
  frozen_state: "女主右手刚将通知书平放到父亲面前，指腹尚未离开纸面。"
  selection_reason: "通知书归属、动作结果与父女反应关系同时可见。"

visual_style_lock: LIVE_ACTION_REALISM   # 镜像 ProjectManifest，必填
style_pack_positive: <镜像 _shared/style-packs.md 本项目风格锁正词包全文>
style_pack_negative: <镜像 _shared/style-packs.md 本项目风格锁负词包全文>

reference_numbering:                     # 固定编号：角色→场景→道具，各类内按名称排序，从 1 连续
  - {image_no: 1, ref: 女主}
  - {image_no: 2, ref: 父亲}
  - {image_no: 3, ref: 客厅}
  - {image_no: 4, ref: 录取通知书}

positive_prompt: >-
  <一条完整、可直接提交生图模型的静态画面提示词>

asset_requirements:
  character_count: 2
  scene_count: 1
  prop_count: 1

asset_bindings:
  characters:
    - name: 女主
      asset_id: CHAR-LIN-01
      asset_version: V3
      reference_role: IDENTITY_APPEARANCE
      inherit:
        - 成年年龄层、脸型、五官、发型
        - 本场服装与伤痕状态
      ignore:
        - 参考图背景、姿势、文字和水印
  scene:
    - name: 客厅
      asset_id: SCENE-HOME-01
      asset_version: V2
      reference_role: SPACE_STYLE
      inherit:
        - 房间结构、家具位置、门窗和主光方向
      ignore:
        - 参考图人物和生成瑕疵
  props:
    - name: 录取通知书
      asset_id: PROP-LETTER-01
      asset_version: V1
      reference_role: PROP_APPEARANCE
      inherit:
        - 尺寸、封面结构和纸张颜色
      ignore:
        - 未经剧本确认的文字

camera:
  shot_size: 中景
  viewpoint: 正面平视
  camera_height: 1.35m
  axis_side: 父女互动轴合法侧 A
  composition: 女主位于画面左侧，父亲位于右侧，桌面构成下方前景
  focal_length_mm: 50
  aperture_f: 4
  focus_target: 女主右手、通知书与父亲面部处于可辨焦平面
  depth_of_field: 双人和通知书清楚，后方家具轻柔化但结构可辨

spatial_continuity:
  world_positions:
    - 女主站在茶几西侧，父亲坐在茶几东侧
  screen_projection:
    - 本机位投影为女主画面左、父亲画面右
  anchors:
    - 父亲右后方的落地窗
    - 画面下方横向茶几边缘
  previous_shot_inheritance:
    - 女主右手持通知书
  next_shot_handoff:
    - 通知书平放在父亲正前方，女主右手尚未完全离开

prop_states:
  - prop: 录取通知书
    owner: 女主
    contact: 女主右手指腹仍接触封面右上角
    position: 茶几中央偏父亲一侧
    orientation: 封面正向父亲
    state: 完整、平放、未被父亲拿起

text_policy:
  mode: FORBIDDEN
  exact_source_text: null

locked_fields:
  - 剧情瞬间
  - 景别
  - 机位
  - 人物数量与身份
  - 人物位置
  - 核心道具
  - 画幅

negative_constraints:
  - 不新增、删减或重复人物
  - 不交换父女的画面位置
  - 通知书不换手、不悬空、不变形
  - 无字幕、标题、镜号、边框、logo、水印
  - 无手指融合、肢体穿插和海报式正面摆拍

aspect_ratio: "9:16"
unresolved_fields: []
change_log: []
```

## 3. 字段约束

- `artifact_id` 不含版本；`full_id` 与兼容别名 `prompt_id` 均等于 `artifact_id + "-" + artifact_version`。
- `source_artifact_id` 与 `source_version` 必须指向实际 `PASS` 的分镜表。
- `source_full_id` 必须等于 `source_artifact_id + "-" + source_version`。
- `source_row_full_id` 必须等于 `shot_id + "-" + storyboard_row_version`，并指向状态为 `PASS` 的规范 `StoryboardRow`。
- `source_status` 与 `source_row_status` 均必须为 `PASS`，两个 `source_stale` 字段均必须为 `false`。
- `source_beat_ids` 必须与当前 PASS `StoryboardRow` 完全一致且非空；禁止降格为单数 `source_beat_id`。
- `frame_role` 默认为 `STORYBOARD_KEYFRAME`；只有上游明确要求时使用 `VIDEO_START_CANDIDATE`、`END_FRAME` 或 `GRAPHIC_CARD`。
- `selected_moment.source_evidence` 必须引用或忠实摘录分镜行，不写新剧情。
- `asset_requirements` 来自 PASS `StoryboardRow` 和资产台账，数量必须与三个 `asset_bindings` 数组一致。空镜头允许 `character_count: 0`，但真人镜头不得通过空数组绕过已出现人物；关键道具数量同理。
- `focal_length_mm` 和 `aperture_f` 使用单一可实现值，不写区间；若项目未要求光学字段，可保留字段并写 `PROJECT_UNSPECIFIED`，不得伪称锁定。
- `screen_projection` 是目标摄影机下的画面投影，不等于世界坐标。
- `unresolved_fields` 非空且涉及身份、位置、关键道具、画幅或风格时，不得交付可投喂 Prompt。
- `negative_constraints` 使用数组，每项只描述一种可见失败。
- 默认 `text_policy.mode: FORBIDDEN`。源分镜明确要求画面文字时改为 `EXACT_SOURCE_TEXT`，并逐字填写。
- `visual_style_lock` 必填且与 ProjectManifest 一致；`style_pack_positive` 必须逐字镜像 `_shared/style-packs.md` 对应风格正词包，`style_pack_negative` 逐字镜像负词包并整体并入 `negative_constraints`；两词包互斥，出现对方风格锁词汇即不合格。
- `reference_numbering` 全项目固定：先角色、再场景、再道具，各类内按名称排序，从 1 连续编号；同一对象在全项目所有规格中编号不变。正文引用参考图时必须写作"图1是女主"式声明，禁止"参考图""上图"等无编号指代。

## 4. Positive Prompt 顺序

使用一个连续段落，依次写：

```text
单张静态任务与画幅
→ 参考图固定编号声明（"图1是女主，图2是父亲，图3是客厅，图4是录取通知书"）
→ 项目风格锁正词包（逐字镜像）、真实度、时代和时间
→ 场景结构与锚点
→ 景别、机位、镜头高度、构图、焦点和景深
→ 逐人物身份、位置、朝向、视线、重心和双手
→ 唯一动作冻结点和道具状态
→ 可见情绪表演
→ 主光、负补、轮廓、实景光池、明暗分区、高光落点
→ 色彩、材质、空气与连续性
```

Prompt 自身必须自包含，不能只写“同上一镜”“按参考图”“保持连续”。资产引用与连续性要在正文中转译成可见事实；参考图只用 `reference_numbering` 的固定编号指代。

## 5. 批量交付

批量时按镜号顺序输出多个独立规格：

```text
SHOT-E01-S01-001 / SP-E01-S01-001-V1
<完整 StoryboardPromptSpec>

SHOT-E01-S01-002 / SP-E01-S01-002-V1
<完整 StoryboardPromptSpec>
```

不得把多个镜头合并成一条 Prompt，也不得让模型直接生成带镜号的多格接触表。单张图审核通过后，拼版工具才能把图片放入 16 格或其他模板；模板编号不是画面内容。

**分镜页 Prompt（评审专用）**：为人工导演整页评审，可用 `scripts/render_page_prompt.ps1` 把同页 2–10 个已 `PASS` 的 `StoryboardPromptSpec` 机械拼装成一条多格页 Prompt：版式固定 2 列 5 行，格号与镜号一一对应；三种模式 `COLOR`（彩色完成稿）、`LINEART_REVIEW`（线稿评审稿，灰阶线稿 + 运镜箭头 + 人物/道具标签）、`LINEART_CLEAN`（净线稿）。页 Prompt 只能由渲染器生成，手工编写或改写即不合格；单镜 `StoryboardPromptSpec` 仍是唯一事实主源，页 Prompt 不引入任何单镜规格之外的事实。

## 6. QA 交接

```yaml
qa_request:
  qa_mode: STORYBOARD_PROMPT
  artifact: <完整 StoryboardPromptSpec DRAFT>
  approved_upstream:
    - <STORYBOARD-E01-S01-V2 及 SHOT-E01-S01-003-V2，status: PASS>
    - <实际使用的资产版本>
  project_constraints: <画幅、风格、真实度和锁定规则>
  change_set: null
  previous_version: null
```

S04 不填写实际 `verdict`。QA 响应使用同一产物 `full_id`，不得把完整 ID 填入稳定 `artifact_id`。
