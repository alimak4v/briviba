#include "briviba/tab.h"

#include "briviba/download_manager.h"

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>

#include <chrono>
#include <cctype>
#include <cstdio>
#include <string>
#include <utility>

@interface BrivibaWebView : WKWebView
@end

@implementation BrivibaWebView

- (NSMenu*)menuForEvent:(NSEvent*)event {
  NSMenu* default_menu = [super menuForEvent:event];
  if (default_menu == nil) {
    return nil;
  }

  BOOL link_menu = NO;
  for (NSMenuItem* item in [default_menu itemArray]) {
    if ([[item title] isEqualToString:@"Open Link"]) {
      link_menu = YES;
      break;
    }
  }
  if (!link_menu) {
    return default_menu;
  }

  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Link"];
  for (NSMenuItem* item in [default_menu itemArray]) {
    NSString* title = [item title];
    BOOL keep = [title isEqualToString:@"Open Link"] ||
                [title isEqualToString:@"Open Link in New Window"] ||
                [title isEqualToString:@"Copy Link"] ||
                [title hasPrefix:@"Share"];
    if (!keep) {
      continue;
    }

    NSMenuItem* copied_item = [item copy];
    if ([title isEqualToString:@"Open Link in New Window"]) {
      [copied_item setTitle:@"Open Link in New Tab"];
    }
    [menu addItem:copied_item];
  }
  return [menu numberOfItems] == 0 ? default_menu : menu;
}

@end

@interface BrivibaNavigationDelegate : NSObject <WKNavigationDelegate, WKUIDelegate> {
 @public
  briviba::Tab* tab;
  briviba::Tab::NavigationStateCallback navigation_state_callback;
  briviba::Tab::PageColorCallback page_color_callback;
  briviba::Tab::OpenUrlInNewTabCallback open_url_in_new_tab_callback;
  briviba::DownloadManager* download_manager;
}
- (void)emitNavigationStateForWebView:(WKWebView*)web_view;
- (void)emitFaviconNavigationStateForWebView:(WKWebView*)web_view;
- (void)emitPageColorForWebView:(WKWebView*)web_view;
@end

@implementation BrivibaNavigationDelegate

- (WKWebView*)webView:(WKWebView*)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration*)configuration
               forNavigationAction:(WKNavigationAction*)navigationAction
                     windowFeatures:(WKWindowFeatures*)windowFeatures {
  (void)webView;
  (void)configuration;
  (void)windowFeatures;
  if (!open_url_in_new_tab_callback) {
    return nil;
  }

  NSURL* url = [[navigationAction request] URL];
  NSString* absolute_string = url == nil ? @"" : [url absoluteString];
  const char* utf8 = [absolute_string UTF8String];
  if (utf8 != nullptr && std::string(utf8).size() > 0) {
    open_url_in_new_tab_callback(std::string(utf8));
  }
  return nil;
}

- (void)webView:(WKWebView*)webView didCommitNavigation:(WKNavigation*)navigation {
  (void)navigation;
  if (tab != nullptr) {
    tab->ResetPageActivity();
    tab->ResetVideoTranslationBridge();
  }
  [self emitNavigationStateForWebView:webView];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
  (void)navigation;
  if (tab != nullptr) {
    tab->ResetPageActivity();
  }
  [self emitNavigationStateForWebView:webView];
  [self emitFaviconNavigationStateForWebView:webView];
  [self emitPageColorForWebView:webView];
}

- (void)webView:(WKWebView*)webView
    navigationAction:(WKNavigationAction*)navigationAction
    didBecomeDownload:(WKDownload*)download {
  (void)webView;
  (void)navigationAction;
  if (download_manager != nullptr) {
    download_manager->ManageDownload(download);
  }
}

- (void)webView:(WKWebView*)webView
    navigationResponse:(WKNavigationResponse*)navigationResponse
     didBecomeDownload:(WKDownload*)download {
  (void)webView;
  (void)navigationResponse;
  if (download_manager != nullptr) {
    download_manager->ManageDownload(download);
  }
}

- (void)emitNavigationStateForWebView:(WKWebView*)web_view {
  if (!navigation_state_callback) {
    return;
  }

  NSURL* url = [web_view URL];
  NSString* absolute_string = url == nil ? @"" : [url absoluteString];
  NSString* title = [web_view title] == nil ? @"" : [web_view title];
  const char* utf8 = [absolute_string UTF8String];
  const char* title_utf8 = [title UTF8String];
  navigation_state_callback([web_view canGoBack], [web_view canGoForward],
                            utf8 == nullptr ? std::string() : std::string(utf8),
                            title_utf8 == nullptr ? std::string() : std::string(title_utf8),
                            std::string());
}

