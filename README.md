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
- `files/usr/bin/naive-watchdog.sh` — каждые 5 минут (cron) проверяет активный экземпляр и после двух неудач подряд перезапускает naiveproxy.
- LuCI-страница **Службы → Naive**: статус, строки подключения обоих серверов с кнопкой «Сохранить и перезапустить», переключение podkop.

## Установка

1. Положить бинарник naive для своей архитектуры в `/usr/bin/naive` (релизы `naiveproxy-*-openwrt-*`).
2. С компьютера:

   ```sh
   ./install.sh root@192.168.1.1            # можно дописать ssh-опции, например -i ~/.ssh/key
   ```

   Скрипт копирует файлы, добавляет их в `/etc/sysupgrade.conf`, ставит watchdog в cron и включает службу. Существующие `config*.json` не перезаписываются; если их нет, создаются из `*.example`.
3. Вписать строки серверов на странице **Службы → Naive** (или `naive-switch set 1 'https://…'`) и выбрать сервер.

## Заметки

- Chrome кэширует файлы LuCI-страниц по версии LuCI (`?v=…`). Если после изменения `servers.js` браузер показывает старую страницу, переименуйте файл и поправьте `path` в `menu.d`.
- podkop работает только с IPv4: IPv6-трафик устройств идёт мимо прокси.
