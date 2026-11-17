#!/bin/bash
set -euo pipefail

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ $(/usr/bin/uname -s) == Darwin ]] || fail '此方案仅支持 macOS。'
[[ $(/usr/bin/id -u) != 0 ]] || fail '请在当前 macOS 用户的终端运行，无需 sudo。'

label=local.codex.cua-clash
domain="gui/$(/usr/bin/id -u)"
service="$domain/$label"
wrapper="$HOME/.local/bin/codex-cua-clash"
agent="$HOME/Library/LaunchAgents/$label.plist"
override=CODEX_NODE_REPL_PATH
marker='# Managed by codex-cua-clash/setup-macos.sh'

case "${1:-install}" in
    uninstall)
        [[ $# == 1 ]] || fail '用法: bash setup-macos.sh uninstall'
        [[ -f "$wrapper" && ! -L "$wrapper" && -f "$agent" && ! -L "$agent" ]] || fail '找不到这套方案安装的两个文件。'
        /usr/bin/grep -Fxq "$marker" "$wrapper" || fail "脚本不是由此安装包管理的：$wrapper"
        [[ $(/usr/bin/plutil -extract Label raw -o - "$agent") == "$label" &&
           $(/usr/bin/plutil -extract ProgramArguments.3 raw -o - "$agent") == "$wrapper" ]] || fail "登录项与安装包不匹配：$agent"
        if /bin/launchctl print "$service" >/dev/null 2>&1; then
            /bin/launchctl bootout "$service"
        fi
        if [[ $(/bin/launchctl getenv "$override") == "$wrapper" ]]; then
            /bin/launchctl unsetenv "$override"
        fi
        /bin/rm "$agent" "$wrapper"
        printf '已卸载。完全退出 Codex 后从 Dock 重开即可。\n'
        exit 0
        ;;
    install) ;;
    *) fail '用法: bash setup-macos.sh install [Clash HTTP 端口] 或 bash setup-macos.sh uninstall' ;;
esac

[[ $# -le 2 ]] || fail '用法: bash setup-macos.sh install [Clash HTTP 端口]'
port=${2:-7890}
[[ $port =~ ^[1-9][0-9]{0,4}$ ]] && (( port <= 65535 )) || fail '请输入 1 到 65535 的端口号。'

if [[ -e "$wrapper" || -L "$wrapper" || -e "$agent" || -L "$agent" ]]; then
    fail '配置文件已存在。若需要更换端口，请先运行 bash setup-macos.sh uninstall。'
fi
[[ -z $(/bin/launchctl getenv "$override") ]] || fail '已有 CODEX_NODE_REPL_PATH 设置，请先核对现有配置。'
if /bin/launchctl print "$service" >/dev/null 2>&1; then
    fail "登录项已存在：$service"
fi

app=
for candidate in /Applications/Codex.app /Applications/ChatGPT.app "$HOME/Applications/Codex.app" "$HOME/Applications/ChatGPT.app"; do
    if [[ -x "$candidate/Contents/Resources/cua_node/bin/node_repl" ]] &&
       /usr/bin/grep -aq CODEX_NODE_REPL_PATH "$candidate/Contents/Resources/app.asar"; then
        [[ -z "$app" ]] || fail '找到多个兼容的 Codex 应用，无法自动确定 Dock 中使用的是哪一个。'
        app=$candidate
    fi
done
[[ -n "$app" ]] || fail '未在 Applications 中找到带所需运行组件的 Codex 桌面版。'
/usr/bin/nc -z -G 2 127.0.0.1 "$port" || fail "无法连接 127.0.0.1:$port，请启动 Clash 并核对 HTTP 或混合端口。"

/bin/mkdir -p "${wrapper%/*}" "${agent%/*}"
staging=$(/usr/bin/mktemp -d)
installed=0
loaded=0
cleanup() {
    if [[ $installed == 0 ]]; then
        if [[ $loaded == 1 ]]; then
            /bin/launchctl bootout "$service" || true
            if [[ $(/bin/launchctl getenv "$override") == "$wrapper" ]]; then
                /bin/launchctl unsetenv "$override" || true
            fi
        fi
        /bin/rm -f "$agent" "$wrapper"
    fi
    /bin/rm -rf "$staging"
}
trap cleanup EXIT

{
    printf '#!/bin/bash\n%s\nset -eu\n' "$marker"
    printf 'proxy_url=%q\n' "http://127.0.0.1:$port"
    /bin/cat <<'WRAPPER'

case ",${CUA_REPL_ENABLED_SURFACES:-}," in
    *,browser,*)
        export HTTPS_PROXY="$proxy_url" https_proxy="$proxy_url"
        bypass="${NO_PROXY:-${no_proxy:-}}"
        export NO_PROXY="${bypass:+$bypass,}localhost,127.0.0.1,::1,[::1]"
        export no_proxy="$NO_PROXY" NODE_USE_ENV_PROXY=1
        # node_repl only forwards explicitly allowed variables to its Node worker.
        allowlist="${NODE_REPL_UNTRUSTED_ENV_ALLOWLIST:-}"
        export NODE_REPL_UNTRUSTED_ENV_ALLOWLIST="${allowlist:+$allowlist,}HTTPS_PROXY,https_proxy,NO_PROXY,no_proxy,NODE_USE_ENV_PROXY"
        ;;
esac
WRAPPER
    printf '\nexec %q "$@"\n' "$app/Contents/Resources/cua_node/bin/node_repl"
} > "$staging/wrapper"

plist="$staging/agent.plist"
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert Label -string "$label" "$plist"
/usr/bin/plutil -insert ProgramArguments -json '["/bin/launchctl","setenv","CODEX_NODE_REPL_PATH"]' "$plist"
/usr/bin/plutil -insert ProgramArguments.3 -string "$wrapper" "$plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$plist"
/usr/bin/plutil -lint "$plist" >/dev/null
/bin/bash -n "$staging/wrapper"
/usr/bin/install -m 700 "$staging/wrapper" "$wrapper"
/usr/bin/install -m 644 "$plist" "$agent"
/bin/launchctl bootstrap "$domain" "$agent"
loaded=1
for attempt in {1..30}; do
    if [[ $(/bin/launchctl getenv "$override") == "$wrapper" ]]; then
        installed=1
        printf '已配置 %s，代理为 127.0.0.1:%s。\n请用 ⌘Q 完全退出 Codex，再从 Dock 正常打开。\n' "$app" "$port"
        exit 0
    fi
    /bin/sleep 0.1
done
fail '登录项未设置运行路径，已撤回本次安装。'
