import 'package:phan_mem_quan_ly_can_ho/widgets/app_logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AIAgentService {
  final String _apiKey = dotenv.env['GEMINI_KEY'] ?? '';
  final String _modelName = 'gemini-2.5-flash';

  AIAgentService() {
    if (_apiKey.isEmpty) {
      logger.w('GEMINI_KEY not found in environment variables');
    } else {
      logger.i('AI Agent Service initialized');
    }
  }

  String get apiKey => _apiKey;
  String get modelName => _modelName;
  bool get isConfigured => _apiKey.isNotEmpty;

  void dispose() => logger.i('AI Agent Service disposed');
}