import 'src/http.dart';

late Server _server;
bool serverReady = false;
Server get server {
    if (!serverReady) {
        throw Exception("Server not ready yet.");
    }
    return _server;
}

Future startServer() async {
    _server = Server(
        onReady: (Server server) => serverReady = true
    );
}