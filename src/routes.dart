import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:mime/mime.dart';

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

List<int> _requestFold(List<int> previous, Uint8List element) => previous..addAll(element);
RegExp _multipartNameRegexp = RegExp(r'name="([^"]+)"');
RegExp _multipartFilenameRegexp = RegExp(r'filename="([^"]+)"');

abstract class _MimeMultipartData {
    String name;

    _MimeMultipartData(this.name);
}

class _MimeMultipartField extends _MimeMultipartData {
    String value;

    _MimeMultipartField(super.name, this.value);
}

class _MimeMultipartFile extends _MimeMultipartData {
    ContentType contentType;
    List<int> content;
    String filename;

    _MimeMultipartFile(super.name, this.contentType, this.content, this.filename);
}

class RequestBody {
    final ContentType contentType;
    final List<int> _content;

    const RequestBody._create(this.contentType, this._content);

    static Future<RequestBody> fromRequest(HttpRequest request) async {
        ContentType contentType = request.headers.contentType ?? ContentType("text", "plain", charset: "utf-8");
        List<int> body = await request.fold<List<int>>([], _requestFold);
        return RequestBody._create(contentType, body);
    }

    dynamic json() {
        if (contentType.mimeType != "application/json") {
            throw ArgumentError("Content type is not JSON: ${contentType.mimeType}");
        }
        return jsonDecode(utf8.decode(_content));
    }

    String text() {
        return utf8.decode(_content);
    }

    List<int> bytes() {
        return _content;
    }

    Map<String, String> form() {
        if (contentType.mimeType != "application/x-www-form-urlencoded") {
            throw ArgumentError("Content type is not form: ${contentType.mimeType}");
        }
        return Uri.splitQueryString(utf8.decode(_content));
    }

    Future<Map<String, _MimeMultipartData>> multipart() async {
        if (contentType.mimeType != "multipart/form-data") {
            throw ArgumentError("Content type is not multipart: ${contentType.mimeType}");
        }
        String boundary = contentType.parameters["boundary"] ?? "";
        if (boundary.isEmpty) {
            throw ArgumentError("Missing boundary in multipart content type: ${contentType.mimeType}");
        }
        var transformer = MimeMultipartTransformer(boundary);
        var stream = Stream.fromIterable([_content]);

        Map<String, _MimeMultipartData> parts = {};
        await for (var part in transformer.bind(stream)) {
            var contentDisposition = part.headers['content-disposition'];
            if (contentDisposition != null && _multipartFilenameRegexp.hasMatch(contentDisposition)) {
                String name = _multipartNameRegexp.firstMatch(contentDisposition)?.group(1) ?? "unknown";
                String filename = _multipartFilenameRegexp.firstMatch(contentDisposition)?.group(1) ?? "unknown";
                List<int> fileContent = await part.toList().then((chunks) => chunks.expand((chunk) => chunk).toList());

                parts[name] = _MimeMultipartFile(
                    name,
                    ContentType.parse(part.headers['content-type'] ?? 'application/octet-stream'),
                    fileContent,
                    filename
                );
            } else if (contentDisposition != null) {
                String fieldValue = await utf8.decoder.bind(part).join();
                String fieldName = _multipartNameRegexp.firstMatch(contentDisposition)?.group(1) ?? "unknown";

                parts[fieldName] = _MimeMultipartField(fieldName, fieldValue);
            }
        }

        return parts;
    }
}

class LoadingParameters {
    final Server server;
    final HttpRequest request;
    final HttpResponse response;
    final Route route;
    final RoutePath path;
    final LoadingContent content;
    HttpSession get session => request.session;
    final Map<String, String> query;
    final RequestBody body;
    final Map<String, String> params;
    final Map localhooks = {};
    late final CodedError _error;
    bool _hasError = false;
    CodedError? get error {
        if (_hasError) return _error; else return null;
    }
    void set error(CodedError? error) {
        if (error != null) {
            _error = error;
            _hasError = true;
        }
    }
    late final WebSocket? _socket;
    bool _hasSocket = false;
    WebSocket? get socket {
        if (_hasSocket) return _socket; else return null;
    }
    void set socket(WebSocket? socket) {
        if (socket != null) {
            _socket = socket;
            _hasSocket = true;
        }
    }

    LoadingParameters._create({
        required this.server,
        required this.request,
        required this.response,
        required this.route,
        required this.path,
        required this.content,
        required this.query,
        required this.body,
        required this.params,
    });

    static Future<LoadingParameters> create(
        Server server,
        HttpRequest request,
        Route route,
        RoutePath path,
        Map<String, String> params
    ) async {
        return LoadingParameters._create(
            server: server,
            request: request,
            response: request.response,
            route: route,
            path: path,
            content: LoadingContent(),
            query: request.uri.queryParameters,
            body: await RequestBody.fromRequest(request),
            params: params
        );
    }
}

enum LoadingContentAreas { before, after, body, headers }

class LoadingContent {
    List<Object> _before = [];
    List<Object> _after = [];
    List<Object> _body = [];
    Map<String, HeaderValue> _headers = {};

