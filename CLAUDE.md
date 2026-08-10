# Emcee (форк AutoQASpace)

Распределённый раннер iOS UI-тестов. Апстрим avito-tech не добавлять — линии давно разошлись.

## Юнит-тесты
`swift test` на локальном тулчейне **дедлочит навечно** (swiftpm-xctest-helper спавнит вложенный swift-build, взаимная блокировка лока пакета). Рабочий способ:
```
swift build --build-tests 2>&1 | grep -cE "error:"    # 0 = компиляция чистая
xcrun xctest -XCTest '<ИмяКласса>' .build/debug/EmceeTestRunnerPackageTests.xctest
```
Бандл называется именно `EmceeTestRunnerPackageTests.xctest`.

## Релизная сборка и деплой
- Релизный бинарь — **только из чистой сборки**: `swift package clean && swift build`. Инкрементальная давала франкен-бинарь (модули со старым layout структур → мусор в полях, полевой инцидент с `bucketShutdownHardCap = 3e-314`).
- Версия в бинарь не зашивается (`undefined_version`) — передаётся `--emcee-version` из Jenkins; идентичность бинаря = путь на JFrog. `make.sh build` штампует хеш в EmceeVersion.swift, для нашего флоу это необязательно. `make.sh test` не использовать (внутри `swift test --parallel` = дедлок).
- Новый код = **новый номер версии** (queue reuse и кэш воркеров матчатся по точному совпадению):
```
curl -su iostestbuild:… -X PUT "https://jfrog.space307.tech/ios-test-build/emcee/<ver>/Emcee" -T .build/debug/Emcee
curl -su iostestbuild:… "https://jfrog.space307.tech/api/storage/ios-test-build/emcee/<ver>/Emcee" | grep sha256   # сверить с shasum -a 256 локального
```
- После деплоя: bump `EMCEE_VERSION_NUMBER`/`EMCEE_VERSION_TAG` в `jenkinsfiles/builds/ios/lib/vars.groovy` и пересборка плагина (см. ниже).

## Зависимость CommandLineToolkit
Форк `AutoQASpace/CommandLineToolkit`, ветка `fix_dependency-pid-kill`, тянется **с GitHub** — правки CLT требуют пуша ветки, затем в Emcee:
```
swift package update CommandLineToolkit   # сверить revision в Package.resolved
```

## Синк с EmceeReportPlugin (КРИТИЧНО)
Плагин вкомпиливает исходники модулей Emcee (localSourceControl `../Emcee`, git-checkout ветки — не рабочее дерево). Каждый релиз Emcee = перепин + пересборка + перезаливка плагина. Детали и ловушки — `../emcee-report-plugin/CLAUDE.md`.

## Ловушки xctestrun / xcresult (полевые, дорого доставшиеся)
- `PreferredScreenCaptureFormat`: значения **только camelCase** `screenshots` / `screenRecording` (зашиты в XCTestCore). Аперкейс-варианты из интернета молча игнорируются, а **дефолт при отсутствии ключа = запись видео** (на рантаймах 17+; 15.4/16.4 умеют только скриншоты) — поэтому ключ пишется всегда, в обе стороны.
- `TestTimeoutsEnabled` / `DefaultTestExecutionTimeAllowance` / `MaximumTestExecutionTimeAllowance` — работают в legacy-формате плиста; allowance Apple округляет **вверх до целой минуты** (270 → 300).
- `xcresulttool get` на Xcode 16+ требует `--legacy`, иначе детерминированный exit 64 даже на валидном бандле.
- xcresult финализируется билдером в самом конце жизни процесса: килл xcodebuild до выхода = бандл без Info.plist = весь бакет стабится в отчёте.

## Архитектурные точки входа (для расследований)
- Чтение result stream: `Sources/ResultStream/ResultStream.swift` (JSONReader поверх `BlockingArrayBasedJSONStream` из CLT; контракт — nil только после close).
- Сторожа бакета: `TestTimeoutTrackingTestRunnerSream` (270с детект + stuck-fallback), `RunnerProcessProgressWaiter` (ожидание выхода билдера: silence 900с / hardCap 1800с), `PreflightPostflightTimeoutTrackingTestRunnerStream`.
- Ретраи: `TestingResultAcceptorImpl` (reenqueue + `EMCEE_TEST_IS_RETRY`), `TestHistoryTrackerImpl` (ретрай не тому, кто ронял).
- xctestrun-генерация: `Sources/AppleTools/XcTestRunFileArgument.swift` (env-гейты видео/таймаутов).
