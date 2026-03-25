import 'package:flutter/material.dart';

class AppTranslations {
  final Locale locale;
  AppTranslations(this.locale);

  static AppTranslations of(BuildContext context) {
    return Localizations.of<AppTranslations>(context, AppTranslations)!;
  }

  static final Map<String, Map<String, String>> _values = {
    'vi': {
      // ── Existing keys ──────────────────────────────────────────────────────
      'lang': 'ngôn ngữ',
      'select_language': 'Chọn ngôn ngữ',
      'vietnamese': 'Tiếng Việt',
      'english': 'Tiếng Anh',
      'confirm': 'Xác nhận',
      'dashboard': 'Trang chủ',
      'logout': 'Đăng xuất',
      'update': 'Cập nhật',
      'your_organizations': 'Tổ Chức Của Bạn',
      'join': 'Tham gia',
      'tooltip_join': 'Tham gia tổ chức',
      'create': 'Tạo mới',
      'tooltip_create': 'Tạo tổ chức mới',
      'no_orgs': 'Chưa có tổ chức nào',
      'no_orgs_sub': 'Tạo tổ chức mới hoặc tham gia bằng mã mời',
      'hello': 'Xin chào!',
      'joined_at': 'Tham gia',
      'admin': 'Quản trị viên',
      'member': 'Thành viên',
      'available_update': 'Cập nhật có sẵn',
      'new_update_ready': 'Phiên bản mới đã sẵn sàng!',
      'click_update_button': 'Nhấn "Tải xuống" để mở trang tải xuống phiên bản mới.',
      'later': 'Để sau',
      'download': 'Tải xuống',
      'opening_download_page': 'Đang mở trang tải xuống...',
      'cannot_open_browser': 'Không thể mở trình duyệt. Vui lòng kiểm tra kết nối.',
      'updating': 'Đang cập nhật...',
      'update_success': 'Cập nhật thành công!',
      'update_failed': 'Không thể cập nhật. Vui lòng thử lại sau.',
      'org_name_required': 'Tên tổ chức *',
      'org_name_example': 'VD: Chung cư ABC',
      'please_enter_org_name': 'Vui lòng nhập tên tổ chức',
      'address': 'Địa chỉ',
      'address_example': 'VD: 123 Nguyễn Huệ, Q1, TP.HCM',
      'optional_on_invoice': 'Tùy chọn - Hiển thị trên hóa đơn',
      'phone': 'Số điện thoại',
      'phone_example': 'VD: 028-1234-5678',
      'email': 'Email',
      'email_example': 'VD: contact@abc.com',
      'email_invalid': 'Email không hợp lệ',
      'contact_info_on_invoice': 'Thông tin liên hệ sẽ hiển thị trên hóa đơn PDF',
      'cancel': 'Huỷ',
      'org_created_success': 'Tạo tổ chức thành công!',
      'create_action': 'Tạo',
      'enter_invite_code': 'Nhập mã mời 8 ký tự để tham gia tổ chức',
      'invite_code': 'Mã mời',
      'invite_code_example': 'VD: A3F7B2C9',
      'invite_code_8_chars': 'Mã mời phải có 8 ký tự',
      'join_org_success': 'Tham gia tổ chức thành công!',
      'invite_code_invalid': 'Mã mời không hợp lệ hoặc bạn đã là thành viên',
      'leave_org': 'Rời khỏi tổ chức',
      'leave_org_confirm': 'Bạn có chắc chắn muốn rời khỏi tổ chức "{{name}}"?',
      'lose_access_warning': 'Bạn sẽ mất quyền truy cập vào tất cả dữ liệu của tổ chức này.',
      'leave_action': 'Rời khỏi',
      'leaving_org': 'Đang rời khỏi tổ chức...',
      'left_org_success': 'Đã rời khỏi tổ chức thành công!',
      'cannot_leave_org': 'Không thể rời khỏi tổ chức. Bạn có thể là quản trị viên cuối cùng.',
      'delete_org': 'Xóa tổ chức',
      'delete_org_warning': 'Hành động này sẽ XÓA VĨNH VIỄN tổ chức "{{name}}" và TẤT CẢ dữ liệu liên quan bao gồm:',
      'all_buildings': 'Tất cả tòa nhà',
      'all_rooms': 'Tất cả phòng',
      'all_tenants': 'Tất cả người thuê',
      'all_payments': 'Tất cả thanh toán',
      'all_members': 'Tất cả thành viên',
      'warning_cannot_undo': 'CẢNH BÁO: Hành động này KHÔNG THỂ HOÀN TÁC!',
      'confirm_enter_org_name': 'Để xác nhận, vui lòng nhập tên tổ chức:',
      'name_mismatch': 'Tên không khớp',
      'delete_permanently': 'XÓA VĨNH VIỄN',
      'deleting_org': 'Đang xóa tổ chức...',
      'please_dont_close': 'Vui lòng không đóng ứng dụng',
      'deleted_org_success': 'Đã xóa tổ chức thành công!',
      'cannot_delete_org': 'Không thể xóa tổ chức. Vui lòng thử lại.',
      'org_info': 'Thông tin tổ chức',
      'org_name_label': 'Tên tổ chức:',
      'created_date': 'Ngày tạo:',
      'id': 'ID:',
      'last_updated': 'Cập nhật lần cuối:',
      'address_label': 'Địa chỉ:',
      'phone_label': 'Số điện thoại:',
      'email_label': 'Email:',
      'bank_name': 'Tên ngân hàng:',
      'account_number': 'Số tài khoản:',
      'account_holder': 'Chủ tài khoản:',
      'tax_code': 'Mã số thuế',
      'close': 'Đóng',
      'migrate_and_delete': 'Di chuyển & xóa tổ chức',
      'migrate_org_data': 'Di chuyển dữ liệu tổ chức',
      'source_org_info': 'Thông tin tổ chức nguồn:',
      'name_with_value': 'Tên: {{name}}',
      'id_with_value': 'ID: {{id}}',
      'target_org_id': 'ID tổ chức đích',
      'enter_target_org_id': 'Nhập ID tổ chức đích nơi muốn di chuyển',
      'target_org_id_placeholder': 'ID của tổ chức đích (không phải tên)',
      'preview_data_migrate': 'Xem trước dữ liệu sẽ di chuyển:',
      'preview_stats': 'Tòa nhà: {{buildings}}, Phòng: {{rooms}}, Người thuê: {{tenants}}, Thanh toán: {{payments}}',
      'please_enter_target_id': 'Vui lòng nhập ID tổ chức đích.',
      'fetching_preview': 'Đang lấy xem trước...',
      'fetched_preview': 'Đã lấy xem trước.',
      'preview_error': 'Lỗi khi lấy xem trước: {{error}}',
      'preview': 'Xem trước',
      'migrating_and_deleting': 'Đang di chuyển và xóa...',
      'migrating_data': 'Đang di chuyển dữ liệu...',
      'error': 'Lỗi: {{error}}',
      'migrated_and_deleted_success': 'Đã di chuyển và xóa tổ chức thành công!',
      'migrated_data_success': 'Đã di chuyển dữ liệu thành công!',
      'operation_failed': 'Thao tác thất bại.',
      'migrate_and_delete_action': 'Di chuyển & XÓA',
      'migrate_action': 'Di chuyển',
      'open_org': 'Mở tổ chức',
      'view_org_info': 'Xem thông tin tổ chức',
      'org_details_and_id': 'Chi tiết tổ chức và ID',
      'migrate_to_other_org': 'Di chuyển dữ liệu sang tổ chức khác',
      'copy_all_data': 'Sao chép toàn bộ dữ liệu sang tổ chức khác',
      'migrate_and_delete_org': 'Di chuyển & xóa tổ chức',
      'transfer_and_delete': 'Chuyển dữ liệu và xóa tổ chức này',
      'delete_org_action': 'Xóa tổ chức',
      'delete_org_permanently': 'Xóa vĩnh viễn tổ chức và tất cả dữ liệu',
      'leave_org_action': 'Rời khỏi tổ chức',
      'will_lose_access': 'Bạn sẽ mất quyền truy cập',
      'confirm_logout': 'Xác nhận đăng xuất',
      'confirm_logout_message': 'Bạn có chắc chắn muốn đăng xuất?',
      'window_size_too_small': 'Kích thước cửa sổ quá nhỏ',
      'minimum_size': 'Kích thước tối thiểu: {{width}}x{{height}}',
      'current_size': 'Hiện tại: {{width}}x{{height}}',
      'user_data_not_found': 'Không tìm thấy dữ liệu người dùng',
      'logout_action': 'Đăng xuất',
      'org_options': 'Tùy chọn tổ chức',
      'day_hint': 'Ngày',
      'month_hint': 'Tháng',
      'year_hint': 'Năm',
      'select_from_calendar': 'Chọn từ lịch',
      'please_enter_date': 'Vui lòng nhập ngày',
      'date_must_be_between': 'Ngày phải từ {{first}} đến {{last}}',
      'buildings_tab': 'Toà nhà',
      'tenants_tab': 'Người thuê',
      'payments_tab': 'Hóa đơn',
      'statistics_tab': 'Thống kê',
      'members_tab': 'Thành viên',
      'add_building': 'Thêm toà nhà',
      'no_buildings': 'Không tìm thấy toà nhà nào',
      'edit': 'Chỉnh sửa',
      'delete': 'Xoá',
      'manage_rooms': 'Quản lý phòng',
      'created_at': 'Tạo lúc',
      'no_payments': 'Chưa có hóa đơn nào',
      'add_payment': 'Thêm Hóa Đơn',
      'add': 'Thêm',
      'search_payments': 'Tìm kiếm hóa đơn...',
      'found_payments': 'Tìm thấy {{count}} hóa đơn',
      'tenant_label': 'Người thuê',
      'amount_label': 'Số tiền',
      'due_date_label': 'Hạn',
      'view_details': 'Xem Chi Tiết',
      'no_data': 'Không có dữ liệu',
      'overview': 'Tổng quan',
      'total_buildings': 'Toà nhà',
      'total_tenants': 'Người thuê',
      'paid_payments': 'Đã thanh toán',
      'pending_payments_label': 'Chưa thanh toán',
      'overdue_payments': 'Quá hạn',
      'total_payments_label': 'Tổng hóa đơn',
      'revenue': 'Doanh thu',
      'collected': 'Đã thu',
      'uncollected': 'Chưa thu',
      'monthly_revenue': 'Doanh thu theo tháng',
      'occupancy_by_building': 'Tỷ lệ lấp đầy theo toà nhà hiện tại',
      'occupancy_trend': 'Xu hướng lấp đầy theo tháng',
      'export_excel': 'Xuất Excel',
      'export_pdf': 'Xuất PDF',
      'filter_by_building': 'Lọc theo toà nhà:',
      'all_buildings_option': 'Tất cả toà nhà',
      'select_building': 'Chọn toà nhà',
      'no_building_data': 'Chưa có dữ liệu toà nhà',
      'occupancy_rate': 'Tỷ lệ lấp đầy (%)',
      'no_building_data_selected': 'Chưa có dữ liệu cho toà nhà này',
      'get_invite_code': 'Lấy mã mời',
      'refresh_code': 'Làm mới mã',
      'refresh_invite_code_title': 'Làm mới mã mời?',
      'refresh_invite_code_body': 'Mã mời cũ sẽ không còn hoạt động nữa. Những người chưa tham gia cần mã mới. Bạn có chắc muốn tiếp tục?',
      'refresh_action': 'Làm mới',
      'code_refreshed': 'Mã mời đã được làm mới',
      'cannot_refresh_code': 'Không thể làm mới mã mời',
      'invite_code_label': 'Mã mời',
      'members_title': 'Thành viên',
      'no_members': 'Không tìm thấy thành viên.',
      'promote_to_admin': 'Thăng cấp Admin',
      'remove_from_org': 'Xóa khỏi tổ chức',
      'confirm_remove': 'Xác nhận xóa',
      'confirm_remove_body': 'Bạn có chắc muốn xóa {{name}} khỏi tổ chức?',
      'member_removed': 'Đã xóa thành viên',
      'promoted_to_admin': 'Đã thăng cấp thành admin',
      'delete_building_title': 'Xóa Toà Nhà',
      'delete_building_confirm': 'Bạn có chắc muốn xóa "{{name}}"?',
      'delete_action_will': 'Thao tác này sẽ:',
      'delete_all_rooms': 'Xóa tất cả phòng trong toà nhà',
      'mark_tenants_moved': 'Đánh dấu {{count}} người thuê là "Đã chuyển đi"',
      'tenant_data_preserved': 'Thông tin người thuê sẽ được lưu giữ để tham khảo',
      'add_building_success': 'Thêm toà nhà thành công',
      'add_building_rooms_success': 'Thêm toà nhà và {{count}} phòng thành công',
      'update_building_success': 'Cập nhật toà nhà thành công',
      'update_building_rooms_success': 'Cập nhật toà nhà và thêm {{count}} phòng thành công',
      'min_window_size': 'Kích thước cửa sổ quá nhỏ',
      'downloading_update': 'Đang tải xuống bản cập nhật',
      'connecting': 'Đang kết nối',

      // ── Organization Screen – Buildings tab ────────────────────────────────
      'delete_building_rooms_removed': 'phòng đã bị xóa',
      'delete_building_tenants_moved': 'người thuê đã được đánh dấu "Đã chuyển đi"',
      'building_deleted_summary': 'Đã xóa toà nhà\n• {{rooms}} phòng đã bị xóa\n• {{tenants}} người thuê đã được đánh dấu "Đã chuyển đi"',
      'cannot_delete_building': 'Không thể xóa toà nhà',
      'delete_building_error': 'Lỗi: {{error}}',
      'loading': 'Đang tải...',

      // ── Organization Screen – Payments tab ─────────────────────────────────
      'search_payments_hint': 'Tìm kiếm hóa đơn...',
      'no_payments_found': 'Không tìm thấy hóa đơn',
      'found_count_payments': 'Tìm thấy {{count}} hóa đơn',
      'edit_payment': 'Chỉnh Sửa',
      'delete_payment': 'Xóa',
      'payment_type_rent': 'Tiền thuê',
      'payment_type_electricity': 'Tiền điện',
      'payment_type_water': 'Tiền nước',
      'payment_type_internet': 'Tiền internet',
      'payment_type_parking': 'Tiền gửi xe',
      'payment_type_maintenance': 'Phí bảo trì',
      'payment_type_deposit': 'Tiền cọc',
      'payment_type_penalty': 'Tiền phạt',
      'payment_type_other': 'Khác',

      // ── Organization Screen – Statistics tab ───────────────────────────────
      'stat_overview_title': 'Tổng quan',
      'stat_buildings': 'Toà nhà',
      'stat_tenants': 'Người thuê',
      'stat_paid': 'Đã thanh toán',
      'stat_pending': 'Chưa thanh toán',
      'stat_overdue': 'Quá hạn',
      'stat_total_payments': 'Tổng hóa đơn',
      'stat_revenue_title': 'Doanh thu',
      'stat_collected': 'Đã thu',
      'stat_uncollected': 'Chưa thu',
      'stat_monthly_revenue': 'Doanh thu theo tháng',
      'stat_occupancy_by_building': 'Tỷ lệ lấp đầy theo toà nhà hiện tại',
      'stat_occupancy_trend': 'Xu hướng lấp đầy theo tháng',
      'stat_no_revenue_data': 'Chưa có dữ liệu doanh thu',
      'stat_no_building_data': 'Chưa có dữ liệu toà nhà',
      'stat_no_building_selected': 'Chưa có dữ liệu cho toà nhà này',
      'stat_filter_by_building': 'Lọc theo toà nhà:',
      'stat_all_buildings': 'Tất cả toà nhà',
      'stat_select_building': 'Chọn tòa nhà',
      'stat_occupancy_rate': 'Tỷ lệ lấp đầy (%)',
      'stat_no_data': 'Không có dữ liệu',

      // ── Organization Screen – Members tab ──────────────────────────────────
      'member_role_admin': 'Quản trị viên',
      'member_role_member': 'Thành viên',
      'member_promote_confirm_title': 'Thăng cấp Admin',
      'member_promote_confirm_body': 'Bạn có chắc muốn thăng cấp {{name}} thành admin?',
      'member_remove_confirm_title': 'Xác nhận xóa',
      'member_remove_confirm_body': 'Bạn có chắc muốn xóa {{name}} khỏi tổ chức?',
      'member_promoted_success': 'Đã thăng cấp thành admin',
      'member_removed_success': 'Đã xóa thành viên',

      // ── PDF / Excel export ─────────────────────────────────────────────────
      'export_cancelled': 'Hủy xuất PDF',
      'export_pdf_saved': 'Đã lưu PDF: {{filename}}',
      'export_pdf_error': 'Lỗi khi xuất PDF: {{error}}',
      'export_excel_saved': 'Đã lưu Excel: {{filename}}',
      'export_excel_success': 'Tệp Excel đã được tạo thành công',
      'export_excel_error': 'Lỗi khi xuất Excel: {{error}}',
      // PDF report headings
      'pdf_report_title': 'BÁO CÁO THỐNG KÊ TỔNG QUAN',
      'pdf_created_at': 'Ngày tạo: {{date}}',
      'pdf_section_overview': '1. TỔNG QUAN',
      'pdf_section_tenant_status': '2. TÌNH TRẠNG NGƯỜI THUÊ',
      'pdf_section_payment_summary': '3. TỔNG KẾT THANH TOÁN',
      'pdf_total_buildings': 'Toà nhà',
      'pdf_total_rooms': 'Tổng phòng',
      'pdf_active_tenants': 'Đang thuê',
      'pdf_occupancy_rate': 'Tỷ lệ lấp đầy',
      'pdf_empty_rooms': 'Phòng trống',
      'pdf_moved_out': 'Đã chuyển đi',
      'pdf_tenant_status_active': 'Đang hoạt động',
      'pdf_tenant_status_inactive': 'Không hoạt động',
      'pdf_tenant_status_moved': 'Đã chuyển đi',
      'pdf_tenant_status_suspended': 'Bị đình chỉ',
      'pdf_tenant_status_total': 'TỔNG',
      'pdf_tenant_col_status': 'Trạng thái',
      'pdf_tenant_col_count': 'Số lượng',
      'pdf_tenant_col_rate': 'Tỷ lệ',
      'pdf_collected': 'Đã thu',
      'pdf_uncollected': 'Chưa thu',
      'pdf_overdue': 'Quá hạn',
      'pdf_cancelled': 'Đã hủy',
      'pdf_invoices': '{{count}} hóa đơn',
      'pdf_auto_generated': 'Báo cáo được tạo tự động',
      'pdf_page': 'Trang {{n}}',
      'pdf_building_detail_title': 'CHI TIẾT THEO TÒA NHÀ',
      'pdf_building_col_name': 'Toà nhà',
      'pdf_building_col_total': 'Tổng phòng',
      'pdf_building_col_occupied': 'Đang thuê',
      'pdf_building_col_empty': 'Trống',
      'pdf_building_col_rate': 'Tỷ lệ',
      'pdf_building_col_revenue': 'Doanh thu',
      'pdf_building_grand_total': 'TỔNG CỘNG',
      'pdf_no_building_data': 'Không có dữ liệu toà nhà',
      'pdf_revenue_title': 'PHÂN TÍCH DOANH THU',
      'pdf_revenue_6months': 'Doanh thu 6 tháng gần nhất',
      'pdf_revenue_detail': 'Chi tiết doanh thu theo tháng',
      'pdf_revenue_col_month': 'Tháng',
      'pdf_revenue_col_amount': 'Doanh thu',
      'pdf_revenue_col_rate': 'Tỷ lệ',
      // Excel sheet names & headings
      'excel_sheet_summary': 'Tổng Quan',
      'excel_sheet_building': 'Chi Tiết Tòa Nhà',
      'excel_sheet_payments': 'Thanh Toán Chi Tiết',
      'excel_summary_title': 'BÁO CÁO THỐNG KÊ TỔNG QUAN',
      'excel_building_title': 'CHI TIẾT THEO TÒA NHÀ',
      'excel_payments_title': 'DANH SÁCH THANH TOÁN CHI TIẾT',
      'excel_col_invoice_id': 'Mã hóa đơn',
      'excel_col_tenant': 'Người thuê',
      'excel_col_amount': 'Số tiền',
      'excel_col_status': 'Trạng thái',
      'excel_col_paid_date': 'Ngày thanh toán',
      'excel_col_due_date': 'Hạn thanh toán',
      'excel_grand_total': 'TỔNG CỘNG',
      'excel_created_at': 'Ngày tạo: {{date}}',
      'excel_stat_buildings': 'Toà nhà',
      'excel_stat_rooms': 'Tổng phòng',
      'excel_stat_rented': 'Đang thuê',
      'excel_stat_occupancy': 'Tỷ lệ lấp đầy',
      'excel_stat_empty': 'Phòng trống',
      'excel_stat_moved_out': 'Đã chuyển đi',

      // ── Building Dialog ───────────────────────────────────────────────────
      'building_dialog_title_add': 'Thêm Toà Nhà',
      'building_dialog_title_edit': 'Sửa Toà Nhà',
 
      // Form fields
      'building_name_label': 'Tên toà nhà *',
      'building_name_hint': 'VD: Toà A',
      'building_address_label': 'Địa chỉ *',
      'building_address_hint': 'VD: 123 Đường ABC',
      'building_auto_generate_rooms': 'Tự động tạo phòng',
      'building_floors_label': 'Số tầng *',
      'building_room_prefix_label': 'Tiền tố số phòng',
 
      // Toggle buttons
      'building_uniform': 'Đồng đều',
      'building_custom': 'Tùy chỉnh',
 
      // Uniform section
      'building_rooms_per_floor_label': 'Số phòng mỗi tầng',
      'building_room_type_label': 'Loại phòng',
      'building_room_type_standard': 'Tiêu chuẩn',
      'building_area_label': 'Diện tích (m²)',
 
      // Custom / per-floor section
      'building_floor_config_title': 'Cấu hình tầng',
      'building_bulk_edit': 'Chỉnh hàng loạt',
      'building_bulk_close': 'Đóng',
      'building_bulk_from_floor': 'Từ tầng',
      'building_bulk_to_floor': 'Đến tầng',
      'building_bulk_rooms': 'Số phòng',
      'building_bulk_type': 'Loại',
      'building_bulk_area': 'm²',
      'building_bulk_apply': 'Áp dụng hàng loạt',
 
      // Floor row columns
      'building_col_count': 'SL',
      'building_col_type': 'Loại',
      'building_col_area': 'm²',
 
      // Custom room names dialog
      'building_set_room_names_tooltip': 'Đặt tên phòng',
      'building_enter_room_count_first': 'Vui lòng nhập số lượng phòng trước',
      'building_custom_names_title': 'Tên phòng tầng {{floor}}',
      'building_room_label': 'Phòng {{n}}',
      'building_room_name_hint': 'VD: Phòng VIP, Studio A...',
      'building_save': 'Lưu',
 
      // Action buttons
      'building_action_add': 'Thêm',
      'building_action_update': 'Cập nhật',
 
      // Validation errors
      'building_error_name_required': 'Vui lòng nhập tên toà nhà',
      'building_error_address_required': 'Vui lòng nhập địa chỉ',
      'building_error_floors_invalid': 'Vui lòng nhập số tầng hợp lệ',
      'building_error_floors_required': 'Vui lòng nhập số tầng',
      'building_error_floors_positive': 'Số tầng phải lớn hơn 0',
      'building_error_rooms_invalid': 'Vui lòng nhập số phòng mỗi tầng hợp lệ',
      'building_error_rooms_required': 'Vui lòng nhập số phòng',
      'building_error_rooms_positive': 'Số phòng phải lớn hơn 0',
    
      // ── Tenants Tab ───────────────────────────────────────────────────────
 
      // General
      'tenant_no_data': 'Không có dữ liệu',
      'tenant_unknown': 'Không xác định',
 
      // Search bar
      'tenant_search_hint': 'Tìm kiếm theo tên, SĐT, email, nghề nghiệp...',
      'tenant_no_tenants': 'Chưa có người thuê nào',
      'tenant_no_results': 'Không tìm thấy kết quả',
      'tenant_try_other_keyword': 'Thử tìm kiếm với từ khóa khác',
      'tenant_found_results': 'Tìm thấy {{count}} kết quả',
 
      // Add button
      'tenant_add_button': 'Thêm người thuê',
 
      // Tenant card
      'tenant_main_tenant_badge': 'Chủ phòng',
      'tenant_location_label': 'Vị trí',
      'tenant_previous_location_label': 'Vị trí trước đây',
      'tenant_location_value': '{{building}} - Phòng {{room}}',
      'tenant_status_label': 'Trạng thái:',
      'tenant_vehicle_count': '{{count}} phương tiện',
      'tenant_options_tooltip': 'Tùy chọn',
 
      // Detail dialog – section headings
      'tenant_detail_location': 'Vị trí',
      'tenant_detail_previous_location': 'Vị trí trước đây',
      'tenant_detail_building': 'Toà nhà',
      'tenant_detail_room': 'Phòng',
      'tenant_detail_contact_section': 'Thông tin liên hệ',
      'tenant_detail_phone': 'Số điện thoại',
      'tenant_detail_email': 'Email',
      'tenant_detail_personal_section': 'Thông tin cá nhân',
      'tenant_detail_gender': 'Giới tính',
      'tenant_detail_national_id': 'CMND/CCCD',
      'tenant_detail_occupation': 'Nghề nghiệp',
      'tenant_detail_workplace': 'Nơi làm việc',
      'tenant_detail_rental_section': 'Thông tin thuê',
      'tenant_detail_move_in_date': 'Ngày vào ở',
      'tenant_detail_days_living': 'Số ngày ở',
      'tenant_detail_days_value': '{{days}} ngày',
      'tenant_detail_monthly_rent': 'Tiền thuê',
      'tenant_detail_deposit': 'Tiền cọc',
      'tenant_detail_apartment_type': 'Loại căn hộ',
      'tenant_detail_area': 'Diện tích',
      'tenant_detail_area_value': '{{area}} m²',
      'tenant_detail_moveout_section': 'Thông tin chuyển đi',
      'tenant_detail_move_out_date': 'Ngày chuyển đi',
      'tenant_detail_duration': 'Thời gian ở',
      'tenant_detail_reason': 'Lý do',
      'tenant_detail_notes': 'Ghi chú',
      'tenant_detail_contract_section': 'Hợp đồng',
      'tenant_detail_contract_start': 'Bắt đầu',
      'tenant_detail_contract_end': 'Kết thúc',
      'tenant_detail_contract_end_date': 'Ngày kết thúc hợp đồng',
      'tenant_detail_contract_status': 'Trạng thái hợp đồng',
      'tenant_detail_early_termination': 'Chấm dứt sớm',
      'tenant_detail_end_label': 'Kết thúc',
      'tenant_detail_days_early': '{{days}} ngày trước hạn',
      'tenant_detail_on_time': 'Đúng thời hạn hợp đồng',
      'tenant_detail_remaining': 'Còn lại',
      'tenant_detail_vehicles_section': 'Phương tiện ({{count}})',
      'tenant_detail_history_section': 'Lịch sử thuê ({{count}})',
      'tenant_detail_history_dates': 'Từ {{from}} đến {{to}}',
      'tenant_detail_status': 'Trạng thái',
 
      // Options label (bottom sheet / dialog title)
      'tenant_options_label': 'Tùy chọn',
 
      // Options menu items
      'tenant_menu_view_detail': 'Xem chi tiết',
      'tenant_menu_edit': 'Chỉnh sửa thông tin',
      'tenant_menu_move_room': 'Chuyển phòng',
      'tenant_menu_move_out': 'Chuyển đi',
      'tenant_menu_vehicles': 'Quản lý phương tiện',
      'tenant_menu_rental_history': 'Lịch sử thuê phòng',
      'tenant_menu_delete': 'Xóa',
 
      // Vehicle management dialog
      'tenant_vehicle_manage_title': 'Quản lý phương tiện',
      'tenant_vehicle_add_tooltip': 'Thêm phương tiện',
      'tenant_vehicle_empty': 'Chưa có phương tiện nào',
      'tenant_vehicle_added': 'Đã thêm phương tiện',
      'tenant_vehicle_add_error': 'Lỗi: Không thể thêm phương tiện',
      'tenant_vehicle_updated': 'Đã cập nhật',
      'tenant_vehicle_parking_registered': 'Đã đăng ký bãi đỗ',
      'tenant_vehicle_parking_unregistered': 'Đã hủy bãi đỗ',
      'tenant_vehicle_deleted': 'Đã xóa phương tiện',
      'tenant_vehicle_parking_spot': 'Bãi đỗ: {{spot}}',
      'tenant_error': 'Lỗi: {{error}}',
 
      // Vehicle popup menu
      'tenant_vehicle_menu_edit': 'Chỉnh sửa',
      'tenant_vehicle_menu_register_parking': 'Đăng ký bãi đỗ',
      'tenant_vehicle_menu_unregister_parking': 'Hủy bãi đỗ',
      'tenant_vehicle_menu_delete': 'Xóa',
 
      // Vehicle delete confirm dialog
      'tenant_vehicle_delete_title': 'Xóa phương tiện',
      'tenant_vehicle_delete_confirm': 'Xóa phương tiện {{plate}}?',
 
      // Add / Edit vehicle dialogs
      'tenant_vehicle_add_title': 'Thêm phương tiện',
      'tenant_vehicle_edit_title': 'Chỉnh sửa phương tiện',
      'tenant_vehicle_plate_label': 'Biển số xe *',
      'tenant_vehicle_type_label': 'Loại xe *',
      'tenant_vehicle_brand_label': 'Hãng xe',
      'tenant_vehicle_model_label': 'Model',
      'tenant_vehicle_color_label': 'Màu sắc',
      'tenant_vehicle_color_hint': 'Đen, Trắng, Xanh...',
      'tenant_vehicle_plate_required': 'Vui lòng nhập biển số xe',
      'tenant_vehicle_add_action': 'Thêm',
      'tenant_vehicle_save_action': 'Lưu',
 
      // Vehicle types
      'tenant_vehicle_motorcycle': 'Xe máy',
      'tenant_vehicle_car': 'Ô tô',
      'tenant_vehicle_bicycle': 'Xe đạp',
      'tenant_vehicle_electric_bike': 'Xe đạp điện',
      'tenant_vehicle_other': 'Khác',
 
      // Parking spot dialog
      'tenant_parking_register_title': 'Đăng ký bãi đỗ',
      'tenant_parking_spot_label': 'Vị trí bãi đỗ',
      'tenant_parking_spot_required': 'Vui lòng nhập vị trí',
      'tenant_parking_register_action': 'Đăng ký',
 
      // Rental history dialog
      'tenant_rental_history_title': 'Lịch sử thuê phòng',
      'tenant_rental_history_empty': 'Không có lịch sử thuê',
 
      // Edit tenant dialog
      'tenant_edit_title': 'Chỉnh sửa thông tin',
      'tenant_edit_save': 'Lưu thay đổi',
      'tenant_section_invoice_apt': 'Hóa đơn & Căn hộ',
 
      // Shared field labels
      'tenant_field_name': 'Họ và tên',
      'tenant_field_name_required': 'Họ và tên *',
      'tenant_field_phone': 'Số điện thoại',
      'tenant_field_phone_required': 'Số điện thoại *',
      'tenant_field_email': 'Email',
      'tenant_field_national_id': 'CMND/CCCD',
      'tenant_field_occupation': 'Nghề nghiệp',
      'tenant_field_workplace': 'Nơi làm việc',
      'tenant_field_rent': 'Giá thuê',
      'tenant_field_rent_required': 'Tiền thuê hàng tháng *',
      'tenant_field_apt_type': 'Loại căn hộ',
      'tenant_field_area': 'Diện tích',
      'tenant_field_move_in_date': 'Ngày chuyển vào',
      'tenant_field_building': 'Toà nhà *',
      'tenant_field_room': 'Phòng *',
      'tenant_field_status': 'Trạng thái',
      'tenant_field_main_tenant': 'Chủ hộ',
 
      // Status dropdown values (for add dialog)
      'tenant_status_active': 'Đang ở',
      'tenant_status_inactive': 'Tạm ngưng',
      'tenant_status_moved_out': 'Đã dọn đi',
 
      // Room dropdown labels
      'tenant_room_occupied': 'Phòng {{number}} (Đã thuê)',
      'tenant_room_vacant': 'Phòng {{number}} (Trống)',
 
      // Add tenant dialog
      'tenant_add_title': 'Thêm Người Thuê',
      'tenant_add_action': 'Thêm mới',
 
      // Move room dialog
      'tenant_move_room_title': 'Chuyển phòng mới',
      'tenant_move_room_building': 'Chọn Toà nhà',
      'tenant_move_room_room': 'Chọn Phòng',
      'tenant_move_room_confirm': 'Xác nhận chuyển',
      'tenant_move_room_success': 'Đã chuyển phòng thành công',
      'tenant_move_room_error': 'Lỗi: Không thể chuyển phòng',
 
      // Move out dialog
      'tenant_moveout_title': 'Đánh dấu đã chuyển đi',
      'tenant_moveout_confirm': 'Đánh dấu {{name}} là đã chuyển đi?',
      'tenant_moveout_date_label': 'Ngày chuyển đi',
      'tenant_moveout_reason_label': 'Lý do',
      'tenant_moveout_reason_1': 'Chuyển đi',
      'tenant_moveout_reason_2': 'Hết hạn hợp đồng',
      'tenant_moveout_reason_3': 'Chấm dứt hợp đồng sớm',
      'tenant_moveout_reason_4': 'Vi phạm hợp đồng',
      'tenant_moveout_reason_5': 'Khác',
      'tenant_moveout_early_warning': 'Chấm dứt sớm {{days}} ngày',
      'tenant_moveout_confirm_action': 'Xác nhận',
      'tenant_moveout_success': 'Đã đánh dấu chuyển đi',
      'tenant_moveout_failed': 'Thất bại',
 
      // Delete tenant
      'tenant_delete_title': 'Xóa người thuê',
      'tenant_delete_confirm': 'Bạn có chắc muốn xóa {{name}}? Hành động này không thể hoàn tác.',
      'tenant_delete_success': 'Đã xóa',
      'tenant_delete_failed': 'Xóa thất bại',
    },

    'en': {
      // ── Existing keys ──────────────────────────────────────────────────────
      'lang': 'language',
      'select_language': 'Select Language',
      'vietnamese': 'Vietnamese',
      'english': 'English',
      'confirm': 'Confirm',
      'dashboard': 'Dashboard',
      'logout': 'Logout',
      'update': 'Update',
      'your_organizations': 'Your Organizations',
      'join': 'Join',
      'tooltip_join': 'Join an existing organization',
      'create': 'Create',
      'tooltip_create': 'Create a new organization',
      'no_orgs': 'No organizations yet',
      'no_orgs_sub': 'Create a new organization or join with an invite code',
      'hello': 'Hello!',
      'joined_at': 'Joined',
      'admin': 'Admin',
      'member': 'Member',
      'available_update': 'Update is available',
      'new_update_ready': 'New Update is ready!',
      'click_update_button': 'Click "Download" to open the page for downloading the new version.',
      'later': 'Later',
      'download': 'Download',
      'opening_download_page': 'Opening download page...',
      'cannot_open_browser': 'Cannot open browser. Please check your connection.',
      'updating': 'Updating...',
      'update_success': 'Update successful!',
      'update_failed': 'Cannot update. Please try again later.',
      'org_name_required': 'Organization Name *',
      'org_name_example': 'E.g.: ABC Apartment',
      'please_enter_org_name': 'Please enter organization name',
      'address': 'Address',
      'address_example': 'E.g.: 123 Main St, District 1, HCMC',
      'optional_on_invoice': 'Optional - Display on invoice',
      'phone': 'Phone Number',
      'phone_example': 'E.g.: 028-1234-5678',
      'email': 'Email',
      'email_example': 'E.g.: contact@abc.com',
      'email_invalid': 'Invalid email',
      'contact_info_on_invoice': 'Contact information will be displayed on PDF invoice',
      'cancel': 'Cancel',
      'org_created_success': 'Organization created successfully!',
      'create_action': 'Create',
      'enter_invite_code': 'Enter 8-character invite code to join organization',
      'invite_code': 'Invite Code',
      'invite_code_example': 'E.g.: A3F7B2C9',
      'invite_code_8_chars': 'Invite code must be 8 characters',
      'join_org_success': 'Joined organization successfully!',
      'invite_code_invalid': 'Invalid invite code or you are already a member',
      'leave_org': 'Leave Organization',
      'leave_org_confirm': 'Are you sure you want to leave "{{name}}"?',
      'lose_access_warning': 'You will lose access to all data of this organization.',
      'leave_action': 'Leave',
      'leaving_org': 'Leaving organization...',
      'left_org_success': 'Left organization successfully!',
      'cannot_leave_org': 'Cannot leave organization. You may be the last admin.',
      'delete_org': 'Delete Organization',
      'delete_org_warning': 'This action will PERMANENTLY DELETE organization "{{name}}" and ALL related data including:',
      'all_buildings': 'All buildings',
      'all_rooms': 'All rooms',
      'all_tenants': 'All tenants',
      'all_payments': 'All payments',
      'all_members': 'All members',
      'warning_cannot_undo': 'WARNING: This action CANNOT BE UNDONE!',
      'confirm_enter_org_name': 'To confirm, please enter the organization name:',
      'name_mismatch': 'Name does not match',
      'delete_permanently': 'DELETE PERMANENTLY',
      'deleting_org': 'Deleting organization...',
      'please_dont_close': 'Please do not close the app',
      'deleted_org_success': 'Organization deleted successfully!',
      'cannot_delete_org': 'Cannot delete organization. Please try again.',
      'org_info': 'Organization Information',
      'org_name_label': 'Organization Name:',
      'created_date': 'Created Date:',
      'id': 'ID:',
      'last_updated': 'Last Updated:',
      'address_label': 'Address:',
      'phone_label': 'Phone:',
      'email_label': 'Email:',
      'bank_name': 'Bank Name:',
      'account_number': 'Account Number:',
      'account_holder': 'Account Holder:',
      'tax_code': 'Tax Code',
      'close': 'Close',
      'migrate_and_delete': 'Migrate & Delete Organization',
      'migrate_org_data': 'Migrate Organization Data',
      'source_org_info': 'Source organization information:',
      'name_with_value': 'Name: {{name}}',
      'id_with_value': 'ID: {{id}}',
      'target_org_id': 'Target Organization ID',
      'enter_target_org_id': 'Enter target organization ID where you want to migrate',
      'target_org_id_placeholder': 'ID of target organization (not name)',
      'preview_data_migrate': 'Preview data to migrate:',
      'preview_stats': 'Buildings: {{buildings}}, Rooms: {{rooms}}, Tenants: {{tenants}}, Payments: {{payments}}',
      'please_enter_target_id': 'Please enter target organization ID.',
      'fetching_preview': 'Fetching preview...',
      'fetched_preview': 'Preview fetched.',
      'preview_error': 'Error fetching preview: {{error}}',
      'preview': 'Preview',
      'migrating_and_deleting': 'Migrating and deleting...',
      'migrating_data': 'Migrating data...',
      'error': 'Error: {{error}}',
      'migrated_and_deleted_success': 'Organization migrated and deleted successfully!',
      'migrated_data_success': 'Data migrated successfully!',
      'operation_failed': 'Operation failed.',
      'migrate_and_delete_action': 'Migrate & DELETE',
      'migrate_action': 'Migrate',
      'open_org': 'Open Organization',
      'view_org_info': 'View Organization Info',
      'org_details_and_id': 'Organization details and ID',
      'migrate_to_other_org': 'Migrate data to another organization',
      'copy_all_data': 'Copy all data to another organization',
      'migrate_and_delete_org': 'Migrate & delete organization',
      'transfer_and_delete': 'Transfer data and delete this organization',
      'delete_org_action': 'Delete Organization',
      'delete_org_permanently': 'Permanently delete organization and all data',
      'leave_org_action': 'Leave Organization',
      'will_lose_access': 'You will lose access',
      'confirm_logout': 'Confirm Logout',
      'confirm_logout_message': 'Are you sure you want to logout?',
      'window_size_too_small': 'Window size too small',
      'minimum_size': 'Minimum size: {{width}}x{{height}}',
      'current_size': 'Current: {{width}}x{{height}}',
      'user_data_not_found': 'User data not found',
      'logout_action': 'Logout',
      'org_options': 'Organization Options',
      'day_hint': 'Day',
      'month_hint': 'Month',
      'year_hint': 'Year',
      'select_from_calendar': 'Pick from calendar',
      'please_enter_date': 'Please enter a date',
      'date_must_be_between': 'Date must be between {{first}} and {{last}}',
      'buildings_tab': 'Buildings',
      'tenants_tab': 'Tenants',
      'payments_tab': 'Payments',
      'statistics_tab': 'Statistics',
      'members_tab': 'Members',
      'add_building': 'Add Building',
      'no_buildings': 'No buildings found',
      'edit': 'Edit',
      'delete': 'Delete',
      'manage_rooms': 'Manage Rooms',
      'created_at': 'Created',
      'no_payments': 'No payments yet',
      'add_payment': 'Add Payment',
      'add': 'Add',
      'search_payments': 'Search payments...',
      'found_payments': 'Found {{count}} payments',
      'tenant_label': 'Tenant',
      'amount_label': 'Amount',
      'due_date_label': 'Due',
      'view_details': 'View Details',
      'no_data': 'No data available',
      'overview': 'Overview',
      'total_buildings': 'Buildings',
      'total_tenants': 'Tenants',
      'paid_payments': 'Paid',
      'pending_payments_label': 'Pending',
      'overdue_payments': 'Overdue',
      'total_payments_label': 'Total Payments',
      'revenue': 'Revenue',
      'collected': 'Collected',
      'uncollected': 'Uncollected',
      'monthly_revenue': 'Monthly Revenue',
      'occupancy_by_building': 'Current Occupancy by Building',
      'occupancy_trend': 'Monthly Occupancy Trend',
      'export_excel': 'Export Excel',
      'export_pdf': 'Export PDF',
      'filter_by_building': 'Filter by building:',
      'all_buildings_option': 'All buildings',
      'select_building': 'Select building',
      'no_building_data': 'No building data yet',
      'occupancy_rate': 'Occupancy rate (%)',
      'no_building_data_selected': 'No data for this building yet',
      'get_invite_code': 'Get Invite Code',
      'refresh_code': 'Refresh Code',
      'refresh_invite_code_title': 'Refresh invite code?',
      'refresh_invite_code_body': 'The old invite code will no longer work. People who haven\'t joined yet will need the new code. Are you sure?',
      'refresh_action': 'Refresh',
      'code_refreshed': 'Invite code refreshed',
      'cannot_refresh_code': 'Cannot refresh invite code',
      'invite_code_label': 'Invite code',
      'members_title': 'Members',
      'no_members': 'No members found.',
      'promote_to_admin': 'Promote to Admin',
      'remove_from_org': 'Remove from organization',
      'confirm_remove': 'Confirm removal',
      'confirm_remove_body': 'Are you sure you want to remove {{name}} from the organization?',
      'member_removed': 'Member removed',
      'promoted_to_admin': 'Promoted to admin',
      'delete_building_title': 'Delete Building',
      'delete_building_confirm': 'Are you sure you want to delete "{{name}}"?',
      'delete_action_will': 'This action will:',
      'delete_all_rooms': 'Delete all rooms in the building',
      'mark_tenants_moved': 'Mark {{count}} tenants as "Moved Out"',
      'tenant_data_preserved': 'Tenant information will be preserved for reference',
      'add_building_success': 'Building added successfully',
      'add_building_rooms_success': 'Building and {{count}} rooms added successfully',
      'update_building_success': 'Building updated successfully',
      'update_building_rooms_success': 'Building updated and {{count}} rooms added successfully',
      'min_window_size': 'Window size too small',
      'downloading_update': 'Downloading update',
      'connecting': 'Connecting',

      // ── Organization Screen – Buildings tab ────────────────────────────────
      'delete_building_rooms_removed': 'rooms deleted',
      'delete_building_tenants_moved': 'tenants marked as "Moved Out"',
      'building_deleted_summary': 'Building deleted\n• {{rooms}} rooms deleted\n• {{tenants}} tenants marked as "Moved Out"',
      'cannot_delete_building': 'Cannot delete building',
      'delete_building_error': 'Error: {{error}}',
      'loading': 'Loading...',

      // ── Organization Screen – Payments tab ─────────────────────────────────
      'search_payments_hint': 'Search payments...',
      'no_payments_found': 'No payments found',
      'found_count_payments': 'Found {{count}} payments',
      'edit_payment': 'Edit',
      'delete_payment': 'Delete',
      'payment_type_rent': 'Rent',
      'payment_type_electricity': 'Electricity',
      'payment_type_water': 'Water',
      'payment_type_internet': 'Internet',
      'payment_type_parking': 'Parking',
      'payment_type_maintenance': 'Maintenance',
      'payment_type_deposit': 'Deposit',
      'payment_type_penalty': 'Penalty',
      'payment_type_other': 'Other',

      // ── Organization Screen – Statistics tab ───────────────────────────────
      'stat_overview_title': 'Overview',
      'stat_buildings': 'Buildings',
      'stat_tenants': 'Tenants',
      'stat_paid': 'Paid',
      'stat_pending': 'Pending',
      'stat_overdue': 'Overdue',
      'stat_total_payments': 'Total Payments',
      'stat_revenue_title': 'Revenue',
      'stat_collected': 'Collected',
      'stat_uncollected': 'Uncollected',
      'stat_monthly_revenue': 'Monthly Revenue',
      'stat_occupancy_by_building': 'Current Occupancy by Building',
      'stat_occupancy_trend': 'Monthly Occupancy Trend',
      'stat_no_revenue_data': 'No revenue data yet',
      'stat_no_building_data': 'No building data yet',
      'stat_no_building_selected': 'No data for this building yet',
      'stat_filter_by_building': 'Filter by building:',
      'stat_all_buildings': 'All buildings',
      'stat_select_building': 'Select building',
      'stat_occupancy_rate': 'Occupancy rate (%)',
      'stat_no_data': 'No data available',

      // ── Organization Screen – Members tab ──────────────────────────────────
      'member_role_admin': 'Admin',
      'member_role_member': 'Member',
      'member_promote_confirm_title': 'Promote to Admin',
      'member_promote_confirm_body': 'Are you sure you want to promote {{name}} to admin?',
      'member_remove_confirm_title': 'Confirm removal',
      'member_remove_confirm_body': 'Are you sure you want to remove {{name}} from the organization?',
      'member_promoted_success': 'Promoted to admin',
      'member_removed_success': 'Member removed',

      // ── PDF / Excel export ─────────────────────────────────────────────────
      'export_cancelled': 'PDF export cancelled',
      'export_pdf_saved': 'PDF saved: {{filename}}',
      'export_pdf_error': 'Error exporting PDF: {{error}}',
      'export_excel_saved': 'Excel saved: {{filename}}',
      'export_excel_success': 'Excel file created successfully',
      'export_excel_error': 'Error exporting Excel: {{error}}',
      // PDF report headings
      'pdf_report_title': 'STATISTICS REPORT',
      'pdf_created_at': 'Created: {{date}}',
      'pdf_section_overview': '1. OVERVIEW',
      'pdf_section_tenant_status': '2. TENANT STATUS',
      'pdf_section_payment_summary': '3. PAYMENT SUMMARY',
      'pdf_total_buildings': 'Buildings',
      'pdf_total_rooms': 'Total Rooms',
      'pdf_active_tenants': 'Rented',
      'pdf_occupancy_rate': 'Occupancy Rate',
      'pdf_empty_rooms': 'Empty Rooms',
      'pdf_moved_out': 'Moved Out',
      'pdf_tenant_status_active': 'Active',
      'pdf_tenant_status_inactive': 'Inactive',
      'pdf_tenant_status_moved': 'Moved Out',
      'pdf_tenant_status_suspended': 'Suspended',
      'pdf_tenant_status_total': 'TOTAL',
      'pdf_tenant_col_status': 'Status',
      'pdf_tenant_col_count': 'Count',
      'pdf_tenant_col_rate': 'Rate',
      'pdf_collected': 'Collected',
      'pdf_uncollected': 'Uncollected',
      'pdf_overdue': 'Overdue',
      'pdf_cancelled': 'Cancelled',
      'pdf_invoices': '{{count}} invoices',
      'pdf_auto_generated': 'Auto-generated report',
      'pdf_page': 'Page {{n}}',
      'pdf_building_detail_title': 'BUILDING DETAILS',
      'pdf_building_col_name': 'Building',
      'pdf_building_col_total': 'Total Rooms',
      'pdf_building_col_occupied': 'Occupied',
      'pdf_building_col_empty': 'Empty',
      'pdf_building_col_rate': 'Rate',
      'pdf_building_col_revenue': 'Revenue',
      'pdf_building_grand_total': 'GRAND TOTAL',
      'pdf_no_building_data': 'No building data available',
      'pdf_revenue_title': 'REVENUE ANALYSIS',
      'pdf_revenue_6months': 'Revenue – Last 6 Months',
      'pdf_revenue_detail': 'Monthly Revenue Breakdown',
      'pdf_revenue_col_month': 'Month',
      'pdf_revenue_col_amount': 'Revenue',
      'pdf_revenue_col_rate': 'Rate',
      // Excel sheet names & headings
      'excel_sheet_summary': 'Summary',
      'excel_sheet_building': 'Building Details',
      'excel_sheet_payments': 'Payment Details',
      'excel_summary_title': 'STATISTICS REPORT',
      'excel_building_title': 'BUILDING DETAILS',
      'excel_payments_title': 'DETAILED PAYMENT LIST',
      'excel_col_invoice_id': 'Invoice ID',
      'excel_col_tenant': 'Tenant',
      'excel_col_amount': 'Amount',
      'excel_col_status': 'Status',
      'excel_col_paid_date': 'Paid Date',
      'excel_col_due_date': 'Due Date',
      'excel_grand_total': 'GRAND TOTAL',
      'excel_created_at': 'Created: {{date}}',
      'excel_stat_buildings': 'Buildings',
      'excel_stat_rooms': 'Total Rooms',
      'excel_stat_rented': 'Rented',
      'excel_stat_occupancy': 'Occupancy Rate',
      'excel_stat_empty': 'Empty Rooms',
      'excel_stat_moved_out': 'Moved Out',

      // ── Building Dialog ───────────────────────────────────────────────────
      'building_dialog_title_add': 'Add Building',
      'building_dialog_title_edit': 'Edit Building',
 
      // Form fields
      'building_name_label': 'Building Name *',
      'building_name_hint': 'E.g.: Block A',
      'building_address_label': 'Address *',
      'building_address_hint': 'E.g.: 123 ABC Street',
      'building_auto_generate_rooms': 'Auto-generate rooms',
      'building_floors_label': 'Number of floors *',
      'building_room_prefix_label': 'Room number prefix',
 
      // Toggle buttons
      'building_uniform': 'Uniform',
      'building_custom': 'Custom',
 
      // Uniform section
      'building_rooms_per_floor_label': 'Rooms per floor',
      'building_room_type_label': 'Room type',
      'building_room_type_standard': 'Standard',
      'building_area_label': 'Area (m²)',
 
      // Custom / per-floor section
      'building_floor_config_title': 'Floor configuration',
      'building_bulk_edit': 'Bulk edit',
      'building_bulk_close': 'Close',
      'building_bulk_from_floor': 'From floor',
      'building_bulk_to_floor': 'To floor',
      'building_bulk_rooms': 'Rooms',
      'building_bulk_type': 'Type',
      'building_bulk_area': 'm²',
      'building_bulk_apply': 'Apply to all',
 
      // Floor row columns
      'building_col_count': 'Qty',
      'building_col_type': 'Type',
      'building_col_area': 'm²',
 
      // Custom room names dialog
      'building_set_room_names_tooltip': 'Set room names',
      'building_enter_room_count_first': 'Please enter the number of rooms first',
      'building_custom_names_title': 'Room names – Floor {{floor}}',
      'building_room_label': 'Room {{n}}',
      'building_room_name_hint': 'E.g.: VIP Room, Studio A...',
      'building_save': 'Save',
 
      // Action buttons
      'building_action_add': 'Add',
      'building_action_update': 'Update',
 
      // Validation errors
      'building_error_name_required': 'Please enter the building name',
      'building_error_address_required': 'Please enter the address',
      'building_error_floors_invalid': 'Please enter a valid number of floors',
      'building_error_floors_required': 'Please enter the number of floors',
      'building_error_floors_positive': 'Number of floors must be greater than 0',
      'building_error_rooms_invalid': 'Please enter a valid number of rooms per floor',
      'building_error_rooms_required': 'Please enter the number of rooms',
      'building_error_rooms_positive': 'Number of rooms must be greater than 0',

      // ── Tenants Tab ───────────────────────────────────────────────────────
 
      // General
      'tenant_no_data': 'No data available',
      'tenant_unknown': 'Unknown',
 
      // Search bar
      'tenant_search_hint': 'Search by name, phone, email, occupation...',
      'tenant_no_tenants': 'No tenants yet',
      'tenant_no_results': 'No results found',
      'tenant_try_other_keyword': 'Try a different keyword',
      'tenant_found_results': 'Found {{count}} results',
 
      // Add button
      'tenant_add_button': 'Add tenant',
 
      // Tenant card
      'tenant_main_tenant_badge': 'Primary tenant',
      'tenant_location_label': 'Location',
      'tenant_previous_location_label': 'Previous location',
      'tenant_location_value': '{{building}} – Room {{room}}',
      'tenant_status_label': 'Status:',
      'tenant_vehicle_count': '{{count}} vehicle(s)',
      'tenant_options_tooltip': 'Options',
 
      // Detail dialog – section headings
      'tenant_detail_location': 'Location',
      'tenant_detail_previous_location': 'Previous location',
      'tenant_detail_building': 'Building',
      'tenant_detail_room': 'Room',
      'tenant_detail_contact_section': 'Contact information',
      'tenant_detail_phone': 'Phone',
      'tenant_detail_email': 'Email',
      'tenant_detail_personal_section': 'Personal information',
      'tenant_detail_gender': 'Gender',
      'tenant_detail_national_id': 'ID / Passport',
      'tenant_detail_occupation': 'Occupation',
      'tenant_detail_workplace': 'Workplace',
      'tenant_detail_rental_section': 'Rental information',
      'tenant_detail_move_in_date': 'Move-in date',
      'tenant_detail_days_living': 'Days living',
      'tenant_detail_days_value': '{{days}} days',
      'tenant_detail_monthly_rent': 'Monthly rent',
      'tenant_detail_deposit': 'Deposit',
      'tenant_detail_apartment_type': 'Apartment type',
      'tenant_detail_area': 'Area',
      'tenant_detail_area_value': '{{area}} m²',
      'tenant_detail_moveout_section': 'Move-out information',
      'tenant_detail_move_out_date': 'Move-out date',
      'tenant_detail_duration': 'Duration',
      'tenant_detail_reason': 'Reason',
      'tenant_detail_notes': 'Notes',
      'tenant_detail_contract_section': 'Contract',
      'tenant_detail_contract_start': 'Start date',
      'tenant_detail_contract_end': 'End date',
      'tenant_detail_contract_end_date': 'Contract end date',
      'tenant_detail_contract_status': 'Contract status',
      'tenant_detail_early_termination': 'Early termination',
      'tenant_detail_end_label': 'End',
      'tenant_detail_days_early': '{{days}} days early',
      'tenant_detail_on_time': 'On schedule',
      'tenant_detail_remaining': 'Remaining',
      'tenant_detail_vehicles_section': 'Vehicles ({{count}})',
      'tenant_detail_history_section': 'Rental history ({{count}})',
      'tenant_detail_history_dates': 'From {{from}} to {{to}}',
      'tenant_detail_status': 'Status',
 
      // Options label
      'tenant_options_label': 'Options',
 
      // Options menu items
      'tenant_menu_view_detail': 'View details',
      'tenant_menu_edit': 'Edit information',
      'tenant_menu_move_room': 'Move room',
      'tenant_menu_move_out': 'Mark as moved out',
      'tenant_menu_vehicles': 'Manage vehicles',
      'tenant_menu_rental_history': 'Rental history',
      'tenant_menu_delete': 'Delete',
 
      // Vehicle management dialog
      'tenant_vehicle_manage_title': 'Manage vehicles',
      'tenant_vehicle_add_tooltip': 'Add vehicle',
      'tenant_vehicle_empty': 'No vehicles registered',
      'tenant_vehicle_added': 'Vehicle added',
      'tenant_vehicle_add_error': 'Error: Could not add vehicle',
      'tenant_vehicle_updated': 'Vehicle updated',
      'tenant_vehicle_parking_registered': 'Parking spot registered',
      'tenant_vehicle_parking_unregistered': 'Parking spot removed',
      'tenant_vehicle_deleted': 'Vehicle deleted',
      'tenant_vehicle_parking_spot': 'Parking: {{spot}}',
      'tenant_error': 'Error: {{error}}',
 
      // Vehicle popup menu
      'tenant_vehicle_menu_edit': 'Edit',
      'tenant_vehicle_menu_register_parking': 'Register parking spot',
      'tenant_vehicle_menu_unregister_parking': 'Remove parking spot',
      'tenant_vehicle_menu_delete': 'Delete',
 
      // Vehicle delete confirm dialog
      'tenant_vehicle_delete_title': 'Delete vehicle',
      'tenant_vehicle_delete_confirm': 'Delete vehicle {{plate}}?',
 
      // Add / Edit vehicle dialogs
      'tenant_vehicle_add_title': 'Add vehicle',
      'tenant_vehicle_edit_title': 'Edit vehicle',
      'tenant_vehicle_plate_label': 'License plate *',
      'tenant_vehicle_type_label': 'Vehicle type *',
      'tenant_vehicle_brand_label': 'Brand',
      'tenant_vehicle_model_label': 'Model',
      'tenant_vehicle_color_label': 'Color',
      'tenant_vehicle_color_hint': 'Black, White, Blue...',
      'tenant_vehicle_plate_required': 'Please enter the license plate',
      'tenant_vehicle_add_action': 'Add',
      'tenant_vehicle_save_action': 'Save',
 
      // Vehicle types
      'tenant_vehicle_motorcycle': 'Motorcycle',
      'tenant_vehicle_car': 'Car',
      'tenant_vehicle_bicycle': 'Bicycle',
      'tenant_vehicle_electric_bike': 'Electric bicycle',
      'tenant_vehicle_other': 'Other',
 
      // Parking spot dialog
      'tenant_parking_register_title': 'Register parking spot',
      'tenant_parking_spot_label': 'Parking spot location',
      'tenant_parking_spot_required': 'Please enter the spot location',
      'tenant_parking_register_action': 'Register',
 
      // Rental history dialog
      'tenant_rental_history_title': 'Rental history',
      'tenant_rental_history_empty': 'No rental history',
 
      // Edit tenant dialog
      'tenant_edit_title': 'Edit information',
      'tenant_edit_save': 'Save changes',
      'tenant_section_invoice_apt': 'Invoice & Apartment',
 
      // Shared field labels
      'tenant_field_name': 'Full name',
      'tenant_field_name_required': 'Full name *',
      'tenant_field_phone': 'Phone number',
      'tenant_field_phone_required': 'Phone number *',
      'tenant_field_email': 'Email',
      'tenant_field_national_id': 'ID / Passport',
      'tenant_field_occupation': 'Occupation',
      'tenant_field_workplace': 'Workplace',
      'tenant_field_rent': 'Rent',
      'tenant_field_rent_required': 'Monthly rent *',
      'tenant_field_apt_type': 'Apartment type',
      'tenant_field_area': 'Area',
      'tenant_field_move_in_date': 'Move-in date',
      'tenant_field_building': 'Building *',
      'tenant_field_room': 'Room *',
      'tenant_field_status': 'Status',
      'tenant_field_main_tenant': 'Primary tenant',
 
      // Status dropdown values
      'tenant_status_active': 'Active',
      'tenant_status_inactive': 'Suspended',
      'tenant_status_moved_out': 'Moved out',
 
      // Room dropdown labels
      'tenant_room_occupied': 'Room {{number}} (Occupied)',
      'tenant_room_vacant': 'Room {{number}} (Vacant)',
 
      // Add tenant dialog
      'tenant_add_title': 'Add Tenant',
      'tenant_add_action': 'Add',
 
      // Move room dialog
      'tenant_move_room_title': 'Move to new room',
      'tenant_move_room_building': 'Select building',
      'tenant_move_room_room': 'Select room',
      'tenant_move_room_confirm': 'Confirm move',
      'tenant_move_room_success': 'Room changed successfully',
      'tenant_move_room_error': 'Error: Could not change room',
 
      // Move out dialog
      'tenant_moveout_title': 'Mark as moved out',
      'tenant_moveout_confirm': 'Mark {{name}} as moved out?',
      'tenant_moveout_date_label': 'Move-out date',
      'tenant_moveout_reason_label': 'Reason',
      'tenant_moveout_reason_1': 'Moving out',
      'tenant_moveout_reason_2': 'Contract expired',
      'tenant_moveout_reason_3': 'Early contract termination',
      'tenant_moveout_reason_4': 'Contract violation',
      'tenant_moveout_reason_5': 'Other',
      'tenant_moveout_early_warning': 'Early termination by {{days}} days',
      'tenant_moveout_confirm_action': 'Confirm',
      'tenant_moveout_success': 'Marked as moved out',
      'tenant_moveout_failed': 'Failed',
 
      // Delete tenant
      'tenant_delete_title': 'Delete tenant',
      'tenant_delete_confirm': 'Are you sure you want to delete {{name}}? This action cannot be undone.',
      'tenant_delete_success': 'Deleted',
      'tenant_delete_failed': 'Delete failed',
    },
  };