    ContentType? contentType;
    int? statusCode;
    bool headersSent = false;

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
            default:
                break;
        }
    }

    void setHeader(String name, HeaderValue header) {
        if (headersSent) print("Headers already sent, cannot send $header");
        _headers[name] = header;
    }

    void _sendHeaders(HttpResponse response) {
        if (headersSent) return;
        if (contentType != null && response.headers.contentType != null) response.headers.contentType = contentType!;
        if (statusCode != null) response.statusCode = statusCode!;
        for (var header in _headers.entries) {
            response.headers.set(header.key, header.value);
        }
        headersSent = true;
    }

    void _sendArea(List area, HttpResponse response) {
        for (var part in area) {
            if (part is String) {
                response.write(part);
            } else if (part is List<int>) {
                response.add(part);
            } else if (part is Stream<List<int>>) {
                response.addStream(part).catchError((e) {
                    print("Error sending stream: $e");
                });
            } else if (part is Uint8List) {
                response.add(part);
            } else {
                throw ArgumentError("Invalid content type: ${part.runtimeType}");
            }
        }
    }

    void send(HttpResponse response) {
        _sendHeaders(response);

        headersSent = true;

        if (_before.isNotEmpty) _sendArea(_before, response);
        if (_body.isNotEmpty) _sendArea(_body, response);
        if (_after.isNotEmpty) _sendArea(_after, response);
        
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

    _process(LoadingParameters parameters) async {
        return await _open(parameters);
    }

    Future load(LoadingParameters parameters) async {
        var content = await _process(parameters);
        parameters.content.append(content);
        return content;
    }

    RouteMatch? match(Uri uri) {
        for (var path in paths) {
            RegExpMatch? match = path.regexp.firstMatch(uri.path);

            if (match != null) {
                Map<String, String> params = {};
                
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

    @override
    Future<String> _open(parameters) async {
        return await file.readAsString(encoding: utf8);
    }
}

class AssetRoute extends Route {
    AssetRoute({
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    @override
    Stream<List<int>> _open(parameters) {
        return file.openRead();
    }
    
    @override
    _process(LoadingParameters parameters) {
        parameters.content._sendHeaders(parameters.response);
        parameters.response.addStream(_open(parameters));
        return;
    }
}

class ExecutableRoute extends Route {
    ExecutableRoute({
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    @override
    _open(parameters) {}
}

class RestRoute extends Route {
    RestRoute({
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    @override
    _open(parameters) {}
}

class WebSocketRoute extends Route {
    HttpServer socket;

    WebSocketRoute(this.socket, {
        required List<String> paths,
        required File file,
        required ContentType contentType,
    }): super(paths: paths, file: file, contentType: contentType);

    @override
    _open(parameters) {}

    // adicionar um meio de rotas websocket coexistirem com rotas normais no mesmo caminho;
}


class Router {
    Set<Route> _routes = <Route>{};
    Set<WebSocketRoute> _wsRoutes = <WebSocketRoute>{};

    bool _addWebSocketRoute(WebSocketRoute route) {
        for (var path in route.paths) {
            if (match(Uri(path: path.raw)) != null) {
                throw ArgumentError("WebSocket route already exists: ${path.raw}");
            }
        }
        return _wsRoutes.add(route);
    }

    bool add(Route route) {
        if (route is WebSocketRoute) return _addWebSocketRoute(route);
        for (var path in route.paths) {
            if (match(Uri(path: path.raw)) != null) {
                throw ArgumentError("Route already exists: ${path.raw}");
            }
        }
        return _routes.add(route);
    }

    bool remove(Route route) {
        if (route is WebSocketRoute) return _wsRoutes.remove(route);
        return _routes.remove(route);
    }

    bool has(Route route) => _routes.contains(route) || _wsRoutes.contains(route);

    void clear() {
        _routes.clear();
        _wsRoutes.clear();
    }

    List<Route> toList() => _routes.toList();

    List<WebSocketRoute> webSocketsToList() => _wsRoutes.toList();

    RouteMatch? match(Uri uri, [bool socket = false]) {
        if (socket) {
            for (var route in _wsRoutes) {
                RouteMatch? match = route.match(uri);
                if (match != null) return match;
            }
        } else {
            for (var route in _routes) {
                RouteMatch? match = route.match(uri);
                if (match != null) return match;
            }
        }
        return null;
    }

    load(HttpRequest request, Server server) async {
        Uri uri = request.uri;
        bool isSocket = WebSocketTransformer.isUpgradeRequest(request);
        RouteMatch? match = this.match(uri, isSocket);
        if (match == null) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write("Not found");
            request.response.close();
            return;
        }
        LoadingParameters parameters = await LoadingParameters.create(
            server,
            request,
            match.route,
            match.path,
            match.params
        );

        try {
            if (isSocket) {
                final WebSocket socket = await WebSocketTransformer.upgrade(request);
                parameters.socket = socket;

                socket.listen((data) {
                    
                });
            } else {

            }
        } on CodedError {

        } on Exception {

        }
    }
}