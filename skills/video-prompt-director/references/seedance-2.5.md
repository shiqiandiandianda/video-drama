# Seedance 2.5 规则可用性门禁

## 目录

1. 当前支持状态
2. 已知硬约束
3. 正式启用所需配置
4. 执行规则
5. 禁止降级伪装

## 1. 当前支持状态

当前工作区没有独立、已验证的 Seedance 2.5 规则文件或通过样本。现有资料只给出模型名、`product_flow: 全能参考` 示例和正文不超过 5000 字的要求。

这些信息不足以确认 2.5 的参考素材类型、任务句式、产品模式、槽位协议、编辑/延长语法和能力边界。因此默认：

```yaml
model: seedance-2.5
support_status: BLOCKED_PENDING_VERIFIED_PROFILE
decision: HUMAN_GATE
```

不得因为用户填了 `model: seedance-2.5` 就直接套用 Seedance 2.0 规则。

## 2. 已知硬约束

当且仅当外部提供已验证 2.5 配置并通过第 3 节门禁后，仍必须满足：

- `task.model: seedance-2.5`。
- 目标 `product_flow` 明确且由已验证配置列为支持。
- `body_char_count <= 5000`。
- 一份 `VideoPromptSpec` 只对应一个 `shot_id` 和一套连续时间轴。
- APPROVED 分镜、PASS 上游、对白保真、锁定字段、计划镜尾和独立 QA 等公共协议继续有效。

5000 字计数口径：只统计 `body`，先把行尾归一化为 LF，再按 Unicode code point 计数；包含标点、空格和换行，不包含宿主展示添加的 Markdown 代码围栏。4999、5000、5001 必须分别做边界测试。

## 3. 正式启用所需配置

调用方必须提供：

```yaml
model_rule_profile:
  rule_id: SD25-<VERSION>
  model: seedance-2.5
  status: VERIFIED
  verified_at: <日期>
  source: <官方/产品锁定规则或已验证内部规范>
  supported_product_flows: []
  supported_generation_tasks:
    - MULTIMODAL_REFERENCE
  accepted_reference_types: []
  task_phrasing:
    multimodal_reference: <准确句式>
    edit_video: <若支持>
    extend_forward: <若支持>
    extend_backward: <若支持>
    composite: <若支持>
  slot_syntax: <准确格式>
  body_char_limit: 5000
  timing_rules: <平台已验证口径>
  unsupported_features: []
  evidence_examples: []
```

以下字段缺一即阻断：规则 ID/版本、`VERIFIED` 状态、来源、当前产品模式、当前任务类型、参考类型、任务句式、槽位语法和 5000 字限制。

`evidence_examples` 至少应包含一条已验证通过的输入、正文和结果/QA 结论；只有失败案例不能把配置标为 `VERIFIED`。

## 4. 执行规则

通过配置门禁后：

1. 只按该配置选择产品模式、素材声明和任务句式。
2. 公共的单镜头、上游锁定、动作物理、对白、连续性、光学和正文纯净规则继续执行。
3. 配置与项目锁定事实冲突时，模型格式不能改写剧情/分镜；进入 `HUMAN_GATE`。
4. 配置声明某任务不支持时不尝试提示词绕过，返回产品/模型路由。
5. 正文超过 5000 时先删除规则解释和重复描述；若仍超限且删除会损失锁定内容，返回 S03/`HUMAN_GATE`，不删剧情或台词。

## 5. 禁止降级伪装

- 不把 Seedance 2.0 reference 改标题当作 2.5 规则。
- 不从“全能参考”四个字推导完整产品能力。
- 不仅凭 `<=5000` 就声称 2.5 可投喂。
- 不用搜索到的未验证帖子、旧截图或模型推断自动把配置标为 `VERIFIED`。
- 不在缺配置时输出“可执行暂定版”并暗示已经符合 2.5；只能输出缺口报告与 `HUMAN_GATE`。
