/// Matches the backend phone format without normalizing or rewriting input.
String? validateRegistrationPhone(String? value) {
  if (value == null || !RegExp(r'^\+?[1-9]\d{9,14}$').hasMatch(value.trim())) {
    return 'Enter 10 digits or +91 followed by 10 digits, without spaces or hyphens.';
  }
  return null;
}
