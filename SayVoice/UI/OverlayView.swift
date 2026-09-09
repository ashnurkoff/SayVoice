import SwiftUI

struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        ZStack {
            // Прозрачная подложка во весь размер панели. Без неё в состоянии .hidden
            // дерево вью пустое, hosting view «схлопывается» под содержимое и утягивает
            // за собой окно: панель становится ровно по карточке (тень обрезается краем
            // окна и остаётся видна только в вырезах у скруглённых углов), а следующий
            // показ центрируется по схлопнувшемуся размеру и уезжает вправо.
            // Color.clear ничего не рисует и не анимируется — рендер-цикл не будит.
            Color.clear

            // .hidden: пустая карточка — иначе анимации в спрятанной панели
            // продолжают гонять рендер-цикл на 60fps и жгут CPU в простое.
            if model.displayState != .hidden {
                GlassCard {
                    contentView
                }
                .animation(.easeInOut(duration: 0.2), value: model.displayState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentView: some View {
        switch model.displayState {
        case .hidden:
            EmptyView()

        case .recording:
            RecordingContent(model: model)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))

        case .transcribing:
            TranscribingContent()
                .transition(.opacity.combined(with: .scale(scale: 0.97)))

        case .result:
            ResultContent(text: model.message)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))

        case .error:
            ErrorContent(message: model.message)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

// MARK: - Glass Card

/// Стеклянная карточка: настоящий Liquid Glass на macOS 26+,
/// фолбэк на ultraThinMaterial со стеклянными акцентами на старых системах.
private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    var body: some View {
        paddedContent
            .overlay {
                // Градиентная окантовка: светлее сверху — эффект преломления кромки
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 10)
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 1)
    }

    @ViewBuilder
    private var paddedContent: some View {
        let padded = content
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

        if #available(macOS 26.0, *) {
            padded.glassEffect(
                .regular.tint(Color(red: 0.42, green: 0.36, blue: 1.0).opacity(0.12)),
                in: shape
            )
        } else {
            padded
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.42, green: 0.36, blue: 1.0).opacity(0.10),
                                        Color(red: 0.42, green: 0.36, blue: 1.0).opacity(0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        .overlay(alignment: .top) {
                            // Блик по верхней кромке
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 22)
                            .clipShape(shape)
                        }
                }
                .clipShape(shape)
        }
    }
}

// MARK: - Recording

private struct RecordingContent: View {
    let model: OverlayModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                PulsingDot()

                Text("Запись")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                RecordingTimer(startDate: model.recordingStart)
            }

            EqualizerView(model: model)
                .frame(height: 88)

            // В режиме удержания запись кончается сама — подсказка не нужна.
            if model.isToggleMode {
                HStack(spacing: 10) {
                    Text(model.hotkeyName.isEmpty
                         ? "Чтобы завершить — нажмите хоткей ещё раз"
                         : "Чтобы завершить — нажмите \(model.hotkeyName) ещё раз")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    StopButton { model.onStop?() }
                }
            }
        }
        .frame(width: 440)
    }
}

/// Кнопка остановки записи в оверлее. Нужна в режиме переключателя: там запись
/// не заканчивается сама, и должен быть способ остановить её мышью.
private struct StopButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Завершить")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Color.primary.opacity(isHovering ? 0.20 : 0.12))
            }
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(isHovering ? 0.32 : 0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.red.opacity(0.4), lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .scaleEffect(isPulsing ? 1.9 : 1.0)
                .opacity(isPulsing ? 0 : 0.8)

            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.7), radius: 5)
        }
        .frame(width: 24, height: 24)
        .onAppear {
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

/// Танцующий зеркальный эквалайзер: бары стоят на месте и активно двигаются
/// вверх-вниз. У каждого бара свой характер (чувствительность и частота
/// колебаний), быстрый подъём на звук и плавное опадание; уровень расходится
/// лёгкой «рябью» от центра к краям. Один Canvas — один проход отрисовки.
private struct EqualizerView: View {
    let model: OverlayModel

    private let barCount = 27
    private let barSpacing: CGFloat = 5

    @State private var engine = BarEngine()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                engine.step(now: now, history: model.levelHistory, barCount: barCount)

                let slot = size.width / CGFloat(barCount)
                let barWidth = max(2, slot - barSpacing)
                let axisY = size.height / 2
                let maxHalf = axisY - 3

                let gradient = Gradient(colors: [
                    Color(red: 0.48, green: 0.42, blue: 1.0),
                    Color(red: 0.85, green: 0.86, blue: 1.0)
                ])

                var reflection = ctx
                reflection.opacity = 0.32

                for k in 0..<barCount {
                    let h = min(maxHalf, max(3, engine.heights[k] * maxHalf))

                    let x = CGFloat(k) * slot + barSpacing / 2
                    let radius = min(barWidth / 2, h / 2)

                    let topRect = CGRect(x: x, y: axisY - h, width: barWidth, height: h)
                    ctx.fill(
                        Path(roundedRect: topRect, cornerRadius: radius),
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: axisY),
                            endPoint: CGPoint(x: 0, y: 0)
                        )
                    )

                    let mh = h * 0.55
                    let botRect = CGRect(x: x, y: axisY + 3, width: barWidth, height: mh)
                    reflection.fill(
                        Path(roundedRect: botRect, cornerRadius: min(radius, mh / 2)),
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: axisY),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                }
            }
        }
    }
}

private struct RecordingTimer: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startDate))
            let mins = Int(elapsed) / 60
            let secs = Int(elapsed) % 60
            Text(String(format: "%d:%02d", mins, secs))
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .monospacedDigit()
        }
    }
}

// MARK: - Transcribing

private struct TranscribingContent: View {
    var body: some View {
        HStack(spacing: 12) {
            BouncingDots()
            Text("Транскрибирую...")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 220)
    }
}

private struct BouncingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color(red: 0.55, green: 0.50, blue: 1.0))
                    .frame(width: 7, height: 7)
                    .offset(y: phase == index ? -5 : 0)
                    .opacity(phase == index ? 1.0 : 0.55)
            }
        }
        .frame(width: 30, height: 18)
        // .task отменяется при удалении вью — repeating Timer здесь
        // никогда не инвалидировался и продолжал анимировать скрытую панель.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

// MARK: - Result

private struct ResultContent: View {
    let text: String
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18))
                .scaleEffect(appeared ? 1.0 : 0.3)
                .opacity(appeared ? 1.0 : 0)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .opacity(appeared ? 1.0 : 0)
                .offset(x: appeared ? 0 : 6)
        }
        .frame(minWidth: 220, maxWidth: 420)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - Error

private struct ErrorContent: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 17))
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(minWidth: 220, maxWidth: 420)
    }
}
