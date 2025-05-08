import 'dart:async';
import 'dart:io';

typedef CommandArgs = List<String>;
typedef CommandFlags = Map<String, CommandArgs>;
typedef CommandHandler = dynamic Function(CommandArgs args, CommandFlags flags, Command command);

RegExp _onlyAlphanumeric = RegExp(r"^[a-zA-Z0-9_\-]+$");

String _checkForValidCommandName(String name) {
    if (name.isEmpty) {
        throw ArgumentError("Command name cannot be empty.");
    }
    if (!_onlyAlphanumeric.hasMatch(name)) {
        throw ArgumentError("Command name can only contain alphanumeric characters, underscores and dashes. Found: $name");
    }
    return name;
}

class CommandLine {
    final CommandArgs args;
    final CommandFlags flags;

    const CommandLine._create(this.args, this.flags);

    factory CommandLine(String commandLineString) {
        final List<String> split = commandLineString.trim().split(" ");

        CommandArgs args = [];
        CommandFlags flags = {};

        String? currentFlag;
        for (var part in split) {
            if (part.startsWith("--")) {
                currentFlag = part.substring(2);
            } else if (currentFlag == null) {
                args.add(part);
            } else {
                if (!flags.containsKey(currentFlag)) {
                    flags[currentFlag] = [];
                }
                flags[currentFlag]!.add(part);
            }
        }

        return CommandLine._create(args, flags);
    }
}

class Command {
    final String name;
    final CommandHandler _handler;
    final Set<Command> subcommands;

    Command({
        required String name,
        required CommandHandler handler,
        this.subcommands = const <Command>{}
    }): this._handler = handler, this.name = _checkForValidCommandName(name);

    void run(String commandLineString) {
        CommandLine commandLine = CommandLine(commandLineString);
        for (var subcommand in subcommands) {
            if (subcommand.name == commandLine.args[0]) {
                subcommand.run(commandLineString.substring(subcommand.name.length + 1));
                return;
            }
        }
        _handler(commandLine.args, commandLine.flags, this);
    }
}

class CommandCollection {
    Set<Command> _commands = Set<Command>();

    operator [](String name) {
        for (var command in _commands) {
            if (command.name == name) {
                return command;
            }
        }
    }

    void add(Command command) => _commands.add(command);

    void remove(Command command) => _commands.remove(command);

    void run(String commandLineString) {
        String commandName = commandLineString.split(" ").elementAt(0);

        for (var command in _commands) {
            if (command.name == commandName) {
                command.run(commandLineString.substring(commandName.length + (commandLineString.endsWith(" ") ? 1 : 0)));
                return;
            }
        }

        print("Command not found: $commandName");
    }

    StreamSubscription listen() {
        return stdin.listen((data) {
            String commandLineString = String.fromCharCodes(data).trim();
            if (commandLineString.isEmpty) return;
            run(commandLineString);
        });
    }
}