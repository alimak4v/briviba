#include "briviba/tab_manager.h"

#include "briviba/cookie_manager.h"
#include "briviba/download_manager.h"

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include <algorithm>
#include <cctype>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace briviba {
namespace {

constexpr size_t kLoadedTabSoftLimit = 4;

std::string StringFromNSString(NSString* value) {
  const char* utf8 = [value UTF8String];
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

std::string SiteKeyFromHost(std::string host) {
  std::transform(host.begin(), host.end(), host.begin(), [](unsigned char character) {
    return static_cast<char>(std::tolower(character));
  });
  while (!host.empty() && host.back() == '.') {
    host.pop_back();
  }
  for (const std::string& prefix : {"www.", "m.", "mobile."}) {
    if (host.starts_with(prefix) && host.size() > prefix.size()) {
      host.erase(0, prefix.size());
      break;
    }
  }

  const size_t last_dot = host.rfind('.');
  if (last_dot == std::string::npos) {
    return host;
  }
  const size_t previous_dot = host.rfind('.', last_dot - 1);
  if (previous_dot == std::string::npos) {
    return host;
  }
  return host.substr(previous_dot + 1);
}

NSString* SearchEngineHomeUrl(const std::string& engine_id) {
  if (engine_id == "google") {
    return @"https://www.google.com";
  }
  if (engine_id == "bing") {
    return @"https://www.bing.com";
  }
  if (engine_id == "yandex") {
    return @"https://yandex.ru";
  }
  return @"https://duckduckgo.com";
}

std::string TopLevelSiteFromInput(const std::string& text, const std::string& search_engine_id) {
  NSString* raw_text = [NSString stringWithUTF8String:text.c_str()];
  NSString* trimmed =
      [raw_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return std::string();
  }

  NSString* url_text = nil;
  if (![trimmed containsString:@"://"] &&
      ([trimmed containsString:@" "] || ![trimmed containsString:@"."])) {
    url_text = SearchEngineHomeUrl(search_engine_id);
  } else {
    url_text = [trimmed containsString:@"://"]
                   ? trimmed
                   : [NSString stringWithFormat:@"https://%@", trimmed];
  }
  NSURL* url = [NSURL URLWithString:url_text];
  NSString* host = [[url host] lowercaseString];
  return host == nil ? std::string() : SiteKeyFromHost(StringFromNSString(host));
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
    tabs_.push_back(ManagedTab{CreateTabForTopLevelSite(std::string()), next_tab_identity_++,
                               std::string(), std::string(), std::string(), std::string(),
                               browsing_mode_, 0});
    active_index_ = tabs_.size() - 1;
    MountActiveTab();
    EmitTabState();
    EmitDefaultPageColor();
  }

  bool RestoreTabs(const std::vector<std::string>& urls, size_t active_index) {
    std::vector<std::string> restore_urls;
    restore_urls.reserve(urls.size());
    for (const std::string& url : urls) {
      if (!url.empty()) {
        restore_urls.push_back(url);
      }
    }
    if (restore_urls.empty()) {
      return false;
    }

    for (NSView* subview in [container_view_ subviews]) {
      [subview removeFromSuperview];
    }
    tabs_.clear();
    active_index_ = 0;

    for (const std::string& url : restore_urls) {
      const std::string top_level_site = TopLevelSiteFromInput(url, search_engine_id_);
      auto tab = CreateTabForTopLevelSite(top_level_site);
      tab->SetRestoredUrl(url);
      tabs_.push_back(ManagedTab{std::move(tab), next_tab_identity_++, top_level_site, url,
                                 std::string(), std::string(), browsing_mode_, 0});
    }

    active_index_ = std::min(active_index, tabs_.size() - 1);
    MountActiveTab();
    EmitTabState();
    return true;
  }

  void SelectTab(size_t index) {
    if (index >= tabs_.size() || index == active_index_) {
      return;
    }
    tabs_[active_index_].tab->ExitFullscreen();
    active_index_ = index;
    MountActiveTab();
    EmitTabState();
  }

  void CloseTab(size_t index) {
    if (index >= tabs_.size() || tabs_.size() <= 1) {
      return;
    }

    const bool closing_active_tab = index == active_index_;
    if (closing_active_tab) {
      tabs_[index].tab->ExitFullscreen();
    }
    RemoveTabView(index);
    tabs_.erase(tabs_.begin() + static_cast<std::vector<ManagedTab>::difference_type>(index));
    if (active_index_ > index) {
      --active_index_;
    } else if (active_index_ >= tabs_.size()) {
      active_index_ = tabs_.size() - 1;
    }

    if (closing_active_tab) {
      MountActiveTab();
      EmitActiveManagedNavigationState();
    }
    EmitTabState();
  }

  bool LoadUrl(const std::string& text) {
    const std::string top_level_site = TopLevelSiteFromInput(text, search_engine_id_);
    if (tabs_.empty()) {
      CreateTab();
    }
    if (!tabs_.empty() && active_index_ < tabs_.size()) {
      RetargetActiveTabIfNeeded(top_level_site);
    }

    Tab* tab = ActiveTab();
    return tab != nullptr && tab->LoadUrl(text);
  }

  std::string CurrentUrl() const {
    const Tab* tab = ActiveTab();
    return tab == nullptr ? std::string() : tab->CurrentUrl();
  }

  std::string UrlForTab(size_t index) const {
    if (index >= tabs_.size()) {
      return std::string();
    }
    return tabs_[index].url.empty() ? tabs_[index].tab->CurrentUrl() : tabs_[index].url;
  }

  std::vector<std::string> SessionUrls() const {
    std::vector<std::string> urls;
    urls.reserve(tabs_.size());
    for (const auto& tab : tabs_) {
      urls.push_back(tab.tab->CurrentUrl());
    }
    return urls;
  }

  size_t ActiveIndex() const { return active_index_; }

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

  std::uint64_t ActiveTabIdentity() const {
    return tabs_.empty() || active_index_ >= tabs_.size() ? 0 : tabs_[active_index_].identity;
  }

  bool InjectVideoTranslationOnActiveTab(std::uint64_t tab_identity,
                                         const std::string& expected_url,
                                         const std::string& script) {
    Tab* tab = ActiveTab();
    if (tab == nullptr || tabs_[active_index_].identity != tab_identity ||
        tab->CurrentUrl() != expected_url) {
      return false;
    }
    tab->EnableVideoTranslationBridge();
    tab->EvaluateJavaScript(script);
    return true;
  }

  void SetSearchEngine(const std::string& engine_id) {
    if (search_engine_id_ == engine_id) {
      return;
    }
    search_engine_id_ = engine_id;
    for (auto& tab : tabs_) {
      tab.tab->SetSearchEngine(search_engine_id_);
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
    ConfigureTabCallbacks();
  }

  void SetPageColorCallback(PageColorCallback callback) {
    page_color_callback_ = std::move(callback);
    ConfigureTabCallbacks();
    EmitDefaultPageColor();
  }

  void SetTabStateCallback(TabStateCallback callback) {
    tab_state_callback_ = std::move(callback);
    EmitTabState();
  }

  NSView* NativeView() const { return container_view_; }

 private:
  struct ManagedTab {
    std::unique_ptr<Tab> tab;
    std::uint64_t identity = 0;
    std::string top_level_site;
    std::string url;
    std::string title;
    std::string favicon_url;
    BrowsingMode browsing_mode = BrowsingMode::kNormal;
    size_t last_active_sequence = 0;
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

  std::unique_ptr<Tab> CreateTabForTopLevelSite(const std::string& top_level_site) {
    WKWebsiteDataStore* data_store = cookie_manager_.NormalWebsiteDataStore();
    if (browsing_mode_ == BrowsingMode::kSecure) {
      data_store = cookie_manager_.SecureWebsiteDataStore();
    } else if (!top_level_site.empty()) {
      data_store = cookie_manager_.WebsiteDataStoreForTopLevelSite(top_level_site);
    }
    auto tab = std::make_unique<Tab>(data_store, download_manager_);
    tab->SetSearchEngine(search_engine_id_);
    ConfigureTabCallbacks(tab.get());
    return tab;
  }

  void RetargetActiveTabIfNeeded(const std::string& top_level_site) {
    if (active_index_ >= tabs_.size()) {
      return;
    }
    ManagedTab& managed_tab = tabs_[active_index_];
    if (managed_tab.top_level_site == top_level_site &&
        managed_tab.browsing_mode == browsing_mode_) {
      return;
    }

    RemoveTabView(active_index_);
    managed_tab.tab = CreateTabForTopLevelSite(top_level_site);
    managed_tab.top_level_site = top_level_site;
    managed_tab.url.clear();
    managed_tab.title.clear();
    managed_tab.favicon_url.clear();
    managed_tab.browsing_mode = browsing_mode_;
    MountActiveTab();
  }

  void ConfigureTabCallbacks() {
    for (auto& tab : tabs_) {
      ConfigureTabCallbacks(tab.tab.get());
    }
  }

  void ConfigureTabCallbacks(Tab* tab) {
    if (tab == nullptr) {
      return;
    }
    tab->SetNavigationStateCallback([this, tab](bool can_go_back, bool can_go_forward,
                                                const std::string& url,
                                                const std::string& title,
                                                const std::string& favicon_url) {
      HandleNavigationState(tab, can_go_back, can_go_forward, url, title, favicon_url);
    });
    tab->SetPageColorCallback([this, tab](Tab::PageColor color) {
      if (ActiveTab() == tab && page_color_callback_) {
        page_color_callback_(color);
      }
    });
    tab->SetOpenUrlInNewTabCallback([this](const std::string& url) {
      CreateTab();
      LoadUrl(url);
    });
  }

  void MountActiveTab() {
    if (tabs_.empty() || active_index_ >= tabs_.size()) {
      return;
    }
    tabs_[active_index_].last_active_sequence = ++activation_sequence_;

    for (size_t index = 0; index < tabs_.size(); ++index) {
      if (index != active_index_) {
        NSView* existing_view = tabs_[index].tab->LoadedNativeView();
        if (existing_view != nil) {
          [existing_view setHidden:YES];
        }
        continue;
      }
      NSView* tab_view = tabs_[index].tab->NativeView();
      if ([tab_view superview] != container_view_) {
        [container_view_ addSubview:tab_view];
        [NSLayoutConstraint activateConstraints:@[
          [[tab_view leadingAnchor] constraintEqualToAnchor:[container_view_ leadingAnchor]],
          [[tab_view topAnchor] constraintEqualToAnchor:[container_view_ topAnchor]],
          [[tab_view trailingAnchor] constraintEqualToAnchor:[container_view_ trailingAnchor]],
          [[tab_view bottomAnchor] constraintEqualToAnchor:[container_view_ bottomAnchor]],
        ]];
      }
      [tab_view setHidden:index != active_index_];
    }
    TrimLoadedTabs();
  }

  void TrimLoadedTabs() {
    size_t loaded_count = 0;
    for (const auto& tab : tabs_) {
      if (tab.tab->LoadedNativeView() != nil) {
        ++loaded_count;
      }
    }
    while (loaded_count > kLoadedTabSoftLimit) {
      size_t unload_index = tabs_.size();
      size_t oldest_sequence = SIZE_MAX;
      for (size_t index = 0; index < tabs_.size(); ++index) {
        if (index == active_index_ || tabs_[index].tab->LoadedNativeView() == nil) {
          continue;
        }
        if (tabs_[index].tab->ShouldStayLoaded()) {
          continue;
        }
        if (tabs_[index].last_active_sequence < oldest_sequence) {
          oldest_sequence = tabs_[index].last_active_sequence;
          unload_index = index;
        }
      }
      if (unload_index >= tabs_.size()) {
        return;
      }
      tabs_[unload_index].tab->Unload();
      --loaded_count;
    }
  }

  void RemoveTabView(size_t index) {
    if (index >= tabs_.size()) {
      return;
    }
    NSView* tab_view = tabs_[index].tab->LoadedNativeView();
    if (tab_view != nil) {
      [tab_view removeFromSuperview];
    }
  }

  void EmitDefaultPageColor() {
    if (page_color_callback_) {
      page_color_callback_(Tab::PageColor{});
    }
  }

  void EmitTabState() {
    if (tab_state_callback_) {
      std::vector<TabManager::TabState> tab_states;
      tab_states.reserve(tabs_.size());
      for (const auto& tab : tabs_) {
        tab_states.push_back(TabManager::TabState{tab.url, tab.title, tab.favicon_url});
      }
      tab_state_callback_(tab_states, active_index_);
    }
  }

  void EmitActiveManagedNavigationState() {
    if (!navigation_state_callback_ || tabs_.empty() || active_index_ >= tabs_.size()) {
      return;
    }
    const ManagedTab& tab = tabs_[active_index_];
    navigation_state_callback_(false, false, tab.url, tab.title, tab.favicon_url);
  }

  size_t IndexForTab(const Tab* source_tab) const {
    for (size_t index = 0; index < tabs_.size(); ++index) {
      if (tabs_[index].tab.get() == source_tab) {
        return index;
      }
    }
    return tabs_.size();
  }

  void HandleNavigationState(Tab* source_tab, bool can_go_back, bool can_go_forward,
                             const std::string& url, const std::string& title,
                             const std::string& favicon_url) {
    const size_t source_index = IndexForTab(source_tab);
    if (source_index < tabs_.size()) {
      tabs_[source_index].url = url;
      tabs_[source_index].top_level_site = TopLevelSiteFromInput(url, search_engine_id_);
      tabs_[source_index].title = title;
      if (!favicon_url.empty()) {
        tabs_[source_index].favicon_url = favicon_url;
      }
      EmitTabState();
    }
    if (source_index == active_index_ && navigation_state_callback_) {
      navigation_state_callback_(can_go_back, can_go_forward, url, title, favicon_url);
    }
  }

  NavigationStateCallback navigation_state_callback_;
  PageColorCallback page_color_callback_;
  TabStateCallback tab_state_callback_;
  CookieManager& cookie_manager_;
  DownloadManager& download_manager_;
  BrowsingMode browsing_mode_ = BrowsingMode::kNormal;
  std::string search_engine_id_ = "duckduckgo";
  std::vector<ManagedTab> tabs_;
  size_t active_index_ = 0;
  size_t activation_sequence_ = 0;
  std::uint64_t next_tab_identity_ = 1;
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

bool TabManager::RestoreTabs(const std::vector<std::string>& urls, size_t active_index) {
  return impl_->RestoreTabs(urls, active_index);
}

void TabManager::SelectTab(size_t index) {
  impl_->SelectTab(index);
}

void TabManager::CloseTab(size_t index) {
  impl_->CloseTab(index);
}

bool TabManager::LoadUrl(const std::string& text) {
  return impl_->LoadUrl(text);
}

std::string TabManager::CurrentUrl() const {
  return impl_->CurrentUrl();
}

std::string TabManager::UrlForTab(size_t index) const {
  return impl_->UrlForTab(index);
}

std::vector<std::string> TabManager::SessionUrls() const {
  return impl_->SessionUrls();
}

size_t TabManager::ActiveIndex() const {
  return impl_->ActiveIndex();
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

void TabManager::SetSearchEngine(const std::string& engine_id) {
  impl_->SetSearchEngine(engine_id);
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

void TabManager::SetTabStateCallback(TabStateCallback callback) {
  impl_->SetTabStateCallback(std::move(callback));
}

std::uint64_t TabManager::ActiveTabIdentity() const {
  return impl_->ActiveTabIdentity();
}

bool TabManager::InjectVideoTranslationOnActiveTab(std::uint64_t tab_identity,
                                                   const std::string& expected_url,
                                                   const std::string& script) {
  return impl_->InjectVideoTranslationOnActiveTab(tab_identity, expected_url, script);
}

NSView* TabManager::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba
