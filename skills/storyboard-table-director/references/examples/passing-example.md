# 通过格式样例

以下样例用于校准 S03 公开九列表和表外追踪方式，不是可复用剧情模板。

## 目录

1. 输入摘要
2. 产物元数据
3. 人类可读九列表
4. 追踪 sidecar 与 QA 请求

## 输入摘要

```yaml
artifact_id: PLOT-E01
artifact_version: V1
full_id: PLOT-E01-V1
status: PASS
project_id: DEMO-001
scene_id: SCENE-E01-S03
aspect_ratio: 9:16
visual_style: 写实家庭短剧，克制温暖
realism: 高真实度
character_assets:
  女主: 18岁，浅色衬衫，深色长裤，右手持录取通知书
  父亲: 48岁，深蓝工装衬衫，坐在餐桌右侧
scene_asset:
  time_and_place: 日内／餐厅
  anchors: 门在世界西侧，餐桌居中，父亲座位在桌世界东侧
prop_assets:
  录取通知书: 起始在女主右手，纸角轻微卷起
director_constraints:
  - 保持女主世界左、父亲世界右，不跨桌面关系轴
previous_shot_continuity: 本场首个 BEAT；按 start_state 建立空间
beat_id: BEAT-E01-S03-004
source_ranges: [SCRIPT-E01-V1:L18-L23]
start_state:
  characters:
    女主: 站在门口，右手拿录取通知书
    父亲: 坐在餐桌右侧，尚未注意通知书
  props:
    录取通知书: 女主右手持有
  environment: {}
  knowledge:
    父亲: 尚不知道录取结果
trigger:
  event: 女主决定公布录取结果
  source_range: SCRIPT-E01-V1:L18
actions:
  - order: 1
    actor: 女主
    action: 走近餐桌
    source_range: SCRIPT-E01-V1:L18-L19
  - order: 2
    actor: 女主
    action: 将通知书放到父亲面前
    target: 父亲
    source_range: SCRIPT-E01-V1:L20
reactions:
  - order: 3
    actor: 父亲
    reaction: 先低头看通知书
    source_range: SCRIPT-E01-V1:L21
  - order: 5
    actor: 父亲
    reaction: 看清内容后抬头看女主
    source_range: SCRIPT-E01-V1:L23
dialogue:
  - order: 4
    speaker: 女主
    text: 爸，我考上了。
    timing: 通知书放稳后
    source_range: SCRIPT-E01-V1:L22
emotion_change:
  - character: 女主
    from: 紧张等待
    to: 释放但仍克制
    evidence: [SCRIPT-E01-V1:L18-L22]
  - character: 父亲
    from: 日常平静
    to: 明显惊讶
    evidence: [SCRIPT-E01-V1:L21-L23]
end_state:
  characters:
    父亲: 准备伸手拿起通知书
  props:
    录取通知书: 位于父亲面前的桌面
  environment: {}
  knowledge:
    父亲: 已知女主考上
continuity:
  must_carry_forward:
    - 通知书位于父亲面前的桌面
  open_actions:
    - 父亲准备从桌面拿起通知书
```

## 产物元数据

```yaml
artifact_type: StoryboardTable
schema_version: "1.0"
project_id: DEMO-001
scene_id: SCENE-E01-S03
source_beat_ids: [BEAT-E01-S03-004]
artifact_id: STORYBOARD-E01-S03
artifact_version: V1
full_id: STORYBOARD-E01-S03-V1
source_artifact_id: PLOT-E01
source_version: V1
source_full_id: PLOT-E01-V1
source_status: PASS
source_stale: false
status: DRAFT
aspect_ratio: "9:16"
visual_style: 写实家庭短剧，克制温暖
realism: 高真实度
```

## 人类可读九列表

| 场景 | 镜号 | 景别 | 机位 | 运镜 | 画面描述 | 秒数/s | 人物情绪/细节动作 | 导演备注 |
|---|---:|---|---|---|---|---:|---|---|
| 日内／餐厅 | 01 | 全景 | 餐厅门侧平视关系位 | 固定 | 餐桌占画面右侧，父亲坐在右侧低头整理碗筷；女主从画面左后方门口进入，右手把通知书贴在腿侧，沿桌左侧走近后停在父亲对面。脚步声停下。 | 3 | 女主步幅偏小，左手指尖反复压住衣角；父亲仍按原节奏摆正碗筷。 | 建立女主世界左、父亲世界右和桌面关系轴；下一镜保持同一轴侧。 |
| 日内／餐厅 | 02 | 中景 | 父亲右肩后过肩平视女主 | 轻缓推近 | 女主位于画面左中部，通知书仍在右手；父亲抬眼触发镜头由中景轻推至中近景，女主吸气后把通知书从腿侧抬到桌面上方，手臂越过桌沿。 | 2.5 | 女主视线先落在父亲手边再抬到他脸上，吸气后肩线短暂绷紧；父亲手上动作停住。 | 推镜由父亲抬眼触发，落在通知书进入二人之间；不跨桌面关系轴。 |
| 日内／餐厅 | 03 | 近景 | 桌边侧拍女主手与父亲前臂 | 固定 | 桌面位于画面下方，女主右手托着通知书从左侧进入；纸张落到父亲面前，指腹压平卷起的纸角后松开，手收回桌沿外。纸面轻响。 | 2 | 女主松手前拇指摩挲纸角，松开后手指仍微蜷；父亲前臂停住，没有提前拿起。 | 锁定通知书归属由女主右手转移至桌面父亲前方；下一镜父亲从此处读取。 |
| 日内／餐厅 | 04 | 中近景 | 女主左肩后过肩平视父亲 | 固定 | 通知书位于父亲面前下方，父亲先低头看清标题，呼吸停住半拍后抬眼看向画面左侧女主；画外女主在纸张放稳后说：“爸，我考上了。” | 3 | 父亲眼神先沿纸面移动，喉结轻滑后迅速抬眼；女主画外说话前有短促吸气。 | 原台词逐字保留；父亲视线朝世界左；保留听话人反应并停在父亲准备伸手的状态。 |

