#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_FINGERPRINT_CONFIG_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_FINGERPRINT_CONFIG_H_

#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/platform/wtf/allocator/allocator.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"

namespace blink {

struct UserAgentMetadata;  // [Added] Forward declaration

class CORE_EXPORT FingerprintConfig {
  USING_FAST_MALLOC(FingerprintConfig);

 public:
  static bool IsCanvasNoiseEnabled();
  static bool IsFontNoiseEnabled();
  static FingerprintConfig* GetInstance();
  static FingerprintConfig& Instance();
  static double GenerateNoise(double input, double factor);
  void LoadConfig();
  void EnforceTimezone();
  // =========================================================
  // 1. 结构体定义 (类型定义)
  // =========================================================
  struct ScreenConfig {
    bool enabled = false;
    int width = 0;
    int height = 0;
    int color_depth = 24;
  };

  struct NetworkConfig {
    bool spoofing_enabled = false;
    double downlink = 10.0;
    double rtt = 50.0;
    String effective_type = "4g";
    bool save_data = false;
  };

  struct BatteryConfig {
    bool spoofing_enabled = false;
    bool charging = true;
    double charging_time = 0.0;
    double discharging_time = 0.0;
    double level = 1.0;
  };

  struct WebRTCConfig {
    bool prevent_ip_leak = true;
  };

  // [新增] 时区配置结构体
  struct TimezoneConfig {
    bool spoofing_enabled = false;
    String zone_id = "America/New_York";
  };

  // [新增] 地理位置配置结构体
  struct GeoConfig {
    bool spoofing_enabled = true;  // [修改] 改为 true
    double latitude = 51.5074;     // [修改] 给个默认值 (伦敦)
    double longitude = -0.1278;
    double accuracy = 10.0;
  };

  struct AudioConfig {
    bool spoofing_enabled = false;
    double sample_rate_offset = 0.0;        // Fixed offset or max random offset
    double reduction_noise_factor = 0.001;  // For compressor
  };

  struct MediaConfig {
    bool spoofing_enabled = false;
  };

  struct SpeechConfig {
    bool spoofing_enabled = false;
  };

  struct BrandConfig {
    String brand;
    String version;
  };

  struct UAConfig {
    bool enabled = false;
    String ua_string;
    String platform = "Win32";
    String platform_version = "13.0.0";
    String full_version = "146.0.0.0";  // [Added]
    String model = "";                  // [Added]
    String architecture = "x86";        // [Added]
    String bitness = "64";              // [Added]
    bool mobile = false;
    bool wow64 = false;  // [Added]
    String language = "en-US";
    Vector<BrandConfig> brands;  // [Added]
  };

  // Helper to infer metadata from UA string
  void InferUAConfigFromString(const String& ua_string);

  // [Added] Apply spoofing to metadata
  void ApplyUASpoofing(UserAgentMetadata& metadata);

  // =========================================================
  // 2. 成员变量声明 (实际存在的变量)
  // =========================================================
  ScreenConfig screen;
  NetworkConfig network;
  BatteryConfig battery;
  WebRTCConfig webrtc;

  // [修改] 必须在这里声明变量，否则 .cc 文件无法访问
  // config->geo
  TimezoneConfig timezone;
  GeoConfig geo;
  AudioConfig audio;

  MediaConfig media;
  SpeechConfig speech;
  UAConfig ua;

  // =========================================================
  // 3. Getters
  // =========================================================
  const Vector<String>& GetFontWhitelist() const;
  String GetWebGLVendor() const;
  String GetWebGLRenderer() const;
  float GetWebGLClearColorNoise() const;
  int GetWebGLViewportNoiseMax() const;
  int GetWebGLReadPixelsNoiseMax() const;
  int GetCanvasFillTextOffsetMax() const;
  bool GetCanvasMeasureTextNoiseEnable() const;
  int GetAudioSampleRateOffsetMax() const;
  int GetFontsOffsetNoiseProbPercent() const;
  int GetHardwareConcurrency() const;
  float GetDeviceMemory() const;
  double GetClientRectsNoiseFactor() const;
  int GetPluginsDescriptionNoiseMax() const;
  int GetWebRTCDeviceLabelNoiseMax() const;
  int GetGlobalSeed() const;

 private:
  int global_seed_ = 0;
  double client_rects_noise_factor_ = 0.000005;
  int fonts_offset_noise_prob_percent_ = 0;
  FingerprintConfig();
  ~FingerprintConfig() = default;

  // 内部私有变量
  String webgl_vendor_ = "Google Inc. (NVIDIA)";
  String webgl_renderer_ =
      "ANGLE (NVIDIA, NVIDIA GeForce RTX 4090 Direct3D11, vs_5_0, ps_5_0)";
  float webgl_clear_color_noise_ = 0.005f;
  int webgl_viewport_noise_max_ = 15;
  int webgl_read_pixels_noise_max_ = 3;
  int canvas_fill_text_offset_max_ = 3;
  bool canvas_measure_text_noise_enable_ = true;
  int audio_sample_rate_offset_max_ = 99;
  int hardware_concurrency_ = 16;
  float device_memory_ = 32.0f;
  int plugins_description_noise_max_ = 9;
  int webrtc_device_label_noise_max_ = 9;
  Vector<String> font_whitelist_;
  bool is_loaded_ = false;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_FINGERPRINT_CONFIG_H_