  String text(String key) => _values[locale.languageCode]?[key] ?? key;
  String operator [](String key) => text(key);

  // Method to handle dynamic values with named parameters
  String textWithParams(String key, Map<String, dynamic> params) {
    String template = text(key);
    params.forEach((key, value) {
      template = template.replaceAll('{{$key}}', value.toString());
    });
    return template;
  }
}

// Delegate để Flutter nhận diện bộ từ điển này
class AppTranslationsDelegate extends LocalizationsDelegate<AppTranslations> {
  const AppTranslationsDelegate();

  @override
  bool isSupported(Locale locale) => ['vi', 'en'].contains(locale.languageCode);

  @override
  Future<AppTranslations> load(Locale locale) async => AppTranslations(locale);

  @override
  bool shouldReload(AppTranslationsDelegate old) => false;
}

extension DatePickerFormatting on AppTranslations {
  bool get isVietnamese => locale.languageCode == 'vi';

  // Returns the appropriate date format pattern
  String get dateFormat => isVietnamese ? 'dd/MM/yyyy' : 'MM/dd/yyyy';

  // Format a date in a readable way
  String formatLongDate(DateTime date) {
    if (isVietnamese) {
      return _formatVietnameseDate(date);
    } else {
      return _formatEnglishDate(date);
    }
  }

