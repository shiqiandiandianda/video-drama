# 合成示例与反例

> 本文件仅示范结构和裁决方法，不是任何真实项目的剧情事实，也不能替代真实剧本回归样本。

## 目录

- [示例一：动作与对白形成一个 BEAT](#示例一动作与对白形成一个-beat)
- [示例二：必须拆成两个 BEAT](#示例二必须拆成两个-beat)
- [示例三：导演决定覆盖剧本](#示例三导演决定覆盖剧本)
- [示例四：来源冲突进入 HUMAN_GATE](#示例四来源冲突进入-human_gate)
- [示例五：局部返修](#示例五局部返修)
- [常见失败](#常见失败)

## 示例一：动作与对白形成一个 BEAT

原文：

```text
18 女主走到餐桌边，把通知书放到父亲面前。
19 女主：爸，我考上了。
20 父亲低头看清内容，抬头看她。
```

判断：三个句子共同完成“父亲得知录取结果”这一个状态变化，可以保持一个 BEAT。

```json
{
  "beat_id": "BEAT-E01-S01-001",
  "source_ranges": ["SCRIPT-E01-V1:L18-L20"],
  "source_status": "CONFIRMED",
  "start_state": {
    "characters": {
      "女主": "站在餐桌附近",
      "父亲": "尚未看到通知书"
    },
    "props": {
      "通知书": "由女主持有"
    },
    "environment": {},
    "knowledge": {
      "父亲": "不知道录取结果"
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
      "action": "把通知书放到父亲面前",
      "target": "父亲",
      "source_range": "SCRIPT-E01-V1:L18"
    }
  ],
  "reactions": [
    {
      "order": 3,
      "actor": "父亲",
      "reaction": "低头看清内容，抬头看女主",
      "source_range": "SCRIPT-E01-V1:L20"
    }
  ],
  "dialogue": [
    {
      "order": 2,
      "speaker": "女主",
      "text": "爸，我考上了。",
      "timing": "通知书放到父亲面前后",
      "source_range": "SCRIPT-E01-V1:L19"
    }
  ],
  "emotion_change": [],
  "end_state": {
    "characters": {
      "女主": "等待父亲反应",
      "父亲": "看过通知书后抬头看女主"
    },
    "props": {
      "通知书": "位于父亲面前"
    },
    "environment": {},
    "knowledge": {
      "父亲": "知道女主已被录取"
    }
  },
  "continuity": {
    "must_carry_forward": ["父亲已经知道录取结果", "通知书位于父亲面前"],
    "open_actions": []
  },
  "decision_overrides": [],
  "notes": []
}
```

不要添加“父亲惊喜落泪”，因为原文没有这一反应。

## 示例二：必须拆成两个 BEAT

原文：

```text
30 父亲看完通知书，沉默地把它推回去。
31 女主愣住，收起通知书，转身离开。
32 门刚打开，母亲提着行李站在门外。
```

划分：

1. `BEAT-...-002`：父亲推回通知书，女主收起并决定离开；结果是关系受挫、女主持有通知书并打开门。
2. `BEAT-...-003`：门打开后母亲出现；结果是人物组合和当前局势变化。

不要把“父亲拒绝→女主离开→母亲出现”全部塞进一个 BEAT。母亲出现拥有独立触发和结果。

## 示例三：导演决定覆盖剧本

原剧本：

```text
父亲看了一眼通知书，把它推回去。
```

已确认决定：

```text
DEC-017，CONFIRMED：父亲拿起通知书完整看完，不再把它推回去。
```

处理：

- 使用确认结果生成行动和结束状态。
- 保留原剧本范围。
- 记录 `decision_overrides`。
- 只改变“查看和推回”相关内容，不自行增加拥抱、道歉或新台词。

```json
{
  "decision_id": "DEC-017",
  "overrides_source": "SCRIPT-E01-V1:L30",
  "original_value": "父亲看了一眼通知书，把它推回去",
  "confirmed_value": "父亲拿起通知书完整看完，不再把它推回去",
  "affected_beats": ["BEAT-E01-S01-002"],
  "status": "CONFIRMED"
}
```

## 示例四：来源冲突进入 HUMAN_GATE

输入：

- 原剧本：父亲把通知书推回去。
- 讨论纪要：父亲拿起通知书查看。
- 讨论纪要只标记“导演想法”，没有确认结论。

处理：

- 继续以原剧本作为正式基线。
- 将讨论纪要标为 `TENTATIVE`，不覆盖。
- 如果调用方声称两者都已锁定，却无法提供更新裁决，则建立冲突并进入 `HUMAN_GATE`。
- 把受阻断的原剧情事件和对白登记为 `OMITTED`，`covered_by` 使用空数组，并计入覆盖总数。

最小问题：

```text
第 1 场最终以“父亲推回通知书”还是“父亲拿起通知书查看”为准？目前两个来源均被标记为锁定，未找到后续裁决。
```

不要根据“拿起来更有戏”自行选择。

## 示例五：局部返修

QA 返回：

```json
{
  "issue_type": "DIALOGUE_CHANGED",
  "evidence": "原文为‘爸，我考上了。’，产物写成‘爸爸，我终于考上了。’",
  "affected_scope": ["BEAT-E01-S01-001"],
  "allowed_paths": [
    "/scenes/0/beats/0/dialogue/0/text",
    "/source_coverage/1/source_text"
  ],
  "locked_fields": [
    "/scenes/0/beats/0/actions",
    "/scenes/0/beats/0/reactions",
    "/scenes/0/beats/0/end_state"
  ]
}
```

只把两处文本恢复为原文并递增版本。不要重写行动、反应、情绪或 BEAT 边界。

## 常见失败

### 失败：补写隐藏动机

```text
父亲故意冷落女主，想逼她成长。
```

原文只写父亲沉默时，该动机没有来源，必须删除。

### 失败：把 BEAT 当镜头

```text
BEAT 1：通知书特写。
BEAT 2：父亲眼睛特写。
```

这是镜头设计，不是剧情状态变化。合并回“父亲看到通知书并获得录取信息”的剧情 BEAT。

### 失败：用摘要改写台词

```text
女主告诉父亲自己考上了。
```

可以作为事件摘要，但不能替代 `dialogue.text` 中的原句“爸，我考上了。”。

### 失败：提前泄露

后文才揭示母亲在门外时，不要在前一 BEAT 的起始状态写“母亲正在门外等待”，除非原文已经向观众明确这一事实。

### 失败：把未知写成确定

原文没有说明通知书由哪只手持有时，不要写“右手持有”。保持“由女主持有”，或在确有影响时记录未知。
