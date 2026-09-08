#include "include/whisper_bridge.h"
#include "whisper.h"
#include <cstring>
#include <string>
#include <cstdio>

// Custom log callback — only show errors and key info
static void sayvoice_log_callback(enum ggml_log_level level, const char* text, void* /*user_data*/) {
    if (level >= GGML_LOG_LEVEL_ERROR) {
        fprintf(stderr, "%s", text);
        return;
    }
    // Pass through key diagnostic lines
    if (text && (
        strstr(text, "GPU name:")    ||
        strstr(text, "GPU family:")  ||
        strstr(text, "model size")   ||
        strstr(text, "type")         ||
        strstr(text, "Metal total")  ||
        strstr(text, "auto-detected language")
    )) {
        fprintf(stderr, "%s", text);
    }
}

whisper_context* whisper_bridge_init(const char* model_path) {
    whisper_log_set(sayvoice_log_callback, nullptr);

    struct whisper_context_params params = whisper_context_default_params();
    params.use_gpu = true;
    return whisper_init_from_file_with_params(model_path, params);
}

void whisper_bridge_free(whisper_context* ctx) {
    if (ctx) whisper_free(ctx);
}

char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,
    int32_t               n_samples,
    SayVoiceWhisperParams bridge_params
) {
    if (!ctx || !samples || n_samples <= 0) return nullptr;

    const bool use_beam = bridge_params.beam_size > 1;
    struct whisper_full_params params = whisper_full_default_params(
        use_beam ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY);
    params.n_threads        = bridge_params.n_threads;
    params.translate        = bridge_params.translate;
    params.no_timestamps    = bridge_params.no_timestamps;
    params.temperature      = bridge_params.temperature;
    // Подавляем несречевые токены (по умолчанию whisper этого НЕ делает) — меньше
    // хвостовых галлюцинаций-клише на тихих/оборванных сегментах. Основную тишину
    // отсекает SilenceTrimmer до вызова whisper; это дополнительный слой защиты.
    params.suppress_nst     = true;
    params.print_realtime   = false;
    params.print_progress   = false;
    params.print_timestamps = false;
    params.print_special    = false;
    params.single_segment   = false;
    params.language         = bridge_params.language ? bridge_params.language : "auto";
    if (use_beam) {
        params.beam_search.beam_size = bridge_params.beam_size;
    }
    if (bridge_params.initial_prompt && bridge_params.initial_prompt[0] != '\0') {
        params.initial_prompt = bridge_params.initial_prompt;
    }

    int result = whisper_full(ctx, params, samples, n_samples);
    if (result != 0) return nullptr;

    std::string output;
    const int n_segments = whisper_full_n_segments(ctx);
    int64_t prev_t1 = -1; // конец предыдущего сегмента, сотые доли секунды
    for (int i = 0; i < n_segments; ++i) {
        const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
        const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

        // Диагностика потери текста: дыра в таймлайне, перескакивающая через границу
        // 30-секундного окна whisper, = окно сдвинулось целиком и речь на стыке не
        // декодирована. Пауза внутри одного окна — это обычная тишина, не сигналим.
        // Эвристика неточная в одну сторону: настоящая длинная пауза, попавшая ровно
        // на 30/60/90 сек, тоже даст эту строку, хотя текст при этом целый. Строка —
        // подсказка для отладки, а не доказательство потери; сверяйся с текстом.
        const int64_t chunk = 100 * 30; // WHISPER_CHUNK_SIZE в сотых долях секунды
        if (prev_t1 >= 0 && t0 - prev_t1 > 50 && (prev_t1 / chunk) != (t0 / chunk)) {
            fprintf(stderr, "[SayVoice] whisper: window gap %.2fs..%.2fs — dropped speech\n",
                    prev_t1 / 100.0, t0 / 100.0);
        }
        prev_t1 = t1;

        const char* text = whisper_full_get_segment_text(ctx, i);
        if (text) {
            // Whisper отдаёт текст сегмента с ведущим пробелом. С включёнными
            // таймстемпами сегментов много (по фразам), и наивная склейка давала
            // двойные пробелы в итоговом тексте — обрезаем края каждого сегмента
            // и соединяем ровно одним пробелом.
            std::string seg(text);
            const size_t b = seg.find_first_not_of(" \t\n\r");
            if (b == std::string::npos) continue;
            const size_t e = seg.find_last_not_of(" \t\n\r");
            seg = seg.substr(b, e - b + 1);

            if (!output.empty()) output += " ";
            output += seg;
        }
    }

    // Trim whitespace
    size_t start = output.find_first_not_of(" \t\n\r");
    size_t end   = output.find_last_not_of(" \t\n\r");
    if (start == std::string::npos) return nullptr;
    output = output.substr(start, end - start + 1);

    if (output.empty()) return nullptr;

    char* cstr = new char[output.size() + 1];
    std::strcpy(cstr, output.c_str());
    return cstr;
}

void whisper_bridge_free_string(char* str) {
    delete[] str;
}
