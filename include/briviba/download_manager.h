#ifndef BRIVIBA_DOWNLOAD_MANAGER_H_
#define BRIVIBA_DOWNLOAD_MANAGER_H_

#include <filesystem>
#include <memory>
#include <string>

#ifdef __OBJC__
@class WKDownload;
#endif

namespace briviba {

class DownloadManager {
 public:
  explicit DownloadManager(std::filesystem::path database_path);
  ~DownloadManager();

  DownloadManager(const DownloadManager&) = delete;
  DownloadManager& operator=(const DownloadManager&) = delete;

  static std::filesystem::path DefaultDatabasePath();

#ifdef __OBJC__
  void ManageDownload(WKDownload* download);
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_DOWNLOAD_MANAGER_H_
