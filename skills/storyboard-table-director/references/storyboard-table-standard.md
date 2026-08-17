# StoryboardTable 标准

## 目录

1. 输入契约
2. 公开九列表
3. 填写标准
4. 表外追踪数据
5. 编号与版本
6. 交付结构
7. 多场 StoryboardTableSet

## 1. 输入契约

只接受 `status: PASS` 的 `PlotProgressionSpec`。每个 BEAT 应提供：

| 字段 | 作用 |
|---|---|
| `beat_id` | 镜头到剧情的追踪键 |
| `source_ranges` | 来源定位数组，用于回查原剧本和原台词 |
| `start_state` | 包含 `characters/props/environment/knowledge` 的四维镜头起点 |
| `trigger` | 包含 `event/source_range` 的触发对象 |
| `actions` | 按 `order` 排列的可见行动数组 |
| `reactions` | 其他人物的即时反应；来源确实没有时允许空列表 |
| `dialogue` | 原台词对象数组；无对白时使用空数组，不使用单对象或 `null` |
| `emotion_change` | 带证据的变化数组，不直接当画面描述 |
| `end_state` | 与 `start_state` 同构的四维新状态 |
| `continuity` | 下一单元必须继承的事实 |

同时读取人物、场景、服装、伤口、道具、画幅、风格、真实度、镜头约束和前后镜状态。缺失会影响剧情、轴线、资产或连续性的输入时，不生成正式表。

## 2. 公开九列表

固定表头：

```markdown
| 场景 | 镜号 | 景别 | 机位 | 运镜 | 画面描述 | 秒数/s | 人物情绪/细节动作 | 导演备注 |
|---|---:|---|---|---|---|---:|---|---|
```

不添加构图、焦段、光圈、Prompt、状态或 ID 列。若单元格内容含竖线，改用顿号、逗号或分号，避免破坏 Markdown 列数。

## 3. 填写标准

### 场景

使用“时间＋内/外景＋地点”，例如 `日内／酒店房间`、`夜外／旧城巷道`。场景变化必须另起镜头，不在一个单元格并列两个地点。

### 镜号

场次内从 `01` 连续递增。公开镜号允许不同场次重新从 `01` 开始；唯一性由表外 `scene_id + shot_id` 保证。

### 景别

使用能承载画面信息的正式景别：远景、全景、中景、近景、特写等。可使用中远景、中近景等必要过渡，但不要把构图或角度混入本列。

### 机位

描述摄影机实体相对主体的位置和角度，例如：

- 正面平视；
- 女主左肩后过肩平视父亲；
- 走廊墙侧 30° 侧拍；
- 膝高轻仰拍；
- 门框外高位俯拍。

避免只有“电影机位”“压迫角度”或无法验证的“左前方”。

### 运镜

写一个主要运动：固定、推、拉、摇、移、跟拍、环绕、升降、手持等。把触发、路径和落点写入画面描述或导演备注，不在本列堆多个动词。`手持跟拍` 可作为一个统一执行方式；轻微手持起伏不是第二个叙事运镜。

### 画面描述

按以下顺序写成连续、可见、可拍的现在时动作：

```text
环境或构图位置
→ 人物初始状态
→ 触发动作
→ 连续动作过程
→ 动作结果
→ 对白或声音
```

至少让读者知道“谁、在哪里、从什么状态开始、因何动作、如何完成、停在哪里”。原台词使用引号并保留说话人；无台词时可写明确的环境声、动作声或保持不写，不虚构旁白。

### 秒数/s

只填数值，可使用小数，如 `2.5`。时长是镜头从可读起点到动作/反应落点的完整容量，不是主动作本身的理论最短耗时。

### 人物情绪/细节动作

写可观察证据：视线落点、眨眼、吸气、呼气、喉结、嘴角、手指、肩线、重心、步幅、衣料、发丝、停顿、接触反馈。每镜一个主情绪，最多一个辅助情绪。禁止仅写“十分震惊”“内心复杂”“非常担心”“平静”“压迫”。

### 导演备注

只记录对下游有执行价值的内容：

- 镜头目的和唯一画面重点；
- 关系轴合法侧、人物左右、视线和出入方向；
- 道具、服装、伤口、姿势和场景锚点连续性；
- 关键声音、动作触发和镜头落点；
- 需要站位图、白模或人工判断的高风险限制。

不要写教程、完整光学参数表或生成模型负面词。

## 4. 表外追踪数据

公开表前使用产物级元数据；公开表后可提供机器 sidecar。不要把它们变成第十列。

```yaml
artifact_type: StoryboardTable
schema_version: "1.0"
project_id: PROJECT-001
scene_id: SCENE-E01-S01
source_beat_ids:
  - BEAT-E01-S01-001
artifact_id: STORYBOARD-E01-S01
artifact_version: V1
full_id: STORYBOARD-E01-S01-V1
source_artifact_id: PLOT-E01
source_version: V1
source_full_id: PLOT-E01-V1
source_status: PASS
source_stale: false
status: DRAFT
aspect_ratio: "9:16"
visual_style: 写实真人
realism: 高真实度
```

