#include "third_party/blink/renderer/core/frame/fingerprint_config.h"

#include <cmath>
#include <limits>
#include <string>

#include "base/base64.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/json/json_reader.h"
#include "base/logging.h"
#include "base/path_service.h"
#include "base/values.h"
#include "third_party/blink/public/common/user_agent/user_agent_metadata.h"  // [Added]
#include "third_party/blink/renderer/platform/wtf/text/string_utf8_adaptor.h"

// ICU 引用
#include <unicode/timezone.h>
#include <unicode/unistr.h>
#include <unicode/utypes.h>  // [修复] 引入 UErrorCode

namespace blink {

// =========================================================
// [内置] 默认配置 (绕过沙箱限制)
// =========================================================
const char* kDefaultConfigJson = R"JSON({
  "global_seed": 11223344,
  "ua_config": {
    "enabled": true,
    "ua_string": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
    "platform": "Win32"
  },
  "webgl": {
    "vendor": "Google Inc. (NVIDIA)",
    "renderer": "ANGLE (NVIDIA, NVIDIA GeForce RTX 4090 Direct3D11, vs_5_0, ps_5_0)",
    "clear_color_noise": 0.005,
    "viewport_noise_max": 15,
    "read_pixels_noise_max": 3
  },
  "hardware": {
    "concurrency": 8,
    "memory_gb": 8.0
  },
  "screen": {
    "enable_spoofing": true,
    "width": 1920,
    "height": 1080,
    "color_depth": 24
  },
  "canvas": {
    "measure_text_noise_enable": true,
    "fill_text_offset_max": 3
  },
  "fonts": {
    "offset_noise_prob_percent": 100
  },
  "network": {
    "spoofing_enabled": true,
    "downlink": 10.0,
    "rtt": 50,
    "effective_type": "4g",
    "save_data": false
  },
  "battery": {
    "spoofing_enabled": true,
    "charging": true,
    "charging_time": 0.0,
    "discharging_time": 0.0,
    "level": 1.0
  },
  "webrtc": {
    "prevent_ip_leak": true
  },
  "timezone": {
    "spoofing_enabled": true,
    "zone_id": "America/Los_Angeles"
  },
  "geo": {
    "spoofing_enabled": true,
    "latitude": 34.0522,
    "longitude": -118.2437,
    "accuracy": 15.0
  }
})JSON";

// =========================================================
// 静态方法
// =========================================================

bool FingerprintConfig::IsCanvasNoiseEnabled() {
  return Instance().canvas_measure_text_noise_enable_;
}

bool FingerprintConfig::IsFontNoiseEnabled() {
  return Instance().fonts_offset_noise_prob_percent_ > 0;
}

FingerprintConfig* FingerprintConfig::GetInstance() {
  return &Instance();
}

FingerprintConfig& FingerprintConfig::Instance() {
  DEFINE_STATIC_LOCAL(FingerprintConfig, instance, ());
  if (!instance.is_loaded_) {
    instance.LoadConfig();
  }
  return instance;
}

FingerprintConfig::FingerprintConfig() = default;

// =========================================================
// Getters
// =========================================================

String FingerprintConfig::GetWebGLVendor() const {
  return webgl_vendor_;
}
String FingerprintConfig::GetWebGLRenderer() const {
  return webgl_renderer_;
}
float FingerprintConfig::GetWebGLClearColorNoise() const {
  return webgl_clear_color_noise_;
}
int FingerprintConfig::GetWebGLViewportNoiseMax() const {
  return webgl_viewport_noise_max_;
}
int FingerprintConfig::GetWebGLReadPixelsNoiseMax() const {
  return webgl_read_pixels_noise_max_;
}
int FingerprintConfig::GetCanvasFillTextOffsetMax() const {
  return canvas_fill_text_offset_max_;
}
bool FingerprintConfig::GetCanvasMeasureTextNoiseEnable() const {
  return canvas_measure_text_noise_enable_;
}
int FingerprintConfig::GetAudioSampleRateOffsetMax() const {
  return audio_sample_rate_offset_max_;
}
int FingerprintConfig::GetFontsOffsetNoiseProbPercent() const {
  return fonts_offset_noise_prob_percent_;
}
int FingerprintConfig::GetHardwareConcurrency() const {
  return hardware_concurrency_;
}
float FingerprintConfig::GetDeviceMemory() const {
  return device_memory_;
}
double FingerprintConfig::GetClientRectsNoiseFactor() const {
  return client_rects_noise_factor_;
}
int FingerprintConfig::GetPluginsDescriptionNoiseMax() const {
  return plugins_description_noise_max_;
}
int FingerprintConfig::GetWebRTCDeviceLabelNoiseMax() const {
  return webrtc_device_label_noise_max_;
}

