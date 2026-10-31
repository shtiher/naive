#!/bin/sh
# Установка на роутер с OpenWrt по SSH: ./install.sh [root@192.168.1.1] [ssh-опции...]
# Бинарник /usr/bin/naive и рабочие конфиги /etc/naiveproxy/config*.json не трогает.
set -e
host=${1:-root@192.168.1.1}
[ $# -gt 0 ] && shift
cd "$(dirname "$0")/files"

tar cf - usr www etc/init.d etc/naiveproxy/*.example | ssh "$@" "$host" '
	set -e
	tar xf - -C /
	chmod 755 /usr/bin/naive-switch /usr/bin/naive-watchdog.sh /etc/init.d/naiveproxy
	for n in config config2; do
		[ -f /etc/naiveproxy/$n.json ] || { cp /etc/naiveproxy/$n.json.example /etc/naiveproxy/$n.json; chmod 600 /etc/naiveproxy/$n.json; }
	done
	for p in /usr/bin/naive-switch /usr/bin/naive-watchdog.sh /etc/init.d/naiveproxy /etc/naiveproxy/ \
	         /usr/share/luci/menu.d/luci-app-naive-switch.json /usr/share/rpcd/acl.d/luci-app-naive-switch.json \
	         /www/luci-static/resources/view/naive-switch/; do
		grep -qxF "$p" /etc/sysupgrade.conf || echo "$p" >> /etc/sysupgrade.conf
	done
	crontab -l 2>/dev/null | grep -q naive-watchdog || { (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/naive-watchdog.sh") | crontab -; }
	/etc/init.d/naiveproxy enable
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
	/etc/init.d/rpcd reload
	echo "установлено; если /usr/bin/naive уже есть — /etc/init.d/naiveproxy restart"
'
