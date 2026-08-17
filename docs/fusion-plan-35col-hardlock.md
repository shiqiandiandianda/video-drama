# 融合方案 V2：硬锁规则 × 现有流水线

日期：2026-08-17（V2，替代 V1）
原则：表格保持简练；同一件事实只在一个 skill 里管；能渲染就不新建阶段。

## 1. 取舍

| 新 skill 内容 | 处置 | 理由 |
|---|---|---|
| 35 列母表 | **弃** | 臃肿，大量"理由列"是废话；一致性价值只在少数几列 |
| 风格锁（3D国漫/真人写实 + 互斥负面词） | **收** | 一句话锁死全项目画风，价值高 |
| 场景子类 + 空间锚点 | **收** | 防"院内画成室内"的唯一硬手段 |
| 人物左右/高低站位锁、防越轴 | **收** | 现有集群只有原则，没有可检查字段 |
| 整页 2列5行 三模式分镜图 | **收，但只做渲染器** | 导演审片确实好用；内容是 S04 已有产物的重排，不许另起生产阶段 |
| 验图一票否决清单、S/A/B 分级 | **收进 S06** | 并入现有 QA，不新增 skill |
| "保留内容/必须修正"返修写法 | **收进 RepairTicket** | 等于已有 locked_fields/change_set，补措辞库即可 |
| 视频六步公式整段格式、{{Mixed x}} 素材调用 | **收，只做导出渲染器** | S05 单镜 spec 是权威内容，整段 Prompt 是格式 |
| 防泄漏条款、知识库复读、报告式输出 | **弃** | 与本仓库可评审、可测试的要求冲突 |

## 2. 改动清单（每处都写到具体文件）

### ProjectManifest
- 加必填 `visual_style_lock: GUOMAN_3D_CG | LIVE_ACTION_REALISM`，配套正/负词包放 `_shared/style-packs.md`，全集群唯一出处，其他文件只引用不复制。旧项目续跑时缺锁 → HUMAN_GATE 补锁。

### S02 script-plot-progression
- `scene_facts` 升级为 `scene_main / scene_sub / spatial_anchors[]`（锚点 ≥2），禁写大类裸词。
- 补一条：现实/闪回属不同场景子类，转场只占相邻 1–2 个 BEAT。

### S03 storyboard-table-director
- **九列公开表一字不动**。
- `shot_map[]` 机器侧只加三个字段：`scene_sub`、`spatial_anchors[]`、`screen_lock`（谁在左/右/高/低，正反打同向）。
- 校验器加三条机械检查：每 10 镜 ≤15s、时间段连续、`scene_sub` 非空且锚点 ≥2。

### S04 storyboard-image-prompt-director
- 单镜 Prompt 模板加两条硬规则：风格锁词包必须镜像；参考图用"图1是__、图2是__"固定编号，禁止"未绑定"写法，用户已给编号原样继承。
- 新增**页渲染器** `scripts/render_page_prompt.ps1`：输入同页已 PASS 的 10 个 shot 行，输出三模式整页 Prompt（COLOR / LINEART_REVIEW / LINEART_CLEAN）。版式（2列5行、格16:9、页32:45、左上编号）和三模式的文字/标签/箭头策略写成枚举配置，渲染器机械拼装，不产新内容。
- LINEART_REVIEW 页接入 P5 人工确认，作为站位/调度审阅图。

### S06 short-drama-unified-qa
- `qa-storyboard-image.md` 增加：S/A/B 严重度定义、一票否决清单（对白气泡/说明栏/线稿彩色主体/灰阶写实化/左右反转/越轴/锚点消失/同页场景乱切/箭头缺失或全同向/标签错漏遮脸/人物变脸——命中即不通过，禁写"基本可用"）、"可进视频阶段"六条件。
- S 级 >3 或版式错 → 整页重做；1–2 格错 → 局部返修。

### 返修（RepairTicket，_shared/pipeline-contract.md）
- 票据加 `preserve_scope`（保留内容，并入 locked_fields 语义）与 `must_fix`（必须修正，必须落到具体镜/格号，禁止"修好感觉"式写法）。
- 返修类型枚举：`FULL_REDO | LOCAL_REPAIR | REINFORCE_CONSTRAINT`。
- 专项返修短语库（院内↔室内互错、左右恢复、标签遮脸、箭头全向右、红印≠流血、孕肚归属、界碑锚点）放 `_shared/repair-phrases.md`，唯一出处。

### S05 video-prompt-director
- 权威产物不变。新增**段导出器** `scripts/render_segment_prompt.ps1`：把同页已 PASS 的若干 spec 渲染成整段格式——"这个视频生成__秒…"开头 + {{Mixed x}} 素材调用 + 分镜图只参考构图/站位/左右/动作/运镜/节奏 + 主体→动作→环境→镜头→风格→约束自然段 + 声音设计 + 画面限制。
- 输入含非 PASS 或 STALE → 拒绝导出。导出免新 QA 门禁（无新内容）。

## 3. 去重硬规则

1. 同一规则只存在于一个文件：风格词包在 `_shared/style-packs.md`，返修短语在 `_shared/repair-phrases.md`，否决清单在 S06，版式枚举在 S04 渲染器。其余文件一律引用。
2. 页 Prompt、段 Prompt 都是渲染产物，不落版本、不进 QA，权威内容永远在 S03/S04/S05 的正式产物里。
3. 任何"新 skill 有、集群已有"的功能，以集群为准，只补缺失规则，不并行两套。

## 4. 顺序与验收

顺序：`_shared` 词包 → S02/S03 字段与校验 → S06 否决清单 → S04 页渲染器 → S05 段导出器 → 返修票据 → 端到端回归。

验收：同一份剧本连跑 3 次——
- 九列表照旧简练；机器侧三字段齐全，校验器全过；
- 整页三模式 Prompt 版式、标签箭头策略机械一致；
- 验图命中否决项时裁决必为不通过；
- 返修 Prompt 必含保留内容 + 具体修正项；
- 段导出格式正确、槽位连续自增；含 STALE 输入必被拒。
