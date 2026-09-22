/// WebDAV 路径与链接处理。
///
/// 约定：调用方传入的路径是**原始文本**（服务器返回的 href 已由 `WebdavXml` 解码），
/// 可能包含 `#`、`?`、`%`、空格、中文等字符。这些字符如果直接拼进链接，
/// 会被当成片段（`#`）或查询（`?`）分隔符，请求就会落到错误的路径上，
/// 表现为列表读取失败、播放失败、401/404 等。这里按路径段重新编码，
/// 把原始路径安全地转成链接和请求目标。
class WebdavUrlxx_c {
  /// 是否为完整链接（http/https）
  static bool isFullUrl(String str) {
    final uri = Uri.tryParse(str.trim());
    if (null == uri || false == uri.hasScheme) {
      return false;
    }
    return (uri.isScheme('http') || uri.isScheme('https'));
  }

  /// 原始路径 -> 编码后的请求路径（以 `/` 开头，保留末尾 `/`）
  static String encodePath(String path) {
    final buffer = StringBuffer();
    for (final segment in path.split('/')) {
      if (segment.isEmpty) {
        continue;
      }
      buffer.write('/');
      // 按路径段编码：`#`、`?`、`%`、空格等会被转义，路径中合法的保留字符保持原样
      buffer.write(Uri(pathSegments: [segment]).path);
    }
    if (buffer.isEmpty) {
      return '/';
    }
    if (path.endsWith('/')) {
      buffer.write('/');
    }
    return buffer.toString();
  }

  /// 连接地址 + 原始路径 -> 完整链接
  /// * [path] 已是完整链接时原样返回（例如共享链接）
  /// * 连接地址里的子路径（如 `/remote.php/dav/files/user/`）会保留
  /// * 无法解析连接地址时返回 null
  static Uri? tryBuildUrl(String baseUrl, String path) {
    if (isFullUrl(path)) {
      return Uri.tryParse(path.trim());
    }
    final base = Uri.tryParse(baseUrl.trim());
    if (null == base || false == base.hasScheme || base.host.isEmpty) {
      return null;
    }
    final segments = <String>[
      ...base.pathSegments.where((e) => e.isNotEmpty),
      ...path.split('/').where((e) => e.isNotEmpty),
    ];
    var url = base.replace(pathSegments: segments);
    // 目录以 '/' 结尾（部分 webdav 服务要求），按路径段拼装时会丢掉，需要补回来
    if (path.endsWith('/') && false == url.path.endsWith('/')) {
      url = url.replace(path: '${url.path}/');
    }
    return url;
  }

  /// 请求目标（request-target）：编码后的 `path` 或 `path?query`
  /// * 用于鉴权签名，必须与实际发出的请求行一致
  static String requestTargetOfUri(Uri url) {
    if (false == url.hasQuery) {
      return url.path;
    }
    return '${url.path}?${url.query}';
  }

  /// 连接地址 + 原始路径 -> 请求目标，无法解析时返回 null
  static String? tryRequestTarget(String baseUrl, String path) {
    final url = tryBuildUrl(baseUrl, path);
    if (null == url) {
      return null;
    }
    return requestTargetOfUri(url);
  }

  /// 解码服务器返回的 href
  /// * 规范要求返回百分号编码的链接；不符合要求的服务器可能返回原始字符
  ///   （例如文件名里的 `%`），此时退回原文，避免整个列表加载失败
  static String tryDecodeHref(String href) {
    try {
      return Uri.decodeFull(href);
    } catch (_) {
      return href;
    }
  }
}
