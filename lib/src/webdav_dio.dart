import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:string_util_xx/StringUtilxx.dart';

import 'package:dio/dio.dart';

import 'auth.dart';
import 'client.dart';
import 'utils.dart';

/// Wrapped http client
class WdDio with DioMixin implements Dio {
  // // Request config
  // BaseOptions? baseOptions;

  // Interceptors
  final List<Interceptor>? interceptorList;

  // debug
  final bool debug;

  WdDio({
    BaseOptions? options,
    this.interceptorList,
    this.debug = false,
  }) {
    this.options = options ?? BaseOptions();
    // 禁止重定向
    this.options.followRedirects = true;

    // 状态码错误视为成功
    this.options.validateStatus = (status) => true;

    // httpClientAdapter = getAdapter();

    // 拦截器
    if (interceptorList != null) {
      for (var item in interceptorList!) {
        interceptors.add(item);
      }
    }

    // debug
    if (debug == true) {
      interceptors.add(LogInterceptor(responseBody: true));
    }
  }

  bool respIsSuccess(Response resp) {
    final code = resp.statusCode;
    if (null != code) {
      // 2xx
      return (code ~/ 100 == 2);
    }
    return StringUtilxx_c.isIgnoreCaseEqual(resp.statusMessage ?? "", "OK");
  }

  void throwRespError(Response<dynamic> resp) {
    final valid =
        (resp.data is String || resp.data is List || resp.data is Map);
    throw newResponseError(
      resp,
      message:
          "code: ${resp.statusCode}, dataType: ${resp.data.runtimeType}, len: ${valid ? '${resp.data.length}' : '-'}, content: ${valid ? resp.data : '<unknown>'}",
    );
  }

