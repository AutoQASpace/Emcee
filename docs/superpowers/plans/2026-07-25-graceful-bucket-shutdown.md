# Graceful Bucket Shutdown (16.0.12) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emcee перестаёт расстреливать живой xcodebuild: после конца чтения result stream билдер дожидается по файловому прогрессу, событийные стражи разоружаются/глушатся, бандл всегда финализируется.

**Architecture:** Ожидание живёт у владельца процесса (`XcodebuildBasedTestRunner`, completion `streamContents`): новое протокольное событие `streamReadingAborted()` глушит событийного стража, новый `RunnerProcessProgressWaiter` ждёт выхода билдера по росту файлов (silence/hardCap → SIGINT→SIGKILL), потом читается бандл и закрывается стрим. Киллы из TestTimeout-трекера и блока #1.3 убираются.

**Tech Stack:** Swift (SPM), репозиторий `/Users/p.starodubkin/Documents/repo/Emcee`, ветка `AQA-7794-scheme-approvals`.

**Спека:** `docs/superpowers/specs/2026-07-23-bucket-shutdown-design.md` (одобрена).

## Global Constraints

- Сборка: `swift build` из корня Emcee; тесты: `swift test --filter <TestClassName>`.
- Коммиты: формат `AQA-7496 <короткое описание>`; БЕЗ `Co-Authored-By`; НЕ пушить.
- CLT-фикс (`kill(pid)` в `DefaultProcessController`) НЕ трогать.
- Пороги: silence = `testRunnerMaximumSilenceDuration` (существующий конфиг, 900с в testargbase); hard cap = `bucketShutdownHardCap` (новый, дефолт **1800**); кламп `hardCap = max(hardCap, silence)` c warning.
- Частота опроса файлов: 5с (техническая константа, не конфиг).
- testargbase.json НЕ менять (выкатывается при включении 16.0.12 отдельно).
- Деплой бинаря (`emcee/16.0.12/Emcee` на JFrog) — только последней задачей, CI не трогать.

---

### Task 1: Конфиг `bucketShutdownHardCap` в TestTimeoutConfiguration

**Files:**
- Modify: `Sources/RunnerModels/TestTimeoutConfiguration.swift`
- Test: `Tests/TestArgFileTests/TestTimeoutConfigurationDecodingTests.swift` (create)

**Interfaces:**
- Produces: `TestTimeoutConfiguration.bucketShutdownHardCap: TimeInterval` и `TestTimeoutConfiguration.defaultBucketShutdownHardCap: TimeInterval == 1800`. Init получает параметр с дефолтом — существующие вызовы конструктора не меняются.

- [ ] **Step 1: Проверить, что тест-таргет существует**

Run: `ls Tests | grep TestArgFileTests`
Expected: `TestArgFileTests`. (Если таргета нет — положить тест в `Tests/RunnerModelsTests/`, проверив аналогично; далее по тексту пути не меняются.)

- [ ] **Step 2: Написать падающий тест декодирования**

```swift
// Tests/TestArgFileTests/TestTimeoutConfigurationDecodingTests.swift
import Foundation
import RunnerModels
import XCTest

final class TestTimeoutConfigurationDecodingTests: XCTestCase {
    func test___decoding_without_hard_cap___uses_default() throws {
        let json = Data("""
        {"singleTestMaximumDuration": 270, "testRunnerMaximumSilenceDuration": 900}
        """.utf8)
        let config = try JSONDecoder().decode(TestTimeoutConfiguration.self, from: json)
        XCTAssertEqual(config.bucketShutdownHardCap, TestTimeoutConfiguration.defaultBucketShutdownHardCap)
        XCTAssertEqual(config.bucketShutdownHardCap, 1800)
    }

    func test___decoding_with_hard_cap___uses_value() throws {
        let json = Data("""
        {"singleTestMaximumDuration": 270, "testRunnerMaximumSilenceDuration": 900, "bucketShutdownHardCap": 3600}
        """.utf8)
        let config = try JSONDecoder().decode(TestTimeoutConfiguration.self, from: json)
        XCTAssertEqual(config.bucketShutdownHardCap, 3600)
    }
}
```

- [ ] **Step 3: Прогнать — убедиться, что падает**