const Vector<String>& FingerprintConfig::GetFontWhitelist() const {
  return font_whitelist_;
}

int FingerprintConfig::GetGlobalSeed() const {
  return global_seed_;
}

// =========================================================
// 核心配置加载
// =========================================================

void FingerprintConfig::LoadConfig() {
  std::string config_content;
  bool is_config_loaded = false;

  // 1. 优先尝试：从命令行参数 --fingerprint-config-path 获取文件路径
  const base::CommandLine* command_line =
      base::CommandLine::ForCurrentProcess();

  if (command_line->HasSwitch("fingerprint-config-path")) {
    base::FilePath config_path =
        command_line->GetSwitchValuePath("fingerprint-config-path");

    if (base::ReadFileToString(config_path, &config_content)) {
      is_config_loaded = true;
      fprintf(stderr, "[FINGERPRINT] Config loaded from file path: %s\n",
              config_path.MaybeAsASCII().c_str());
    } else {
      fprintf(stderr,
              "[FINGERPRINT] ERROR: Failed to read config file from path: %s\n",
              config_path.MaybeAsASCII().c_str());
    }
  }

  // 2. 也是优先尝试（兼容旧方案）：从命令行参数 --fingerprint-config (Base64)
  // 获取 (实际上如果路径参数存在且成功，这里会被覆盖，或者我们可以让路径优先)
  if (!is_config_loaded && command_line->HasSwitch("fingerprint-config")) {
    std::string encoded_config =
        command_line->GetSwitchValueASCII("fingerprint-config");
    if (base::Base64Decode(encoded_config, &config_content)) {
      is_config_loaded = true;
      fprintf(stderr,
              "[FINGERPRINT] Config loaded via CommandLine Base64 (Sandbox "
              "Safe).\n");
    } else {
      fprintf(stderr,
              "[FINGERPRINT] ERROR: Failed to decode command line config.\n");
    }
  }

  // 3. 备用尝试：直接读取 exe 同级目录下 fingerprint.json (仅在 --no-sandbox
  // 模式或特定环境下有效)
  if (!is_config_loaded) {
    base::FilePath exe_path;
    if (base::PathService::Get(base::DIR_EXE, &exe_path)) {
      base::FilePath config_path = exe_path.AppendASCII("fingerprint.json");
      if (base::ReadFileToString(config_path, &config_content)) {
        is_config_loaded = true;
      }
    }
  }

  // 4. [Fix] If no config loaded, use internal default
  if (!is_config_loaded) {
    config_content = kDefaultConfigJson;
    is_config_loaded = true;
    fprintf(stderr, "[FINGERPRINT] using built-in default config.\n");
  }

  // 4. Parse JSON and apply config
  if (is_config_loaded) {
    auto result =
        base::JSONReader::ReadAndReturnValueWithError(config_content, 0);
    if (result.has_value() && result->is_dict()) {
      const auto& root = result->GetDict();
      global_seed_ = root.FindInt("global_seed").value_or(0);

      // [UA]
      const auto* ua_node = root.FindDict("ua_config");
      if (ua_node) {
        ua.enabled = ua_node->FindBool("enabled").value_or(false);
        const std::string* s = ua_node->FindString("ua_string");
        if (s) {
          ua.ua_string = String::FromUTF8(s->c_str());
          InferUAConfigFromString(ua.ua_string);
        }

        s = ua_node->FindString("platform");
        if (s) {
          ua.platform = String::FromUTF8(s->c_str());
        }

        s = ua_node->FindString("platform_version");
        if (s) {
          ua.platform_version = String::FromUTF8(s->c_str());
        }

        s = ua_node->FindString("full_version");
        if (s) {
          ua.full_version = String::FromUTF8(s->c_str());
        }

        s = ua_node->FindString("model");
        if (s) {
          ua.model = String::FromUTF8(s->c_str());
        }

        s = ua_node->FindString("architecture");
        if (s) {
          ua.architecture = String::FromUTF8(s->c_str());
        }

        s = ua_node->FindString("bitness");
        if (s) {
          ua.bitness = String::FromUTF8(s->c_str());
        }

        ua.mobile = ua_node->FindBool("mobile").value_or(false);
        ua.wow64 = ua_node->FindBool("wow64").value_or(false);

        s = ua_node->FindString("language");
        if (s) {
          ua.language = String::FromUTF8(s->c_str());
        }

        const auto* brands_list = ua_node->FindList("brands");
        if (brands_list) {
          ua.brands.clear();
          for (const auto& val : *brands_list) {
            if (val.is_dict()) {
              const auto& dict = val.GetDict();
              const std::string* b = dict.FindString("brand");
              const std::string* v = dict.FindString("version");
              if (b && v) {
                BrandConfig bc;
                bc.brand = String::FromUTF8(b->c_str());
                bc.version = String::FromUTF8(v->c_str());
                ua.brands.push_back(bc);
              }
            }
          }
        }
      }

      // [WebGL]
      const auto* webgl = root.FindDict("webgl");
      if (webgl) {
        const std::string* s = webgl->FindString("vendor");
        if (s) {
          webgl_vendor_ = String::FromUTF8(s->c_str());
        }
        s = webgl->FindString("renderer");
        if (s) {
          webgl_renderer_ = String::FromUTF8(s->c_str());
        }

        webgl_clear_color_noise_ =
            webgl->FindDouble("clear_color_noise").value_or(0.005);
        webgl_viewport_noise_max_ =
            webgl->FindInt("viewport_noise_max").value_or(15);
        webgl_read_pixels_noise_max_ =
            webgl->FindInt("read_pixels_noise_max").value_or(3);
      }

      // [Hardware]
      const auto* hw = root.FindDict("hardware");
      if (hw) {
        // 1. CPU 核心数处理：强制转换为偶数
        // 理由：现代 CPU 逻辑核心数几乎均为偶数，出现奇数会触发风险标记
        int cpu_val = hw->FindInt("concurrency").value_or(16);
        if (cpu_val > 0 && cpu_val % 2 != 0) {
          cpu_val += 1;  // 奇数向上取偶，例如 7 变为 8
        }
        hardware_concurrency_ = cpu_val;

        // 2. 内存容量处理：自动向下取最接近的 2 的幂次方
        // 理由：Web 暴露的 deviceMemory 通常为 0.25, 0.5, 1, 2, 4, 8 等标准值
        // 该逻辑确保即使 JSON 填入 7 或 12，也会返回 4 或 8 这种真实数值
        double mem_val = hw->FindDouble("memory_gb").value_or(32.0);
        if (mem_val > 0) {
          // 使用数学公式：2^(floor(log2(mem_val)))
          mem_val = std::pow(2, std::floor(std::log2(mem_val)));
        }
        device_memory_ = static_cast<float>(mem_val);
      }

      // [Screen]
      const auto* scr = root.FindDict("screen");
      if (scr) {
        screen.enabled = scr->FindBool("enable_spoofing").value_or(false);
        screen.width = scr->FindInt("width").value_or(1920);
        screen.height = scr->FindInt("height").value_or(1080);
        screen.color_depth = scr->FindInt("color_depth").value_or(24);
      }

      // [Canvas & Fonts]
      const auto* cvs = root.FindDict("canvas");
      if (cvs) {
        canvas_measure_text_noise_enable_ =
            cvs->FindBool("measure_text_noise_enable").value_or(true);
        canvas_fill_text_offset_max_ =
            cvs->FindInt("fill_text_offset_max").value_or(3);
      }

      // [Audio]
      const auto* aud = root.FindDict("audio");
      if (aud) {
        audio_sample_rate_offset_max_ =
            aud->FindInt("sample_rate_offset_max").value_or(100);

        // [Added] Populate public AudioConfig struct
        audio.spoofing_enabled =
            aud->FindBool("spoofing_enabled").value_or(false);
        audio.sample_rate_offset =
            aud->FindDouble("sample_rate_offset").value_or(0.0);
        audio.reduction_noise_factor =
            aud->FindDouble("reduction_noise_factor").value_or(0.001);
      }

      // [Plugins]
      const auto* plg = root.FindDict("plugins");
      if (plg) {
        plugins_description_noise_max_ =
            plg->FindInt("description_noise_max").value_or(5);
      }

      // [解析 Rects]
      const auto* rects = root.FindDict("rects");
      if (rects) {
        client_rects_noise_factor_ =
            rects->FindDouble("noise_factor").value_or(0.000005);
      }

      // [Fonts]
      const auto* fonts = root.FindDict("fonts");
      if (fonts) {
        fonts_offset_noise_prob_percent_ =
            fonts->FindInt("offset_noise_prob_percent").value_or(10);

        // [新增] 解析 JSON 中的 whitelist 数组
        const auto* whitelist_node = fonts->FindList("whitelist");
        if (whitelist_node) {
          font_whitelist_.clear();
          for (const auto& value : *whitelist_node) {
            if (value.is_string()) {
              font_whitelist_.push_back(
                  String::FromUTF8(value.GetString().c_str()));
            }
          }
        }
      }

      // [Network]
      const auto* net = root.FindDict("network");
      if (net) {
        network.spoofing_enabled =
            net->FindBool("spoofing_enabled").value_or(true);
        network.downlink = net->FindDouble("downlink").value_or(10.0);
        network.rtt = net->FindDouble("rtt").value_or(50.0);
        const std::string* s = net->FindString("effective_type");
        if (s) {
          network.effective_type = String::FromUTF8(s->c_str());
        }
        network.save_data = net->FindBool("save_data").value_or(false);
      }

      // [Battery]
      const auto* bat = root.FindDict("battery");
      if (bat) {
        battery.spoofing_enabled =
            bat->FindBool("spoofing_enabled").value_or(true);
        battery.charging = bat->FindBool("charging").value_or(true);
        battery.charging_time = bat->FindDouble("charging_time").value_or(0.0);
        battery.discharging_time =
            bat->FindDouble("discharging_time")
                .value_or(std::numeric_limits<double>::infinity());
        battery.level = bat->FindDouble("level").value_or(1.0);
      }

      // [WebRTC]
      const auto* rtc = root.FindDict("webrtc");
      if (rtc) {
        webrtc.prevent_ip_leak =
            rtc->FindBool("prevent_ip_leak").value_or(true);
        webrtc_device_label_noise_max_ =
            rtc->FindInt("device_label_noise_max").value_or(5);
      }

      // [Geo]
      const auto* g = root.FindDict("geo");
      if (g) {
        geo.spoofing_enabled = g->FindBool("spoofing_enabled").value_or(true);
        geo.latitude = g->FindDouble("latitude").value_or(geo.latitude);
        geo.longitude = g->FindDouble("longitude").value_or(geo.longitude);
        geo.accuracy = g->FindDouble("accuracy").value_or(geo.accuracy);
      }

      // [Timezone]
      const auto* tz = root.FindDict("timezone");
      if (tz) {
        timezone.spoofing_enabled =
            tz->FindBool("spoofing_enabled").value_or(true);
        const std::string* s = tz->FindString("zone_id");
        if (s) {
          timezone.zone_id = String::FromUTF8(s->c_str());
        }
      }
    }
  }

  // 4. 执行 Hook 逻辑 (无论配置来源如何，都要执行)

  // [Geo 兜底]
  if (geo.spoofing_enabled) {
    if (geo.latitude == 0 && geo.longitude == 0) {
      geo.latitude = 51.5074;
      geo.longitude = -0.1278;
    }
  }

  // [Timezone 兜底]
  if (timezone.spoofing_enabled) {
    if (timezone.zone_id.empty()) {
      timezone.zone_id = "Europe/London";
    }
  }

  is_loaded_ = true;
  EnforceTimezone();
}

