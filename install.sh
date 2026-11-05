#!/bin/sh
# Установка naive-switch на роутер с OpenWrt. Запускать на роутере:
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/shtiher/naive/main/install.sh)"
# Спрашивает: ставить ли бинарник naive, строки двух серверов, направить ли podkop на naive.

REPO=shtiher/naive
NAIVE_REPO=klzgrad/naiveproxy
TMP=/tmp/naive-install
SYSUPGRADE_PATHS="/usr/bin/naive /usr/bin/naive-switch /usr/bin/naive-failover /etc/init.d/naiveproxy /etc/naiveproxy/
/usr/share/luci/menu.d/luci-app-naive-switch.json /usr/share/rpcd/acl.d/luci-app-naive-switch.json
/www/luci-static/resources/view/naive-switch/"

die() { echo "Ошибка: $*" >&2; exit 1; }

# Вопросы читаем с терминала, чтобы работал и вариант `wget -qO- … | sh`
if (exec </dev/tty) 2>/dev/null; then TTY=/dev/tty; else TTY=/dev/stdin; fi
ask() { printf '%s ' "$1" >&2; read -r ans <"$TTY" || ans=; printf '%s' "$ans"; }
yes_no() {  # yes_no "вопрос" y|n — по умолчанию
    case "$2" in y) hint="[Y/n]";; *) hint="[y/N]";; esac
    a=$(ask "$1 $hint")
    case "${a:-$2}" in y|Y|д|Д|yes|да) return 0;; *) return 1;; esac
}

fetch() { # fetch URL [файл]
    if command -v curl >/dev/null; then
        curl -fsSL "$1" ${2:+-o "$2"}
    else
        wget -qO "${2:--}" "$1"
    fi
}

PKG_UPDATED=
pkg_install() {
    if command -v apk >/dev/null; then
        apk add "$@"
    else
        [ -n "$PKG_UPDATED" ] || { opkg update >/dev/null || die "opkg update не прошёл"; PKG_UPDATED=1; }
        opkg install "$@"
    fi
}

install_naive() {
    . /etc/openwrt_release
    arch=$DISTRIB_ARCH
    echo "Ищу последний релиз naiveproxy для $arch…"
    rel=$(fetch "https://api.github.com/repos/$NAIVE_REPO/releases/latest") || die "не удалось получить список релизов"
    urls=$(echo "$rel" | jsonfilter -e '@.assets[*].browser_download_url')
    url=$(echo "$urls" | grep -- "-openwrt-$arch.tar.xz\$" | head -n1)
    [ -n "$url" ] || url=$(echo "$urls" | grep -- "-openwrt-$arch-static.tar.xz\$" | head -n1)
    [ -n "$url" ] || die "в релизе нет сборки для $arch"

    command -v xz >/dev/null || { echo "Ставлю xz для распаковки…"; pkg_install xz >/dev/null || die "не удалось установить xz"; }

    echo "Скачиваю ${url##*/}…"
    fetch "$url" "$TMP/naive.tar.xz" || die "не удалось скачать"
    mkdir -p "$TMP/naive" && xz -dc "$TMP/naive.tar.xz" | tar xf - -C "$TMP/naive" || die "не удалось распаковать"
    bin=$(find "$TMP/naive" -type f -name naive | head -n1)
    [ -n "$bin" ] && chmod 755 "$bin" && "$bin" --version >/dev/null 2>&1 || die "скачанный naive не запускается на этом роутере"

    # podkop может вести github.com через naive — останавливаем его только на время замены
    cp "$bin" /usr/bin/naive.new || die "не удалось записать /usr/bin/naive"
    /etc/init.d/naiveproxy stop 2>/dev/null || true
    mv /usr/bin/naive.new /usr/bin/naive
    if [ -x /etc/init.d/naiveproxy ]; then /etc/init.d/naiveproxy start; sleep 3; fi
    echo "Установлен $(/usr/bin/naive --version)"
}

set -e
rm -rf "$TMP" && mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

