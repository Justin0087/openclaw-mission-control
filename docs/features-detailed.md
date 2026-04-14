# 功能详细说明文档

## 目录

1. [组织与成员管理](#1-组织与成员管理)
2. [Board 管理](#2-board-管理)
3. [任务管理](#3-任务管理)
4. [审批工作流](#4-审批工作流)
5. [Agent 管理与生命周期](#5-agent-管理与生命周期)
6. [网关管理](#6-网关管理)
7. [Board 记忆与聊天](#7-board-记忆与聊天)
8. [Board 引导流程](#8-board-引导流程)
9. [Webhook 系统](#9-webhook-系统)
10. [技能市场](#10-技能市场)
11. [标签系统](#11-标签系统)
12. [自定义字段](#12-自定义字段)
13. [活动流与审计](#13-活动流与审计)
14. [仪表盘与指标](#14-仪表盘与指标)
15. [用户设置](#15-用户设置)
16. [Board 分组](#16-board-分组)
17. [Souls 模板目录](#17-souls-模板目录)

---

## 1. 组织与成员管理

### 概述
Organization 是 Mission Control 的顶级租户实体。所有 Board、Agent、Gateway、Tag、技能等资源都从属于一个 Organization。

### 功能清单

| 功能 | 角色要求 | API 端点 |
|------|---------|---------|
| 创建组织 | 任何已认证用户 | `POST /api/v1/organizations` |
| 查看当前组织 | Org Member | `GET /api/v1/organizations/me` |
| 编辑组织 | Org Admin | `PATCH /api/v1/organizations/me` |
| 查看成员列表 | Org Member | `GET /api/v1/organizations/members` |
| 修改成员权限 | Org Admin | `PATCH /api/v1/organizations/members/{id}` |
| 移除成员 | Org Admin | `DELETE /api/v1/organizations/members/{id}` |
| 发送邀请 | Org Admin | `POST /api/v1/organizations/invites` |
| 查看邀请列表 | Org Member | `GET /api/v1/organizations/invites` |
| 接受邀请 | 被邀请用户 | `POST /api/v1/organizations/invites/{id}/accept` |
| 撤回邀请 | Org Admin | `DELETE /api/v1/organizations/invites/{id}` |
| 查看Board访问矩阵 | Org Admin | `GET /api/v1/organizations/board-access/{member_id}` |

### 权限模型

```
OrganizationMember
├── role: "admin" | "member"
├── all_boards_read: bool (全局 Board 读权限)
├── all_boards_write: bool (全局 Board 写权限)
└── OrganizationBoardAccess (每 Board 细粒度)
    ├── board_id
    ├── can_read: bool
    └── can_write: bool
```

### 邀请流程

```
Admin 创建邀请 (指定 email + role + Board 权限)
  │
  ▼
邀请记录创建 (含 unique token)
  │
  ▼
被邀请用户登录后接受邀请
  │
  ├── 自动创建 OrganizationMember
  ├── 应用预定义的 Board 权限
  └── 自动配置默认技能包
```

### 自动成员创建
新用户首次通过 `/api/v1/auth/bootstrap` 登录时，如果没有所属组织，系统会自动创建一个组织并将用户设为 Admin。

---

## 2. Board 管理

### 概述
Board 是 Mission Control 的核心工作单位，代表一个目标或项目。每个 Board 有自己的任务列表、Agent、审批规则和记忆。

### 功能清单

| 功能 | 角色要求 | API 端点 |
|------|---------|---------|
| 列出 Board | Org Member (按权限过滤) | `GET /api/v1/boards` |
| 创建 Board | Org Admin | `POST /api/v1/boards` |
| 查看 Board | Actor (read) | `GET /api/v1/boards/{id}` |
| 编辑 Board | User (write) | `PATCH /api/v1/boards/{id}` |
| 删除 Board | Org Admin | `DELETE /api/v1/boards/{id}` |
| 获取 Board 快照 | Actor (read) | `GET /api/v1/boards/{id}/snapshot` |

### Board 配置选项

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `board_type` | string | "goal" | Board 类型 |
| `objective` | string | — | Board 目标描述 |
| `success_metrics` | JSON | — | 成功指标 |
| `target_date` | datetime | — | 目标日期 |
| `max_agents` | int | 1 | 最大 Agent 数量 |
| `require_approval_for_done` | bool | true | 任务完成需要审批 |
| `require_review_before_done` | bool | false | 任务完成需要先 review |
| `comment_required_for_review` | bool | false | review 需要附带评论 |
| `block_status_changes_with_pending_approval` | bool | false | 有待处理审批时阻止状态变更 |
| `only_lead_can_change_status` | bool | false | 仅 Lead Agent 可变更状态 |

### Board 快照
快照聚合 Board 的完整状态，包括任务列表、审批状态、近期记忆，供 Agent 一次性获取上下文。

### Board 删除级联
删除 Board 时级联删除：所有任务、Agent、审批、记忆、Webhook、依赖关系、引导会话、指纹等。

### 前端 UI
- 列表页：表格视图，支持排序和删除
- 详情页：Kanban 看板 (inbox → in_progress → review → done) + 审批面板 + 聊天组件
- 支持拖拽任务在列之间移动

---

## 3. 任务管理

### 概述
Task 是 Board 内的工作单元，支持完整的状态流转、Agent 分配、标签、依赖关系、自定义字段和评论。

### 功能清单

| 功能 | 角色要求 | API 端点 |
|------|---------|---------|
| 列出任务 | Actor (read) | `GET /api/v1/boards/{id}/tasks` |
| 实时任务流 | Actor | `GET /api/v1/boards/{id}/tasks/stream` (SSE) |
| 创建任务 | Actor (write) | `POST /api/v1/boards/{id}/tasks` |
| 查看任务 | Actor (read) | `GET /api/v1/boards/{id}/tasks/{task_id}` |
| 更新任务 | Actor (write) | `PATCH /api/v1/boards/{id}/tasks/{task_id}` |
| 删除任务 | User (write) | `DELETE /api/v1/boards/{id}/tasks/{task_id}` |
| 任务评论列表 | Actor | `GET .../tasks/{id}/comments` |
| 任务评论流 | Actor | `GET .../tasks/{id}/comments/stream` (SSE) |
| 创建评论 | Actor | `POST .../tasks/{id}/comments` |

### 状态流转

```
inbox ──► in_progress ──► review ──► done
  │           │              │
  │           │              ▼
  │           │        (审批门控)
  │           │         如果 require_approval_for_done=true
  │           │         需要 approved 状态的审批才能 done
  │           │
  │           └── ← (任何时候可退回)
  └── ← (任何时候可退回)
```

### 任务依赖 (DAG)

```
Task A ──depends_on──► Task B
                        │
                        ▼
            Task B 未完成 → Task A 显示"已阻塞"
            Task B 完成后 → Task A 解除阻塞
```

- 依赖关系是有向无环图 (DAG)
- 系统会做循环检测，拒绝创建环
- 前端显示 DependencyBanner 阻塞提示

### 任务指纹去重
使用 SHA-256 哈希 (标题 + 描述 + board_id) 生成指纹，防止 Agent 创建重复任务。

### 前端 Kanban 视图

```
┌─────────┐ ┌────────────┐ ┌──────────┐ ┌─────────┐
│  Inbox  │ │ In Progress│ │  Review  │ │  Done   │
├─────────┤ ├────────────┤ ├──────────┤ ├─────────┤
│ TaskCard│ │  TaskCard  │ │ TaskCard │ │TaskCard │
│ TaskCard│ │            │ │          │ │TaskCard │
│         │ │            │ │          │ │         │
└─────────┘ └────────────┘ └──────────┘ └─────────┘
         ◄──── 拖拽移动 ────►
```

---

## 4. 审批工作流

### 概述
Approval 是 Mission Control 的治理核心。Agent 在执行敏感操作前提交审批，人类操作者或 Lead Agent 审核后决定是否放行。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出审批 (含筛选) | `GET /api/v1/boards/{id}/approvals?status=pending` |
| 实时审批流 | `GET /api/v1/boards/{id}/approvals/stream` (SSE) |
| 创建审批 | `POST /api/v1/boards/{id}/approvals` |
| 查看审批详情 | `GET /api/v1/boards/{id}/approvals/{approval_id}` |
| 更新审批状态 | `PATCH /api/v1/boards/{id}/approvals/{approval_id}` |
| 全局审批视图 | 前端 `/approvals` 页面 |

### 审批状态机

```
pending ──► approved   (放行)
   │
   ├──► rejected    (拒绝)
   │
   └──► cancelled   (取消)
```

### 审批-任务关联 (N:M)
一个审批可以关联多个任务 (通过 ApprovalTaskLink)。当审批被批准后，关联的任务才能进入 done 状态。

### 置信度评分

```python
confidence = compute_confidence(rubric_scores)
# rubric_scores: {"accuracy": 5, "completeness": 4, "safety": 5}
# 加权计算后得出 0.0-1.0 的置信度分数

if confidence < threshold or is_external or is_risky:
    → 需要人工审批
else:
    → 可自动通过
```

### 冲突检测
当 Board 配置 `block_status_changes_with_pending_approval=true` 时：
- 有待处理审批的任务不能变更状态
- API 返回冲突的审批 ID 列表

---

## 5. Agent 管理与生命周期

### 概述
Agent 是 Mission Control 中的 AI 执行单元，通过 Gateway 部署到远程环境中运行。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出 Agent | `GET /api/v1/agents` |
| 实时 Agent 流 | `GET /api/v1/agents/stream` (SSE) |
| 创建 Agent | `POST /api/v1/agents` |
| 查看 Agent | `GET /api/v1/agents/{id}` |
| 更新 Agent | `PATCH /api/v1/agents/{id}` |
| 心跳上报 | `POST /api/v1/agents/{id}/heartbeat` |
| Agent 自身操作 | `GET/POST /api/v1/agent/*` (50+ 端点) |

### Agent 角色

| 角色 | 作用域 | 核心职责 |
|------|--------|---------|
| **Main** | Gateway 级 | 网关控制、模板管理、Agent 配置分发 |
| **Lead** | Board 级 | 任务规划、工作分配、置信度评估、审批发起 |
| **Worker** | Board 级 | 任务执行、状态上报、评论提交 |

### 生命周期状态

```
创建 → provisioning
          │
          ▼
       active ←─── heartbeat (每 30 秒)
          │
          ├──► idle (超时未心跳)
          │
          ├──► offline (长时间无响应)
          │
          └──► error (异常)
```

### Agent 自身操作 (agent.py)

Agent 通过 `X-Agent-Token` 认证后可执行的操作 (按角色分)：

**Lead Agent：**
- 查看/创建/更新任务
- 发起审批
- 写入 Board 记忆
- 广播消息给其他 Agent
- 查看 Board 快照和引导状态

**Worker Agent：**
- 查看分配给自己的任务
- 更新任务状态
- 提交任务评论
- 读取 Board 记忆
- 上报心跳

**Main Agent：**
- 网关级控制操作
- Agent 元数据查询
- 会话管理

### 心跳机制
- Agent 每 30 秒上报心跳
- 后端对 `last_seen_at` 做节流写入 (30 秒间隔, 仅非安全方法触发)
- 速率限制: 20 请求/60秒/IP

---

## 6. 网关管理

### 概述
Gateway 是连接 Mission Control 与远程 OpenClaw 运行环境的桥梁。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出网关 | `GET /api/v1/gateways` |
| 创建网关 | `POST /api/v1/gateways` |
| 查看网关 | `GET /api/v1/gateways/{id}` |
| 更新网关 | `PATCH /api/v1/gateways/{id}` |
| 模板同步 | `POST /api/v1/gateways/{id}/templates/sync` |
| 网关状态 | `GET /api/v1/gateways/status` |
| 会话列表 | `GET /api/v1/gateways/sessions` |
| 会话详情 | `GET /api/v1/gateways/sessions/{id}` |
| 会话历史 | `GET /api/v1/gateways/sessions/{id}/history` |

### 网关配置

| 字段 | 说明 |
|------|------|
| `name` | 网关名称 |
| `url` | WebSocket URL (wss://) |
| `token` | 认证令牌 |
| `workspace_root` | 工作空间根路径 |
| `disable_device_pairing` | 禁用设备配对 |
| `allow_insecure_tls` | 允许不安全 TLS |

### 模板同步
同步操作将 Jinja2 模板渲染后推送到网关，可选项：
- `include_main`: 包含主 Agent 模板
- `reset_sessions`: 重置网关会话
- `rotate_tokens`: 轮换认证令牌
- `overwrite`: 覆盖已有配置

---

## 7. Board 记忆与聊天

### 概述
Board Memory 是 Board 级别的持久化上下文系统，同时支持"系统记忆"和"聊天消息"两种模式。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出记忆 | `GET /api/v1/boards/{id}/memory?is_chat=true/false` |
| 实时记忆流 | `GET /api/v1/boards/{id}/memory/stream` (SSE) |
| 写入记忆 | `POST /api/v1/boards/{id}/memory` |
| 暂停 Board | `POST /api/v1/boards/{id}/memory/pause` |

### 两种模式

| 模式 | `is_chat` | 用途 |
|------|-----------|------|
| 系统记忆 | false | 持久化上下文 (目标、决策、要点) |
| 聊天消息 | true | 实时对话, @提及 Agent, 指令下发 |

### @提及机制
聊天消息中使用 `@agent-name` 语法提及 Agent。后端 `mentions.py` 服务提取提及并广播给对应 Agent。

### Board 分组记忆
Board Group 也有独立的记忆系统 (BoardGroupMemory)，在分组内所有 Board 之间共享。

---

## 8. Board 引导流程

### 概述
Onboarding 是 Board 的初始配置向导，通过对话式交互帮助用户设定目标和配置 Lead Agent。

### 流程

```
1. 用户开始引导 (POST /start)
   │
   ▼
2. 系统提问, 用户回答 (POST /answer) × N 轮
   │
   ▼
3. 生成 Lead Agent 草案 (GET /lead-agent-draft)
   │
   ▼
4. 用户确认 (POST /confirm)
   │
   ├── 设定 Board 目标
   ├── 创建 Lead Agent
   └── 触发 Gateway 预配置
   │
   ▼
5. Lead Agent 完成初始化 (POST /lead-agent-complete)
```

### 数据持久化
- `BoardOnboardingSession.messages`: JSON 数组存储对话历史
- `BoardOnboardingSession.draft_goal`: JSON 存储目标草案
- 状态: `active` → `completed`

---

## 9. Webhook 系统

### 概述
Board Webhook 允许外部系统通过 HTTP 推送事件到 Board，支持 HMAC 签名验证。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出 Webhook | `GET /api/v1/boards/{id}/webhooks` |
| 创建 Webhook | `POST /api/v1/boards/{id}/webhooks` |
| 查看 Webhook | `GET .../webhooks/{webhook_id}` |
| 更新 Webhook | `PATCH .../webhooks/{webhook_id}` |
| 删除 Webhook | `DELETE .../webhooks/{webhook_id}` |
| 查看 Payload 记录 | `GET .../webhooks/{webhook_id}/payloads` |
| Webhook 接收 (无需认证) | `POST .../webhooks/{webhook_id}` |

### 安全机制
- HMAC-SHA256 签名验证
- 可配置签名头名称
- payload 记录包含 headers、source_ip、content_type
- 速率限制: 60 请求/60秒/IP

### Payload 处理流程

```
外部系统 POST → Webhook 端点
  │
  ├── 验证 HMAC 签名 (如果配置了 secret)
  ├── 解析 payload (JSON/form/text)
  ├── 记录 BoardWebhookPayload
  ├── 入队异步处理 (Redis Queue)
  │
  ▼
Worker 异步处理 → 投递给相关 Agent
```

---

## 10. 技能市场

### 概述
Skills Marketplace 允许组织管理和安装 Agent 可用的技能。技能来自 Git 仓库，可以打包为 Skill Pack。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出技能 | `GET /api/v1/skills` |
| 创建技能 | `POST /api/v1/skills` |
| 查看技能 | `GET /api/v1/skills/{id}` |
| 安装技能到网关 | `POST /api/v1/skills/{id}/install` |
| 列出技能包 | `GET /api/v1/skills/packs` |
| 创建技能包 | `POST /api/v1/skills/packs` |
| 同步技能包 | `POST /api/v1/skills/packs/{id}/sync` |

### 技能模型

```
SkillPack (技能包)
  source_url: Git 仓库 URL
  branch: 分支名 (默认 "main")
     │
     │ sync 操作
     ▼
MarketplaceSkill (市场技能)
  name, description, category, risk
  source_url: 具体技能 URL
     │
     │ install 操作
     ▼
GatewayInstalledSkill (已安装技能)
  gateway_id + skill_id
```

---

## 11. 标签系统

### 概述
Tag 是组织级别的标签，用于对任务进行分类和筛选。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出标签 | `GET /api/v1/tags` |
| 创建标签 | `POST /api/v1/tags` |
| 查看标签 | `GET /api/v1/tags/{id}` |
| 更新标签 | `PATCH /api/v1/tags/{id}` |
| 删除标签 | `DELETE /api/v1/tags/{id}` |

### 标签属性
- `name`: 标签名称
- `slug`: 自动生成的 URL 友好名 (小写, 空格→连字符)
- `color`: 颜色代码 (默认 "9e9e9e")
- `description`: 描述
- `task_count`: 聚合字段, 关联任务数

### 任务-标签关联
通过 TagAssignment (task_id + tag_id) 实现多对多关联。任务更新时可批量替换标签。

---

## 12. 自定义字段

### 概述
Custom Fields 允许组织定义自定义的任务字段，按 Board 启用。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出字段定义 | `GET /api/v1/organizations/me/custom-fields` |
| 创建字段定义 | `POST /api/v1/organizations/me/custom-fields` |
| 查看字段 | `GET .../custom-fields/{id}` |
| 更新字段 | `PATCH .../custom-fields/{id}` |
| 删除字段 | `DELETE .../custom-fields/{id}` |
| 分配到 Board | `PATCH .../custom-fields/{id}/boards?board_ids=...` |

### 字段类型

| 类型 | 说明 |
|------|------|
| `text` | 单行文本 |
| `text_long` | 多行文本 |
| `integer` | 整数 |
| `decimal` | 小数 |
| `boolean` | 布尔 |
| `date` | 日期 |
| `date_time` | 日期时间 |
| `url` | URL |
| `json` | JSON 数据 |

### 三级结构

```
TaskCustomFieldDefinition (组织级定义)
  │
  ├── BoardTaskCustomField (Board 级启用)
  │
  └── TaskCustomFieldValue (任务级值)
```

---

## 13. 活动流与审计

### 概述
Activity Feed 记录系统中的所有操作事件，提供审计追踪能力。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出活动 | `GET /api/v1/activity` |
| 实时活动流 | `GET /api/v1/activity/stream` (SSE) |

### 事件类型
- 任务创建/更新/状态变更
- 审批创建/审核
- Agent 上线/下线
- Board 聊天消息
- 任务评论

### 前端实时活动页
- 并行开启多个 SSE 连接 (每个 Board 一个)
- 最大 300 条事件 + 去重
- 事件映射到前端路由 (点击跳转)
- 页面不活跃时暂停流

---

## 14. 仪表盘与指标

### 概述
Dashboard 提供 KPI 面板和时间序列图表，展示组织运营状况。

### 指标端点

| 端点 | 说明 |
|------|------|
| `GET /api/v1/metrics/kpis` | 关键绩效指标 (任务数/审批/完成率) |
| `GET /api/v1/metrics/graphs` | 时间序列 (任务创建/状态变更/审批) |
| `GET /api/v1/metrics/wip` | 在制品 (WIP) 按 Board/状态 |

### 时间范围
24h / 3d / 7d / 14d / 1m / 3m / 6m / 1y

### 支持的过滤
- `board_id`: 按 Board 筛选
- `group_id`: 按 Board 分组筛选

---

## 15. 用户设置

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 查看个人资料 | `GET /api/v1/users/me` |
| 更新个人资料 | `PATCH /api/v1/users/me` |
| 删除账户 | `DELETE /api/v1/users/me` |

### 可编辑字段
- `name`: 显示名称
- `preferred_name`: 首选名称
- `pronouns`: 代词
- `timezone`: 时区
- `notes`: 备注
- `context`: 上下文信息

### 账户删除
级联删除：用户所有组织 → 组织下所有资源 (Agent, Board, Task, 审批, 记忆, Webhook 等)。

---

## 16. Board 分组

### 概述
Board Group 将多个 Board 归类管理，支持分组快照和分组心跳。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 列出分组 | `GET /api/v1/board-groups` |
| 创建分组 | `POST /api/v1/board-groups` |
| 查看分组 | `GET /api/v1/board-groups/{id}` |
| 更新分组 | `PATCH /api/v1/board-groups/{id}` |
| 删除分组 | `DELETE /api/v1/board-groups/{id}` |
| 分组快照 | `GET /api/v1/board-groups/{id}/snapshot` |
| 分组心跳 | `POST /api/v1/board-groups/{id}/heartbeat` |

### 分组快照
聚合分组内所有 Board 的任务，按状态和优先级排序。

### 分组记忆
独立于 Board 记忆的共享上下文，在分组内所有 Board 之间共享。

---

## 17. Souls 模板目录

### 概述
Souls Directory 是一个只读的 Agent soul 模板搜索服务，从 GitHub 获取模板。

### 功能清单

| 功能 | API 端点 |
|------|---------|
| 搜索模板 | `GET /api/v1/souls-directory/search` |
| 获取模板内容 | `GET /api/v1/souls-directory/{handle}/{slug}` |
| 获取 Markdown | `GET /api/v1/souls-directory/{handle}/{slug}.md` |

### 数据来源
- GitHub sitemap 解析
- raw.githubusercontent.com 获取 Markdown 内容
- 模糊搜索 (handle + slug 子串匹配)
