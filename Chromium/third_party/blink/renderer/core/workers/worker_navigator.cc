/*
 * Copyright (C) 2008 Apple Inc. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#include "third_party/blink/renderer/core/workers/worker_navigator.h"
#include "third_party/blink/public/platform/web_worker_fetch_context.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/dom/events/event_target.h"
#include "third_party/blink/renderer/core/workers/worker_global_scope.h"
#include "third_party/blink/renderer/core/workers/worker_or_worklet_global_scope.h"
#include "third_party/blink/renderer/core/workers/worker_thread.h"
#include "third_party/blink/renderer/platform/loader/fetch/resource_fetcher.h"
#include "third_party/blink/renderer/core/frame/fingerprint_config.h"

namespace blink {

WorkerNavigator::WorkerNavigator(ExecutionContext* execution_context)
    : NavigatorBase(execution_context) {}

WorkerNavigator::~WorkerNavigator() = default;

// [新增代码开始] 这里开始插入指纹混淆逻辑

String WorkerNavigator::userAgent() const {
  FingerprintConfig* config = FingerprintConfig::GetInstance();
  if (config && config->ua.enabled) {
    return config->ua.ua_string;
  }
  return NavigatorBase::userAgent();
}

String WorkerNavigator::platform() const {
  FingerprintConfig* config = FingerprintConfig::GetInstance();
  if (config && config->ua.enabled) {
    return config->ua.platform;
  }
  return NavigatorBase::platform();
}

// 修正 1: 返回值类型改为 unsigned
unsigned WorkerNavigator::hardwareConcurrency() const {
  FingerprintConfig* config = FingerprintConfig::GetInstance();
  if (config) {
    // 强制转换为 unsigned 以匹配签名
    return static_cast<unsigned>(config->GetHardwareConcurrency());
  }
  return NavigatorBase::hardwareConcurrency();
}

// 修正 2: 保持 float，实现覆盖逻辑
float WorkerNavigator::deviceMemory() const {
  FingerprintConfig* config = FingerprintConfig::GetInstance();
  if (config) {
    return config->GetDeviceMemory();
  }
  return NavigatorBase::deviceMemory();
}
// [新增代码结束]

String WorkerNavigator::GetAcceptLanguages() {
  auto* global_scope = To<WorkerOrWorkletGlobalScope>(GetExecutionContext());
  if (!global_scope) {
    // Prospective fix for crbug.com/40945292 and crbug.com/40827704
    // Return empty string since it is better than crashing here, and the return
    // value is not that important since the worker context is already
    // destroyed.
    return "";
  }

  return global_scope->GetAcceptLanguages();
}

void WorkerNavigator::NotifyUpdate() {
  WorkerOrWorkletGlobalScope* global_scope =
      To<WorkerOrWorkletGlobalScope>(GetExecutionContext());
  if (!global_scope) {
    // In case of the context destruction, `GetExecutionContext()` returns
    // nullptr. Then, there is no `global_scope` to execute the language
    // event.
    return;
  }
  SetLanguagesDirty();
  global_scope->DispatchEvent(
      *Event::Create(event_type_names::kLanguagechange));
}

void WorkerNavigator::Trace(Visitor* visitor) const {
  NavigatorBase::Trace(visitor);
  AcceptLanguagesWatcher::Trace(visitor);
}

}  // namespace blink
