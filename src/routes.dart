import 'dart:io';

RegExp _uriChars = RegExp(r"^[a-zA-Z0-9_\-\.]+$");

bool _checkForValidPathPart(String part) {
    if (part.isEmpty) {
        throw ArgumentError("Path part cannot be empty.");
    }
    if (!_uriChars.hasMatch(part)) {
        throw ArgumentError("Path part can only contain alphanumeric characters, underscores, dashes and dots. Found: $part");
    }
    return true;
}

Set<int> _validExecErrorHttpCodes = {
    300, 301, 302, 303, 304, 305, 306, 307, 308, 400,
    401, 402, 403, 404, 405, 406, 407, 408, 409, 410,
    411, 412, 413, 414, 415, 416, 417, 418, 421, 422,
    423, 424, 425, 426, 428, 429, 431, 451, 500, 501,
    502, 503, 504, 505, 506, 507, 508, 510, 511
};

Set<int> _timeoutErrors = const { 408, 504 };
Set<int> _authenticationErrors = const { 401, 407 };
Set<int> _permissionErrors = const { 403 };
Set<int> _notFoundErrors = const { 404 };
Set<int> _implementationErrors = const { 501, 505 };

class CodedError extends Error {
    int code;
    late String type = "Unknown";
    String message;

    CodedError({
        required this.code,
        required this.message
    }) {
        if (!_validExecErrorHttpCodes.contains(code)) code = 500;

        String stringCode = code.toString();

        if (stringCode.length != 3) return;
        if (_timeoutErrors.contains(code)) {
            type = "Timeout";
            return;
        }
        if (_authenticationErrors.contains(code)) {
            type = "Authentication";
            return;
        }
        if (_permissionErrors.contains(code)) {
            type = "Permission";
            return;
        }
        if (_notFoundErrors.contains(code)) {
            type = "NotFound";
            return;
        }
        if (_implementationErrors.contains(code)) {
            type = "Implementation";
            return;
        }
        if (stringCode.startsWith("4")) {
            type = "Client";
            return;
        }
        if (stringCode.startsWith("5")) {
            type = "Server";
            return;
        }
        if (stringCode.startsWith("3")) {
            type = "Redirect";
            return;
        }
    }

    String toString() {
        return "${type}Error ($code): $message\n${stackTrace}";
    }
}

class RoutePath {
    final String raw;
    final RegExp regexp;
    final List<String> params;

    const RoutePath._create(this.raw, this.regexp, this.params);

    factory RoutePath(String path) {
        final bool startsWith = path.startsWith("/");
        final bool endsWith = path.endsWith("/");
        path = path.substring(startsWith ? 1 : 0, endsWith ? -1 : null);

        List<String> regexpParts = [];
        List<String> params = [];

        List<String> parts = path.split("/");
        for (var part in parts) {
            if (part.startsWith("[") && part.endsWith("]")) {
                part = part.substring(1, part.length - 1);
                if (part.isEmpty) {
                    throw ArgumentError("Parameter path part cannot be empty.");
                }
                regexpParts.add("([^/]+)");
                params.add(part);
            } else {
                if (!_checkForValidPathPart(part)) {
                    throw ArgumentError("Invalid path part: $part");
                }
                regexpParts.add(part.replaceAll(".", "\\.").replaceAll("-", "\\-"));
            }
        }

        RegExp regexp = RegExp("^/${regexpParts.join("/")}/?^");
        String raw = "/${parts.join("/")}/";
        return RoutePath._create(raw, regexp, params);
    }
}

class LoadingParameters {
    var server;
    HttpRequest? request;
    HttpResponse? response;
    Route? route;
    RoutePath? path;
    var content;
    var session;
    Map<String, String>? query;
    var body;
    var params;
    Map localhooks = {};
    CodedError? error;


}

enum LoadingContentAreas { before, after, body }

class LoadingContent {
    List<Object> _before = [];
    List<Object> _after = [];
    List<Object> _body = [];

    ContentType? contentType;
    int? statusCode;

    LoadingContent({
        this.contentType,
        this.statusCode
    });

    void clear() {
        _before.clear();
        _after.clear();
        _body.clear();
    }

    void append(Object chunk, {LoadingContentAreas area = LoadingContentAreas.body}) {
        switch (area) {
            case LoadingContentAreas.before:
                _before.add(chunk);
                break;
            case LoadingContentAreas.after:
                _after.add(chunk);
                break;
            case LoadingContentAreas.body:
                _body.add(chunk);
                break;
        }
    }

    void _sendArea(List area) {
        for (var part in area) {
            if (part is String) {
                print(part);
            } else if (part is List<int>) {
                print(part);
            } else if (part is Stream<List<int>>) {
                part.listen((data) => print(data));
            } else {
                throw ArgumentError("Invalid content type: ${part.runtimeType}");
            }
        }
    }

    void send(HttpResponse response) {
        if (contentType != null && response.headers.contentType != null) response.headers.contentType = contentType!;
        if (statusCode != null) response.statusCode = statusCode!;

        if (_before.isNotEmpty) _sendArea(_before);
        if (_body.isNotEmpty) _sendArea(_body);
        if (_after.isNotEmpty) _sendArea(_after);
        
        response.close();
    }
}

abstract class Route {
    late List<RoutePath> paths;
    File file;
    ContentType contentType;
    // dependencies
    // events

    Route({
        required List<String> paths,
        required this.file,
        required this.contentType,
    }) {
        this.paths = paths.map((path) => RoutePath(path)).toList();
    }

    _open(LoadingParameters parameters);

    Future load(LoadingParameters parameters) async {
        return await _open(parameters); // mudar para adicionar a um LoadingContent
    }
}

class ScreenRoute extends Route {
    ScreenRoute({
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    _open(parameters) {}
}

class AssetRoute extends Route {
    AssetRoute({
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    _open(parameters) {}
}

class ExecutableRoute extends Route {
    ExecutableRoute({
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    _open(parameters) {}
}

class RestRoute extends Route {
    RestRoute({
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    _open(parameters) {}
}

class Router {}