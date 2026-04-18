#include "third_party/blink/renderer/core/frame/navigator_device_memory.h"

#include "third_party/blink/public/common/device_memory/approximated_device_memory.h"
#include "third_party/blink/renderer/core/frame/fingerprint_config.h"

namespace blink {

// [Modified] Fingerprint Spoofing
float NavigatorDeviceMemory::deviceMemory() const {
  blink::FingerprintConfig* config = blink::FingerprintConfig::GetInstance();
  if (config && config->ua.enabled) {
    return config->GetDeviceMemory();
  }
  return ApproximatedDeviceMemory::GetApproximatedDeviceMemory();
}

}  // namespace blink
