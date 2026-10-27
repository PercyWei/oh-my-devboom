# oh-my-devboom

轻量、模块化的个人开发环境初始化工具，面向 Linux 服务器、Docker 容器和 macOS。入口和安装模块使用 Bash，支持系统自带的 Bash 3.2，不依赖 Python 或 Node.js。

## 安装内容总览

默认安装内容：

| 类别 | 内容 | 模块 |
| --- | --- | --- |
| 基础工具 | git、curl、wget、vim、unzip、zsh | `base` |
| 包管理器 | Homebrew | `homebrew` |
| Zsh 增强 | Antidote 插件管理器，以及 zsh-completions（补全）、zsh-autosuggestions（输入建议）、zsh-syntax-highlighting（语法高亮） | `zsh` |
| Prompt | Powerlevel10k、gitstatusd Git 状态辅助程序及个人主题预设 | `powerlevel10k` |
| 配置部署 | Zsh 启动配置、插件列表、Git 通用配置和 Powerlevel10k 预设，通过软链接部署 | `dotfiles` |

启用 `tools` 模块后，可在配置中逐项选择工具，或用 `--tools` 指定：

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

已有组件会复用，Homebrew 在 root 或容器中跳过。下载授权和已有配置的处理规则见[上游下载与授权](#上游下载与授权)、[程序配置部署](#程序配置部署)。

## 快速开始

先准备 `git`，克隆仓库，复制默认安装配置后按需修改：

```bash
git clone https://github.com/PercyWei/oh-my-devboom.git
cd oh-my-devboom
cp config/default.conf config/local.conf
vim config/local.conf
bash bootstrap.sh --config config/local.conf
```

安装前会显示模块、工具及安装策略，确认后执行；未授权的上游下载会逐项询问。

非交互执行使用 `--non-interactive`；上游安装脚本、插件、主题和发布包需设置 `allow_remote=true` 或传入 `--allow-remote`，否则跳过对应下载。

```bash
# 使用个人配置并授权上游下载
bash bootstrap.sh --config config/local.conf --non-interactive --allow-remote

# 临时安装全部模块和工具
bash bootstrap.sh --non-interactive --allow-remote --modules all --tools all

# 仅部署配置，保留冲突文件
bash bootstrap.sh --non-interactive --modules dotfiles

# 仅安装 jq 和 fd
bash bootstrap.sh --non-interactive --modules tools --tools jq,fd
```

配置通过软链接指向仓库文件。部署后请保留仓库目录；移动后需重新部署。

## 安装选择配置

默认读取 `config/default.conf`，用 `--config FILE` 指定其他文件，相对路径以当前工作目录为准。建议复制为 `config/local.conf` 修改；该文件已被 Git 忽略，需用 `--config` 显式加载。

配置采用 INI 格式：

| 章节 | 内容 |
| --- | --- |
| `[modules]` | 各功能模块的总开关，值为 `true` 或 `false` |
| `[tools]` | 每个可选开发工具的开关；仅在 `[modules]` 中 `tools=true` 时生效 |
| `[options]` | `allow_remote=true\|false` 控制[上游下载授权](#上游下载与授权)；`github_proxy` 设置 GitHub 加速前缀；`conflict=skip\|backup` 控制已有配置的处理方式 |

默认关闭 `tools`，其余模块启用。工具条目默认全部选中，启用 `tools` 时请按需调整。

例如，安装基础工具、fzf、jq、fd 并部署配置：

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

指定文件替代默认配置：未列出的模块和工具均关闭；未填写的选项采用 `allow_remote=false`、`conflict=skip`、`github_proxy=`（直连）。

支持空行、`#` 注释和赋值两侧的空白。值不加引号，不展开变量；未知章节、键或无效值会报错。

命令行参数优先于配置文件，与 `--config` 的位置无关。别名、Git 偏好和主题外观在[程序配置](#程序配置部署)中修改。

## 仓库结构

```text
bootstrap.sh              # 配置读取、参数解析、清单确认、模块调度
lib/                      # 系统检测、权限、包管理、下载及软链接
modules/                  # 每个功能一个 Bash 模块
config/
  default.conf            # 默认安装配置
  local.conf              # 个人安装配置（Git 忽略）
  zsh/                    # .zshrc 与固定提交的插件列表
  git/                    # 通用 Git 配置
  powerlevel10k/           # .p10k.zsh 主题预设
tests/run.sh              # 基础测试
```

`modules/NAME.sh` 通过 `module_NAME()` 执行安装：返回 `0` 表示完成，`2` 表示跳过或部分未完成，`1` 表示错误。入口汇总结果，公共逻辑放在 `lib/`。

## 模块与参数

执行顺序固定：Linux 为 `base → homebrew → zsh → powerlevel10k → tools → dotfiles`；macOS 交换前两个模块的顺序。仅执行选中的模块。

| 参数 | 说明 |
| --- | --- |
| `--help` | 显示使用说明 |
| `--list-modules` | 列出可用模块 |
| `--config FILE` | 读取指定安装配置；默认使用仓库的 `config/default.conf` |
| `--modules LIST` | 逗号分隔的模块名，或 `all`；替换配置中的模块选择 |
| `--tools LIST` | 逗号分隔的工具名（见安装内容总览），或 `all`；替换配置中的工具选择 |
| `--non-interactive` | 非交互模式，打印清单后执行，不等待输入；不自动授权上游下载 |
| `--allow-remote` | 允许[上游下载与授权](#上游下载与授权)中列出的直接下载和执行 |
| `--conflict skip\|backup` | 覆盖配置文件中的冲突规则 |

`--tools` 需配合 `tools` 模块使用。未知参数或无效值会报错。

安装错误返回非零状态；权限不足、平台不支持、未授权或配置冲突导致的跳过会记录原因，不中断其他模块。退出码为零也可能存在跳过项，请检查结果摘要。

## Linux 与 macOS

脚本自动检测系统、发行版、架构、权限和包管理器。Linux 支持 `apt-get`、`dnf`、`yum`、`pacman`、`zypper` 和 `apk`，macOS 使用 Homebrew；包不可用或权限不足时会提示。

jq 和 fd 通过包管理器安装。fd 在 Debian/Ubuntu 和 Fedora 中包名为 `fd-find`；Debian/Ubuntu 中命令名为 `fdfind`，项目 Zsh 配置会按需设置 `fd` 别名。其他 Shell 和脚本可直接调用 `fdfind`。参见 [fd 安装说明](https://github.com/sharkdp/fd#installation)。

Zellij 优先通过已有 Homebrew 或 Arch 的 pacman 安装，否则下载固定版本发布包，校验 SHA-256 后放入 `~/.local/bin`，支持 Linux/macOS 的 x86_64 和 ARM64。安装后运行 `zellij` 启动会话。

Zellij 默认使用 `$SHELL` 创建窗格，运行 `exec zsh` 后该变量仍可能是 `/bin/bash`。新会话可显式指定 Zsh，参见 [Zellij CLI 配置](https://zellij.dev/documentation/command-line-options)：

```bash
zellij options --default-shell "$(command -v zsh)"
```

NVTOP 通过包管理器安装。Linux 需具备 GPU 驱动和设备访问权限，容器需暴露 GPU；macOS 仅支持 Apple GPU，Intel Mac 会跳过，详见 [NVTOP 上游说明](https://github.com/Syllo/nvtop#apple)。Homebrew 的 [nvtop 公式](https://formulae.brew.sh/formula/nvtop)当前因上游校验值问题被标记为 deprecated。

全新 Linux 环境建议启用 `base`。安装系统包时，root 直接执行，普通用户按需使用 sudo；无管理员权限时，可部署用户配置和支持用户级安装的工具。

macOS 需要先准备 Apple Command Line Tools：

```bash
xcode-select --install
```

完成后以普通用户运行入口脚本。脚本和 Zsh 配置会按平台加载 Homebrew 环境。

容器中使用系统包管理器，跳过 Homebrew。以实际工作账户运行以下命令；若需要输入 sudo 密码，去掉 `--non-interactive`：

```bash
bash bootstrap.sh --non-interactive --allow-remote \
  --modules base,zsh,powerlevel10k,tools,dotfiles
exec zsh
```

已有 `.zshrc` 默认保留，需要替换时使用 `--conflict backup`。仓库应放在持久化目录中；容器重建后，系统包和未持久化的工具、插件、缓存需重新安装。

安装后先运行 `zsh` 检查配置，再按需修改默认 Shell：

```bash
chsh -s "$(command -v zsh)"
```

## 程序配置部署

程序配置位于 `config/`，通过软链接部署到以下位置。`XDG_CONFIG_HOME` 默认为 `~/.config`。

| 仓库文件 | 目标 |
| --- | --- |
| `config/zsh/zshrc` | `${ZDOTDIR:-$HOME}/.zshrc` |
| `config/zsh/zsh_plugins.txt` | `$XDG_CONFIG_HOME/oh-my-devboom/zsh_plugins.txt` |
| `config/git/gitconfig` | `~/.gitconfig` |
| `config/powerlevel10k/p10k.zsh` | `${ZDOTDIR:-$HOME}/.p10k.zsh` |

直接编辑仓库文件即可修改配置，Shell 配置需重新打开终端加载。插件列表使用固定提交，修改后需重跑 `zsh` 模块生成静态配置。`dotfiles` 仅部署文件，插件和主题需启用对应安装模块。

fzf 提供 Ctrl-R、Ctrl-T 和 Alt-C 快捷键，zoxide 提供 `z`、`zi` 目录跳转命令。新版 fzf 使用 `fzf --zsh` 初始化；Debian/Ubuntu 旧版所需脚本在安装时缓存到 `${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-devboom/fzf`，仅加载与当前版本匹配的脚本。精简容器缺少这些脚本时，从 APT 仓库下载对应版本包提取；其他来源的旧版 fzf 需升级。

Powerlevel10k 需要 Zsh 5.1+，安装在 `${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-devboom/powerlevel10k`，预设从 `${ZDOTDIR:-$HOME}/.p10k.zsh` 加载。

预设采用 lean 单行紧凑布局和 `nerdfont-v3` 图标；左侧显示目录、Git 状态和提示符，右侧显示命令状态、耗时、后台任务、环境信息和 24 小时时间。transient prompt（简化已执行命令的提示符）设为 `always`，instant prompt（即时提示）设为 `verbose`。

请在本机终端配置兼容 Nerd Font v3 的字体，如 [MesloLGS NF](https://github.com/romkatv/powerlevel10k#fonts)。

修改 `config/powerlevel10k/p10k.zsh` 后，运行 `source "${ZDOTDIR:-$HOME}/.p10k.zsh"` 加载。也可使用 [`p10k configure`](https://github.com/romkatv/powerlevel10k#configuration-wizard) 向导；由于 `.p10k.zsh` 是软链接，向导会更新仓库中的预设。

部署遵循以下规则：

- 目标不存在：创建软链接。
- 已指向当前配置：跳过。
- 存在冲突：默认 `skip`，保留原文件。
- 使用 `--conflict backup`：将原文件、目录或链接备份后再部署，日志显示带时间戳的备份路径。

示例：

```bash
bash bootstrap.sh --non-interactive --modules dotfiles --conflict backup
```

恢复时，删除对应软链接，再将日志中的备份移回原位置。

Git 通用配置加载 `~/.gitconfig.local`，个人信息写入该文件：

```bash
git config --file "$HOME/.gitconfig.local" user.name "Your Name"
git config --file "$HOME/.gitconfig.local" user.email "you@example.com"
```

## 上游下载与授权

`allow_remote` / `--allow-remote` 授权以下内容的直接下载和执行或加载：

| 安装内容 | 上游来源 |
| --- | --- |
| Homebrew 官方安装脚本 | [Homebrew/install](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) |
| uv 官方安装脚本及其下载的工具 | [Astral 安装器](https://astral.sh/uv/install.sh) |
| Antidote 插件管理器 | [v2.3.0 固定提交](https://github.com/mattmc3/antidote/tree/9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14) |
| 三个 Zsh 插件 | [zsh-completions](https://github.com/zsh-users/zsh-completions)、[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)、[zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)，提交固定在 `config/zsh/zsh_plugins.txt` |
| Powerlevel10k 主题 | [固定提交 d05a1b0](https://github.com/romkatv/powerlevel10k/tree/d05a1b00f9a61f9578bf9dc19b8451942dde8734) |
| gitstatusd Git 状态辅助程序 | [官方 v1.5.4 发布文件](https://github.com/romkatv/gitstatus/releases/tag/v1.5.4)，按 Powerlevel10k 固定提交中的清单校验 SHA-256 |
| Zellij 官方发布包 | [官方 v0.45.1 发布包](https://github.com/zellij-org/zellij/releases/tag/v0.45.1)，校验固定的压缩包 SHA-256 |

通过 APT、Homebrew、pacman 等包管理器安装，以及本地配置部署，不受此开关限制。例如，uv 或 Zellij 通过已有 Homebrew 安装时无需授权。

设置 `allow_remote=true` 或传入 `--allow-remote` 可授权所选内容。未授权时，交互模式逐项确认，非交互模式跳过。

`github_proxy` 默认为第三方服务 `https://ghfast.top/`，用于项目管理的 `github.com`、`raw.githubusercontent.com` 文件下载及 Git 克隆、拉取（Git 2.31+）。前缀须为以 `/` 结尾的 HTTPS URL；设为空或在自定义配置中省略时直连。Git 加速仅在下载期间生效，保留原有配置和 `origin`。

日志显示官方来源和加速地址；下载仍需授权，并执行原有固定提交和 SHA-256 校验。失败时不自动切换来源。代理不覆盖包管理器、`astral.sh` 及 Homebrew、uv 安装器内部的下载。

Homebrew、uv 安装脚本随上游更新，未固定版本。未预授权时，交互模式先下载审查副本、显示来源及可用的 SHA-256，再确认执行；该校验值用于标识文件，不代表上游签名。

已有工具不会自动升级；系统包、Homebrew 包及安装器下载的工具版本未锁定。项目管理的下载使用以下超时，失败后继续其他模块：

| 下载方式 | 超时与重试 |
| --- | --- |
| curl | 连接超时 15 秒；连续 60 秒低于 1 字节/秒则中止；单次传输上限 300 秒，Zellij 为 1800 秒。最多重试 2 次，300 秒后不再发起重试，已开始的传输可继续 |
| wget | 网络等待超时 30 秒；GNU wget 最多尝试 3 次，BusyBox wget 不重试，且其 DNS 查询不受该参数限制 |
| Git | Antidote 克隆、整批插件下载、Powerlevel10k 拉取各限时 120 秒；HTTP 传输连续 30 秒低于 1 字节/秒也会中止 |

上述超时不适用于 Homebrew、uv 安装器内部及包管理器。

gitstatusd 支持 Linux/macOS 的 x86_64 和 ARM64，缓存于 `${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-devboom/gitstatus`。清理缓存后，重跑 `powerlevel10k` 模块恢复。

## 检查与测试

测试在临时 HOME 中运行，包管理和下载使用模拟命令：

```bash
bash tests/run.sh
git ls-files -z '*.sh' | xargs -0 -n 1 bash -n
```

覆盖系统检测、配置与参数解析、幂等性、配置部署、Shell 初始化、GitHub 加速及下载失败处理。Shell 集成检查需要 Zsh，缺失时跳过；CI 在 Ubuntu 和 macOS 上运行这些检查。

实机复测需检查 `z`、`zi`、fzf 快捷键和 Powerlevel10k Git 状态；NVTOP 的 GPU 数据展示需在具备设备访问权限的环境验证。

## 常见问题

**无权限安装系统包怎么办？** 系统包需要 root 或 sudo；可先部署配置和支持用户级安装的工具。

**已有 `.zshrc` 会被覆盖吗？** 默认保留。用 `--conflict backup` 备份后部署仓库配置，备份路径见日志。

**安装后命令仍找不到？** 重开终端或启动 `zsh`，并检查日志中是否有失败或跳过项。

**插件或主题下载失败怎么办？** 检查日志中的下载地址和网络错误。默认经 ghfast.top 加速，设置 `github_proxy=` 可直连。网络恢复后沿用原配置重跑失败模块，例如：`bash bootstrap.sh --config config/local.conf --non-interactive --allow-remote --modules zsh,powerlevel10k`。

**fzf 已安装，但快捷键不可用？** 运行 `bash bootstrap.sh --non-interactive --modules tools --tools fzf` 补齐 Shell 集成，再重开 Zsh。Debian/Ubuntu 旧版脚本从系统包源获取，无需 `--allow-remote`；若源中已无对应版本，先用原包管理器升级 fzf。

**只安装 Prompt，不接管 Shell 配置？** 只选择 `powerlevel10k`，将 `config/powerlevel10k/p10k.zsh` 复制或链接到 `${ZDOTDIR:-$HOME}/.p10k.zsh`，再参照 `config/zsh/zshrc`，把 instant prompt 和主题、预设的加载语句加入自己的 `.zshrc`。

**如何更新配置或工具？** 更新仓库后重跑所需模块；工具升级使用原包管理器或工具自身的更新命令。