  // methods-------------------------
  Future<Response<T>> req<T>(
    Client self,
    String method,
    String path, {
    dynamic data,
    Function(Options)? optionsHandler,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    // options
    Options options = Options(method: method);
    options.headers ??= {};

    // 二次处理options
    if (optionsHandler != null) {
      optionsHandler(options);
    }

    // authorization
    String? str = self.auth.authorize(method, path);
    if (str != null) {
      options.headers?['Authorization'] = str;
    }
    // 跳过 zrok 警告
    options.headers?['skip_zrok_interstitial'] = "1";

    var resp = await requestUri<T>(
      Uri.parse(path.startsWith(RegExp(r'(http|https)://'))
          ? path
          : join(self.uri, path)),
      options: options,
      data: data,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
    if (((resp.statusCode ?? 0) ~/ 100) == 3) {
      // 3xx 处理重定向
      final location = resp.headers["location"];
      if (true == location?.isNotEmpty) {
        final usePath = Uri.tryParse(location!.first);
        if (null != usePath) {
          resp = await requestUri<T>(
            usePath,
            options: options,
            data: data,
            onSendProgress: onSendProgress,
            onReceiveProgress: onReceiveProgress,
            cancelToken: cancelToken,
          );
        }
      }
    }

    if (resp.statusCode == 401) {
      String? w3AHeader = resp.headers['www-authenticate']?.firstOrNull;
      String? lowerW3AHeader = w3AHeader?.toLowerCase();

      // before is noAuth
      if (self.auth.type == AuthType.NoAuth) {
        // Digest
        if (lowerW3AHeader?.contains('digest') == true) {
          self.auth = DigestAuth(
              user: self.auth.user,
              pwd: self.auth.pwd,
              dParts: DigestParts(w3AHeader));
        } else if (lowerW3AHeader?.contains('basic') == true) {
          // Basic
          self.auth = BasicAuth(user: self.auth.user, pwd: self.auth.pwd);
        } else {
          // error
          throw newResponseError(
            resp,
            message: "Unsupport AuthType: $lowerW3AHeader",
          );
        }
      } else if (self.auth.type == AuthType.DigestAuth &&
          lowerW3AHeader?.contains('stale=true') == true) {
        // before is digest and Nonce Lifetime is out
        self.auth = DigestAuth(
          user: self.auth.user,
          pwd: self.auth.pwd,
          dParts: DigestParts(w3AHeader),
        );
      } else {
        throw newResponseError(
          resp,
          message: "401, and faild to retry when set auth.",
        );
      }

      // retry
      return req<T>(
        self,
        method,
        path,
        data: data,
        optionsHandler: optionsHandler,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
      );
    }

    return resp;
  }

  // OPTIONS
  Future<Response> wdOptions(
    Client self,
    String path, {
    CancelToken? cancelToken,
  }) {
    return req(
      self,
      'OPTIONS',
      path,
      optionsHandler: (options) => options.headers?['depth'] = '0',
      cancelToken: cancelToken,
    );
  }

  // // quota
  // Future<Response> wdQuota(Client self, String dataStr,
  //     {CancelToken cancelToken}) {
  //   return this.req(self, 'PROPFIND', '/', data: utf8.encode(dataStr),
  //       optionsHandler: (options) {
  //     options.headers['depth'] = '0';
  //     options.headers['accept'] = 'text/plain';
  //   }, cancelToken: cancelToken);
  // }

  // PROPFIND
  Future<Response> wdPropfind(
    Client self,
    String path,
    bool depth,
    String dataStr, {
    CancelToken? cancelToken,
  }) async {
    var resp = await req(
      self,
      'PROPFIND',
      path,
      data: dataStr,
      optionsHandler: (options) {
        options.headers?['depth'] = depth ? '1' : '0';
        options.headers?['content-type'] = 'application/xml;charset=UTF-8';
        options.headers?['accept'] = 'application/xml,text/xml';
        options.headers?['accept-charset'] = 'utf-8';
        options.headers?['accept-encoding'] = '';
      },
      cancelToken: cancelToken,
    );

    if (false == respIsSuccess(resp)) {
      throwRespError(resp);
    }

    return resp;
  }

  // PROPFIND
  Future<Response> wdPropGet(
    Client self,
    String path,
    bool depth,
    String dataStr, {
    CancelToken? cancelToken,
  }) async {
    var resp = await req(
      self,
      'GET',
      path,
      data: dataStr,
      optionsHandler: (options) {
        options.headers?['depth'] = depth ? '1' : '0';
        options.headers?['content-type'] = 'application/xml;charset=UTF-8';
        options.headers?['accept'] = 'application/xml,text/xml';
        options.headers?['accept-charset'] = 'utf-8';
        options.headers?['accept-encoding'] = '';
      },
      cancelToken: cancelToken,
    );

    if (false == respIsSuccess(resp)) {
      throwRespError(resp);
    }

    return resp;
  }

  /// MKCOL
  Future<Response> wdMkcol(Client self, String path,
      {CancelToken? cancelToken}) {
    return req(self, 'MKCOL', path, cancelToken: cancelToken);
  }

  /// DELETE
  Future<Response> wdDelete(Client self, String path,
      {CancelToken? cancelToken}) {
    return req(self, 'DELETE', path, cancelToken: cancelToken);
  }

  /// COPY OR MOVE
  Future<void> wdCopyMove(
    Client self,
    String oldPath,
    String newPath,
    bool isCopy,
    bool overwrite, {
    CancelToken? cancelToken,
  }) async {
    var method = isCopy == true ? 'COPY' : 'MOVE';
    var resp = await req(self, method, oldPath, optionsHandler: (options) {
      options.headers?['destination'] = Uri.encodeFull(join(self.uri, newPath));
      options.headers?['overwrite'] = overwrite == true ? 'T' : 'F';
    }, cancelToken: cancelToken);

    var status = resp.statusCode;
    // TODO 207
    if (status == 201 || status == 204 || status == 207) {
      return;
    } else if (status == 409) {
      await _createParent(self, newPath, cancelToken: cancelToken);
      return wdCopyMove(
        self,
        oldPath,
        newPath,
        isCopy,
        overwrite,
        cancelToken: cancelToken,
      );
    } else {
      throwRespError(resp);
    }
  }

  /// create parent folder
  Future<void>? _createParent(Client self, String path,
      {CancelToken? cancelToken}) {
    var parentPath = path.substring(0, path.lastIndexOf('/') + 1);

    if (parentPath == '' || parentPath == '/') {
      return null;
    }
    return self.mkdirAll(parentPath, cancelToken);
  }

  /// read a file with bytes
  Future<List<int>> wdReadWithBytes(
    Client self,
    String path, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    var pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (false == respIsSuccess(pResp)) {
      throwRespError(pResp);
    }

    var resp = await req(
      self,
      'GET',
      path,
      optionsHandler: (options) => options.responseType = ResponseType.bytes,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
    if (false == respIsSuccess(resp)) {
      if (resp.statusCode != null) {
        if (resp.statusCode! >= 300 && resp.statusCode! < 400) {
          return (await req(
            self,
            'GET',
            resp.headers["location"]!.first,
            optionsHandler: (options) =>
                options.responseType = ResponseType.bytes,
            onReceiveProgress: onProgress,
            cancelToken: cancelToken,
          ))
              .data;
        }
      }
      throwRespError(resp);
    }
    return resp.data;
  }

  /// read a file with stream
  Future<void> wdReadWithStream(
    Client self,
    String path,
    String savePath, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    var pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (false == respIsSuccess(pResp)) {
      throwRespError(pResp);
    }

    Response<ResponseBody> resp;

    // Reference Dio download
    // request
    try {
      resp = await req(
        self,
        'GET',
        path,
        optionsHandler: (options) => options.responseType = ResponseType.stream,
        // onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        if (e.response!.requestOptions.receiveDataWhenStatusError == true) {
          final res = await transformer.transformResponse(
            e.response!.requestOptions..responseType = ResponseType.json,
            e.response!.data as ResponseBody,
          );
          e.response!.data = res;
        } else {
          e.response!.data = null;
        }
      }
      rethrow;
    }
    if (false == respIsSuccess(resp)) {
      throwRespError(resp);
    }

    resp.headers = Headers.fromMap(resp.data!.headers);

    // If directory (or file) doesn't exist yet, the entire method fails
    File file = File(savePath);
    file.createSync(recursive: true);

    final raf = file.openSync(mode: FileMode.write);

    // Create a Completer to notify the success/error state.
    var completer = Completer<Response>();
    var future = completer.future;
    var received = 0;

    // Stream<Uint8List>
    var stream = resp.data!.stream;
    var compressed = false;
    var total = 0;
    var contentEncoding =
        resp.headers[Headers.contentEncodingHeader]?.firstOrNull;
    if (contentEncoding != null) {
      compressed = ['gzip', 'deflate', 'compress'].contains(contentEncoding);
    }
    if (compressed) {
      total = -1;
    } else {
      total = int.parse(
        resp.headers[Headers.contentLengthHeader]?.firstOrNull ?? '-1',
      );
    }

    late StreamSubscription subscription;
    Future? asyncWrite;
    var closed = false;
    Future closeAndDelete() async {
      if (!closed) {
        closed = true;
        await asyncWrite;
        await raf.close();
        await file.delete();
      }
    }

    subscription = stream.listen(
      (data) {
        subscription.pause();
        // Write file asynchronously
        asyncWrite = raf.writeFrom(data).then((raf) {
          // Notify progress
          received += data.length;
          onProgress?.call(received, total);
          if (cancelToken == null || !cancelToken.isCancelled) {
            subscription.resume();
          }
        }).catchError((err) async {
          try {
            await subscription.cancel();
          } finally {
            completer.completeError(DioException(
              requestOptions: resp.requestOptions,
              error: err,
            ));
          }
        });
      },
      onDone: () async {
        try {
          await asyncWrite;
          closed = true;
          await raf.close();
          completer.complete(resp);
        } catch (err) {
          completer.completeError(DioException(
            requestOptions: resp.requestOptions,
            error: err,
          ));
        }
      },
      onError: (e) async {
        try {
          await closeAndDelete();
        } finally {
          completer.completeError(DioException(
            requestOptions: resp.requestOptions,
            error: e,
          ));
        }
      },
      cancelOnError: true,
    );

    // ignore: unawaited_futures
    cancelToken?.whenCancel.then((_) async {
      await subscription.cancel();
      await closeAndDelete();
    });

    if (resp.requestOptions.receiveTimeout != null &&
        resp.requestOptions.receiveTimeout!
                .compareTo(const Duration(milliseconds: 0)) >
            0) {
      future = future
          .timeout(resp.requestOptions.receiveTimeout!)
          .catchError((Object err) async {
        await subscription.cancel();
        await closeAndDelete();
        if (err is TimeoutException) {
          throw DioException(
            requestOptions: resp.requestOptions,
            error:
                'Receiving data timeout[${resp.requestOptions.receiveTimeout}ms]',
            type: DioExceptionType.receiveTimeout,
          );
        } else {
          throw err;
        }
      });
    }
    // ignore: invalid_use_of_internal_member
    await DioMixin.listenCancelForAsyncTask(cancelToken, future);
  }

  /// write a file with bytes
  Future<void> wdWriteWithBytes(
    Client self,
    String path,
    Uint8List data, {
    String? contentType,
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    final pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (false == respIsSuccess(pResp)) {
      throwRespError(pResp);
    }

    // mkdir
    await _createParent(self, path, cancelToken: cancelToken);

    final resp = await req(
      self,
      'PUT',
      path,
      data: data,
      optionsHandler: (options) {
        options.headers?["Content-Type"] =
            contentType ?? "application/octet-stream";
        options.headers?['content-length'] = data.length;
      },
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
    final status = resp.statusCode;
    if (status == 200 || status == 201 || status == 204) {
      return;
    }
    throwRespError(resp);
  }

  /// write a file with stream
  Future<void> wdWriteWithStream(
    Client self,
    String path,
    Stream<List<int>> data,
    int length, {
    String? contentType,
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    final pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (false == respIsSuccess(pResp)) {
      throwRespError(pResp);
    }

    // mkdir
    await _createParent(self, path, cancelToken: cancelToken);

    final resp = await req(
      self,
      'PUT',
      path,
      data: data,
      optionsHandler: (options) {
        options.headers?["Content-Type"] =
            contentType ?? "application/octet-stream";
        options.headers?['content-length'] = data.length;
      },
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
    final status = resp.statusCode;
    if (status == 200 || status == 201 || status == 204) {
      return;
    }
    throwRespError(resp);
  }
}
