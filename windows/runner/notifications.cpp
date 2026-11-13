#include "notifications.h"

#include <notificationactivationcallback.h>
#include <shlobj.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Notifications.h>
#include <fstream>
#include <mutex>
#include <sstream>

namespace reminders {
using namespace winrt::Windows::UI::Notifications;
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
using Microsoft::WRL::ComPtr;
constexpr wchar_t kAppId[] = L"microplanner.DeadlineReminders";
constexpr wchar_t kClsid[] = L"{11D20DF4-31D3-4F92-94F4-B5B13AF04047}";
const CLSID kActivator = {0x11d20df4,0x31d3,0x4f92,{0x94,0xf4,0xb5,0xb1,0x3a,0xf0,0x40,0x47}};
constexpr ULONG_PTR kActivationMessage = 0x4d50524e;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
std::mutex pending_mutex;
std::string pending;
HWND main_window = nullptr;
DWORD registration = 0;

std::wstring Executable() {
  wchar_t path[32768];
  DWORD length = GetModuleFileNameW(nullptr, path, 32768);
  return std::wstring(path, length);
}
void RegistryString(const std::wstring& key, const wchar_t* name,
                    const std::wstring& value) {
  HKEY handle;
  winrt::check_win32(RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr,
      0, KEY_SET_VALUE, nullptr, &handle, nullptr));
  LSTATUS status = RegSetValueExW(handle, name, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(handle);
  winrt::check_win32(status);
}
void Activate(const std::wstring& argument) {
  {
    std::lock_guard<std::mutex> lock(pending_mutex);
    pending = winrt::to_string(argument);
  }
  // COM can invoke on another thread. Transfer navigation to the UI thread.
  if (main_window) PostMessageW(main_window, WM_APP + 81, 0, 0);
}
class Activator final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
    INotificationActivationCallback> {
 public:
  HRESULT STDMETHODCALLTYPE Activate(LPCWSTR, LPCWSTR args,
      const NOTIFICATION_USER_INPUT_DATA*, ULONG) override {
    reminders::Activate(args ? args : L"");
    return S_OK;
  }
};
class Factory final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IClassFactory> {
 public:
  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid,
                                           void** result) override {
    if (outer) return CLASS_E_NOAGGREGATION;
    return Microsoft::WRL::Make<Activator>()->QueryInterface(iid, result);
  }
  HRESULT STDMETHODCALLTYPE LockServer(BOOL) override { return S_OK; }
};
ToastNotifier Notifier() { return ToastNotificationManager::CreateToastNotifier(kAppId); }

std::wstring XmlEscape(const std::string& text) {
  std::wstring result;
  for (wchar_t c : winrt::to_hstring(text)) {
    switch (c) {
      case L'&': result += L"&amp;"; break;
      case L'<': result += L"&lt;"; break;
      case L'>': result += L"&gt;"; break;
      case L'\"': result += L"&quot;"; break;
      case L'\'': result += L"&apos;"; break;
      default: if (c >= 32 || c == 10 || c == 13 || c == 9) result += c;
    }
  }
  return result;
}
winrt::Windows::Data::Xml::Dom::XmlDocument Content(
    const std::string& title, const std::string& body, const std::string& payload) {
  winrt::Windows::Data::Xml::Dom::XmlDocument doc;
  doc.LoadXml(L"<toast launch=\"" + XmlEscape(payload) +
      L"\"><visual><binding template=\"ToastGeneric\"><text>" + XmlEscape(title) +
      L"</text><text>" + XmlEscape(body) + L"</text></binding></visual></toast>");
  return doc;
}
void Cancel(int64_t id) {
  auto tag = winrt::to_hstring(std::to_string(id));
  auto notifier = Notifier();
  for (auto event : notifier.GetScheduledToastNotifications()) {
    if (event.Tag() == tag) notifier.RemoveFromSchedule(event);
  }
  ToastNotificationManager::History().Remove(tag, L"reminders", kAppId);
}
void Schedule(int64_t id, int64_t at, const std::string& title,
              const std::string& body, const std::string& payload, int64_t expires = 0) {
  Cancel(id);
  auto content = Content(title, body, payload);
  auto tag = winrt::to_hstring(std::to_string(id));
  auto when = winrt::clock::from_time_t(static_cast<time_t>(at / 1000)) +
      std::chrono::milliseconds(at % 1000);
  if (when <= winrt::clock::now()) {
    ToastNotification event(content);
    event.Tag(tag); event.Group(L"reminders");
    if (expires > 0) event.ExpirationTime(winrt::clock::from_time_t(static_cast<time_t>(expires / 1000)));
    Notifier().Show(event);
  } else {
    ScheduledToastNotification event(content, when);
    event.Tag(tag); event.Group(L"reminders");
    if (expires > 0) event.ExpirationTime(winrt::clock::from_time_t(static_cast<time_t>(expires / 1000)));
    Notifier().AddToSchedule(event);
  }
}
const EncodableValue& Field(const EncodableMap& map, const char* key) {
  return map.at(EncodableValue(key));
}
int64_t Number(const EncodableValue& value) {
  if (auto number = std::get_if<int64_t>(&value)) return *number;
  return std::get<int32_t>(value);
}

