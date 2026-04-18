#include "third_party/blink/renderer/core/frame/navigator_concurrent_hardware.h"

#include "base/system/sys_info.h"  // Added for base::SysInfo::NumberOfProcessors()
#include "third_party/blink/renderer/core/frame/fingerprint_config.h"

namespace blink {

// [Modified] Fingerprint Spoofing
unsigned NavigatorConcurrentHardware::hardwareConcurrency() const {
  blink::FingerprintConfig* config = blink::FingerprintConfig::GetInstance();
  if (config && config->ua.enabled) {
    return config->GetHardwareConcurrency();
  }
  return static_cast<unsigned>(base::SysInfo::NumberOfProcessors());
}
}  // namespace blink
