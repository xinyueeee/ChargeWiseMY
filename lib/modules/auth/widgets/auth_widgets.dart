import 'package:flutter/material.dart';

const _labelColor = Color(0xFF1F2937);
const _hintColor = Color(0xFF9AA5B1);
const _primaryGreen = Color(0xFF00B894);

/// Branded header shown at the top of the auth screens, consistent across
/// login and register so both feel like the same flow.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenSize.width * 0.75,
            maxHeight: screenSize.height * 0.3,
          ),
          child: Image.asset(
            'assets/images/login_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _labelColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _hintColor, fontSize: 13),
        ),
      ],
    );
  }
}

/// Field with a label above it (matches the rest of the app's forms, e.g.
/// the "Record Charging Session" screen), rather than a floating label.
class AuthLabeledField extends StatelessWidget {
  const AuthLabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.required = true,
    this.hintText,
    this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final String? hintText;
  final IconData? prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: _labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            children: required
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: Colors.red),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, color: _primaryGreen, size: 20),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
