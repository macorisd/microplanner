#pragma once

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <memory>
#include <string>

namespace reminders {
// Register only per-user shell/COM identity; no service or package is installed.
void Initialize();
void Shutdown();
void Bind(flutter::BinaryMessenger* messenger, HWND window);
bool HandleMessage(UINT message, LPARAM param);
bool ForwardToExisting();
// Diagnostic gate uses the same adapter and executable, without opening user data.
int Probe(const std::wstring& command);
}  // namespace reminders
