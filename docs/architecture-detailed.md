# 软件架构文档

## 目录

1. [系统概述](#1-系统概述)
2. [技术栈](#2-技术栈)
3. [系统拓扑](#3-系统拓扑)
4. [后端架构](#4-后端架构)
5. [前端架构](#5-前端架构)
6. [数据模型](#6-数据模型)
7. [认证与授权体系](#7-认证与授权体系)
8. [实时通信机制](#8-实时通信机制)
9. [异步任务与队列](#9-异步任务与队列)
10. [网关与Agent编排](#10-网关与agent编排)

---

## 1. 系统概述

OpenClaw Mission Control 是一个集中式运维与治理平台，用于跨团队和组织运行 OpenClaw Agent。它提供统一的可视化界面、审批控制和网关感知的编排能力。

核心定位：
- **运维优先**：为可靠地运行 Agent 工作而构建，而非仅创建任务
- **治理内置**：审批、认证模式和清晰的控制边界是一等公民
- **网关感知**：支持本地和连接式运行时环境

## 2. 技术栈

```
┌─────────────────────────────────────────────────────┐
│                    前端 (Frontend)                    │
│  Next.js 16 · React 19 · TypeScript · TailwindCSS   │
│  TanStack React Query · Orval (API 客户端生成)        │
│  Radix UI · shadcn/ui 组件模式                        │
└───────────────────────┬─────────────────────────────┘
                        │ HTTP / SSE
┌───────────────────────┴─────────────────────────────┐
│                    后端 (Backend)                     │
│  FastAPI · Python 3.12+ · Pydantic V2               │
│  SQLModel · SQLAlchemy · Alembic (数据库迁移)         │
│  fastapi-pagination · Jinja2 (模板)                  │
└──────┬──────────────┬───────────────┬───────────────┘
       │              │               │
┌──────┴──────┐ ┌─────┴─────┐ ┌──────┴──────┐
│  PostgreSQL │ │   Redis   │ │   Worker    │
│  16-alpine  │ │ 7-alpine  │ │  (RQ 队列)  │
│  数据持久化   │ │ 任务队列   │ │ Webhook处理 │
└─────────────┘ └───────────┘ └─────────────┘
```

| 层 | 技术 | 版本 |
|---|---|---|
| 前端框架 | Next.js (App Router) | 16.1.7 |
| UI 框架 | React | 19.2.4 |
| 样式 | TailwindCSS + tailwindcss-animate | — |
| 数据获取 | TanStack React Query + Orval 生成 | — |
| 后端框架 | FastAPI | 0.131.0 |
| ORM | SQLModel + SQLAlchemy | 0.0.32 / 2.0.46 |
| 数据库 | PostgreSQL | 16 |
| 缓存/队列 | Redis + RQ | 7 / 2.6.0 |
| 认证 | Clerk (生产) / Local Token (自托管) | — |
| Python 管理 | uv | latest |
| 前端包管理 | npm | — |

## 3. 系统拓扑

### 运行时服务

```
                    ┌──────────────┐
                    │   Browser    │
                    │  (用户/操作者) │
                    └──────┬───────┘
                           │ HTTP :3000
                    ┌──────┴───────┐
                    │   Frontend   │
                    │  (Next.js)   │
                    │   :3000      │
                    └──────┬───────┘
                           │ HTTP / SSE :8000
                    ┌──────┴───────┐
                    │   Backend    │◄──── OpenClaw Gateway
                    │  (FastAPI)   │      (WebSocket 双向通信)
                    │   :8000      │
                    └──┬───────┬───┘
                       │       │
              ┌────────┴──┐ ┌──┴────────┐
              │ PostgreSQL│ │   Redis   │
              │  :5432    │ │  :6379    │
              └───────────┘ └─────┬─────┘
                                  │
                           ┌──────┴──────┐
                           │   Worker    │
                           │ (RQ 消费者)  │
                           │ Webhook 投递 │
                           │ 异步任务处理  │
                           └─────────────┘
```

### Docker Compose 服务映射

| 服务名 | 镜像/构建 | 端口 | 依赖 |
|--------|----------|------|------|
| `db` | postgres:16-alpine | 5432 | — |
| `redis` | redis:7-alpine | 6379 | — |
| `backend` | ./backend/Dockerfile | 8000 | db (healthy), redis (healthy) |
| `frontend` | ./frontend/Dockerfile | 3000 | backend |
| `webhook-worker` | ./backend/Dockerfile | 无 | db (healthy), redis (healthy) |

## 4. 后端架构

### 分层结构

```
backend/app/
├── api/              # 路由层 (25 个路由模块)
│   ├── deps.py       # 依赖注入定义 (认证、会话、资源解析)
│   ├── agents.py     # Agent 组织级管理
│   ├── agent.py      # Agent 作用域操作 (50+ 端点)
│   ├── approvals.py  # 审批工作流
│   ├── boards.py     # Board CRUD + 快照
│   ├── tasks.py      # 任务 CRUD + 评论 + SSE
│   └── ...           # 其余 19 个路由模块
├── core/             # 核心基础设施
│   ├── config.py     # 环境变量加载与校验
│   ├── auth.py       # 用户认证 (Clerk JWT)
│   ├── agent_auth.py # Agent 认证 (X-Agent-Token)
│   ├── time.py       # 统一时间处理 (utcnow)
│   ├── logging.py    # 集中日志
│   └── error_handling.py # 全局错误处理
├── db/               # 数据库层
│   ├── session.py    # 会话管理 + 迁移逻辑
│   ├── query_manager.py # QueryModel ORM 描述符
│   └── crud.py       # 基础 CRUD 异常
├── models/           # 数据模型 (29 个模型)
│   ├── base.py       # QueryModel 基类
│   ├── tenancy.py    # TenantScoped 多租户基类
│   ├── __init__.py   # 模型注册 (Alembic 发现)
│   └── ...           # 各业务模型
├── schemas/          # Pydantic V2 输入/输出模式
│   ├── common.py     # NonEmptyStr 等共享类型
│   └── ...           # 各业务 Schema
└── services/         # 业务逻辑层
    ├── board_lifecycle.py    # Board 生命周期 (级联删除)
    ├── board_snapshot.py     # Board 快照构建
    ├── lead_policy.py        # Lead Agent 置信度策略
    ├── mentions.py           # @提及提取
    ├── organizations.py      # 组织上下文与权限
    ├── queue.py              # Redis 队列封装
    ├── queue_worker.py       # Worker 消费循环
    └── ...                   # 其余服务
```

### 请求处理流程

```
HTTP 请求
  │
  ├─ CORS 中间件 (跨域)
  ├─ Security Headers 中间件 (安全头)
  │
  ▼
FastAPI 路由匹配
  │
  ├─ Depends(get_auth_context)        → 用户认证
  ├─ Depends(get_agent_auth_context)  → Agent 认证
  ├─ Depends(require_org_member)      → 组织成员检查
  ├─ Depends(get_board_for_actor_read/write) → Board 访问控制
  ├─ Depends(get_task_or_404)         → 资源解析
  │
  ▼
路由处理函数
  │
  ├─ 调用 Service 层 (业务逻辑)
  ├─ 调用 record_activity() (审计记录)
  │
  ▼
session.commit()
  │
  ▼
Pydantic 序列化 → JSON 响应
```

### API 路由总表

| 前缀 | 模块 | 功能 | 认证 |
|------|------|------|------|
| `/api/v1/auth` | auth.py | 用户认证引导 | Bearer JWT |
| `/api/v1/agents` | agents.py | Agent 组织管理 | Org Admin |
| `/api/v1/agent` | agent.py | Agent 自身操作 (50+ 端点) | X-Agent-Token |
| `/api/v1/activity` | activity.py | 活动流 + SSE | Actor (用户/Agent) |
| `/api/v1/boards` | boards.py | Board CRUD + 快照 | Org Member/Admin |
| `/api/v1/boards/{id}/tasks` | tasks.py | 任务 CRUD + 评论 + SSE | Actor |
| `/api/v1/boards/{id}/approvals` | approvals.py | 审批工作流 | Actor |
| `/api/v1/boards/{id}/memory` | board_memory.py | Board 记忆/聊天 | Actor |
| `/api/v1/boards/{id}/webhooks` | board_webhooks.py | Webhook 配置 + 接收 | User / 无认证(接收) |
| `/api/v1/boards/{id}/onboarding` | board_onboarding.py | Board 引导流程 | User |
| `/api/v1/board-groups` | board_groups.py | Board 分组管理 | Org Member/Admin |
| `/api/v1/gateways` | gateways.py | 网关管理 + 会话检查 | Org Admin |
| `/api/v1/organizations` | organizations.py | 组织、成员、邀请 | User / Org Admin |
| `/api/v1/skills` | skills_marketplace.py | 技能市场 | Org Admin |
| `/api/v1/tags` | tags.py | 标签 CRUD | Org Member/Admin |
| `/api/v1/metrics` | metrics.py | 仪表盘指标 | Org Member |
| `/api/v1/users` | users.py | 用户资料 | User |
| `/api/v1/organizations/me/custom-fields` | task_custom_fields.py | 自定义字段 | Org Admin |
| `/api/v1/souls-directory` | souls_directory.py | Soul 模板目录 | Actor |

## 5. 前端架构

### 目录结构

```
frontend/src/
├── app/                    # Next.js App Router 页面
│   ├── layout.tsx          # 根布局 (Auth → Query → GlobalLoader)
│   ├── page.tsx            # 落地页
│   ├── sign-in/            # 登录页
│   ├── dashboard/          # 仪表盘
│   ├── activity/           # 活动流 (SSE 实时)
│   ├── boards/             # Board 管理 (列表/详情/编辑/Kanban)
│   ├── agents/             # Agent 管理
│   ├── approvals/          # 全局审批
│   ├── board-groups/       # Board 分组
│   ├── gateways/           # 网关管理
│   ├── skills/             # 技能市场
│   ├── tags/               # 标签管理
│   ├── custom-fields/      # 自定义字段
│   ├── organization/       # 组织设置
│   ├── settings/           # 用户设置
│   ├── onboarding/         # 新手引导
│   └── invite/             # 邀请接受
├── api/
│   ├── generated/          # Orval 生成 (禁止手动编辑)
│   └── mutator.ts          # 自定义 fetch: token 注入 + 错误处理
├── auth/
│   ├── mode.ts             # 认证模式枚举
│   ├── clerk.tsx           # Clerk 封装 (SignedIn/SignedOut)
│   └── localAuth.ts        # Local Token 管理
├── components/
│   ├── atoms/              # 原子组件 (BrandMark, StatusDot, StatusPill)
│   ├── molecules/          # 分子组件 (TaskCard, DependencyBanner)
│   ├── organisms/          # 有机体 (DashboardSidebar, TaskBoard, UserMenu)
│   ├── templates/          # 模板 (DashboardShell, LandingShell)
│   ├── ui/                 # 基础 UI (Button, Input, Dialog, Table)
│   ├── providers/          # 上下文提供者 (Auth, Query)
│   └── [feature]/          # 按功能分组 (agents/, boards/, tags/ 等)
├── hooks/                  # 自定义 Hooks
│   ├── usePageActive.ts    # 页面活跃检测 (控制 SSE)
│   └── ...
└── lib/                    # 工具函数
    ├── api-base.ts         # API URL 解析
    ├── list-delete.ts      # 乐观删除
    └── use-url-sorting.ts  # URL 排序状态
```

### 组件架构 (Atomic Design)

```
Template (DashboardShell)
  │
  ├── Organism (DashboardSidebar)
  │     ├── Atom (BrandMark)
  │     └── Atom (StatusDot) ← 健康检查指示器
  │
  ├── Organism (TaskBoard) ← Kanban 多列拖拽
  │     └── Molecule (TaskCard)
  │           ├── Atom (StatusPill)
  │           └── Atom (StatusDot)
  │
  └── Organism (BoardChatComposer)
```

### 数据流模式

```
┌─────────────┐    ┌──────────────┐    ┌───────────────┐
│  Orval 生成  │───►│ React Query  │───►│   组件渲染     │
│  API Hooks   │    │  缓存/同步    │    │  (useState)   │
└─────────────┘    └──────────────┘    └───────────────┘
       │                  │
       │           invalidateQueries()
       │                  │
       ▼                  ▼
┌─────────────┐    ┌──────────────┐
│  mutator.ts │    │  SSE Stream  │ ← 实时更新
│  Token 注入  │    │  轮询回退     │
└─────────────┘    └──────────────┘
```

## 6. 数据模型

### 实体关系总览

```
Organization (顶级租户)
│
├── BoardGroup (Board 分组)
│   ├── Board (工作板)
│   └── BoardGroupMemory (分组记忆)
│
├── Board (工作板) ──── Gateway (网关)
│   ├── Task (任务)
│   │   ├── TagAssignment → Tag
│   │   ├── TaskDependency (任务依赖 DAG)
│   │   ├── TaskCustomFieldValue → TaskCustomFieldDefinition
│   │   └── TaskFingerprint (去重指纹)
│   ├── Agent (AI Agent)
│   │   ├── Approval (审批)
│   │   │   └── ApprovalTaskLink (审批-任务 N:M)
│   │   └── ActivityEvent (活动事件)
│   ├── BoardMemory (Board 记忆/聊天)
│   ├── BoardWebhook → BoardWebhookPayload
│   └── BoardOnboardingSession
│
├── OrganizationMember → User
│   └── OrganizationBoardAccess (Board 级权限)
├── OrganizationInvite
│   └── OrganizationInviteBoardAccess
│
├── Tag (标签)
├── MarketplaceSkill → GatewayInstalledSkill
├── SkillPack
└── TaskCustomFieldDefinition
    └── BoardTaskCustomField (Board 级启用)
```

### 模型统计

| 类别 | 数量 |
|------|------|
| 总模型数 | 29 |
| QueryModel 基类 | 15 |
| TenantScoped (多租户) | 14 |
| 关联/桥表 | 5 |
| 含 JSON 列的模型 | 13 |
| 含唯一约束的模型 | 15 |
| 索引字段总计 | 90+ |

### 核心模型字段

#### Task (任务)
- `status`: inbox → in_progress → review → done
- `priority`: low / medium / high / critical
- `assigned_agent_id`: 分配给哪个 Agent
- `due_at`: 截止时间
- 支持依赖关系 (DAG)、自定义字段、标签、指纹去重

#### Agent
- `status`: provisioning / active / idle / offline / error
- `is_board_lead`: 是否为 Board 主导 Agent
- `heartbeat_config`: JSON 配置
- `identity_profile` / `identity_template` / `soul_template`: Agent 身份配置
- `lifecycle_generation`: 生命周期版本号
- `last_seen_at`: 30 秒间隔心跳更新

#### Board
- `board_type`: goal (目标导向)
- 治理配置：`require_approval_for_done`、`require_review_before_done`、`block_status_changes_with_pending_approval`、`only_lead_can_change_status`
- `max_agents`: 最大 Agent 数量限制
- `success_metrics`: JSON 成功指标

#### Approval (审批)
- `action_type`: 行为类型
- `confidence`: 置信度评分
- `rubric_scores`: JSON 评分细则
- `status`: pending → approved / rejected / cancelled
- 支持多任务关联 (N:M via ApprovalTaskLink)

## 7. 认证与授权体系

### 双模式认证

```
┌──────────────────────────────────────────────┐
│              认证模式选择                       │
│  NEXT_PUBLIC_AUTH_MODE / AUTH_MODE             │
├──────────────────┬───────────────────────────┤
│  "clerk" (生产)   │  "local" (自托管)          │
│  Clerk JWT       │  共享 Bearer Token         │
│  用户标识独立     │  所有用户共享同一 token     │
│  SSO/社交登录    │  sessionStorage 存储       │
│  最低 50 字符     │  最低 50 字符              │
└──────────────────┴───────────────────────────┘
```

### 三级授权模型

```
Level 1: Actor 类型
  ├── User (人类用户)
  │   ├── super_admin (全局管理员)
  │   ├── org admin (组织管理员)
  │   └── member (组织成员)
  └── Agent (AI Agent)
      ├── main (网关主 Agent)
      ├── lead (Board 主导)
      └── worker (Board 工作者)

Level 2: 组织上下文
  ├── OrganizationMember.role
  ├── OrganizationMember.all_boards_read / all_boards_write
  └── OrganizationBoardAccess (每 Board 细粒度)

Level 3: Board 作用域
  ├── Agent 只能访问自己所属的 Board
  ├── User 根据 Board Access 矩阵决定
  └── 治理配置 (审批门槛、状态变更限制 等)
```

### Agent 认证

```
HTTP 请求
  │
  ├─ Header: X-Agent-Token: <token>
  │  或 Authorization: Bearer <agent-token>
  │
  ▼
agent_auth.py → 验证 token hash
  │
  ├─ 更新 last_seen_at (30 秒节流)
  ├─ 速率限制: 20 req/60s per IP
  │
  ▼
AgentAuthContext { agent: Agent }
```

## 8. 实时通信机制

### Server-Sent Events (SSE)

本系统全部使用 SSE 而非 WebSocket 进行前端实时推送。

```
前端                                     后端
  │                                        │
  ├── GET /tasks/stream?since=T ─────────►│ 轮询数据库
  │                                        │ 发现新行 > since
  │◄── event: task                  ◄──────│
  │    data: {"id":..., "status":...}      │
  │                                        │
  │◄── event: task                  ◄──────│
  │    data: {...}                         │
  │                                        │
  │  (连接保持打开, 持续轮询)               │
```

#### SSE 端点列表

| 端点 | 推送内容 |
|------|---------|
| `/api/v1/boards/{id}/tasks/stream` | 任务创建/更新/状态变更 |
| `/api/v1/boards/{id}/approvals/stream` | 审批状态变更 |
| `/api/v1/agents/stream` | Agent 心跳/状态 |
| `/api/v1/boards/{id}/memory/stream` | Board 聊天/记忆 |
| `/api/v1/activity/stream` | 全局活动流 |

#### 前端重连策略

- 指数退避: 基础 1s, 倍率 2x, 抖动 0.2, 最大 5 分钟
- 页面不活跃时暂停流 (`usePageActive` hook)
- 最大保留 300 条事件, 去重 via `seenIdsRef`

## 9. 异步任务与队列

```
┌─────────────┐     enqueue      ┌─────────┐     dequeue      ┌──────────┐
│  Backend    │ ──────────────► │  Redis   │ ──────────────► │  Worker  │
│  (API 层)   │                  │  Queue   │                  │  (RQ)    │
└─────────────┘                  └─────────┘                  └──────────┘
                                                                   │
                                                    ┌──────────────┤
                                                    │              │
                                              Webhook 投递    Agent 生命周期
                                              HMAC 签名验证    模板同步
                                              重试 (指数退避)  状态刷新
```

### Worker 配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `RQ_REDIS_URL` | redis://localhost:6379/0 | Redis 连接 |
| `RQ_QUEUE_NAME` | default | 队列名 |
| `RQ_DISPATCH_THROTTLE_SECONDS` | 2.0 | 投递节流 |
| `RQ_DISPATCH_MAX_RETRIES` | 3 | 最大重试次数 |

## 10. 网关与Agent编排

### 网关架构

```
Mission Control (Backend)
        │
        │ WebSocket (wss://)
        │
        ▼
┌───────────────────┐
│  OpenClaw Gateway  │
│  (远程运行时环境)    │
│                    │
│  ├── Main Agent   │ ← 网关级控制 Agent
│  ├── Lead Agent   │ ← Board 主导 Agent (规划/编排)
│  └── Worker Agent │ ← Board 工作 Agent (执行任务)
└───────────────────┘
```

### Agent 生命周期

```
provisioning ──► active ──► idle ──► offline
     │              │         │
     │              ▼         │
     │          (heartbeat    │
     │           每30秒)      │
     │              │         │
     └──────── error ◄────────┘
```

### Agent 角色

| 角色 | 作用域 | 职责 |
|------|--------|------|
| **Main** | Gateway | 网关级控制, 模板管理, 会话管理 |
| **Lead** | Board | 任务规划, 置信度评估, 审批发起 |
| **Worker** | Board | 任务执行, 状态上报, 心跳 |

### 模板系统

Gateway 模板用 Jinja2 渲染，包含：
- `BOARD_AGENTS.md.j2` — Agent 清单
- `BOARD_BOOTSTRAP.md.j2` — Board 引导
- `BOARD_DELIVERY_STATUS.md.j2` — 交付状态
- `BOARD_HEARTBEAT.md.j2` — 心跳配置
- `BOARD_IDENTITY.md.j2` — Agent 身份
- `BOARD_MEMORY.md.j2` — 记忆上下文
- `BOARD_SOUL.md.j2` — Agent Soul 模板
- `BOARD_TOOLS.md.j2` — 可用工具
- `BOARD_USER.md.j2` — 用户上下文
