# BZ5 Cloud — спецификация v1.3 (финальная)

Дата: 2026-07-03 · v1.2 + рефайнменты server-review v1.2 (bz5-research/cloud-v2/spec-v1.2-server-review.md)
Статус: **GREEN LIGHT — к реализации** (вердикт ревью v1.2: «ready to implement, no blockers»; старт: C1 + остаток S1 параллельно).

Changelog v1.2 → v1.3: R1 — паттерн advisory lock «взять поздно, держать коротко» вшит в S4; R2 — fail-closed bootstrap/allowlist в S2; R3 — уточнена формулировка дедупа §3.1; §1 — исправлен устаревший факт про offsite.

---

## 0. Зафиксированные решения

| # | Решение | Кто утвердил |
|---|---------|--------------|
| D1 | client_uuid (UUIDv7) как глобальный ключ дедупа всех сущностей; Drift schema bump 13→14 | Alex, 3 Jul |
| D2 | Регистрация: email + OTP-код (passwordless), пароль опционально | Alex, 3 Jul |
| D3 | GPS/геоданные НЕ собираются; схема без геополей, помечено future | Alex, 3 Jul |
| D4 | Привязка ГУ: pairing code (паттерн Smart TV); setup-token остаётся admin-каналом; `register-device` — legacy/admin-путь | Alex, 3 Jul |
| **D5 (v1.1)** | **Существующие device_token никогда не инвалидируются миграциями.** Живое устройство при привязке сохраняет токен. Для свежего устройства (переустановка) **pairing = регистрация**: новый токен выдаётся на шаге `pair/claim`. Токен меняется ТОЛЬКО через pairing | резолюция A2 |
| D6 (v1.1) | Durable-состояние в Postgres **для auth/OTP/сессий**; ингест-rate-limit остаётся in-memory (abuse-защита, потеря при рестарте приемлема). Без Redis | резолюция B4 |
| D7 (v1.2) | Bootstrap владельца: первый OTP-вход с email == `OWNER_EMAIL` (env) присваивает существующий seed-user. Гейт действует **уже на `otp/request`**: до присвоения seed письма шлются только на OWNER_EMAIL (защита relay, N3) | резолюция B1+N3 |
| D8 (new) | Целостность pull-курсора (N1): сервер — advisory lock вокруг присвоения server_seq + commit (жёсткая гарантия, при наших объёмах бесплатно); клиент — идемпотентное применение по client_uuid с overlap-окном `since = last_seq − N` (страхует ретраи и restore). Оба слоя обязательны | резолюция N1 |
| D9 (new) | Pairing (b) по OAuth device-flow: два секрета. `user_code` (короткий, на экране ГУ, вводится на телефоне — авторизует одобрение владельцем) и `device_code` (длинный, генерируется ГУ при `pair/start`, предъявляется при поллинге — **токен выдаётся только по нему**). Короткий код никогда не даёт токен | резолюция N2 |
| D10 (new) | Регистрация после bootstrap: **allowlist до публичного запуска**. `otp/request` шлёт коды только на email из allowlist-таблицы (управление из админки); переход на открытую регистрацию — одним конфиг-флагом при решении о дистрибуции | Alex, 3 Jul (N3) |

## 1. Контекст сервера (verified live, 3 Jul)

