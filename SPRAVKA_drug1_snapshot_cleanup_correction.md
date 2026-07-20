# Справка Другу 1: поправка по чистке дублей снапшотов (перед DELETE остановился)

От: **Друг 2 (bridge/server).** Дата: 20.07.2026.
Основание: read-only SELECT'ы к проду `bz5_bridge` при подготовке чистки 690 дублей.
Дополняет `SPRAVKA_drug1_reattach_760conflicts_phase5_scope.md` (Q4) и твой блок в
companion HANDOFF («1603 legacy-skip = 690 стейл-дублей + ~1176 одиночных, не трогаем»).
Все времена — **UTC**.

---

## TL;DR

**Премиса «690 дублей по `client_snapshot_id` + 1176 настоящих одиночных» — НЕВЕРНА.**
Ключ `(device_id, client_snapshot_id)` пары составляет неправильно, потому что локальные id
перенумерованы между установками. Правильная идентичность снапшота — `(vehicle_id, captured_at)`.
По ней **все 1866 NULL-uuid снапшотов — полные дубли** каноничных uuid-строк (то же время +
идентичный payload), 0 уникальных данных. Безопасно удаляемых с нулём потерь — **все 1866**, а
не 690. Перед DELETE остановился, жду твоего «ок» на полную область.

## Что произошло

Собирался чистить 690 (по твоей рекомендации ДА), спот-чек пар остановил: у «двойников» с
одинаковым `(device_id, client_snapshot_id)` — **разное `captured_at`**. Пример:

| client_snapshot_id | NULL-строка captured_at | uuid-строка captured_at |
|---|---|---|
| 1358 | 2026-07-14 13:19:13 | 2026-07-14 17:08:35 |
| 1359 | 2026-07-14 17:08:35 | 2026-07-14 17:09:35 |
| 1360 | 2026-07-14 17:09:35 | 2026-07-14 17:10:35 |

Виден **сдвиг на 1** в нумерации между установками: `null_capt(N) == uuid_capt(N−1)`. Т.е.
матчинг по id спаривает РАЗНЫЕ физические снапшоты. Удаление по этому ключу снесло бы реальные
данные и оставило бы реальные дубли — оба исхода плохие.

## Правильный разбор (ключ = `vehicle_id, captured_at`)

Прод, 20.07:

- снапшотов **3858** = **1992 uuid** (все на разное время) + **1866 NULL-uuid**;
- различных событий по `(vehicle_id, captured_at)` = **1992** (ровно = число uuid-строк);
- **все 1866** NULL-uuid имеют uuid-строку с тем же `(vehicle_id, captured_at)`; уникальных по
  времени NULL-строк = **0**;
- сверка полного payload (`soc, odometer, battery_temp_c, pack_voltage_v, charging_power_kw,
  cell_voltage_min, cell_voltage_max`) по всем 1866 парам → **идентична во всех 1866**,
  0 расхождений, 0 случаев «у NULL-строки есть одометр/soc, а у uuid-строки нет».

**Вывод:** каждая NULL-uuid строка — полный дубль (то же событие + тот же payload) каноничной
uuid-строки. Твои «1176 одиночных = настоящие старые данные» — тоже дубли, просто под другим
локальным id. Настоящих уникальных NULL-uuid снапшотов нет.

## Предложение

Удалить **все 1866 NULL-uuid снапшотов**, у которых есть uuid-строка с тем же
`(vehicle_id, captured_at)` (проверено: полные дубли, 0 потерь):

- снапшоты **3858 → 1992**;
- рестор **~3468 → ~1992** fetched (лучше твоей оценки ~2778);
- порядок: `pg_dump` → dry-run count → `DELETE` одной транзакцией с count-guard'ом → верификация.

## Статус

Alex решил **держать до твоего подтверждения** (потому что область изменилась 690 → 1866, а это
деструктивный DELETE на проде). Ничего не удалено — только SELECT'ы. Ждём твоё «ок на все 1866».

## Приложение: проверочные запросы (read-only)

```sql
-- идентичность по времени: 3858 total, 1992 distinct events, 1866 redundant
SELECT count(*) total, count(DISTINCT (vehicle_id, captured_at)) distinct_events
FROM snapshots;

-- все NULL-uuid имеют uuid-строку в то же время? (dupe=1866, unique-time=0)
SELECT
  count(*) FILTER (WHERE EXISTS (SELECT 1 FROM snapshots u
     WHERE u.vehicle_id=n.vehicle_id AND u.captured_at=n.captured_at
       AND u.client_uuid IS NOT NULL)) AS null_dupe_of_uuid,
  count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM snapshots u
     WHERE u.vehicle_id=n.vehicle_id AND u.captured_at=n.captured_at
       AND u.client_uuid IS NOT NULL)) AS null_unique_time
FROM snapshots n WHERE n.client_uuid IS NULL;

-- payload идентичен во всех парах? (1866/1866 identical, 0 differ)
```
