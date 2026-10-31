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
- `files/usr/bin/naive-watchdog.sh` — каждые 5 минут (cron) проверяет активный экземпляр и после двух неудач подряд перезапускает naiveproxy.
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

Ещё он ставит `curl`, если его нет, копирует скрипты и страницу LuCI, добавляет все пути (включая `/usr/bin/naive`) в `/etc/sysupgrade.conf`, ставит watchdog в cron, включает и запускает службу. Повторный запуск безопасен — так же обновляются скрипты.

Из клона репозитория на роутере можно запустить `sh install.sh` — тогда файлы берутся из соседнего `files/`, а не с GitHub.

## Заметки

- Chrome кэширует файлы LuCI-страниц по версии LuCI (`?v=…`). Если после изменения `servers.js` браузер показывает старую страницу, переименуйте файл и поправьте `path` в `menu.d`.
- podkop работает только с IPv4: IPv6-трафик устройств идёт мимо прокси.
