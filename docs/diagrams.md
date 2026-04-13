# 架构图与流程图

本文档包含 OpenClaw Mission Control 的所有 Mermaid 图表源代码。在支持 Mermaid 的 Markdown 渲染器中查看可自动渲染为图形。

---

## 1. 系统架构图

```mermaid
graph TB
    subgraph "前端 (Next.js)"
        Browser["浏览器"]
        FE["Frontend :3000<br/>Next.js 16 + React 19"]
    end

    subgraph "后端 (FastAPI)"
        BE["Backend :8000<br/>FastAPI + SQLModel"]
        Worker["Webhook Worker<br/>RQ 消费者"]
    end

    subgraph "数据层"
        PG["PostgreSQL :5432<br/>16-alpine"]
        Redis["Redis :6379<br/>7-alpine"]
    end

    subgraph "外部集成"
        GW["OpenClaw Gateway<br/>(WebSocket)"]
        Clerk["Clerk Auth<br/>(可选)"]
        GH["GitHub<br/>(Souls Directory)"]
    end

    Browser -->|HTTP :3000| FE
    FE -->|HTTP / SSE :8000| BE
    BE --> PG
    BE --> Redis
    Redis --> Worker
    Worker --> PG
    BE <-->|WebSocket| GW
    BE -.->|JWT 验证| Clerk
    BE -.->|Sitemap 获取| GH
```

## 2. 数据模型 ER 图

```mermaid
erDiagram
    Organization ||--o{ Board : has
    Organization ||--o{ BoardGroup : has
    Organization ||--o{ Gateway : has
    Organization ||--o{ OrganizationMember : has
    Organization ||--o{ OrganizationInvite : has
    Organization ||--o{ Tag : has
    Organization ||--o{ MarketplaceSkill : has
    Organization ||--o{ SkillPack : has
    Organization ||--o{ TaskCustomFieldDefinition : has

    BoardGroup ||--o{ Board : contains
    BoardGroup ||--o{ BoardGroupMemory : has

    Board ||--o{ Task : has
    Board ||--o{ Agent : has
    Board ||--o{ Approval : has
    Board ||--o{ BoardMemory : has
    Board ||--o{ BoardWebhook : has
    Board ||--o{ BoardOnboardingSession : has
    Board ||--o{ TaskDependency : has
    Board ||--o{ TaskFingerprint : has
    Board ||--o{ BoardTaskCustomField : has

    Gateway ||--o{ Agent : deploys
    Gateway ||--o{ Board : serves
    Gateway ||--o{ GatewayInstalledSkill : has

    Agent ||--o{ Task : assigned
    Agent ||--o{ Approval : creates
    Agent ||--o{ ActivityEvent : generates

    Task ||--o{ TagAssignment : tagged
    Task ||--o{ TaskDependency : depends
    Task ||--o{ TaskCustomFieldValue : has
    Task ||--o{ ApprovalTaskLink : linked

    Approval ||--o{ ApprovalTaskLink : links
    Tag ||--o{ TagAssignment : used
    MarketplaceSkill ||--o{ GatewayInstalledSkill : installed

    OrganizationMember ||--o{ OrganizationBoardAccess : has
    OrganizationInvite ||--o{ OrganizationInviteBoardAccess : has
    User ||--o{ OrganizationMember : belongs
    TaskCustomFieldDefinition ||--o{ BoardTaskCustomField : enabled
    TaskCustomFieldDefinition ||--o{ TaskCustomFieldValue : valued

    BoardWebhook ||--o{ BoardWebhookPayload : receives
```

## 3. 请求处理流程

