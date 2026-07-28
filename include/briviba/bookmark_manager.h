#ifndef BRIVIBA_BOOKMARK_MANAGER_H_
#define BRIVIBA_BOOKMARK_MANAGER_H_

#include <filesystem>
#include <memory>
#include <string>

namespace briviba {

class BookmarkManager {
 public:
  explicit BookmarkManager(std::filesystem::path database_path);
  ~BookmarkManager();

  BookmarkManager(const BookmarkManager&) = delete;
  BookmarkManager& operator=(const BookmarkManager&) = delete;

  static std::filesystem::path DefaultDatabasePath();

  bool AddBookmark(const std::string& url);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_BOOKMARK_MANAGER_H_