- Python 3.11, FastAPI 0.115.x, uvicorn 0.32, SQLAlchemy 2.0 async + asyncpg, Alembic 1.14, Pydantic v2. Admin UI — статический vanilla html/js (hash-routing)
- Одна Postgres 16 (bind-mount), pg_dump daily/weekly локально + **offsite на Scaleway (age-encrypt, cron 04:00 UTC, с 3 Jul)**. max_connections=20
- Схема multi-user-ready (`users`, `vehicles`, `owner_user_id` FK), воркфлоу single-tenant. Текущие данные: users 1 (seed, без email), vehicles 1, devices 2, trips 50, snapshots 1315
- Ingest-семантика конфликтов (`app/routers/data.py`): trips/feature_catalog = **UPSERT**; snapshots/samples/sweeps/livelogs/canmonitor = **DO NOTHING**
- Retention: trips/snapshots — нет (вечные); samples/livelog/can 90 дн; audit 30; commands(finished) 14; diag 180
- Почта: greenfield (нет MTA, нет библиотек)
- Ресурсы: 4 vCPU / 7.7 GB RAM (swap 0) / 90 GB диск: 66 GB занято (74%), из них ~12 GB — реклеймится docker prune; VPS общий с другими проектами. БД ~12 MB
- nginx: `client_max_body_size 25M` (лимит push-аплоадов), `proxy_read_timeout 60s` (важен для pull)
- ⚠️ `make test` TRUNCATE-ит живую БД; audit_log — best-effort, без user-reference (token_fp 8 hex)

## 2. Несущие стены платформы

1. **ГУ DiLink без GMS** → вход на машине только через pairing code с телефона.
2. **Переустановка APK на DiLink стирает всё** (Drift, secureStorage-токен, prefs). **Restore восстанавливает данные; идентичность НЕ восстанавливается — она пере-выпускается через pairing** (v1.1, A1). Restore = единственный путь обновления версии без потери истории.
3. **Клиент после 3×401 стирает токен и останавливается** (данные Drift НЕ стирает). Graceful-режим «требуется привязка» — клиентский этап C6.
4. **Restore покрывает**: trips, snapshots, настройки. **Не покрывает**: livelog/samples/can (retention 90 дн), идентичность (см. п.2). В UI restore сказать явно.
5. **Дефект дедупа сегодня (мотивация D1, ужесточено A3):** после очистки локальной БД autoincrement рестартует, и на сервере: snapshots/sweeps/livelog — молчаливый drop новых строк; **trips — молчаливая ПЕРЕЗАПИСЬ старых поездок новыми** (UPSERT по (device_id, client_trip_id) = порча истории). Каждая поездка после wipe без C1 портит серверную историю → C1 первым.

## 3. Модель данных и синк

### 3.1 Идентичность
- `client_uuid` UUIDv7 на каждой синкуемой сущности, генерируется клиентом. Дедуп-ключ сервера: `(vehicle_id, client_uuid)`.
- Скоуп: `account → vehicles → devices`. Device — источник, vehicle — владелец данных. Уточнение (R3): client_uuid глобально уникален, так что `(vehicle_id, client_uuid)` — это общее vehicle-пространство имён, а не схлопывание записей разных устройств (каждое генерирует свои uuid; кросс-девайсных коллизий нет и не нужно).
- Миграция UNIQUE (B2): alembic-ревизия добавляет новые constraint'ы `(vehicle_id, client_uuid)`, **старые per-device UNIQUE живут параллельно до подтверждения backfill**, дропаются отдельной ревизией.

### 3.2 Синк
- **Push**: батчи с client_uuid, идемпотентно по дедуп-ключу. Лимит: body ≤ 25M (nginx) — клиент режет батчи.
- **Pull**: `GET /v2/sync/pull?vehicle=<id>&since=<server_seq>` — пагинация обязательна (страница ~1–2 MB), полный restore = серия страниц с since=0. Узкое место — `proxy_read_timeout 60s`, не body-limit (A4): страницы держать заведомо быстрее таймаута.
- **server_seq** (B3): BIGINT из глобальной sequence, проставляется на КАЖДОМ insert/update (иначе LWW-апдейты невидимы курсору), индекс `(vehicle_id, server_seq)`. Плюс net-new колонки `updated_at` (LWW) и `deleted_at` (tombstones) на trips/snapshots — отдельная alembic-ревизия в S4.
- **Целостность курсора (D8/N1):** без защиты pull между statement-присвоением seq и commit теряет строки навсегда (классическая дыра sequence-CDC). Сервер: advisory lock на присвоение+commit. Клиент: применяет страницы идемпотентно по client_uuid и запрашивает с overlap (`since = last_seq − N`, N ≈ 100) — повторная выборка безвредна.
- Auth pull (A2): device_token, привязанный к vehicle, ИЛИ account-JWT владельца vehicle. Телефон ходит по JWT; свежепривязанное ГУ — по своему новому токену.
- Конфликты: телеметрия append-only; мутабельное — LWW по updated_at серверных часов.

