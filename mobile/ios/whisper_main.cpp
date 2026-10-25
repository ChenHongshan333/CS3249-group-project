#include "main.h"
#include "whisper.cpp/whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "whisper.cpp/examples/dr_wav.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <mutex>
#include <stdio.h>
#include <string>
#include <thread>
#include <vector>
#include "json/json.hpp"

using json = nlohmann::json;

namespace
{
std::mutex g_whisper_mutex;
struct whisper_context *g_ctx = nullptr;
std::string g_loaded_model;
bool g_log_silenced = false;

void silence_whisper_logs() noexcept
{
    if (!g_log_silenced)
    {
        whisper_set_log_callback(nullptr);
        g_log_silenced = true;
    }
}

struct whisper_context *get_or_load_context(const std::string &model_path) noexcept
{
    silence_whisper_logs();
    if (model_path.empty())
    {
        return nullptr;
    }
    if (g_ctx != nullptr && g_loaded_model == model_path)
    {
        return g_ctx;
    }
    if (g_ctx != nullptr)
    {
        whisper_free(g_ctx);
        g_ctx = nullptr;
        g_loaded_model.clear();
    }
    g_ctx = whisper_init_from_file(model_path.c_str());
    if (g_ctx != nullptr)
    {
        g_loaded_model = model_path;
    }
    return g_ctx;
}
} // namespace

char *jsonToChar(const json &jsonData) noexcept
{
    std::string result = jsonData.dump();
    char *ch = static_cast<char *>(std::malloc(result.size() + 1));
    if (ch == nullptr)
    {
        return nullptr;
    }
    std::memcpy(ch, result.c_str(), result.size() + 1);
    return ch;
}

struct whisper_params
{
    int32_t seed = -1;
    int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());

    int32_t n_processors = 1;
    int32_t offset_t_ms = 0;
    int32_t offset_n = 0;
    int32_t duration_ms = 0;
    int32_t max_context = -1;
    int32_t max_len = 0;
    int32_t best_of = 5;
    int32_t beam_size = -1;

    float word_thold = 0.01f;
    float entropy_thold = 2.40f;
    float logprob_thold = -1.00f;

    bool verbose = false;
    bool print_special_tokens = false;
    bool speed_up = false;
    bool translate = false;
    bool diarize = false;
    bool no_fallback = false;
    bool output_txt = false;
    bool output_vtt = false;
    bool output_srt = false;
    bool output_wts = false;
    bool output_csv = false;
    bool print_special = false;
    bool print_colors = false;
    bool print_progress = false;
    bool no_timestamps = false;
    bool split_on_word = false;

    std::string language = "en";
    std::string prompt;
    std::string model = "models/ggml-tiny.bin";
    std::string audio = "samples/jfk.wav";
    std::vector<std::string> fname_inp = {};
    std::vector<std::string> fname_outp = {};
};

