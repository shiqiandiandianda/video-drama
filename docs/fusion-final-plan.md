# Skill 集群改造执行基准（最终版）

> 合并 `rework-v2-plan.md` 与 `fusion-plan-35col-hardlock.md`，并经四轮对齐裁决。
> 本文档是唯一执行基准；两份旧方案自此作废。
> 愿景：AI 短剧符合视听语言逻辑、短剧节奏与短剧运镜，成片看不出是 AI 制作，如同真人实拍。

---

## 1. 五条铁律

1. **图纸入库，禁止填空**：`reference-final-prompt-参考素材说明.txt` 收编为 `_shared/segment-format.md`（唯一格式出处），派生三物——结构 schema（进 S05 契约）、渲染模板（进渲染脚本）、检查清单（进 S06）。任何生产 skill 的输入里永远不放参考文档原文，LLM 见不到"可填的空"。
2. **缺字段 = 阻断，禁止编造**：十五节全部字段纳入 `unresolved_fields` 阻断规则；body 中任何事实无法指回结构化字段 = 不合格。
3. **一个萝卜一个坑**：十五节每一节有且仅有一个事实主源（见 §2 归属表）；同一规则只存在于一个文件，他处只引用。
4. **文本全渲染**：LLM 只产结构化字段，所有面向模型的文本（九列表、图 Prompt、十五节 body）都是脚本渲染产物，正确性由构造保证，校验器只做 sanity。
5. **提要求 / 做东西 / 质检三段分工**：S01 签发要求，生产 skill 产事实，S06 只检已有之物；没有签发要求或权威依据支撑的检查项不得开阻断单。

## 2. 十五节 × 事实主源归属表

| 节 | 唯一事实主源 | 性质 |
|---|---|---|
| 一、参考素材说明 | 项目资产台账 + S05 槽位编号 | 机械渲染 |
| 二、素材使用规则 | `_shared/segment-format.md` 静态规则包 | 静态 + 槽位替换 |
| 三、视觉与摄影基准 | `Manifest.visual_style_lock` + 机型规则包 + S02 `scene_tone` | 机械渲染 |
| 四、场景空间锚点 | S02 `spatial_anchors`（含摄影机锚点）+ S03 `screen_lock` | 机械渲染 |
| 五、承接上一段 | 上段 S05 `final_state`；首段 = S02 首 BEAT `start_state`；跨集 = EpisodeHandoff | 机械继承 |
| 六、镜头时间轴 | S03 `shot_map` + `_shared` 景别→焦段光圈映射表；起止时间 = 秒数累加 | 机械渲染 |
| 七、时间轴对白 | 台词 = 原剧本逐字（经 S02）；演绎参数 = S03 `dialogue_delivery` | 引用 + 上游生产 |
| 八、镜尾状态 | S03 `shot_map[].end_state`（补丁 1） | 机械渲染 |
| 九、重复结构说明 | 无事实 | 纯静态 |
| 十、全段光线与色彩 | S02 场景光线基调 + S05 段级统一决策（结构化字段） | 上游生产 + S05 有限决策 |
| 十一、全段摄影规格 | `_shared` 映射表 + S03 景别 | 机械渲染 |
| 十二、声音设计 | S02 场景环境 + S03 画面描述 | 机械渲染 |
| 十三、全段连续性约束 | `_shared` 静态规则 + S03 段内锁 | 机械渲染 |
| 十四、负面约束 | `_shared/style-packs.md` 负面词 | 机械渲染 |
| 十五、最终承接状态 | S05 `final_state`（段级生产，QA 检） | S05 生产 |

**LLM 生产坑只有三个**：S02 产剧情、S03 产镜头设计、S05 产段级决策（分组/光线统一/最终状态）。

## 3. 关键裁决记录

1. **段是权威产物**：`VideoPromptSpec` 升级为段级（`segment_id` + `covered_shot_ids[]`），落版本、进 QA；十五节 body 是渲染产物。原 fusion 方案"段只做导出器、免 QA"否决。
2. **段内镜头数**：2–6 镜，单镜 ≥1.5s，段内各镜时长之和 = 段时长（15s / 30s）。
3. **页 ≠ 段**：页（2列5行=10格）是图轨审片排版单位；段（15/30s）是视频生成单位。段按连续 `shot_ids` + 时长上限分组，页按排版数量分组。
4. **页渲染器输入** = 同页 10 个已 PASS 的 StoryboardPromptSpec（S04 产物重排），不是 S03 行。
5. **三个补丁**：① S03 `shot_map` 加 per-shot `end_state`（1:1 默认继承 BEAT `end_state`，拆分时显式给出）；② 道具画面位置推导规则（道具归属 × 持有人 `screen_lock` 位置 → 节6 道具行，无持有人读 BEAT `props` 位置）写进 S05 渲染规则；③ 摄影机锚点并入 S02 `spatial_anchors`。
6. **旧产物**：`schema_version` 升 "2.0"；旧 1.0 单镜 VideoPromptSpec 标记 STALE 按段重产。旧项目缺风格锁 → HUMAN_GATE 补锁。

## 4. 改造内容总表