void FingerprintConfig::EnforceTimezone() {
  // 必须确保配置已加载
  if (!is_loaded_) {
    return;
  }

  // ================= [FINGERPRINT DYNAMIC START] =================
  // 使用成员变量 (timezone.zone_id)，它是由 LoadConfig 从 JSON 解析出来的
  if (timezone.spoofing_enabled && !timezone.zone_id.empty()) {
    std::string tz_str = timezone.zone_id.Utf8().data();

    // 1. 设置系统环境
#if BUILDFLAG(IS_WIN)
    _putenv_s("TZ", tz_str.c_str());
    _tzset();
#else
    setenv("TZ", tz_str.c_str(), 1);
    tzset();
#endif

    // 2. 设置 ICU
    icu::UnicodeString tz_id(timezone.zone_id.Utf8().c_str());
    std::unique_ptr<icu::TimeZone> zone(icu::TimeZone::createTimeZone(tz_id));

    if (*zone != icu::TimeZone::getUnknown()) {
      icu::TimeZone::adoptDefault(zone.release());
      LOG(INFO) << ">>> [FINGERPRINT] EnforceTimezone applied dynamically: "
                << tz_str;
    } else {
      LOG(WARNING) << ">>> [FINGERPRINT] Invalid Timezone ID: " << tz_str;
    }
  }
  // ================= [FINGERPRINT DYNAMIC END] =================
}