```yaml
shot_map:
  - project_id: PROJECT-001
    scene_id: SCENE-E01-S01
    shot_no: "01"
    shot_id: SHOT-E01-S01-001
    artifact_id: SHOT-E01-S01-001
    artifact_version: V1
    full_id: SHOT-E01-S01-001-V1
    storyboard_row_version: V1
    source_artifact_id: PLOT-E01
    source_version: V1
    source_full_id: PLOT-E01-V1
    source_status: PASS
    source_stale: false
    source_beat_ids: [BEAT-E01-S01-001]
    status: DRAFT
    scene_sub: 住宅-餐厅
    spatial_anchors:
      - {kind: FIXTURE, name: 餐桌, screen_position: 画面中央偏右, description: 长方形木桌}
      - {kind: CAMERA_ANCHOR, name: 主机位, screen_position: 餐厅门侧, description: 朝餐桌方向拍摄}
    screen_lock:
      characters:
        - {name: 女主, screen_side: LEFT, vertical: EYE_LEVEL}
        - {name: 父亲, screen_side: RIGHT, vertical: EYE_LEVEL}
      main_axis: 左→右
      two_shot_same_direction: true
    end_state:
      characters: {女主: 站在餐桌旁等待, 父亲: 抬头看向女主}
      props: {录取通知书: 平放在父亲面前}
      camera: {position: 门侧平视, focus: 父亲眼睛}
      action_stop: 父亲抬头动作完成瞬间
    dialogue_delivery:
      - speaker: 女主
        text_source: BEAT-E01-S01-001#dialogue[0]
        pause_before_keywords: ["考上了"]
        pause_seconds: 0.3
        stress_keywords: ["考上了"]
        primary_gesture: 右手轻推通知书
        after_hold_s: 0.5
    segment_hint: null
    columns:
      scene: 日内／酒店房间
      shot_no: "01"
      shot_size: 全景
      camera_position: 正面平视
      camera_movement: 固定
      visual_description: <完整画面描述>
      duration_s: 3
      performance: <人物情绪/细节动作>
      director_note: <导演备注>
```

一个镜头可覆盖多个紧密相连的 BEAT，一个 BEAT 也可拆为多镜；所有 BEAT 必须至少在 `shot_map` 出现一次。`columns` 是九列表正文的规范机器源，Markdown 表必须由它渲染，禁止分别维护两份可能漂移的正文。

### 机器侧新增字段（十五节渲染的事实源）

- `scene_sub` / `spatial_anchors`：逐镜镜像 S02 同名字段，不得改写；与 S02 不一致即不合格。
- `screen_lock`：本镜人物画面位置锁。`screen_side` 取 `LEFT | RIGHT | CENTER`，`vertical` 取 `HIGH | LOW | EYE_LEVEL`；`main_axis` 写人物主关系轴（如"左→右""门口→床区"）；`two_shot_same_direction` 表示正反打保持同向。同场各镜的 `screen_lock` 不得无理由互换左右或镜像。
- `end_state`（镜尾状态，补丁①）：本镜终帧的人物位置/姿态/视线/手部、道具位置状态、摄影机机位与焦点、动作停点。镜头与 BEAT 为 1:1 覆盖时默认继承所覆盖末个 BEAT 的 `end_state`；一个 BEAT 拆成多镜时，中间镜的 `end_state` 由 S03 显式给出（这是镜头设计决策）。下一镜必须直接继承上一镜 `end_state`，禁止切镜重置。
- `dialogue_delivery`：本镜每句台词的演绎参数——停顿关键词与秒数、重音关键词、主手势、台词后留白秒数；`text_source` 指回 BEAT 的 dialogue 项，台词文本本身禁止在此重复。无对白镜头使用空数组。
- `segment_hint`：可选分段边界建议（`null` 或 `"BREAK_AFTER"` 表示建议本镜之后切段），供 S01 派工与 S05 组段参考；S05 可在时长上限内调整，但不得无理由忽略。

`StoryboardTable` 是单场容器，因此使用单值 `scene_id`。多场请求输出 `StoryboardTableSet` 包装下的多个单场表，每个子表保留自己的全局字段。表级容器没有单一镜头时不要伪造 `shot_id`；把每行视为规范 `StoryboardRow` 子产物，并在 `shot_map` 上完整携带正文、`project_id`、`scene_id`、`shot_id`、稳定产物 ID、版本、来源和状态。

表级 `source_beat_ids` 保存本场全部 BEAT。所有行的 `source_beat_ids` 并集必须与表级集合完全相等，确保没有 BEAT 被漏拍，也没有引用场外 BEAT。

