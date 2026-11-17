# Obsidian LiveSync + CouchDB

Самостоятельный Docker Compose сервер CouchDB для плагина [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync). По умолчанию CouchDB доступна только локально. Для подключения с других устройств используйте HTTPS через Caddy или уже работающий proxy Coolify.

## Содержание

- [Быстрый запуск на этом компьютере](#быстрый-запуск-на-этом-компьютере)
- [Развертывание на VPS](#развертывание-на-vps)
  - [С Coolify](docs/deployment.md#vps-через-coolify)
  - [Без Coolify, с Caddy](docs/deployment.md#vps-без-coolify-https-через-caddy)
- [Резервные копии](#резервные-копии)
- [Состав репозитория](#состав-репозитория)

Перед подключением основного vault сначала проверьте синхронизацию на пустом vault или отдельной копии и сделайте резервную копию важных заметок. Пароль CouchDB и E2EE-пароль LiveSync — разные значения: первый нужен для входа на сервер, второй шифрует данные в плагине.

## Быстрый запуск на этом компьютере

Нужны Docker Engine или Docker Desktop и Docker Compose v2.

```sh
cp .env.example .env
openssl rand -hex 32
```

Скопируйте результат команды в `COUCHDB_PASSWORD` файла `.env`. В шаблоне уже заданы `COUCHDB_USER=obsidian_admin` и `COUCHDB_DATABASE=obsidiannotes`; при желании измените их. Пароль в `.env.example` — заглушка. Храните `.env` в безопасности: этот файл исключён из Git.

Запустите CouchDB и создайте базу:

```sh
chmod 600 .env
docker compose up -d
docker compose ps -a
docker compose logs couchdb-init
```

Для Obsidian на том же компьютере укажите `http://127.0.0.1:15984` и credentials из `.env`. Затем следуйте [инструкции подключения Obsidian](docs/obsidian-setup.md).

CouchDB привязана к localhost и напрямую недоступна другим устройствам. Для телефона или удалённого компьютера разверните сервер на VPS и настройте HTTPS. Если VPS уже управляется Coolify, используйте [инструкцию для Coolify](docs/deployment.md); профиль Caddy этого репозитория включать не нужно.

## Развертывание на VPS

- **С Coolify:** [пошаговая инструкция](docs/deployment.md#vps-через-coolify).
- **Без Coolify:** [инструкция с Caddy](docs/deployment.md#vps-без-coolify-https-через-caddy).

Не открывайте порты CouchDB `5984` и `15984` в публичный интернет. Удалённые устройства должны подключаться по HTTPS.

## Резервные копии

Создать согласованную локальную копию можно командой:

```sh
./scripts/backup.sh
```

Скрипт ненадолго останавливает CouchDB на время архивации volume. Инструкции по расписанию, хранению копий вне сервера и staged restore — в разделе [резервного копирования и восстановления](docs/backup-restore.md). Копия на том же VPS не защищает от потери VPS или диска.

## Состав репозитория

- `docker-compose.yml` — сервисы CouchDB и опциональный Caddy.
- `couchdb/livesync.ini` — single-node режим, CORS и лимиты запросов.
- `scripts/` — инициализация базы, backup и staged restore.
- `.env.example` — шаблон настроек; скопируйте его в `.env`, который исключён из Git.
- `docs/` — инструкции по развертыванию, подключению Obsidian и резервному копированию.
