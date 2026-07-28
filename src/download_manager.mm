#include "briviba/download_manager.h"

#include "briviba/app_paths.h"

#include <sqlite3.h>

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

#include <chrono>
#include <filesystem>
#include <memory>
#include <string>
#include <utility>

@interface BrivibaDownloadDelegate : NSObject <WKDownloadDelegate> {
 @public
  sqlite3* database;
}
@end

namespace briviba {
namespace {

class Statement {
 public:
  Statement(sqlite3* database, const char* sql) {
    if (sqlite3_prepare_v2(database, sql, -1, &statement_, nullptr) != SQLITE_OK) {
      statement_ = nullptr;
    }
  }

  ~Statement() {
    if (statement_ != nullptr) {
      sqlite3_finalize(statement_);
    }
  }

  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;

  sqlite3_stmt* get() const { return statement_; }

 private:
  sqlite3_stmt* statement_ = nullptr;
};

int64_t UnixTimeSeconds() {
  const auto now = std::chrono::system_clock::now();
  return std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
}

std::string StringFromNSString(NSString* value) {
  const char* utf8 = [value UTF8String];
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

NSURL* UniqueDestinationUrl(NSString* suggested_filename) {
  NSString* filename = [suggested_filename length] == 0 ? @"briviba-download" : suggested_filename;
  NSURL* downloads_url = [[NSFileManager defaultManager] URLForDirectory:NSDownloadsDirectory
                                                                inDomain:NSUserDomainMask
                                                       appropriateForURL:nil
                                                                  create:YES
                                                                   error:nil];
  NSURL* destination = [downloads_url URLByAppendingPathComponent:filename];
  NSString* extension = [destination pathExtension];
  NSString* base_name = [[destination URLByDeletingPathExtension] lastPathComponent];

  NSInteger suffix = 1;
  while ([[NSFileManager defaultManager] fileExistsAtPath:[destination path]]) {
    NSString* candidate_name =
        [NSString stringWithFormat:@"%@-%ld", base_name, static_cast<long>(suffix)];
    if ([extension length] > 0) {
      candidate_name = [candidate_name stringByAppendingPathExtension:extension];
    }
    destination = [downloads_url URLByAppendingPathComponent:candidate_name];
    ++suffix;
  }
  return destination;
}

void RecordDownload(sqlite3* database, const std::string& url, const std::string& path,
                    const std::string& state) {
  if (database == nullptr) {
    return;
  }

  Statement statement(database,
                      "INSERT INTO downloads(url, path, state, updated_at) VALUES(?1, ?2, ?3, ?4);");
  if (statement.get() == nullptr) {
    return;
  }

  sqlite3_bind_text(statement.get(), 1, url.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(statement.get(), 2, path.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(statement.get(), 3, state.c_str(), -1, SQLITE_TRANSIENT);
  sqlite3_bind_int64(statement.get(), 4, UnixTimeSeconds());
  sqlite3_step(statement.get());
}

}  // namespace
}  // namespace briviba

@implementation BrivibaDownloadDelegate

- (void)download:(WKDownload*)download
    decideDestinationUsingResponse:(NSURLResponse*)response
                 suggestedFilename:(NSString*)suggestedFilename
                 completionHandler:(void (^)(NSURL* _Nullable destination))completionHandler {
  (void)response;
  NSURL* destination = briviba::UniqueDestinationUrl(suggestedFilename);
  NSURL* request_url = [[download originalRequest] URL];
  NSString* absolute_url = request_url == nil ? @"" : [request_url absoluteString];
  briviba::RecordDownload(database, briviba::StringFromNSString(absolute_url),
                          briviba::StringFromNSString([destination path]), "started");
  completionHandler(destination);
}

- (void)downloadDidFinish:(WKDownload*)download {
  NSURL* request_url = [[download originalRequest] URL];
  NSString* absolute_url = request_url == nil ? @"" : [request_url absoluteString];
  briviba::RecordDownload(database, briviba::StringFromNSString(absolute_url), std::string(),
                          "finished");
}

- (void)download:(WKDownload*)download didFailWithError:(NSError*)error resumeData:(NSData*)resumeData {
  (void)error;
  (void)resumeData;
  NSURL* request_url = [[download originalRequest] URL];
  NSString* absolute_url = request_url == nil ? @"" : [request_url absoluteString];
  briviba::RecordDownload(database, briviba::StringFromNSString(absolute_url), std::string(),
                          "failed");
}

@end

namespace briviba {

class DownloadManager::Impl {
 public:
  explicit Impl(std::filesystem::path database_path) : database_path_(std::move(database_path)) {
    std::filesystem::create_directories(database_path_.parent_path());

    sqlite3* database = nullptr;
    if (sqlite3_open(database_path_.string().c_str(), &database) == SQLITE_OK) {
      database_.reset(database);
      EnsureSchema();
    } else if (database != nullptr) {
      sqlite3_close(database);
    }

    delegate_ = [[BrivibaDownloadDelegate alloc] init];
    delegate_->database = database_.get();
  }

  void ManageDownload(WKDownload* download) { [download setDelegate:delegate_]; }

 private:
  struct DatabaseDeleter {
    void operator()(sqlite3* database) const {
      if (database != nullptr) {
        sqlite3_close(database);
      }
    }
  };

  void EnsureSchema() {
    const char* sql =
        "CREATE TABLE IF NOT EXISTS downloads("
        "id INTEGER PRIMARY KEY,"
        "url TEXT NOT NULL,"
        "path TEXT NOT NULL,"
        "state TEXT NOT NULL,"
        "updated_at INTEGER NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS downloads_updated_at_idx ON downloads(updated_at);";
    sqlite3_exec(database_.get(), sql, nullptr, nullptr, nullptr);
  }

  std::filesystem::path database_path_;
  std::unique_ptr<sqlite3, DatabaseDeleter> database_;
  BrivibaDownloadDelegate* delegate_ = nil;
};

DownloadManager::DownloadManager(std::filesystem::path database_path)
    : impl_(std::make_unique<Impl>(std::move(database_path))) {}

DownloadManager::~DownloadManager() = default;

std::filesystem::path DownloadManager::DefaultDatabasePath() {
  return ApplicationSupportFile("downloads.sqlite3");
}

void DownloadManager::ManageDownload(WKDownload* download) {
  impl_->ManageDownload(download);
}

}  // namespace briviba
