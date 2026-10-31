#!/bin/sh
# Проверяет тот naive, который сейчас включён в podkop (podkop.main.proxy_string):
# socks5://127.0.0.1:1080 -> config.json, socks5://127.0.0.1:1081 -> config2.json.
# При двух неудачных попытках подряд перезапускает naiveproxy.
URL="https://www.google.com/generate_204"
PROXY="$(uci -q get podkop.main.proxy_string)"
PORT="$(echo "$PROXY" | sed -n "s#^socks5h\?://127\.0\.0\.1:\([0-9]*\).*#\1#p")"
# podkop смотрит не на локальный naive — проверять нечего
[ -n "$PORT" ] || exit 0
check() {
	[ "$(curl -s -m 15 -x socks5h://127.0.0.1:$PORT -o /dev/null -w "%{http_code}" "$URL")" = "204" ]
}
check && exit 0
sleep 10
check && exit 0
logger -t naive-watchdog "port $PORT not responding, restarting naiveproxy"
/etc/init.d/naiveproxy restart
