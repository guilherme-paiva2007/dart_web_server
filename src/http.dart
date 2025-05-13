import 'dart:io';
import "routes.dart";

class Server {
    late HttpServer _http;
    bool serverReady = false;
    HttpServer get http {
        if (!serverReady) {
            throw Exception("Server not ready yet.");
        }
        return _http;
    }

    Router router = Router();

    Server({ Function(Server server)? onReady }) {
        HttpServer.bind(InternetAddress.anyIPv4, 8080).then((server) {
            _http = server;
            serverReady = true;
            if (onReady != null) {
                onReady(this);
            }
            print("Listening on http://${server.address.host}:${server.port}");
            server.listen((HttpRequest request) async {
                print("Request: ${request.method} ${request.uri}");
                request.response
                    ..statusCode = 200
                    ..write("Hello, world!")
                    ..close();
            });
        }).catchError((e) {
            print("Error: $e");
        });
    }
}