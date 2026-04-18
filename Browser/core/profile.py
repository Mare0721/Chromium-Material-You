import json
import random
import re
import time
import urllib.request

DEFAULT_BROWSER_VERSION = "146.0.7673.0"


def _sanitize_browser_version(version):
    """Normalize browser version into major.minor.build.patch."""
    if isinstance(version, str):
        m = re.search(r"(\d+\.\d+\.\d+\.\d+)", version)
        if m:
            return m.group(1)
    return DEFAULT_BROWSER_VERSION

def _lookup_ip_geo(ip_addr):
    """(Helper) Query Geo/Timezone by IP"""
    try:
        url = f"http://ip-api.com/json/{ip_addr}?fields=lat,lon,timezone,city,countryCode,status"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            if data.get("status") == "success":
                return {
                    "latitude": round(data["lat"], 4),
                    "longitude": round(data["lon"], 4),
                    "timezone": data["timezone"],
                    "countryCode": data.get("countryCode", "US"),
                }
    except Exception:
        pass
    # Default: Los Angeles, US
    return {"latitude": 34.0522, "longitude": -118.2437, "timezone": "America/Los_Angeles", "countryCode": "US"}

def _get_lang_by_country(cc):
    """(Helper) Map Country Code to Chrome Language"""
    cc = cc.upper()
    # Common mappings
    map_db = {
        "CN": "zh-CN", "TW": "zh-TW", "HK": "zh-HK",
        "US": "en-US", "GB": "en-GB", "CA": "en-CA", "AU": "en-AU",
        "JP": "ja", "KR": "ko",
        "DE": "de", "FR": "fr", "ES": "es", "IT": "it", "RU": "ru",
        "BR": "pt-BR", "PT": "pt-PT",
        "IN": "en-IN", # or hi
        "VN": "vi", "TH": "th", "ID": "id",
    }
    return map_db.get(cc, "en-US")