Run: `swift test --filter TestTimeoutConfigurationDecodingTests 2>&1 | tail -5`
Expected: FAIL (нет `bucketShutdownHardCap`).

- [ ] **Step 4: Реализация**

Заменить содержимое `Sources/RunnerModels/TestTimeoutConfiguration.swift`:

```swift
import Foundation

public struct TestTimeoutConfiguration: Codable, Hashable {
    /** A maximum duration for a single test. */
    public let singleTestMaximumDuration: TimeInterval

    /** A maximum allowed duration for a test runner stdout/stderr to be silent. */
    public let testRunnerMaximumSilenceDuration: TimeInterval

    /// Absolute upper bound for waiting for the test runner host process to exit after its
    /// result stream reading has ended. Safety net against a process that keeps showing
    /// file activity forever. Must not undercut the silence criterion (clamped at use site).
    public let bucketShutdownHardCap: TimeInterval

    public static let defaultBucketShutdownHardCap: TimeInterval = 1800

    public init(
        singleTestMaximumDuration: TimeInterval,
        testRunnerMaximumSilenceDuration: TimeInterval,
        bucketShutdownHardCap: TimeInterval = TestTimeoutConfiguration.defaultBucketShutdownHardCap
    ) {
        self.singleTestMaximumDuration = singleTestMaximumDuration
        self.testRunnerMaximumSilenceDuration = testRunnerMaximumSilenceDuration
        self.bucketShutdownHardCap = bucketShutdownHardCap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        singleTestMaximumDuration = try container.decode(TimeInterval.self, forKey: .singleTestMaximumDuration)
        testRunnerMaximumSilenceDuration = try container.decode(TimeInterval.self, forKey: .testRunnerMaximumSilenceDuration)
        bucketShutdownHardCap = try container.decodeIfPresent(TimeInterval.self, forKey: .bucketShutdownHardCap)
            ?? TestTimeoutConfiguration.defaultBucketShutdownHardCap
    }
}
```

- [ ] **Step 5: Прогнать тесты — зелёные; сборка целиком**

Run: `swift test --filter TestTimeoutConfigurationDecodingTests 2>&1 | tail -3 && swift build 2>&1 | tail -2`
Expected: PASS ×2, `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/RunnerModels/TestTimeoutConfiguration.swift Tests/TestArgFileTests/TestTimeoutConfigurationDecodingTests.swift
git commit -m "AQA-7496 bucketShutdownHardCap config (default 1800, decodeIfPresent)"
```

---

### Task 2: `RunnerProcessProgressWaiter` — файловый страж

**Files:**
- Create: `Sources/AppleTools/RunnerProcessProgressWaiter.swift`
- Test: `Tests/AppleToolsTests/RunnerProcessProgressWaiterTests.swift` (create)

**Interfaces:**
- Consumes: `TestTimeoutConfiguration` (Task 1) — значения порогов передаются числами.
- Produces:
  - `RunnerProcessProgressWaiter(logger: ContextualLogger, maximumSilenceDuration: TimeInterval, hardCap: TimeInterval, pollInterval: TimeInterval = 5)`
  - `func waitForExit(isProcessRunning: () -> Bool, progressMarker: () -> String, killProcess: () -> ())`
  - `enum FileActivityMarker { static func marker(paths: [AbsolutePath]) -> String }`

- [ ] **Step 1: Написать падающие тесты**

