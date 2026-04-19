import 'package:flutter/material.dart';

// Centralized theme constants for the app
const Color kPrimaryColor = Color(0xFF2D6A4F);
const Color kBackgroundColor = Color(0xFFF0F4F1);
const Color kAccentColor = Color(0xFF0077B6);
const Color kInfoColor = Color(0xFF48CAE4);
const Color kDangerColor = Color(0xFFE63946);

const double kCardRadius = 20.0;

final ThemeData appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: kPrimaryColor),
  scaffoldBackgroundColor: kBackgroundColor,
  useMaterial3: false,
);
