#include "briviba/bookmark_manager.h"

#include "briviba/app_paths.h"

#include <sqlite3.h>

#include <chrono>
#include <filesystem>
#include <memory>
#include <string>
#include <utility>

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

}  // namespace

class BookmarkManager::Impl {
 public:
  explicit Impl(std::filesystem::path database_path) : database_path_(std::move(database_path)) {
    std::filesystem::create_directories(database_path_.parent_path());

    sqlite3* database = nullptr;
    if (sqlite3_open(database_path_.string().c_str(), &database) == SQLITE_OK) {
      database_.reset(database);
      EnsureSchema();
      return;
    }

    if (database != nullptr) {
      sqlite3_close(database);
    }
  }

  bool AddBookmark(const std::string& url) {
    if (database_ == nullptr || url.empty()) {
      return false;
    }

    Statement statement(database_.get(),
                        "INSERT INTO bookmarks(url, created_at) VALUES(?1, ?2) "
                        "ON CONFLICT(url) DO UPDATE SET created_at = excluded.created_at;");
    if (statement.get() == nullptr) {
      return false;
    }

    sqlite3_bind_text(statement.get(), 1, url.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(statement.get(), 2, UnixTimeSeconds());
    return sqlite3_step(statement.get()) == SQLITE_DONE;
  }

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
        "CREATE TABLE IF NOT EXISTS bookmarks("
        "id INTEGER PRIMARY KEY,"
        "url TEXT NOT NULL UNIQUE,"
        "created_at INTEGER NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS bookmarks_created_at_idx ON bookmarks(created_at);";
    sqlite3_exec(database_.get(), sql, nullptr, nullptr, nullptr);
  }

  std::filesystem::path database_path_;
  std::unique_ptr<sqlite3, DatabaseDeleter> database_;
};

BookmarkManager::BookmarkManager(std::filesystem::path database_path)
    : impl_(std::make_unique<Impl>(std::move(database_path))) {}

BookmarkManager::~BookmarkManager() = default;

std::filesystem::path BookmarkManager::DefaultDatabasePath() {
  return ApplicationSupportFile("bookmarks.sqlite3");
}

bool BookmarkManager::AddBookmark(const std::string& url) {
  return impl_->AddBookmark(url);
}

}  // namespace briviba
