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

以下开发工具为可选项，需在安装配置中启用 `tools` 模块；每个工具可以独立开关，也可用 `--tools` 临时指定子集：

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

已有组件会跳过重复安装；实际完成项取决于平台支持、权限和[上游下载授权](#上游下载与授权)。Homebrew 在 root、容器等不满足安装条件的环境中会跳过，配置冲突按[程序配置部署](#程序配置部署)中的规则处理。

## 快速开始

先准备 `git`，克隆仓库，复制默认安装配置后按需修改：

```bash
git clone https://github.com/PercyWei/oh-my-devboom.git
cd oh-my-devboom
cp config/default.conf config/local.conf
vim config/local.conf
bash bootstrap.sh --config config/local.conf
```

安装前会打印配置来源、最终选择的模块和工具，以及上游下载授权和配置冲突策略。交互模式确认整体清单后开始执行；未预先授权的上游内容仍会按来源逐项请求确认。

非交互执行必须加 `--non-interactive`，仍会打印清单，但不等待输入。直接下载的上游安装脚本、插件、主题和发布包需通过 `allow_remote=true` 或 `--allow-remote` 单独授权，否则跳过对应步骤；具体内容和包管理器例外见[上游下载与授权](#上游下载与授权)。

```bash
# 使用自己的安装配置，授权其中选中的上游内容
bash bootstrap.sh --config config/local.conf --non-interactive --allow-remote

# 临时安装全部模块和工具
bash bootstrap.sh --non-interactive --allow-remote --modules all --tools all

# 仅部署配置：保留现有冲突文件
bash bootstrap.sh --non-interactive --modules dotfiles

# 临时覆盖文件中的模块和工具选择
bash bootstrap.sh --non-interactive --modules tools --tools jq,fd
```

Shell、Git 和主题配置通过软链接指向仓库文件。部署后请保留仓库所在目录；若移动仓库，需要重新部署配置。

## 安装选择配置

默认读取仓库中的 `config/default.conf`；`--config FILE` 改为读取指定文件，相对路径按运行命令时所在目录解释。`config/local.conf` 已加入 Git 忽略规则，但不会自动加载，使用它时需要显式传入 `--config`。也可以为不同设备保存不同文件。

配置采用单一的 INI 格式，按职责分成三个章节：

| 章节 | 内容 |
| --- | --- |
| `[modules]` | 各功能模块的总开关，值为 `true` 或 `false` |
| `[tools]` | 每个可选开发工具的开关；仅在 `[modules]` 中 `tools=true` 时生效 |
| `[options]` | `allow_remote=true\|false` 控制[上游下载授权](#上游下载与授权)；`conflict=skip\|backup` 控制已有配置的处理方式 |

默认配置启用 `base`、`homebrew`、`zsh`、`powerlevel10k`、`dotfiles`，关闭 `tools` 总开关；工具条目默认全部为 `true`，因此启用 `tools` 后应按需关闭不需要的工具。基础工具和模块职责见上面的安装内容总览。

例如，仅安装基础工具、fzf、jq、fd，并部署 Shell/Git/主题配置，可以使用：

```ini
[modules]
base=true
tools=true
dotfiles=true

[tools]
fzf=true
jq=true
fd=true

[options]
allow_remote=false
conflict=skip
```

指定文件完整决定本次选择，不与默认文件合并：未列出的模块和工具均关闭，未写的行为选项采用 `allow_remote=false`、`conflict=skip`。模块和工具标识符见下文参数表及默认配置文件。

文件支持空行、`#` 注释和赋值两侧的空白；值不加引号，不支持变量替换或执行命令。未知章节、键或无效值会报错。

命令行参数覆盖文件中的对应设置，与 `--config` 在参数中的位置无关。`--modules` 和 `--tools` 分别替换整个列表，支持 `all`；`--tools` 不会自动启用 `tools` 模块。安装选择文件只决定安装内容和策略；要修改别名、Git 偏好或主题外观，请编辑后文列出的程序配置。

## 仓库结构

```text
bootstrap.sh              # 配置读取、参数解析、清单确认、模块调度
lib/                      # 系统检测、权限、包管理、下载及软链接
modules/                  # 每个功能一个 Bash 模块
config/
  default.conf            # 默认安装选择，复制后按需修改
  local.conf              # 个人安装选择，Git 忽略，需用 --config 指定
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
| `--config FILE` | 读取指定安装配置；默认使用仓库的 `config/default.conf` |
| `--modules LIST` | 逗号分隔的模块名，或 `all`；替换配置中的模块选择 |
| `--tools LIST` | 工具列表：`uv,fzf,rg,bat,eza,zoxide,zellij,nvtop,jq,fd`，或 `all`；替换配置中的工具选择，平台不支持时明确跳过 |
| `--non-interactive` | 非交互模式，打印清单后执行，不等待输入；不自动授权上游下载 |
| `--allow-remote` | 允许[上游下载与授权](#上游下载与授权)中列出的直接下载和执行 |
| `--conflict skip\|backup` | 覆盖配置文件中的冲突规则 |

未知参数、模块、工具或冲突策略会直接报错。`--tools` 只设置工具列表，不会自动选择 `tools` 模块。

实际安装或执行错误返回非零状态。权限不足、平台条件不满足、上游下载未授权及配置冲突等跳过情形会显示原因，但允许其他模块继续，并在没有实际错误时返回零；自动化执行后请同时检查结果摘要。

## Linux 与 macOS

脚本检测操作系统、Linux 发行版、架构、用户权限和可用包管理器。Linux 支持检测 `apt-get`、`dnf`、`yum`、`pacman`、`zypper` 和 `apk`；macOS 使用 Homebrew。检测到包管理器不代表发行版的所有可选包均可安装，缺少包或权限时会明确报告。

jq 和 fd 通过包管理器安装。fd 在 Debian/Ubuntu 和 Fedora 的包名为 `fd-find`，在 Debian/Ubuntu 中命令名为 `fdfind`；项目 Zsh 配置会在没有 `fd` 命令时设置 `alias fd=fdfind`，其他 Shell 和脚本可直接调用 `fdfind`。已有 `fd` 或 `fdfind` 时会跳过重复安装。参见 [fd 安装说明](https://github.com/sharkdp/fd#installation)。

Zellij 优先使用已有 Homebrew 或 Arch 的 pacman 安装，其他环境使用固定版本的官方发布包，校验 SHA-256 后放入 `~/.local/bin`，支持 Linux/macOS 的 x86_64 和 ARM64。直接下载发布包时需要上游下载授权，安装后手动运行 `zellij` 启动会话。

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

在容器中可直接选择以下模块。使用实际工作账户运行入口；普通用户需要输入 sudo 密码时，去掉 `--non-interactive`：

```bash
bash bootstrap.sh --non-interactive --allow-remote \
  --modules base,zsh,powerlevel10k,tools,dotfiles
exec zsh
```

执行后检查结果摘要和配置冲突提示；已有 `.zshrc` 默认保留，按需使用 `--conflict backup` 部署仓库配置。将仓库保存在需要长期保留的位置；容器重建后，系统包及 HOME 中未持久化的工具、插件和缓存需要重新安装。

脚本不会自动执行 `chsh`。安装结束后可先运行 `zsh` 检查配置，再根据设备权限自行修改默认 Shell：

```bash
chsh -s "$(command -v zsh)"
```

## 程序配置部署

Shell、Git 和主题的配置文件集中在 `config/`，默认部署位置如下。`XDG_CONFIG_HOME` 默认为 `~/.config`；设置 `ZDOTDIR` 时，`.zshrc` 和 `.p10k.zsh` 部署到该目录。

| 仓库文件 | 目标 |
| --- | --- |
| `config/zsh/zshrc` | `${ZDOTDIR:-$HOME}/.zshrc` |
| `config/zsh/zsh_plugins.txt` | `$XDG_CONFIG_HOME/oh-my-devboom/zsh_plugins.txt` |
| `config/git/gitconfig` | `~/.gitconfig` |
| `config/powerlevel10k/p10k.zsh` | `${ZDOTDIR:-$HOME}/.p10k.zsh` |

修改 Shell、Git 或主题文件后，软链接会立即使用新内容；重新打开 Shell 以加载 Shell 配置。插件列表固定到各仓库的提交，修改列表后需要重新运行 `zsh` 模块以生成静态插件文件。Shell 启动仅加载本地组件，不会自动下载代码或 gitstatusd；只运行 `dotfiles` 也不会安装插件或主题。

即使系统已初始化补全，或插件尚未安装，已安装的 fzf 和 zoxide 仍会初始化。fzf 优先使用 `fzf --zsh`，启用 Ctrl-R、Ctrl-T 和 Alt-C。Debian/Ubuntu 的旧版系统 fzf 在安装阶段将补全和快捷键脚本保存到 `${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-devboom/fzf`，仅在与当前 fzf 版本一致时加载。精简容器若裁剪了系统包文档，则从 APT 仓库下载已安装的精确版本包并提取脚本，沿用 APT 校验，不修改全局 dpkg 规则；其他来源的旧版 fzf 会提示升级。zoxide 提供 `z`、`zi` 目录跳转命令。

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
bash bootstrap.sh --non-interactive --modules dotfiles --conflict backup
```

恢复时，先检查日志中的备份路径，删除本工具创建的对应软链接，再将备份移回原位置。不要删除实际配置目录。

Git 配置不包含个人姓名、邮箱或凭据，并加载 `~/.gitconfig.local`。将个人信息写入该文件，避免修改仓库中的共享配置：

```bash
git config --file "$HOME/.gitconfig.local" user.name "Your Name"
git config --file "$HOME/.gitconfig.local" user.email "you@example.com"
```

## 上游下载与授权

`allow_remote` / `--allow-remote` 控制本项目直接下载的上游安装脚本、插件、主题和发布包，具体包括：

| 安装内容 | 上游来源 |
| --- | --- |
| Homebrew 官方安装脚本 | [Homebrew/install](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) |
| uv 官方安装脚本及其下载的工具 | [Astral 安装器](https://astral.sh/uv/install.sh) |
| Antidote 插件管理器 | [v2.3.0 固定提交](https://github.com/mattmc3/antidote/tree/9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14) |
| 三个 Zsh 插件 | [zsh-completions](https://github.com/zsh-users/zsh-completions)、[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)、[zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)，提交固定在 `config/zsh/zsh_plugins.txt` |
| Powerlevel10k 主题 | [固定提交 d05a1b0](https://github.com/romkatv/powerlevel10k/tree/d05a1b00f9a61f9578bf9dc19b8451942dde8734) |
| gitstatusd Git 状态辅助程序 | [官方 v1.5.4 发布文件](https://github.com/romkatv/gitstatus/releases/tag/v1.5.4)，按 Powerlevel10k 固定提交中的清单校验 SHA-256 |
| Zellij 官方发布包 | [官方 v0.45.1 发布包](https://github.com/zellij-org/zellij/releases/tag/v0.45.1)，校验固定的压缩包 SHA-256 |

授权按安装路径生效。通过 APT、Homebrew、pacman 等包管理器安装，以及部署本地配置软链接，不受此开关限制；例如 uv 通过已有 Homebrew 安装、Zellij 通过 Homebrew 或 pacman 安装时，无需此授权。包管理器仍可能联网，已安装的组件仍按模块规则复用或补齐配置。

设置 `allow_remote=true` 或传入 `--allow-remote` 后，允许安装清单中相应内容的下载和执行。默认未授权时，交互执行会按来源逐项确认；非交互执行会跳过表中的直接下载步骤，不下载或执行这些内容。

对尚未授权的官方安装脚本，交互模式会先下载为本地审查副本，显示来源 URL，并在有 SHA-256 工具时显示下载文件的校验值，再请求执行确认。校验工具缺失时会提示人工审查；该 SHA-256 用于标识下载内容，不能替代发布方提供的独立校验或签名。Homebrew、uv 的安装脚本 URL 会随上游更新，尚未固定内容，请先审查对应上游安装器。

该工具用于初始化和重新部署，不强制升级已有工具。系统包、Homebrew 包及安装器下载的工具版本未锁定。项目管理的下载使用以下限制，失败或超时会报错并继续其他模块：

| 下载方式 | 超时与重试 |
| --- | --- |
| curl | 连接超时 15 秒；连续 60 秒低于 1 字节/秒则中止；单次传输默认上限 300 秒，Zellij 发布包为 1800 秒。最多重试 2 次，经过 300 秒后不再启动重试，在途请求仍可继续，因此不是全过程 300 秒上限 |
| wget | 网络等待超时 30 秒；GNU wget 最多尝试 3 次，BusyBox wget 不重试，且其 DNS 查询不受该参数限制 |
| Git | Antidote 克隆、整批插件下载、Powerlevel10k 拉取各自计时，120 秒后终止该任务及子进程；HTTP 传输连续 30 秒低于 1 字节/秒也会中止 |

这些限制不控制 Homebrew、uv 安装脚本内部的下载，也不限制包管理器的执行时间。

`powerlevel10k` 模块在安装阶段下载并校验 gitstatusd，支持 Linux、macOS 的 x86_64 和 ARM64，缓存到 `${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-devboom/gitstatus`。Shell 启动禁用 gitstatusd 自动安装；清除此缓存后，重新运行 `powerlevel10k` 模块恢复。

## 检查与测试

测试使用临时 HOME 和模拟命令，不会调用真实包管理器、实际下载或安装上游软件，也不会修改当前用户配置：

```bash
bash tests/run.sh
git ls-files -z '*.sh' | xargs -0 -n 1 bash -n
```

覆盖系统检测、安装配置与参数解析、重复执行、配置部署、Shell 初始化和下载超时/失败处理。Shell 集成检查需要本机已有 Zsh；缺失时该组会明确跳过。CI 在 Ubuntu 和 macOS 上运行相同检查。测试结果不能代替全新服务器、容器和 macOS 设备上的真实安装验证。

新环境复测时，还应确认交互式 Zsh 中的 `z`、`zi`、fzf 快捷键及 Powerlevel10k 的 Git 状态显示。CPU 容器只能检查 NVTOP 的安装和无 GPU 时的行为，GPU 数据展示需在具备设备访问权限的环境验证。

## 常见问题

**无权限安装系统包怎么办？** 先使用可完成的用户级模块和配置部署。系统包安装需要 root 或可用 sudo；脚本会报告无法完成的步骤。

**已有 `.zshrc` 等配置会被覆盖吗？** 默认保留并跳过。需要使用仓库配置时，显式选择 `--conflict backup`，检查日志中的备份路径。

**安装后命令仍找不到？** 重新打开终端，或启动新的 `zsh`。同时查看日志，确认安装未因权限、上游下载授权或平台条件而跳过。

**插件或主题下载失败怎么办？** 查看原始网络错误及最终 `Failed` 摘要，确认容器能够访问对应上游；配置软链接部署成功不代表插件或主题已安装。网络恢复后重新运行失败的模块，例如 `bash bootstrap.sh --non-interactive --allow-remote --modules zsh,powerlevel10k`。

**fzf 已安装，但快捷键不可用？** 运行 `bash bootstrap.sh --non-interactive --modules tools --tools fzf` 补齐 Shell 集成，然后重新打开 Zsh。Debian/Ubuntu 旧版所需脚本通过系统包来源获取，无需 `--allow-remote`；若仓库已无法提供当前已安装版本，先用原包管理器升级 fzf，再重试。Shell 启动不会联网下载脚本。

**只安装 Prompt，不接管 Shell 配置？** 只选择 `powerlevel10k`，将 `config/powerlevel10k/p10k.zsh` 复制或链接到 `${ZDOTDIR:-$HOME}/.p10k.zsh`，再参照 `config/zsh/zshrc`，把 instant prompt 和主题、预设的加载语句加入自己的 `.zshrc`。

**如何更新配置或工具？** 更新仓库后重新执行所需模块；配置软链接直接使用仓库内容。工具升级请使用其原安装方式，例如系统包管理器、Homebrew 或 uv 自身的更新命令。
