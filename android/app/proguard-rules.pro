-keep class ai.onnxruntime.** { *; }

# google_mlkit_text_recognition exposes optional builders for scripts that are
# not bundled. Lectura uses the Latin recognizer for Romanian OCR.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