- (void)emitFaviconNavigationStateForWebView:(WKWebView*)web_view {
  if (!navigation_state_callback) {
    return;
  }

  NSString* script =
      @"(() => {"
       "const links = Array.from(document.querySelectorAll('link[rel]'));"
       "const icon = links.find((link) => /(^|\\s)(icon|shortcut icon|apple-touch-icon)(\\s|$)/i"
       ".test(link.rel) && link.href);"
       "return icon ? new URL(icon.href, location.href).href : '';"
       "})()";
  [web_view evaluateJavaScript:script
             completionHandler:^(id result, NSError* error) {
               if (error != nil || ![result isKindOfClass:[NSString class]]) {
                 return;
               }

               NSURL* url = [web_view URL];
               NSString* absolute_string = url == nil ? @"" : [url absoluteString];
               NSString* title = [web_view title] == nil ? @"" : [web_view title];
               NSString* favicon_url = (NSString*)result;
               const char* utf8 = [absolute_string UTF8String];
               const char* title_utf8 = [title UTF8String];
               const char* favicon_utf8 = [favicon_url UTF8String];
               navigation_state_callback(
                   [web_view canGoBack], [web_view canGoForward],
                   utf8 == nullptr ? std::string() : std::string(utf8),
                   title_utf8 == nullptr ? std::string() : std::string(title_utf8),
                   favicon_utf8 == nullptr ? std::string() : std::string(favicon_utf8));
             }];
}

- (void)emitPageColorForWebView:(WKWebView*)web_view {
  if (!page_color_callback) {
    return;
  }

  NSString* script =
      @"(() => {"
       "const target = document.body || document.documentElement;"
       "const style = window.getComputedStyle(target);"
       "return style.backgroundColor || 'rgb(255, 255, 255)';"
       "})()";
  [web_view evaluateJavaScript:script
             completionHandler:^(id result, NSError* error) {
               if (error != nil || ![result isKindOfClass:[NSString class]]) {
                 return;
               }

               NSString* color_string = (NSString*)result;
               const char* utf8 = [color_string UTF8String];
               if (utf8 == nullptr) {
                 return;
               }

               int red = 255;
               int green = 255;
               int blue = 255;
               double alpha = 1.0;
               const int rgba_count =
                   std::sscanf(utf8, "rgba(%d, %d, %d, %lf)", &red, &green, &blue, &alpha);
               const int rgb_count = std::sscanf(utf8, "rgb(%d, %d, %d)", &red, &green, &blue);
               if (rgba_count < 3 && rgb_count != 3) {
                 return;
               }

               briviba::Tab::PageColor color;
               color.red = static_cast<double>(red) / 255.0;
               color.green = static_cast<double>(green) / 255.0;
               color.blue = static_cast<double>(blue) / 255.0;
               color.alpha = alpha;
               page_color_callback(color);
             }];
}

@end

@interface BrivibaActivityHandler : NSObject <WKScriptMessageHandler> {
 @public
  briviba::Tab* tab;
}
@end

@implementation BrivibaActivityHandler

- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
  (void)userContentController;
  (void)message;
  if (tab != nullptr) {
    tab->MarkPageActivity();
  }
}

@end

static BOOL BrivibaHostMatches(NSString* host, NSString* allowed_host) {
  if ([host isEqualToString:allowed_host]) {
    return YES;
  }
  return [host hasSuffix:[@"." stringByAppendingString:allowed_host]];
}

static NSString* BrivibaVideoTranslationRelaySource() {
  NSURL* resource_url = [[NSBundle mainBundle] URLForResource:@"video_translation_relay"
                                               withExtension:@"js"];
  if (resource_url == nil) {
    return nil;
  }
  NSError* error = nil;
  NSString* source = [NSString stringWithContentsOfURL:resource_url
                                              encoding:NSUTF8StringEncoding
                                                 error:&error];
  return error == nil ? source : nil;
}

static BOOL BrivibaIsAllowedVideoTranslationSource(NSURL* url) {
  NSString* host = [[url host] lowercaseString];
  if (host == nil) {
    return NO;
  }
  for (NSString* allowed_host in @[
         @"youtube.com", @"youtu.be", @"vimeo.com", @"vk.com", @"vkvideo.ru", @"dzen.ru",
         @"rutube.ru", @"ok.ru", @"coursera.org"
       ]) {
    if (BrivibaHostMatches(host, allowed_host)) {
      return YES;
    }
  }
  return NO;
}

static BOOL BrivibaIsAllowedVideoTranslationDestination(NSURL* url) {
  if (![[[url scheme] lowercaseString] isEqualToString:@"https"]) {
    return NO;
  }
  NSString* host = [[url host] lowercaseString];
  if (host == nil) {
    return NO;
  }
  for (NSString* allowed_host in
       @[ @"yandex.ru", @"yandex.net", @"googlevideo.com", @"youtube.com", @"vimeo.com" ]) {
    if (BrivibaHostMatches(host, allowed_host)) {
      return YES;
    }
  }
  return [@[
    @"vot.toil.cc", @"vot-worker.toil.cc", @"media-proxy.toil.cc", @"t2mc.toil.cc",
    @"raw.githubusercontent.com", @"cloudflare-dns.com", @"rust-server-531j.onrender.com",
    @"vot-worker.kload.workers.dev", @"translate-backend.transly.workers.dev"
  ] containsObject:host];
}

static constexpr NSUInteger kVideoTranslationMaxConcurrentRequests = 8;
static constexpr NSUInteger kVideoTranslationMaxRequestBytes = 32 * 1024 * 1024;
static constexpr NSUInteger kVideoTranslationMaxResponseBytes = 64 * 1024 * 1024;
static constexpr NSUInteger kVideoTranslationMaxRequestIdLength = 64;
static constexpr NSTimeInterval kVideoTranslationNoTimeoutInterval = 7 * 24 * 60 * 60;

