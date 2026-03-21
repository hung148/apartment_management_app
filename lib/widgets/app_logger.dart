import 'package:logger/logger.dart';

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       // no stack trace on normal logs
    errorMethodCount: 8,  // stack trace on errors
    colors: true,
    printEmojis: true,
  ),
);