`storyboard_row_version` 是 S04 必须保存的行版本；它应与该行的 `artifact_version` 一致。新表所有行为 `V1`。局部修订时只递增目标行版本，未修改行保留原版本，从而让下游按 `shot_id + storyboard_row_version` 判断是否 `STALE`。

生产阶段表与行均写 `DRAFT`。统一 QA 只有在所有行通过时，才在同一次裁决中把表和每条 `shot_map.status` 写为 `PASS`；任一行 `REPAIR` 或 `HUMAN_GATE` 时，父表不得标为 `PASS`。

## 5. 编号与版本

- `scene_id`：原样沿用上游 `SCENE-E##-S##`。
- `shot_id`：去掉 `scene_id` 的 `SCENE-` 前缀并生成 `SHOT-E##-S##-<三位场次内序号>`。
- `artifact_id`：稳定且不带版本，如 `STORYBOARD-E01-S01`。
- `artifact_version`：首次为 `V1`，任何正式修订递增。
- `full_id`：由稳定 ID 与版本派生，如 `STORYBOARD-E01-S01-V1`。
- `source_artifact_id`、`source_version` 与 `source_full_id`：分别保存直接上游的稳定 ID、版本和完整 ID；`source_status` 必须为 `PASS`，`source_stale` 必须为 `false`。
- 生产阶段写 `DRAFT`；统一 QA 才能给出 `PASS`、`REPAIR` 或 `HUMAN_GATE`。

需求书中的早期 QA/RepairTicket 例子曾把完整 ID 写入名为 `artifact_id` 的字段。接收这种旧格式时先正规化：把带尾部 `-V<n>` 的值保存为 `full_id`，并拆出稳定 `artifact_id` 与独立版本；不要让同一对象同时使用两种语义。

## 6. 交付结构

按以下顺序一次性交付：

1. `输入门禁：通过`，并列出直接上游版本；
2. 产物元数据；
3. 九列表；
4. `shot_map`；
5. 汇总：场次数、镜数、总时长、待确认项；
6. QA 请求：

```yaml
qa_mode: STORYBOARD_TABLE
artifact: <完整当前 StoryboardTable：元数据、九列表、shot_map>
approved_upstream:
  - <status: PASS 的完整 PlotProgressionSpec>
project_constraints:
  aspect_ratio: "9:16"
  visual_style: 写实真人
  realism: 高真实度
  director_constraints: []
change_set: null
previous_version: null
```

首次生成时 `change_set` 和 `previous_version` 为 `null`。局部返修或导演确认修改时，两者必须分别携带本次精确变更和修改前完整版本。`checked_against`、`verdict`、`issues`、`repair_ticket`、`checked_at` 属于 QA 输出，不要冒充 QA 请求字段，也不要在生产 Skill 的交付里伪造 QA 裁决。

## 7. 多场 StoryboardTableSet

多场请求仍为每个场次生成一份完整的单场 `StoryboardTable`。仅使用以下 wrapper 负责排序和汇总，不把多个 `scene_id` 压进单场子产物：

```yaml
artifact_type: StoryboardTableSet
schema_version: "1.0"
project_id: PROJECT-001
artifact_id: STORYBOARD-SET-EP01
artifact_version: V1
full_id: STORYBOARD-SET-EP01-V1
source_artifact_id: PLOT-E01
source_version: V1
source_full_id: PLOT-E01-V1
source_status: PASS
source_stale: false
status: DRAFT
ordered_tables:
  - scene_id: SCENE-E01-S01
    artifact_id: STORYBOARD-E01-S01
    artifact_version: V1
    full_id: STORYBOARD-E01-S01-V1
    shot_count: 6
    total_duration_s: 18.5
  - scene_id: SCENE-E01-S02
    artifact_id: STORYBOARD-E01-S02
    artifact_version: V1
    full_id: STORYBOARD-E01-S02-V1
    shot_count: 4
    total_duration_s: 12
summary:
  scene_count: 2
  shot_count: 10
  total_duration_s: 30.5
```

每个子表都要依次交付自己的元数据、九列表、`shot_map` 和完整五字段 QA 请求。wrapper 本身不替代子表 QA；每个子表分别使用 `qa_mode: STORYBOARD_TABLE`。Set 状态按子表结果汇总：任一 `HUMAN_GATE` 优先为 `HUMAN_GATE`；否则任一 `REPAIR` 为 `REPAIR`；检查中为 `CHECKING`；仅当全部子表 `PASS` 时 Set 才为 `PASS`。`APPROVED` 同样要求全部子表已人工确认。

在一个 Markdown 文件中连续渲染多张九列表时，对整个文件运行校验器；其 `table_count` 必须等于 `ordered_tables` 数量。若子表分文件保存，则逐文件运行。局部修改只递增对应子表及目标行版本，并只使对应 `shot_id` 下游失效。