@interface BrivibaVideoTranslationHandler
    : NSObject <WKScriptMessageHandler, NSURLSessionDataDelegate, NSURLSessionTaskDelegate> {
 @public
  __weak WKWebView* web_view;
  WKContentWorld* content_world;
  NSString* pending_page_script;
  BOOL relay_ready;
  NSURLSession* session;
  NSMutableDictionary<NSString*, NSURLSessionDataTask*>* tasks;
  NSMutableDictionary<NSNumber*, NSString*>* request_ids;
  NSMutableDictionary<NSNumber*, NSMutableData*>* response_bodies;
  NSMutableDictionary<NSNumber*, NSHTTPURLResponse*>* responses;
  NSMutableDictionary<NSNumber*, NSString*>* failure_messages;
}
- (void)sendPayload:(NSDictionary*)payload;
- (void)invalidate;
@end

@implementation BrivibaVideoTranslationHandler

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    tasks = [[NSMutableDictionary alloc] init];
    request_ids = [[NSMutableDictionary alloc] init];
    response_bodies = [[NSMutableDictionary alloc] init];
    responses = [[NSMutableDictionary alloc] init];
    failure_messages = [[NSMutableDictionary alloc] init];
    NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    [configuration setHTTPShouldSetCookies:NO];
    [configuration setHTTPCookieStorage:nil];
    [configuration setURLCredentialStorage:nil];
    [configuration setURLCache:nil];
    [configuration setRequestCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [configuration setHTTPMaximumConnectionsPerHost:kVideoTranslationMaxConcurrentRequests];
    session = [NSURLSession sessionWithConfiguration:configuration
                                            delegate:self
                                       delegateQueue:[NSOperationQueue mainQueue]];
  }
  return self;
}

- (void)sendPayload:(NSDictionary*)payload {
  WKWebView* current_web_view = web_view;
  if (current_web_view == nil || content_world == nil ||
      ![NSJSONSerialization isValidJSONObject:payload]) {
    return;
  }
  NSData* json_data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  NSString* json = [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding];
  if (json == nil) {
    return;
  }
  NSString* script = [NSString
      stringWithFormat:@"window.__brivibaVideoTranslationBridgeDidComplete(%@);", json];
  if (@available(macOS 11.0, *)) {
    [current_web_view evaluateJavaScript:script
                                 inFrame:nil
                          inContentWorld:content_world
                       completionHandler:nil];
  }
}

- (void)invalidate {
  for (NSURLSessionDataTask* task in [tasks allValues]) {
    [task cancel];
  }
  [tasks removeAllObjects];
  [request_ids removeAllObjects];
  [response_bodies removeAllObjects];
  [responses removeAllObjects];
  [failure_messages removeAllObjects];
  [session invalidateAndCancel];
  session = nil;
  pending_page_script = nil;
  relay_ready = NO;
  content_world = nil;
  web_view = nil;
}

- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
  (void)userContentController;
  if (![[message body] isKindOfClass:[NSDictionary class]] || ![[message frameInfo] isMainFrame] ||
      !BrivibaIsAllowedVideoTranslationSource([web_view URL])) {
    return;
  }

  NSDictionary* body = (NSDictionary*)[message body];
  NSString* request_id = [body[@"id"] isKindOfClass:[NSString class]] ? body[@"id"] : nil;
  NSString* action = [body[@"action"] isKindOfClass:[NSString class]] ? body[@"action"] : nil;
  if (request_id == nil || [request_id length] == 0 ||
      [request_id length] > kVideoTranslationMaxRequestIdLength || action == nil) {
    return;
  }
  if ([action isEqualToString:@"abort"]) {
    NSURLSessionDataTask* task = tasks[request_id];
    [tasks removeObjectForKey:request_id];
    if (task != nil) {
      NSNumber* task_key = @([task taskIdentifier]);
      [request_ids removeObjectForKey:task_key];
      [response_bodies removeObjectForKey:task_key];
      [responses removeObjectForKey:task_key];
      [failure_messages removeObjectForKey:task_key];
      [task cancel];
    }
    return;
  }
  if (![action isEqualToString:@"request"]) {
    return;
  }
  if (tasks[request_id] != nil) {
    return;
  }
  if ([tasks count] >= kVideoTranslationMaxConcurrentRequests) {
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : @"network",
      @"message" : @"Too many concurrent video translation requests"
    }];
    return;
  }

  NSString* url_text = [body[@"url"] isKindOfClass:[NSString class]] ? body[@"url"] : nil;
  if ([url_text length] == 0 || [url_text length] > 4096) {
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : @"network",
      @"message" : @"Video translation request URL is invalid or too long"
    }];
    return;
  }
  NSURL* url = url_text == nil ? nil : [NSURL URLWithString:url_text];
  if (url == nil || !BrivibaIsAllowedVideoTranslationDestination(url)) {
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : @"network",
      @"message" : @"Video translation request URL is not allowed"
    }];
    return;
  }

  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
  NSString* method = [body[@"method"] isKindOfClass:[NSString class]] ? body[@"method"] : @"GET";
  method = [method uppercaseString];
  if (![@[ @"GET", @"HEAD", @"POST", @"PUT", @"DELETE" ] containsObject:method]) {
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : @"network",
      @"message" : @"Video translation request method is not allowed"
    }];
    return;
  }
  [request setHTTPMethod:method];
  NSNumber* timeout = [body[@"timeout"] isKindOfClass:[NSNumber class]] ? body[@"timeout"] : nil;
  if (timeout != nil) {
    const double timeout_milliseconds = MAX([timeout doubleValue], 0.0);
    [request setTimeoutInterval:timeout_milliseconds == 0.0
                                    ? kVideoTranslationNoTimeoutInterval
                                    : MIN(timeout_milliseconds / 1000.0, 300.0)];
  }

  NSDictionary* headers = [body[@"headers"] isKindOfClass:[NSDictionary class]] ? body[@"headers"] : nil;
  if ([headers count] > 64) {
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : @"network",
      @"message" : @"Video translation request has too many headers"
    }];
    return;
  }
  for (id header_object in headers) {
    if (![header_object isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString* header = (NSString*)header_object;
    id value = headers[header];
    NSString* lowercase_header = [header lowercaseString];
    if (![value isKindOfClass:[NSString class]] || [header length] > 256 || [value length] > 8192 ||
        [lowercase_header isEqualToString:@"host"] ||
        [lowercase_header isEqualToString:@"content-length"] ||
        [lowercase_header isEqualToString:@"cookie"]) {
      continue;
    }
    [request setValue:(NSString*)value forHTTPHeaderField:header];
  }

  NSString* request_body = [body[@"body"] isKindOfClass:[NSString class]] ? body[@"body"] : @"";
  NSString* body_encoding =
      [body[@"bodyEncoding"] isKindOfClass:[NSString class]] ? body[@"bodyEncoding"] : @"none";
  NSData* http_body = nil;
  if ([body_encoding isEqualToString:@"base64"]) {
    if ([request_body length] > (kVideoTranslationMaxRequestBytes * 4 / 3) + 4) {
      http_body = nil;
    } else {
      http_body = [[NSData alloc] initWithBase64EncodedString:request_body options:0];
    }
  } else if ([body_encoding isEqualToString:@"utf8"]) {
    http_body = [request_body dataUsingEncoding:NSUTF8StringEncoding];
  } else if (![body_encoding isEqualToString:@"none"]) {
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : @"network",
      @"message" : @"Video translation request body encoding is not supported"
    }];
    return;
  }
  if ([http_body length] > kVideoTranslationMaxRequestBytes ||
      ([body_encoding isEqualToString:@"base64"] && [request_body length] > 0 && http_body == nil)) {
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : @"network",
      @"message" : @"Video translation request body is invalid or too large"
    }];
    return;
  }
  [request setHTTPBody:http_body];

  NSURLSessionDataTask* task = [session dataTaskWithRequest:request];
  tasks[request_id] = task;
  NSNumber* task_key = @([task taskIdentifier]);
  request_ids[task_key] = request_id;
  response_bodies[task_key] = [NSMutableData data];
  [task resume];
}

- (void)URLSession:(NSURLSession*)url_session
                  task:(NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest* request))completion_handler {
  (void)url_session;
  (void)response;
  if (BrivibaIsAllowedVideoTranslationDestination([request URL])) {
    completion_handler(request);
    return;
  }
  failure_messages[@([task taskIdentifier])] = @"Video translation redirect URL is not allowed";
  completion_handler(nil);
}

- (void)URLSession:(NSURLSession*)url_session
              dataTask:(NSURLSessionDataTask*)data_task
    didReceiveResponse:(NSURLResponse*)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completion_handler {
  (void)url_session;
  NSNumber* task_key = @([data_task taskIdentifier]);
  const bool response_has_body =
      ![[[[data_task originalRequest] HTTPMethod] uppercaseString] isEqualToString:@"HEAD"];
  if (response_has_body &&
      [response expectedContentLength] > static_cast<int64_t>(kVideoTranslationMaxResponseBytes)) {
    failure_messages[task_key] = @"Video translation response is too large";
    completion_handler(NSURLSessionResponseCancel);
    return;
  }
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    responses[task_key] = (NSHTTPURLResponse*)response;
  }
  completion_handler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)url_session
          dataTask:(NSURLSessionDataTask*)data_task
    didReceiveData:(NSData*)data {
  (void)url_session;
  NSNumber* task_key = @([data_task taskIdentifier]);
  NSMutableData* response_body = response_bodies[task_key];
  if (response_body == nil || failure_messages[task_key] != nil) {
    return;
  }
  if ([response_body length] + [data length] > kVideoTranslationMaxResponseBytes) {
    failure_messages[task_key] = @"Video translation response is too large";
    [data_task cancel];
    return;
  }
  [response_body appendData:data];
}

