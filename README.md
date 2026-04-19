# 指纹修改总结

## 一、配置中心 (C++ 基础设施)

### 📁 `fingerprint_config.h` / `fingerprint_config.cc`
- **路径**: `third_party/blink/renderer/core/frame/`
- **作用**: 整个指纹系统的**核心单例**，负责：
  1. 从 `--fingerprint-config-path` 命令行参数读取 JSON 配置文件
  2. 备用：从 `--fingerprint-config` (Base64 编码) 读取
  3. 兜底：使用内置默认配置 `kDefaultConfigJson`
  4. 解析所有模块配置 → 存储为结构体成员变量
  5. 提供 `GenerateNoise(input, factor)` 确定性噪声函数

#### `GenerateNoise` 核心算法
```cpp
double FingerprintConfig::GenerateNoise(double input, double factor) {
    int seed = Instance().GetGlobalSeed();  // 从 JSON 读入的种子
    double deterministic_val = std::sin(seed + input + 0.12345);
    return deterministic_val * factor;
}
```
> **原理**: `sin(seed + input)` 保证：同一种子+同一输入 → 永远输出相同噪声值（确定性）。不同种子 → 完全不同的噪声序列。`factor` 控制噪声幅度。

---

## 二、各指纹修改详情

### 1️⃣ User-Agent (UA) + Client Hints

