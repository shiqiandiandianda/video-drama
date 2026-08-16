# 示例与实测案例索引

## 目录

1. 示例性质
2. 合同级合成示例
3. 输入门禁失败
4. 时长超载路由
5. 局部返修示例
6. 当前图片资料
7. 实测案例索引
8. 案例使用规则

## 1. 示例性质

本文件中的结构化示例用于验证契约和路由，不是已生成视频的金标准。当前资料库没有状态为“已验证通过”的 S05 Prompt＋视频＋QA 成对样本，因此不得把合成示例标为生产验收 PASS。

## 2. 合同级合成示例

假设上游已经明确：一条 6 秒固定中景，女主把通知书推到父亲面前并说一句短台词；分镜图已人工批准，右手和双人位置已锁定。

```yaml
project_id: PRJ-DEMO
scene_id: SCENE-E01-S01
shot_id: SHOT-E01-S01-003
artifact_id: VP-E01-S01-003
artifact_version: V1
full_id: VP-E01-S01-003-V1
video_prompt_id: VP-E01-S01-003-V1
status: DRAFT
task:
  task_mode: CREATE
  generation_task: MULTIMODAL_REFERENCE
  model: seedance-2.0
  model_rule_profile: SD20-V3.4
  product_flow: <调用方已验证模式>
  output_scope: SINGLE_SHOT
  delivery_mode: PROMPT_ONLY
  aspect_ratio: "9:16"
  target_duration_seconds: 6
approved_image_full_id: IMG-E01-S01-003-V2
source_artifacts:
  - role: APPROVED_STORYBOARD
    full_id: IMG-E01-S01-003-V2
    status: APPROVED
    stale: false
    scope: SHOT-E01-S01-003
  - role: PLOT_PROGRESSION
    full_id: PLOT-E01-V1
    status: PASS
    stale: false
    scope: BEAT-E01-S01-002
  - role: STORYBOARD_TABLE
    full_id: STORYBOARD-E01-S01-V2
    status: PASS
    stale: false
    scope: SHOT-E01-S01-003
  - role: MODEL_RULES
    full_id: SD20-RULES-V3.4
    status: PASS
    validation_status: VERIFIED
    stale: false
    scope: seedance-2.0
start_state:
  spatial_world:
    - 女主站在茶几西侧，父亲坐在茶几东侧
  screen_projection:
    - 女主画面左侧中景，父亲画面右侧中景，通知书在两人之间前景
  characters:
    - name: 女主
      action_stage: PREPARATION
      hand_and_contact: 右手压住通知书右上角
      provenance: APPROVED_IMAGE_VISIBLE
    - name: 父亲
      action_stage: REACTION_PREPARATION
      gaze_target: 女主右手与通知书
      provenance: APPROVED_IMAGE_VISIBLE
  props:
    - name: 通知书
      owner: 女主
      holder_or_contact: 女主右手
      state: 完整、平放、未被父亲拿起
action_flow:
  core_emotion: 克制期待
  intended_result: 父亲注意力被通知书击中，但尚未拿起
  timeline:
    - start_seconds: 0
      end_seconds: 2
      primary_event: 女主把通知书沿桌面向父亲推近
      action_physics: 右手先压实纸面再平稳前送，重心轻微前移，纸张停在父亲正前方
      performance: 女主看一眼父亲再落回通知书；父亲闭嘴，视线跟随纸面
      camera_execution: 固定中景，不新增运动
      light_sound_change: 纸张摩擦桌面的轻声清楚
    - start_seconds: 2
      end_seconds: 6
      primary_event: 女主停手说出原台词，父亲听懂后呼吸停半拍
      action_physics: 女主指腹尚未完全离开封面，姿势保持稳定
      performance: 女主短吸气后开口；父亲不张嘴，下巴微收并抬眼看她
      camera_execution: 固定中景停在双人和通知书关系上
      light_sound_change: 环境声压低，台词结束后留半拍静场
dialogue_audio:
  - speaker: 女主
    exact_text: "爸，这是我的录取通知书。"
    source_ref: SCRIPT-E01-V1:<示例范围>
    start_seconds: 2.4
    end_seconds: 5.2
    voice: 成年年轻女性，克制清楚，音量正常，语速自然，开口前短吸气
    listener_reactions:
      - 父亲闭嘴，先看通知书再抬眼看女主
camera:
  shot_size: 中景
  viewpoint: 正面平视
  confirmed_movement: FIXED
  optics_source: DERIVED_EXECUTION
  focal_length_mm: 50
  aperture_f: 4
  camera_distance_m: 2.4
  focus_target: 双方面部与通知书构成的可辨平面
  follow_focus: NONE
  visible_depth_of_field: 双人、右手和通知书清楚，背景家具轻柔化但结构可辨
end_state:
  state_kind: PLANNED
  recommended_stable_frame_seconds: 5.8
  next_shot_must_inherit:
    - 通知书平放在父亲正前方
    - 女主右手指腹尚未完全离开封面
    - 父亲尚未拿起通知书
body_sections:
  reference_materials: "参考图素材说明：女主{{Mixed 1}}，父亲{{Mixed 2}}，客厅{{Mixed 3}}，确认分镜图{{Mixed 7}}。"
  approved_start_and_spatial_state: "参考确认分镜图{{Mixed 7}}中已批准的双人中景构图……"
  continuous_timeline: "0-2秒：……\n2-6秒：……"
  imaging: "50mm、f/4，摄影机距双人约2.4米……"
  sound_continuity_stability: "保留纸面摩擦、呼吸和室内环境声，不生成BGM……"
body: <五个分区按固定顺序拼接后的完整正文>
body_char_count: <按契约计算>
```

