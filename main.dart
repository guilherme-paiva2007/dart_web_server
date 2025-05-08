import "server.dart";
import "commands.dart";

void main() async {
    await startServer();
    startCli();
}