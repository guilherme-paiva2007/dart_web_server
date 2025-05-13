import 'src/http.dart';

late Server _server;
bool _serverReady = false;
Server get server {
    if (!_serverReady) {
        throw Exception("Server not ready yet.");
    }
    return _server;
}

Future startServer() async {
    _server = Server(
        onReady: (Server server) => _serverReady = true
    );
}