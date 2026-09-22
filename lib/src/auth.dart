import 'dart:convert';
import 'utils.dart';

/// Auth type
enum AuthType {
  NoAuth,
  BasicAuth,
  DigestAuth,
}

/// Auth -----------------------------------
class Auth {
  /// username
  final String user;

  /// password
  final String pwd;

  const Auth({
    required this.user,
    required this.pwd,
  });

  /// Get auth type
  AuthType get type => AuthType.NoAuth;

  /// Get authorization data
  ///
  /// `requestTarget` 是编码后的请求目标（`path` 或 `path?query`），
  /// 与请求行里的目标一致（见 `WebdavUrlxx_c.requestTargetOfUri`）。
  String? authorize(String method, String requestTarget) => null;
}

/// BasicAuth ------------------------------------
class BasicAuth extends Auth {
  const BasicAuth({
    required super.user,
    required super.pwd,
  });

  @override
  AuthType get type => AuthType.BasicAuth;

  @override
  String authorize(String method, String path) {
    List<int> bytes = utf8.encode('$user:$pwd');
    return 'Basic ${base64Encode(bytes)}';
  }
}

// DigestAuth ----------------------------------
class DigestAuth extends Auth {
  DigestParts dParts;

  DigestAuth({
    required super.user,
    required super.pwd,
    required this.dParts,
  });

  String? get nonce => dParts.parts['nonce'];

  String? get realm => dParts.parts['realm'];

  String? get qop => dParts.parts['qop'];

  String? get opaque => dParts.parts['opaque'];

  String? get algorithm => dParts.parts['algorithm'];

  String? get entityBody => dParts.parts['entityBody'];

  @override
  AuthType get type => AuthType.DigestAuth;

  @override
  String authorize(String method, String requestTarget) {
    // 传入的已是编码后的请求目标（见 WebdavUrlxx_c.requestTargetOfUri），
    // 这里不能再编码，否则与服务端收到的请求行不一致，摘要校验会失败
    dParts.uri = requestTarget;
    dParts.method = method;
    return _getDigestAuthorization();
  }

  String _getDigestAuthorization() {
    int nonceCount = 1;
    String cnonce = computeNonce();
    String ha1 = _computeHA1(nonceCount, cnonce);
    String ha2 = _computeHA2();
    String response = _computeResponse(ha1, ha2, nonceCount, cnonce);
    final authorization = StringBuffer(
        'Digest username="$user", realm="$realm", nonce="$nonce", uri="${dParts.uri}", nc=$nonceCount, cnonce="$cnonce", response="$response"');

    if (qop?.isNotEmpty == true) {
      authorization.write(', qop=$qop');
    }

    if (opaque?.isNotEmpty == true) {
      authorization.write(', opaque=$opaque');
    }

    return authorization.toString();
  }

  //
  String _computeHA1(int nonceCount, String cnonce) {
    String? algorithm = this.algorithm;

    if (algorithm == 'MD5' || algorithm?.isEmpty != false) {
      return md5Hash('$user:$realm:$pwd');
    } else if (algorithm == 'MD5-sess') {
      String md5Str = md5Hash('$user:$realm:$pwd');
      return md5Hash('$md5Str:$nonceCount:$cnonce');
    }

    return '';
  }

  //
  String _computeHA2() {
    String? qop = this.qop;

    if (qop == 'auth' || qop?.isEmpty != false) {
      return md5Hash('${dParts.method}:${dParts.uri}');
    } else if (qop == 'auth-int' && entityBody?.isEmpty == false) {
      return md5Hash('${dParts.method}:${dParts.uri}:${md5Hash(entityBody!)}');
    }

    return '';
  }

  //
  String _computeResponse(
      String ha1, String ha2, int nonceCount, String cnonce) {
    String? qop = this.qop;

    if (qop?.isEmpty != false) {
      return md5Hash('$ha1:$nonce:$ha2');
    } else if (qop == 'auth' || qop == 'auth-int') {
      return md5Hash('$ha1:$nonce:$nonceCount:$cnonce:$qop:$ha2');
    }

    return '';
  }
}

/// DigestParts
class DigestParts {
  String uri = '';
  String method = '';

  Map<String, String> parts = {
    'nonce': '',
    'realm': '',
    'qop': '',
    'opaque': '',
    'algorithm': '',
    'entityBody': '',
  };

  DigestParts(String? authHeader) {
    if (authHeader != null) {
      final keys = parts.keys;
      final list = authHeader.split(',');
      for (final kv in list) {
        for (final k in keys) {
          if (kv.contains(k)) {
            final index = kv.indexOf('=');
            if (kv.length - 1 > index) {
              parts[k] = trim(kv.substring(index + 1), '"');
            }
          }
        }
      }
    }
  }
}
