import 'package:flutter/material.dart';
import '../../utils/localizations/app_localizations.dart';

// Shared wording for the operational replacement pages. Keep field labels visible
// above multiline inputs so enlarged text does not obscure values or errors.
String opsText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'history': ['Financial history', 'Lịch sử tài chính'],
    'before': ['Before', 'Trước'],
    'after': ['After', 'Sau'],
    'collect': ['Payment collected', 'Đã thu tiền'],
    'overridePrice': [
      'Custom total (optional)',
      'Tổng tiền tùy chỉnh (không bắt buộc)',
    ],
    'overrideReason': ['Reason for custom price', 'Lý do tùy chỉnh giá'],
    'days': ['days', 'ngày'],
    'charge': ['Other tenant charge', 'Khoản thu khác của khách'],
    'unitPrice': ['Unit price', 'Đơn giá'],
    'quantity': [
      'Quantity (up to 3 decimal places)',
      'Số lượng (tối đa 3 chữ số thập phân)',
    ],
    'electricity': ['Electricity', 'Tiền điện'],
    'water': ['Water', 'Tiền nước'],
    'internet': ['Internet', 'Internet'],
    'parking': ['Parking', 'Gửi xe'],
    'maintenance': ['Maintenance', 'Bảo trì'],
    'penalty': ['Penalty', 'Phạt'],
    'other': ['Other', 'Khác'],

    'invoices': [
      'Invoices and building expenses',
      'Hóa đơn và chi phí thuê tòa nhà',
    ],
    'propertyLayout': [
      'Property layout and room defaults',
      'Sơ đồ tòa nhà và mặc định phòng',
    ],
    'bookings': ['Manage bookings', 'Quản lý đặt phòng'],
    'back': ['Back', 'Quay lại'],
    'reload': ['Reload', 'Tải lại'],
    'save': ['Save', 'Lưu'],
    'review': ['Review calculation', 'Kiểm tra tính toán'],
    'confirm': ['Confirm and save', 'Xác nhận và lưu'],
    'retry': ['Retry identical request', 'Thử lại đúng yêu cầu'],
    'saved': ['Saved successfully.', 'Đã lưu thành công.'],
    'unavailable': [
      'Unavailable, changed, or access denied. Reload to check current data.',
      'Không thể truy cập, dữ liệu đã thay đổi hoặc không có quyền. Tải lại để kiểm tra.',
    ],
    'uncertain': [
      'No confirmed reply. Retry the same request before continuing.',
      'Chưa nhận được xác nhận. Thử lại đúng yêu cầu trước khi tiếp tục.',
    ],
    'required': ['Enter a valid value.', 'Nhập giá trị hợp lệ.'],
    'empty': ['No records.', 'Chưa có dữ liệu.'],
    'more': ['Load more', 'Tải thêm'],
    'create': ['Create new', 'Tạo mới'],
    'edit': ['Edit', 'Chỉnh sửa'],
    'reason': ['Reason / description', 'Lý do / mô tả'],
    'currency': ['Currency', 'Tiền tệ'],
    'amount': ['Amount', 'Số tiền'],
    'paid': ['Paid', 'Đã thanh toán'],
    'total': ['Total', 'Tổng cộng'],
    'status': ['Status', 'Trạng thái'],
    'income': ['Income', 'Thu'],
    'expense': ['Expense', 'Chi'],
    'tenantRent': ['Tenant rent', 'Tiền thuê của khách'],
    'buildingRent': ['Whole-building rent', 'Thuê nguyên tòa nhà'],
    'tenant': ['Tenant', 'Người thuê'],
    'start': ['Period start (YYYY-MM-DD)', 'Bắt đầu kỳ (YYYY-MM-DD)'],
    'end': [
      'Period end, excluded (YYYY-MM-DD)',
      'Kết thúc kỳ, không tính ngày này (YYYY-MM-DD)',
    ],
    'due': ['Due date (YYYY-MM-DD)', 'Ngày đến hạn (YYYY-MM-DD)'],
    'internetFee': ['Internet fee', 'Phí internet'],
    'cableTVFee': ['Cable TV fee', 'Phí truyền hình'],
    'hotWaterFee': ['Hot water fee', 'Phí nước nóng'],
    'lateFee': ['Late fee', 'Phí chậm trả'],
    'taxAmount': ['Tax', 'Thuế'],
    'invoiceHelp': [
      'Rent uses actual calendar days and saved rate changes. The end date is excluded. Review the server calculation before saving. Existing rent amounts stay fixed; edits change fees and due date. Refund all paid amounts before voiding.',
      'Tiền thuê tính theo ngày lịch thực tế và các lần đổi giá đã lưu. Không tính ngày kết thúc. Kiểm tra tính toán từ máy chủ trước khi lưu. Tiền thuê đã ghi giữ nguyên; chỉnh sửa phí và hạn thanh toán. Hoàn hết tiền đã thu trước khi hủy.',
    ],
    'void': ['Void invoice', 'Hủy hóa đơn'],
    'payExpense': ['Record expense payment', 'Ghi nhận thanh toán chi phí'],
    'reverseExpense': [
      'Reverse expense payment',
      'Hoàn lại thanh toán chi phí',
    ],
    'method': ['Payment method', 'Phương thức thanh toán'],
    'cash': ['Cash', 'Tiền mặt'],
    'bankTransfer': ['Bank transfer', 'Chuyển khoản'],
    'cancel': ['Cancel', 'Hủy'],
    'layoutHelp': [
      'These settings describe the building and suggest values for new rooms. Existing rooms, prices and bookings are unchanged. Enter one room count per floor, separated by commas.',
      'Các cài đặt mô tả tòa nhà và gợi ý giá trị cho phòng mới. Phòng, giá và đặt phòng hiện có không thay đổi. Nhập số phòng từng tầng, ngăn cách bằng dấu phẩy.',
    ],
    'floors': ['Number of floors', 'Số tầng'],
    'roomPrefix': ['Room prefix', 'Tiền tố phòng'],
    'roomType': ['Default room type', 'Loại phòng mặc định'],
    'roomArea': ['Default area (m²)', 'Diện tích mặc định (m²)'],
    'floorRoomCounts': ['Room counts by floor', 'Số phòng theo tầng'],
    'room': ['Room', 'Phòng'],
    'guest': ['Guest name', 'Tên khách'],
    'phone': ['Phone', 'Điện thoại'],
    'notes': ['Notes', 'Ghi chú'],
    'startLocal': [
      'Arrival (YYYY-MM-DD HH:mm)',
      'Nhận phòng (YYYY-MM-DD HH:mm)',
    ],
    'endLocal': [
      'Departure (YYYY-MM-DD HH:mm)',
      'Trả phòng (YYYY-MM-DD HH:mm)',
    ],
    'hourly': ['Hourly', 'Theo giờ'],
    'daily': ['Daily', 'Theo ngày'],
    'overnight': ['Overnight', 'Qua đêm'],
    'deposit': ['Collect deposit', 'Thu tiền cọc'],
    'depositAmount': ['Required deposit', 'Tiền cọc yêu cầu'],
    'payment': ['Collect booking payment', 'Thu tiền đặt phòng'],
    'refundRent': ['Refund booking payment', 'Hoàn tiền đặt phòng'],
    'refund': ['Refund deposit', 'Hoàn tiền cọc'],
    'checkout': [
      'Check out and collect remaining balance',
      'Trả phòng và thu số tiền còn lại',
    ],
    'confirmed': ['Confirm booking', 'Xác nhận đặt phòng'],
    'checkedIn': ['Check in', 'Nhận phòng'],
    'cancelled': ['Cancel booking', 'Hủy đặt phòng'],
    'noShow': ['Mark no-show', 'Đánh dấu không đến'],
    'occurrence': [
      'Repeated daylight-saving time',
      'Giờ bị lặp khi đổi giờ mùa hè',
    ],
    'first': ['First occurrence', 'Lần thứ nhất'],
    'second': ['Second occurrence', 'Lần thứ hai'],
    'bookingHelp': [
      'Enter times in the displayed property timezone. Rates are calculated by the server. Hourly prices use elapsed hours; daily and overnight prices charge each started 24-hour block. A configured daily threshold switches hourly pricing to daily.',
      'Nhập giờ theo múi giờ tòa nhà hiển thị. Máy chủ tính giá. Giá giờ theo thời lượng thực tế; giá ngày và qua đêm tính mỗi chu kỳ 24 giờ đã bắt đầu. Ngưỡng ngày đã cài đặt chuyển giá giờ sang giá ngày.',
    ],
    'reviewWarning': [
      'Review this action before confirming. Financial and history records are retained.',
      'Kiểm tra thao tác trước khi xác nhận. Dữ liệu tài chính và lịch sử được giữ lại.',
    ],
  };
  return labels[key]?[vi ? 1 : 0] ?? key;
}

Widget opsField(
  BuildContext context,
  String key,
  TextEditingController controller, {
  required bool enabled,
  String? label,
  bool required = true,
}) => Padding(
  padding: const EdgeInsets.only(top: 16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label ?? opsText(context, key)),
      const SizedBox(height: 8),
      Semantics(
        label: label ?? opsText(context, key),
        child: TextFormField(
          key: ValueKey('ops-$key'),
          controller: controller,
          enabled: enabled,
          maxLines: null,
          decoration: const InputDecoration(errorMaxLines: 8),
          validator: (v) => required && (v ?? '').trim().isEmpty
              ? opsText(context, 'required')
              : null,
        ),
      ),
    ],
  ),
);
Widget opsPage(BuildContext context, List<Widget> children) => SafeArea(
  child: Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  ),
);

int? operationalMoney(String text, String currency) {
  final value = text.trim().replaceAll(',', '.');
  if (!RegExp(
    currency == 'USD' ? r'^\d+(?:\.\d{1,2})?$' : r'^\d+$',
  ).hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null) return null;
  final minor =
      whole * (currency == 'USD' ? 100 : 1) +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return minor <= 1000000000000 ? minor : null;
}