### 3.3 Клиентская миграция (Drift 13→14) — этап C1, максимальный приоритет (см. §2.5)
- client_uuid во все синкуемые таблицы, backfill UUIDv7, отправка mapping (device_id, старый id → uuid) на сервер один раз.

## 4. Аккаунты и доступ

### 4.1 Регистрация/вход (телефон)
- `POST /v2/auth/otp/request {email}` → 6-значный код, TTL 10 мин, одноразовый, хэш в БД
- `POST /v2/auth/otp/verify {email, code}` → access JWT (15 мин) + refresh (opaque, ротация, Keystore)
- **Bootstrap (D7/B1):** пока seed-user без email — request/verify принимают только `OWNER_EMAIL`; успешный вход пишет email в seed-строку. После присвоения — режим allowlist (D10): коды только адресам из allowlist, новые users создаются только для них
- **Fail-closed (R2):** если `OWNER_EMAIL` не задан в env и seed не присвоен — `otp/request` отклоняет ЛЮБОЙ email (4xx). Ошибка конфигурации не должна превращать сервис в открытый mail-relay
- Пароль опционально после входа; Google Sign-In на телефоне — фаза 3
- Rate-limit в Postgres: 5 OTP/час на email, 20/час на IP

### 4.2 Привязка устройств (pairing) — оба сценария (A2)
**(a) Живое устройство** (токен есть): `pair/start {device_id}` → user_code+QR (TTL 5 мин) → телефон `pair/claim {user_code}` → сервер ставит owner; **токен не меняется**. Так мигрируют оба текущих устройства.
**(b) Свежее устройство** (после переустановки, токена нет): ГУ генерирует локальный ephemeral id → `pair/start` без серверной регистрации → телефон `pair/claim` → **сервер создаёт devices-строку под аккаунтом/vehicle и выдаёт новый device_token** полящему ГУ → дальше restore-мастер (C5) тянет историю vehicle. `register-device` остаётся admin/legacy.

### 4.3 Управление
- «Мои устройства» (телефон + админка): список, last_seen, revoke. Revoke помечает токен отозванным; клиент в graceful-режиме «требуется привязка» (C6), локальные данные не тронуты
- Роли: owner / user. Квоты — nullable-задел

## 5. Безопасность
- Access JWT 15 мин / refresh с ротацией; device_token — прежняя схема (SHA-256+pepper)
- JWT-секрет — env-параметр (семантика как APP_TOKEN_PEPPER: ротация = глобальный логаут); **reuse-detection ротации refresh**: предъявление уже-ротированного refresh = вероятная кража → revoke всей цепочки сессии (N4)
- Ожидаемое поведение (N5): revoke устройства мгновенен (проверка revoked_at на каждом запросе); отзыв аккаунт-сессии на stateless JWT добирает до 15 мин до истечения — принято как норма
- Certificate pinning в клиенте; публикация sha256 релизных APK
- OTP-relay: Postmark / Resend / SES. Предусловие прода: SPF+DKIM+DMARC (DNS — Alex)
- **Auth-аудит (C1-ревью): отдельная durable-таблица `auth_events`** (user_id, device_id, event, ip, ts), retention 365 дн. Существующий audit_log (best-effort, 30 дн, без user-ref) для security-trail не годится
- Чистка otp_codes/sessions/refresh_tokens — расширение существующего retention-sweeper'а (B4), не новый механизм

## 6. Этапы

