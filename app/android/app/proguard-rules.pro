# Release builds shrink and rename code (R8). The Flutter Gradle plugin picks
# this file up on its own.

# Razorpay Checkout (razorpay_flutter → com.razorpay:checkout). Its checkout
# runs in a WebView that calls back into these classes by name, so R8 must
# not rename or drop them — Razorpay's own published rules.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