```swift
// Tests/AppleToolsTests/RunnerProcessProgressWaiterTests.swift
import AppleTools
import EmceeLogging
import Foundation
import XCTest

final class RunnerProcessProgressWaiterTests: XCTestCase {
    private let logger = ContextualLogger.noOp

    private func makeWaiter(silence: TimeInterval, hardCap: TimeInterval) -> RunnerProcessProgressWaiter {
        RunnerProcessProgressWaiter(
            logger: logger,
            maximumSilenceDuration: silence,
            hardCap: hardCap,
            pollInterval: 0.02
        )
    }

    func test___process_exits_on_its_own___no_kill() {
        var running = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { running = false }
        var killed = false

        makeWaiter(silence: 5, hardCap: 10).waitForExit(
            isProcessRunning: { running },
            progressMarker: { "constant" },
            killProcess: { killed = true }
        )

        XCTAssertFalse(killed)
    }

    func test___no_progress_beyond_silence___kills() {
        var killed = false

        makeWaiter(silence: 0.1, hardCap: 10).waitForExit(
            isProcessRunning: { !killed },
            progressMarker: { "frozen" },
            killProcess: { killed = true }
        )

        XCTAssertTrue(killed)
    }

    func test___continuous_progress___survives_silence_but_hits_hard_cap() {
        var killed = false
        var counter = 0

        makeWaiter(silence: 0.15, hardCap: 0.5).waitForExit(
            isProcessRunning: { !killed },
            progressMarker: { counter += 1; return "tick-\(counter)" },
            killProcess: { killed = true }
        )

        XCTAssertTrue(killed)
    }

    func test___hard_cap_below_silence___is_clamped_to_silence() {
        // ждать дольше silence процесс с прогрессом должен, даже если cap задан меньше
        var killed = false
        let startedAt = Date()
        var counter = 0

        makeWaiter(silence: 0.3, hardCap: 0.05).waitForExit(
            isProcessRunning: { !killed && Date().timeIntervalSince(startedAt) < 0.2 },
            progressMarker: { counter += 1; return "tick-\(counter)" },
            killProcess: { killed = true }
        )

        XCTAssertFalse(killed, "cap должен быть клампнут до silence: процесс с прогрессом дожил до своего выхода")
    }
}
```

Если `ContextualLogger.noOp` не существует — использовать способ создания логгера из соседних тестов `Tests/AppleToolsTests/` (посмотреть в `XcodebuildBasedTestRunnerTests.swift`).

- [ ] **Step 2: Прогнать — падает**

Run: `swift test --filter RunnerProcessProgressWaiterTests 2>&1 | tail -3`
Expected: FAIL / does not compile («no such type»).

- [ ] **Step 3: Реализация**

```swift
// Sources/AppleTools/RunnerProcessProgressWaiter.swift
import EmceeLogging
import Foundation
import PathLib

/// Waits for the test runner host process (xcodebuild) to exit on its own after its result
/// stream reading has ended. The process finalizes the xcresult bundle at the very end of
/// its lifetime, so it must not be killed while it shows signs of file activity. Kills only
/// a process whose activity stalled (silence) or which outlived the absolute hard cap.
public final class RunnerProcessProgressWaiter {
    private let logger: ContextualLogger
    private let maximumSilenceDuration: TimeInterval
    private let hardCap: TimeInterval
    private let pollInterval: TimeInterval

    public init(
        logger: ContextualLogger,
        maximumSilenceDuration: TimeInterval,
        hardCap: TimeInterval,
        pollInterval: TimeInterval = 5
    ) {
        self.logger = logger
        self.maximumSilenceDuration = maximumSilenceDuration
        self.pollInterval = pollInterval
        if hardCap < maximumSilenceDuration {
            logger.warning("bucketShutdownHardCap (\(hardCap)) is below silence duration (\(maximumSilenceDuration)), clamping to silence")
            self.hardCap = maximumSilenceDuration
        } else {
            self.hardCap = hardCap
        }
    }

    public func waitForExit(
        isProcessRunning: () -> Bool,
        progressMarker: () -> String,
        killProcess: () -> ()
    ) {
        let startedAt = Date()
        var lastProgressAt = startedAt
        var lastMarker = progressMarker()

        while isProcessRunning() {
            let now = Date()
            if now.timeIntervalSince(startedAt) >= hardCap {
                logger.warning("Test runner process outlived hard cap (\(hardCap) sec), killing it")
                killProcess()
                return
            }
            let marker = progressMarker()
            if marker != lastMarker {
                lastMarker = marker
                lastProgressAt = now
            } else if now.timeIntervalSince(lastProgressAt) >= maximumSilenceDuration {
                logger.warning("Test runner process shows no file activity for \(maximumSilenceDuration) sec, killing it")
                killProcess()
                return
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }
}

/// Snapshot of observable file activity; any change of the marker counts as progress.
public enum FileActivityMarker {
    public static func marker(paths: [AbsolutePath]) -> String {
        let fileManager = FileManager()
        var parts = [String]()
        for path in paths {
            parts.append(describe(path: path.pathString, fileManager: fileManager))
            // неглубокий обход каталога (xcresult): записи первого уровня + Data/
            if let firstLevel = try? fileManager.contentsOfDirectory(atPath: path.pathString) {
                for entry in firstLevel.sorted() {
                    parts.append(describe(path: path.appending(entry).pathString, fileManager: fileManager))
                }
                let dataDir = path.appending("Data").pathString
                if let dataEntries = try? fileManager.contentsOfDirectory(atPath: dataDir) {
                    parts.append("\(dataDir):count=\(dataEntries.count)")
                }
            }
        }
        return parts.joined(separator: "|")
    }

    private static func describe(path: String, fileManager: FileManager) -> String {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return "\(path):absent"
        }
        let size = (attributes[.size] as? Int) ?? -1
        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "\(path):\(size):\(mtime)"
    }
}
```

