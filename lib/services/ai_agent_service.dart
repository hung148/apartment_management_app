import 'package:apartment_management_project_2/widgets/app_logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:get_it/get_it.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';

class AIAgentService {
  late GenerativeModel _model;
  final String _apiKey = dotenv.env['GEMINI_KEY'] ?? '';
  final String _modelName = 'gemini-pro';
  
  // Service locator dependencies
  late BuildingService _buildingService;
  late TenantService _tenantService;
  late RoomService _roomService;
  late PaymentService _paymentService;
  final GetIt _getIt = GetIt.instance;

  AIAgentService() {
    _initializeServices();
    _initializeModel();
  }

  /// Initialize dependent services from get_it
  void _initializeServices() {
    try {
      _buildingService = _getIt<BuildingService>();
      _tenantService = _getIt<TenantService>();
      _roomService = _getIt<RoomService>();
      _paymentService = _getIt<PaymentService>();
      logger.i('AI Agent Service dependencies initialized');
    } catch (e) {
      logger.w('Error initializing services: $e');
    }
  }

  /// Initialize the generative AI model
  void _initializeModel() {
    try {
      if (_apiKey.isEmpty) {
        logger.w('GEMINI_KEY not found in environment variables');
        throw Exception('API key is required for AI Agent Service');
      }

      _model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
      );
      logger.i('AI Agent Service initialized successfully');
    } catch (e) {
      logger.e('Error initializing AI Agent Service', error: e);
      rethrow;
    }
  }

  /// ========================================
  /// TEXT GENERATION METHODS
  /// ========================================

  /// Generate text content using AI
  Future<String?> generateText(String prompt) async {
    try {
      logger.i('Generating text with prompt: $prompt');
      
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      
      final result = response.text ?? '';
      logger.i('Text generation successful');
      return result;
    } catch (e) {
      logger.e('Error generating text', error: e);
      return null;
    }
  }

  /// Generate text with streaming response
  Stream<String> generateTextStream(String prompt) async* {
    try {
      logger.i('Starting streaming text generation');
      
      final content = [Content.text(prompt)];
      final stream = _model.generateContentStream(content);
      
      await for (final response in stream) {
        final text = response.text ?? '';
        if (text.isNotEmpty) {
          yield text;
        }
      }
      logger.i('Streaming text generation completed');
    } catch (e) {
      logger.e('Error in streaming text generation', error: e);
      yield 'Error: ${e.toString()}';
    }
  }

  /// ========================================
  /// CONVERSATIONAL METHODS
  /// ========================================

  /// Start a chat session and send a message
  Future<String?> sendChatMessage(String message) async {
    try {
      logger.i('Sending chat message: $message');
      
      final content = [Content.text(message)];
      final response = await _model.generateContent(content);
      
      final result = response.text ?? '';
      logger.i('Chat message sent successfully');
      return result;
    } catch (e) {
      logger.e('Error sending chat message', error: e);
      return null;
    }
  }

  /// ========================================
  /// CRUD OPERATIONS - BUILDINGS
  /// ========================================

  /// Get all buildings for an organization
  Future<List<dynamic>> getBuildings(String organizationId) async {
    try {
      logger.i('Fetching buildings for organization: $organizationId');
      final buildings = await _buildingService.getOrganizationBuildings(organizationId);
      logger.i('Retrieved ${buildings.length} buildings');
      return buildings;
    } catch (e) {
      logger.e('Error getting buildings', error: e);
      return [];
    }
  }

  /// Get single building by ID
  Future<dynamic?> getBuildingById(String buildingId) async {
    try {
      logger.i('Fetching building: $buildingId');
      return await _buildingService.getBuildingById(buildingId);
    } catch (e) {
      logger.e('Error getting building', error: e);
      return null;
    }
  }

  /// ========================================
  /// CRUD OPERATIONS - TENANTS
  /// ========================================

  /// Get all tenants in an organization
  Future<List<dynamic>> getTenants(String organizationId) async {
    try {
      logger.i('Fetching all tenants for organization: $organizationId');
      final tenants = await _tenantService.getOrganizationTenants(organizationId);
      logger.i('Retrieved ${tenants.length} tenants');
      return tenants;
    } catch (e) {
      logger.e('Error getting tenants', error: e);
      return [];
    }
  }

  /// Get tenants by building
  Future<List<dynamic>> getTenantsByBuilding(String organizationId, String buildingId) async {
    try {
      logger.i('Fetching tenants for building: $buildingId');
      final tenants = await _tenantService.getBuildingTenants(organizationId, buildingId);
      logger.i('Retrieved ${tenants.length} tenants for building');
      return tenants;
    } catch (e) {
      logger.e('Error getting tenants by building', error: e);
      return [];
    }
  }

  /// ========================================
  /// CRUD OPERATIONS - ROOMS
  /// ========================================

  /// Get all rooms by building
  Future<List<dynamic>> getRoomsByBuilding(String organizationId, String buildingId) async {
    try {
      logger.i('Fetching rooms for building: $buildingId');
      final rooms = await _roomService.getBuildingRooms(organizationId, buildingId);
      logger.i('Retrieved ${rooms.length} rooms');
      return rooms;
    } catch (e) {
      logger.e('Error getting rooms', error: e);
      return [];
    }
  }

  /// Get room by ID
  Future<dynamic?> getRoomById(String roomId) async {
    try {
      logger.i('Fetching room: $roomId');
      return await _roomService.getRoomById(roomId);
    } catch (e) {
      logger.e('Error getting room', error: e);
      return null;
    }
  }

  /// ========================================
  /// CRUD OPERATIONS - PAYMENTS
  /// ========================================

  /// Get all payments in organization
  Future<List<dynamic>> getPayments(String organizationId) async {
    try {
      logger.i('Fetching all payments');
      final payments = await _paymentService.getOrganizationPayments(organizationId);
      logger.i('Retrieved ${payments.length} payments');
      return payments;
    } catch (e) {
      logger.e('Error getting payments', error: e);
      return [];
    }
  }

  /// Get payments by building
  Future<List<dynamic>> getPaymentsByBuilding(String organizationId, String buildingId) async {
    try {
      logger.i('Fetching payments for building: $buildingId');
      final payments = await _paymentService.getBuildingPayments(organizationId, buildingId);
      logger.i('Retrieved ${payments.length} payments');
      return payments;
    } catch (e) {
      logger.e('Error getting payments by building', error: e);
      return [];
    }
  }

  /// Get payments by tenant
  Future<List<dynamic>> getPaymentsByTenant(String organizationId, String tenantId) async {
    try {
      logger.i('Fetching payments for tenant: $tenantId');
      final payments = await _paymentService.getTenantPayments(organizationId, tenantId);
      logger.i('Retrieved ${payments.length} payments');
      return payments;
    } catch (e) {
      logger.e('Error getting payments by tenant', error: e);
      return [];
    }
  }

  /// Get overdue/outstanding payments
  Future<List<dynamic>> getOutstandingPayments(String organizationId) async {
    try {
      logger.i('Fetching outstanding/overdue payments');
      final payments = await _paymentService.getOverduePayments(organizationId);
      logger.i('Retrieved ${payments.length} outstanding payments');
      return payments;
    } catch (e) {
      logger.e('Error getting outstanding payments', error: e);
      return [];
    }
  }

  /// ========================================
  /// DATA ANALYSIS (Phan tich du lieu)
  /// ========================================

  /// Analyze financial data from real payment data
  Future<String?> analyzeFinancialData(String organizationId, String buildingId) async {
    try {
      logger.i('Analyzing financial data for building: $buildingId');
      
      // Fetch real payment data
      final payments = await getPaymentsByBuilding(organizationId, buildingId);
      if (payments.isEmpty) {
        return 'Không có dữ liệu thanh toán để phân tích.';
      }
      
      // Prepare data summary for AI analysis
      final dataStr = payments.toString();
      
      final prompt = '''
      Phân tích dữ liệu tài chính chi tiết từ các khoản thanh toán:
      
      Dữ liệu thanh toán: $dataStr
      
      Vui lòng cung cấp:
      1. Tóm tắt các chỉ số chính
      2. Các xu hướng và mẫu được xác định
      3. Cách tiếp cận để cải thiện
      4. Các khu vực rủi ro cần giám sát
      5. Khuyến nghị chi tiết
      ''';
      
      return await generateText(prompt);
    } catch (e) {
      logger.e('Error analyzing financial data', error: e);
      return null;
    }
  }

  /// Analyze occupancy data
  Future<String?> analyzeOccupancyData(String organizationId, String buildingId) async {
    try {
      logger.i('Analyzing occupancy data for building: $buildingId');
      
      // Fetch real room and tenant data
      final rooms = await getRoomsByBuilding(organizationId, buildingId);
      final tenants = await getTenantsByBuilding(organizationId, buildingId);
      
      if (rooms.isEmpty) {
        return 'Không có dữ liệu phòng để phân tích.';
      }
      
      final occupancyRate = (tenants.length / rooms.length) * 100;
      
      final prompt = '''
      Phân tích dữ liệu chiếm dụng của tòa nhà:
      
      - Tổng số phòng: ${rooms.length}
      - Phòng được thuê: ${tenants.length}
      - Tỷ lệ chiếm dụng: ${occupancyRate.toStringAsFixed(2)}%
      - Phòng trống: ${rooms.length - tenants.length}
      
      Vui lòng cung cấp:
      1. Phân tích tỷ lệ chiếm dụng
      2. Xu hướng và mẫu
      3. Cơ hội cải thiện
      4. Chiến lược tìm kiếm người thuê
      5. Khuyến nghị để tối đa hóa doanh thu
      ''';
      
      return await generateText(prompt);
    } catch (e) {
      logger.e('Error analyzing occupancy data', error: e);
      return null;
    }
  }

  /// Analyze tenant and payment trends
  Future<String?> analyzeTenantTrends(String organizationId, String buildingId) async {
    try {
      logger.i('Analyzing tenant trends for building: $buildingId');
      
      final tenants = await getTenantsByBuilding(organizationId, buildingId);
      final payments = await getPaymentsByBuilding(organizationId, buildingId);
      final outstandingPayments = await getOutstandingPayments(organizationId);
      
      final prompt = '''
      Phân tích xu hướng người thuê và thanh toán:
      
      - Tổng số người thuê: ${tenants.length}
      - Tổng thanh toán: ${payments.length}
      - Khoản thanh toán chưa thanh toán: ${outstandingPayments.length}
      
      Vui lòng cung cấp:
      1. Phân tích hành vi thanh toán
      2. Tỷ lệ tất toát nợ
      3. Xu hướng giữ chân người thuê
      4. Các cảnh báo sớm về độc tính
      5. Khuyến nghị khôi phục và dự phòng
      ''';
      
      return await generateText(prompt);
    } catch (e) {
      logger.e('Error analyzing tenant trends', error: e);
      return null;
    }
  }

  /// ========================================
  /// REPORT GENERATION (Xuat bao cao)
  /// ========================================

  /// Generate comprehensive building report
  Future<String?> generateBuildingReport(String organizationId, String buildingId) async {
    try {
      logger.i('Generating comprehensive building report for: $buildingId');
      
      // Fetch all relevant data
      final building = await getBuildingById(buildingId);
      final rooms = await getRoomsByBuilding(organizationId, buildingId);
      final tenants = await getTenantsByBuilding(organizationId, buildingId);
      final payments = await getPaymentsByBuilding(organizationId, buildingId);
      
      if (building == null) {
        return 'Không tìm thấy tòa nhà.';
      }
      
      final occupancyRate = rooms.isNotEmpty ? (tenants.length / rooms.length) * 100 : 0;
      
      final prompt = '''
      Tạo báo cáo tòa nhà toàn diện:
      
      Thông tin tòa nhà:
      - Tên: $building
      - Tổng phòng: ${rooms.length}
      - Phòng được thuê: ${tenants.length}
      - Tỷ lệ chiếm dụng: ${occupancyRate.toStringAsFixed(2)}%
      - Tổng thanh toán: ${payments.length}
      
      Báo cáo phải bao gồm:
      1. Tóm tắt điều hành
      2. Thống kê hiệu suất chính
      3. Phân tích chi tiết
      4. Khuyến nghị cải thiện
      5. Kết luận
      ''';
      
      return await generateText(prompt);
    } catch (e) {
      logger.e('Error generating building report', error: e);
      return null;
    }
  }

  /// Generate monthly financial report
  Future<String?> generateMonthlyFinancialReport(String organizationId, String buildingId) async {
    try {
      logger.i('Generating monthly financial report for: $buildingId');
      
      final payments = await getPaymentsByBuilding(organizationId, buildingId);
      
      if (payments.isEmpty) {
        return 'Không có dữ liệu thanh toán cho tháng này.';
      }
      
      final prompt = '''
      Tạo báo cáo tài chính hàng tháng:
      
      Dữ liệu thanh toán: $payments
      
      Báo cáo phải bao gồm:
      1. Tóm tắt doanh thu
      2. Doanh thu theo loại (tiền thuê, tiền điện, nước)
      3. Khoản thanh toán chưa thanh toán
      4. Xu hướng so với tháng trước
      5. Dự báo cho tháng tiếp theo
      6. Khuyến nghị hành động
      ''';
      
      return await generateText(prompt);
    } catch (e) {
      logger.e('Error generating monthly financial report', error: e);
      return null;
    }
  }

  /// Generate occupancy report
  Future<String?> generateOccupancyReport(String organizationId, String buildingId) async {
    try {
      logger.i('Generating occupancy report for: $buildingId');
      
      final rooms = await getRoomsByBuilding(organizationId, buildingId);
      final tenants = await getTenantsByBuilding(organizationId, buildingId);
      
      if (rooms.isEmpty) {
        return 'Không có dữ liệu phòng để tạo báo cáo.';
      }
      
      final occupancyRate = (tenants.length / rooms.length) * 100;
      
      final prompt = '''
      Tạo báo cáo chiếm dụng chi tiết:
      
      - Tổng phòng: ${rooms.length}
      - Phòng được thuê: ${tenants.length}
      - Phòng trống: ${rooms.length - tenants.length}
      - Tỷ lệ (%) : ${occupancyRate.toStringAsFixed(2)}%
      
      Báo cáo phải bao gồm:
      1. Phân tích tỷ lệ hiện tại
      2. Xu hướng lịch sử
      3. Dự báo chiếm dụng
      4. Phòng có vấn đề
      5. Chiến lược cải thiện chiếm dụng
      6. Dự báo doanh thu
      ''';
      
      return await generateText(prompt);
    } catch (e) {
      logger.e('Error generating occupancy report', error: e);
      return null;
    }
  }

  /// Stream comprehensive report generation
  Stream<String> generateReportStream(String organizationId, String buildingId, {String reportType = 'comprehensive'}) async* {
    try {
      logger.i('Starting streaming $reportType report for building: $buildingId');
      
      // Fetch data
      final building = await getBuildingById(buildingId);
      final rooms = await getRoomsByBuilding(organizationId, buildingId);
      final tenants = await getTenantsByBuilding(organizationId, buildingId);
      final payments = await getPaymentsByBuilding(organizationId, buildingId);
      
      if (building == null) {
        yield 'Không tìm thấy tòa nhà.';
        return;
      }
      
      final occupancyRate = rooms.isNotEmpty ? (tenants.length / rooms.length) * 100 : 0;
      
      final prompt = '''
      Tạo báo cáo $reportType toàn diện chi tiết:
      
      Thông tin tòa nhà:
      - Tên: $building
      - Tổng phòng: ${rooms.length}
      - Phòng được thuê: ${tenants.length}
      - Tỷ lệ chiếm dụng: ${occupancyRate.toStringAsFixed(2)}%
      - Tổng thanh toán: ${payments.length}
      
      Báo cáo phải bao gồm:
      1. Tóm tắt điều hành chi tiết
      2. Phân tích tài chính
      3. Phân tích chiếm dụng
      4. Phân tích xu hướng người thuê
      5. Khuyến nghị chiến lược
      6. Kết luận và hành động tiếp theo
      ''';
      
      final content = [Content.text(prompt)];
      final stream = _model.generateContentStream(content);
      
      await for (final response in stream) {
        final text = response.text ?? '';
        if (text.isNotEmpty) {
          yield text;
        }
      }
      logger.i('Streaming report generation completed');
    } catch (e) {
      logger.e('Error in streaming report generation', error: e);
      yield 'Lỗi: ${e.toString()}';
    }
  }

  /// ========================================
  /// UTILITY METHODS
  /// ========================================

  /// Check if AI service is properly configured
  bool get isConfigured => _apiKey.isNotEmpty;

  /// Get AI model info
  String getModelInfo() => 'Model: $_modelName, API Key Status: ${_apiKey.isNotEmpty ? 'Configured' : 'Not Configured'}';

  /// Dispose resources if needed
  void dispose() {
    logger.i('AI Agent Service disposed');
  }
}
