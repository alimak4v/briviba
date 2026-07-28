#include "briviba/window_manager.h"

#include <memory>

namespace briviba {

WindowManager::WindowManager() = default;

WindowManager::~WindowManager() = default;

void WindowManager::OpenInitialWindow() {
  auto window = std::make_unique<BrowserWindow>();
  window->Show();
  windows_.push_back(std::move(window));
}

}  // namespace briviba
