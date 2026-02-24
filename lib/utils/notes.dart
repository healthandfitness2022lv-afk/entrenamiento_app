/// ======================================================
/// LOAD MODEL REFACTOR NOTES
/// ======================================================
///
/// Problema:
/// - Volumen actual es absoluto (weight × reps).
/// - No considera intensidad relativa.
/// - No normaliza entre ejercicios con y sin 1RM.
///
/// Idea futura:
/// - Modelo híbrido.
/// - Relative volume para lifts principales.
/// - RPE-based intensity para accesorios.
/// - Unified Load = volume × intensityIndex.
///
/// Integración:
/// - FatigueService
/// - WeeklyLoadScreen
/// - RMService
///
/// Estado: pendiente.
/// ======================================================