- (void)URLSession:(NSURLSession*)url_session
              task:(NSURLSessionTask*)task
    didCompleteWithError:(NSError*)error {
  (void)url_session;
  NSNumber* task_key = @([task taskIdentifier]);
  NSString* request_id = request_ids[task_key];
  if (request_id == nil || tasks[request_id] != task) {
    return;
  }
  NSHTTPURLResponse* response = responses[task_key];
  NSData* response_body = response_bodies[task_key] == nil ? [NSData data] : response_bodies[task_key];
  NSString* failure_message = failure_messages[task_key];
  [tasks removeObjectForKey:request_id];
  [request_ids removeObjectForKey:task_key];
  [response_bodies removeObjectForKey:task_key];
  [responses removeObjectForKey:task_key];
  [failure_messages removeObjectForKey:task_key];

  if (failure_message != nil || error != nil) {
    NSString* error_kind = [error code] == NSURLErrorTimedOut ? @"timeout" : @"network";
    NSString* error_message = failure_message == nil ? [error localizedDescription] : failure_message;
    [self sendPayload:@{
      @"id" : request_id,
      @"error" : error_kind,
      @"message" : error_message == nil ? @"Network request failed" : error_message
    }];
    return;
  }

  NSMutableArray<NSString*>* response_header_lines = [NSMutableArray array];
  for (id key in [response allHeaderFields]) {
    [response_header_lines
        addObject:[NSString stringWithFormat:@"%@: %@", key, [response allHeaderFields][key]]];
  }
  NSString* final_url = [[[task currentRequest] URL] absoluteString];
  NSInteger status = [response statusCode];
  NSString* status_text = [NSHTTPURLResponse localizedStringForStatusCode:status];
  [self sendPayload:@{
    @"id" : request_id,
    @"status" : @(status),
    @"statusText" : status_text == nil ? @"" : status_text,
    @"finalUrl" : final_url == nil ? @"" : final_url,
    @"responseHeaders" : [response_header_lines componentsJoinedByString:@"\n"],
    @"body" : [response_body base64EncodedStringWithOptions:0]
  }];
}

@end

namespace briviba {
namespace {

constexpr std::chrono::seconds kRecentActivityWindow(180);

std::string TrimAsciiWhitespace(const std::string& text) {
  size_t begin = 0;
  while (begin < text.size() && std::isspace(static_cast<unsigned char>(text[begin])) != 0) {
    ++begin;
  }

  size_t end = text.size();
  while (end > begin && std::isspace(static_cast<unsigned char>(text[end - 1])) != 0) {
    --end;
  }

  return text.substr(begin, end - begin);
}

bool HasUrlScheme(const std::string& text) {
  for (const char character : text) {
    if (character == ':') {
      return true;
    }
    if (!std::isalpha(static_cast<unsigned char>(character)) &&
        !std::isdigit(static_cast<unsigned char>(character)) && character != '+' &&
        character != '-' && character != '.') {
      return false;
    }
  }
  return false;
}

bool LooksLikeSearchQuery(const std::string& text) {
  for (const char character : text) {
    if (std::isspace(static_cast<unsigned char>(character)) != 0) {
      return true;
    }
  }
  return text.find('.') == std::string::npos && !HasUrlScheme(text);
}

NSString* SearchUrlFormat(const std::string& engine_id) {
  if (engine_id == "google") {
    return @"https://www.google.com/search?q=%@";
  }
  if (engine_id == "bing") {
    return @"https://www.bing.com/search?q=%@";
  }
  if (engine_id == "yandex") {
    return @"https://yandex.ru/search/?text=%@";
  }
  return @"https://duckduckgo.com/?q=%@";
}

std::string UrlTextFromInput(const std::string& input, const std::string& search_engine_id) {
  if (!LooksLikeSearchQuery(input)) {
    return HasUrlScheme(input) ? input : "https://" + input;
  }

  NSString* query = [NSString stringWithUTF8String:input.c_str()];
  NSString* encoded_query =
      [query stringByAddingPercentEncodingWithAllowedCharacters:
                 [NSCharacterSet URLQueryAllowedCharacterSet]];
  NSString* url = [NSString stringWithFormat:SearchUrlFormat(search_engine_id), encoded_query];
  const char* utf8 = [url UTF8String];
  return utf8 == nullptr ? std::string("https://duckduckgo.com") : std::string(utf8);
}

NSString* SafariLikeUserAgent() {
  return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "KHTML, like Gecko) Version/18.0 Safari/605.1.15";
}

void ConfigureWebView(WKWebViewConfiguration* configuration) {
  if (@available(macOS 12.3, *)) {
    [[configuration preferences] setElementFullscreenEnabled:YES];
  }
  [configuration setMediaTypesRequiringUserActionForPlayback:WKAudiovisualMediaTypeNone];
  SEL pip_selector = NSSelectorFromString(@"setAllowsPictureInPictureMediaPlayback:");
  if ([configuration respondsToSelector:pip_selector]) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, pip_selector, YES);
  }
}

double MonotonicSeconds() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

