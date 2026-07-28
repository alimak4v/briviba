#ifndef BRIVIBA_WINDOW_MANAGER_H_
#define BRIVIBA_WINDOW_MANAGER_H_

#include <memory>
#include <vector>

#include "briviba/browser_window.h"

namespace briviba {

class WindowManager {
 public:
  WindowManager();
  ~WindowManager();

  WindowManager(const WindowManager&) = delete;
  WindowManager& operator=(const WindowManager&) = delete;

  void OpenInitialWindow();

 private:
  std::vector<std::unique_ptr<BrowserWindow>> windows_;
};

}  // namespace briviba

#endif  // BRIVIBA_WINDOW_MANAGER_H_