command -v curl >/dev/null || { echo "Ставлю curl…"; pkg_install curl >/dev/null; }

# Файлы naive-switch: из соседнего каталога files/ (если запущено из клона) или с GitHub.
# Качаем до установки naive: пока он перезапускается, GitHub через podkop может быть недоступен.
src=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/files
if [ ! -d "$src/usr/bin" ]; then
    echo "Скачиваю $REPO…"
    fetch "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" "$TMP/repo.tar.gz" || die "не удалось скачать $REPO"
    tar xzf "$TMP/repo.tar.gz" -C "$TMP"
    src=$(ls -d "$TMP"/naive-*/files)
fi

# 1. naive
if [ -x /usr/bin/naive ]; then
    cur=$(/usr/bin/naive --version 2>/dev/null)
    yes_no "naive уже установлен (${cur:-версия неизвестна}). Обновить до последнего релиза?" n && install_naive
else
    yes_no "Установить naive (последний релиз с GitHub)?" y && install_naive
fi

(cd "$src" && tar cf - usr www etc/init.d etc/naiveproxy/*.example) | tar xf - -C /
chmod 755 /usr/bin/naive-switch /usr/bin/naive-failover /etc/init.d/naiveproxy
# Старые версии: watchdog заменён naive-failover, страница servers.js — main.js
rm -f /usr/bin/naive-watchdog.sh /www/luci-static/resources/view/naive-switch/servers.js
sed -i '\#^/usr/bin/naive-watchdog.sh$#d' /etc/sysupgrade.conf
echo "Скрипты и страница LuCI установлены"

# 2. Строки серверов
for n in 1 2; do
    conf=/etc/naiveproxy/config.json
    [ $n = 2 ] && conf=/etc/naiveproxy/config2.json
    if [ -f "$conf" ]; then
        keep="оставить $(naive-switch get $n | sed -e 's#^[a-z+]*://##' -e 's#^.*@##')"
    else
        keep="взять из примера"
    fi
    while :; do
        url=$(ask "Строка сервера $n (https://логин:пароль@хост:443, Enter — $keep):")
        if [ -z "$url" ]; then
            [ -f "$conf" ] || { cp "$conf.example" "$conf"; chmod 600 "$conf"; }
            break
        fi
        naive-switch write $n "$url" && break
    done
done

# Автозапуск, автоматика (naive-failover), сохранение при sysupgrade
for p in $SYSUPGRADE_PATHS; do
    grep -qxF "$p" /etc/sysupgrade.conf || echo "$p" >> /etc/sysupgrade.conf
done
(crontab -l 2>/dev/null | grep -v -e naive-watchdog -e naive-failover; echo "* * * * * /usr/bin/naive-failover") | crontab -
/etc/init.d/cron restart >/dev/null 2>&1 || true
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
/etc/init.d/rpcd reload
if [ -x /usr/bin/naive ]; then
    /etc/init.d/naiveproxy enable
    /etc/init.d/naiveproxy restart
    sleep 3
    echo "naiveproxy запущен"
else
    echo "Внимание: /usr/bin/naive нет — служба не запущена. Повторите установку и согласитесь поставить naive."
fi

# 3. podkop
if uci -q get podkop.main >/dev/null; then
    if yes_no "Направить podkop на naive?" y; then
        s=$(ask "Какой сервер, 1 или 2? [1]")
        case "$s" in 2) ;; *) s=1;; esac
        cp -p /etc/config/podkop "/etc/naiveproxy/podkop.bak-$(date +%Y-%m-%d-%H%M)"
        uci set podkop.main.connection_type=proxy
        uci set podkop.main.proxy_config_type=url
        uci commit podkop
        naive-switch $s
    fi
else
    echo "podkop не найден (нет секции podkop.main) — шаг пропущен. После его установки: naive-switch 1"
fi

echo
naive-switch status
echo
echo "Готово. Страница: LuCI → Службы → Naive; консоль: naive-switch"