NSString* PageActivityScriptSource() {
  return
      @"(() => {"
       "if (window.__brivibaActivityInstalled) return;"
       "window.__brivibaActivityInstalled = true;"
       "let lastPost = 0;"
       "let mutationCount = 0;"
       "let animationFrameCount = 0;"
       "const post = (kind) => {"
       "  const now = Date.now();"
       "  if (now - lastPost < 2000) return;"
       "  lastPost = now;"
       "  try { window.webkit.messageHandlers.brivibaActivity.postMessage(kind); } catch (_) {}"
       "};"
       "const mediaActive = () => {"
       "  try {"
       "    return Array.from(document.querySelectorAll('audio,video')).some((element) =>"
       "      !element.paused && !element.ended && element.readyState > 1);"
       "  } catch (_) { return false; }"
       "};"
       "document.addEventListener('play', () => post('media'), true);"
       "document.addEventListener('playing', () => post('media'), true);"
       "document.addEventListener('timeupdate', () => { if (mediaActive()) post('media'); }, true);"
       "setInterval(() => { if (mediaActive()) post('media'); }, 5000);"
       "try {"
       "  const observer = new MutationObserver((mutations) => { mutationCount += mutations.length; });"
       "  const startObserver = () => observer.observe(document.documentElement || document, {"
       "    childList: true, subtree: true, characterData: true, attributes: true"
       "  });"
       "  if (document.documentElement) startObserver();"
       "  else document.addEventListener('DOMContentLoaded', startObserver, { once: true });"
       "  setInterval(() => {"
       "    if (mutationCount >= 80) post('page-update');"
       "    mutationCount = 0;"
       "  }, 5000);"
       "} catch (_) {}"
       "try {"
       "  const nativeRequestAnimationFrame = window.requestAnimationFrame;"
       "  if (nativeRequestAnimationFrame && !nativeRequestAnimationFrame.__brivibaWrapped) {"
       "    const wrappedRequestAnimationFrame = function(callback) {"
       "      animationFrameCount += 1;"
       "      return nativeRequestAnimationFrame.call(window, callback);"
       "    };"
       "    wrappedRequestAnimationFrame.__brivibaWrapped = true;"
       "    window.requestAnimationFrame = wrappedRequestAnimationFrame;"
       "    setInterval(() => {"
       "      if (animationFrameCount >= 90 && document.querySelector('canvas')) post('animation');"
       "      animationFrameCount = 0;"
       "    }, 5000);"
       "  }"
       "} catch (_) {}"
       "try {"
       "  const NativeWebSocket = window.WebSocket;"
       "  if (NativeWebSocket && !NativeWebSocket.__brivibaWrapped) {"
       "    const WrappedWebSocket = function(...args) {"
       "      const socket = new NativeWebSocket(...args);"
       "      socket.addEventListener('message', () => post('websocket'));"
       "      return socket;"
       "    };"
       "    Object.setPrototypeOf(WrappedWebSocket, NativeWebSocket);"
       "    WrappedWebSocket.prototype = NativeWebSocket.prototype;"
       "    WrappedWebSocket.__brivibaWrapped = true;"
       "    window.WebSocket = WrappedWebSocket;"
       "  }"
       "} catch (_) {}"
       "})();";
}

}  // namespace

class Tab::Impl {
 public:
  Impl(Tab* owner, WKWebsiteDataStore* website_data_store, DownloadManager& download_manager)
      : owner_(owner), website_data_store_(website_data_store), download_manager_(download_manager) {}

  ~Impl() {
    DetachVideoTranslationHandler();
    DetachActivityHandler();
  }

  bool LoadUrl(const std::string& text) {
    EnsureLoaded();
    std::string trimmed = TrimAsciiWhitespace(text);
    if (trimmed.empty()) {
      return false;
    }

    const std::string url_text = UrlTextFromInput(trimmed, search_engine_id_);
    NSString* url_string = [NSString stringWithUTF8String:url_text.c_str()];
    NSURL* url = [NSURL URLWithString:url_string];
    if (url == nil || [url scheme] == nil) {
      return false;
    }

    current_url_ = url_text;
    if ([url isFileURL]) {
      NSURL* read_access_url = [url URLByDeletingLastPathComponent];
      [web_view_ loadFileURL:url allowingReadAccessToURL:read_access_url];
      EmitNavigationState();
      return true;
    }
    [web_view_ loadRequest:[NSURLRequest requestWithURL:url]];
    EmitNavigationState();
    return true;
  }

  void SetRestoredUrl(const std::string& url) {
    current_url_ = url;
    if (web_view_ != nil && !current_url_.empty()) {
      NSString* url_string = [NSString stringWithUTF8String:current_url_.c_str()];
      NSURL* ns_url = [NSURL URLWithString:url_string];
      if (ns_url != nil) {
        [web_view_ loadRequest:[NSURLRequest requestWithURL:ns_url]];
      }
    }
  }

  std::string CurrentUrl() const {
    if (web_view_ == nil) {
      return current_url_;
    }
    NSURL* url = [web_view_ URL];
    NSString* absolute_string = url == nil ? @"" : [url absoluteString];
    const char* utf8 = [absolute_string UTF8String];
    return utf8 == nullptr ? std::string() : std::string(utf8);
  }

  bool ShouldStayLoaded() const {
    if (web_view_ == nil) {
      return false;
    }
    if ([web_view_ isLoading]) {
      return true;
    }
    return MonotonicSeconds() - last_page_activity_seconds_ <= kRecentActivityWindow.count();
  }

  void MarkPageActivity() { last_page_activity_seconds_ = MonotonicSeconds(); }

  void ResetPageActivity() { last_page_activity_seconds_ = 0.0; }

  void ResetVideoTranslationBridge() { DetachVideoTranslationHandler(); }

  void Unload() {
    current_url_ = CurrentUrl();
    [web_view_ setNavigationDelegate:nil];
    [web_view_ setUIDelegate:nil];
    if (navigation_delegate_ != nil) {
      navigation_delegate_->tab = nullptr;
    }
    DetachVideoTranslationHandler();
    DetachActivityHandler();
    [web_view_ removeFromSuperview];
    navigation_delegate_ = nil;
    web_view_ = nil;
  }

