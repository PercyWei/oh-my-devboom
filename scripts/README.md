# 20261028_维护脚本

创建时间：20261028 18:13:39 Asia/Shanghai

最后修订时间：20261028 18:44:50 Asia/Shanghai

本目录用于检查和更新仓库中的固定版本，以及维护 Clash 镜像。需要 Bash 3.2+，以下命令均从**仓库根目录**执行。

[检查版本](#检查当前固定值与上游最新值) · [更新固定值](#更新仓库固定值) · [Clash 镜像](#维护-clash-镜像) · [验证与排错](#验证与排错)

| 脚本 | 主要职责 | 影响范围 |
| --- | --- | --- |
| [update-pins.sh](update-pins.sh) | 比较固定值与上游最新值；更新 Zellij、Powerlevel10k、Antidote 和默认插件 pin | 检查只读；更新写入对应仓库文件 |
| [update-clash.sh](update-clash.sh) | 同步源码镜像、发布组件归档、更新 Clash 固定值 | 会修改 GitHub/Gitee 镜像及相关仓库文件 |

两者都不升级当前已安装的工具，也不自动提交本地变更。日常环境更新由原包管理器或上游工具负责，用户的插件清单需自行同步。

## 检查当前固定值与上游最新值

```bash
# 检查全部固定仓库；省略 all 的 check 命令作用相同
bash scripts/update-pins.sh check all

# 只检查一个组件
bash scripts/update-pins.sh check zellij
bash scripts/update-pins.sh check powerlevel10k
bash scripts/update-pins.sh check clash

# 只检查默认清单中的一个插件
bash scripts/update-pins.sh check plugin zsh-users/zsh-syntax-highlighting
```

检查需要 Git、curl 和 jq，可在有未提交修改的工作区执行。它读取的是**当前仓库文件中的固定值**，不是机器上已安装的版本；不下载程序归档，不改写仓库或用户配置。

### 检查范围与“最新”的含义

| 检查对象 | 上游仓库 | 比较目标 |
| --- | --- | --- |
| Zellij | `zellij-org/zellij` | 官方最新稳定 Release |
| Antidote | `mattmc3/antidote` | 官方最新稳定 Release 及对应 commit |
| Powerlevel10k | `romkatv/powerlevel10k` | 默认分支 HEAD 的 commit |
| gitstatus | `romkatv/gitstatus` | 官方最新稳定 Release，仅供参考 |
| 默认插件 | [插件清单](../config/zsh/zsh_plugins.txt)中的仓库 | 各自默认分支 HEAD 的 commit |
| clashctl | `nelvko/clashctl` | 默认分支 HEAD 的 commit |
| Mihomo | `MetaCubeX/mihomo` | 官方最新稳定 Release |
| yq | `mikefarah/yq` | 官方最新稳定 Release |

目前默认清单有 5 个插件，因此 `check all` 共检查 12 个仓库。`check powerlevel10k` 同时展示主题和 gitstatus；`check clash` 展示 clashctl、Mihomo 和 yq。

Powerlevel10k 和插件采用默认分支作为明确的跟踪目标；Release 名称不一定反映这些仓库当前维护的代码。检查显示的 Git SHA 会缩短，比较时使用完整值。

gitstatus 的最新 Release 与主题要求的版本可能不同。真正更新时始终依据所选主题的 `gitstatus/install.info` 配套核对，不能根据单独的最新 Release 升级 gitstatus。

### 如何理解结果

| 状态 | 含义 |
| --- | --- |
| 相同 | 当前固定值与选定的上游目标一致 |
| 不同 | 两者不一致，需进一步审阅；不代表已经验证版本先后或兼容性 |
| 查询失败 | 无法取得或解析上游信息，本行不能用于判断是否需要更新 |
| 读取失败 | 无法从本地文件读取唯一的固定值，需检查模块或插件清单 |

批量检查遇到单个仓库失败后会继续检查其他仓库。读取和查询全部成功时退出码为 `0`，即使存在不同项；任一项失败时最终返回非零。

## 更新仓库固定值

更新需要 Git、curl、jq、tar 和 shasum。所有涉及的目标文件必须没有未提交修改，避免与当前编辑混写。

### 单项、批量与全部更新

更新必须显式使用 `update`。组件后可跟指定版本或 Git 引用，省略版本时按上表策略自动发现最新目标。多个组件按顺序列出，可以混用指定版本和自动发现：

```bash
# 单项：最新稳定 Release 或默认分支 HEAD
bash scripts/update-pins.sh update zellij

# 多项：均采用最新目标
bash scripts/update-pins.sh update zellij powerlevel10k

# 多项：Zellij 使用指定版本，Powerlevel10k 使用最新提交
bash scripts/update-pins.sh update zellij v0.45.1 powerlevel10k

# 插件也可以与其他工具一起更新
bash scripts/update-pins.sh update antidote v2.3.0 plugin zsh-users/zsh-syntax-highlighting 0.8.0

# 全部本地可直接维护的组件：采用最新目标，展示计划后统一确认
bash scripts/update-pins.sh update all
```

组件名 `zellij`、`powerlevel10k`、`antidote`、`plugin` 表示下一项开始；若 Git 分支恰好与组件或命令同名，使用完整引用，例如 `refs/heads/zellij`。

`update all` 包含 Zellij、Powerlevel10k、Antidote 和默认清单中的全部插件，gitstatus 随主题配套更新。Clash 的外部镜像发布仍使用 [update-clash.sh](update-clash.sh)，不包含在这个本地更新集合中。全部更新固定使用 `update all`，不能附加其他参数；要为不同组件指定版本，应显式列出各项。重复组件或重复插件会在查询上游前报错。

### 指定非最新版本

指定参数不要求等于上游最新值，也不强制比当前固定值更新，可用于逐步升级或回退。Zellij 和 Antidote 使用 `vX.Y.Z`，Powerlevel10k 和插件接受 commit、tag 或分支：

```bash
bash scripts/update-pins.sh update zellij v0.45.1
bash scripts/update-pins.sh update antidote v2.3.0
bash scripts/update-pins.sh update powerlevel10k master
bash scripts/update-pins.sh update plugin zsh-users/zsh-syntax-highlighting 0.8.0
```

示例值只说明参数格式；实际固定值以安装模块和插件清单为准。历史版本仍须符合安装器接口和校验要求，例如 Zellij 的目标必须是稳定 Release 且提供有效的官方资产摘要。

### 计划与确认

脚本先解析全部参数，检查所有目标文件，再逐项拉取来源、核对摘要和安装接口，在临时目录准备完整结果。任一项准备失败，都不会写入目标文件。

准备完成后统一列出各项的当前固定值、实际目标和变化状态；Powerlevel10k 还会列出主题要求的 gitstatus 版本。Git 引用已解析为真实 commit，确认后不会再次查询浮动分支来改变目标。

“内容变化”表示固定值相同，但摘要等组件文件内容不同；gitstatus 行标记为“随主题”，表示配套核对。

存在文件变化时提示 `是否写入以上更新？[y/N]`，输入 `y` 或 `yes` 才会写入，大小写均可。回车、其他回答或输入结束均取消并返回非零；内容全部相同时直接结束，无需确认。单项更新也采用相同流程。

### 校验与写入

| 命令 | 写入目标 | 写入前核对 |
| --- | --- | --- |
| `update zellij [TAG]` | [modules/tools.sh](../modules/tools.sh) | 稳定 Release、四个平台资产的官方摘要及归档成员 |
| `update powerlevel10k [REF]` | [modules/powerlevel10k.sh](../modules/powerlevel10k.sh) | 实际 commit、主题接口、配套 gitstatus 版本及四个平台归档 |
| `update antidote [TAG]` | [modules/antidote.sh](../modules/antidote.sh) | 稳定 tag 对应的实际 commit 和安装接口 |
| `update plugin OWNER/REPO [REF]` | [默认插件清单](../config/zsh/zsh_plugins.txt) | 清单中唯一存在的仓库及可检出的 commit |

Powerlevel10k、Antidote 和插件的 Git 引用都经过实际拉取、解析 `^{commit}` 并检出，annotated tag 会归一化为对应 commit。二进制按预期 SHA-256 下载核对，归档中须包含安装器要求的文件。Powerlevel10k 对应四个平台的 gitstatus 版本需一致，否则脚本会要求人工调整安装模块。

多个插件的变更累积到同一份临时清单。确认后再次核对所有目标文件没有并发修改，为变化的文件准备替换副本，再逐个原子替换并保留权限；内容相同的文件不写入。版本、提交和摘要继续保存在现有模块中，不额外维护状态文件。

每个文件的替换是原子的，多个文件不构成整批事务；写入期间发生磁盘故障或中断时，需检查 `git diff` 后继续维护。

### 更新后的操作

1. 审阅 `git diff` 和上游变更，核对安装接口、个人主题覆盖及相关文档。
2. 运行[本地检查](../README.md#本地检查与-ci)，在隔离环境验证安装和重复执行。
3. 提交确认后的变更。已部署环境按模块规则复用已有工具，不会因此自动升级。

默认插件清单更新后，需要手动同步 `${ZDOTDIR:-$HOME}/.zsh_plugins.txt` 中对应的 pin，再运行 `exec zsh`；脚本不会替换用户清单。

## 维护 Clash 镜像

Clash 的源码和二进制发布需要独立的镜像流程。`update-pins.sh check clash` 可只读查看上游差异；实际同步和发布使用 `update-clash.sh`。

### 前提条件

- Git、gh、官方 gitee CLI、jq、curl、shasum，以及解包所需的 tar。
- `gh` 登录 `PercyWei`，gitee CLI 登录 `back_door`。
- `source`、`packages` 要求 [modules/clash.sh](../modules/clash.sh)、根 [README.md](../README.md)、[config/default.conf](../config/default.conf) 没有未提交修改。

| 环境变量 | 用途 | 默认值 |
| --- | --- | --- |
| `GITEE_BIN` | gitee CLI 的可执行路径 | `gitee` |
| `CLASHCTL_REPO_DIR` | 本地镜像克隆目录 | 本项目同级的 `clashctl` |

### 命令与影响范围

| 命令 | 实际操作 |
| --- | --- |
| `sync` | 将上游 `nelvko/clashctl` 的 master 同步到 `PercyWei/clashctl`，再推送到 `back_door/clashctl`；不改变安装固定值 |
| `source COMMIT` | 先同步镜像，再核对已审阅的 40 位 commit 属于同步后的 master；检查安装接口，更新源码 pin 与归档摘要 |
| `packages MIHOMO_VERSION YQ_VERSION` | 核对官方资产摘要，创建或复用 Gitee Release，上传缺失附件并匿名下载比对，最后更新本地固定值；不先同步源码 |

```bash
bash scripts/update-clash.sh sync
bash scripts/update-clash.sh source e38d643725594c38c3fb02f355a2c89eba9c296c
bash scripts/update-clash.sh packages v1.19.33 v4.54.1
```

示例值只说明参数格式。Mihomo 使用 `vX.Y.Z`，yq 使用 `v4.X.Y`；源码提交应先审阅，再传入完整 commit。

已有 Release 和附件保留，相同内容复用；同名附件内容不同会报错，不覆盖。组件发布还包含摘要文件、许可文件及对应 Mihomo 源码。

`source`、`packages` 会更新安装模块及根 README 等既有说明文件，但不会自动改写本说明中的命令示例。执行后审阅全部差异，必要时同步文档。

## 验证与排错

- **检查显示不同**：先查看上游变更；它只表示固定值不同，不是自动升级决定。
- **查询失败**：检查 GitHub 网络访问和 API 限流信息。失败项会明确显示，批量检查仍继续处理剩余仓库。
- **目标文件有修改**：检查仍可运行；更新前需先提交或妥善保存对应文件的修改。
- **发布包缺少摘要或格式变化**：停止更新，核实上游发布和安装接口；不要用刚下载文件的自算摘要代替官方预期值。
- **出现部分本地更新**：批量更新和 Clash 维护可能涉及多个本地文件。写入期间失败后需审阅全部差异，脚本不负责整批回滚或提交。

这两个脚本的目标是维护仓库中的安装依据。安装方式、配置归属和用户环境更新规则见[项目 README](../README.md)。