json transcribe(json jsonBody) noexcept
{
    std::lock_guard<std::mutex> lock(g_whisper_mutex);

    whisper_params params;
    params.n_threads = jsonBody.value("threads", 4);
    params.n_processors = jsonBody.value("n_processors", 1);
    params.verbose = jsonBody.value("is_verbose", false);
    params.translate = jsonBody.value("is_translate", false);
    params.language = jsonBody.value("language", std::string("en"));
    params.print_special_tokens = jsonBody.value("is_special_tokens", false);
    params.no_timestamps = jsonBody.value("is_no_timestamps", true);
    params.model = jsonBody.value("model", std::string(""));
    params.audio = jsonBody.value("audio", std::string(""));
    params.split_on_word = jsonBody.value("split_on_word", false);
    params.speed_up = jsonBody.value("speed_up", false);
    params.diarize = jsonBody.value("diarize", false);
    if (jsonBody.contains("prompt") && jsonBody["prompt"].is_string())
    {
        params.prompt = jsonBody["prompt"].get<std::string>();
    }

    json jsonResult;
    jsonResult["@type"] = "transcribe";

    if (params.n_threads < 1)
    {
        params.n_threads = 1;
    }
    if (params.n_processors < 1)
    {
        params.n_processors = 1;
    }

    if (params.language.empty() || params.language == "auto")
    {
        params.language = "auto";
    }
    else if (whisper_lang_id(params.language.c_str()) == -1)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "Unknown language: " + params.language;
        return jsonResult;
    }

    struct whisper_context *ctx = get_or_load_context(params.model);
    if (ctx == nullptr)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "Failed to load model: " + params.model;
        return jsonResult;
    }

    std::string text_result = "";
    const auto fname_inp = params.audio;
    std::vector<float> pcmf32;
    {
        drwav wav;
        if (!drwav_init_file(&wav, fname_inp.c_str(), NULL))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "Failed to open WAV file: " + fname_inp;
            return jsonResult;
        }

        if (wav.channels != 1 && wav.channels != 2)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV must be mono or stereo: " + fname_inp;
            drwav_uninit(&wav);
            return jsonResult;
        }

        if (wav.sampleRate != WHISPER_SAMPLE_RATE)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV must be 16 kHz: " + fname_inp;
            drwav_uninit(&wav);
            return jsonResult;
        }

        if (wav.bitsPerSample != 16)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV must be 16-bit PCM: " + fname_inp;
            drwav_uninit(&wav);
            return jsonResult;
        }

        const int n = static_cast<int>(wav.totalPCMFrameCount);
        std::vector<int16_t> pcm16(n * wav.channels);
        drwav_read_pcm_frames_s16(&wav, n, pcm16.data());
        drwav_uninit(&wav);

        pcmf32.resize(n);
        if (wav.channels == 1)
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[i]) / 32768.0f;
            }
        }
        else
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[2 * i] + pcm16[2 * i + 1]) / 65536.0f;
            }
        }
    }

    {
        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

        wparams.print_realtime = false;
        wparams.print_progress = false;
        wparams.print_timestamps = !params.no_timestamps;
        wparams.print_special = params.print_special_tokens;
        wparams.translate = params.translate;
        wparams.language = params.language.c_str();
        wparams.detect_language = params.language == "auto";
        wparams.n_threads = params.n_threads;
        wparams.split_on_word = params.split_on_word;
        wparams.speed_up = params.speed_up;
        wparams.tdrz_enable = params.diarize;
        wparams.no_context = true;
        wparams.single_segment = true;
        wparams.suppress_blank = true;
        wparams.suppress_non_speech_tokens = true;

        if (!params.prompt.empty())
        {
            wparams.initial_prompt = params.prompt.c_str();
        }

        if (params.split_on_word)
        {
            wparams.max_len = 1;
            wparams.token_timestamps = true;
        }

        const int rc = params.n_processors > 1
            ? whisper_full_parallel(ctx, wparams, pcmf32.data(), pcmf32.size(), params.n_processors)
            : whisper_full(ctx, wparams, pcmf32.data(), pcmf32.size());

        if (rc != 0)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "Failed to process audio: " + fname_inp;
            return jsonResult;
        }

        const int n_segments = whisper_full_n_segments(ctx);
        std::vector<json> segmentsJson = {};

        for (int i = 0; i < n_segments; ++i)
        {
            const char *text = whisper_full_get_segment_text(ctx, i);
            if (text == nullptr)
            {
                continue;
            }
            text_result += std::string(text);
            if (!params.no_timestamps)
            {
                json jsonSegment;
                jsonSegment["from_ts"] = whisper_full_get_segment_t0(ctx, i);
                jsonSegment["to_ts"] = whisper_full_get_segment_t1(ctx, i);
                jsonSegment["text"] = text;
                segmentsJson.push_back(jsonSegment);
            }
        }

        if (!params.no_timestamps)
        {
            jsonResult["segments"] = segmentsJson;
        }
    }

    jsonResult["text"] = text_result;
    return jsonResult;
}

extern "C"
{
    FUNCTION_ATTRIBUTE
    void whisper_kit_free(char *ptr)
    {
        std::free(ptr);
    }

    FUNCTION_ATTRIBUTE
    char *request(char *body)
    {
        try
        {
            silence_whisper_logs();
            json jsonBody = json::parse(body);
            json jsonResult;

            if (jsonBody["@type"] == "initModel")
            {
                std::lock_guard<std::mutex> lock(g_whisper_mutex);
                std::string model_path = jsonBody.value("model", std::string(""));
                struct whisper_context *ctx = get_or_load_context(model_path);
                if (ctx == nullptr)
                {
                    jsonResult["@type"] = "error";
                    jsonResult["message"] = "Failed to load model: " + model_path;
                }
                else
                {
                    jsonResult["@type"] = "modelLoaded";
                    jsonResult["model"] = model_path;
                }
                return jsonToChar(jsonResult);
            }

            if (jsonBody["@type"] == "getTextFromWavFile")
            {
                try
                {
                    return jsonToChar(transcribe(jsonBody));
                }
                catch (const std::exception &e)
                {
                    jsonResult["@type"] = "error";
                    jsonResult["message"] = e.what();
                    return jsonToChar(jsonResult);
                }
            }

            if (jsonBody["@type"] == "getVersion")
            {
                jsonResult["@type"] = "version";
                jsonResult["message"] = "lib version: v1.0.1";
                return jsonToChar(jsonResult);
            }

            jsonResult["@type"] = "error";
            jsonResult["message"] = "method not found";
            return jsonToChar(jsonResult);
        }
        catch (const std::exception &e)
        {
            json jsonResult;
            jsonResult["@type"] = "error";
            jsonResult["message"] = e.what();
            return jsonToChar(jsonResult);
        }
    }
}
