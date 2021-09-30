workspace(name="example")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
  name = "build_bazel_rules_nodejs",
  sha256 = "b32a4713b45095e9e1921a7fcb1adf584bc05959f3336e7351bcf77f015a2d7c",
  urls = ["https://github.com/bazelbuild/rules_nodejs/releases/download/4.1.0/rules_nodejs-4.1.0.tar.gz"],
)

load("@build_bazel_rules_nodejs//:index.bzl", "node_repositories", "npm_install")
node_repositories(node_version = "16.9.0")
npm_install(
  name = "npm",
  package_json = "//third_party/npm:package.json",
  package_lock_json = "//third_party/npm:package-lock.json",
)