  String _formatVietnameseDate(DateTime date) {
    final weekdays = [
      'Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư',
      'Thứ năm', 'Thứ sáu', 'Thứ bảy',
    ];

    final weekday = weekdays[date.weekday % 7];
    return '$weekday, ngày ${date.day} tháng ${date.month} năm ${date.year}';
  }

  String _formatEnglishDate(DateTime date) {
    final weekdays = [
      'Sunday', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday',
    ];

    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final weekday = weekdays[date.weekday % 7];
    final day = date.day;
    final month = months[date.month - 1];
    final year = date.year;

    // Add ordinal suffix (st, nd, rd, th)
    String daySuffix;
    if (day >= 11 && day <= 13) {
      daySuffix = 'th';
    } else {
      switch (day % 10) {
        case 1: daySuffix = 'st'; break;
        case 2: daySuffix = 'nd'; break;
        case 3: daySuffix = 'rd'; break;
        default: daySuffix = 'th';
      }
    }

    return '$weekday, $month $day$daySuffix, $year';
  }
}


/* Usage Examples:
// Simple translation (no parameters)
Text(AppTranslations.of(context)['logout'])

// Translation with parameters
Text(
  AppTranslations.of(context).textWithParams(
    'leave_org_confirm',
    {'name': org.name}
  )
)
*/