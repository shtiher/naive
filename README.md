# naive

Два экземпляра [naiveproxy](https://github.com/klzgrad/naiveproxy) на роутере с OpenWrt и переключение между ними для [podkop](https://github.com/itdoginfo/podkop), из консоли и из LuCI.

| Сервер | Конфиг | SOCKS |
|---|---|---|
| 1 | `/etc/naiveproxy/config.json` | `127.0.0.1:1080` |
| 2 | `/etc/naiveproxy/config2.json` | `127.0.0.1:1081` |

podkop отправляет трафик в тот SOCKS, который записан в `podkop.main.proxy_string`.

## Состав

- `files/etc/init.d/naiveproxy` — служба procd, запускает оба экземпляра.
- `files/usr/bin/naive-switch` — переключение и настройка:
  - `naive-switch 1|2` — направить podkop на сервер 1 или 2;
  - `naive-switch status` — какой сервер активен и отвечают ли оба;
  - `naive-switch restart` — перезапустить naiveproxy;
  - `naive-switch get 1|2` — показать строку proxy сервера;
  - `naive-switch set 1|2 URL` — записать новую строку (`https://логин:пароль@хост:443`, можно `naive+https://…#имя`); прежний конфиг сохраняется в `config*.json.prev`, naiveproxy перезапускается.
  - `naive-switch write 1|2 URL` — то же без перезапуска (использует установщик);
  - `naive-switch direct` — пустить трафик `podkop.main` напрямую (секция в режиме `exclusion`);
  - `naive-switch auto on|off` — включить/выключить автоматику; `naive-switch auto` — её последний статус.
  Ручные `1|2|direct` выключают автоматику, чтобы она не перебивала выбор.
- `files/usr/bin/naive-failover` — автоматика, cron раз в минуту:
  - сервер 1 в приоритете, при отказе — сервер 2, отказали оба — `podkop.main` идёт напрямую (`exclusion`);
  - сервер снова отвечает 2 проверки подряд — podkop возвращается на него (1 приоритетнее 2);
  - нет интернета совсем (ya.ru, 77.88.8.8, 1.1.1.1) — ничего не меняет;
  - оба сервера не отвечают — сначала перезапускает naiveproxy (не чаще раза в 15 мин);
  - naive отвечает, а трафик не идёт через sing-box (проверка `main-out` через clash API `:9090`), DNS не отдаёт fakeip или нет таблицы nft — перезапускает podkop (не чаще раза в 10 мин);
  - при выключенной автоматике (`naive-switch auto off`) только проверяет и пишет статус, ничего не переключает и не перезапускает;
  - статус: `/tmp/naive-failover/status`, JSON: `naive-failover json` (`/tmp/naive-failover/state.json`), история: `/tmp/naive-failover/history`, события — в `logread -e naive-failover`.
- `files/usr/bin/naive-ha` — команды для Home Assistant по SSH. Ключ HA добавляется в `/etc/dropbear/authorized_keys` с привязкой к скрипту, поэтому им можно выполнить только `status` (JSON), `vpn on` (включить автоматику и сразу уйти на рабочий сервер) и `vpn off` (podkop напрямую, автоматика выключена):

  ```
  command="/usr/bin/naive-ha",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA… homeassistant
  ```

  Пример пакета для HA (датчик статуса, датчики серверов и интернета, выключатель VPN) — `homeassistant/vpn.yaml`.
- LuCI-страница **Службы → Naive**: статус, строки подключения обоих серверов с кнопкой «Сохранить и перезапустить», переключение podkop.

## Установка

В терминале роутера (по SSH):

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/shtiher/naive/main/install.sh)"
```

Установщик спросит:

1. **Установить naive?** Скачивает последний релиз [naiveproxy](https://github.com/klzgrad/naiveproxy/releases) под архитектуру роутера (`DISTRIB_ARCH`), при необходимости ставит `xz` для распаковки. Если naive уже есть, предлагает обновить (по умолчанию нет).
2. **Строки серверов 1 и 2** (`https://логин:пароль@хост:443` или `naive+https://…#имя`). Enter — оставить текущую; если конфига ещё нет — взять из `*.example` (потом вписать на странице LuCI).
3. **Направить podkop на naive?** Переводит podkop в режим proxy/url и выбирает сервер 1 или 2. Прежний `/etc/config/podkop` сохраняется в `/etc/naiveproxy/podkop.bak-*`. Если podkop не установлен, шаг пропускается.

Ещё он ставит `curl`, если его нет, копирует скрипты и страницу LuCI, добавляет все пути (включая `/usr/bin/naive`) в `/etc/sysupgrade.conf`, ставит `naive-failover` в cron (раз в минуту, старый `naive-watchdog.sh` удаляется), включает и запускает службу. Повторный запуск безопасен — так же обновляются скрипты.

Из клона репозитория на роутере можно запустить `sh install.sh` — тогда файлы берутся из соседнего `files/`, а не с GitHub.

## Заметки

- Chrome кэширует файлы LuCI-страниц по версии LuCI (`?v=…`). Если после изменения `naive.js` (раньше `servers.js`, `main.js`) браузер показывает старую страницу, переименуйте файл и поправьте `path` в `menu.d`.
- podkop работает только с IPv4: IPv6-трафик устройств идёт мимо прокси.
