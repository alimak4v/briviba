#include "briviba/tab_manager.h"

#include "briviba/cookie_manager.h"
#include "briviba/download_manager.h"

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
  Impl(CookieManager& cookie_manager, DownloadManager& download_manager)
      : cookie_manager_(cookie_manager), download_manager_(download_manager) {
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
    tabs_.push_back(
        ManagedTab{CreateTabForTopLevelSite(std::string()), std::string(), browsing_mode_});
    active_index_ = tabs_.size() - 1;
    MountActiveTab();
    EmitDefaultPageColor();
  }

  bool LoadUrl(const std::string& text) {
    const std::string top_level_site = TopLevelSiteFromInput(text);
    if (!top_level_site.empty() &&
        (ActiveTopLevelSite() != top_level_site || ActiveBrowsingMode() != browsing_mode_)) {
      ReplaceActiveTabForTopLevelSite(top_level_site);
    }

    Tab* tab = ActiveTab();
    return tab != nullptr && tab->LoadUrl(text);
  }

  std::string CurrentUrl() const {
    const Tab* tab = ActiveTab();
    return tab == nullptr ? std::string() : tab->CurrentUrl();
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

  void SetBrowsingMode(BrowsingMode mode) {
    if (browsing_mode_ == mode) {
      return;
    }
    browsing_mode_ = mode;
    CreateTab();
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
    BrowsingMode browsing_mode = BrowsingMode::kNormal;
  };

  Tab* ActiveTab() {
    if (tabs_.empty() || active_index_ >= tabs_.size()) {
      return nullptr;
    }
    return tabs_[active_index_].tab.get();
  }

  const Tab* ActiveTab() const {
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

  BrowsingMode ActiveBrowsingMode() const {
    if (tabs_.empty() || active_index_ >= tabs_.size()) {
      return BrowsingMode::kNormal;
    }
    return tabs_[active_index_].browsing_mode;
  }

  std::unique_ptr<Tab> CreateTabForTopLevelSite(const std::string& top_level_site) {
    WKWebsiteDataStore* data_store = cookie_manager_.NormalWebsiteDataStore();
    if (browsing_mode_ == BrowsingMode::kSecure) {
      data_store = cookie_manager_.SecureWebsiteDataStore();
    } else if (!top_level_site.empty()) {
      data_store = cookie_manager_.WebsiteDataStoreForTopLevelSite(top_level_site);
    }
    auto tab = std::make_unique<Tab>(data_store, download_manager_);
    tab->SetNavigationStateCallback(navigation_state_callback_);
    tab->SetPageColorCallback(page_color_callback_);
    return tab;
  }

  void ReplaceActiveTabForTopLevelSite(const std::string& top_level_site) {
    ManagedTab managed_tab{
        CreateTabForTopLevelSite(top_level_site),
        top_level_site,
        browsing_mode_,
    };
    if (tabs_.empty()) {
      tabs_.push_back(std::move(managed_tab));
      active_index_ = 0;
    } else {
      tabs_[active_index_] = std::move(managed_tab);
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
  DownloadManager& download_manager_;
  BrowsingMode browsing_mode_ = BrowsingMode::kNormal;
  std::vector<ManagedTab> tabs_;
  size_t active_index_ = 0;
  NSView* container_view_ = nil;
};

TabManager::TabManager(CookieManager& cookie_manager, DownloadManager& download_manager)
    : impl_(std::make_unique<Impl>(cookie_manager, download_manager)) {}

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

std::string TabManager::CurrentUrl() const {
  return impl_->CurrentUrl();
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

void TabManager::SetBrowsingMode(BrowsingMode mode) {
  impl_->SetBrowsingMode(mode);
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
