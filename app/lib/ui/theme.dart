import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// L0ck palette — the original L0ck-ECP prototype's colours, shared with the L0ck web site.
abstract final class L0ckColors {
  static const bg = Color(0xFF0A0C09);
  static const panel = Color(0xFF111410);
  static const widget = Color(0xFF161A13);
  static const border = Color(0xFF2D4A1E);
  static const greenDark = Color(0xFF3B6D11);
  static const green = Color(0xFF5A8A2E);
  static const greenLight = Color(0xFF8FAF6A);
  static const orange = Color(0xFFEF9F27);
  static const text = Color(0xFFC8D4B8);
  static const data = Color(0xFFD4E8B0);
  // Brighter than the original 5A7A3A: 4.5:1+ on panels, readable outdoors
  static const dim = Color(0xFF7A9A58);
  static const red = Color(0xFFE24B4A);

  // Channel states
  static const ok = Color(0xFF22C55E);
  static const amber = Color(0xFFF59E0B);
  static const off = Color(0xFF6B7280);
}

/// Small uppercase label with wide spacing, as in the original app's panels.
const labelStyle = TextStyle(
    color: L0ckColors.dim, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 2);

ThemeData l0ckTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: L0ckColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: L0ckColors.green,
        secondary: L0ckColors.orange,
        surface: L0ckColors.panel,
        error: L0ckColors.red,
        onSurface: L0ckColors.text,
      ),
      fontFamily: 'monospace', // system font only: no runtime font downloads
      appBarTheme: const AppBarTheme(
        backgroundColor: L0ckColors.panel,
        foregroundColor: L0ckColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: L0ckColors.border, width: 0.5)),
        titleTextStyle: TextStyle(
            fontFamily: 'monospace',
            color: L0ckColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 2),
      ),
      dividerColor: L0ckColors.border,
      listTileTheme: const ListTileThemeData(iconColor: L0ckColors.greenLight),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: L0ckColors.widget,
        contentTextStyle: TextStyle(color: L0ckColors.text, fontFamily: 'monospace'),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: L0ckColors.greenLight,
          side: const BorderSide(color: L0ckColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: L0ckColors.greenLight),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: L0ckColors.border)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: L0ckColors.greenLight)),
        labelStyle: TextStyle(color: L0ckColors.greenLight),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: L0ckColors.greenDark,
          foregroundColor: L0ckColors.text,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: L0ckColors.green),
          ),
          textStyle: const TextStyle(
              fontFamily: 'monospace', fontWeight: FontWeight.w600, letterSpacing: 2),
        ),
      ),
    );

/// A PIN field that keeps the keyboard from learning or suggesting what is typed.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.label,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: true,
        keyboardType: TextInputType.number,
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        maxLength: 12,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: ''),
        onSubmitted: onSubmitted,
      );
}