此示例只证明“一镜、来源、时间轴、右手、对白、光学和计划镜尾”的结构能对齐；没有真实上游文件和生成结果时不能作为 PASS 样本。

## 3. 输入门禁失败

输入：图片只有 `status: PASS`，没有人工 `APPROVED` 记录。

正确路由：

```yaml
status: HUMAN_GATE
shot_id: SHOT-E01-S01-003
blocked_fields:
  - approved_storyboard.status
evidence: 当前图片 IMG-E01-S01-003-V2 只通过自动 QA，未完成人工确认
return_to: human-director
required_input:
  - 当前图片的 APPROVED 状态、approved_by 和锁定字段
```

禁止输出“可执行暂定 Prompt”。

Seedance 2.5 只有模型名和“全能参考/5000 字”时同样返回 `HUMAN_GATE`，要求完整 `VERIFIED` 规则配置。

## 4. 时长超载路由

若 15 秒 PASS 分镜行同时要求复杂空间建立、敌人冲刺、女主奔跑喊话、捡枪、换握、瞄准、开火、能量攻击、第三人飞入救场和后续两句对白，负荷远超建议容量。

S05 不删除剧情、不加速全部动作、不自行拆镜，输出：

```yaml
status: HUMAN_GATE
shot_id: SHOT-E01-S01-010
issue_type: DURATION_ACTION_DIALOGUE_OVERLOAD
evidence:
  estimated_load_points: 20
  recommended_budget: 9
  locked_duration_seconds: 15
return_to: storyboard-table-director
required_decision: 由 S03 拆镜/调整时长并重新通过 QA 后，使旧图片和 VP 标记 STALE
```

## 5. 局部返修示例

若上一版把通知书写成左手，而图片、分镜表和连续性均锁定右手，RepairTicket 只开放持物手相关路径：

- 把 `start_state.props[].holder_or_contact` 改回右手；
- 同步修改对应 `action_flow` 和 body 时间段镜像；
- 不改变双人位置、景别、焦段、台词、光影、时长和计划落点；
- `V1 → V2`，状态回到 `DRAFT`，重新提交 `QA:VIDEO_PROMPT`。

## 6. 当前图片资料

工作区三张 PNG：

- 一张空白 16 格竖屏拼版模板；
- 两张带红色镜号的黑白剧情联系表，合计 01–26 镜；
- 后段包含录音计时、时间卡和中文字幕画面。

它们没有结构化 `shot_id/prompt_id/image_version` 清单、人工批准状态、上游分镜表、原始对白或资产槽位，因此不能直接通过 S05 门禁。可用方式：

- 空白模板只用于外部审核拼版，不是视频参考资产。
- 联系表可做视觉读取/连续性 smoke test，但必须由测试夹具显式标为“合成元数据”，不能伪称生产 APPROVED。
- 红色镜号、白色边框、录音界面以外的拼版文字和水印默认不继承。
- 时间/录音/字幕文字只有上游给出精确源文本并批准时才允许生成。

## 7. 实测案例索引

按标签检索原知识库，不整库复制到上下文：

| 案例 | 状态 | 可继承内容 | 不可声称 |
|---|---|---|---|
| `LY-EP26-素材槽位-001` | 待实测 | 一槽多物是风险；独立对象分槽 | 修改方案已验证有效 |
| `LY-EP26-空间连续-002` | 待实测 | 模糊“左前/右后”会导致方向错误 | 修订已通过生成 |
| `LY-EP26-时长负荷-003` | 待实测 | 15 秒约 20 负荷点必须拆分 | 新拆法已通过 |
| `NT-喜剧场-表演-001` | 待实测 | 抽象情绪不足，需身体节拍 | 具体微表演模板已验证 |
| `QL-登场场-镜头节奏-001` | 失败 | 避免 8–9 秒大全景等人走近；需要悬念/反应/揭示层级 | 修改方案是成功模板 |
| `QL-羞辱对白-表演运镜-002` | 部分通过 | 可保留已确认空间轴线、对位和独立口型窗口 | 站桩对白、无关键词落点部分可用 |
| `QL-捧杀对白-群像静止-003` | 失败 | 避免克制=冻结、群像静止、听者无反应、慢推静态脸、槽位格式混用 | 新写法已复测通过 |
| `QL-群英楼-光影平淡-004` | 失败 | 避免泛化暖光、大平光、全场等亮、白衣过曝 | 六层修订已实拍验证 |
| `QL-第9集-整集总纲冒充Prompt-005` | 失败 | 单段门禁；整集总纲不能冒充最终 Prompt | 旧整集写法可投喂 |
| `QL-规则外露动作退化-006` | 失败 | 规则需内化为动作、表演、声光和运镜；正文不能像说明书 | 新规则版本已生成验证 |

当前案例统计是 4 个待实测、5 个失败、1 个部分通过，0 个“已验证通过”。

## 8. 案例使用规则

1. 失败案例只用于避错，不复制原 Prompt，不把修改假设当成功模板。
2. 部分通过案例只继承明确标注为可保留的部分。
3. 待实测案例只能作为风险提示和测试假设。
4. 案例状态、模型版本或项目条件不同，不直接泛化。
5. 形成正式正例至少需要：完整上游、VideoPromptSpec、实际生成结果和独立 QA/导演确认。
6. 每次模型规则升级后重新判断案例是否失效。
