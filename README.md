# oh-my-devboom

轻量、模块化的个人开发环境初始化工具，面向 Linux 服务器、Docker 容器和 macOS。入口和安装模块使用 Bash，支持系统自带的 Bash 3.2，不依赖 Python 或 Node.js。

## 安装内容总览

默认选中的模块会尝试安装或配置以下内容：

| 类别 | 内容 | 模块 |
| --- | --- | --- |
| 基础工具 | git、curl、wget、vim、unzip、zsh | `base` |
| 包管理器 | Homebrew | `homebrew` |
| Zsh 增强 | Antidote 插件管理器，以及 zsh-completions（补全）、zsh-autosuggestions（输入建议）、zsh-syntax-highlighting（语法高亮） | `zsh` |
| Prompt | Powerlevel10k、gitstatusd Git 状态辅助程序，以及仓库独立维护的个人主题预设 | `powerlevel10k` |
| 配置部署 | Zsh 启动配置、插件列表、Git 通用配置和 Powerlevel10k 预设，通过软链接部署 | `dotfiles` |

以下开发工具为可选项，需选择 `tools` 模块；该模块默认安装表中全部工具，也可用 `--tools` 指定子集：

| 工具 | 用途 | `--tools` 名称 |
| --- | --- | --- |
| uv | Python 环境与依赖管理 | `uv` |
| fzf | 交互式模糊查找 | `fzf` |
| ripgrep | 文件内容搜索，命令为 `rg` | `rg` |
| bat | 带语法高亮的文件查看 | `bat` |
| eza | 文件与目录列表 | `eza` |
| zoxide | 根据使用记录快速跳转目录 | `zoxide` |
| Zellij | 终端分屏、标签页与持久会话 | `zellij` |
| NVTOP | 查看 GPU 利用率、显存及相关进程 | `nvtop` |
| jq | JSON 筛选、转换与格式化 | `jq` |
| fd | 按文件名、扩展名和类型查找文件 | `fd` |

