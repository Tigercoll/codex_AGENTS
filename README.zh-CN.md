# codex_AGENTS

[English README](./README.md)

这是一个用于维护 Codex 全局 Agent 规则的仓库，同时也包含一套本地同步工具，用来镜像并映射 [`agency-agents`](https://github.com/msitarzewski/agency-agents) 专家角色模板。

## 仓库内容

- `AGENTS.md` - 全局执行策略的英文主版本
- `agents-ch.md` - 与 `AGENTS.md` 同步维护的中文镜像
- `tools/agency-sync/` - 跨平台同步脚本与共享角色配置

## 目录结构

```text
.
|-- AGENTS.md
|-- agents-ch.md
|-- README.md
|-- README.zh-CN.md
`-- tools/
    `-- agency-sync/
        |-- agency-agent-profiles.json
        |-- sync-agency-agents.ps1
        |-- sync-agency-agents.sh
        |-- sync-agency-agents
        `-- sync-agency-agents.cmd
```

## 同步工具做什么

这套工具会从 `msitarzewski/agency-agents` 拉取角色模板，把它们安装到固定本地目录，并生成一份专家映射表。主线程在委派专家角色前，应先查询这份映射表，而不是临时随意选择模板。

默认输出位置：

- 角色模板目录：
  - Windows: `C:\Users\<you>\.codex\agents\agency-agents\`
  - Linux/macOS: `~/.codex/agents/agency-agents/`
- 机器可读映射表：
  - Windows: `C:\Users\<you>\.codex\agents\agency-agent-map.json`
  - Linux/macOS: `~/.codex/agents/agency-agent-map.json`
- 人工可读索引：
  - Windows: `C:\Users\<you>\.codex\agents\agency-agent-map.md`
  - Linux/macOS: `~/.codex/agents/agency-agent-map.md`

## 为什么要这样做

这个仓库配套的是一套以编排为核心的全局工作模型：

- 主线程负责总控、分配、监督与最终集成
- 非简单任务默认先走规划线程
- 专家委派应先通过映射表解析
- 角色模板固定落在统一目录，便于复用和维护
- 允许受控二级委派，但不能无限向下扩散

## 使用方式

### Windows PowerShell

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\agency-sync\sync-agency-agents.ps1
```

### Windows CMD

```bat
tools\agency-sync\sync-agency-agents.cmd
```

### Linux / macOS

```bash
bash ./tools/agency-sync/sync-agency-agents.sh
```

### 统一启动器（类 Unix shell）

```bash
./tools/agency-sync/sync-agency-agents
```

## 常用覆盖参数

所有同步入口都支持同一组核心覆盖参数：

- 仓库地址
- 分支名
- 源镜像目录
- 安装目录
- JSON 映射表路径
- Markdown 索引路径
- 共享 profiles 配置路径

示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\agency-sync\sync-agency-agents.ps1 `
  -RepoUrl "https://github.com/msitarzewski/agency-agents.git" `
  -Branch "main"
```

```bash
bash ./tools/agency-sync/sync-agency-agents.sh \
  --repo-url "https://github.com/msitarzewski/agency-agents.git" \
  --branch "main"
```

## 说明

- `agency-agent-profiles.json` 是类别目录和自动路由角色映射的共享配置源。
- PowerShell 版本与 shell 版本应尽量保持行为一致。
- 这些脚本在本仓库中进行版本管理，但实际运行时也可以复制到本地 `.codex/bin` 目录中使用。

## 维护规则

如果全局编排策略发生变化，至少要在同一批改动中同步更新：

- `AGENTS.md`
- `agents-ch.md`

避免中英文策略漂移。