- [ ] **Step 4: Прогнать тесты — зелёные**

Run: `swift test --filter RunnerProcessProgressWaiterTests 2>&1 | tail -3`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleTools/RunnerProcessProgressWaiter.swift Tests/AppleToolsTests/RunnerProcessProgressWaiterTests.swift
git commit -m "AQA-7496 RunnerProcessProgressWaiter: file-progress guard with silence+hardCap"
```

---

### Task 3: Событие `streamReadingAborted()` — передача поста

**Files:**
- Modify: `Sources/Runner/TestRunnerStream.swift`
- Modify: `Sources/Runner/CompositeTestRunnerStream.swift`
- Modify: `Sources/Runner/PreflightPostflightTimeoutTrackingTestRunnerStream.swift`
- Test: `Tests/RunnerTests/PreflightPostflightTimeoutTrackingTestRunnerStreamTests.swift`

**Interfaces:**
- Produces: `TestRunnerStream.streamReadingAborted()` — дефолтная реализация пустая; композит форвардит; событийный страж останавливает таймер. Task 5 вызывает его из владельца.

- [ ] **Step 1: Написать падающий тест**

Добавить в `Tests/RunnerTests/PreflightPostflightTimeoutTrackingTestRunnerStreamTests.swift` (стиль файла: `DateProviderFixture`, инвертированные expectation):

```swift
    func test___postflight_is_not_called___after_stream_reading_aborted() {
        preflightExpectation.isInverted = true
        postflightExpectation.isInverted = true

        testStream.openStream()
        testStream.testStarted(testName: TestName(className: "class", methodName: "test"))
        testStream.testStopped(
            testStoppedEvent: TestStoppedEvent(
                testName: TestName(className: "class", methodName: "test"),
                result: .success,
                testDuration: 1,
                testExceptions: [],
                logs: [],
                testStartTimestamp: dateProvider.dateSince1970ReferenceDate()
            )
        )
        testStream.streamReadingAborted()
        dateProvider.result += 5

        wait(for: [preflightExpectation, postflightExpectation], timeout: 5)
    }
```

Сигнатуру `TestStoppedEvent` при расхождении взять из существующего `FLAKY_test___postflight_is_called…` в этом же файле.

- [ ] **Step 2: Прогнать — не компилируется**

Run: `swift test --filter PreflightPostflightTimeoutTrackingTestRunnerStreamTests 2>&1 | tail -3`
Expected: compile error «no member streamReadingAborted».

- [ ] **Step 3: Реализация**

`Sources/Runner/TestRunnerStream.swift` — добавить в протокол и extension:

```swift
public protocol TestRunnerStream {
    func openStream()
    func testStarted(testName: TestName)
    func caughtException(testException: TestException)
    func logCaptured(entry: TestLogEntry)
    func testStopped(testStoppedEvent: TestStoppedEvent)
    func closeStream()

    /// Reading of the runner's result stream has ended while the runner process may still
    /// be alive (e.g. stream parse failure). No further events can arrive; event-based
    /// silence watchdogs must stand down — file-based progress guarding takes over.
    func streamReadingAborted()
}

public extension TestRunnerStream {
    func streamReadingAborted() {}
}
```

`Sources/Runner/CompositeTestRunnerStream.swift` — добавить метод:

```swift
    public func streamReadingAborted() {
        testRunnerStreams.forEach { $0.streamReadingAborted() }
    }