已有组件会跳过重复安装；实际完成项取决于平台支持、权限和远程代码许可。Homebrew 在 root、容器等不满足安装条件的环境中会跳过，配置冲突按[配置管理](#配置管理)中的规则处理。

## 快速开始

先准备 `git`，克隆并查看脚本：

```bash
git clone https://github.com/PercyWei/oh-my-devboom.git
cd oh-my-devboom
bash bootstrap.sh --help
bash bootstrap.sh
```

交互模式可选择安装模块，并确认远程代码来源。默认选择 `base,homebrew,zsh,powerlevel10k,dotfiles`；可选开发工具需要显式选择 `tools` 模块。

非交互执行必须加 `--yes`。它接受当前模块选择，并使用非交互方式调用包管理器；远程安装脚本、Antidote、插件、Powerlevel10k 和 Zellij 发布包仍需单独允许：

```bash
# 使用默认模块；未允许的远程安装会跳过并给出提示
bash bootstrap.sh --yes

# 安装全部模块，允许下文列出的远程代码来源
bash bootstrap.sh --yes --allow-remote \
  --modules base,homebrew,zsh,powerlevel10k,tools,dotfiles

# 仅部署配置：保留现有冲突文件
bash bootstrap.sh --yes --modules dotfiles

# 安装指定的可选工具
bash bootstrap.sh --yes --allow-remote --modules tools --tools uv,rg,fzf

# 安装终端会话管理与 GPU 监控工具
bash bootstrap.sh --yes --allow-remote --modules tools --tools zellij,nvtop

# 安装 JSON 处理与文件查找工具
bash bootstrap.sh --yes --modules tools --tools jq,fd
```

配置通过软链接指向仓库文件。部署后请保留仓库所在目录；若移动仓库，需要重新部署配置。

## 仓库结构

```text
bootstrap.sh              # 参数解析、交互选择、模块调度
lib/                      # 系统检测、权限、包管理、下载及软链接
modules/                  # 每个功能一个 Bash 模块
config/
  zsh/                    # .zshrc 与固定提交的插件列表
  git/                    # 通用 Git 配置
  powerlevel10k/          # 独立 .p10k.zsh 主题预设
tests/run.sh              # 隔离环境下的基础测试
```

`modules/NAME.sh` 定义 `module_NAME()`，加载文件时不执行安装。模块返回 `0` 表示完成，`2` 表示跳过或部分未完成，`1` 表示错误；入口负责汇总日志和最终退出状态。公共能力集中在 `lib/`，模块只描述本功能的安装步骤。

## 模块与参数

| 模块 | 职责 |
| --- | --- |
| `base` | 安装 git、curl、wget、vim、unzip、zsh 等基础工具 |
| `homebrew` | 检测或安装 Homebrew，并配置当前执行过程的 PATH |
| `zsh` | 安装 Zsh、Antidote 及常用插件 |
| `powerlevel10k` | 按固定提交安装 Powerlevel10k；个人预设独立保存在仓库配置中 |
| `tools` | 安装选中的 uv、fzf、ripgrep、bat、eza、zoxide、Zellij、NVTOP、jq、fd |
| `dotfiles` | 部署 Shell、Git 和 Powerlevel10k 配置软链接 |

模块按依赖顺序执行，参数中的顺序不影响执行顺序：Linux 先 `base` 后 `homebrew`，macOS 先 `homebrew` 后 `base`，其余按表中顺序执行。只选择需要的模块；配置部署由 `dotfiles` 模块负责。

| 参数 | 说明 |
| --- | --- |
| `--help` | 显示使用说明 |
| `--list-modules` | 列出可用模块 |
| `--modules LIST` | 逗号分隔的模块名；指定后替换默认选择 |
| `--tools LIST` | `tools` 模块的工具列表；支持 `uv,fzf,rg,bat,eza,zoxide,zellij,nvtop,jq,fd`，默认全部，平台不支持时明确跳过 |
| `--yes` | 非交互执行，不等待安装选择或确认 |
| `--allow-remote` | 允许远程安装脚本、插件、主题及直接下载的工具发布包 |
| `--conflict skip\|backup` | 配置冲突规则，默认 `skip` |

未知参数、模块、工具或冲突策略会直接报错。`--tools` 只设置工具列表，不会自动选择 `tools` 模块。

实际安装或执行错误返回非零状态。权限不足、平台条件不满足、未允许远程代码及配置冲突等跳过情形会显示原因，但允许其他模块继续，并在没有实际错误时返回零；自动化执行后请同时检查结果摘要。

## Linux 与 macOS

脚本检测操作系统、Linux 发行版、架构、用户权限和可用包管理器。Linux 支持检测 `apt-get`、`dnf`、`yum`、`pacman`、`zypper` 和 `apk`；macOS 使用 Homebrew。检测到包管理器不代表发行版的所有可选包均可安装，缺少包或权限时会明确报告。

jq 和 fd 通过包管理器安装。fd 在 Debian/Ubuntu 和 Fedora 的包名为 `fd-find`，在 Debian/Ubuntu 中命令名为 `fdfind`；项目 Zsh 配置会在没有 `fd` 命令时设置 `alias fd=fdfind`，其他 Shell 和脚本可直接调用 `fdfind`。已有 `fd` 或 `fdfind` 时会跳过重复安装。参见 [fd 安装说明](https://github.com/sharkdp/fd#installation)。

Zellij 优先使用已有 Homebrew 或 Arch 的 pacman 安装，其他环境使用固定版本的官方发布包，校验 SHA-256 后放入 `~/.local/bin`，支持 Linux/macOS 的 x86_64 和 ARM64。发布包路径需要远程代码许可，安装后手动运行 `zellij` 启动会话。

Zellij 默认使用 `$SHELL` 创建终端窗格；即使当前已运行 `exec zsh`，该变量仍可能是 `/bin/bash`。需要在新会话中使用本项目的 Zsh 配置时，显式指定 Shell，参见 [Zellij CLI 配置](https://zellij.dev/documentation/command-line-options)：

```bash
zellij options --default-shell "$(command -v zsh)"
```

NVTOP 使用系统包管理器或 Homebrew 安装。Linux 的 GPU 监控依赖对应驱动和设备访问权限；容器还需向进程暴露 GPU，安装 NVTOP 不会配置驱动或容器设备。macOS 后端仅支持 Apple GPU，功能有限，Intel Mac 会跳过；详见 [NVTOP 上游说明](https://github.com/Syllo/nvtop#apple)。Homebrew 的 [nvtop 公式](https://formulae.brew.sh/formula/nvtop)当前因上游校验值问题被标记为 deprecated，包管理器报错时会如实记录。

在全新的 Linux 上，通常先选择 `base`；基础工具通过系统包管理器安装。root 直接执行系统包安装，普通用户仅在实际需要时使用可用的 sudo。无 root、无可用 sudo 的环境仍可部署用户配置，并使用满足条件的用户级工具安装方式。

macOS 需要先准备 Apple Command Line Tools：

```bash
xcode-select --install
```

完成系统弹窗中的安装后，在普通用户账户下运行入口脚本。Homebrew 的安装位置和 PATH 根据平台检测；Zsh 配置也会加载已有 Homebrew 环境。

容器检测使用常见标记文件、`container` 环境变量，以及已安装的 `systemd-detect-virt --container --quiet`；不会为检测额外安装依赖。容器中通常使用 root 和系统包管理器，本工具跳过已识别容器中的 Homebrew 安装（包括容器内的普通用户）。root 安装及其他不满足条件的环境也会给出原因并跳过。

在容器中可直接选择以下模块。使用实际工作账户运行入口；普通用户需要输入 sudo 密码时，去掉 `--yes`：

```bash
bash bootstrap.sh --yes --allow-remote \
  --modules base,zsh,powerlevel10k,tools,dotfiles
exec zsh
```

执行后检查结果摘要和配置冲突提示；已有 `.zshrc` 默认保留，按需使用 `--conflict backup` 部署仓库配置。将仓库保存在需要长期保留的位置；容器重建后，系统包及 HOME 中未持久化的工具、插件和缓存需要重新安装。

脚本不会自动执行 `chsh`。安装结束后可先运行 `zsh` 检查配置，再根据设备权限自行修改默认 Shell：

```bash
chsh -s "$(command -v zsh)"
```

## 配置管理

配置文件集中在 `config/`，默认部署位置如下。`XDG_CONFIG_HOME` 默认为 `~/.config`；设置 `ZDOTDIR` 时，`.zshrc` 和 `.p10k.zsh` 部署到该目录。

| 仓库文件 | 目标 |
| --- | --- |
| `config/zsh/zshrc` | `${ZDOTDIR:-$HOME}/.zshrc` |
| `config/zsh/zsh_plugins.txt` | `$XDG_CONFIG_HOME/oh-my-devboom/zsh_plugins.txt` |
| `config/git/gitconfig` | `~/.gitconfig` |
| `config/powerlevel10k/p10k.zsh` | `${ZDOTDIR:-$HOME}/.p10k.zsh` |

修改 Shell、Git 或主题文件后，软链接会立即使用新内容；重新打开 Shell 以加载 Shell 配置。插件列表固定到各仓库的提交，修改列表后需要重新运行 `zsh` 模块以生成静态插件文件。Shell 启动仅加载本地组件，不会自动下载代码或 gitstatusd；只运行 `dotfiles` 也不会安装插件或主题。

即使系统已初始化补全，或插件尚未安装，已安装的 fzf 和 zoxide 仍会初始化。fzf 优先使用 `fzf --zsh`；不支持该选项的旧版加载 Debian/Ubuntu 系统包中的 `/usr/share/doc/fzf/examples/completion.zsh` 和 `key-bindings.zsh`，启用 Ctrl-R、Ctrl-T 和 Alt-C；缺少这些脚本时会提示升级 fzf。zoxide 提供 `z`、`zi` 目录跳转命令。

Powerlevel10k 需要 Zsh 5.1 或更高版本，安装在 `${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-devboom/powerlevel10k`。Zsh 配置在开头启用 instant prompt（即时提示），随后加载已安装的主题和 `${ZDOTDIR:-$HOME}/.p10k.zsh`。

仓库预设采用 lean、单行、紧凑布局，图标较少，使用 `nerdfont-v3` 图标模式；左侧显示目录、Git 状态和提示符，右侧按需显示命令状态、耗时、后台任务、环境信息和 24 小时时间。transient prompt（简化已执行命令的提示符）设为 `always`，instant prompt 设为 `verbose`。环境信息相关段落只检测已有工具，不会因此安装语言运行时或版本管理器。

终端需要配置兼容 Nerd Font v3 的字体；可使用上游推荐的 [MesloLGS NF](https://github.com/romkatv/powerlevel10k#fonts)。字体显示由本机终端决定，服务器或容器中不会自动安装字体。

日常定制直接编辑 `config/powerlevel10k/p10k.zsh`，再运行 `source "${ZDOTDIR:-$HOME}/.p10k.zsh"` 加载；完整重新配置可使用 [`p10k configure`](https://github.com/romkatv/powerlevel10k#configuration-wizard)。部署后 `.p10k.zsh` 是软链接，运行该向导也会更新仓库中的预设文件。

部署遵循以下规则：

- 目标不存在：创建软链接。
- 已指向当前配置：跳过，重复执行不追加配置。
- 目标存在且与当前配置冲突：默认 `skip`，保留原文件并显示提示。
- 使用 `--conflict backup`：先把原文件、目录或软链接重命名为带时间戳的备份，再创建软链接。备份路径会显示在日志中。

示例：

```bash
bash bootstrap.sh --yes --modules dotfiles --conflict backup
```

恢复时，先检查日志中的备份路径，删除本工具创建的对应软链接，再将备份移回原位置。不要删除实际配置目录。

Git 配置不包含个人姓名、邮箱或凭据，并加载 `~/.gitconfig.local`。将个人信息写入该文件，避免修改仓库中的共享配置：

```bash
git config --file "$HOME/.gitconfig.local" user.name "Your Name"
git config --file "$HOME/.gitconfig.local" user.email "you@example.com"
```

## 远程来源与可重复执行

安装前会检查目标命令和安装目录，已安装的组件通常直接跳过。该工具用于初始化和重新部署，不强制升级已有工具。Antidote、默认插件和 Powerlevel10k 固定提交；系统包、Homebrew 包及远程安装器下载的工具版本未锁定。

远程脚本先下载到本地审查副本，显示来源 URL，并在有 SHA-256 工具时显示下载文件的校验值，再由交互确认或 `--allow-remote` 允许执行。校验工具缺失时会明确提示人工审查；非交互模式未设置 `--allow-remote` 时不下载或执行安装脚本。该 SHA-256 用于标识下载内容，不能替代发布方提供的独立校验或签名。请先审查对应上游安装器；系统包和 Homebrew 包仍按各自包管理器的机制安装。

项目管理的远程下载使用以下限制，失败或超时会报错并继续其他模块：

| 下载方式 | 超时与重试 |
| --- | --- |
| curl | 连接超时 15 秒，单次传输上限 300 秒，最多重试 2 次；经过 300 秒后不再启动重试，在途请求仍可能继续，因此不是全过程 300 秒上限 |
| wget | 网络等待超时 30 秒；GNU wget 最多尝试 3 次，BusyBox wget 不重试，且其 DNS 查询不受该参数限制 |
| Git | Antidote 克隆、整批插件下载、Powerlevel10k 拉取各自计时，120 秒后终止该任务及子进程；HTTP 传输连续 30 秒低于 1 字节/秒也会中止 |

这些限制不控制 Homebrew、uv 安装脚本内部的下载，也不限制包管理器的执行时间。

| 组件 | 上游来源 |
| --- | --- |
| Homebrew | [官方安装脚本](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) |
| Antidote | [v2.3.0 固定提交](https://github.com/mattmc3/antidote/tree/9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14) |
| Powerlevel10k | [固定提交 d05a1b0](https://github.com/romkatv/powerlevel10k/tree/d05a1b00f9a61f9578bf9dc19b8451942dde8734) |
| gitstatusd | [官方 v1.5.4 发布文件](https://github.com/romkatv/gitstatus/releases/tag/v1.5.4)，按 Powerlevel10k 固定提交中的清单校验 SHA-256 |
| Zellij | [官方 v0.45.1 发布包](https://github.com/zellij-org/zellij/releases/tag/v0.45.1)，校验固定的压缩包 SHA-256 |
| uv | [官方安装脚本](https://astral.sh/uv/install.sh) |

Homebrew、uv 的安装脚本 URL 会随上游更新，尚未固定内容。Antidote 插件列表中的仓库也是执行代码的来源，请在启用前审查插件列表。Antidote、插件、Powerlevel10k 和 Zellij 发布包在下载前同样需要远程代码许可。

`powerlevel10k` 模块在安装阶段下载并校验 gitstatusd，支持 Linux、macOS 的 x86_64 和 ARM64，缓存到 `${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-devboom/gitstatus`。Shell 启动禁用 gitstatusd 自动安装；清除此缓存后，重新运行 `powerlevel10k` 模块恢复。

## 检查与测试

测试使用临时 HOME 和模拟命令，不会调用真实包管理器、安装远程组件或修改当前用户配置：

```bash
bash tests/run.sh
git ls-files -z '*.sh' | xargs -0 -n 1 bash -n
```

覆盖系统检测、参数解析、重复执行、配置部署、Shell 初始化和下载超时/失败处理。Shell 集成检查需要本机已有 Zsh；缺失时该组会明确跳过。CI 在 Ubuntu 和 macOS 上运行相同检查。测试结果不能代替全新服务器、容器和 macOS 设备上的真实安装验证。

新环境复测时，还应确认交互式 Zsh 中的 `z`、`zi`、fzf 快捷键及 Powerlevel10k 的 Git 状态显示。CPU 容器只能检查 NVTOP 的安装和无 GPU 时的行为，GPU 数据展示需在具备设备访问权限的环境验证。

## 常见问题

**无权限安装系统包怎么办？** 先使用可完成的用户级模块和配置部署。系统包安装需要 root 或可用 sudo；脚本会报告无法完成的步骤。

**已有 `.zshrc` 等配置会被覆盖吗？** 默认保留并跳过。需要使用仓库配置时，显式选择 `--conflict backup`，检查日志中的备份路径。

**安装后命令仍找不到？** 重新打开终端，或启动新的 `zsh`。同时查看日志，确认安装未因权限、远程执行许可或平台条件而跳过。

**插件或主题下载失败怎么办？** 查看原始网络错误及最终 `Failed` 摘要，确认容器能够访问对应上游；配置软链接部署成功不代表插件或主题已安装。网络恢复后重新运行失败的模块，例如 `bash bootstrap.sh --yes --allow-remote --modules zsh,powerlevel10k`。

**只安装 Prompt，不接管 Shell 配置？** 只选择 `powerlevel10k`，将 `config/powerlevel10k/p10k.zsh` 复制或链接到 `${ZDOTDIR:-$HOME}/.p10k.zsh`，再参照 `config/zsh/zshrc`，把 instant prompt 和主题、预设的加载语句加入自己的 `.zshrc`。

**如何更新配置或工具？** 更新仓库后重新执行所需模块；配置软链接直接使用仓库内容。工具升级请使用其原安装方式，例如系统包管理器、Homebrew 或 uv 自身的更新命令。