  void ExitFullscreen() {
    if (web_view_ == nil) {
      return;
    }

    NSString* script =
        @"(() => {"
         "try {"
         "  const doc = document;"
         "  const exitDocFullscreen = doc.exitFullscreen || doc.webkitExitFullscreen;"
         "  if (doc.fullscreenElement && exitDocFullscreen) exitDocFullscreen.call(doc);"
         "  if (doc.webkitFullscreenElement && exitDocFullscreen) exitDocFullscreen.call(doc);"
         "  for (const video of Array.from(doc.querySelectorAll('video'))) {"
         "    try {"
         "      if (video.webkitPresentationMode === 'fullscreen' && video.webkitExitFullscreen) {"
         "        video.webkitExitFullscreen();"
         "      }"
         "      if (video.webkitDisplayingFullscreen && video.webkitExitFullscreen) {"
         "        video.webkitExitFullscreen();"
         "      }"
         "    } catch (_) {}"
         "  }"
         "} catch (_) {}"
         "})();";
    [web_view_ evaluateJavaScript:script completionHandler:nil];
  }

  void GoBack() {
    EnsureLoaded();
    if ([web_view_ canGoBack]) {
      [web_view_ goBack];
    }
    EmitNavigationState();
  }

  void GoForward() {
    EnsureLoaded();
    if ([web_view_ canGoForward]) {
      [web_view_ goForward];
    }
    EmitNavigationState();
  }

  void Reload() {
    EnsureLoaded();
    [web_view_ reload];
    EmitNavigationState();
  }

  void EvaluateJavaScript(const std::string& script) {
    EnsureLoaded();
    if (web_view_ == nil || script.empty()) {
      return;
    }

    NSString* script_string = [NSString stringWithUTF8String:script.c_str()];
    if (script_string == nil) {
      return;
    }
    if (video_translation_handler_ == nil || video_translation_handler_->content_world == nil) {
      return;
    }
    if (@available(macOS 11.0, *)) {
      if (!video_translation_handler_->relay_ready) {
        video_translation_handler_->pending_page_script = script_string;
        return;
      }
      [web_view_ evaluateJavaScript:script_string
                           inFrame:nil
                    inContentWorld:[WKContentWorld pageWorld]
                 completionHandler:nil];
    }
  }

  void EnableVideoTranslationBridge() {
    EnsureLoaded();
    if (web_view_ == nil || video_translation_handler_ != nil) {
      return;
    }
    NSString* relay_source = BrivibaVideoTranslationRelaySource();
    if (relay_source == nil) {
      return;
    }
    video_translation_handler_ = [[BrivibaVideoTranslationHandler alloc] init];
    video_translation_handler_->web_view = web_view_;
    if (@available(macOS 11.0, *)) {
      video_translation_handler_->content_world =
          [WKContentWorld worldWithName:@"app.briviba.video-translation-relay"];
      [[web_view_ configuration].userContentController
          addScriptMessageHandler:video_translation_handler_
                     contentWorld:video_translation_handler_->content_world
                             name:@"brivibaVideoTranslation"];
      __weak BrivibaVideoTranslationHandler* weak_handler = video_translation_handler_;
      [web_view_ evaluateJavaScript:relay_source
                           inFrame:nil
                    inContentWorld:video_translation_handler_->content_world
                 completionHandler:^(id result, NSError* error) {
                   (void)result;
                   BrivibaVideoTranslationHandler* handler = weak_handler;
                   if (handler == nil || error != nil) {
                     return;
                   }
                   WKWebView* current_web_view = handler->web_view;
                   if (current_web_view == nil) {
                     return;
                   }
                   handler->relay_ready = YES;
                   NSString* pending_script = handler->pending_page_script;
                   handler->pending_page_script = nil;
                   if (pending_script != nil) {
                     [current_web_view evaluateJavaScript:pending_script
                                                  inFrame:nil
                                           inContentWorld:[WKContentWorld pageWorld]
                                        completionHandler:nil];
                   }
                 }];
    }
  }

  void SetSearchEngine(const std::string& engine_id) { search_engine_id_ = engine_id; }

  void SetNavigationStateCallback(NavigationStateCallback callback) {
    navigation_state_callback_ = std::move(callback);
    if (navigation_delegate_ != nil) {
      navigation_delegate_->navigation_state_callback = navigation_state_callback_;
    }
    EmitNavigationState();
  }

  void SetPageColorCallback(PageColorCallback callback) {
    page_color_callback_ = std::move(callback);
    if (navigation_delegate_ != nil) {
      navigation_delegate_->page_color_callback = page_color_callback_;
    }
  }

  void SetOpenUrlInNewTabCallback(OpenUrlInNewTabCallback callback) {
    open_url_in_new_tab_callback_ = std::move(callback);
    if (navigation_delegate_ != nil) {
      navigation_delegate_->open_url_in_new_tab_callback = open_url_in_new_tab_callback_;
    }
  }

  NSView* NativeView() {
    EnsureLoaded();
    return web_view_;
  }

  NSView* LoadedNativeView() const { return web_view_; }

