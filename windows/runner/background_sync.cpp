#include "background_sync.h"
#include <windows.h>
#include <taskschd.h>
#include <sddl.h>
#include <wrl/client.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/base.h>
#include <algorithm>
#include <chrono>
#include <memory>
#include <string>
#include <vector>
#include "flutter/generated_plugin_registrant.h"
#include "notifications.h"

using Microsoft::WRL::ComPtr;
namespace background_sync {
namespace {
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
HANDLE gate = nullptr;
bool held = false, headless = false, complete = false;
class Bstr {
 public:
  explicit Bstr(const std::wstring& value) : value_(SysAllocString(value.c_str())) {}
  ~Bstr() { SysFreeString(value_); }
  BSTR get() const { return value_; }
 private:
  BSTR value_;
};
std::wstring UserSid() {
  HANDLE token = nullptr;
  winrt::check_bool(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token));
  DWORD size = 0; GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> data(size);
  const BOOL ok = GetTokenInformation(token, TokenUser, data.data(), size, &size);
  CloseHandle(token); winrt::check_bool(ok);
  LPWSTR sid = nullptr;
  winrt::check_bool(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid, &sid));
  std::wstring value(sid); LocalFree(sid); return value;
}
HANDLE Gate() {
  if (!gate) gate = CreateMutexW(nullptr, FALSE, (L"Local\\microplanner-reminder-sync-" + UserSid()).c_str());
  winrt::check_bool(gate != nullptr); return gate;
}
std::wstring TaskName() { return L"microplanner reminder sync " + UserSid(); }
bool Acquire(DWORD timeout) {
  auto result = WaitForSingleObject(Gate(), timeout);
  held = result == WAIT_OBJECT_0 || result == WAIT_ABANDONED;
  return held;
}
void Release() { if (held) { ReleaseMutex(Gate()); held = false; } }
ComPtr<ITaskFolder> Folder() {
  ComPtr<ITaskService> service;
  winrt::check_hresult(CoCreateInstance(CLSID_TaskScheduler, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&service)));
  VARIANT empty; VariantInit(&empty);
  winrt::check_hresult(service->Connect(empty, empty, empty, empty));
  ComPtr<ITaskFolder> folder;
  winrt::check_hresult(service->GetFolder(Bstr(L"\\").get(), &folder));
  return folder;
}
std::wstring Xml(const std::wstring& input) {
  std::wstring value;
  for (auto c : input) {
    if (c == L'&') value += L"&amp;";
    else if (c == L'<') value += L"&lt;";
    else if (c == L'>') value += L"&gt;";
    else if (c == L'\"') value += L"&quot;";
    else value += c;
  }
  return value;
}
void Configure(bool enabled) {
  auto folder = Folder();
  if (!enabled) {
    auto result = folder->DeleteTask(Bstr(TaskName()).get(), 0);
    if (FAILED(result) && result != HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)) winrt::check_hresult(result);
    return;
  }
  wchar_t buffer[32768]; GetModuleFileNameW(nullptr, buffer, 32768);
  const std::wstring exe(buffer), sid = UserSid();
  SYSTEMTIME time; GetSystemTime(&time);
  wchar_t stamp[40];
  swprintf_s(stamp, L"%04u-%02u-%02uT%02u:%02u:%02uZ", time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond);
  const std::wstring xml = L"<?xml version=\"1.0\"?><Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">"
    L"<RegistrationInfo><Description>Keep microplanner reminders up to date without opening a window.</Description></RegistrationInfo>"
    L"<Triggers><TimeTrigger><Repetition><Interval>PT30M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>" + std::wstring(stamp) +
    L"</StartBoundary><Enabled>true</Enabled></TimeTrigger><LogonTrigger><Enabled>true</Enabled><UserId>" + sid +
    L"</UserId><Delay>PT1M</Delay></LogonTrigger></Triggers><Principals><Principal id=\"User\"><UserId>" + sid +
    L"</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>"
    L"<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>"
    L"<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>"
    L"<Enabled>true</Enabled><Hidden>true</Hidden><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT1M</ExecutionTimeLimit><Priority>7</Priority></Settings>"
    L"<Actions Context=\"User\"><Exec><Command>" + Xml(exe) + L"</Command><Arguments>--background-reminder-sync</Arguments><WorkingDirectory>" +
    Xml(exe.substr(0, exe.find_last_of(L"\\/"))) + L"</WorkingDirectory></Exec></Actions></Task>";
  VARIANT user, empty; VariantInit(&user); VariantInit(&empty);
  user.vt = VT_BSTR; user.bstrVal = SysAllocString(sid.c_str());
  ComPtr<IRegisteredTask> task;
  const auto result = folder->RegisterTask(Bstr(TaskName()).get(), Bstr(xml).get(), TASK_CREATE_OR_UPDATE,
    user, empty, TASK_LOGON_INTERACTIVE_TOKEN, empty, &task);
  VariantClear(&user); winrt::check_hresult(result);
}
bool Registered() {
  ComPtr<IRegisteredTask> task;
  const auto result = Folder()->GetTask(Bstr(TaskName()).get(), &task);
  if (FAILED(result)) return false;
  VARIANT_BOOL enabled = VARIANT_FALSE;
  winrt::check_hresult(task->get_Enabled(&enabled)); return enabled == VARIANT_TRUE;
}
}
void Bind(flutter::BinaryMessenger* messenger) {
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
    messenger, "microplanner/backgroundSync", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      const auto& method = call.method_name();
      if (method == "foregroundStart") {
        if (!Acquire(60000)) throw std::runtime_error("Reminder sync did not finish");
        result->Success();
      } else if (method == "configure") { Configure(std::get<bool>(*call.arguments())); result->Success(); }
      else if (method == "status") { result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("registered"), flutter::EncodableValue(Registered())}})); }
      else if (method == "acquire" && headless) result->Success(flutter::EncodableValue(Acquire(0)));
      else if (method == "release" && headless) { Release(); result->Success(); }
      else if (method == "complete" && headless) {
        const auto state = std::get<std::string>(*call.arguments());
        HKEY health = nullptr;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\microplanner\\ReminderSync", 0, nullptr, 0, KEY_SET_VALUE, nullptr, &health, nullptr) == ERROR_SUCCESS) {
          const auto outcome = winrt::to_hstring(state);
          RegSetValueExW(health, L"LastResult", 0, REG_SZ,
            reinterpret_cast<const BYTE*>(outcome.c_str()), static_cast<DWORD>((outcome.size() + 1) * sizeof(wchar_t)));
          RegCloseKey(health);
        }
        if (state == "disabled" || state == "expired") Configure(false);
        complete = true; result->Success();
      }
      else result->NotImplemented();
    } catch (const winrt::hresult_error&) { result->Error("background", "Background sync could not be scheduled. Try again."); }
    catch (const std::exception&) { result->Error("background", "Background sync is unavailable. Try again."); }
  });
}
int Run() {
  // Avoid starting a second engine while the normal app owns reminders.
  if (!Acquire(0)) return 0;
  Release(); headless = true;
  try {
    reminders::Initialize(false);
    flutter::DartProject project(L"data");
    project.set_dart_entrypoint("backgroundReminderSync");
    project.set_gpu_preference(flutter::GpuPreference::LowPowerPreference);
    flutter::FlutterEngine engine(project);
    if (!engine.Run()) return 1;
    RegisterPlugins(&engine);
    reminders::Bind(engine.messenger(), nullptr);
    Bind(engine.messenger());
    const ULONGLONG limit = GetTickCount64() + 55000;
    while (!complete && GetTickCount64() < limit) {
      auto delay = std::chrono::duration_cast<std::chrono::milliseconds>(engine.ProcessMessages()).count();
      MsgWaitForMultipleObjectsEx(0, nullptr, static_cast<DWORD>((std::max)(int64_t(0), (std::min)(int64_t(200), int64_t(delay)))), QS_ALLINPUT, MWMO_INPUTAVAILABLE);
      MSG msg;
      while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    }
    Release(); channel.reset(); reminders::Shutdown(); engine.ShutDown();
    return complete ? 0 : 1;
  } catch (...) { Release(); return 1; }
}
}