```mermaid
flowchart TD
    A[HTTP 请求] --> B{CORS 中间件}
    B --> C{Security Headers}
    C --> D[路由匹配]
    D --> E{认证类型?}

    E -->|Bearer Token| F[get_auth_context<br/>用户认证]
    E -->|X-Agent-Token| G[get_agent_auth_context<br/>Agent 认证]

    F --> H{角色检查}
    G --> I{作用域检查}

    H -->|Admin| J[require_org_admin]
    H -->|Member| K[require_org_member]
    I --> L[Agent Board 作用域验证]

    J --> M{资源解析}
    K --> M
    L --> M

    M --> N[Board / Task 访问控制]
    N --> O[Service 层调用]
    O --> P[record_activity 审计]
    P --> Q[session.commit]
    Q --> R[Pydantic 序列化]
    R --> S[JSON 响应]
```

## 4. 认证流程图

```mermaid
flowchart TD
    A[用户访问前端] --> B{AUTH_MODE?}

    B -->|local| C[显示 LocalAuthLogin]
    B -->|clerk| D[显示 Clerk SignIn]

    C --> E[用户输入 Token]
    E --> F[存入 sessionStorage]
    F --> G[Authorization: Bearer token]

    D --> H[Clerk JWT 流程]
    H --> I[Clerk Session Token]
    I --> G

    G --> J[POST /api/v1/auth/bootstrap]
    J --> K{验证成功?}

    K -->|是| L[返回 UserRead]
    K -->|否| M[401 Unauthorized]

    L --> N[自动创建 Org<br/>如果首次登录]
    N --> O[跳转到 Dashboard]
```

## 5. 任务状态流转图

```mermaid
stateDiagram-v2
    [*] --> inbox : 创建任务

    inbox --> in_progress : 开始工作
    in_progress --> inbox : 退回

    in_progress --> review : 提交审查
    review --> in_progress : 需要修改

    review --> done : 完成
    done --> review : 重新开启

    state review {
        [*] --> checking_approval
        checking_approval --> waiting_approval : require_approval=true
        checking_approval --> can_complete : require_approval=false
        waiting_approval --> can_complete : 审批通过
    }

    note right of inbox : 新任务入口
    note right of in_progress : Agent 执行中
    note right of review : 评审阶段
    note right of done : 已完成
```

## 6. 审批工作流

```mermaid
flowchart TD
    A[Agent 执行任务] --> B{需要审批?}

    B -->|confidence < threshold| C[创建 Approval]
    B -->|is_external or is_risky| C
    B -->|confidence >= threshold| D[自动通过]

    C --> E[Approval status: pending]

    E --> F{关联任务}
    F --> G[ApprovalTaskLink N:M]

    G --> H{审批决定?}

    H -->|approved| I[关联任务可 → done]
    H -->|rejected| J[任务状态不变]
    H -->|cancelled| K[审批取消]

    I --> L[通知 Gateway]
    J --> L
```

## 7. Agent 生命周期

```mermaid
stateDiagram-v2
    [*] --> provisioning : 创建 Agent

    provisioning --> active : Gateway 确认
    provisioning --> error : 配置失败

    active --> active : heartbeat (30s)
    active --> idle : 心跳超时
    active --> error : 异常

    idle --> active : 恢复心跳
    idle --> offline : 长时间无响应

    offline --> provisioning : 重新配置
    error --> provisioning : 重试

    note right of provisioning : Gateway 正在配置
    note right of active : 正常运行, 每30s心跳
    note right of idle : 暂时无响应
    note right of offline : 完全失联
    note right of error : 需要干预
```

## 8. Webhook 处理流程

```mermaid
sequenceDiagram
    participant Ext as 外部系统
    participant API as Backend API
    participant DB as PostgreSQL
    participant Q as Redis Queue
    participant W as Worker

    Ext->>API: POST /webhooks/{id}
    API->>API: 验证 HMAC 签名
    API->>API: 解析 Payload (JSON/Form/Text)
    API->>DB: 保存 WebhookPayload
    API->>Q: 入队异步处理
    API-->>Ext: 200 OK

    W->>Q: 消费任务
    W->>DB: 查询关联 Agent
    W->>W: 投递给 Agent
    W->>DB: 更新处理状态
```

## 9. Board 引导流程