double FingerprintConfig::GenerateNoise(double input, double factor) {
  // 1. 获取当前实例中的种子 (从 JSON 读来的那个 12345)
  int seed = Instance().GetGlobalSeed();

  // 2. 核心算法：sin(种子 + 输入 + 偏移)
  // 增加常量偏移 (0.12345) 防止 seed=0 && input=0 时结果为 0
  double deterministic_val =
      std::sin(static_cast<double>(seed) + input + 0.12345);

  return deterministic_val * factor;
}

void FingerprintConfig::InferUAConfigFromString(const String& ua_string) {
  if (ua_string.empty()) {
    return;
  }

  // Platform inference (only set platform name, NOT platform_version)
  // platform_version is always determined by the browser process
  // via GetPlatformVersion() to ensure system-level consistency.
  if (ua_string.Contains("Windows")) {
    ua.platform = "Win32";
  } else if (ua_string.Contains("Macintosh")) {
    ua.platform = "MacIntel";
  } else if (ua_string.Contains("Linux")) {
    ua.platform = "Linux x86_64";
  } else if (ua_string.Contains("Android")) {
    ua.platform = "Linux armv81";
    ua.mobile = true;
    ua.model = "Nexus 5";  // Default fallback
  }

  // Version inference
  wtf_size_t pos = ua_string.Find("Chrome/");
  if (pos == kNotFound) {
    pos = ua_string.Find("CriOS/");
  }
  if (pos == kNotFound) {
    pos = ua_string.Find("Version/");
  }

  if (pos != kNotFound) {
    // NOTE: Do NOT extract full_version or brands from ua_string here.
    // full_version and brands are determined by the browser process
    // (user_agent_utils.cc) using the proper Chrome algorithm with
    // correct GREASE brand names and shuffle order.
    // Overriding them here would cause inconsistencies detected by
    // fingerprint scanners like Browserscan and Pixelscan.
  }

  // Arch inference
  if (ua_string.Contains("Win64") || ua_string.Contains("x64") ||
      ua_string.Contains("x86_64")) {
    ua.architecture = "x86";
    ua.bitness = "64";
  } else {
    ua.bitness = "32";
  }
}

