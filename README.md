# oh-my-devboom

轻量、模块化的个人开发环境初始化工具，适用于 Linux 服务器、Docker 容器和 macOS。

使用 Bash 编写，无需预装 Python 或 Node.js。支持按需安装、重复执行和配置备份，已有工具按规则复用，配置以普通文件部署。

## 快速开始

需要 Bash 3.2+ 和 Git。macOS 请先运行 `xcode-select --install`，完成 Command Line Tools 安装后再继续。

```bash
git clone https://github.com/PercyWei/oh-my-devboom.git
cd oh-my-devboom
cp config/default.conf config/local.conf
```

编辑 `config/local.conf`，选择需要的模块和工具。**Linux 默认启用 Clash**，首次运行前需在已有 `[clash]` 章节填写服务器本地 YAML 的绝对路径：

```ini
[clash]
config_file = /root/clash.yaml
```

不需要代理时，将 `[modules]` 中的 `clash` 改为 `false`；macOS 会自动跳过该模块。

```bash
bash bootstrap.sh --config config/local.conf
```

入口会检测环境、展示安装清单并请求确认，结束后汇总完成、跳过和失败项。请以实际使用环境的账户运行；通过 `sudo bash` 执行会配置 root 账户。

安装成功后，当前终端可运行 `exec zsh` 加载配置。Powerlevel10k 图标需要终端使用 Nerd Font v3 字体，例如 [MesloLGS NF](https://github.com/romkatv/powerlevel10k#fonts)。

## 安装内容

[默认配置](config/default.conf)启用以下全部模块及开发工具，可逐项关闭。

| 模块 | 内容 |
| --- | --- |
| `clash` | clashctl、Mihomo 和 yq；使用本地 YAML，在安装期间提供代理，仅支持 Linux |
| `base` | git、curl、wget、vim、unzip、zsh |
| `homebrew` | 安装或复用 Homebrew，并配置 PATH |
| `zsh` | Antidote、Oh My Zsh Git 插件、zsh-completions、zsh-autosuggestions、zsh-syntax-highlighting |
| `powerlevel10k` | Powerlevel10k 主题、gitstatusd 和个人主题预设 |
| `tools` | 下表中的开发工具 |
| `dotfiles` | 复制基础 Shell/Git 配置，按已就绪组件部署可选配置片段 |
| `shell` | 将当前账户的默认登录 Shell 设为 Zsh |

| 开发工具 | 用途 |
| --- | --- |
| uv | Python 环境与依赖管理 |
| fzf | 模糊查找、补全及 Ctrl-R / Ctrl-T / Alt-C 快捷键 |
| ripgrep（`rg`） | 搜索文件内容 |
| bat | 带语法高亮地查看文件 |
| eza | 增强文件列表，提供 `ll`、`la` 别名 |
| zoxide | 使用 `z`、`zi` 快速跳转目录 |
| Zellij（`zellij`） | 终端分屏、标签页与持久会话，别名 `zj` |
| NVTOP（`nvtop`） | GPU 利用率、显存和进程监控 |
| jq | JSON 筛选、转换与格式化 |
| fd | 按文件名、扩展名和类型查找文件 |
| GitHub CLI（`gh`） | 管理 GitHub 仓库、Issue 和 Pull Request |
| [ModelScope Hub](https://github.com/modelscope/modelscope_hub)（`modelscope-hub`） | 使用 `ms-hub` 下载、上传和管理模型及数据集 |
| [Hugging Face Hub](https://huggingface.co/docs/huggingface_hub/guides/cli)（`huggingface-hub`） | 使用 `hf` 管理 Hugging Face 模型、数据集和仓库 |

Linux 使用 `apt-get`、`dnf`、`yum`、`pacman`、`zypper` 或 `apk`，macOS 使用 Homebrew。root 跳过 Homebrew；Linux 容器不新装 Homebrew。系统包安装需要 root 或 sudo，权限不足或包不可用时会提示。

NVTOP 需要 GPU 驱动及设备访问权限，容器需暴露 GPU；macOS 仅支持 Apple GPU。Debian/Ubuntu 的 `batcat`、`fdfind` 会按需配置为 `bat`、`fd` 别名。

`gh` 通过现有软件源安装，使用前运行 `gh auth login` 登录 GitHub；升级可参考[官方安装说明](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)。

两个 Hub 工具通过 `uv tool install` 安装到隔离环境，命令放在 `~/.local/bin`；选择任一项会先安装或复用 uv。优先使用已有的 Python ≥3.10，缺失时由 uv 下载。项目中的 Python 代码仍需在自己的环境中声明和安装依赖。

按需使用 `ms-hub login`、`hf auth login` 登录；升级运行 `uv tool upgrade modelscope-hub huggingface-hub`。

## 按需安装

### 配置文件

默认读取 `config/default.conf`。建议复制为被 Git 忽略的 `config/local.conf`，通过 `--config` 显式加载。

| 章节 | 作用 |
| --- | --- |
| `[modules]` | 功能模块开关，使用 `true` / `false` |
| `[tools]` | 开发工具开关，仅在 `tools` 模块启用时生效 |
| `[clash]` | `config_file` 指定本地 YAML 的绝对路径 |
| `[options]` | 下载授权 `allow_remote`、冲突策略 `conflict`、GitHub 加速前缀 `github_proxy`、Git 超时 `git_timeout` |

指定配置文件会完整替代默认配置：未列出的模块和工具关闭；选项默认使用 `allow_remote=false`、`conflict=skip`、`github_proxy=`、`git_timeout=600`。值不加引号，不展开 `~` 或 `$HOME`；命令行参数优先于配置文件。

### 常用命令

```bash
# 非交互执行，并授权所选组件的上游下载
bash bootstrap.sh --config config/local.conf --non-interactive --allow-remote

# 仅安装 jq 和 fd
bash bootstrap.sh --non-interactive --modules tools --tools jq,fd

# 仅安装 GitHub CLI
bash bootstrap.sh --non-interactive --modules tools --tools gh

# 使用 uv 安装两个 Hub 工具；首次安装 uv 时需下载授权
bash bootstrap.sh --non-interactive --modules tools --tools modelscope-hub,huggingface-hub --allow-remote

# 选择全部模块和工具；Linux 仍需配置 Clash YAML
bash bootstrap.sh --config config/local.conf --modules all --tools all

# 查看完整参数和模块说明
bash bootstrap.sh --help
bash bootstrap.sh --list-modules
```

`--modules` 和 `--tools` 接受逗号分隔的名称或 `all`；`--tools` 需配合 `tools` 模块使用。

`--non-interactive` 仅关闭输入提示。直接上游下载需另外设置 `allow_remote=true` 或传入 `--allow-remote`，范围包括：clashctl 及 Mihomo/yq、Homebrew/uv 安装脚本、Antidote 和 Zsh 插件、Powerlevel10k/gitstatusd、Zellij 发布包。未授权时交互确认，非交互跳过；包管理器安装和本地配置部署不受此开关限制。

## 配置管理

配置复制到用户目录，安装后不依赖仓库位置，可直接编辑目标文件。`XDG_CONFIG_HOME` 默认是 `~/.config`；设置 `ZDOTDIR` 时，`.zshrc` 和 `.p10k.zsh` 跟随该目录。

| 配置 | 默认目标 |
| --- | --- |
| 基础 Zsh 配置 | `~/.zshrc` |
| 可选 Zsh 片段 | `~/.config/oh-my-devboom/zsh/` |
| Antidote 插件清单 | `~/.config/oh-my-devboom/zsh_plugins.txt` |
| Git 通用配置 | `~/.gitconfig` |
| Powerlevel10k 主题预设 | `~/.p10k.zsh` |

基础配置始终部署；可选片段按实际命令和安装文件是否就绪部署，支持接入已有工具。插件清单需已生成插件静态配置，主题预设需 Powerlevel10k 和 gitstatusd 就绪。单独重跑 `dotfiles` 不会因为本次未选择某个安装模块而删除它的配置。

基础 `.zshrc` 保留环境、历史记录、补全和固定加载顺序。工具配置位于 [config/zsh/modules/](config/zsh/modules/)，安装新工具后重跑 `dotfiles` 接入。修改插件清单后，重跑 `zsh` 模块生成静态配置；主题可直接修改 `.p10k.zsh` 或运行 `p10k configure`。

Antidote 通过 `use-omz` 加载 Oh My Zsh Git 插件及必要依赖，提供 `gst`（`git status`）、`gp`（`git push`）、`ga`（`git add`）等别名。Zellij 就绪时部署独立片段，使用 `zj` 启动。

部署规则：

- 目标不存在时复制，普通文件内容相同时跳过。
- 内容冲突时默认 `skip`，保留原配置；`backup` 先备份再替换，日志显示备份路径。
- 已有软链接指向普通文件时，优先转换为保留当前内容的普通文件，本次不替换为仓库预设；悬空链接或目录链接按冲突策略处理。

在仓库目录中执行：

```bash
# 保留当前配置，将已有文件软链接转换为普通文件
bash bootstrap.sh --non-interactive --modules dotfiles --conflict skip

# 备份冲突配置，再部署仓库预设
bash bootstrap.sh --non-interactive --modules dotfiles --conflict backup
```

已有 `.zshrc` 需按上述规则更新后才能加载模块片段。恢复备份时，将日志中的备份文件移回原位置。

已有环境更新 Git 插件和别名时，先部署配置，再生成插件静态文件：

```bash
bash bootstrap.sh --non-interactive --modules dotfiles --conflict backup
bash bootstrap.sh --non-interactive --modules zsh --allow-remote
exec zsh
```

需要 Clash 代理时，第二步改用 `--config config/local.conf --modules clash,zsh`。

个人 Git 身份单独保存在 `~/.gitconfig.local`：

```bash
git config --file "$HOME/.gitconfig.local" user.name "Your Name"
git config --file "$HOME/.gitconfig.local" user.email "you@example.com"
```

## 网络与代理

`clash` 使用 [nelvko/clashctl](https://github.com/nelvko/clashctl)，要求 Linux 和 Bash 4+，安装在 `${XDG_DATA_HOME:-$HOME/.local/share}/clashctl`，与 `oh-my-devboom` 数据目录同级。

clashctl 固定提交 `e38d643`，从 [Gitee 镜像](https://gitee.com/back_door/clashctl)直连下载；[组件发布包](https://gitee.com/back_door/clashctl/releases/tag/mihomo-v1.19.33-yq-v4.54.1)固定 Mihomo v1.19.33、yq v4.54.1，支持 Linux x86_64/aarch64。源码和安装包均校验 SHA-256，不依赖 `github_proxy`。

安装时使用已下载归档并跳过 GitHub 版本查询；系统依赖走发行版源，已有完整安装直接复用。

- 从服务器本地 YAML 导入配置；Clash 就绪并通过联网检查后，才继续后续安装。未就绪会停止安装。
- 代理启用后，本轮下载使用原始 GitHub URL，不再叠加 GitHub 加速前缀。
- 安装结束、报错退出或可捕获的中断时关闭该目录的 Clash 内核，保留程序与配置。

部署对应 Zsh 片段后，可手动使用：

```bash
clashctl on
clashctl off --stop
clashctl status
```

Clash 尚未启用时，GitHub 下载默认使用第三方加速前缀 `https://ghfast.top/`，可通过 `[options] github_proxy` 修改或置空直连。该前缀覆盖本项目直接发起的 GitHub 文件下载和 Git 请求（Git 加速需 Git 2.31+），不覆盖包管理器或上游安装器内部的下载。

uv 安装 Hub 工具需要访问 PyPI，缺少合适的 Python 时还需访问 GitHub；`github_proxy` 不改写 uv 内部的下载请求。

安装前会显示上游来源，源码固定提交与发布包校验见相应[安装模块](modules/)。Homebrew、uv 安装脚本随上游更新。

## 常见问题

**安装后仍是 Bash？**

先检查摘要中的 `zsh`、`powerlevel10k` 和 `dotfiles` 是否完成，再运行 `exec zsh`。`shell` 模块修改登录 Shell，重新登录后生效；容器平台若固定启动 `bash`，还需调整平台的终端启动命令。

**可以重复执行吗？如何更新？**

可以。已有工具按规则复用，不自动升级；工具升级使用原包管理器或上游提供的更新方式。更新仓库预设后重跑 `dotfiles`，配置冲突按 `skip/backup` 处理。

**fzf 已安装，但快捷键不可用？**

外部升级或更换 fzf 后，刷新集成脚本并接入配置：

```bash
bash bootstrap.sh --non-interactive --modules tools,dotfiles --tools fzf
```

旧 Debian/Ubuntu 的集成脚本从匹配版本的 APT 包提取；若仓库已不提供该版本，先升级 fzf。已有 `.zshrc` 仍按配置冲突规则处理。

**下载失败或安装有跳过项？**

查看摘要中的原因和重试命令。Git 任务默认限时 600 秒，可在 `[options] git_timeout` 调整；同时检查网络、加速前缀和下载授权。退出码为零也可能存在跳过项。保存完整日志可使用 `> install.log 2>&1`。

## 项目结构与开发

```text
bootstrap.sh     # 统一入口
modules/         # 按功能划分的安装模块
lib/             # 系统检测、下载、包管理与配置部署
config/          # 默认安装配置和程序配置
scripts/         # 镜像与固定版本维护
tests/run.sh     # 基础检查
```

基础检查使用临时 HOME 和模拟的包管理、下载命令，CI 配置覆盖 Ubuntu 与 macOS：

```bash
bash tests/run.sh
```

Clash 的完整安装流程、终端交互和 GPU 展示仍需在目标环境实机验证。

### 维护 Clash 镜像

需要 `git`、`gh`、官方 `gitee` CLI、`jq`、`curl` 和 `shasum`；`gh`、`gitee` 分别登录 `PercyWei`、`back_door`。可用 `GITEE_BIN` 指定 Gitee CLI 的绝对路径，`CLASHCTL_REPO_DIR` 指定本地克隆目录，默认使用仓库同级的 `clashctl`。

```bash
# 同步上游 master 到 PercyWei/clashctl 和 back_door/clashctl，不改安装固定版本
bash scripts/update-clash.sh sync

# 包含同步，更新指定提交及源码归档 SHA-256；安装器适配仍需人工审查
bash scripts/update-clash.sh source e38d643725594c38c3fb02f355a2c89eba9c296c

# 发布指定稳定版本的组件包
bash scripts/update-clash.sh packages v1.19.33 v4.54.1
```

`packages` 按官方 Release 提供的 SHA-256 摘要校验安装包，发布或复用 Gitee 附件，经匿名下载核对后更新本地固定版本、README 和默认配置。旧 Release 和附件保留，相同内容复用，不同内容报错，可重复执行。

`source`、`packages` 要求 `modules/clash.sh`、`README.md`、`config/default.conf` 无未提交改动。脚本不安装或升级服务器，也不提交本地变更。
