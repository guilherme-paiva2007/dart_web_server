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