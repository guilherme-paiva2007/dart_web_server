import 'dart:io';
import "coded_error.dart";
import 'http.dart';

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

    LoadingParameters._create({
        required this.server,
        required this.request,
        required this.response,
        required this.route,
        required this.path,
        required this.content,
        required this.session,
        required this.query,
        required this.params,
    });

    factory LoadingParameters(
        Server server,
        HttpRequest request,
        Route route,
        RoutePath path,
        Map<String, String> params
    ) {
        HttpResponse response = request.response;
        Map<String, String>? query = request.uri.queryParameters;

        return LoadingParameters._create(
            server: server,
            request: request,
            response: response,
            route: route,
            path: path,
            content: LoadingContent(),
            session: request.session,
            query: query,
            params: params
        );
    }
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

class RouteMatch {
    final Route route;
    final RoutePath path;
    final Map<String, String> params;

    const RouteMatch({
        required this.route,
        required this.path,
        required this.params
    });
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

    RouteMatch? match(Uri uri) {
        for (var path in paths) {
            if (path.regexp.hasMatch(uri.path)) {
                Map<String, String> params = {};

                RegExpMatch match = path.regexp.firstMatch(uri.path)!;
                
                for (var i = 0; i < path.params.length; i++) {
                    String paramName = path.params[i];
                    String paramValue = match.group(i + 1)!;
                    params[paramName] = paramValue;
                }

                return RouteMatch(
                    route: this,
                    params: params,
                    path: path
                );
            }
        }
        return null;
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