 private:
  void EnsureLoaded() {
    if (web_view_ != nil) {
      return;
    }

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    ConfigureWebView(configuration);
    WKUserContentController* user_content_controller = [[WKUserContentController alloc] init];
    WKUserScript* activity_script =
        [[WKUserScript alloc] initWithSource:PageActivityScriptSource()
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
    [user_content_controller addUserScript:activity_script];
    activity_handler_ = [[BrivibaActivityHandler alloc] init];
    activity_handler_->tab = owner_;
    [user_content_controller addScriptMessageHandler:activity_handler_ name:@"brivibaActivity"];
    [configuration setUserContentController:user_content_controller];
    if (website_data_store_ != nil) {
      [configuration setWebsiteDataStore:website_data_store_];
    }
    web_view_ = [[BrivibaWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    [web_view_ setCustomUserAgent:SafariLikeUserAgent()];
    navigation_delegate_ = [[BrivibaNavigationDelegate alloc] init];
    navigation_delegate_->tab = owner_;
    navigation_delegate_->download_manager = &download_manager_;
    navigation_delegate_->navigation_state_callback = navigation_state_callback_;
    navigation_delegate_->page_color_callback = page_color_callback_;
    navigation_delegate_->open_url_in_new_tab_callback = open_url_in_new_tab_callback_;
    [web_view_ setNavigationDelegate:navigation_delegate_];
    [web_view_ setUIDelegate:navigation_delegate_];
    [web_view_ setAllowsBackForwardNavigationGestures:YES];
    [web_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    if (!current_url_.empty()) {
      NSString* url_string = [NSString stringWithUTF8String:current_url_.c_str()];
      NSURL* url = [NSURL URLWithString:url_string];
      if (url != nil) {
        if ([url isFileURL]) {
          [web_view_ loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
        } else {
          [web_view_ loadRequest:[NSURLRequest requestWithURL:url]];
        }
      }
    }
  }

  void EmitNavigationState() {
    if (navigation_delegate_ != nil && web_view_ != nil) {
      [navigation_delegate_ emitNavigationStateForWebView:web_view_];
    }
  }

  void DetachActivityHandler() {
    if (web_view_ != nil && activity_handler_ != nil) {
      [[web_view_ configuration].userContentController removeScriptMessageHandlerForName:@"brivibaActivity"];
      activity_handler_->tab = nullptr;
      activity_handler_ = nil;
    }
  }

  void DetachVideoTranslationHandler() {
    if (web_view_ != nil && video_translation_handler_ != nil) {
      if (@available(macOS 11.0, *)) {
        [[web_view_ configuration].userContentController
            removeScriptMessageHandlerForName:@"brivibaVideoTranslation"
                                  contentWorld:video_translation_handler_->content_world];
      }
      [video_translation_handler_ invalidate];
      video_translation_handler_ = nil;
    }
  }

  Tab* owner_;
  WKWebsiteDataStore* website_data_store_ = nil;
  DownloadManager& download_manager_;
  NavigationStateCallback navigation_state_callback_;
  PageColorCallback page_color_callback_;
  OpenUrlInNewTabCallback open_url_in_new_tab_callback_;
  std::string search_engine_id_ = "duckduckgo";
  std::string current_url_;
  BrivibaNavigationDelegate* navigation_delegate_ = nil;
  BrivibaActivityHandler* activity_handler_ = nil;
  BrivibaVideoTranslationHandler* video_translation_handler_ = nil;
  WKWebView* web_view_ = nil;
  double last_page_activity_seconds_ = 0.0;
};

Tab::Tab(WKWebsiteDataStore* website_data_store, DownloadManager& download_manager)
    : impl_(std::make_unique<Impl>(this, website_data_store, download_manager)) {}

Tab::~Tab() = default;

bool Tab::LoadUrl(const std::string& text) {
  return impl_->LoadUrl(text);
}

void Tab::SetRestoredUrl(const std::string& url) {
  impl_->SetRestoredUrl(url);
}

std::string Tab::CurrentUrl() const {
  return impl_->CurrentUrl();
}

bool Tab::ShouldStayLoaded() const {
  return impl_->ShouldStayLoaded();
}

void Tab::MarkPageActivity() {
  impl_->MarkPageActivity();
}

void Tab::ResetPageActivity() {
  impl_->ResetPageActivity();
}

void Tab::ResetVideoTranslationBridge() {
  impl_->ResetVideoTranslationBridge();
}

void Tab::Unload() {
  impl_->Unload();
}

void Tab::ExitFullscreen() {
  impl_->ExitFullscreen();
}

void Tab::GoBack() {
  impl_->GoBack();
}

void Tab::GoForward() {
  impl_->GoForward();
}

void Tab::Reload() {
  impl_->Reload();
}

void Tab::EvaluateJavaScript(const std::string& script) {
  impl_->EvaluateJavaScript(script);
}

void Tab::EnableVideoTranslationBridge() {
  impl_->EnableVideoTranslationBridge();
}

void Tab::SetSearchEngine(const std::string& engine_id) {
  impl_->SetSearchEngine(engine_id);
}

void Tab::SetNavigationStateCallback(NavigationStateCallback callback) {
  impl_->SetNavigationStateCallback(std::move(callback));
}

void Tab::SetPageColorCallback(PageColorCallback callback) {
  impl_->SetPageColorCallback(std::move(callback));
}

void Tab::SetOpenUrlInNewTabCallback(OpenUrlInNewTabCallback callback) {
  impl_->SetOpenUrlInNewTabCallback(std::move(callback));
}

NSView* Tab::NativeView() const {
  return const_cast<Impl*>(impl_.get())->NativeView();
}

NSView* Tab::LoadedNativeView() const {
  return impl_->LoadedNativeView();
}

}  // namespace briviba
