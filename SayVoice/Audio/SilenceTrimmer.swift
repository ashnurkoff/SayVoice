import Foundation

/// Обрезка тишины и детекция «пустых» записей.
///
/// Whisper галлюцинирует на тишине/тихом аудио: обученный на ютуб-субтитрах, он на
/// пустом входе выдаёт клише вроде «Спасибо за субтитры…» / «Thank you for watching».
/// Тот же эффект даёт хвостовая пауза в конце длинной диктовки — модель «дописывает»
/// последнее окно клише вместо реального текста.
///
/// Решение до whisper:
///  - если речи нет вообще → пропустить транскрипцию (ничего не вставлять);
///  - иначе отрезать ведущую/хвостовую тишину, оставив небольшой паддинг.
///
/// Чистая функция без зависимостей — тестируется отдельно от приложения.
enum SilenceTrimmer {

    /// 16 kHz mono — формат, в котором аудио приходит из AudioConverter.
    static let sampleRate = 16_000

    /// Длина кадра для оценки энергии: 30 мс.
    static let frameLength = 480

    /// Порог речи по RMS кадра. Тишина комнаты после HP-фильтра ≈ −60…−50 dBFS,
    /// речь ≈ −35…−20 dBFS, тихая речь ≈ −42 dBFS. 0.005 ≈ −46 dBFS — консервативно:
    /// уверенно ловит тишину и почти наверняка не режет реальную речь.
    static let speechRMSThreshold: Float = 0.005

    /// Паддинг вокруг речи, чтобы не подрезать тихие начала/окончания слов: ~240 мс.
    static let padFrames = 8

    /// Сколько кадров должно быть речевыми, чтобы считать запись непустой: 10 × 30 мс = 0.3 с.
    ///
    /// Раньше хватало ОДНОГО кадра выше порога — случайный стук по столу или щелчок
    /// кнопки проходили за речь, и whisper на такой записи дописывал initial_prompt:
    /// в историю падали обрывки инструкции («Расшифровка ведёт к нам и решёт эту файл»)
    /// и классический мусор вроде «Игорь Негода». В реальной диктовке речевых кадров
    /// больше половины (замер: 62% на 21-секундной записи), так что порог с запасом.
    static let minSpeechFrames = 10

    /// Диапазон сэмплов, содержащих речь (с паддингом), или nil, если речи нет.
    static func speechRange(
        _ samples: [Float],
        frameLength: Int = frameLength,
        threshold: Float = speechRMSThreshold,
        padFrames: Int = padFrames,
        minSpeechFrames: Int = minSpeechFrames
    ) -> Range<Int>? {
        guard !samples.isEmpty, frameLength > 0 else { return nil }

        var firstSpeechFrame = -1
        var lastSpeechFrame = -1
        var speechFrames = 0
        var frameStart = 0
        var frameIndex = 0

        while frameStart < samples.count {
            let frameEnd = min(frameStart + frameLength, samples.count)
            var sumSquares: Float = 0
            var i = frameStart
            while i < frameEnd {
                let s = samples[i]
                sumSquares += s * s
                i += 1
            }
            let count = frameEnd - frameStart
            let rms = count > 0 ? (sumSquares / Float(count)).squareRoot() : 0
            if rms >= threshold {
                if firstSpeechFrame < 0 { firstSpeechFrame = frameIndex }
                lastSpeechFrame = frameIndex
                speechFrames += 1
            }
            frameStart = frameEnd
            frameIndex += 1
        }

        // Речи нет вообще либо её слишком мало, чтобы это была диктовка.
        guard firstSpeechFrame >= 0, speechFrames >= minSpeechFrames else { return nil }

        let start = max(0, (firstSpeechFrame - padFrames) * frameLength)
        let end = min(samples.count, (lastSpeechFrame + 1 + padFrames) * frameLength)
        return start..<end
    }

    /// Обрезает ведущую/хвостовую тишину. Возвращает nil, если речи нет —
    /// вызывающий код должен в этом случае пропустить транскрипцию.
    static func trim(_ samples: [Float]) -> [Float]? {
        guard let range = speechRange(samples) else { return nil }
        if range.lowerBound == 0 && range.upperBound == samples.count {
            return samples
        }
        return Array(samples[range])
    }
}
