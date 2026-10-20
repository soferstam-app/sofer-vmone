#include "flutter_window.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mmsystem.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::vector<unsigned char> BuildMetronomeWave(int volume) {
  constexpr int kSampleRate = 44100;
  constexpr int kSamples = kSampleRate * 24 / 1000;
  constexpr int kHeader = 44;
  const int data_length = kSamples * 2;
  std::vector<unsigned char> wave(kHeader + data_length, 0);

  auto ascii = [&wave](int offset, const char* value) {
    for (int i = 0; value[i] != '\0'; ++i) {
      wave[offset + i] = static_cast<unsigned char>(value[i]);
    }
  };
  auto put16 = [&wave](int offset, std::uint16_t value) {
    wave[offset] = static_cast<unsigned char>(value & 0xff);
    wave[offset + 1] = static_cast<unsigned char>((value >> 8) & 0xff);
  };
  auto put32 = [&wave](int offset, std::uint32_t value) {
    for (int i = 0; i < 4; ++i) {
      wave[offset + i] = static_cast<unsigned char>((value >> (i * 8)) & 0xff);
    }
  };

  ascii(0, "RIFF");
  put32(4, 36 + data_length);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  put32(16, 16);
  put16(20, 1);
  put16(22, 1);
  put32(24, kSampleRate);
  put32(28, kSampleRate * 2);
  put16(32, 2);
  put16(34, 16);
  ascii(36, "data");
  put32(40, data_length);

  constexpr double kPi = 3.14159265358979323846;
  std::uint32_t noise = 0x4d595df4;
  const double gain = static_cast<double>(volume) / 100.0;
  for (int i = 0; i < kSamples; ++i) {
    const double time = static_cast<double>(i) / kSampleRate;
    const double decay = std::exp(-time * 185.0);
    noise = 1664525u * noise + 1013904223u;
    const double random =
        (static_cast<double>(noise) / 4294967295.0) * 2.0 - 1.0;
    const double tone = std::sin(2.0 * kPi * 2350.0 * time);
    const double shaped = ((tone * .72) + (random * .28)) * decay * gain;
    auto sample = static_cast<int>(std::lround(shaped * 30000.0));
    if (sample < -32768) sample = -32768;
    if (sample > 32767) sample = 32767;
    put16(kHeader + i * 2, static_cast<std::uint16_t>(sample));
  }
  return wave;
}

std::vector<unsigned char> BuildAlertWave() {
  constexpr int kSampleRate = 44100;
  constexpr int kSamples = kSampleRate * 420 / 1000;
  constexpr int kHeader = 44;
  const int data_length = kSamples * 2;
  std::vector<unsigned char> wave(kHeader + data_length, 0);

  auto ascii = [&wave](int offset, const char* value) {
    for (int i = 0; value[i] != '\0'; ++i) {
      wave[offset + i] = static_cast<unsigned char>(value[i]);
    }
  };
  auto put16 = [&wave](int offset, std::uint16_t value) {
    wave[offset] = static_cast<unsigned char>(value & 0xff);
    wave[offset + 1] = static_cast<unsigned char>((value >> 8) & 0xff);
  };
  auto put32 = [&wave](int offset, std::uint32_t value) {
    for (int i = 0; i < 4; ++i) {
      wave[offset + i] =
          static_cast<unsigned char>((value >> (i * 8)) & 0xff);
    }
  };

  ascii(0, "RIFF");
  put32(4, 36 + data_length);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  put32(16, 16);
  put16(20, 1);
  put16(22, 1);
  put32(24, kSampleRate);
  put32(28, kSampleRate * 2);
  put16(32, 2);
  put16(34, 16);
  ascii(36, "data");
  put32(40, data_length);

  constexpr double kPi = 3.14159265358979323846;
  for (int i = 0; i < kSamples; ++i) {
    const double time = static_cast<double>(i) / kSampleRate;
    const bool first = time < .17;
    const bool second = time >= .23;
    const double frequency = first ? 880.0 : 1175.0;
    double edge = 0.0;
    if (first) {
      edge = std::min(time / .012, (.17 - time) / .018);
    } else if (second) {
      edge = std::min((time - .23) / .012, (.42 - time) / .025);
    }
    const double envelope = std::max(0.0, std::min(1.0, edge));
    auto sample = static_cast<int>(std::lround(
        std::sin(2.0 * kPi * frequency * time) * envelope * 28500.0));
    if (sample < -32768) sample = -32768;
    if (sample > 32767) sample = 32767;
    put16(kHeader + i * 2, static_cast<std::uint16_t>(sample));
  }
  return wave;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  metronome_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "sofer_vmone/metronome",
          &flutter::StandardMethodCodec::GetInstance());
  metronome_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "beat" && call.method_name() != "alert") {
          result->NotImplemented();
          return;
        }
        if (call.method_name() == "alert") {
          PlaySoundA(nullptr, nullptr, 0);
          alert_wave_ = BuildAlertWave();
          PlaySoundA(reinterpret_cast<LPCSTR>(alert_wave_.data()), nullptr,
                     SND_ASYNC | SND_MEMORY | SND_NODEFAULT);
          result->Success();
          return;
        }
        int volume = 70;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          const auto at = arguments->find(flutter::EncodableValue("volume"));
          if (at != arguments->end()) {
            if (const auto* value = std::get_if<std::int32_t>(&at->second)) {
              volume = *value;
            } else if (const auto* value64 =
                           std::get_if<std::int64_t>(&at->second)) {
              volume = static_cast<int>(*value64);
            }
          }
        }
        if (volume < 0) volume = 0;
        if (volume > 100) volume = 100;
        PlaySoundA(nullptr, nullptr, 0);
        if (volume > 0) {
          metronome_wave_ = BuildMetronomeWave(volume);
          PlaySoundA(reinterpret_cast<LPCSTR>(metronome_wave_.data()), nullptr,
                     SND_ASYNC | SND_MEMORY | SND_NODEFAULT);
        }
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  PlaySoundA(nullptr, nullptr, 0);
  metronome_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