| 项目 | 详情 |
|---|---|
| **修改文件** | [fingerprint_config.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/fingerprint_config.cc)、[navigator.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/navigator.cc)、[navigator_ua_data.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/navigator_ua_data.cc)、[navigator_base.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/execution_context/navigator_base.cc) |
| **Python 层** | [profile.py](file:///e:/src/Browser/core/profile.py) 生成 `ua_config` 字段 |

**修改原理**:
- **`navigator.userAgent`**: 从 JSON 读取 `ua_string` 直接替换返回值
- **`navigator.platform`**: 从 JSON 读取 `platform` 字段 (Win32/MacIntel/Linux)  
- **Client Hints (高熵)**: `ApplyUASpoofing()` 方法覆盖 `UserAgentMetadata` 中的 `platform_version`、`full_version`、`architecture`、`bitness`、`model`、`mobile`
- **`navigator.webdriver`**: 在 `navigator.cc` 中**硬编码返回 `false`**，隐藏自动化状态
- **版本号策略**: UA 使用 Reduced UA 格式 (如 `Chrome/145.0.0.0`)，但 `full_version` 保留真实小版本号，由浏览器进程的 `GetUserAgentBrandList()` 生成正确的 GREASE Brand 名称

---

### 2️⃣ WebGL 指纹

| 项目 | 详情 |
|---|---|
| **修改文件** | [webgl_rendering_context_base.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc) |

**修改原理**:
- **`WEBGL_debug_renderer_info`**: 将 `getParameter(UNMASKED_VENDOR_WEBGL)` 和 `UNMASKED_RENDERER_WEBGL` 的返回值替换为 JSON 配置中的 `webgl.vendor` / `webgl.renderer`
- **`clearColor` 噪声**: 在 `clearColor()` 调用中注入微小颜色偏移 (`webgl_clear_color_noise_`)
- **`readPixels` 噪声**: 在像素读取结果中注入随机偏移 (`webgl_read_pixels_noise_max_`)
- **Viewport 噪声**: 修改 viewport 尺寸查询结果 (`webgl_viewport_noise_max_`)

> 目的：使 WebGL 渲染结果的 Hash 值在不同环境间不同，同时在同一环境内保持一致。

---

### 3️⃣ Canvas 指纹

| 项目 | 详情 |
|---|---|
| **修改文件** | [base_rendering_context_2d.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/canvas/canvas2d/base_rendering_context_2d.cc)、[text_metrics.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/html/canvas/text_metrics.cc)、[canvas_async_blob_creator.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/html/canvas/canvas_async_blob_creator.cc) |

**修改原理**:
- **`measureText()` 噪声**: 在 `text_metrics.cc` 中，使用 `global_seed` + 文本内容 hash 生成确定性噪声，扰动 `width` 等测量结果
- **`fillText()` 偏移**: 在 `base_rendering_context_2d.cc` 中，对文字绘制坐标注入微小偏移 (`fill_text_offset_max`)，改变 Canvas 渲染像素
- **`toDataURL()` / `toBlob()` 尾字节**: 在 `canvas_async_blob_creator.cc` 中，使用 `global_seed` + 图像尺寸生成确定性尾字节，改变导出图像的 Hash

> 三重噪声叠加：测量 + 绘制 + 导出，确保 Canvas 指纹唯一。

---

### 4️⃣ DOM Rects (ClientRects) 指纹

| 项目 | 详情 |
|---|---|
| **修改文件** | [range.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/dom/range.cc)、[element.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/dom/element.cc) |

**修改原理**:
- **`getClientRects()`**: 遍历所有返回的 `DOMRect`，对 `x/y/width/height` 各注入 `GenerateNoise(value, noise_factor)` 确定性噪声
- **`getBoundingClientRect()`**: 同上逻辑，单个矩形
- **`Element.getClientRects()`**: 在 `element.cc` 中定义独立的 `getDeterministicRectsNoise()` 函数，使用 `value * 10000` 转整数 + `seed XOR` + 黄金分割乘法散列
- **白名单保护**: 仅对 `http://` 和 `https://` 协议生效，避免 `chrome://` 等内部页面崩溃

---

### 5️⃣ 字体 (Font) 指纹

| 项目 | 详情 |
|---|---|
| **修改文件** | [simple_font_data.cc](file:///e:/src/chromium/src/third_party/blink/renderer/platform/fonts/simple_font_data.cc)、[font_access.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/font_access/font_access.cc) |

**修改原理**:
- **字体度量噪声**: 在 `simple_font_data.cc` 中，当 `font_noise_enabled && global_seed != 0` 时，对字体的 `ascent/descent` 等度量值添加基于 `stable_hash ^ global_seed` 的确定性噪声
- **字体白名单**: 从 JSON 的 `fonts.whitelist` 数组中读取允许的字体列表，限制 `enumerateDevices` 可见字体数量
- **`Font Access API`**: 在 `font_access.cc` 中拦截，按白名单过滤返回结果
- **概率控制**: `offset_noise_prob_percent` 控制噪声注入概率 (0-100%)

---

### 6️⃣ 音频 (Audio) 指纹

| 项目 | 详情 |
|---|---|
| **修改文件** | [base_audio_context.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/webaudio/base_audio_context.cc)、[dynamics_compressor_node.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/webaudio/dynamics_compressor_node.cc) |

**修改原理**:
- **AudioContext 采样率偏移**: 在 `base_audio_context.cc` 中，当 `audio.spoofing_enabled` 时，对 `sampleRate` 注入微小偏移 (`sample_rate_offset`)
- **DynamicsCompressor 噪声**: 在压缩器节点中，使用 `reduction_noise_factor` 对 `reduction` 值注入噪声，改变音频处理指纹

> AudioContext 指纹检测依赖精确的音频处理结果 Hash，微小的采样率/压缩参数变化即可产生不同指纹。

---

### 7️⃣ 屏幕 (Screen) 信息

| 项目 | 详情 |
|---|---|
| **修改文件** | [fingerprint_config.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/fingerprint_config.cc) 解析 `screen` 节点 |

**修改原理**:
- 覆盖 `screen.width`、`screen.height`、`screen.colorDepth` 的返回值
- 通过 JSON 配置 `screen.enable_spoofing` 控制开关

---

### 8️⃣ 硬件信息 (Hardware Concurrency + Device Memory)

| 项目 | 详情 |
|---|---|
| **修改文件** | [fingerprint_config.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/fingerprint_config.cc) |

**修改原理**:
- **`navigator.hardwareConcurrency`**: 从 JSON 读取，**强制转偶数** (奇数 CPU 核心数在真实世界罕见，会被检测)
- **`navigator.deviceMemory`**: 从 JSON 读取，**自动向下取 2 的幂** (`2^floor(log2(val))`)，因为 Web API 只暴露 0.25/0.5/1/2/4/8 等标准值

---

### 9️⃣ 时区 (Timezone)

| 项目 | 详情 |
|---|---|
| **修改文件** | [fingerprint_config.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/fingerprint_config.cc) → `EnforceTimezone()`、[timezone_controller.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/timezone/timezone_controller.cc)、[local_dom_window.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/local_dom_window.cc) |

**修改原理**:
- **系统环境**: 通过 `_putenv_s("TZ", ...)` (Windows) 设置 C 运行时时区
- **ICU 层**: 通过 `icu::TimeZone::adoptDefault()` 设置 ICU 默认时区
- **双重保护**: `EnforceTimezone()` 在配置加载后立即调用，确保 `Date()` 和 `Intl.DateTimeFormat` 等所有时区 API 返回一致结果

---

### 🔟 地理位置 (Geolocation)

| 项目 | 详情 |
|---|---|
| **修改文件** | [geolocation.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/geolocation/geolocation.cc) |

**修改原理**:
- 拦截 `navigator.geolocation.getCurrentPosition()` 和 `watchPosition()`
- 当 `geo.spoofing_enabled` 时，替换返回的 `latitude`、`longitude`、`accuracy` 为 JSON 配置值
- Python 层根据代理 IP 自动查询对应地理位置 (`ip-api.com`)

---

### 1️⃣1️⃣ 电池 (Battery)

| 项目 | 详情 |
|---|---|
| **修改文件** | [battery_manager.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/battery/battery_manager.cc) |

**修改原理**:
- 拦截 `navigator.getBattery()` 返回的 `BatteryManager` 对象
- 替换 `charging`、`chargingTime`、`dischargingTime`、`level` 四个属性
- Python 层随机生成合理的电池参数

---

### 1️⃣2️⃣ 网络信息 (Network Information)

| 项目 | 详情 |
|---|---|
| **修改文件** | [network_information.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/netinfo/network_information.cc) |

**修改原理**:
- 覆盖 `navigator.connection` 的 `downlink`、`rtt`、`effectiveType`、`saveData` 属性
- 使检测站无法通过网络指纹关联真实身份

---

### 1️⃣3️⃣ 媒体设备 (Media Devices)

| 项目 | 详情 |
|---|---|
| **修改文件** | [media_devices.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/mediastream/media_devices.cc) |

**修改原理**:
- 当 `media.spoofing_enabled` 时，修改 `enumerateDevices()` 返回的设备列表
- 防止通过摄像头/麦克风设备 ID 进行跨站追踪

---

### 1️⃣4️⃣ 语音合成 (Speech)

| 项目 | 详情 |
|---|---|
| **修改文件** | [speech_synthesis.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/speech/speech_synthesis.cc) |

**修改原理**:
- 当 `speech.spoofing_enabled` 时，限制 `speechSynthesis.getVoices()` 返回的语音列表
- 语音列表是强指纹信号（不同系统/语言包安装情况不同）

---

### 1️⃣5️⃣ WebRTC IP 泄露防护

| 项目 | 详情 |
|---|---|
| **修改文件** | [fingerprint_config.cc](file:///e:/src/chromium/src/third_party/blink/renderer/core/frame/fingerprint_config.cc) |

**修改原理**:
- `webrtc.prevent_ip_leak = true` 时，限制 WebRTC STUN/TURN 行为
- 防止真实局域网 IP 通过 ICE Candidate 泄露

---

### 1️⃣6️⃣ 插件 (Plugins)

| 项目 | 详情 |
|---|---|
| **修改文件** | [dom_plugin_array.cc](file:///e:/src/chromium/src/third_party/blink/renderer/modules/plugins/dom_plugin_array.cc) |

**修改原理**:
- 对 `navigator.plugins` 的描述信息注入随机字符噪声 (`plugins_description_noise_max_`)
- 使插件指纹在不同环境间有所差异

---

## 三、Python 层

### 📁 `core/profile.py` — 指纹生成器

生成完整的 `fingerprint.json`，包含所有指纹模块的配置值：

| 字段 | 来源 |
|---|---|
| `global_seed` | `random.randint(1000000, 99999999)` — 全局随机种子 |
| `ua_config` | Chrome 144-146 真实正式版号 + Reduced UA |
| `webgl` | 从 `hardware_data.py` 的 GPU 数据库随机选择 |
| `hardware` | 根据 GPU Tier 联动匹配 CPU/RAM |
| `screen` | 根据 GPU Tier 联动匹配分辨率 |
| `fonts` | 从 18 种常见字体中随机选 10-15 种 |
| `timezone/geo` | 根据代理 IP 查询地理信息 (`ip-api.com`) |
| `battery` | 随机充电状态、电量 |
| `audio` | 固定噪声参数 |

### 📁 `core/hardware_data.py` — GPU 数据库 + 硬件联动

- **GPU 数据库**: 包含 NVIDIA/AMD/Intel 共 80+ 款显卡，跨越 15 年，分 5 个性能等级
- **硬件联动函数**:
  - `get_hardware_config(tier)` → 根据 GPU 等级返回合理的 CPU 核心数 + RAM
  - `get_screen_config(tier)` → 根据 GPU 等级返回合理的屏幕分辨率

### 📁 `core/launcher.py` — 启动器

- 每个 Worker 拥有独立的 `fingerprint.json` (`worker_{id}/fingerprint.json`)
- 通过 `--fingerprint-config-path` 传递给 Chrome 进程
- 保证多实例并发启动时指纹不会互相覆盖

---

## 四、总结表

| # | 指纹类型 | 修改层 | 原理 |
|---|---|---|---|
| 1 | User-Agent + Client Hints | C++ + Python | 替换UA字符串 + 覆盖高/低熵Hints |
| 2 | WebGL | C++ + Python | 替换显卡标识 + 渲染噪声 |
| 3 | Canvas | C++ | 文字测量/绘制/导出三重噪声 |
| 4 | DOM Rects | C++ | 确定性坐标噪声 (`sin(seed+input)*factor`) |
| 5 | 字体 | C++ + Python | 度量噪声 + 白名单过滤 |
| 6 | 音频 | C++ + Python | 采样率偏移 + 压缩器噪声 |
| 7 | 屏幕信息 | C++ + Python | 替换分辨率/色深 |
| 8 | 硬件 | C++ + Python | 替换核心数/内存 + 偶数化/2的幂 |
| 9 | 时区 | C++ + Python | 环境变量 + ICU 双重设置 |
| 10 | 地理位置 | C++ + Python | 拦截 API + IP 反查 |
| 11 | 电池 | C++ + Python | 替换电池状态 |
| 12 | 网络信息 | C++ | 替换带宽/延迟/类型 |
| 13 | 媒体设备 | C++ | 过滤设备列表 |
| 14 | 语音合成 | C++ | 限制语音列表 |
| 15 | WebRTC | C++ | 阻止 IP 泄露 |
| 16 | 插件 | C++ | 描述信息噪声 |
| 17 | navigator.webdriver | C++ | 硬编码返回 false |

Pixelscan检测
<img width="1919" height="1030" alt="屏幕截图 2026-04-19 004304" src="https://github.com/user-attachments/assets/bafb696c-aa46-46e6-831c-af0d6f898428" />


