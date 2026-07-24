# Завершение бакета без расстрела живого билдера (16.0.12)

Дата: 2026-07-24. Статус: дизайн согласован по итогам брейншторма, ждёт ревью спеки.

## Контекст

Бакет (все тесты списком в `OnlyTestIdentifiers` xctestrun) исполняет один автономный процесс
xcodebuild («билдер»). Emcee после старта — пассивный наблюдатель: читает файл
`result_stream.json` (tail → `BlockingArrayBasedJSONStream` → `JSONReader` → декодер событий)
и ждёт терминации. Корневая запись xcresult пишется билдером в самом конце (финализация);
до неё бандл нечитаем, и весь бакет стабится плагином в Allure.

Доказано (инцидент 22.07, бакет 909F853E; по коду — от противного): при живом билдере чтение
стрима завершается **только** исключением `JSONReader` на синтаксически битом JSON. Причина
порчи JSON — открытый дефект A (вне скоупа, см. «Отложено»).

После оживления доставки сигналов (CLT-фикс `f77f0c0`) в билдера стреляют три механизма,
два из которых бьют здоровый процесс:

| Стрелок | Порог | Судьба в этой спеке |
|---|---|---|
| Блок #1.3 в `Runner.runOnce` — килл при закрытии стрима | мгновенно | разоружается (п.4) |
| `TestTimeoutTrackingTestRunnerSream` → килл билдера при тесте дольше `singleTestMaximumDuration` | 270с | разоружается (п.3) |
| `PreflightPostflightTimeoutTrackingTestRunnerStream` → килл по тишине событий | 900с | остаётся; глушится только на пути ожидания (п.2) |

## Принятые решения (из брейншторма)

- Критерий ожидания живого билдера — **прогресс по файлам**, не фикс-таймаут.
- Дубли хвоста (queue-ретраи тестов, которые оригинал доиграл после ошибки чтения) — **терпим**.
- Ожидание живёт у **владельца процесса** (`XcodebuildBasedTestRunner`).
- Один смысловой параметр тишины на всё: `testRunnerMaximumSilenceDuration` (уже в testargbase).
- Инвариант: **в любой момент за жизнь билдера отвечает ровно один страж**.
- Нативные пер-тестовые таймауты XCTest — отложены в ресерч (см. «Отложено»).

## Модель стражей

| Фаза | Страж | Критерий | Порог |
|---|---|---|---|
| Чтение стрима идёт | Preflight/Postflight (существующий) | тишина по событиям | `testRunnerMaximumSilenceDuration` (900с) |
| Чтение умерло, билдер жив | `RunnerProcessProgressWaiter` (новый) | тишина по росту файлов | тот же `testRunnerMaximumSilenceDuration` |
| Поверх второй фазы | hard cap внутри waiter'а | абсолютное время с момента смерти чтения | `bucketShutdownHardCap` (новый конфиг) |

Эскалация при срабатывании любого из порогов второй фазы: SIGINT → 15с → SIGKILL
(`interruptAndForceKillIfNeeded`, рабочий после CLT-фикса) → `waitForProcessToDie()`.

## Изменения

### П.1 — путь ожидания у владельца

`Sources/AppleTools/XcodebuildBasedTestRunner.swift`, completion-блок `streamContents` (:107-120):

1. При ошибке: лог «Result stream error» + размер/mtime `result_stream.json` (улика для дефекта A).
2. `testRunnerStream.streamReadingAborted()` — передача поста (п.2).
3. `RunnerProcessProgressWaiter.waitForExit(...)` — ждать собственного выхода билдера.
4. `readResultBundle(...)` — бандл к этому моменту финализирован (исчезает мусорный
   `Error parsing xcresult bundle … exit code 64`).
5. `testRunnerStream.closeStream()` — Runner отпускается последним.

Штатный путь (билдер уже мёртв к completion) не меняется: шаги 2–3 мгновенны.

Новый тип `Sources/AppleTools/RunnerProcessProgressWaiter.swift` (одна ответственность,
юнит-тестируемый):
- Прогресс = максимум из (mtime/размер `result_stream.json`) и (максимальный mtime по
  неглубокому обходу `resultBundle.xcresult`: каталог + записи первого уровня + `Data/`).
- Опрос каждые 5с (техническая константа), пока `isProcessRunning`.
- Прогресс стоит ≥ `testRunnerMaximumSilenceDuration` ИЛИ суммарное ожидание ≥
  `bucketShutdownHardCap` → эскалация (см. выше).

### П.2 — передача поста событийному стражу

- В протокол `TestRunnerStream` добавляется `streamReadingAborted()` с пустой реализацией
  по умолчанию (protocol extension — конформеры не меняются).
- `PreflightPostflightTimeoutTrackingTestRunnerStream` реализует его как `stopAnyTracking()`
  — тот же выключатель, что у `testStarted`/`closeStream`. Вызов идемпотентен: при смерти
  чтения посреди теста страж уже стоит выключенным (пограничный факт из кода).
