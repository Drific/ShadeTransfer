// lib/constants/charset.dart

class Charset {
  Charset._();

  static const String digits = '23456789';
  static const String lower = 'abcdefghjkmnpqrstuvwxyz';
  static const String upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

  static const String all = digits + lower + upper;
  static const int base = all.length; // 55

  static bool isValid(String c) => all.contains(c);
  static int indexOf(String c) => all.indexOf(c);
  static String charAt(int i) => all[i];
}