### Сервер (Друг 2)
- **S1 — Гигиена (предусловие):** offsite-бэкап — ✅ **сделано 3 Jul** (pg_dump -Fc -Z9 → age-encrypt → rclone → Scaleway s3://ineedto-backups/bzcloud, cron 04:00 UTC, retention 14d/8w, приватный age-ключ у Alex вне VPS, восстановление проверено end-to-end; `scripts/backup-s3.sh` / `make backup-offsite`). Остаток: test-БД для make test; docker prune (~12 GB)
- **S2 — Аккаунт-ядро:** активация users.email, таблицы otp_codes/sessions/refresh_tokens/auth_events + **allowlist-таблица с CRUD в админке (D10)**, OTP endpoints, **bootstrap seed-юзера по OWNER_EMAIL с гейтом на otp/request (D7)**, relay-интеграция, durable rate-limit auth, JWT-секрет env + reuse-detection (N4), расширение sweeper'а
- **S3 — Pairing:** оба сценария §4.2 по device-flow D9 (user_code + device_code, токен только по device_code), revoke, привязка legacy
- **S4 — Sync v2:** alembic: client_uuid + двойные UNIQUE (B2), server_seq/updated_at/deleted_at (B3); **advisory lock присвоения seq (D8) по паттерну R1: `pg_advisory_xact_lock` берётся непосредственно ПЕРЕД `nextval(server_seq)`, commit сразу после — не в начале длинной транзакции**, иначе медленный батч сериализует все synced-writes и (с N6) выедает пул; приём mapping; pull с пагинацией и курсором server_seq; после подтверждения backfill — ревизия дропа старых UNIQUE. Watch (N6): пул коннектов при max_connections=20 под S4+S5 нагрузкой
- **S5 — Веб-кабинет** (после S2, параллелится)

### Клиент (Друг 1)
- **C1 — Drift 13→14 + mapping** — первым: каждый wipe без него портит trips на сервере (§2.5)
- **C2 — Auth UI (телефон):** email-OTP, Keystore
- **C3 — Pairing UI (ГУ):** код+QR, поллинг; «Мои устройства»; сценарий (b) — pairing-экран на свежей установке вместо Setup
- **C4 — Push v2** (батчи по client_uuid, нарезка ≤25M)
- **C5 — Restore-мастер:** первый запуск → pairing (b) → «найден vehicle X: 50 поездок, 1315 снапшотов — восстановить?» → порционный pull с прогрессом, применение идемпотентно по client_uuid, курсор с overlap (D8)
- **C6 — Graceful 401 (из C2-ревью):** вместо «стереть токен и умереть» — состояние «требуется привязка», данные и сервисы локально живы, кнопка на pairing
- Зависимости: C1 → C4 → C5; C2 → C3 → C6

### Инфраструктура (Alex)
- ~~Offsite-бэкап~~ — ✅ сделано (Scaleway; приватный age-ключ хранить надёжно вне VPS — без него бэкапы невосстановимы)
- Домен отправки почты + SPF/DKIM/DMARC; выбор relay
- Значение OWNER_EMAIL для bootstrap
- ~~Решение по N3~~ — ✅ принято: allowlist (D10)

## 7. Функционал v2+ (без изменений против v1.0)
SOH-серия в кабинете → экспорт CSV/JSON → FCM-уведомления (телефон) → зарядная статистика → share-links (public_slug) → мультиавто → анонимная парковая статистика.

## 8. Открытые вопросы
1. ~~Фреймворк/версии~~ — закрыт (A5) · 2. ~~Body-limit pull~~ — закрыт (A4) · 3. ~~Offsite~~ — сделан
4. Домен для OTP-почты + relay — за Alex
5. ~~Политика регистрации~~ — закрыт: allowlist до публичного запуска (D10)
6. Free/paid tier — отложено

## 9. Куда смотреть
- Ревью: `cloud-v2/spec-v1.0-server-review.md`, `spec-v1.1-server-review.md`, `spec-v1.2-server-review.md`
- Бэкап-скрипты: `bz5-bridge:scripts/backup-s3.sh`, `make backup-offsite`
- Клиентские инварианты: AA2, триплет версий, 4 гейта — действуют для всех C-этапов
