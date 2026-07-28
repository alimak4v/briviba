#include "briviba/tab_manager.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <utility>
#include <vector>

namespace briviba {

class TabManager::Impl {
 public:
  Impl() {
    container_view_ = [[NSView alloc] initWithFrame:NSZeroRect];
    [container_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [container_view_ setWantsLayer:YES];
  }

  void CreateInitialTab() {
    if (tabs_.empty()) {
      CreateTab();
    }
  }

  void CreateTab() {
    auto tab = std::make_unique<Tab>();
    tab->SetNavigationStateCallback(navigation_state_callback_);
    tab->SetPageColorCallback(page_color_callback_);

    tabs_.push_back(std::move(tab));
    active_index_ = tabs_.size() - 1;
    MountActiveTab();
    EmitDefaultPageColor();
  }

  bool LoadUrl(const std::string& text) {
    Tab* tab = ActiveTab();
    return tab != nullptr && tab->LoadUrl(text);
  }

  void GoBack() {
    Tab* tab = ActiveTab();
    if (tab != nullptr) {
      tab->GoBack();
    }
  }

  void GoForward() {
    Tab* tab = ActiveTab();
    if (tab != nullptr) {
      tab->GoForward();
    }
  }

  void Reload() {
    Tab* tab = ActiveTab();
    if (tab != nullptr) {
      tab->Reload();
    }
  }

  void SetNavigationStateCallback(NavigationStateCallback callback) {
    navigation_state_callback_ = std::move(callback);
    for (const auto& tab : tabs_) {
      tab->SetNavigationStateCallback(navigation_state_callback_);
    }
  }

  void SetPageColorCallback(PageColorCallback callback) {
    page_color_callback_ = std::move(callback);
    for (const auto& tab : tabs_) {
      tab->SetPageColorCallback(page_color_callback_);
    }
    EmitDefaultPageColor();
  }

  NSView* NativeView() const { return container_view_; }

 private:
  Tab* ActiveTab() {
    if (tabs_.empty() || active_index_ >= tabs_.size()) {
      return nullptr;
    }
    return tabs_[active_index_].get();
  }

  void MountActiveTab() {
    Tab* tab = ActiveTab();
    if (tab == nullptr) {
      return;
    }

    for (NSView* subview in [container_view_ subviews]) {
      [subview removeFromSuperview];
    }

    NSView* tab_view = tab->NativeView();
    [container_view_ addSubview:tab_view];
    [NSLayoutConstraint activateConstraints:@[
      [[tab_view leadingAnchor] constraintEqualToAnchor:[container_view_ leadingAnchor]],
      [[tab_view topAnchor] constraintEqualToAnchor:[container_view_ topAnchor]],
      [[tab_view trailingAnchor] constraintEqualToAnchor:[container_view_ trailingAnchor]],
      [[tab_view bottomAnchor] constraintEqualToAnchor:[container_view_ bottomAnchor]],
    ]];
  }

  void EmitDefaultPageColor() {
    if (page_color_callback_) {
      page_color_callback_(Tab::PageColor{});
    }
  }

  NavigationStateCallback navigation_state_callback_;
  PageColorCallback page_color_callback_;
  std::vector<std::unique_ptr<Tab>> tabs_;
  size_t active_index_ = 0;
  NSView* container_view_ = nil;
};

TabManager::TabManager() : impl_(std::make_unique<Impl>()) {}

TabManager::~TabManager() = default;

void TabManager::CreateInitialTab() {
  impl_->CreateInitialTab();
}

void TabManager::CreateTab() {
  impl_->CreateTab();
}

bool TabManager::LoadUrl(const std::string& text) {
  return impl_->LoadUrl(text);
}

void TabManager::GoBack() {
  impl_->GoBack();
}

void TabManager::GoForward() {
  impl_->GoForward();
}

void TabManager::Reload() {
  impl_->Reload();
}

void TabManager::SetNavigationStateCallback(NavigationStateCallback callback) {
  impl_->SetNavigationStateCallback(std::move(callback));
}

void TabManager::SetPageColorCallback(PageColorCallback callback) {
  impl_->SetPageColorCallback(std::move(callback));
}

NSView* TabManager::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba
