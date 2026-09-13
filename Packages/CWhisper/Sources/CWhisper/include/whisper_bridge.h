#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct whisper_context whisper_context;

typedef struct {
    int     n_threads;
    bool    translate;
    bool    no_timestamps;
    float   temperature;
    const char* language;       // "auto", "ru", "en", etc.
    int     beam_size;          // >1 = beam search, иначе greedy
    const char* initial_prompt; // контекст/словарь для code-switching; NULL = без промпта
} SayVoiceWhisperParams;

whisper_context* whisper_bridge_init(const char* model_path);
void             whisper_bridge_free(whisper_context* ctx);

// Returns heap-allocated UTF-8 string. Free with whisper_bridge_free_string().
// Returns NULL on error or empty result.
char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,
    int32_t               n_samples,
    SayVoiceWhisperParams params
);
void whisper_bridge_free_string(char* str);

// Detects the spoken language from the first 30 seconds of audio.
// Returns a whisper language code ("ru", "en", ...) owned by whisper — do not free —
// or NULL when detection fails.
const char* whisper_bridge_detect_language(
    whisper_context* ctx,
    const float*     samples,
    int32_t          n_samples,
    int              n_threads
);

#ifdef __cplusplus
}
#endif
