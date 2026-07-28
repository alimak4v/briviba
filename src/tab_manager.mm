#include "briviba/tab_manager.h"

#include "briviba/cookie_manager.h"

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace briviba {
namespace {

std::string StringFromNSString(NSString* value) {
  const char* utf8 = [value UTF8String];
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

std::string TopLevelSiteFromInput(const std::string& text) {
  NSString* raw_text = [NSString stringWithUTF8String:text.c_str()];
  NSString* trimmed =
      [raw_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return std::string();
  }

  NSString* url_text = [trimmed containsString:@"://"]
                           ? trimmed
                           : [NSString stringWithFormat:@"https://%@", trimmed];
  NSURL* url = [NSURL URLWithString:url_text];
  NSString* host = [[url host] lowercaseString];
  return host == nil ? std::string() : StringFromNSString(host);
}

}  // namespace

class TabManager::Impl {
 public:
  explicit Impl(CookieManager& cookie_manager) : cookie_manager_(cookie_manager) {
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
    tabs_.push_back(ManagedTab{CreateTabForTopLevelSite(std::string()), std::string()});
    active_index_ = tabs_.size() - 1;
    MountActiveTab();
    EmitDefaultPageColor();
  }

  bool LoadUrl(const std::string& text) {
    const std::string top_level_site = TopLevelSiteFromInput(text);
    if (!top_level_site.empty() && ActiveTopLevelSite() != top_level_site) {
      ReplaceActiveTabForTopLevelSite(top_level_site);
    }

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
    for (auto& tab : tabs_) {
      tab.tab->SetNavigationStateCallback(navigation_state_callback_);
    }
  }

  void SetPageColorCallback(PageColorCallback callback) {
    page_color_callback_ = std::move(callback);
    for (auto& tab : tabs_) {
      tab.tab->SetPageColorCallback(page_color_callback_);
    }
    EmitDefaultPageColor();
  }

  NSView* NativeView() const { return container_view_; }

 private:
  struct ManagedTab {
    std::unique_ptr<Tab> tab;
    std::string top_level_site;
  };

  Tab* ActiveTab() {
    if (tabs_.empty() || active_index_ >= tabs_.size()) {
      return nullptr;
    }
    return tabs_[active_index_].tab.get();
  }

  std::string ActiveTopLevelSite() const {
    if (tabs_.empty() || active_index_ >= tabs_.size()) {
      return std::string();
    }
    return tabs_[active_index_].top_level_site;
  }

  std::unique_ptr<Tab> CreateTabForTopLevelSite(const std::string& top_level_site) {
    WKWebsiteDataStore* data_store =
        top_level_site.empty() ? cookie_manager_.NormalWebsiteDataStore()
                               : cookie_manager_.WebsiteDataStoreForTopLevelSite(top_level_site);
    auto tab = std::make_unique<Tab>(data_store);
    tab->SetNavigationStateCallback(navigation_state_callback_);
    tab->SetPageColorCallback(page_color_callback_);
    return tab;
  }

  void ReplaceActiveTabForTopLevelSite(const std::string& top_level_site) {
    if (tabs_.empty()) {
      tabs_.push_back(ManagedTab{CreateTabForTopLevelSite(top_level_site), top_level_site});
      active_index_ = 0;
    } else {
      tabs_[active_index_] = ManagedTab{CreateTabForTopLevelSite(top_level_site), top_level_site};
    }
    MountActiveTab();
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
  CookieManager& cookie_manager_;
  std::vector<ManagedTab> tabs_;
  size_t active_index_ = 0;
  NSView* container_view_ = nil;
};

TabManager::TabManager(CookieManager& cookie_manager)
    : impl_(std::make_unique<Impl>(cookie_manager)) {}

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