```

`Sources/Runner/PreflightPostflightTimeoutTrackingTestRunnerStream.swift` — добавить метод (рядом с `closeStream`):

```swift
    public func streamReadingAborted() {
        // События больше не придут — тишина по ним не признак зависания.
        // Пост принимает файловый страж (RunnerProcessProgressWaiter).
        stopAnyTracking()
    }
```

- [ ] **Step 4: Прогнать — зелёные; сборка**

Run: `swift test --filter PreflightPostflightTimeoutTrackingTestRunnerStreamTests 2>&1 | tail -3 && swift build 2>&1 | tail -2`
Expected: PASS (новый тест), `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/Runner/TestRunnerStream.swift Sources/Runner/CompositeTestRunnerStream.swift Sources/Runner/PreflightPostflightTimeoutTrackingTestRunnerStream.swift Tests/RunnerTests/PreflightPostflightTimeoutTrackingTestRunnerStreamTests.swift
git commit -m "AQA-7496 streamReadingAborted: event-based watchdog stands down when stream reading dies"
```

---

### Task 4: Разоружение килла в TestTimeout-трекере

**Files:**
- Modify: `Sources/Runner/Runner.swift` (обработчик `detectedLongRunningTest`, ~строка 163)

**Interfaces:**
- Consumes: ничего нового. Синтетический `TestStoppedEvent(.failure)` и warning-лог трекера остаются нетронутыми.

- [ ] **Step 1: Правка**

В `Sources/Runner/Runner.swift` в замыкании `detectedLongRunningTest` (внутри `TestTimeoutTrackingTestRunnerSream(...)`) удалить строку:

```swift
                        testRunnerRunningInvocationContainer.currentValue()?.cancel()
```

и на её месте оставить комментарий:

```swift
                        // НЕ убиваем хост-процесс: килл здесь кладёт весь бакет (недописанный
                        // xcresult → стабы на все тесты в отчёте). Историческая семантика:
                        // тест помечен упавшим синтетическим событием выше и уйдёт в ретрай,
                        // зависшее приложение добивает симуляторный watchdog (watchdogSettings).
                        // Лечение истинно-мёртвого раннера — spec 2026-07-23, раздел «Отложено».
```

- [ ] **Step 2: Сборка + проверка, что киллов из этого замыкания нет**

Run: `swift build 2>&1 | tail -2 && grep -n -A24 "detectedLongRunningTest: " Sources/Runner/Runner.swift | grep -c "cancel()"`
Expected: `Build complete!`, затем `0`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Runner/Runner.swift
git commit -m "AQA-7496 disarm bucket kill in long-running-test handler (synthetic failure + retry keep working)"
```

---

### Task 5: Путь ожидания у владельца

**Files:**
- Modify: `Sources/Runner/TestRunner.swift` (протокол `TestRunner.prepareTestRun` — новый параметр)
- Modify: `Sources/Runner/Runner.swift` (вызов `prepareTestRun`, ~строка 228)
- Modify: `Sources/Runner/FailureReportingTestRunnerProxy.swift` (форвард параметра)
- Modify: `Tests/RunnerTestHelpers/FakeTestRunner.swift` (сигнатура, :70)
- Modify: `Sources/AppleTools/XcodebuildBasedTestRunner.swift` (сигнатура + completion-блок `streamContents`, :99-126)

**Interfaces:**
- Consumes: `RunnerProcessProgressWaiter`, `FileActivityMarker` (Task 2), `streamReadingAborted()` (Task 3), `TestTimeoutConfiguration.bucketShutdownHardCap` (Task 1).
- Produces: `prepareTestRun(buildArtifacts:developerDirLocator:entriesToRun:logger:testContext:testRunnerStream:testTimeoutConfiguration:)` — новая сигнатура протокола `TestRunner`.

- [ ] **Step 1: Расширить протокол `TestRunner`**

`Sources/Runner/TestRunner.swift`:

```swift
public protocol TestRunner {
    func additionalEnvironment(
        testRunnerWorkingDirectory: AbsolutePath
    ) -> [String: String]

    func prepareTestRun(
        buildArtifacts: IosBuildArtifacts,
        developerDirLocator: DeveloperDirLocator,
        entriesToRun: [TestEntry],
        logger: ContextualLogger,
        testContext: TestContext,
        testRunnerStream: TestRunnerStream,
        testTimeoutConfiguration: TestTimeoutConfiguration
    ) throws -> TestRunnerInvocation
}
```