void FingerprintConfig::ApplyUASpoofing(UserAgentMetadata& metadata) {
  if (!ua.enabled) {
    return;
  }

  if (!ua.platform.empty()) {
    metadata.platform = ua.platform.Utf8();
  }
  if (!ua.platform_version.empty()) {
    metadata.platform_version = ua.platform_version.Utf8();
  }
  if (!ua.full_version.empty()) {
    metadata.full_version = ua.full_version.Utf8();
  }
  if (!ua.model.empty()) {
    metadata.model = ua.model.Utf8();
  }
  if (!ua.architecture.empty()) {
    metadata.architecture = ua.architecture.Utf8();
  }
  if (!ua.bitness.empty()) {
    metadata.bitness = ua.bitness.Utf8();
  }
  metadata.mobile = ua.mobile;
  metadata.wow64 = ua.wow64;

  // Brands: only apply if explicitly configured in JSON.
  // Otherwise, browser process generates correct brands via
  // GetUserAgentBrandList().
  if (!ua.brands.empty()) {
    metadata.brand_version_list.clear();
    metadata.brand_full_version_list.clear();
    for (const auto& b : ua.brands) {
      UserAgentBrandVersion bv;
      bv.brand = b.brand.Utf8();
      bv.version = b.version.Utf8();
      metadata.brand_version_list.push_back(bv);
      metadata.brand_full_version_list.push_back(bv);
    }
  }
}

}  // namespace blink