## 追踪 sidecar

```yaml
shot_map:
  - project_id: DEMO-001
    scene_id: SCENE-E01-S03
    shot_no: "01"
    shot_id: SHOT-E01-S03-001
    artifact_id: SHOT-E01-S03-001
    artifact_version: V1
    full_id: SHOT-E01-S03-001-V1
    storyboard_row_version: V1
    source_artifact_id: PLOT-E01
    source_version: V1
    source_full_id: PLOT-E01-V1
    source_status: PASS
    source_stale: false
    source_beat_ids: [BEAT-E01-S03-004]
    status: DRAFT
    columns:
      scene: 日内／餐厅
      shot_no: "01"
      shot_size: 全景
      camera_position: 餐厅门侧平视关系位
      camera_movement: 固定
      visual_description: 餐桌占画面右侧，父亲坐在右侧低头整理碗筷；女主从画面左后方门口进入，右手把通知书贴在腿侧，沿桌左侧走近后停在父亲对面。脚步声停下。
      duration_s: 3
      performance: 女主步幅偏小，左手指尖反复压住衣角；父亲仍按原节奏摆正碗筷。
      director_note: 建立女主世界左、父亲世界右和桌面关系轴；下一镜保持同一轴侧。
  - project_id: DEMO-001
    scene_id: SCENE-E01-S03
    shot_no: "02"
    shot_id: SHOT-E01-S03-002
    artifact_id: SHOT-E01-S03-002
    artifact_version: V1
    full_id: SHOT-E01-S03-002-V1
    storyboard_row_version: V1
    source_artifact_id: PLOT-E01
    source_version: V1
    source_full_id: PLOT-E01-V1
    source_status: PASS
    source_stale: false
    source_beat_ids: [BEAT-E01-S03-004]
    status: DRAFT
    columns:
      scene: 日内／餐厅
      shot_no: "02"
      shot_size: 中景
      camera_position: 父亲右肩后过肩平视女主
      camera_movement: 轻缓推近
      visual_description: 女主位于画面左中部，通知书仍在右手；父亲抬眼触发镜头由中景轻推至中近景，女主吸气后把通知书从腿侧抬到桌面上方，手臂越过桌沿。
      duration_s: 2.5
      performance: 女主视线先落在父亲手边再抬到他脸上，吸气后肩线短暂绷紧；父亲手上动作停住。
      director_note: 推镜由父亲抬眼触发，落在通知书进入二人之间；不跨桌面关系轴。
  - project_id: DEMO-001
    scene_id: SCENE-E01-S03
    shot_no: "03"
    shot_id: SHOT-E01-S03-003
    artifact_id: SHOT-E01-S03-003
    artifact_version: V1
    full_id: SHOT-E01-S03-003-V1
    storyboard_row_version: V1
    source_artifact_id: PLOT-E01
    source_version: V1
    source_full_id: PLOT-E01-V1
    source_status: PASS
    source_stale: false
    source_beat_ids: [BEAT-E01-S03-004]
    status: DRAFT
    columns:
      scene: 日内／餐厅
      shot_no: "03"
      shot_size: 近景
      camera_position: 桌边侧拍女主手与父亲前臂
      camera_movement: 固定
      visual_description: 桌面位于画面下方，女主右手托着通知书从左侧进入；纸张落到父亲面前，指腹压平卷起的纸角后松开，手收回桌沿外。纸面轻响。
      duration_s: 2
      performance: 女主松手前拇指摩挲纸角，松开后手指仍微蜷；父亲前臂停住，没有提前拿起。
      director_note: 锁定通知书归属由女主右手转移至桌面父亲前方；下一镜父亲从此处读取。
  - project_id: DEMO-001
    scene_id: SCENE-E01-S03
    shot_no: "04"
    shot_id: SHOT-E01-S03-004
    artifact_id: SHOT-E01-S03-004
    artifact_version: V1
    full_id: SHOT-E01-S03-004-V1
    storyboard_row_version: V1
    source_artifact_id: PLOT-E01
    source_version: V1
    source_full_id: PLOT-E01-V1
    source_status: PASS
    source_stale: false
    source_beat_ids: [BEAT-E01-S03-004]
    status: DRAFT
    columns:
      scene: 日内／餐厅
      shot_no: "04"
      shot_size: 中近景
      camera_position: 女主左肩后过肩平视父亲
      camera_movement: 固定
      visual_description: 通知书位于父亲面前下方，父亲先低头看清标题，呼吸停住半拍后抬眼看向画面左侧女主；画外女主在纸张放稳后说：“爸，我考上了。”
      duration_s: 3
      performance: 父亲眼神先沿纸面移动，喉结轻滑后迅速抬眼；女主画外说话前有短促吸气。
      director_note: 原台词逐字保留；父亲视线朝世界左；保留听话人反应并停在父亲准备伸手的状态。
```

```yaml
summary:
  scene_count: 1
  shot_count: 4
  total_duration_s: 10.5
  human_gate_items: []
qa_request:
  qa_mode: STORYBOARD_TABLE
  artifact: <上述完整 STORYBOARD-E01-S03-V1>
  approved_upstream:
    - <完整 PLOT-E01-V1，status: PASS>
  project_constraints:
    aspect_ratio: "9:16"
    visual_style: 写实家庭短剧，克制温暖
    realism: 高真实度
    director_constraints:
      - 保持女主世界左、父亲世界右，不跨桌面关系轴
  change_set: null
  previous_version: null
```