### Phase 0 · `_shared` 地基
- 新增 `segment-format.md`（图纸：十五节字段 schema + 渲染模板 + 静态规则包 + 景别→焦段光圈映射表）
- 新增 `style-packs.md`（`GUOMAN_3D_CG` / `LIVE_ACTION_REALISM` 正/负词包，唯一出处）
- 新增 `repair-phrases.md`（专项返修短语库，唯一出处）
- `pipeline-contract.md`：双轨、`SEG-E##-###` / `HANDOFF-E##` 规范 ID、RepairTicket 加 `preserve_scope`/`must_fix`/`repair_type`、失效矩阵加段级与跨集行

### Phase 1 · S02 剧情
- `scene_facts` 升级：`scene_main` / `scene_sub` / `spatial_anchors[]`（≥2，含摄影机锚点）/ `scene_tone`（本场风格/色彩/节奏）/ `light_base`（主光方向/色温）
- 闪回规则：现实/闪回属不同场景子类，转场只占相邻 1–2 个 BEAT
- 跨集：首 BEAT `start_state` 必须可追溯到上集 EpisodeHandoff 或显式标记时间跳跃；锚点须与 Handoff 禁止重置项一致
- `source_type` 加 `EPISODE_HANDOFF`

### Phase 2 · S03 镜头设计（视听语言主战场）
- `shot_map[]` 加：`scene_sub`、`spatial_anchors[]`、`screen_lock`（谁在左/右/高/低，正反打同向）、`end_state`（镜尾状态）、`dialogue_delivery`（停顿/重音/主手势/留白）、`segment_hint`
- 运镜动机硬规则：摄影机运动只在人物动作、视线变化、信息揭示或情绪爆点触发；快速运镜结束立即恢复稳定
- 短剧节奏规则：开场 hook 时限、反转密度、单镜信息容量、窗口自检（连续 3 镜不重复信息、不无理由越轴、不重置状态）
- 校验器机械检查：单镜 ≥1.5s、时间段连续、`scene_sub` 非空且锚点 ≥2、`screen_lock` 与 `end_state` 齐备

### Phase 3 · 双轨化
- `ProjectManifest.constraints.storyboard_image_track: REQUIRED | OPTIONAL | DISABLED`（默认 OPTIONAL）
- VISUAL_TRACK = 现状链路；DIRECT_TRACK = S03 行 PASS 直进 S05，`start_state.source_status` 加 `LOCKED_UPSTREAM_PLUS_PREVIOUS_END_STATE`
- S01 P6 门禁双轨化；`validate_qa_request.ps1` 放行无图轨

### Phase 4 · S05 段组装 + 机械渲染
- 契约重构：`segment_id` + `covered_shot_ids[]` + 段级字段（`timeline[]` / `segment_light_color` / `sound_design` / `final_state`）+ `continuity_checks` 加 `window/window_checks`
- 新增 `render_segment_prompt.ps1`：唯一 body 生成途径，输入非 PASS/STALE 拒绝渲染
- `validate_body.ps1` 降级为 sanity（字数/槽位连续/禁词/污染词）
- `validate_prompt_sequence.ps1` 改段序列：段间承接签名 + 窗口 ±2 弱规则
- 跨集首段 `PREVIOUS_END_STATE` 允许来自 EpisodeHandoff

### Phase 5 · S06 质检
- `qa-video-prompt.md` 重写：段结构、段内时间轴、窗口流畅度、跨集承接、十五节 conformance、对白时间轴位置、body 事实可指回字段
- `qa-storyboard-table.md`：窗口流畅度（3 镜窗口）与节奏/视听语言规则族
- `qa-storyboard-image.md`：S/A/B 严重度 + 一票否决清单（仅 VISUAL_TRACK）
- RepairTicket 加段级选择器 `target_segment_ids`；失效传播表加段级与跨集行
- 裁决不变量：无签发要求或权威依据支撑的检查项不得作为阻断问题

### Phase 6 · S01 要求签发
- dispatch 加 `requirements`（`quality_bar` / `project_constraints` / `focus`）
- 生产 skill 产物根级镜像 `requirements_ref`
- `artifact_type` 加 `EPISODE_HANDOFF`；非首集 P1 需上集 HANDOFF
- 跨集：P7 交付追加产出 EpisodeHandoff；Handoff 变化 → 下集 PLOT 及下游 STALE

### Phase 7 · S04 图轨（仅 VISUAL_TRACK）
- 单镜 Prompt 模板：风格锁词包必须镜像；参考图固定编号"图1是__、图2是__"，禁止"未绑定"
- 新增 `render_page_prompt.ps1`：三模式整页渲染（COLOR / LINEART_REVIEW / LINEART_CLEAN），版式枚举配置，机械拼装；LINEART_REVIEW 接 P5 人工确认

## 5. 实施与验收

顺序：Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7，每步跑回归保持绿色。

验收：同一份剧本连跑 3 次——
- 九列表照旧简练；`shot_map` 新字段齐全，校验器全过；
- 十五节 body 与结构化字段零冲突；含 STALE 输入必被拒；
- 缺字段必阻断，无编造；
- 段间承接签名一致；窗口 distance=2 矛盾被拒；
- 跨集缺 HANDOFF 时 P1 阻断。
