#ifndef BRIVIBA_TOOLBAR_H_
#define BRIVIBA_TOOLBAR_H_

#include <functional>
#include <memory>
#include <string>

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class Toolbar {
 public:
  using Action = std::function<void()>;
  using AddressSubmitAction = std::function<void(const std::string& text)>;

  Toolbar();
  ~Toolbar();

  Toolbar(const Toolbar&) = delete;
  Toolbar& operator=(const Toolbar&) = delete;

  void SetBackAction(Action action);
  void SetForwardAction(Action action);
  void SetReloadAction(Action action);
  void SetBookmarkAction(Action action);
  void SetMenuAction(Action action);
  void SetSettingsAction(Action action);
  void SetAddressSubmitAction(AddressSubmitAction action);
  void SetAddressText(const std::string& text);
  void SetPageIdentity(const std::string& url, const std::string& title);
  void SetNavigationState(bool can_go_back, bool can_go_forward);

#ifdef __OBJC__
  NSView* NativeView() const;
  NSView* AddressFieldNativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_TOOLBAR_H_
