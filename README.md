# oh-my-devboom

面向 Linux 服务器、Docker 容器和 macOS 的个人开发环境初始化工具。

使用 Bash 编写，无需预装 Python 或 Node.js。支持按需安装、重复执行和配置备份；配置以普通文件部署，安装后可独立于源码仓库使用。

[快速开始](#快速开始) · [安装内容](#安装内容) · [按需安装](#按需安装) · [配置与更新](#配置与更新) · [网络与代理](#网络与代理) · [常见问题](#常见问题) · [项目维护](#项目维护)

## 快速开始

需要 **Bash 3.2+ 和 Git**。macOS 请先运行 `xcode-select --install`，完成 Command Line Tools 安装。

**1. 获取仓库，准备个人安装配置。**

```bash
git clone https://github.com/PercyWei/oh-my-devboom.git
cd oh-my-devboom
cp config/default.conf config/local.conf
```

编辑 `config/local.conf`，选择需要的模块和工具。该文件已被 Git 忽略。

> **Linux 默认启用 Clash。** 在已有 `[clash]` 章节填写本地 YAML 的绝对路径；代理未就绪时，后续安装会停止。不需要安装期间代理时，将 `[modules]` 中的 `clash` 改为 `false`。macOS 自动跳过该模块。

```ini
[clash]
config_file = /root/clash.yaml
```

**2. 运行安装，查看结果摘要。**

```bash
bash bootstrap.sh --config config/local.conf
```

入口会检测环境、展示安装清单并请求确认，结束后汇总完成、跳过和失败项。退出码为 `0` 时仍可能有未完成项，请查看摘要。

请以实际使用环境的账户运行；`sudo bash bootstrap.sh` 会配置 root 账户。

**3. 加载 Zsh 配置。**

```bash
exec zsh
```

`shell` 模块修改的默认登录 Shell 在重新登录后生效。Powerlevel10k 图标需要终端使用 Nerd Font v3，例如 [MesloLGS NF](https://github.com/romkatv/powerlevel10k#fonts)。

## 安装内容

[默认配置](config/default.conf)启用以下全部模块和工具，可逐项关闭。

| 模块 | 职责 |
| --- | --- |
| `clash` | 安装或复用 clashctl、Mihomo 和 yq，在 Linux 安装期间提供代理 |
| `base` | 安装 git、curl、wget、vim、unzip、zsh |
| `homebrew` | 安装或复用 Homebrew，准备命令搜索路径 |
| `antidote` | 安装插件管理器，初始化清单并预下载插件 |
| `powerlevel10k` | 安装主题和配套 gitstatusd |
| `tools` | 安装所选开发工具 |
| `dotfiles` | 部署所选 Shell/Git 配置及已就绪组件的接入片段 |
| `shell` | 将当前账户的默认登录 Shell 设为 Zsh |

| 工具选择名 | 命令 | 用途 |
| --- | --- | --- |
| `uv` | `uv` | Python 环境与依赖管理 |
| `fzf` | `fzf` | 模糊查找、补全及 Ctrl-R / Ctrl-T / Alt-C 快捷键 |
| `rg` | `rg` | ripgrep 内容搜索 |
| `bat` | `bat` | 文件预览与语法高亮 |
| `eza` | `eza`、`ll`、`la` | 增强文件列表 |
| `tree` | `tree` | 树状显示目录结构 |
| `zoxide` | `zoxide`、`z`、`zi` | 按使用记录跳转目录 |
| `zellij` | `zellij`、`zj` | 终端分屏、标签页与持久会话 |
| `nvtop` | `nvtop` | GPU 监控，需驱动和设备访问权限 |
| `jq` | `jq` | JSON 筛选与转换 |
| `fd` | `fd` | 按文件名、类型等查找文件 |
| `gh` | `gh` | GitHub 仓库、Issue 和 Pull Request 管理 |
| [`modelscope-hub`](https://github.com/modelscope/modelscope_hub) | `ms-hub`、`modelscope` | ModelScope 模型、数据集等 Hub 资源管理 |
| [`huggingface-hub`](https://huggingface.co/docs/huggingface_hub/guides/cli) | `hf` | Hugging Face 模型、数据集和仓库管理 |

工具的别名、补全和快捷键由 `dotfiles` 接入。Debian/Ubuntu 的 `batcat`、`fdfind` 会按需提供为 `bat`、`fd` 别名。NVTOP 在容器中需要暴露 GPU，macOS 仅支持 Apple GPU。

| 环境 | 软件来源与条件 |
| --- | --- |
| Linux | 支持 `apt-get`、`dnf`、`yum`、`pacman`、`zypper`、`apk`；系统包安装需要 root 或 sudo |
| macOS | 使用 Homebrew；需要普通用户和 Command Line Tools |

root 跳过 Homebrew，Linux 容器不新装 Homebrew。安装和 Zsh 初始化都优先使用 PATH 中的 `brew`，未找到时再搜索标准目录；uv、Zellij 的具体下载方式由安装模块选择。

系统包安装后逐项确认命令路径；未找到命令时报告失败。直接下载的 Zellij 在部署前执行 `--version`，确认二进制可以运行。

### Hub 工具

两个 Hub 工具通过 `uv tool install` 安装到隔离环境，命令位于 `~/.local/bin`。选择任一项会自动补齐 uv；优先复用 Python ≥3.10，缺失时由 uv 下载。Python 项目使用的 SDK 仍需在项目环境中声明和安装。

完成 `dotfiles` 部署并运行 `exec zsh` 后，再按需登录：

```bash
ms-hub login
hf auth login
```

Hub 工具升级使用 `uv tool upgrade modelscope-hub huggingface-hub`。GitHub CLI 使用前运行 `gh auth login`，升级使用原包管理器，安装来源见[官方说明](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)。

## 按需安装

### 选择模块、工具和配置

| 参数 | 选择对象 | 使用条件 |
| --- | --- | --- |
| `--modules LIST` | 功能模块 | 覆盖配置文件中的模块选择 |
| `--tools LIST` | 开发工具 | 配合 `tools` 模块使用 |
| `--dotfiles LIST` | 配置组件 | 必须启用 `dotfiles` 模块，默认选择全部组件 |

三个参数都接受逗号分隔的名称或 `all`。工具安装与配置部署分别选择；`dotfiles` 可接入已安装的工具。

```bash
# 仅安装 jq 和 fd
bash bootstrap.sh --non-interactive --modules tools --tools jq,fd

# 安装两个 Hub 工具并接入配置
bash bootstrap.sh --non-interactive --modules tools,dotfiles --tools modelscope-hub,huggingface-hub --allow-remote

# 按个人配置非交互安装，并授权所选组件的上游下载
bash bootstrap.sh --config config/local.conf --non-interactive --allow-remote
```

Hub 示例要求已安装 Zsh；全新环境可将模块列表改为 `base,tools,dotfiles`。已有 `.zshrc` 需按冲突策略更新，才能加载对应片段。

> `--non-interactive` 仅关闭输入提示，**不代表授权远程下载**。直接上游下载需设置 `allow_remote=true` 或传入 `--allow-remote`；未授权时交互确认，非交互跳过。包管理器安装、本地配置部署和已有组件复用不受此限制。Linux 启用 Clash 时，代理未就绪仍会停止后续安装。

授权范围包括 clashctl 及 Mihomo/yq、Homebrew/uv 安装器、Antidote 及插件清单中的插件、Powerlevel10k/gitstatusd、Zellij 发布包。安装前会展示具体来源。

### 安装配置文件

默认读取 `config/default.conf`，个人配置通过 `--config` 显式加载。

| 章节 | 内容 |
| --- | --- |
| `[modules]` | 模块开关，使用 `true` / `false` |
| `[tools]` | 工具开关，仅在 `tools` 模块启用时生效 |
| `[clash]` | `config_file`：可读本地 YAML 的绝对路径 |
| `[options]` | 下载授权、冲突策略、GitHub 加速前缀、Git 下载超时 |

指定配置文件会完整替代默认配置，未列出的模块和工具关闭。省略的选项使用 `allow_remote=false`、`conflict=skip`、`github_proxy=`、`git_timeout=600`。值不加引号，不展开 `~` 或 `$HOME`；命令行参数优先于配置文件。

完整参数和模块说明：

```bash
bash bootstrap.sh --help
bash bootstrap.sh --list-modules
```

## 配置与更新

### 文件归属与定向更新

配置以普通文件复制到用户目录，安装后不依赖仓库位置。

| 配置 | 默认路径 | 更新方式 |
| --- | --- | --- |
| 基础 Zsh 配置 | `~/.zshrc` | 按 `skip` / `backup` 部署 |
| 工具接入片段 | `~/.config/oh-my-devboom/zsh/` | 选中且组件就绪时部署 |
| 个人 Zsh 覆盖 | `~/.zshrc.local` | 用户自行创建和维护 |
| Antidote 插件清单 | `~/.zsh_plugins.txt` | 缺失时初始化，已有内容保留 |
| Git 通用配置 | `~/.gitconfig` | 按 `skip` / `backup` 部署 |
| Git 个人配置 | `~/.gitconfig.local` | 用户自行创建和维护 |
| Powerlevel10k 个人配置 | `~/.p10k.zsh` | 缺失时初始化，已有内容保留 |

设置 `ZDOTDIR` 时，`.zshrc`、`.zshrc.local`、`.zsh_plugins.txt` 和 `.p10k.zsh` 跟随该目录。

```bash
# 只更新两个工具的接入片段
bash bootstrap.sh --non-interactive --modules dotfiles --dotfiles homebrew,huggingface-hub --conflict backup

# 更新全部已就绪组件的项目配置
bash bootstrap.sh --non-interactive --modules dotfiles --conflict backup
```

可选配置组件：`zshrc`、`git`、`homebrew`、`clash`、`eza`、`bat`、`fd`、`zellij`、`huggingface-hub`、`fzf`、`zoxide`、`antidote`、`powerlevel10k`。其中 `antidote` 包含插件清单初始化和加载片段，`powerlevel10k` 包含个人配置初始化、即时提示和主题加载片段。

已有 `.zshrc` 需要同步加载顺序时，将 `zshrc` 一并选中。

项目配置的冲突处理如下：

| 目标状态 | 处理方式 |
| --- | --- |
| 不存在 | 复制配置 |
| 普通文件内容相同 | 跳过，不产生备份 |
| 内容冲突，`skip` | 保留现有文件 |
| 内容冲突，`backup` | 备份后替换，摘要显示备份路径 |
| 软链接指向普通文件 | 保留当前内容并转换为普通文件，本次不替换为仓库预设 |
| 悬空链接或目录链接 | 按冲突策略处理 |

个人 `.zsh_plugins.txt`、`.p10k.zsh` 只在缺失且组件就绪时初始化，`backup` 也保留已有内容。有效文件软链接会转换为保留内容的普通文件，其他现有路径保持不变。

`dotfiles` 不自动删除已有片段；卸载工具后需自行删除对应片段。恢复配置备份时，将摘要中列出的备份文件移回原位置。

### 个人设置与插件

个人 alias 和环境变量写入 `${ZDOTDIR:-$HOME}/.zshrc.local`，在全部工具与主题配置之后加载。影响工具初始化的路径参数应提前设置，例如放在 `.zshenv` 中。

Git 身份写入个人配置：

```bash
git config --file "$HOME/.gitconfig.local" user.name "Your Name"
git config --file "$HOME/.gitconfig.local" user.email "you@example.com"
```

Powerlevel10k 先加载固定主题自带的 lean 模板，再加载个人 `.p10k.zsh`。`p10k configure` 会写入该用户文件；如需采用[仓库的精简预设](config/powerlevel10k/p10k.zsh)，请先手动备份个人文件，再复制到用户配置位置。

Antidote 的[默认清单](config/zsh/zsh_plugins.txt)包含 use-omz、Oh My Zsh Git、补全、自动建议和语法高亮插件。Git 插件提供 `gst`、`gp`、`ga` 等别名。编辑用户 `.zsh_plugins.txt` 后运行 `exec zsh`，Antidote 会按需重建静态加载脚本。

更新未锁定的插件：

```bash
antidote update --bundles
exec zsh
```

带 `pin` 的插件会被更新命令跳过。需要采用仓库的新固定提交时，手动同步用户清单中对应的 `pin`，再运行 `exec zsh`。

<details>
<summary>目录与缓存：哪些文件需要长期保留？</summary>

| 变量 | 默认目录 | 用途 |
| --- | --- | --- |
| `XDG_CONFIG_HOME` | `~/.config` | 工具接入配置 |
| `XDG_DATA_HOME` | `~/.local/share` | 程序资源和长期数据 |
| `XDG_CACHE_HOME` | `~/.cache` | 可重建缓存、下载副本和安装临时文件 |

`$XDG_DATA_HOME/oh-my-devboom/` 保存 Antidote、插件、主题、gitstatusd、fzf 集成脚本和 Shell 历史；同级 `clashctl/` 保存代理程序与配置。`GITSTATUS_CACHE_DIR` 是上游变量名，在本项目中指向数据目录中的 `oh-my-devboom/gitstatus/`；gitstatusd 由 bootstrap 准备，Zsh 启动时不自动补装。

检测到 `hf` 时部署的片段将凭据默认放在 `$XDG_DATA_HOME/huggingface/`，包括 `token` 和 `stored_tokens`。显式 `HF_TOKEN_PATH` 优先，其次沿用显式 `HF_HOME`；模型和其他下载缓存保持上游配置。该设置对加载片段后启动的 CLI/Python 进程生效，见[环境变量说明](https://huggingface.co/docs/huggingface_hub/package_reference/environment_variables)和[认证文件路径定义](https://github.com/huggingface/huggingface_hub/blob/main/src/huggingface_hub/constants.py)。ModelScope 凭据默认位于 `~/.modelscope/credentials/`，见[官方配置说明](https://github.com/modelscope/modelscope_hub#configuration)。

本项目的 `oh-my-devboom/zcompdump`、`oh-my-devboom/plugins.zsh` 和 `p10k-instant-prompt-*.zsh` 可在后续 Zsh 启动时重建。`oh-my-devboom/installer.*` 是安装器副本；Clash、Zellij 的下载解压目录及代理环境交接文件仅在安装期间使用。可清理安装结束后的残留，安装进行中请保留。

**Zellij 的会话和授权记录需要单独保留。** 本项目保留上游行为，固定版本 v0.45.1 的会话恢复数据位于：

| 平台 | 会话恢复目录 |
| --- | --- |
| Linux | `${XDG_CACHE_HOME:-$HOME/.cache}/zellij/contract_version_1/session_info/` |
| macOS | `~/Library/Caches/org.Zellij-Contributors.Zellij/contract_version_1/session_info/` |

同一缓存根目录的 `permissions.kdl` 保存插件授权记录。删除会话数据会失去对应恢复记录，删除授权记录后需重新授权。详见[会话恢复说明](https://zellij.dev/documentation/session-resurrection.html)和[固定版本路径定义](https://github.com/zellij-org/zellij/blob/v0.45.1/zellij-utils/src/consts.rs)。

</details>

<details>
<summary>已有环境迁移：模块名、插件加载及数据目录</summary>

**旧模块名。** 将个人安装配置中 `[modules]` 下的 `zsh` 或 `zsh_plugins` 改为 `antidote`。

**切换到 Antidote 原生加载。** 更新基础配置与相关片段，再重启 Zsh；用户插件清单会保留。

```bash
bash bootstrap.sh --non-interactive --modules dotfiles --dotfiles zshrc,antidote,fzf,zoxide --conflict backup
exec zsh
```

**gitstatusd 目录。** 若已有程序位于缓存目录，重新安装到数据目录并更新加载配置：

```bash
bash bootstrap.sh --non-interactive --modules powerlevel10k,dotfiles --dotfiles zshrc,powerlevel10k --allow-remote --conflict backup
exec zsh
```

确认正常后，可自行删除旧的 `${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-devboom/gitstatus/`。个人 `.p10k.zsh` 会保留。

**Hugging Face 凭据目录。** 确认 `hf` 可用，更新配置并重新登录：

```bash
bash bootstrap.sh --non-interactive --modules dotfiles --dotfiles zshrc,huggingface-hub --conflict backup
exec zsh
hf auth login
```

需要保留多个已保存凭据时，将旧目录的 `token`、`stored_tokens` 一起迁移到新目录并保留原权限。确认认证正常后再清理旧副本。

</details>

## 网络与代理

Linux Clash 模块使用 [clashctl](https://github.com/nelvko/clashctl)，要求 Bash 4+，安装在 `${XDG_DATA_HOME:-$HOME/.local/share}/clashctl`。

安装期间的流程为：**导入本地 YAML → 启动代理并检查联网 → 执行后续安装 → 关闭内核**。报错退出或可捕获的中断也会触发关闭，程序与配置保留。

部署 Clash 配置片段后，可手动使用：

```bash
clashctl on
clashctl off --stop
clashctl status
```

| 下载对象 | 来源与固定方式 |
| --- | --- |
| clashctl 源码 | [Gitee 镜像](https://gitee.com/back_door/clashctl)，固定提交 `e38d643`，校验 SHA-256 |
| Mihomo / yq | [Gitee 组件发布包](https://gitee.com/back_door/clashctl/releases/tag/mihomo-v1.19.33-yq-v4.54.1)，固定 v1.19.33 / v4.54.1，校验 SHA-256；支持 Linux x86_64/aarch64 |
| Antidote、默认插件、主题和直接下载的发布包 | 固定提交或版本，具体值见[安装模块](modules/)和[插件清单](config/zsh/zsh_plugins.txt) |
| Homebrew / uv 安装器 | 随上游更新，执行前展示来源和下载脚本路径 |

已有完整 clashctl 安装会复用；首次安装使用已校验归档并跳过 GitHub 版本查询，系统依赖仍走发行版源。

Clash 启用前，项目直接发起的 GitHub 文件下载和 Git 请求默认使用 `https://ghfast.top/`，可通过 `[options] github_proxy` 修改或置空；Git 加速需要 Git 2.31+。Clash 就绪后，本轮停用该加速前缀。

包管理器、上游安装器和 uv 内部下载不受该前缀改写。Hub 工具需要访问 PyPI，缺少 Python 时还可能需要访问 GitHub。日常 Antidote 下载与更新使用当时的网络环境；安装配置中的 `github_proxy`、`git_timeout` 和下载授权仅作用于 bootstrap。

## 常见问题

<details>
<summary>安装后为什么仍然是 Bash？</summary>

当前终端需要运行 `exec zsh`。默认登录 Shell 的变更在重新登录后生效；容器平台若固定启动 `bash`，还需调整终端启动命令。若配置未生效，查看摘要中 Zsh、插件、主题及 `dotfiles` 的完成情况。

</details>

<details>
<summary>可以重复执行吗？如何升级？</summary>

可以。已有工具按模块规则复用，升级使用原包管理器或上游提供的方式。更新仓库预设后，通过 `--dotfiles` 部署所需配置；个人插件清单和主题配置自行维护。仓库固定版本的调整见[项目维护](#项目维护)。

</details>

<details>
<summary>fzf 已安装，但快捷键不可用？</summary>

外部升级或更换 fzf 后，刷新集成脚本并接入配置：

```bash
bash bootstrap.sh --non-interactive --modules tools,dotfiles --tools fzf --dotfiles zshrc,fzf
```

旧 Debian/Ubuntu 的脚本从匹配版本的 APT 包提取；若软件源不再提供该版本，先升级 fzf。已有 `.zshrc` 仍按 `skip` / `backup` 处理。

</details>

<details>
<summary>下载失败或摘要中有跳过项？</summary>

按摘要中的原因处理，再使用附带的重试命令。Git 下载默认限时 600 秒，可调整 `[options] git_timeout`，并检查网络与代理。退出码 `0` 不代表所有组件完成；需要保留日志时，可在安装命令后追加 `> install.log 2>&1`。

</details>

## 项目维护

```text
bootstrap.sh             # 安装入口
modules/                 # 功能模块
lib/                     # 系统检测、下载、包管理与配置部署
config/                  # 安装配置和程序配置
scripts/update-pins.sh   # 固定版本维护
scripts/update-clash.sh  # Clash 镜像维护
tests/run.sh             # 基础检查
```

### 本地检查与 CI

完整检查需要 Zsh 和 ShellCheck，在仓库目录运行：

```bash
git ls-files -z '*.sh' | xargs -0 -n 1 /bin/bash -n
git ls-files -z '*.zsh' 'config/zsh/zshrc' | xargs -0 -n 1 zsh -n
git ls-files -z '*.sh' | xargs -0 shellcheck --severity=warning
/bin/bash tests/run.sh
```

CI 在 Ubuntu 与 macOS 上准备检查工具并输出实际版本，保留 macOS `/bin/bash` 的 Bash 3.2 验证。现有检查使用临时 HOME 和模拟的包管理、下载命令；Clash 完整安装、终端交互和 GPU 展示仍需在目标环境验证。

### 版本与镜像维护

只读比较固定值，或批量更新并确认计划；每个组件可指定版本，省略时自动发现最新目标：

```bash
bash scripts/update-pins.sh check all
bash scripts/update-pins.sh update zellij v0.45.1 powerlevel10k
bash scripts/update-pins.sh update all
```

检查不改写文件；更新会先校验全部所选项，展示计划并确认后写入对应仓库文件。`update all` 覆盖 Zellij、Powerlevel10k、Antidote 和默认插件；Clash 通过专用镜像流程维护。完整用法见 [scripts/README.md](scripts/README.md)。