- [ ] **Step 2: Обновить всех вызывающих/конформеров (компилятор — чеклист)**

`Sources/Runner/Runner.swift` (~:228) — добавить аргумент:

```swift
        let runningInvocation = try testRunner.prepareTestRun(
            buildArtifacts: configuration.buildArtifacts,
            developerDirLocator: developerDirLocator,
            entriesToRun: entriesToRun,
            logger: logger,
            testContext: testContext,
            testRunnerStream: testRunnerStream,
            testTimeoutConfiguration: configuration.testTimeoutConfiguration
        ).startExecutingTests()
```

`Sources/Runner/FailureReportingTestRunnerProxy.swift` — добавить параметр и прокинуть:

```swift
    public func prepareTestRun(
        buildArtifacts: IosBuildArtifacts,
        developerDirLocator: DeveloperDirLocator,
        entriesToRun: [TestEntry],
        logger: ContextualLogger,
        testContext: TestContext,
        testRunnerStream: TestRunnerStream,
        testTimeoutConfiguration: TestTimeoutConfiguration
    ) throws -> TestRunnerInvocation {
        do {
            return try testRunner.prepareTestRun(
                buildArtifacts: buildArtifacts,
                developerDirLocator: developerDirLocator,
                entriesToRun: entriesToRun,
                logger: logger,
                testContext: testContext,
                testRunnerStream: testRunnerStream,
                testTimeoutConfiguration: testTimeoutConfiguration
            )
        } catch {
            return generateFailureResults(
                entriesToRun: entriesToRun,
                runnerError: error,
                testRunnerStream: testRunnerStream
            )
        }
    }
```

`Tests/RunnerTestHelpers/FakeTestRunner.swift:70` — добавить параметр `testTimeoutConfiguration: TestTimeoutConfiguration` (в теле не использовать).

`Sources/AppleTools/XcodebuildBasedTestRunner.swift` — добавить параметр в `prepareTestRun`.

- [ ] **Step 3: Переписать completion-блок `streamContents` в `XcodebuildBasedTestRunner.swift` (:107-120)**

Было (для ориентира): `error → лог → readResultBundle → closeStream`. Стало:

```swift
            resultStream.streamContents { [weak self] error in
                if let error = error {
                    logger.error("Result stream error: \(error)", subprocessPidInfo: sender.subprocessInfo.pidInfo)
                    // улика для расследования порчи стрима (дефект A)
                    logger.error("Result stream file state: \(FileActivityMarker.marker(paths: [resultStreamFile]))")
                }

                // Билдер автономен: конец НАШЕГО чтения (в т.ч. по ошибке парсера) не означает
                // конца исполнения тестов. Процесс финализирует xcresult в самом конце жизни —
                // убивать его здесь нельзя (гонка с финализацией = нечитаемый бандл = весь бакет
                // стабится в отчёте). Событийный страж слепнет без событий — глушим его и ждём
                // выхода процесса по файловому прогрессу; убиваем только вставших/переживших cap.
                testRunnerStream.streamReadingAborted()

                if let strongSelf = self {
                    RunnerProcessProgressWaiter(
                        logger: logger,
                        maximumSilenceDuration: testTimeoutConfiguration.testRunnerMaximumSilenceDuration,
                        hardCap: testTimeoutConfiguration.bucketShutdownHardCap
                    ).waitForExit(
                        isProcessRunning: { sender.isProcessRunning },
                        progressMarker: { FileActivityMarker.marker(paths: [resultStreamFile, xcresultBundlePath]) },
                        killProcess: {
                            sender.interruptAndForceKillIfNeeded()
                            sender.waitForProcessToDie()
                        }
                    )
                    strongSelf.readResultBundle(
                        path: xcresultBundlePath,
                        testRunnerStream: testRunnerStream
                    )
                }

                testRunnerStream.closeStream()
            }
```

Проверить имена локальных переменных по фактическому коду блока (`sender`, `resultStreamFile`, `xcresultBundlePath` — все в области видимости `onStart`/`prepareTestRun`; при расхождении имён использовать фактические).

