import "dart:io";

import "src/cli.dart";

CommandCollection commands = CommandCollection();

void startCli() {
    List<Command> commandsList = [
        Command(
            name: "oii",
            handler: (args, flags, command) {
                print("Oiiii");
            }
        ),
        Command(
            name: "tchau",
            handler: (args, flags, command) {
                print("Tchauuu");
                exit(0);
            }
        ),
        Command(
            name: "sub",
            handler: (args, flags, command) {
                print("Subcommand not found: ${args[0]}");
            },
            subcommands: {
                Command(
                    name: "1",
                    handler: (args, flags, command) {
                        print("Subcommand 1");
                    }
                ),
                Command(
                    name: "2",
                    handler: (args, flags, command) {
                        print("Subcommand 2");
                    }
                )
            }
        ),
        Command(
            name: "exit",
            handler: (args, flags, command) {
                exit(0);
            }
        )
    ];

    for (var command in commandsList) {
        commands.add(command);
    }

    commands.listen();
}