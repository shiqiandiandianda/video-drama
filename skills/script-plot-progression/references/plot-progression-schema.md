# PlotProgressionSpec 契约

## 目录

- [规范格式](#规范格式)
- [顶层字段](#顶层字段)
- [来源覆盖](#来源覆盖)
- [场次字段](#场次字段)
- [BEAT 字段](#beat-字段)
- [状态对象](#状态对象)
- [冲突与未知项](#冲突与未知项)
- [不变量](#不变量)
- [完整最小示例](#完整最小示例)

## 规范格式

使用 UTF-8 JSON 保存正式机器产物。允许在聊天中附 Markdown 摘要或 YAML 展示，但不得让展示版替代 JSON 正式产物。

建议文件名：

```text
plot-progression-E01-V1.json
```

不要在 S02 产物中创建 `shot_id`。镜头 ID 从 S03 开始生成。

## 顶层字段

| 字段 | 类型 | 要求 |
|---|---|---|
| `schema_version` | string | 当前固定为 `1.0` |
| `project_id` | string | 项目内稳定唯一 |
| `artifact_id` | string | 推荐 `PLOT-E01` |
| `artifact_version` | string | `V1`、`V2` 递增 |
| `full_id` | string | 必须等于 `artifact_id-artifact_version` |
| `source_artifact_id` | string | 主要原剧本 ID |
| `source_version` | string | 主要原剧本版本 |
| `source_full_id` | string | 必须等于 `source_artifact_id + "-" + source_version` |
| `source_artifacts` | array | 所有实际使用来源 |
| `status` | string | `DRAFT` 或 `HUMAN_GATE`；外部 QA/流程可写入其他全局状态 |
| `scope` | object | 集号和场次 ID 范围 |
| `coverage_summary` | object | 事件和对白覆盖计数 |
| `source_coverage` | array | 每项剧情事实的来源覆盖 |
| `decision_overrides` | array | 已确认导演覆盖记录 |
| `conflicts` | array | 未裁决来源冲突 |
| `unknowns` | array | 资料未知项 |
| `scenes` | array | 按剧情顺序排列的场次 |
| `impact_scope` | object | UPDATE/REPAIR 的最小影响范围；CREATE 可为空数组 |

`source_artifacts` 项使用：

```json
{
  "source_id": "SCRIPT-E01",
  "source_type": "SCRIPT",
  "version": "V1",
  "scope": "E01",
  "locator_type": "LINE",
  "path": "D:\\project\\episode-01.txt"
}
```

允许的 `source_type`：

- `SCRIPT`
- `CONFIRMED_DECISION`
- `CHARACTER_RELATION`
- `SCENE_FACT`
- `ASSET_CONSTRAINT`
- `TRANSCRIPT`

`TRANSCRIPT` 只有在相应内容已经标记确认状态时才能覆盖剧本。

## 来源覆盖

每个剧情事件和每句对白建立一个覆盖项：

```json
{
  "coverage_id": "COV-E01-0001",
  "source_range": "SCRIPT-E01-V1:L18-L20",
  "content_type": "EVENT",
  "source_text": "女主走到桌边，把通知书放到父亲面前。",
  "covered_by": ["BEAT-E01-S01-001"],
  "coverage": "FULL",
  "note": null
}
```

对白覆盖项的 `source_text` 必须与 BEAT 中的 `dialogue.text` 逐字一致。不要规范化标点、错别字或称呼。

允许的覆盖状态：

- `FULL`：完整进入 BEAT。
- `PARTIAL`：只覆盖一部分，产物不能进入 QA 正常放行。
- `OMITTED`：遗漏，产物不能进入 QA 正常放行。

`coverage_summary` 使用：

```json
{
  "total_story_events": 1,
  "covered_story_events": 1,
  "total_dialogue_lines": 1,
  "preserved_dialogue_lines": 1
}
```

计数必须与 `source_coverage` 中的 `content_type` 和 `coverage` 一致。

冲突或资料缺失阻断的原文仍然必须进入 `source_coverage`。使用：

```json
{
  "coverage_id": "COV-E01-0003",
  "source_range": "SCRIPT-E01-V1:L22",
  "content_type": "DIALOGUE",
  "source_text": "我不会签。",
  "covered_by": [],
  "coverage": "OMITTED",
  "note": "由 CONFLICT-E01-001 阻断，等待导演裁决"
}
```

只有顶层状态为 `HUMAN_GATE` 且覆盖状态不是 `FULL` 时，`covered_by` 才允许为空。该项仍计入 `total_story_events` 或 `total_dialogue_lines`，但不计入已覆盖或已保留数量。

## 场次字段

```json
{
  "scene_id": "SCENE-E01-S01",
  "scene_number": 1,
  "source_ranges": ["SCRIPT-E01-V1:L1-L30"],
  "heading": {
    "time": "日",
    "interior_exterior": "内",
    "location": "父亲家餐厅"
  },
  "characters_present": ["女主", "父亲"],
  "scene_start_state": {},
  "beats": [],
  "scene_end_state": {}
}
```

要求：

- 按原剧情顺序排列场次。
- 使用正整数 `scene_number`。
- 为非标准剧本保留所有参与划分判断的来源范围。
- 只列真实在场或被剧本明确置于画外的角色；画外状态写入对应状态对象。

## BEAT 字段

```json
{
  "beat_id": "BEAT-E01-S01-001",
  "source_ranges": ["SCRIPT-E01-V1:L18-L24"],
  "source_status": "CONFIRMED",
  "start_state": {},
  "trigger": {},
  "actions": [],
  "reactions": [],
  "dialogue": [],
  "emotion_change": [],
  "end_state": {},
  "continuity": {},
  "decision_overrides": [],
  "notes": []
}
```

字段要求：

| 字段 | 要求 |
|---|---|
| `beat_id` | 场次内连续，推荐 `BEAT-E01-S01-001` |
| `source_ranges` | 至少一项，不得伪造 |
| `source_status` | `CONFIRMED` 或 `DERIVED` |
| `start_state` | BEAT 开始时必要人物、道具、环境和信息状态 |
| `trigger` | 推动该 BEAT 的事件及来源 |
| `actions` | 按发生顺序排列的可见行动 |
| `reactions` | 其他人物或环境的即时反应 |
| `dialogue` | 原始台词，不得改写 |
| `emotion_change` | 必须带证据；没有变化时使用空数组 |
| `end_state` | 行动和反应完成后形成的新状态 |
| `continuity` | 下个 BEAT 必须继承及仍未完成的动作 |
| `decision_overrides` | 影响本 BEAT 的确认决定 ID |
| `notes` | 只写来源或结构说明，不写镜头建议 |

`trigger` 使用：

```json
{
  "event": "女主决定公布录取结果",
  "source_range": "SCRIPT-E01-V1:L18"
}
```

`actions` 使用：

```json
{
  "order": 1,
  "actor": "女主",
  "action": "走近餐桌，将通知书放到父亲面前",
  "target": "父亲",
  "source_range": "SCRIPT-E01-V1:L18-L20"
}
```

`reactions` 使用：

```json
{
  "order": 2,
  "actor": "父亲",
  "reaction": "低头看向通知书",
  "source_range": "SCRIPT-E01-V1:L21"
}
```

`dialogue` 使用：

```json
{
  "order": 3,
  "speaker": "女主",
  "text": "爸，我考上了。",
  "timing": "通知书放稳后",
  "source_range": "SCRIPT-E01-V1:L22"
}
```

同一 BEAT 的 `order` 在行动、反应和对白之间共同排序，不得重复。

`emotion_change` 使用：

```json
{
  "character": "父亲",
  "from": "日常平静",
  "to": "明显惊讶",
  "evidence": ["SCRIPT-E01-V1:L21-L24"]
}
```

## 状态对象

统一使用以下四个维度；没有相关事实时使用空对象，不删除字段：

```json
{
  "characters": {},
  "props": {},
  "environment": {},
  "knowledge": {}
}
```

只保留影响当前或后续剧情理解的状态。不要堆积不影响剧情的视觉细节。

`continuity` 使用：

```json
{
  "must_carry_forward": [
    "通知书位于父亲面前"
  ],
  "open_actions": [
    "父亲准备伸手拿起通知书"
  ]
}
```

## 冲突与未知项

冲突使用：

```json
{
  "conflict_id": "CONFLICT-E01-001",
  "source_refs": ["SCRIPT-E01-V1:L20", "DEC-017"],
  "summary": "原剧本和确认状态不明的讨论稿给出互斥结果",
  "affected_scope": ["SCENE-E01-S01"],
  "status": "UNRESOLVED",
  "question": "这一场以原剧本结果还是讨论稿结果为准？"
}
```

未知项使用：

```json
{
  "unknown_id": "UNKNOWN-E01-001",
  "description": "剧本缺页，无法确认父亲是否已经看到通知书",
  "affected_scope": ["BEAT-E01-S01-001"],
  "blocking": true,
  "source_refs": ["SCRIPT-E01-V1:L18-L24"]
}
```

存在未解决冲突或 `blocking: true` 的未知项时，将顶层状态设为 `HUMAN_GATE`。

## 不变量

- 保持 `full_id == artifact_id + "-" + artifact_version`。
- 保持 `source_artifact_id` 和 `source_version` 指向主要剧本。
- 保持 `source_full_id == source_artifact_id + "-" + source_version`。
- 保持场次、BEAT 和所有 `order` 唯一且顺序稳定。
- 保持每个 BEAT 至少含一个行动、反应或对白。
- 保持每个 BEAT 同时具有 `start_state`、`trigger` 和 `end_state`。
- 保持每句对白有来源覆盖项，且文本逐字一致。
- 保持所有正式剧情事件覆盖为 `FULL`。
- 保持被冲突或未知项阻断的内容仍有覆盖记录，不通过漏记降低分母。
- 保持情绪变化具有来源证据。
- 保持未解决冲突与 `HUMAN_GATE` 状态一致。
- 保持 S02 产物不含 `shot_id` 或镜头设计字段。

## 完整最小示例

```json
{
  "schema_version": "1.0",
  "project_id": "PROJECT-001",
  "artifact_id": "PLOT-E01",
  "artifact_version": "V1",
  "full_id": "PLOT-E01-V1",
  "source_artifact_id": "SCRIPT-E01",
  "source_version": "V1",
  "source_full_id": "SCRIPT-E01-V1",
  "source_artifacts": [
    {
      "source_id": "SCRIPT-E01",
      "source_type": "SCRIPT",
      "version": "V1",
      "scope": "E01",
      "locator_type": "LINE",
      "path": "episode-01.txt"
    }
  ],
  "status": "DRAFT",
  "scope": {
    "episode_id": "E01",
    "scene_ids": ["SCENE-E01-S01"]
  },
  "coverage_summary": {
    "total_story_events": 1,
    "covered_story_events": 1,
    "total_dialogue_lines": 1,
    "preserved_dialogue_lines": 1
  },
  "source_coverage": [
    {
      "coverage_id": "COV-E01-0001",
      "source_range": "SCRIPT-E01-V1:L18-L21",
      "content_type": "EVENT",
      "source_text": "女主走到桌边，把通知书放到父亲面前。父亲低头看向通知书。",
      "covered_by": ["BEAT-E01-S01-001"],
      "coverage": "FULL",
      "note": null
    },
    {
      "coverage_id": "COV-E01-0002",
      "source_range": "SCRIPT-E01-V1:L22",
      "content_type": "DIALOGUE",
      "source_text": "爸，我考上了。",
      "covered_by": ["BEAT-E01-S01-001"],
      "coverage": "FULL",
      "note": null
    }
  ],
  "decision_overrides": [],
  "conflicts": [],
  "unknowns": [],
  "scenes": [
    {
      "scene_id": "SCENE-E01-S01",
      "scene_number": 1,
      "source_ranges": ["SCRIPT-E01-V1:L1-L30"],
      "heading": {
        "time": "日",
        "interior_exterior": "内",
        "location": "父亲家餐厅"
      },
      "characters_present": ["女主", "父亲"],
      "scene_start_state": {
        "characters": {
          "女主": "站在门口，右手拿着录取通知书",
          "父亲": "坐在餐桌右侧，尚未注意到通知书"
        },
        "props": {
          "录取通知书": "由女主右手持有"
        },
        "environment": {},
        "knowledge": {
          "父亲": "尚不知道录取结果"
        }
      },
      "beats": [
        {
          "beat_id": "BEAT-E01-S01-001",
          "source_ranges": ["SCRIPT-E01-V1:L18-L24"],
          "source_status": "CONFIRMED",
          "start_state": {
            "characters": {
              "女主": "站在门口，右手拿着录取通知书",
              "父亲": "坐在餐桌右侧，尚未注意到通知书"
            },
            "props": {
              "录取通知书": "由女主右手持有"
            },
            "environment": {},
            "knowledge": {
              "父亲": "尚不知道录取结果"
            }
          },
          "trigger": {
            "event": "女主决定公布录取结果",
            "source_range": "SCRIPT-E01-V1:L18"
          },
          "actions": [
            {
              "order": 1,
              "actor": "女主",
              "action": "走近餐桌，将通知书放到父亲面前",
              "target": "父亲",
              "source_range": "SCRIPT-E01-V1:L18-L20"
            }
          ],
          "reactions": [
            {
              "order": 2,
              "actor": "父亲",
              "reaction": "低头看向通知书",
              "source_range": "SCRIPT-E01-V1:L21"
            }
          ],
          "dialogue": [
            {
              "order": 3,
              "speaker": "女主",
              "text": "爸，我考上了。",
              "timing": "通知书放稳后",
              "source_range": "SCRIPT-E01-V1:L22"
            }
          ],
          "emotion_change": [
            {
              "character": "父亲",
              "from": "日常平静",
              "to": "明显惊讶",
              "evidence": ["SCRIPT-E01-V1:L21-L24"]
            }
          ],
          "end_state": {
            "characters": {
              "女主": "站在餐桌旁等待父亲反应",
              "父亲": "低头看见通知书后抬头看向女主"
            },
            "props": {
              "录取通知书": "平放在父亲面前"
            },
            "environment": {},
            "knowledge": {
              "父亲": "已经知道女主被录取"
            }
          },
          "continuity": {
            "must_carry_forward": ["通知书位于父亲面前"],
            "open_actions": ["父亲准备伸手拿起通知书"]
          },
          "decision_overrides": [],
          "notes": []
        }
      ],
      "scene_end_state": {
        "characters": {
          "女主": "站在餐桌旁",
          "父亲": "看向女主"
        },
        "props": {
          "录取通知书": "平放在父亲面前"
        },
        "environment": {},
        "knowledge": {
          "父亲": "已经知道女主被录取"
        }
      }
    }
  ],
  "impact_scope": {
    "changed_beats": [],
    "stale_downstream": []
  }
}
```
