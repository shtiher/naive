'use strict';
'require view';
'require fs';
'require ui';

function run(args) {
	return fs.exec('/usr/bin/naive-switch', Array.isArray(args) ? args : [ args ]).then(function(res) {
		return (res.stdout || '') + (res.stderr || '');
	}).catch(function(e) {
		return 'Ошибка: ' + e.message;
	});
}

function hostOf(url) {
	return (url || '').replace(/^[a-z+]*:\/\//, '').replace(/^.*@/, '').replace(/[:\/].*$/, '') || '?';
}

return view.extend({
	load: function() {
		return Promise.all([ run('status'), run([ 'get', '1' ]), run([ 'get', '2' ]), run('auto') ]);
	},

	setAuto: function(on) {
		this.busy('Автоматика…', on ? 'Включаю автоматический выбор сервера' : 'Выключаю автоматику');
		return run([ 'auto', on ? 'on' : 'off' ]).then(L.bind(this.refresh, this));
	},

	goDirect: function() {
		if (!confirm('Пустить трафик podkop напрямую, без naive? Автоматика при этом выключится.'))
			return;
		this.busy('Переключение…', 'Перевожу podkop.main в режим «напрямую»');
		return run('direct').then(L.bind(this.refresh, this));
	},

	busy: function(title, text) {
		ui.showModal(title, [ E('p', { 'class': 'spinning' }, text) ]);
	},

	switchTo: function(n) {
		this.busy('Переключение…', 'Переключаю podkop на сервер ' + n + ' и проверяю связь');
		return run(String(n)).then(L.bind(this.refresh, this));
	},

	restartNaive: function() {
		this.busy('Перезапуск…', 'Перезапускаю сервис naiveproxy и проверяю связь');
		return run('restart').then(L.bind(function(st) {
			this.out.textContent = st;
			ui.hideModal();
		}, this));
	},

	saveConfig: function(n, input) {
		var url = input.value.trim();
		if (!/^(naive\+)?(https|quic):\/\/[^@\/]+@[^@\/]+/.test(url)) {
			ui.addNotification(null, E('p', 'Сервер ' + n + ': нужна строка вида https://логин:пароль@хост:443'), 'warning');
			return;
		}
		this.busy('Сохранение…', 'Записываю конфиг сервера ' + n + ', перезапускаю naiveproxy и проверяю связь');
		return run([ 'set', String(n), url ]).then(L.bind(function(res) {
			ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, res),
				/Ошибка|НЕ ОТВЕЧАЕТ/.test(res) ? 'warning' : 'info');
			return this.refresh();
		}, this));
	},

	refresh: function() {
		this.out.textContent = 'Проверяю…';
		return Promise.all([ run('status'), run([ 'get', '1' ]), run([ 'get', '2' ]), run('auto') ]).then(L.bind(function(r) {
			this.out.textContent = r[0];
			this.autoOut.textContent = r[3];
			for (var n = 1; n <= 2; n++) {
				this.inputs[n].value = r[n].trim();
				this.labels[n].textContent = 'Сервер ' + n + ': ' + hostOf(r[n].trim());
			}
			ui.hideModal();
		}, this));
	},

	serverSection: function(n, url) {
		var self = this;
		var input = E('input', {
			'type': 'password', 'class': 'cbi-input-text', 'value': url,
			'style': 'width:100%;font-family:monospace', 'autocomplete': 'off', 'spellcheck': 'false',
			'placeholder': 'https://логин:пароль@хост:443'
		});
		var label = E('span', {}, 'Сервер ' + n + ': ' + hostOf(url));
		this.inputs[n] = input;
		this.labels[n] = label;

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ label, E('small', { 'style': 'font-weight:normal' }, n == 1 ? '  socks 127.0.0.1:1080' : '  socks 127.0.0.1:1081') ]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, 'Строка proxy'),
				E('div', { 'class': 'cbi-value-field' }, [
					E('div', { 'style': 'display:flex;gap:.5em' }, [
						input,
						E('button', { 'class': 'cbi-button', 'click': function() {
							input.type = (input.type == 'password') ? 'text' : 'password';
						} }, 'Показать')
					]),
					E('div', { 'class': 'cbi-value-description' },
						'Можно вставить ссылку naive+https://…#имя — префикс и имя отбросятся. Прежний конфиг сохраняется в ' +
						(n == 1 ? 'config.json.prev' : 'config2.json.prev') + '.')
				])
			]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button cbi-button-save', 'click': function() { return self.saveConfig(n, input); } },
					'Сохранить и перезапустить'), ' ',
				E('button', { 'class': 'cbi-button cbi-button-action', 'click': function() { return self.switchTo(n); } },
					'Направить podkop сюда')
			])
		]);
	},

	render: function(data) {
		var self = this;
		this.inputs = {};
		this.labels = {};
		this.out = E('pre', { 'style': 'white-space:pre-wrap' }, data[0]);
		this.autoOut = E('pre', { 'style': 'white-space:pre-wrap' }, data[3]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'Naive'),
			E('div', { 'class': 'cbi-map-descr' },
				'Через какой сервер naive podkop отправляет трафик из списка, и строки подключения обоих серверов.'),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, 'Статус'),
				this.out,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'cbi-button', 'click': function() { return self.refresh(); } }, 'Обновить статус'), ' ',
					E('button', { 'class': 'cbi-button cbi-button-reset', 'click': function() { return self.restartNaive(); } },
						'Перезапустить naive')
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, 'Автоматика (naive-failover, проверка раз в минуту)'),
				E('div', { 'class': 'cbi-section-descr' },
					'Сервер 1 в приоритете, при отказе — сервер 2, если отказали оба — трафик podkop идёт напрямую. ' +
					'Сервер снова заработал — podkop возвращается на него. Нет интернета — ничего не меняется. ' +
					'Если naive работает, а трафик через podkop/sing-box не идёт — podkop перезапускается. ' +
					'Ручное переключение выключает автоматику.'),
				this.autoOut,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'cbi-button cbi-button-apply', 'click': function() { return self.setAuto(true); } }, 'Включить автоматику'), ' ',
					E('button', { 'class': 'cbi-button', 'click': function() { return self.setAuto(false); } }, 'Выключить автоматику'), ' ',
					E('button', { 'class': 'cbi-button cbi-button-negative', 'click': function() { return self.goDirect(); } }, 'Напрямую (без naive)')
				])
			]),
			this.serverSection(1, data[1].trim()),
			this.serverSection(2, data[2].trim())
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