void Initialize() {
  auto exe = Executable();
  RegistryString(L"Software\\Classes\\CLSID\\" + std::wstring(kClsid) +
      L"\\LocalServer32", nullptr, L"\"" + exe + L"\" -ToastActivated");
  auto app = L"Software\\Classes\\AppUserModelId\\" + std::wstring(kAppId);
  RegistryString(app, L"DisplayName", L"microplanner");
  RegistryString(app, L"CustomActivator", kClsid);
  RegistryString(app, L"IconUri", exe.substr(0, exe.find_last_of(L"\\/")) + L"\\microplanner.ico");
  winrt::check_hresult(SetCurrentProcessExplicitAppUserModelID(kAppId));
  // A real Start Menu shortcut is required for classic desktop notification identity.
  PWSTR programs = nullptr;
  winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs));
  auto shortcut = std::wstring(programs) + L"\\microplanner.lnk";
  CoTaskMemFree(programs);
  ComPtr<IShellLinkW> link;
  winrt::check_hresult(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&link)));
  winrt::check_hresult(link->SetPath(exe.c_str()));
  winrt::check_hresult(link->SetWorkingDirectory(exe.substr(0, exe.find_last_of(L"\\/")).c_str()));
  ComPtr<IPropertyStore> properties;
  winrt::check_hresult(link.As(&properties));
  PROPVARIANT app_id; InitPropVariantFromString(kAppId, &app_id);
  winrt::check_hresult(properties->SetValue(PKEY_AppUserModel_ID, app_id));
  PropVariantClear(&app_id);
  PROPVARIANT activator; InitPropVariantFromCLSID(kActivator, &activator);
  winrt::check_hresult(properties->SetValue(PKEY_AppUserModel_ToastActivatorCLSID, activator));
  PropVariantClear(&activator);
  winrt::check_hresult(properties->Commit());
  ComPtr<IPersistFile> file; winrt::check_hresult(link.As(&file));
  winrt::check_hresult(file->Save(shortcut.c_str(), TRUE));
  ComPtr<IClassFactory> factory = Microsoft::WRL::Make<Factory>();
  winrt::check_hresult(CoRegisterClassObject(kActivator, factory.Get(),
      CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &registration));
  // Classic unpackaged apps need a first, suppressed notification before Windows
  // exposes scheduling/settings. This matches Microsoft's compatibility toolkit.
  ToastNotification bootstrap(Content("microplanner", "Reminders are ready", "{}"));
  bootstrap.Tag(L"registration"); bootstrap.Group(L"reminders");
  bootstrap.SuppressPopup(true);
  bootstrap.ExpirationTime(winrt::clock::now() + std::chrono::seconds(15));
  Notifier().Show(bootstrap);
  ToastNotificationManager::History().Remove(L"registration", L"reminders", kAppId);
}
bool ForwardToExisting() {
  HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"microplanner");
  if (!existing) return false;
  // No payload at initial COM launch: let its factory deliver through this process.
  SetForegroundWindow(existing);
  return true;
}
void Bind(flutter::BinaryMessenger* messenger, HWND window) {
  main_window = window;
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "microplanner/notifications", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      const auto& method = call.method_name();
      if (!registration) Initialize();
      if (method == "status" || method == "requestPermission") {
        result->Success(EncodableValue(EncodableMap{
            {EncodableValue("enabled"), EncodableValue(Notifier().Setting() == NotificationSetting::Enabled)},
            {EncodableValue("precise"), EncodableValue(true)}}));
      } else if (method == "schedule") {
        const auto& map = std::get<EncodableMap>(*call.arguments());
        const auto expires = Number(Field(map, "expires"));
        const auto deadline = Number(Field(map, "deadline"));
        const auto kind = map.find(EncodableValue("atDeadline"));
        const bool at_deadline = kind != map.end() && std::get<bool>(kind->second);
        const auto latest = deadline + (at_deadline ? 300000 : 0);
        Schedule(Number(Field(map,"id")), Number(Field(map,"at")),
            std::get<std::string>(Field(map,"title")), std::get<std::string>(Field(map,"body")),
            std::get<std::string>(Field(map,"payload")), expires < latest ? expires : latest);
        result->Success();
      } else if (method == "cancel") {
        Cancel(Number(*call.arguments())); result->Success();
      } else if (method == "pending") {
        EncodableList ids;
        for (auto item : Notifier().GetScheduledToastNotifications())
          ids.emplace_back(winrt::to_string(item.Tag()));
        result->Success(EncodableValue(ids));
      } else if (method == "launch") {
        std::lock_guard<std::mutex> lock(pending_mutex);
        result->Success(EncodableValue(pending)); pending.clear();
      } else if (method == "settings") {
        ShellExecuteW(nullptr, L"open", L"ms-settings:notifications", nullptr, nullptr, SW_SHOWNORMAL);
        result->Success();
      } else if (method == "exactPermission") {
        result->Success();
      } else result->NotImplemented();
    } catch (const winrt::hresult_error& error) {
      result->Error("notifications", winrt::to_string(error.message()));
    } catch (const std::exception&) {
      result->Error("notifications", "The notification request could not be processed.");
    }
  });
}
bool HandleMessage(UINT message, LPARAM param) {
  if (message == WM_COPYDATA) {
    auto data = reinterpret_cast<COPYDATASTRUCT*>(param);
    if (data->dwData != kActivationMessage || data->cbData > 16384) return false;
    Activate(std::wstring(static_cast<wchar_t*>(data->lpData), data->cbData / sizeof(wchar_t)));
    return true;
  }
  if (message != WM_APP + 81) return false;
  if (channel) channel->InvokeMethod("activated", nullptr);
  ShowWindow(main_window, SW_RESTORE); SetForegroundWindow(main_window);
  return true;
}
void Shutdown() {
  channel.reset(); main_window = nullptr;
  if (registration) { CoRevokeClassObject(registration); registration = 0; }
}
int Probe(const std::wstring& command) {
  // Report stays in the normal bundle, with no account or task data.
  auto path = Executable(); path = path.substr(0, path.find_last_of(L"\\/")) + L"\\notification-check.txt";
  std::ofstream report(path);
  report << "command=[" << winrt::to_string(command) << "]\n";
  try {
    if (command == L"activate" || command == L"activate-reminder") {
      // Exercise the registered COM server, including ordinary cold startup.
      // Do not register this diagnostic process as the activation server.
      ComPtr<INotificationActivationCallback> callback;
      std::wstring payload = L"{}";
      if (command == L"activate-reminder") {
        for (auto item : ToastNotificationManager::History().GetHistory(kAppId)) {
          auto argument = item.Content().DocumentElement().GetAttribute(L"launch");
          if (argument != L"{}" && !argument.empty()) { payload = argument.c_str(); break; }
        }
        if (payload == L"{}") { report << "FAIL no reminder in history\n"; return 1; }
      }
      winrt::check_hresult(CoCreateInstance(kActivator, nullptr, CLSCTX_LOCAL_SERVER,
          IID_PPV_ARGS(&callback)));
      winrt::check_hresult(callback->Activate(kAppId, payload.c_str(), nullptr, 0));
      report << "activation=delivered\nPASS\n";
      return 0;
    }
    Initialize();
    if (command == L"schedule") {
      auto at = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::system_clock::now().time_since_epoch()).count() + 15000;
      Schedule(2147483000, at, "microplanner", "Scheduled reminder test", "{}");
      report << "scheduled at " << at << "\n";
    } else if (command == L"cancel") Cancel(2147483000);
    else if (command == L"show") Schedule(2147483000, 0, "microplanner", "Notification test", "{}");
    report << "enabled=" << (Notifier().Setting() == NotificationSetting::Enabled) << "\n";
    for (auto item : Notifier().GetScheduledToastNotifications()) report << winrt::to_string(item.Tag()) << "\n";
    for (auto item : ToastNotificationManager::History().GetHistory(kAppId))
      report << "displayed=" << winrt::to_string(item.Tag()) << "\n";
    report << "PASS\n";
    Shutdown(); return 0;
  } catch (const winrt::hresult_error& error) {
    report << "FAIL " << winrt::to_string(error.message()) << "\n";
    return 1;
  }
}
}  // namespace reminders
