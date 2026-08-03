#include "my_application.h"

#include <cstdlib>
#include <dirent.h>
#include <dlfcn.h>
#include <iostream>
#include <string>
#include <unistd.h>

namespace {

bool IsTruthy(const char* value) {
  if (value == nullptr) return false;
  const std::string normalized(value);
  return normalized == "1" || normalized == "true" ||
         normalized == "TRUE" || normalized == "yes" ||
         normalized == "YES";
}

bool HasUsableRenderNode() {
  DIR* directory = opendir("/dev/dri");
  if (directory == nullptr) return false;

  bool found = false;
  while (const dirent* entry = readdir(directory)) {
    const std::string name(entry->d_name);
    if (name.rfind("renderD", 0) != 0) continue;
    const std::string path = "/dev/dri/" + name;
    if (access(path.c_str(), R_OK | W_OK) == 0) {
      found = true;
      break;
    }
  }
  closedir(directory);
  return found;
}

bool HasOpenGlLoader() {
  void* library = dlopen("libGL.so.1", RTLD_LAZY | RTLD_LOCAL);
  if (library == nullptr) return false;
  const bool usable =
      dlsym(library, "glXGetProcAddressARB") != nullptr ||
      dlsym(library, "glXGetProcAddress") != nullptr;
  dlclose(library);
  return usable;
}

bool HasHardwareVideoDevice() {
  // VA-API (including Crostini's forwarded media/render path) uses the DRM
  // render node. NVIDIA's proprietary decoder may expose /dev/nvidia0. mpv's
  // auto-safe policy performs the codec/API validation after this capability
  // gate; the runner must not downgrade a working Crostini EGL path to CPU.
  return HasUsableRenderNode() || access("/dev/nvidia0", R_OK | W_OK) == 0;
}

void SetCapability(const char* name, bool available) {
  setenv(name, available ? "1" : "0", 1);
}

void ConfigureRenderingPolicy() {
  const bool is_crostini = std::getenv("SOMMELIER_VERSION") != nullptr;
  const bool allow_accelerated_ui =
      IsTruthy(std::getenv("TWITCH_FREEDOM_ACCELERATED_UI"));
  const bool has_render_node = HasUsableRenderNode();
  const bool has_opengl = HasOpenGlLoader();
  const bool has_video_decode = HasHardwareVideoDevice();
  const bool has_gpu_ui = has_render_node && has_opengl;
  SetCapability("TWITCH_FREEDOM_GPU_AVAILABLE", has_render_node);
  SetCapability("TWITCH_FREEDOM_OPENGL_AVAILABLE", has_opengl);
  SetCapability("TWITCH_FREEDOM_HWDEC_AVAILABLE", has_video_decode);
  const bool force_cpu_opengl =
      IsTruthy(std::getenv("TWITCH_FREEDOM_SOFTWARE")) ||
      IsTruthy(std::getenv("LIBGL_ALWAYS_SOFTWARE")) ||
      (!has_gpu_ui && !allow_accelerated_ui);

  // Keep Flutter's OpenGL compositor enabled even on CPU-only hosts. Linux
  // pixel-buffer video textures are uploaded through the OpenGL texture API
  // and are unavailable through Flutter's pure software compositor.
  if (std::getenv("TWITCH_FREEDOM_MEDIA_RENDERER") == nullptr) {
    const bool allow_media_gpu =
        IsTruthy(std::getenv("TWITCH_FREEDOM_MEDIA_GPU"));
    setenv("TWITCH_FREEDOM_MEDIA_RENDERER",
           (!has_video_decode && !allow_media_gpu) || force_cpu_opengl
               ? "software"
               : "hardware",
           1);
  }
  if (std::getenv("TWITCH_FREEDOM_AI_RENDERER") == nullptr) {
    const bool allow_ai_acceleration =
        IsTruthy(std::getenv("TWITCH_FREEDOM_AI_ACCELERATION"));
    setenv("TWITCH_FREEDOM_AI_RENDERER",
           (is_crostini && !allow_ai_acceleration) || force_cpu_opengl
               ? "cpu"
               : "auto",
           1);
  }

  setenv("FLUTTER_LINUX_RENDERER", "opengl", 1);

  if (!force_cpu_opengl) {
    setenv("TWITCH_FREEDOM_RENDERER",
           is_crostini ? "crostini-x11-accelerated" : "gpu-default", 1);
    std::cerr
        << "[TwitchFreedom][LinuxRunner] Rendering policy: ACCELERATED UI; "
        << "gpu=" << (has_render_node ? "yes" : "no")
        << ", opengl=" << (has_opengl ? "yes" : "no")
        << ", hwdec=" << (has_video_decode ? "yes" : "no") << ", "
        << "media=" << std::getenv("TWITCH_FREEDOM_MEDIA_RENDERER")
        << ", ai=" << std::getenv("TWITCH_FREEDOM_AI_RENDERER") << ". "
        << "Set TWITCH_FREEDOM_SOFTWARE=1 for UI fallback." << std::endl;
    return;
  }

  setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
  setenv("GALLIUM_DRIVER", "llvmpipe", 1);
  // Keep half of this eight-vCPU Crostini VM available for Flutter's UI
  // thread, media decoding, GTK input, and optional local inference. Allow an
  // explicit user value to override the conservative default.
  if (std::getenv("LP_NUM_THREADS") == nullptr) {
    setenv("LP_NUM_THREADS", "4", 1);
  }
  setenv("TWITCH_FREEDOM_RENDERER",
         is_crostini ? "crostini-x11-cpu-opengl" : "cpu-opengl-opt-in", 1);

  const char* llvm_threads = std::getenv("LP_NUM_THREADS");

  std::cerr
      << "[TwitchFreedom][LinuxRunner] Rendering policy: CPU OPENGL. "
      << "gpu=" << (has_render_node ? "yes" : "no")
      << ", opengl=" << (has_opengl ? "yes" : "no")
      << ", hwdec=" << (has_video_decode ? "yes" : "no") << ". "
      << "Flutter external textures enabled; Mesa llvmpipe rendering forced."
      << " LIBGL_ALWAYS_SOFTWARE=" << std::getenv("LIBGL_ALWAYS_SOFTWARE")
      << " GALLIUM_DRIVER=" << std::getenv("GALLIUM_DRIVER")
      << " LP_NUM_THREADS=" << (llvm_threads == nullptr ? "auto" : llvm_threads)
      << " media=" << std::getenv("TWITCH_FREEDOM_MEDIA_RENDERER")
      << " ai=" << std::getenv("TWITCH_FREEDOM_AI_RENDERER") << std::endl;
}

void ConfigureDisplayBackend() {
  const char* requested = std::getenv("TWITCH_FREEDOM_GDK_BACKEND");
  if (requested != nullptr && requested[0] != '\0') {
    setenv("GDK_BACKEND", requested, 1);
    std::cerr << "[TwitchFreedom][LinuxRunner] GTK backend override: "
              << requested << "." << std::endl;
    return;
  }

  if (std::getenv("SOMMELIER_VERSION") != nullptr) {
    // Native Wayland avoids an extra X11/Sommelier presentation bridge. It is
    // materially smoother for idle UI scrolling and pointer interaction on a
    // virgl-capable Crostini host. Keep X11 as a compatibility fallback when
    // accelerated GL or the Wayland socket is unavailable.
    const bool wayland_ready = std::getenv("WAYLAND_DISPLAY") != nullptr &&
                                HasUsableRenderNode() && HasOpenGlLoader();
    if (wayland_ready) {
      setenv("GDK_BACKEND", "wayland", 1);
      setenv("TWITCH_FREEDOM_DISPLAY_BACKEND", "wayland-accelerated", 1);
      std::cerr << "[TwitchFreedom][LinuxRunner] Crostini accelerated GTK "
                   "backend: native Wayland."
                << std::endl;
    } else if (std::getenv("DISPLAY") != nullptr) {
      setenv("GDK_BACKEND", "x11", 1);
      setenv("TWITCH_FREEDOM_DISPLAY_BACKEND", "x11-compatible", 1);
      std::cerr << "[TwitchFreedom][LinuxRunner] Crostini compatibility GTK "
                   "backend: X11."
                << std::endl;
    }
  }
}

}  // namespace

int main(int argc, char** argv) {
  ConfigureDisplayBackend();
  ConfigureRenderingPolicy();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