- `TestTimeoutTrackingTestRunnerSream` глушить НЕ нужно: после п.3 его срабатывание — только
  безвредная синтетика «failed по таймауту» (тест и так уйдёт в ретрай).

### П.3 — разоружение килла в трекере зависших тестов

`Sources/Runner/Runner.swift:163`: убрать `…currentValue()?.cancel()` из обработчика
`detectedLongRunningTest`. Остаются: warning-лог и синтетический
`TestStoppedEvent(.failure, "test timed out")` → тест помечен упавшим, уходит в ретрай.

Это возврат исторической семантики: годы (и чистая неделя 16.0.9) система жила именно с
холостым киллом здесь — зависшие тесты помечались упавшими, замороженные приложения добивал
симуляторный watchdog (`watchdogSettings: 42` в testargbase), бакет продолжался.

**Остаточный риск (принят)**: истинно-мёртвый раннер при живом приложении держит слот до конца
прогона — освободить некому. Риск не новый (жил все годы холостого килла, боли не давал);
закрывается отложенным блоком эскалации.

### П.4 — разоружение Runner на штатном пути

`Sources/Runner/Runner.swift:252-256` (блок #1.3): `cancel()+wait()` →
`wait()` (процесс к этому моменту мёртв на всех путях — мгновенно) + `performPostRunCleanup()`.

`performPostRunCleanup()` — новый метод `TestRunnerRunningInvocation` (дефолт — пустой):
в `ProcessControllerWrappingTestRunnerInvocation` зовёт только in-sim зачистку
(`onCancel` → существующий `InSimulatorApplicationTerminator`, app + runner), без килла.
После этой правки Runner не убивает процессы нигде, кроме легитимных таймаут-обработчиков.

### П.5 — новый конфиг `bucketShutdownHardCap`

- `TestTimeoutConfiguration` (RunnerModels) + декодирование в TestArgFile:
  `decodeIfPresent`, дефолт **1800с** — старые testargbase работают без правок.
- Валидация при старте: `hardCap < silence` → warning в лог + кламп `hardCap = silence`.
- В testargbase выкатывается при включении 16.0.12 (не раньше).

### П.6 — зачистка лживых логов и комментариев

- `ProcessControllerWrappingTestRunnerInvocation.swift:33-38`: лог «force-killing … process
  group» и комментарий про `kill(-pid)` — переформулировать под фактику (прямой pid).
- `CancellableRecordingImpl.swift` (комментарии :19-23, :44-50): описывают групповой килл как
  текущее поведение CLT — обновить: в CLT прямой pid с `f77f0c0`.

## Verification

1. `swift build` зелёный; юниты: `RunnerProcessProgressWaiter` (вышел сам / прогресс идёт /
   прогресс встал / hard cap), трекер (килл не зовётся, синтетика пишется),
   глушение (`streamReadingAborted` останавливает postflight-таймер).
2. Стенд emcee1, имитация ошибки чтения (S3): во время живого бакета дописать мусор в
   `result_stream.json` (`echo garbage >> …`) — парсер бросает как в проде. Проверить:
   билдер дожил, все тесты доехали, бандл читаем `xcresulttool`, в worker-логе виден путь
   ожидания, мусорного exit-64 нет.
3. Стенд, имитация зависшего билдера (S5): SIGSTOP билдеру во время ожидания → прогресс-стоп
   добивает через `silence`, слот освобождён.
4. Штатный стенд-прогон: тайминги не изменились (зазор «Finished executing tests → Did get» ~1с).
5. Деплой `ios-test-build/emcee/16.0.12/Emcee`; включение в CI — отдельным решением
   пользователя (прод сейчас на стабильном 16.0.9).

## Отложено (в план, не в этот релиз)

1. **Ресерч: нативные пер-тестовые таймауты XCTest** — `-test-timeouts-enabled YES
   -default-test-execution-time-allowance <сек>`: XCTest сам валит зависший тест и продолжает
   бакет. Проверить на стенде работу с legacy-xctestrun. Если работает — закрывает остаточный
   риск п.3 нативно.
2. **Эскалация для мёртвого раннера** (если ресерч №1 не выгорит): двухступенчатый трекер —
   на `D` терминировать только приложение (`InSimulatorApplicationTerminator` c областью
   «только app»), на `2×D` терминировать раннер (билдер сам финализирует бандл), килл билдера
   — последний рубеж.
3. **Самотерминация раннера** (запасной путь №2): watchdog в тест-бандле через
   `XCTestObservation` + `abort()` с фонового потока.
4. **Дефект A**: что портит JSON в result_stream.json (первая улика — расширенный лог из п.1).
5. **Backfill из бандла**: устранение дублей queue-ретраев доигранного хвоста.

## Вне скоупа

- Судьба веток Emcee (`AQA-7794-scheme-approvals` с коммитами поверх) — отдельное решение.
- Нативная видеозапись (16.0.11, `VIDEO_*`) — готова, живёт независимо.
