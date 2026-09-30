/// Basic email shape shared by forms, the same rule the server uses.
/// Allows plus addresses (name+tag@gmail.com) and long domain endings
/// (.company, .travel). Only delivery really proves an address.
final RegExp emailFormat = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String value) => emailFormat.hasMatch(value.trim());