```mermaid
sequenceDiagram
    participant U as 用户
    participant FE as 前端
    participant BE as 后端
    participant GW as Gateway

    U->>FE: 点击 "开始引导"
    FE->>BE: POST /onboarding/start
    BE-->>FE: 返回首个问题

    loop 对话轮次
        U->>FE: 回答问题
        FE->>BE: POST /onboarding/answer
        BE-->>FE: 返回下一个问题/建议
    end

    FE->>BE: GET /onboarding/lead-agent-draft
    BE-->>FE: Lead Agent 配置草案

    U->>FE: 确认配置
    FE->>BE: POST /onboarding/confirm
    BE->>BE: 设置 Board 目标
    BE->>BE: 创建 Lead Agent
    BE->>GW: 预配置 Agent

    GW-->>BE: Agent 就绪
    BE->>BE: POST /onboarding/lead-agent-complete
    BE-->>FE: 引导完成
```

## 10. SSE 实时推送架构

```mermaid
flowchart LR
    subgraph "前端 (Activity Page)"
        C1[Board 1 Task Stream]
        C2[Board 1 Approval Stream]
        C3[Board 1 Memory Stream]
        C4[Board 2 Task Stream]
        C5[Agent Stream]
        Merge[事件聚合<br/>去重 + 排序<br/>最大 300 条]
        UI[Activity Feed UI]
    end

    subgraph "后端 SSE 端点"
        S1[/tasks/stream]
        S2[/approvals/stream]
        S3[/memory/stream]
        S4[/agents/stream]
    end

    subgraph "数据库轮询"
        DB[(PostgreSQL)]
    end

    DB --> S1
    DB --> S2
    DB --> S3
    DB --> S4

    S1 -->|SSE| C1
    S2 -->|SSE| C2
    S3 -->|SSE| C3
    S1 -->|SSE| C4
    S4 -->|SSE| C5

    C1 --> Merge
    C2 --> Merge
    C3 --> Merge
    C4 --> Merge
    C5 --> Merge
    Merge --> UI
```

## 11. 多租户访问控制

```mermaid
flowchart TD
    A[请求进入] --> B{获取 Actor}

    B -->|User| C[解析 active_organization]
    B -->|Agent| D[从 Agent.board_id 推导]

    C --> E[检查 OrganizationMember]
    E --> F{all_boards_read/write?}

    F -->|是| G[访问所有 Board]
    F -->|否| H[查询 OrganizationBoardAccess]

    H --> I{目标 Board 有权限?}
    I -->|can_read=true| J[允许读操作]
    I -->|can_write=true| K[允许写操作]
    I -->|无记录| L[403 Forbidden]

    D --> M{Agent 属于目标 Board?}
    M -->|是| N[允许 Board 作用域操作]
    M -->|否| O{是 Main Agent?}
    O -->|是| P[允许 Gateway 级操作]
    O -->|否| L
```

## 12. 网关与Agent编排

```mermaid
flowchart TB
    subgraph "Mission Control"
        MC[Backend API]
        DB[(PostgreSQL)]
    end

    subgraph "Gateway Runtime"
        GW[Gateway Server]
        Main[Main Agent<br/>网关级控制]
        subgraph "Board A"
            LeadA[Lead Agent<br/>规划/编排]
            WorkerA1[Worker Agent 1]
            WorkerA2[Worker Agent 2]
        end
        subgraph "Board B"
            LeadB[Lead Agent]
            WorkerB1[Worker Agent 1]
        end
    end

    MC <-->|WebSocket| GW
    MC --> DB

    GW --> Main
    Main --> LeadA
    Main --> LeadB
    LeadA --> WorkerA1
    LeadA --> WorkerA2
    LeadB --> WorkerB1

    WorkerA1 -->|heartbeat :8000| MC
    WorkerA2 -->|heartbeat :8000| MC
    WorkerB1 -->|heartbeat :8000| MC
    LeadA -->|approval :8000| MC
    LeadB -->|approval :8000| MC
```
