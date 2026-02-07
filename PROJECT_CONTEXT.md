# Project Context

## Purpose
This is a Flutter fitness training app focused on:
- Workout logging
- Fatigue tracking
- Muscle heatmap visualization
- Training progression analysis

## Tech Stack
- Flutter
- Firebase Auth
- Firestore
- Flutter Web + Android

## Core Rules (DO NOT BREAK)
- Never duplicate workout logs
- Never recalculate fatigue unless explicitly requested
- Preserve historical data integrity
- UI changes must not affect domain logic

## Architecture
- lib/models → domain models
- lib/services → business logic (timers, fatigue, audio)
- lib/screens → UI
- Avoid tight coupling between screens and services

## Critical Files
- fatigue_recalculation_service.dart
- tabata_timer_service.dart
- muscle_catalog.dart

Changes to these files must be minimal and justified.
