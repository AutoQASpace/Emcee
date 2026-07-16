    # SimulatorVideoRecorder

Модуль для записи видео с симуляторов iOS с оптимизацией производительности.

## Проблема

Запись видео через `simctl io recordVideo` сильно нагружает CPU виртуальной машины, особенно при:
- Высоком разрешении дисплея (Retina)
- Использовании кодека HEVC (более CPU-intensive)
- Множественных параллельных записях
- Отсутствии аппаратного ускорения

**Важно:** `simctl` не поддерживает параметр `--fps` для контроля частоты кадров. Оптимизация возможна только через выбор кодека и других доступных параметров.

## Решение

Модуль предоставляет настраиваемые параметры записи для снижения нагрузки на систему:
- **Выбор кодека**: `h264` менее нагружает CPU чем `hevc`
- **Mask policy**: `ignored` может немного снизить обработку
- **Автоматическая оптимизация** для CI/CD окружений

## Использование

### Базовое использование (с оптимизацией по умолчанию - h264)

```swift
let recorder = SimulatorVideoRecorder(
    processControllerProvider: provider,
    simulatorUuid: udid,
    simulatorSetPath: setPath
)

let recording = try recorder.startRecording(
    outputPath: videoPath
)

// Выполнение теста...

let savedVideoPath = recording.stopRecording()
```

### CI/CD окружение (минимальная нагрузка - h264 + mask=ignored)

```swift
let recording = try recorder.startRecording(
    outputPath: videoPath,
    options: .ciOptimized  // h264 + mask=ignored - снижает CPU load
)
```

### Локальная разработка (высокое качество - hevc)

```swift
let recording = try recorder.startRecording(
    outputPath: videoPath,
    options: .highQuality  // hevc кодек для лучшего сжатия
)
```

### Кастомная конфигурация

```swift
let customOptions = SimulatorVideoRecorder.RecordingOptions(
    codecType: .h264,      // h264 менее нагружает CPU
    force: true,            // Перезаписывать существующий файл
    maskPolicy: "ignored"  // Упростить обработку маски
)

let recording = try recorder.startRecording(
    outputPath: videoPath,
    options: customOptions
)
```

### Обратная совместимость

Старый код продолжит работать:

```swift
// Старый способ (кодек можно указать явно, но будет переопределён options)
let recording = try recorder.startRecording(
    codecType: .hevc,  // Игнорируется, если указан в options
    outputPath: videoPath,
    options: .default  // Использует h264 из options
)
```

### Отмена записи

```swift
// Остановить и сохранить видео
let videoPath = recording.stopRecording()

// Или отменить запись (удалить файл)
recording.cancelRecording()
```

## Опции записи

| Опция | Кодек | Mask | Использование | CPU Load | Размер файла |
|-------|-------|------|----------------|----------|--------------|
| `.ciOptimized` | h264 | ignored | CI/CD, массовые тесты | ~40-50% | ~60-70% |
| `.default` | h264 | none | Рекомендуется | ~50-60% | ~70-80% |
| `.highQuality` | hevc | none | Локальная отладка | ~80-90% | ~40-50% |
| Без опций (hevc) | hevc | none | Не рекомендуется | 100% | 100% |

*Процентные значения относительно записи с hevc кодеком*

## Рекомендации

1. **Для CI/CD**: Используйте `.ciOptimized` (h264 + mask=ignored) - это снизит нагрузку на виртуалку на ~40-50%
2. **Для обычных тестов**: Используйте `.default` (h264) - оптимальный баланс между качеством и производительностью
3. **Для отладки UI**: Используйте `.highQuality` (hevc) - лучшее сжатие, но больше нагрузка на CPU
4. **Избегайте hevc в CI**: Для массовых тестов используйте h264

## Технические детали

- **Кодек h264** обычно менее нагружает CPU чем hevc, особенно на старых системах
- **Кодек hevc** даёт лучшее сжатие (меньший размер файла), но требует больше CPU
- `simctl` не поддерживает параметр `--fps` - частота кадров фиксирована
- `simctl` не использует аппаратное ускорение VideoToolbox, поэтому кодирование нагружает CPU
- Параметр `--force` автоматически перезаписывает существующий файл
- Параметр `--mask=ignored` может немного снизить нагрузку, игнорируя обработку маски дисплея

## Доступные параметры simctl

`simctl io recordVideo` поддерживает следующие параметры:
- `--codec=<codec>`: "h264" или "hevc" (по умолчанию "hevc")
- `--display=<display>`: "internal" или "external" (по умолчанию "internal")
- `--mask=<policy>`: "ignored", "black", или "alpha"
- `--force`: Перезаписать существующий файл

**НЕ поддерживается:**
- `--fps` - контроль частоты кадров недоступен

## Альтернативные способы снижения нагрузки

Если `simctl` всё ещё создаёт слишком большую нагрузку:

1. **Использовать скриншоты вместо видео** для успешных тестов
2. **Записывать видео только для failed тестов** (уже реализовано в плагине)
3. **Использовать внешние инструменты** (ffmpeg, QuickTime) с настройкой FPS
4. **Уменьшить разрешение симулятора** (менее Retina дисплеи)