class ProfileManager:
    @staticmethod
    def generate_fingerprint(proxy_ip=None, browser_version=None, compliance_mode=True):
        """Generate a reproducible fingerprint focused on internal consistency."""
        chrome_ver = _sanitize_browser_version(browser_version)
        chrome_reduced_ver = f"{chrome_ver.split('.')[0]}.0.0.0"
        ua_string = f"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{chrome_reduced_ver} Safari/537.36"

        # ===== 显卡数据库 (Extended) =====
        from .hardware_data import GPU_DB, get_hardware_config, get_screen_config
        
        vendor, renderer, tier = random.choice(GPU_DB)

        # ===== 硬件一致性联动 =====
        # 根据显卡 Tier 自动匹配合理的 CPU/RAM
        concurrency, memory_gb = get_hardware_config(tier)

        # ===== 随机屏幕 =====
        # 根据显卡 Tier 自动匹配合理的分辨率
        scr = get_screen_config(tier)

        # ===== 字体白名单 =====
        all_fonts = [
            "Arial", "Arial Black", "Calibri", "Cambria", "Comic Sans MS", "Consolas", 
            "Courier New", "Georgia", "Impact", "Microsoft YaHei", "MS Gothic", "Segoe UI",
            "Tahoma", "Times New Roman", "Trebuchet MS", "Verdana", "Webdings", "Wingdings"
        ]
        # 随机选择 10-15 个字体作为白名单
        # 注意: C++ 有长度限制，不要给太多
        cnt = random.randint(10, min(len(all_fonts), 15))
        font_list = sorted(random.sample(all_fonts, cnt))

        # ===== 根据 IP 生成时区/地理位置/语言 =====
        geo_info = _lookup_ip_geo(proxy_ip) if proxy_ip else _lookup_ip_geo("")
        lang_code = _get_lang_by_country(geo_info.get("countryCode", "US"))

        # ===== Battery 配置 (两种模式下均随机化，保持拟真) =====
        is_charging = random.choice([True, False])
        battery_level = round(random.uniform(0.15, 0.95), 2)
        battery_cfg = {
            "spoofing_enabled": True,
            "charging": is_charging,
            "charging_time": 0 if is_charging else random.randint(1200, 7200),
            "level": battery_level,
            "discharging_time": 0 if is_charging else random.randint(3600, 28800),
        }

        # ===== Network 配置 (随机化，模拟不同网络环境) =====
        net_types = [
            {"effective_type": "4g", "downlink": round(random.uniform(8.0, 50.0), 1), "rtt": random.randint(30, 80)},
            {"effective_type": "4g", "downlink": round(random.uniform(50.0, 150.0), 1), "rtt": random.randint(10, 40)},
            {"effective_type": "3g", "downlink": round(random.uniform(1.5, 8.0), 1), "rtt": random.randint(80, 200)},
        ]
        net_choice = random.choice(net_types)
        network_cfg = {
            "spoofing_enabled": True,
            "downlink": net_choice["downlink"],
            "rtt": net_choice["rtt"],
            "effective_type": net_choice["effective_type"],
            "save_data": False,
        }

        if compliance_mode:
            canvas_cfg = {
                "measure_text_noise_enable": False,
                "fill_text_offset_max": 0,
            }
            rects_cfg = {
                "noise_factor": 0.0,
            }
            fonts_cfg = {
                "offset_noise_prob_percent": 0,
                "whitelist": font_list,
            }
            plugins_cfg = {
                "description_noise_max": 0,
            }
            audio_cfg = {
                "spoofing_enabled": False,
                "sample_rate_offset": 0,
                "reduction_noise_factor": 0.0,
            }

        else:
            canvas_cfg = {
                "measure_text_noise_enable": True,
                "fill_text_offset_max": 2,
            }
            rects_cfg = {
                "noise_factor": 0.000003,
            }
            fonts_cfg = {
                "offset_noise_prob_percent": 80,
                "whitelist": font_list,
            }
            plugins_cfg = {
                "description_noise_max": 3,
            }
            audio_cfg = {
                "spoofing_enabled": True,
                "sample_rate_offset": 3,
                "reduction_noise_factor": 0.0005,
            }

        # ===== Media Devices & Plugins 随机配置 =====
        # 模拟真实用户的设备差异：麦克风/摄像头数量各不相同
        mic_count    = random.randint(1, 3)
        speaker_count = random.randint(1, 2)
        camera_count  = random.randint(0, 2)
        media_devices_cfg = {
            "spoofing_enabled": True,
            "microphone_count": mic_count,
            "speaker_count": speaker_count,
            "camera_count": camera_count,
        }

        # 插件列表随机化：从常见插件中选取
        all_plugins = [
            {"name": "PDF Viewer",               "filename": "internal-pdf-viewer",   "description": "Portable Document Format"},
            {"name": "Chrome PDF Viewer",         "filename": "internal-pdf-viewer",   "description": "Portable Document Format"},
            {"name": "Chromium PDF Viewer",       "filename": "mhjfbmdgcfjbbpaeojofohoefgiehjai", "description": "Portable Document Format"},
            {"name": "Microsoft Edge PDF Viewer", "filename": "internal-pdf-viewer",   "description": "Portable Document Format"},
            {"name": "WebKit built-in PDF",       "filename": "webkit-openpdf-plugin",  "description": "Portable Document Format"},
        ]
        # 随机选 2-4 个插件，顺序随机
        plugin_count = random.randint(2, min(4, len(all_plugins)))
        chosen_plugins = random.sample(all_plugins, plugin_count)
        plugins_list_cfg = {
            "spoofing_enabled": True,
            "plugins": chosen_plugins,
        }

        # ===== 组装完整配置 =====
        return {
            "global_seed": random.randint(1000000, 99999999),
            "meta": {
                "compliance_mode": compliance_mode,
                "generated_at": int(time.time()),
                "browser_version": chrome_ver,
            },
            # [Phoenix] Lang for Launcher
            "language": lang_code,
            "ua_config": {
                "enabled": True,
                "ua_string": ua_string,
                "platform": "Win32",
                "platform_version": "10.0.0",
                "full_version": chrome_ver,
                "architecture": "x86",
                "bitness": "64",
                "mobile": False,
                "wow64": False,
            },
            "webgl": {
                "vendor": vendor,
                "renderer": renderer,
                "clear_color_noise": 0.0,
                "read_pixels_noise_max": 0,
                "viewport_noise_max": 0,
            },
            "hardware": {
                "concurrency": concurrency,
                "memory_gb": memory_gb,
            },
            "screen": {
                "enable_spoofing": True,
                "width": scr[0],
                "height": scr[1],
                "color_depth": 24,
            },
            "canvas": canvas_cfg,
            "rects": rects_cfg,
            "fonts": fonts_cfg,
            "plugins": plugins_cfg,
            "plugins_list": plugins_list_cfg,
            "media_devices": media_devices_cfg,
            "network": network_cfg,
            "webrtc": {
                "prevent_ip_leak": True,
            },
            "timezone": {
                "spoofing_enabled": True,
                "zone_id": geo_info["timezone"],
            },
            "geo": {
                "spoofing_enabled": True,
                "latitude": geo_info["latitude"],
                "longitude": geo_info["longitude"],
                "accuracy": round(random.uniform(10.0, 50.0), 1),
            },
            "battery": battery_cfg,
            "audio": audio_cfg,
        }

    @staticmethod
    def save_profile(path, config):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