- [ ] **Step 4: Сборка + тесты затронутых таргетов**

Run: `swift build 2>&1 | tail -2 && swift test --filter AppleToolsTests 2>&1 | tail -3 && swift test --filter RunnerTests 2>&1 | tail -3`
Expected: `Build complete!`, тесты PASS (правки сигнатур в фикстурах — по ошибкам компилятора).

- [ ] **Step 5: Commit**

```bash
git add Sources/Runner/TestRunner.swift Sources/Runner/Runner.swift Sources/Runner/FailureReportingTestRunnerProxy.swift Tests/RunnerTestHelpers/FakeTestRunner.swift Sources/AppleTools/XcodebuildBasedTestRunner.swift
git commit -m "AQA-7496 owner waits for runner exit by file progress before reading bundle and closing stream"
```

---

### Task 6: Разоружение #1.3 + `performPostRunCleanup()`

**Files:**
- Modify: `Sources/Runner/TestRunner.swift` (протокол `TestRunnerRunningInvocation`)
- Modify: `Sources/Runner/ProcessControllerWrappingTestRunnerInvocation.swift`
- Modify: `Sources/Runner/Runner.swift` (блок #1.3, ~:252-256)

**Interfaces:**
- Produces: `TestRunnerRunningInvocation.performPostRunCleanup()` (дефолт — пустой). `cancel()` не меняется — им пользуются легитимные таймаут-обработчики (preflight/postflight, silence).

- [ ] **Step 1: Протокол**

`Sources/Runner/TestRunner.swift`:

```swift
public protocol TestRunnerRunningInvocation {
    var pidInfo: PidInfo { get }
    func cancel()
    func wait()

    /// Cleanup for the normal end-of-bucket path: the host process is already dead by now,
    /// only auxiliary cleanup (in-simulator apps) must happen here. No killing.
    func performPostRunCleanup()
}

public extension TestRunnerRunningInvocation {
    func performPostRunCleanup() {}
}
```

- [ ] **Step 2: Реализация у обёртки + правка лживого лога**

`Sources/Runner/ProcessControllerWrappingTestRunnerInvocation.swift` — добавить метод и переписать текст в `cancel()`:

```swift
    public func cancel() {
        // Аварийное завершение (таймауты тишины/длинного теста): убиваем host-процесс
        // сигналом напрямую по pid (см. CLT DefaultProcessController.send(signal:)),
        // затем зачищаем приложения внутри симулятора.
        let pid = processController.processId
        let name = processController.processName
        logger.debug("cancel(): killing test runner host process (pid \(pid), name '\(name)')")
        processController.terminateAndForceKillIfNeeded()
        logger.debug("cancel(): host process pid \(pid) ('\(name)') killed; starting in-simulator app cleanup")
        onCancel()
        logger.debug("cancel(): in-simulator app cleanup finished for host pid \(pid) ('\(name)')")
    }

    public func performPostRunCleanup() {
        let pid = processController.processId
        logger.debug("postRunCleanup(): host process pid \(pid) already exited; running in-simulator app cleanup")
        onCancel()
        logger.debug("postRunCleanup(): in-simulator app cleanup finished for host pid \(pid)")
    }
```

- [ ] **Step 3: Блок #1.3 в `Runner.runOnce`**

Заменить блок после `streamClosedCallback.wait(...)` (сейчас: комментарий + `cancel()` + `wait()`):

```swift
        // Стрим закрыт. Хост-процесс к этому моменту мёртв на всех путях: штатно стрим
        // закрывается его терминацией, а при ошибке чтения владелец (XcodebuildBasedTestRunner)
        // дожидается выхода/добивает вставшего ДО closeStream. Убивать здесь нечего и нельзя
        // (гонка с финализацией xcresult — spec 2026-07-23-bucket-shutdown-design). Остаётся
        // только зачистка приложений внутри симулятора перед освобождением сима (анти-каскад).
        if let runningInvocation = testRunnerRunningInvocationContainer.currentValue() {
            runningInvocation.wait()
            runningInvocation.performPostRunCleanup()
        }
```

- [ ] **Step 4: Сборка + тесты**

Run: `swift build 2>&1 | tail -2 && swift test --filter RunnerTests 2>&1 | tail -3`
Expected: `Build complete!`, PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Runner/TestRunner.swift Sources/Runner/ProcessControllerWrappingTestRunnerInvocation.swift Sources/Runner/Runner.swift
git commit -m "AQA-7496 disarm stream-close kill: wait + in-sim cleanup only (kill stays in timeout handlers)"
```

---

### Task 7: Зачистка устаревших комментариев про групповой килл

**Files:**
- Modify: `Sources/SimulatorVideoRecorder/CancellableRecordingImpl.swift` (комментарии :19-23, :44-50)

- [ ] **Step 1: Обновить комментарии**

В `stopRecording()` заменить комментарий на:

```swift
        // Шлём SIGINT напрямую по PID: simctl recordVideo корректно финализирует mp4 по SIGINT.
        // SIGKILL нельзя — обрежет недописанный файл. (Исторический контекст: до CLT-фикса
        // f77f0c0 групповой kill(-pid) в ProcessController был ESRCH no-op; сейчас доставка
        // сигналов работает, прямой kill здесь остаётся как независимый от обвязки путь.)
```

В `cancelRecording()` заменить комментарий на:

```swift
        // Отмена записи: мягкий SIGINT (recordVideo отпускает GPU-ресурсы и выходит),
        // bounded-ожидание, SIGKILL — только зависшему. Файл затем удаляется (это отмена).
        // Жёсткий SIGKILL посреди захвата подозревался в деградации paravirt-GPU стека.
```

- [ ] **Step 2: Сборка + Commit**

Run: `swift build 2>&1 | tail -2`
Expected: `Build complete!`

```bash
git add Sources/SimulatorVideoRecorder/CancellableRecordingImpl.swift
git commit -m "AQA-7496 update stale comments about group kill (direct pid since CLT f77f0c0)"
```

---

### Task 8: Полный прогон, стенд, деплой 16.0.12

**Files:** нет правок кода.

- [ ] **Step 1: Полная сборка и весь набор юнитов затронутых таргетов**

Run: `swift build 2>&1 | tail -2 && swift test --filter "RunnerProcessProgressWaiterTests|PreflightPostflightTimeoutTrackingTestRunnerStreamTests|TestTimeoutConfigurationDecodingTests" 2>&1 | tail -5`
Expected: всё зелёное.

- [ ] **Step 2: Стенд emcee1 — имитация S3 (ошибка чтения при живом билдере)**

По методике B0 (артефакты в `/Users/jenkins/emcee/*/emceeBinary/tempFolder/.../testrun.xctestrun`, свежий сим в default set), бинарь Emcee — свежесобранный, доставить на стенд и запустить бакет через воркер-путь ЛИБО локально повторить связку: во время живого прогона выполнить на стенде:

```bash
echo 'garbage-not-a-json' >> <runnerWorkingDir>/result_stream.json
```

Проверить:
- worker-лог: «Result stream error» + «Result stream file state» + путь ожидания (нет мгновенного килла);
- билдер дожил до конца, все тесты выполнены;
- бандл читаем: `xcrun xcresulttool get object --path resultBundle.xcresult` без exit 64;
- мусорного `Error parsing xcresult bundle … exit code 64` в результатах нет.

- [ ] **Step 3: Стенд — имитация S5 (вставший билдер)**

Во время пути ожидания: `kill -STOP <pid xcodebuild>` → через `testRunnerMaximumSilenceDuration` прогресс-страж добивает (лог «no file activity … killing»), слот освобождён.

- [ ] **Step 4: Стенд — штатный прогон**

Обычный бакет без вмешательств: зазор «Finished executing tests → Did get» остаётся ~1с, поведение не изменилось.

- [ ] **Step 5: Деплой бинаря (без CI)**

```bash
cd /Users/p.starodubkin/Documents/repo/Emcee && swift build 2>&1 | tail -2
curl -s -w "HTTP %{http_code}\n" -u iostestbuild:Iefai3Ae -X PUT \
  "https://jfrog.space307.tech/ios-test-build/emcee/16.0.12/Emcee" -T .build/debug/Emcee | tail -3
```

Expected: HTTP 201. vars.groovy/testargbase НЕ трогать — включение в CI отдельным решением пользователя (добавление `bucketShutdownHardCap` в testargbase — вместе с включением).
