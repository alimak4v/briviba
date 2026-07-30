#ifndef BRIVIBA_BROWSER_WINDOW_H_
#define BRIVIBA_BROWSER_WINDOW_H_

#include <memory>

namespace briviba {

class BrowserWindow {
 public:
  BrowserWindow();
  ~BrowserWindow();

  BrowserWindow(const BrowserWindow&) = delete;
  BrowserWindow& operator=(const BrowserWindow&) = delete;

  void Show();
  void CreateNewTab();

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_BROWSER_WINDOW_H_
