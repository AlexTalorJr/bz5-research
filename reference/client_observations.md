# Client-side observations from research cycles

Накапливаемый список observations про поведение
`bz5-companion` Flutter-клиента, замеченных в ходе research, не
относящихся к самой телеметрии. Эти пункты — кандидаты на патчи
в `bz5-companion`, **не в этом repo**.

## From cycle 001 (2026-05-25)

### `args.notes` не пробрасывается в `sweep_runs.notes`

Bridge Claude POSTил `bleStartSweep` с `args.notes = "Cycle 1 — VCU
low-byte scan for power/current DIDs"`. В `sweep_runs.notes`
сохранилось жёстко `"started via bridge command"`. Пользовательский
контекст потерян.

Локация (предположительно): `lib/services/bridge_diag_service.dart`,
ветка `_handleCommand` → `bleStartSweep`, вызов `ConnectionService.runSweep()`.
Параметр `notes` из args либо не передаётся в `runSweep`, либо
`runSweep` его не использует при insertion в Drift's `sweep_runs`.

**Impact**: средний. Без notes сложно сшивать sweep_runs строки с
research-цели через несколько месяцев. Bridge Claude и owner могут
сшивать через `started_at ≈ command.dispatched_at`, но это manual
correlation.

**Action**: исправить в следующем patch'е bz5-companion. Просто
протянуть `args.notes` через `runSweep` параметр в `TripsCompanion`
(точнее, `SweepRunsCompanion.notes`).

### `period_ms` не honoured

Запрошен `period_ms=250`. Фактический cadence ≈ 110 ms/DID
(28 секунд на 255 DID). Возможные причины:
- `period_ms` игнорируется полностью; cadence = BLE round-trip floor
- `period_ms` устанавливает min interval, фактический может быть
  выше (если BLE медленный)
- Параметр пробрасывается но в неправильное место

**Impact**: низкий для исследования. 110 ms cadence фактически
определяет min время sweep — для планирования сжимаем
`~110 ms × N` DIDs. Но если потом захотим **slower** sweep (для
отладки, например), параметр нужно реально honour.

**Action**: исправить в bz5-companion позже. Пока — задокументировано.

### `vehicle_name = "unknown vehicle"` после Restore

Owner observed после успешного Restore-from-cloud: Cloud backup
card показывает "Enabled (unknown vehicle)". Sync работает,
трипы видны, но vehicle metadata пуста.

**Причина**: `CloudSyncService.startRestore()` swap'ает client_token
и устанавливает `_deviceId`, но **не запрашивает** vehicle metadata
у сервера. Эти поля (`_vehicleId`, `_vehicleName`) клиент знает
только из `register-device` response, которого при Restore нет.

**Impact**: средний. UI-cosmetic, не функциональный. Но "unknown
vehicle" неприятно видеть.

**Action**: исправить в следующем patch'е bz5-companion. Варианты:
- После probe-success вытянуть vehicle через `GET /v1/data/vehicles/me`
  (если такой endpoint существует у Друга 2 — если нет, добавить)
- Или взять `vehicle_id` из первого восстановленного trip'а
  (он там есть в JSON response от `/v1/data/trips`) и использовать
  для отображения

### Version string не отображается в UI на head unit'е

Owner: "секции Dashboard не существует на head display, версию
посмотреть негде". Текущий debug overlay `_kDiagVersion` рендерится
только на phone portrait layout.

**Impact**: средний. Без видимой версии трудно подтвердить что
владелец действительно на нужном build'е после in-place install
или uninstall+install.

**Action**: добавить version string в Settings → About screen
(простое single-line добавление, не trigger'ит protected file rule).
