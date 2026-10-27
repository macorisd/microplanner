// Exercise the real runner on an invisible fixture window, never a user window.
#include "win32_window.h"
#include "../../test/window_size_policy_test.cpp"

#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT,
                             LPARAM monitors) {
  MONITORINFO info{sizeof(MONITORINFO)};
  if (GetMonitorInfo(monitor, &info)) {
    reinterpret_cast<std::vector<RECT>*>(monitors)->push_back(info.rcMonitor);
  }
  return TRUE;
}

void CheckMinimum(HWND hwnd) {
  MONITORINFO info{sizeof(MONITORINFO)};
  Check(GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &info),
        "Cannot read fixture monitor");
  MINMAXINFO limits{};
  SendMessage(hwnd, WM_GETMINMAXINFO, 0, reinterpret_cast<LPARAM>(&limits));
  const LONG width = info.rcMonitor.right - info.rcMonitor.left;
  const LONG height = info.rcMonitor.bottom - info.rcMonitor.top;
  Check(limits.ptMinTrackSize.x * 2 >= width &&
        limits.ptMinTrackSize.x * 2 < width + 2,
        "Width limit is not half the current monitor");
  Check(limits.ptMinTrackSize.y * 2 >= height &&
        limits.ptMinTrackSize.y * 2 < height + 2,
        "Height limit is not half the current monitor");
  RECT actual;
  Check(GetWindowRect(hwnd, &actual), "Cannot read fixture size");
  Check(actual.right - actual.left >= limits.ptMinTrackSize.x,
        "Window shrank below minimum width");
  Check(actual.bottom - actual.top >= limits.ptMinTrackSize.y,
        "Window shrank below minimum height");
  Check(!IsWindowVisible(hwnd), "Sizing fixture must remain invisible");
}
}  // namespace

int main() {
  // This affects only the invisible test process, not the desktop's settings.
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  try {
    Win32Window fixture;
    Check(fixture.Create(L"microplanner sizing fixture", {10, 10}, {1280, 720}),
          "Cannot create native sizing fixture");
    const HWND hwnd = fixture.GetHandle();
    std::vector<RECT> monitors;
    EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                        reinterpret_cast<LPARAM>(&monitors));
    Check(!monitors.empty(), "No monitors found");
    for (const auto& monitor : monitors) {
      SetWindowPos(hwnd, nullptr, monitor.left + 10, monitor.top + 10, 100, 100,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      CheckMinimum(hwnd);
      RECT suggested{monitor.left + 10, monitor.top + 10,
                     monitor.left + 110, monitor.top + 110};
      SendMessage(hwnd, WM_DPICHANGED, MAKELONG(144, 144),
                  reinterpret_cast<LPARAM>(&suggested));
      CheckMinimum(hwnd);
      SendMessage(hwnd, WM_DISPLAYCHANGE, 0, 0);
      CheckMinimum(hwnd);
    }
    std::cout << "Passed native minimum tracking, resize, DPI and display messages on "
              << monitors.size() << " monitor(s); fixture stayed invisible.\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}
