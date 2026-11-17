# Развертывание

## Содержание

- [Локальный стенд](#локальный-стенд)
- [VPS через Coolify](#vps-через-coolify)
  - [Подготовьте домен](#1-подготовьте-домен)
  - [Создайте приложение в Coolify](#2-создайте-приложение-в-coolify)
  - [Задайте логин и пароль сервера](#3-задайте-логин-и-пароль-сервера)
  - [Подключите домен и HTTPS](#4-подключите-домен-и-https)
  - [Запустите сервер и проверьте доступ](#5-запустите-сервер-и-проверьте-доступ)
  - [Подключите Obsidian](#6-подключите-obsidian)
  - [Резервная копия](#резервная-копия)
- [VPS без Coolify: HTTPS через Caddy](#vps-без-coolify-https-через-caddy)
  - [Подготовьте VPS и DNS](#1-подготовьте-vps-и-dns)
  - [Установите Docker Engine и Compose](#2-установите-docker-engine-и-compose)
  - [Скопируйте репозиторий на VPS](#3-скопируйте-репозиторий-на-vps)
  - [Создайте production `.env`](#4-создайте-production-env)
  - [Проверьте конфигурацию и запустите Compose](#5-проверьте-конфигурацию-и-запустите-compose)
  - [Проверьте здоровье, базу и HTTPS](#6-проверьте-здоровье-базу-и-https)
  - [Подключите Obsidian](#7-подключите-obsidian)
  - [Настройте backup и остановку](#8-настройте-backup-и-остановку)
  - [Если HTTPS не запускается](#если-https-не-запускается)
- [Обновление CouchDB](#обновление-couchdb)

## Локальный стенд

1. Скопируйте `.env.example` в `.env`.
2. Создайте пароль командой `openssl rand -hex 32` и вставьте его в `COUCHDB_PASSWORD`.
3. Ограничьте доступ к файлу: `chmod 600 .env`.
4. Запустите `docker compose up -d`.
5. Проверьте `docker compose ps -a` и `docker compose logs couchdb-init`.

CouchDB слушает `5984` в контейнере, но Docker публикует его на `127.0.0.1:${COUCHDB_PORT}` на хосте. Настройки `.ini` включают single-node режим, обязательную авторизацию после первичной инициализации, CORS для Obsidian и лимиты, применённые в локальном стенде.

Если база была удалена вручную, запустите идемпотентный init-сервис ещё раз:

```sh
docker compose run --rm couchdb-init
```

## VPS через Coolify

Эта инструкция предназначена владельцу Obsidian vault, который разворачивает личный сервер LiveSync из этого репозитория. Предполагается, что Coolify уже установлен на VPS. Домен будет вести на ваш сервер, а Coolify proxy обеспечит HTTPS. Профиль `public` и Caddy включать не нужно.

### 1. Подготовьте домен

Выберите поддомен, например `sync.example.com`, и создайте у DNS-провайдера запись `A` с IP вашего VPS. Запись `AAAA` добавляйте, только если на VPS работает публичный IPv6. В firewall VPS разрешите входящий TCP `80` и `443` для Coolify proxy.

### 2. Создайте приложение в Coolify

В Coolify откройте **Project** и **Environment**, выберите **+ New → Application** и укажите Git-репозиторий, в котором находится этот файл. Если репозиторий приватный, сначала подключите Git-провайдера в Coolify. Выберите нужную ветку, тип **Docker Compose** и Compose-файл `docker-compose.yml` в корне репозитория. Создайте приложение; отдельную Coolify Database добавлять не нужно.

### 3. Задайте логин и пароль сервера

Откройте созданное приложение → **Environment Variables** и добавьте значения для production:

| Переменная | Что указать |
| --- | --- |
| `COUCHDB_USER` | `obsidian_admin` или своё имя пользователя |
| `COUCHDB_PASSWORD` | новый пароль, созданный локально командой `openssl rand -hex 32` |
| `COUCHDB_DATABASE` | `obsidiannotes` или своё имя базы |

Отметьте пароль как секретный, если Coolify предлагает такую настройку. Пароль в `.env.example` — заглушка, использовать её нельзя. Не добавляйте credentials в Git. Для одного сервера оставьте остальные параметры по умолчанию, включая `COUCHDB_VOLUME_EXTERNAL=false`. `COUCHDB_DOMAIN` и `COUCHDB_PORT` для настройки домена Coolify не нужны.

### 4. Подключите домен и HTTPS

В приложении откройте **Domains → Add Domain**:

1. В поле домена укажите `https://sync.example.com`, заменив пример на свой поддомен.
2. Для Docker Compose выберите сервис `couchdb` и внутренний порт `5984`.
3. Сохраните домен и включите перенаправление HTTP на HTTPS, если Coolify показывает эту настройку.

Устройства будут подключаться к `https://sync.example.com` без `:5984`. Coolify proxy сам запросит TLS-сертификат, если DNS указывает на VPS и входящие порты `80/443` доступны ([настройка доменов Coolify](https://coolify.io/docs/core/networking/domains)). Не открывайте порты `5984` и `15984` в firewall.

### 5. Запустите сервер и проверьте доступ

Нажмите **Deploy**. В логах дождитесь, пока `couchdb` станет healthy, а `couchdb-init` успешно завершится. Этот init-шаг создаёт базу для LiveSync. В Coolify завершённый `couchdb-init` может отображаться как остановленный одноразовый контейнер — это нормально, если его логи показывают успех.

Проверьте адрес с компьютера:

```sh
curl -Iv https://sync.example.com/
```

Проверьте авторизацию и health endpoint. Команда запросит пароль; если вы задали другое имя пользователя, замените `obsidian_admin`:

```sh
curl -fsS --user obsidian_admin https://sync.example.com/_up
```

Без credentials CouchDB должна отвечать `401`.

### 6. Подключите Obsidian

1. Установите плагин Self-hosted LiveSync в Obsidian и откройте Quick Setup / Onboarding.
2. Введите URL `https://sync.example.com`, имя пользователя, пароль и имя базы, заданные в Coolify.
3. Задайте E2EE-пароль LiveSync. Он шифрует заметки на стороне Obsidian и не является паролем CouchDB; сохраните его отдельно, он понадобится каждому вашему устройству.
4. Завершите onboarding, затем синхронизируйте тестовую заметку и вложение.
5. На втором устройстве установите плагин с теми же настройками и подключитесь к существующей базе через Fetch/Join.

Не подключайте рабочий vault, пока тестовая синхронизация не подтверждена. Подробности — в [инструкции по подключению Obsidian](obsidian-setup.md).

### Резервная копия

Persistent volume сохраняет базу при redeploy приложения, но сам по себе не является резервной копией. До подключения рабочего vault настройте в Coolify или отдельно резервное копирование данных и проверьте восстановление.

## VPS без Coolify: HTTPS через Caddy

Используйте эту ветку, только если на сервере нет другого reverse proxy, который уже занимает `80/443`. В `.env` задайте реальный `COUCHDB_DOMAIN`. До запуска домен должен указывать на VPS, а TCP 80/443 должны быть доступны Caddy. Запустите:

Ниже — инструкция для **свежего Ubuntu Server 24.04 LTS**. Для Debian используйте соответствующий Docker apt repository из [официальной инструкции](https://docs.docker.com/engine/install/debian/). Предполагается, что у вас есть домен и доступ к DNS и firewall VPS.

### 1. Подготовьте VPS и DNS

1. Создайте VPS с публичным IPv4. Добавьте DNS-запись `A` для поддомена, например `sync.example.com`, указывающую на IPv4 VPS.
2. Добавляйте `AAAA` только если на VPS настроена доступная извне IPv6-сеть. Уберите устаревшую AAAA-запись: Caddy и клиенты могут выбирать неверный адрес.
3. В firewall панели VPS разрешите входящий TCP `22` только с вашего адреса управления, а TCP `80` и `443` — для всех адресов. Если используете другой SSH-порт, разрешите его вместо `22`.
4. Не открывайте наружу `5984` или `15984`. В этом Compose CouchDB публикуется только на `127.0.0.1:15984`; удалённые устройства подключаются через Caddy по HTTPS.

Проверьте DNS с локального компьютера:

```sh
dig +short A sync.example.com
dig +short AAAA sync.example.com
```

Перед запуском убедитесь, что порты `80` и `443` свободны: Caddy должен принимать на них трафик. Не останавливайте существующий веб-сервер, пока не выяснили, что он обслуживает.

### 2. Установите Docker Engine и Compose

Если Docker Engine и Compose уже установлены, проверьте версии и переходите к следующему шагу:

```sh
sudo docker --version
sudo docker compose version
```

Если Docker Engine уже есть, но `docker compose version` не работает, установите Compose plugin по [официальной инструкции](https://docs.docker.com/compose/install/linux/). На чистом Ubuntu Server установите Docker Engine и Compose по [официальной инструкции Docker](https://docs.docker.com/engine/install/ubuntu/):

```sh
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
```

Используйте `sudo` для Docker-команд. Членство в группе `docker` фактически даёт права уровня root. Не удаляйте существующие Docker-пакеты, контейнеры или данные вслепую: сначала выясните, использует ли их сервер.

### 3. Скопируйте репозиторий на VPS

На VPS создайте каталог для проекта от имени SSH-пользователя:

```sh
sudo install -d -o "$(id -un)" -g "$(id -gn)" /opt/livesync-couchdb
```

На локальном компьютере, из корня этого репозитория, скопируйте файлы. Замените `deploy` и `VPS_IP` на SSH-пользователя и адрес вашего VPS:

```sh
rsync -av --exclude='.env' --exclude='backups/' ./ deploy@VPS_IP:/opt/livesync-couchdb/
```

Исключение `.env` не переносит локальные credentials на сервер. Затем подключитесь к VPS и перейдите в каталог:

```sh
ssh deploy@VPS_IP
cd /opt/livesync-couchdb
```

Compose-проект задаёт фиксированные имена `livesync-couchdb` и `livesync-couchdb-data`. Эта инструкция рассчитана на одну установку на чистом Docker-хосте. Если на VPS уже есть такой контейнер или volume, сначала проверьте их и сделайте backup; новый запуск может повторно использовать существующий volume.

### 4. Создайте production `.env`

В корне проекта на VPS выполните:

```sh
cp .env.example .env
openssl rand -hex 32
nano .env
```

Вставьте сгенерированное значение в `COUCHDB_PASSWORD`, задайте ваш домен в `COUCHDB_DOMAIN`, например `sync.example.com`. В шаблоне `COUCHDB_USER=obsidian_admin` и `COUCHDB_DATABASE=obsidiannotes`; их можно оставить или заменить. Пароль в шаблоне — заглушка, использовать её нельзя. Оставьте `COUCHDB_VOLUME_EXTERNAL=false` и `COUCHDB_PORT=15984`.

Ограничьте права и проверьте, что Git игнорирует файл:

```sh
chmod 600 .env
grep -Fx .env .gitignore
```

`COUCHDB_USER`, `COUCHDB_PASSWORD` и `COUCHDB_DATABASE` понадобятся для подключения Obsidian. E2EE-пароль LiveSync задаётся отдельно в плагине и не должен совпадать с паролем CouchDB. Не отправляйте `.env` в Git или мессенджер. Setup URI может содержать конфиденциальные настройки — передавайте его только защищённым способом.

### 5. Проверьте конфигурацию и запустите Compose

Убедитесь, что `COUCHDB_DOMAIN` совпадает с DNS-именем, затем проверьте Compose-конфигурацию и запустите VPS-профиль:

```sh
sudo docker compose --profile public config -q
sudo docker compose --profile public up -d
```

Профиль `public` запускает Caddy на публичных портах `80/443`. Caddyfile направляет запросы домена к `couchdb:5984` внутри Docker-сети. Порт CouchDB напрямую наружу не публикуется. Caddy обеспечивает HTTPS, но не заменяет авторизацию CouchDB. При рабочем DNS и доступных снаружи портах Caddy автоматически получает и продлевает публичный TLS-сертификат ([требования Caddy](https://caddyserver.com/docs/automatic-https)).

### 6. Проверьте здоровье, базу и HTTPS

```sh
sudo docker compose --profile public ps -a
sudo docker compose logs --tail=100 couchdb-init caddy
curl -Iv https://sync.example.com/
```

Ожидается `couchdb` со статусом `healthy`, завершившийся с кодом `0` `couchdb-init` и успешная TLS-проверка `curl` без ошибки сертификата. Ответ `401` без credentials допустим и подтверждает, что запрос дошёл до CouchDB с включённой авторизацией. Проверьте, что в логах Caddy нет ошибок DNS или получения сертификата.

При необходимости проверьте CouchDB health endpoint: замените имя пользователя на своё; `curl` запросит пароль интерактивно:

```sh
curl -fsS --user obsidian_admin https://sync.example.com/_up
```

Панель firewall провайдера должна оставаться ограниченной портами SSH, `80` и `443`. Docker может направлять опубликованный container-порт в обход правил UFW; не полагайтесь только на UFW и не публикуйте дополнительные порты без проверки ([Docker и firewall](https://docs.docker.com/engine/network/packet-filtering-firewalls/#docker-and-ufw)).

### 7. Подключите Obsidian

1. Сначала используйте **пустой тестовый vault** или отдельную копию рабочих заметок.
2. Установите Self-hosted LiveSync, откройте Quick Setup / Onboarding и используйте URL `https://sync.example.com` без порта.
3. Введите `COUCHDB_USER`, `COUCHDB_PASSWORD` и `COUCHDB_DATABASE` из `.env`, затем настройте отдельный E2EE-пароль LiveSync и сохраните его в защищённом месте.
4. Синхронизируйте тестовую заметку и вложение; проверьте их на втором тестовом устройстве.
5. На дополнительных устройствах присоединяйтесь к уже созданной базе через Fetch/Join. Не запускайте Rebuild и не выбирайте перезапись сервера без проверенной копии данных.

Подробные шаги мастера, selector и безопасного подключения второго устройства — в [инструкции Obsidian](obsidian-setup.md). Не подключайте рабочий vault, пока тестовый обмен файлами не подтверждён.

### 8. Настройте backup и остановку

Создайте первую резервную копию и сохраните её также вне VPS:

```sh
sudo ./scripts/backup.sh
```

Backup-скрипт архивирует CouchDB volume, но не включает `.env` и Caddy volumes. Храните credentials отдельно в зашифрованном хранилище; подробности staged restore и перечень сохраняемых данных — в [инструкции backup/restore](backup-restore.md).

Для остановки сервисов без удаления данных:

```sh
sudo docker compose --profile public stop
```

Для запуска снова выполните `sudo docker compose --profile public up -d`. Не используйте `docker compose down -v`: эта команда удаляет volume базы.

### Если HTTPS не запускается

- Проверьте, что DNS `A`/`AAAA` ведут на этот VPS и нет устаревшей записи `AAAA`.
- Убедитесь, что провайдер пропускает TCP `80/443`, а другой веб-сервер не занял эти порты.
- Посмотрите `sudo docker compose logs --tail=200 caddy`.
- Не открывайте `5984` или `15984` для решения проблем с HTTPS: CouchDB должна оставаться доступной через Caddy.

## Обновление CouchDB

Версия образа закреплена на `3.5.3`, чтобы пересоздание контейнера не подтянуло несовместимую версию незаметно. Перед обновлением:

1. Выполните `sudo ./scripts/backup.sh` и сохраните копию вне сервера.
2. Выберите целевой tag и проверьте его release notes.
3. Измените обе записи `couchdb:3.5.3` в `docker-compose.yml` на одинаковый tag.
4. Выполните `sudo docker compose --profile public pull couchdb couchdb-init && sudo docker compose --profile public up -d`.
5. Проверьте `sudo docker compose --profile public ps -a`, логи CouchDB/Caddy, LiveSync и возможность восстановления backup.

Не удаляйте volume командой `docker compose down -v`: она удалит базу вместе с контейнерами.
